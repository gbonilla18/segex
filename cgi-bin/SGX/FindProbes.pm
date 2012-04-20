package SGX::FindProbes;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;

require SGX::DBLists;
require Tie::IxHash;
require SGX::Abstract::JSEmitter;
use SGX::Abstract::Exception ();
use SGX::Util qw/car cdr trim min bind_csv_handle distinct file_opts_html
  dec2indexes32 locationAsTextToCanon coord2int/;
use SGX::Debug;
use SGX::Config qw/$IMAGES_DIR $YUI_BUILD_ROOT/;

#---------------------------------------------------------------------------
#  Parsers for lists of IDs/symbols
#---------------------------------------------------------------------------
my %parser = (
    'Probe IDs' => sub {

        # Regular expression for the first column (probe/reporter id) reads as
        # follows: from beginning to end, match any character other than [space,
        # forward/back slash, comma, equal or pound sign, opening or closing
        # parentheses, double quotation mark] from 1 to 18 times.
        my $x = shift;
        if ( $x =~ m/^([^\s,\/\\=#()"]{1,18})$/ ) {
            return $1;
        }
        else {
            SGX::Exception::User->throw(
                error => "Invalid probe ID $x on line " . shift );
        }
    },
    'Genes/Accession Nos.' => sub {
        my $x = shift;
        if ( $x =~ /^([^\+\s]+)$/ ) {
            return $1;
        }
        else {
            SGX::Exception::User->throw(
                error => "Invalid gene symbol $x on line " . shift );
        }
    },
    'GO IDs' => sub {
        my $x = shift;
        if ( $x =~ /^(?:GO\:|)(\d+)$/ ) {
            return $1;
        }
        else {
            SGX::Exception::User->throw(
                error => "Invalid GO accession number $x on line " . shift );
        }
    }
);

#---------------------------------------------------------------------------
#  When creating temporary lists in MySQL, use the types below
#---------------------------------------------------------------------------
my %sqlTypes = (
    'Probe IDs'            => 'char(18) NOT NULL',
    'Genes/Accession Nos.' => 'char(32) NOT NULL',
    'GO IDs'               => 'int(10) unsigned'
);
my %sqlNames = (
    'Probe IDs'            => 'reporter',
    'Genes/Accession Nos.' => 'gsymbol',
    'GO IDs'               => 'go_acc'
);

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Initialize parts that deal with responding to CGI queries
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my $self = shift;
    $self->SUPER::init();

    $self->set_attributes( _title => 'Find Probes' );
    $self->register_actions(
        'Search' => { head => 'Search_head', body => 'Search_body' },
        'Search GO terms' => { body => 'SearchGO_body' },
        'Get CSV'         => { head => 'GetCSV_head' }
    );
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  default_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_head {
    my $self = shift;
    my ( $js_src_yui, $js_src_code, $css_src_yui, $css_src_code ) =
      @$self{qw{_js_src_yui _js_src_code _css_src_yui _css_src_code}};

    push @$css_src_yui,
      (
        'button/assets/skins/sam/button.css',
        'tabview/assets/skins/sam/tabview.css'
      );

    # background image from: http://subtlepatterns.com/?p=703
    push @$css_src_code, +{ -code => <<END_css};
.yui-skin-sam .yui-navset .yui-content { 
    background-image:url('$IMAGES_DIR/fancy_deboss.png'); 
}
END_css

    push @$js_src_yui,
      (
        'yahoo-dom-event/yahoo-dom-event.js', 'element/element-min.js',
        'button/button-min.js',               'tabview/tabview-min.js'
      );
    push @$js_src_code, +{ -code => <<"END_onload"};
var tabView = new YAHOO.widget.TabView('property_editor');
YAHOO.util.Event.addListener(window, 'load', function() {
    selectTabFromHash(tabView);
});
END_onload

    $self->getSessionOverrideCGI();
    push @$js_src_code,
      ( { -src => 'collapsible.js' }, { -src => 'FormFindProbes.js' } );

    $self->{_species_data} = $self->get_species();
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  get_species
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_species {
    my $self = shift;
    my $dbh  = $self->{_dbh};
    my $sth  = $dbh->prepare('SELECT sid, sname FROM species ORDER BY sname');
    my $rc   = $sth->execute();
    my $data = $sth->fetchall_arrayref();
    $sth->finish;

    my %data;
    my $data_t = tie(
        %data, 'Tie::IxHash',
        '' => '@All Species',
        map { shift @$_ => shift @$_ } @$data
    );
    return \%data;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  GetCSV_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub GetCSV_head {
    my $self = shift;
    my $q    = $self->{_cgi};
    $self->getSessionOverrideCGI();

    $self->{_SeachParams} = {
        query_text => car( $q->param('q_old') ),
        scope      => car( $q->param('scope_old') ),
        match      => car( $q->param('match_old') )
    };
    $self->{_UserSession}->commit();

    my $search_terms =
      [ distinct( split( /[,\s]+/, trim( car $q->param('q') ) ) ) ];
    my $exp_hash  = $self->getReportExperiments($search_terms);
    my $data_hash = $self->getReportData($search_terms);
    $self->{_DataForCSV} = [ $exp_hash, $data_hash ];
    $self->printFindProbeCSV();
    exit;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  Search_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub Search_head {
    my $self = shift;

    $self->getSessionOverrideCGI();
    my $next_action = $self->FindProbes_init();

    if ( !$next_action ) {
        $self->set_action('');
        $self->default_head();
        return 1;
    }

    my ( $s, $js_src_yui, $js_src_code ) =
      @$self{qw{_UserSession _js_src_yui _js_src_code}};

    push @{ $self->{_css_src_yui} },
      (
        'paginator/assets/skins/sam/paginator.css',
        'datatable/assets/skins/sam/datatable.css',
        'container/assets/skins/sam/container.css'
      );
    push @$js_src_yui,
      (
        'yahoo-dom-event/yahoo-dom-event.js', 'dragdrop/dragdrop-min.js',
        'container/container-min.js',         'element/element-min.js',
        'datasource/datasource-min.js',       'paginator/paginator-min.js',
        'datatable/datatable-min.js',         'selector/selector-min.js'
      );

    if ( $next_action == 1 ) {
        my $jscode;
        $self->safe_execute(
            sub {
                $jscode = $self->findProbes_js( $self->xTableQuery() );
            },
            "Could not execute query. Database response was: %s"
        );
        push @$js_src_code,
          ( { -code => $jscode }, { -src => 'FindProbes.js' } );
    }
    elsif ( $next_action == 2 ) {
        $self->getGOTerms();
        push @$js_src_code,
          ( { -code => $self->goTerms_js() }, { -src => 'GoTerms.js' } );
        $self->set_action('Search GO terms');
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  goTerms_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub goTerms_js {
    my $self = shift;
    my $q    = $self->{_cgi};
    my $data = $self->{_GoTerms} || [];

    my $rowcount = scalar(@$data);
    my $caption  = sprintf( 'Found %d GO %s',
        $rowcount, $self->pluralize_noun( 'term', $rowcount ) );

    my %json_probelist = (
        caption => $caption,
        records => $data,
        headers => $self->{_GoTerms_Names}
    );

    my ( $scope, $match ) = @$self{qw/_scope _match/};
    my $js = SGX::Abstract::JSEmitter->new( pretty => 0 );
    return ''
      . $js->let(
        [
            queryText  => $self->{_QueryText},
            match      => $match,
            scope      => $scope,
            url_prefix => $q->url( -absolute => 1 ),
            project_id => $self->{_WorkingProject},
            data       => \%json_probelist
        ],
        declare => 1
      );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  build_SearchPredicateGO
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub build_SearchPredicateGO {
    my $self  = shift;
    my $match = $self->{_match};

    my $params           = [];
    my $predicate        = [];
    my %translate_fields = (
        'GO Names'       => ['go_name'],
        'GO Names/Desc.' => [ 'go_name', 'go_term_definition' ]
    );
    my $scope = $self->{_scope};
    my $type  = $translate_fields{$scope};
    SGX::Exception::Internal->throw("Unrecognized search scope \"$scope\"\n")
      if not defined $type;

    if ( $match eq 'Full-Word' ) {

        # not searching for any symbols here so no need to check existence of
        # parser key.
        $predicate = [
            sprintf( 'MATCH (%s) AGAINST (? IN BOOLEAN MODE)',
                join( ',', @$type ) )
        ];
        $params = [ $self->{_QueryText} ];
        $self->{_QueryTextProc} = $params;
    }
    elsif ( $match eq 'Prefix' ) {
        my @items = split( /[,\s]+/, $self->{_QueryText} );
        $self->{_QueryTextProc} = \@items;
        ( $predicate => $params ) = @items
          ? (
            [ join( ' OR ', map { "$_ REGEXP ?" } @$type ) ] => [
                map {
                    join( '|', map { "[[:<:]]$_" } @items )
                  } @$type
            ]
          )
          : ( [] => [] );
    }
    elsif ( $match eq 'Partial' ) {
        my @items = split( /[,\s]+/, $self->{_QueryText} );
        $self->{_QueryTextProc} = \@items;
        ( $predicate => $params ) =
          @items
          ? ( [ join( ' OR ', map { "$_ REGEXP ?" } @$type ) ] =>
              [ map { join( '|', @items ) } @$type ] )
          : ( [] => [] );
    }
    else {
        SGX::Exception::Internal->throw(
            error => "Invalid match value $match\n" );
    }

    if ( @$predicate == 0 ) {
        push @$predicate, map { "$_ IN (NULL)" } @$type;
    }
    my $predicate_sql = 'WHERE ' . join( ' AND ', @$predicate );

    # returns tuple of SQL string + reference to query parameters
    return ( $predicate_sql, $params );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  getGOTerms
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getGOTerms {
    my $self = shift;
    my $dbh  = $self->{_dbh};

    my $query_text = $self->{_QueryText};
    my $scope      = $self->{_scope};
    my $match      = $self->{_match};

    my @fields =
        ( $scope eq 'GO Names' )
      ? ('go_name')
      : ( 'go_name', 'go_term_definition' );
    my $relevance =
      ( $match eq 'Full-Word' )
      ? sprintf( ',MATCH (%s) AGAINST (?) AS relevance', join( ',', @fields ) )
      : '';
    my @param_relevance = ( $match eq 'Full-Word' ) ? ($query_text) : ();
    my ( $predicate, $param ) = $self->build_SearchPredicateGO();

    #---------------------------------------------------------------------------
    # only return results for platforms that belong to the current working
    # project (as determined through looking up studies linked to the current
    # project).
    #---------------------------------------------------------------------------
    #    my $curr_proj             = $self->{_WorkingProject};
    #    my $sql_subset_by_project = '';
    #    if ( defined($curr_proj) && $curr_proj ne '' ) {
    #        $curr_proj             = $dbh->quote($curr_proj);
    #        $sql_subset_by_project = <<"END_sql_subset_by_project"
    #INNER JOIN probe    ON ProbeGene.rid=probe.rid
    #INNER JOIN study    ON study.pid=probe.pid
    #INNER JOIN ProjectStudy ON prid=$curr_proj AND ProjectStudy.stid=study.stid
    #END_sql_subset_by_project
    #    }

    #---------------------------------------------------------------------------
    #  chromosomal location limits
    #---------------------------------------------------------------------------
    my ( $limit_sql, $limit_param ) = $self->build_location_predparam();
    $limit_sql =
      (@$limit_param)
      ? "INNER JOIN probe USING(rid) $limit_sql"
      : '';

    #---------------------------------------------------------------------------
    #  query itself
    #---------------------------------------------------------------------------
    my $order_by =
      ( $match eq 'Full-Word' )
      ? 'ORDER BY relevance DESC'
      : 'ORDER BY Probes DESC';

    my $sql = <<"END_query1";
SELECT
    go_acc                        AS 'GO Acc. No.',
    go_name                       AS 'Term Name and Description',
    go_term_definition            AS 'Go Term Def.',
    go_term_type                  AS 'Term Type',
    count(distinct ProbeGene.rid) AS 'Probes'
FROM (
    SELECT go_acc, go_name, go_term_definition, go_term_type $relevance
    FROM go_term 
    $predicate
) AS search_result
INNER JOIN GeneGO    USING(go_acc)
INNER JOIN ProbeGene USING(gid)
$limit_sql
GROUP BY go_acc
$order_by
END_query1

    my $sth   = $dbh->prepare($sql);
    my $rc    = $sth->execute( @param_relevance, @$param, @$limit_param );
    my @names = @{ $sth->{NAME} };
    my $data  = $sth->fetchall_arrayref();
    $sth->finish();
    $self->{_GoTerms}       = $data;
    $self->{_GoTerms_Names} = \@names;
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  FindProbes_init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub FindProbes_init {
    my $self = shift;

    #---------------------------------------------------------------------------
    #  initialization code (moved from new() constructor)
    #---------------------------------------------------------------------------
    $self->set_attributes( _dbLists => SGX::DBLists->new( delegate => $self ) );

    my $q = $self->{_cgi};

    my $action        = car $q->param('b');
    my $text          = trim( car $q->param('q') );
    my $filefield_val = car $q->param('file');
    my $upload_file   = defined($filefield_val) && ( $filefield_val ne '' );

    $self->{_QueryText} = $text;

    #---------------------------------------------------------------------------
    #  scope to search and chromosomal range if any
    #---------------------------------------------------------------------------
    my $scope;
    if ($upload_file) {
        $scope = car $q->param('scope_file');
    }
    else {
        $scope              = car $q->param('scope');
        $self->{_loc_spid}  = car $q->param('spid');
        $self->{_loc_pid}   = car $q->param('pid');
        $self->{_loc_chr}   = car $q->param('chr');
        $self->{_loc_start} = coord2int( car $q->param('start') );
        $self->{_loc_end}   = coord2int( car $q->param('end') );
    }
    $self->{_scope} = $scope;

    if (
           $text eq ''
        && !$upload_file
        && (   !( defined( $self->{_loc_spid} ) and $self->{_loc_spid} ne '' )
            && !( defined( $self->{_loc_pid} ) and $self->{_loc_pid} ne '' ) )
      )
    {
        $self->add_message( { -class => 'error' },
            'No search criteria specified' );
        return;
    }

    #---------------------------------------------------------------------------
    #  pattern match type
    #---------------------------------------------------------------------------
    my $match = car $q->param('match');
    $match = 'Full-Word'
      if $upload_file
          || !defined($match)
          || ( $scope eq 'Probe IDs' or $scope eq 'GO IDs' );
    $self->{_match} = $match;

    $self->{_extra_fields} =
      defined( $q->param('extra_fields') )
      ? 2
      : 1;

    $self->{_graphs} =
      defined( $q->param('show_graphs') )
      ? car( $q->param('graph_type') )
      : '';

    #---------------------------------------------------------------------------
    #Split on spaces or commas. For Full-Word matches, emulate the treatment in
    #build_SearchPredicate.
    #---------------------------------------------------------------------------
    my @textSplit;
    if ( $match eq 'Full-Word' ) {
        if ( my $p = $parser{$scope} ) {
            $text =~ s/^\W*//;
            $text =~ s/\W*$//;
            @textSplit = map { $p->($_) } split( /[^\w:]+/, $text );
        }
        else {
            @textSplit = split( /[,\s]+/, $text );
        }
    }
    else {
        @textSplit = split( /[,\s]+/, $text );
    }

    #---------------------------------------------------------------------------
    #  special action for GO terms
    #---------------------------------------------------------------------------
    if ( $scope eq 'GO Names' or $scope eq 'GO Names/Desc.' ) {
        return 2;
    }

    #---------------------------------------------------------------------------
    #  do not create temporary table if no file uploaded or if <=1 term(s)
    #  entered or if terms are not symbols or if match type is not full word.
    #---------------------------------------------------------------------------
    return 1
      if !$upload_file
          and (  @textSplit < 2
              or !exists $parser{$scope}
              or $match ne 'Full-Word' );

    #----------------------------------------------------------------------
    #  More than one terms entered and matching is exact.
    #  Try to load file if uploading a file.
    #----------------------------------------------------------------------
    my $outputFileName;

    if ($upload_file) {
        require SGX::CSV;
        my ( $outputFileNames, $recordsValid ) =
          SGX::CSV::sanitizeUploadWithMessages(
            $self, 'file',
            csv_in_opts => { quote_char => undef },
            parser      => [ $parser{$scope} ]
          );
        $outputFileName = $outputFileNames->[0];
    }

    #----------------------------------------------------------------------
    #  now load into temporary table
    #----------------------------------------------------------------------
    my $dbLists = $self->{_dbLists};
    $self->{_TempTable} =
      ( defined $outputFileName )
      ? $dbLists->uploadFileToTemp(
        filename  => $outputFileName,
        name_type => [ $sqlNames{$scope}, $sqlTypes{$scope} ]
      )
      : $dbLists->createTempList(
        items     => \@textSplit,
        name_type => [ $sqlNames{$scope}, $sqlTypes{$scope} ]
      );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  getSessionOverrideCGI
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Gets full user name from session and full project name from CGI
#                parameters or session in that order. Also sets project id.
#       THROWS:  SGX::Exception::Internal, Class::Exception::DBI
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getSessionOverrideCGI {
    my ($self) = @_;
    my ( $dbh, $q, $s ) = @$self{qw{_dbh _cgi _UserSession}};

    # For user name, just look it up from the session
    $self->{_UserFullName} =
      ( defined $s )
      ? $s->{session_cookie}->{full_name}
      : '';

    # :TRICKY:06/28/2011 13:47:09:es: We implement the following behavior: if,
    # in the URI option string, "proj" is set to some value (e.g. "proj=32") or
    # to an empty string (e.g. "proj="), we set the data field _WorkingProject
    # to that value; if the "proj" option is missing from the URI, we use the
    # value of "curr_proj" from session data. This allows us to have all
    # portions of the data accessible via a REST-style interface regardless of
    # current user preferences.
    if ( defined( my $cgi_proj = $q->param('proj') ) ) {
        $self->{_WorkingProject} = $cgi_proj;
        if ( $cgi_proj ne '' ) {

            # now need to obtain project name from the database
            my $sth =
              $dbh->prepare(qq{SELECT prname FROM project WHERE prid=?});
            my $rc = $sth->execute($cgi_proj);
            if ( $rc == 1 ) {

                # project exists in the database
                $self->{_WorkingProject} = $cgi_proj;
                ( $self->{_WorkingProjectName} ) = $sth->fetchrow_array;
            }
            elsif ( $rc < 1 ) {

                # project doesn't exist in the database
                $self->{_WorkingProject}     = '';
                $self->{_WorkingProjectName} = '';
            }
            else {
                SGX::Exception::Internal->throw( error =>
"More than one result returned where unique was expected\n"
                );
            }
            $sth->finish;
        }
        else {
            $self->{_WorkingProjectName} = '';
        }
    }
    elsif ( defined $s ) {
        $self->{_WorkingProject}     = $s->{session_cookie}->{curr_proj};
        $self->{_WorkingProjectName} = $s->{session_cookie}->{proj_name};
    }
    else {
        $self->{_WorkingProject}     = '';
        $self->{_WorkingProjectName} = '';
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  build_SearchPredicate
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub build_SearchPredicate {
    my $self  = shift;
    my $match = $self->{_match};

    my $params           = [];
    my $predicate        = [];
    my %translate_fields = (
        'GO IDs'               => ['go_acc'],
        'Probe IDs'            => ['reporter'],
        'Genes/Accession Nos.' => ['gsymbol'],
        'Gene Names/Desc.'     => [ 'gsymbol', 'gname', 'gdesc' ]
    );
    my $scope = $self->{_scope};
    my $type  = $translate_fields{$scope};
    SGX::Exception::Internal->throw("Unrecognized search scope \"$scope\"\n")
      if not defined $type;

    if ( $match eq 'Full-Word' ) {
        if ( my $p = $parser{$scope} ) {

            # Symbols or IDs, entered whole: split on non-word characters
            # excluding colons (colons are used inside GO:0001234-like IDs).
            my $queryText = $self->{_QueryText};
            $queryText =~ s/^\W*//;
            $queryText =~ s/\W*$//;
            my @items = map { $p->($_) } split( /[^\w:]+/, $queryText );
            $self->{_QueryTextProc} = \@items;

            ( $predicate => $params ) = @items
              ? (
                [
                    join(
                        ' OR ',
                        map {
                            "$_ IN ("
                              . join( ',', map { '?' } @items ) . ')'
                          } @$type
                    )
                ] => [ map { @items } @$type ]
              )
              : ( [] => [] );
        }
        elsif ( $self->{_QueryText} ne '' ) {

           # MySQL full-text search
           # # :TODO:03/19/2012 00:22:42:es: Have a problem here: 1- to 3-letter
           # words are not indexed by full-text search in MySQL. A possible
           # solution is to search for short words using REGEXP matching,
           # however would have to deal with special situations such as
           # quotation marks or plus and minus characters.
            $predicate = [
                sprintf( 'MATCH (%s) AGAINST (? IN BOOLEAN MODE)',
                    join( ',', @$type ) )
            ];
            $params = [ $self->{_QueryText} ];
            $self->{_QueryTextProc} = $params;
        }
        else {
            ( $predicate => $params ) = ( [] => [] );
            $self->{_QueryTextProc} = $params;
        }
    }
    elsif ( $match eq 'Prefix' ) {
        my @items = split( /[,\s]+/, $self->{_QueryText} );
        $self->{_QueryTextProc} = \@items;
        ( $predicate => $params ) = @items
          ? (
            [ join( ' OR ', map { "$_ REGEXP ?" } @$type ) ] => [
                map {
                    join( '|', map { "[[:<:]]$_" } @items )
                  } @$type
            ]
          )
          : ( [] => [] );
    }
    elsif ( $match eq 'Partial' ) {
        my @items = split( /[,\s]+/, $self->{_QueryText} );
        $self->{_QueryTextProc} = \@items;
        ( $predicate => $params ) =
          @items
          ? ( [ join( ' OR ', map { "$_ REGEXP ?" } @$type ) ] =>
              [ map { join( '|', @items ) } @$type ] )
          : ( [] => [] );
    }
    else {
        SGX::Exception::Internal->throw(
            error => "Invalid match value $match\n" );
    }

    if ( @$predicate == 0 ) {
        push @$predicate, map { "$_ IN (NULL)" } @$type;
    }
    my $predicate_sql = 'WHERE ' . join( ' AND ', @$predicate );

    # returns tuple of SQL string + reference to query parameters
    return ( $predicate_sql, $params );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  build_location_predparam
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub build_location_predparam {
    my $self = shift;

    my $query = 'INNER JOIN platform ON probe.pid=platform.pid';
    my @param;

    #---------------------------------------------------------------------------
    #  Filter by platform
    #---------------------------------------------------------------------------
    my $loc_pid = $self->{_loc_pid};
    if ( defined $loc_pid and $loc_pid ne '' ) {
        $query .= ' AND platform.pid=?';
        push @param, $loc_pid;
    }

    #---------------------------------------------------------------------------
    # Filter by chromosomal location
    #---------------------------------------------------------------------------
    my $loc_spid = $self->{_loc_spid};
    if ( defined $loc_spid and $loc_spid ne '' ) {
        $query .= ' AND platform.sid=?';
        push @param, $loc_spid;
    }

    #---------------------------------------------------------------------------
    #  For location, we need either platform or species id
    #---------------------------------------------------------------------------
    if (   ( defined $loc_pid and $loc_pid ne '' )
        || ( defined $loc_spid and $loc_spid ne '' ) )
    {

   # where Intersects(LineString(Point(0,93160788), Point(0,103160849)), locus);
   # chromosome is meaningless unless species or platform was specified.
        my $loc_chr = $self->{_loc_chr};
        if ( defined $loc_chr and $loc_chr ne '' ) {
            $query .=
              ' INNER JOIN locus ON probe.rid=locus.rid AND locus.chr=?';
            push @param, $loc_chr;

            # starting and ending interval positions are meaningless if no
            # chromosome was specified.
            my $loc_start = $self->{_loc_start};
            my $loc_end   = $self->{_loc_end};
            if ( defined($loc_start) && defined($loc_end) ) {
                $query .=
' AND Intersects(LineString(Point(0,?), Point(0,?)), zinterval)';
                push @param, ( $loc_start, $loc_end );
            }
        }
    }
    return ( $query, \@param );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  getReportExperiments
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getReportExperiments {
    my $self         = shift;
    my $search_terms = shift;
    my $dbh          = $self->{_dbh};

    #---------------------------------------------------------------------------
    #  in one query, get all platforms
    #---------------------------------------------------------------------------
    my $platform_sql =
      'SELECT pid, sname, pname from platform LEFT JOIN species using(sid)';
    my $platform_sth = $dbh->prepare($platform_sql);
    $platform_sth->execute();
    my %platform_hash;
    while ( my @row = $platform_sth->fetchrow_array() ) {
        my $pid = shift @row;
        $platform_hash{$pid} = { attr => \@row };
    }
    $platform_sth->finish();

    #---------------------------------------------------------------------------
    # in another query, get attributes for all experiments in which the probes
    # are found
    #---------------------------------------------------------------------------
    $self->{_dbLists} ||= SGX::DBLists->new( delegate => $self );
    my $exp_temp_table = $self->{_dbLists}->createTempList(
        items     => $search_terms,
        name_type => [ 'rid', 'int(10) unsigned' ]
    );
    my $exp_sql = <<"END_ExperimentDataQuery";
SELECT
    experiment.pid,
    experiment.eid                                         AS 'Exp. ID', 
    PValFlag,
    GROUP_CONCAT(DISTINCT study.description SEPARATOR ',') AS 'Study(ies)',
    CONCAT(experiment.sample2, ' / ', experiment.sample1)  AS 'Exp. Name',
    experiment.ExperimentDescription                       AS 'Exp. Description'
FROM $exp_temp_table AS tmp
INNER JOIN microarray USING(rid)
INNER JOIN experiment USING(eid)
LEFT JOIN StudyExperiment USING(eid)
LEFT JOIN study USING(stid)
GROUP BY experiment.eid
ORDER BY experiment.eid ASC
END_ExperimentDataQuery
    my $exp_sth = $dbh->prepare($exp_sql);
    $exp_sth->execute();
    my @exp_names = @{ $exp_sth->{NAME} };
    shift @exp_names;
    shift @exp_names;
    shift @exp_names;

    #---------------------------------------------------------------------------
    #  Once we have platforms, add platform/species info to experiment hash
    #  At this point, the experiment hash values will look like this:
    #
    #  pid => {
    #   attr => [
    #     0) pname
    #     1) sname
    #   ],
    #   exp => [[
    #      0) eid
    #      1) study_desc
    #      2) exp_name
    #      3) exp_desc
    #      4) pvalflag
    #      5) platform name
    #      6) species name
    #   ]]
    #  };
    #---------------------------------------------------------------------------
    while ( my @row = $exp_sth->fetchrow_array() ) {
        my $pid      = shift @row;
        my $eid      = shift @row;
        my $platform = $platform_hash{$pid};
        if ( my $experiments = $platform->{exp} ) {
            $experiments->{$eid} = \@row;
        }
        else {
            $platform->{exp} = { $eid => \@row };
        }
    }
    $exp_sth->finish();

    # delete those platform ids for which no experiments were found
    my @pids_no_eids =
      grep { !defined( $platform_hash{$_}->{exp} ) } keys %platform_hash;
    delete @platform_hash{@pids_no_eids};

    return { data => \%platform_hash, headers => { exp => \@exp_names } };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  getReportData
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getReportData {
    my $self         = shift;
    my $search_terms = shift;
    my $dbh          = $self->{_dbh};
    my $dbLists      = $self->{_dbLists};

    #---------------------------------------------------------------------------
    #  in another, get all annotation
    #---------------------------------------------------------------------------
    my $annot_temp_table = $dbLists->createTempList(
        items     => $search_terms,
        name_type => [ 'rid', 'int(10) unsigned' ]
    );
    my $annot_sql = <<"END_ExperimentDataQuery";
SELECT
    probe.rid,
    probe.pid,
    probe.reporter AS 'Probe ID',
    probe.probe_sequence AS 'Probe Sequence',
    GROUP_CONCAT(DISTINCT CONCAT(locus.chr, ':', AsText(locus.zinterval)) separator ' ') AS 'Locus',
    GROUP_CONCAT(DISTINCT if(gene.gtype=0, gene.gsymbol, NULL) separator ', ') AS 'Accession No.',
    GROUP_CONCAT(DISTINCT if(gene.gtype=1, gene.gsymbol, NULL) separator ', ') AS 'Gene',
    GROUP_CONCAT(DISTINCT concat(gene.gname, if(isnull(gene.gdesc), '', concat(', ', gene.gdesc))) separator '; ') AS 'Gene Name/Desc.'

FROM $annot_temp_table AS tmp
INNER JOIN probe USING(rid)
LEFT JOIN locus USING(rid)
LEFT JOIN ProbeGene USING(rid)
LEFT JOIN gene USING(gid)
GROUP BY probe.rid
END_ExperimentDataQuery

    my $annot_sth = $dbh->prepare($annot_sql);
    $annot_sth->execute();
    my @annot_names = @{ $annot_sth->{NAME} };
    shift @annot_names;
    shift @annot_names;

    #---------------------------------------------------------------------------
    #  Translate location data at column with zero-based index 3
    #---------------------------------------------------------------------------
    my %annot_hash;
    while ( my @row = $annot_sth->fetchrow_array() ) {
        my $rid = shift @row;
        $row[3] = locationAsTextToCanon( $row[3] );
        $annot_hash{$rid} = { annot => \@row };
    }
    $annot_sth->finish();

    #---------------------------------------------------------------------------
    #  in yet another, get data
    #---------------------------------------------------------------------------
    my $data_temp_table = $dbLists->createTempList(
        items     => $search_terms,
        name_type => [ 'rid', 'int(10) unsigned' ]
    );
    my $data_sql = <<"END_ExperimentDataQuery";
SELECT
    rid,
    eid,
    ratio       AS 'Ratio',
    foldchange  AS 'Fold Change',
    intensity1  AS 'Intensity-1',
    intensity2  AS 'Intensity-2',
    pvalue1     AS 'P-Value 1',
    pvalue2     AS 'P-Value 2',
    pvalue3     AS 'P-Value 3',
    pvalue4     AS 'P-Value 4'
FROM $data_temp_table AS tmp
INNER JOIN microarray USING(rid)
END_ExperimentDataQuery
    my $data_sth = $dbh->prepare($data_sql);
    $data_sth->execute();
    my @data_names = @{ $data_sth->{NAME} };
    shift @data_names;

    while ( my @row = $data_sth->fetchrow_array ) {
        my $rid        = shift @row;
        my $probe_info = $annot_hash{$rid};
        if ( my $experiments = $probe_info->{exp} ) {
            push @$experiments, \@row;
        }
        else {
            $probe_info->{exp} = [ \@row ];
        }
    }
    $data_sth->finish();

    #---------------------------------------------------------------------------
    # pid => [{
    #    annot => [
    #       reporter,
    #       acc_num,
    #       gene,
    #       probe_seq,
    #       gene_name
    #    ],
    #    exp => [[
    #       eid,
    #       ratio,
    #       foldchange,
    #       intensity1,
    #       intensity2,
    #       pvalue1,
    #       pvalue2,
    #       pvalue3,
    #       pvalue4
    #    ]]
    # }]
    #---------------------------------------------------------------------------
    my %reconf_hash;
    foreach my $val ( values %annot_hash ) {
        my $pid = shift @{ $val->{annot} };
        if ( my $reconf_memb = $reconf_hash{$pid} ) {
            push @$reconf_memb, $val;
        }
        else {
            $reconf_hash{$pid} = [$val];
        }
    }
    return {
        data    => \%reconf_hash,
        headers => {
            annot => \@annot_names,
            exp   => \@data_names
        }
    };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  printFindProbeCSV
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Print the data from the hashes into a CSV file.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub printFindProbeCSV {
    my $self = shift;

    #Clear our headers so all we get back is the CSV file.
    my ( $q, $s ) = @$self{qw/_cgi _UserSession/};
    my ( $exp_hash_base, $data_hash_base ) = @{ $self->{_DataForCSV} };
    my $exp_hash  = $exp_hash_base->{data};
    my $data_hash = $data_hash_base->{data};

    $s->commit() if defined $s;
    print $q->header(
        -type       => 'text/csv',
        -attachment => 'results.csv',
        -cookie     => ( ( defined $s ) ? $s->cookie_array() : [] )
    );

    my $print = bind_csv_handle( \*STDOUT );

    # Report Header
    my $search_params = $self->{_SeachParams};
    my @queryItems = split( /[,\s]+/, $search_params->{query_text} );
    $print->( [ 'Find Probes Report', scalar localtime() ] );
    $print->( [ 'Generated By',       $self->{_UserFullName} ] );
    $print->( [ 'Working Project',    $self->{_WorkingProjectName} ] );
    $print->(
        [
            'Query',
            (
                $search_params->{scope} eq 'GO IDs'
                ? join(
                    ' ', map { 'GO:' . sprintf( '%07d', $_ ) } @queryItems
                  )
                : join( ' ', @queryItems )
            )
        ]
    );
    $print->( [ 'Scope',            $search_params->{scope} ] );
    $print->( [ 'Patterns Matched', $search_params->{match} ] );
    $print->();

    my $exp_head_headers =
      [ 'Exp. ID', @{ $exp_hash_base->{headers}->{exp} || [] } ];
    my $annot_headers = $data_hash_base->{headers}->{annot} || [];
    my $exp_headers   = $data_hash_base->{headers}->{exp}   || [];

    # always show these data fields:
    # 1: ratio, 2: foldchange, 3: intensity1, 4: intensity2
    my @always_show = 1 .. 4;
    my $offset      = $always_show[$#always_show] + 1;

    while ( my ( $pid, $obj ) = each %$exp_hash ) {

        # print platform header
        $print->( $obj->{attr} );
        $print->();

        # print headers for experiment head
        $print->($exp_head_headers);

        # Indexes:
        # 1: ratio, 2: foldchange, 3: intensity1, 4: intensity2, 5: p-value1...
        my $experiments = $obj->{exp} || {};
        my @sorted_eids = sort { $a <=> $b } keys %$experiments;
        my %eid2array = map {
            $_ => [
                @always_show,
                map { $offset + $_ }
                  dec2indexes32( shift @{ $experiments->{$_} } )
              ]
        } @sorted_eids;

        # print experiments sorted by ID
        $print->( [ $_, @{ $experiments->{$_} } ] ) for @sorted_eids;

        # now print experiment headers horizontally
        $print->(
            [
                ( map { '' } @$annot_headers ),
                map {
                    $experiments->{$_}->[1],
                      map { '' }
                      @$exp_headers[ cdr( @{ $eid2array{$_} } ) ]
                  } @sorted_eids
            ]
        );

        # print headers for annotation + experiments data
        $print->(
            [
                @$annot_headers,
                map {
                    my $eid = $_;
                    map { "$eid: $_" } @$exp_headers[ @{ $eid2array{$eid} } ]
                  } @sorted_eids
            ]
        );

        # print annotation + experiment data per probe
        my $platform_data = $data_hash->{$pid};
        foreach my $row (@$platform_data) {
            my $annot = $row->{annot};
            my $exp   = $row->{exp};
            $print->(
                [
                    @$annot,
                    map { my $eid = $_->[0]; @$_[ @{ $eid2array{$eid} } ] }
                      sort { $a->[0] <=> $b->[0] } @$exp
                ]
            );
        }
        $print->();
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  xTableQuery
#   PARAMETERS:  $type - query type (probe|gene)
#                tmp_table => $tmpTable - uploaded table to join on
#      RETURNS:  true value
#  DESCRIPTION:  Fills _InsideTableQuery field
#       THROWS:  SGX::Exception::User
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub xTableQuery {
    my $self      = shift;
    my $dbh       = $self->{_dbh};
    my $tmp_table = $self->{_TempTable};
    my $haveTable = ( defined($tmp_table) and ( $tmp_table ne '' ) );

    my @param;

    #---------------------------------------------------------------------------
    #  innermost SELECT statement differs depending on whether we are searching
    #  the probe table or the gene table
    #---------------------------------------------------------------------------
    my $innerSQL;

    my $scope = $self->{_scope};
    if ($haveTable) {
        if ( $scope eq 'Probe IDs' ) {
            $innerSQL = <<"END_table_probe";
SELECT rid, gid FROM probe 
INNER JOIN $tmp_table USING(reporter)
LEFT JOIN ProbeGene USING(rid)
END_table_probe
        }
        elsif ( $scope eq 'GO IDs' ) {
            $innerSQL = <<"END_table_go";
SELECT rid, gid
FROM ProbeGene
INNER JOIN (
    SELECT DISTINCT rid FROM ProbeGene 
    INNER JOIN GeneGO USING(gid) 
    INNER JOIN $tmp_table USING(go_acc)
) AS d1 USING(rid)
END_table_go
        }
        else {
            $innerSQL = <<"END_table_gene";
SELECT rid, gid
FROM ProbeGene
INNER JOIN (
    SELECT DISTINCT rid FROM ProbeGene 
    INNER JOIN gene USING(gid) 
    INNER JOIN $tmp_table USING(gsymbol) 
) AS d1 USING(rid)
END_table_gene
        }
        $self->{_QueryTextProc} = [ split( /[,\s]+/, $self->{_QueryText} ) ];
    }
    else {
        my ( $pred_sql, $pred_param ) = $self->build_SearchPredicate();
        push @param, @$pred_param;
        if ( $scope eq 'Probe IDs' ) {
            $innerSQL = <<"END_no_table_probe";
SELECT rid, gid 
FROM
    (SELECT rid FROM probe $pred_sql) AS search_result
LEFT JOIN ProbeGene USING(rid)
END_no_table_probe
        }
        elsif ( $scope eq 'GO IDs' ) {
            $innerSQL = <<"END_no_table_go";
SELECT rid, gid
FROM ProbeGene
INNER join (
    SELECT DISTINCT rid FROM
        (SELECT DISTINCT gid from GeneGO $pred_sql) AS search_result
    INNER JOIN ProbeGene USING(gid)
) AS d1 USING(rid)
END_no_table_go
        }
        else {
            $innerSQL = <<"END_no_table_gene";
SELECT rid, gid
FROM ProbeGene
INNER join (
    SELECT DISTINCT rid FROM
        (SELECT gid FROM gene $pred_sql) AS search_result
    INNER JOIN ProbeGene USING(gid)
) AS d1 USING(rid)
END_no_table_gene
        }
    }

    #---------------------------------------------------------------------------
    # Filter by chromosomal location (use platform table to look up species when
    # only species is specified and not an actual chromosomal location).
    #---------------------------------------------------------------------------
    my ( $limit_sql, $limit_param ) = $self->build_location_predparam();
    push @param, @$limit_param;

    #---------------------------------------------------------------------------
    # only return results for platforms that belong to the current working
    # project (as determined through looking up studies linked to the current
    # project).
    #---------------------------------------------------------------------------
    my $sql_subset_by_project = '';
    my $curr_proj             = $self->{_WorkingProject};
    if ( defined($curr_proj) && $curr_proj ne '' ) {
        $sql_subset_by_project = <<"END_sql_subset_by_project";
INNER JOIN study ON study.pid=platform.pid
INNER JOIN ProjectStudy ON prid=? AND ProjectStudy.stid=study.stid
END_sql_subset_by_project
        push @param, $curr_proj;
    }

    #---------------------------------------------------------------------------
    #  fields to select:
    #  $extra_fields == 0: rid
    #  $extra_fields == 1: rid, pid, reporter, sname, pname, accnum, gene
    #  $extra_fields == 2: rid, pid, reporter, sname, pname, accnum, gene,
    #                      probe_seq, gene_name
    #---------------------------------------------------------------------------
    my $extra_fields  = $self->{_extra_fields};
    my @select_fields = ('probe.rid');
    if ( $extra_fields > 0 ) {
        push @select_fields,
          (
            'platform.pid',
            "probe.reporter  AS 'Probe ID'",
            "species.sname   AS 'Species'",
            "species.slatin  AS 'Species Official Name'",
            "platform.pname  AS 'Platform'",
"group_concat(distinct if(gene.gtype=0, gene.gsymbol, NULL) separator ', ') AS 'Accession No.'",
"group_concat(distinct if(gene.gtype=1, gene.gsymbol, NULL) separator ', ') AS 'Gene'",
          );
    }
    if ( $extra_fields > 1 ) {
        push @select_fields,
          (
            "probe.probe_sequence AS 'Probe Sequence'",
"GROUP_CONCAT(DISTINCT CONCAT(locus.chr, ':', AsText(locus.zinterval)) separator '; ') AS 'Locus'",
"group_concat(distinct concat(gene.gname, if(isnull(gene.gdesc), '', concat(', ', gene.gdesc))) separator '; ') AS 'Gene Name/Desc.'"
          );
        if ( !defined( $self->{_loc_chr} ) ) {

            # do a left join on locus (note that if _loc_chr is defined then
            # we are already joining the locus table anyway
            $limit_sql .= ' LEFT JOIN locus ON probe.rid=locus.rid';
        }
    }
    my $selectFieldsSQL = join( ',', @select_fields );

    #---------------------------------------------------------------------------
    #  inner query -- allow for plain dump if location is specified but no
    #  search terms entered.
    #
    #  TODO: if uploading a file, only return info for probes uploaded?
    #---------------------------------------------------------------------------

    $innerSQL =
      ( ( !$haveTable ) and $self->{_QueryText} eq '' )
      ? ''
      : <<"END_innerSQL";
INNER JOIN (
    SELECT DISTINCT COALESCE(ProbeGene.rid, d2.rid) AS rid
    FROM ($innerSQL) AS d2
    LEFT join ProbeGene USING(gid)
) AS d3 on probe.rid=d3.rid
END_innerSQL

    #---------------------------------------------------------------------------
    #  main query
    #---------------------------------------------------------------------------
    my $sql = <<"END_XTableQuery";
SELECT
$selectFieldsSQL
FROM probe
$innerSQL
LEFT join ProbeGene ON probe.rid=ProbeGene.rid
LEFT join gene ON gene.gid=ProbeGene.gid
$limit_sql
LEFT JOIN species ON species.sid=platform.sid
$sql_subset_by_project
group by probe.rid
END_XTableQuery

    my $sth = $dbh->prepare($sql);
    my $rc  = $sth->execute(@param);

    # :TRICKY:07/24/2011 12:27:32:es: accessing NAME array will fail if is done
    # after any data were fetched.
    my @headers = @{ $sth->{NAME} };
    my $data    = $sth->fetchall_arrayref;

    # return tuple of headers + data array reference
    return ( \@headers, $data );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  findProbes_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub findProbes_js {
    my $self = shift;

    my $headers = shift;
    my $records = shift;

    #---------------------------------------------------------------------------
    #  HTML output
    #---------------------------------------------------------------------------
    my $rowcount = @{ $records || [] };

    my $proj_name = $self->{_WorkingProjectName};
    my $caption   = sprintf(
        '%sFound %d related %s',
        (
            ( defined($proj_name) && $proj_name ne '' )
            ? "$proj_name: "
            : ''
        ),
        $rowcount,
        $self->pluralize_noun( 'probe', $rowcount )
    );

    my %json_probelist = (
        caption => $caption,
        records => $records,
        headers => $headers
    );

    my ( $scope, $match ) = @$self{qw/_scope _match/};
    my $js = SGX::Abstract::JSEmitter->new( pretty => 0 );
    return ''
      . $js->let(
        [
            queryText    => $self->{_QueryText},
            match        => $match,
            scope        => $scope,
            show_graphs  => $self->{_graphs},
            extra_fields => $self->{_extra_fields},
            project_id   => $self->{_WorkingProject},
            data         => \%json_probelist
        ],
        declare => 1
      );
}

#===  FUNCTION  ================================================================
#         NAME:  SearchGO_body
#      PURPOSE:  display results table for Find Probes
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub SearchGO_body {
    my $self = shift;
    my %args = @_;
    my $q    = $self->{_cgi};

    my $extra_fields = $args{extra_fields} || [];
    my $action_a = $args{action_a}
      || $q->url( absolute => 1 ) . '?a=findProbes';
    my $action_b = $args{action_b} || 'Search';

    my $type  = $self->{_scope} || '';
    my $match = $self->{_match} || '';

    my @actions = (
        $q->a(
            {
                -id    => 'resulttable_selectall',
                -title => 'Get probes for all GO accession numbers below'
            },
            'Select all'
        ),
        $q->a(
            {
                -id    => 'resulttable_astext',
                -title => 'Present data in this table in tab-delimited format'
            },
            'View as plain text'
        )
    );

    my $textToShow = (
        $self->{_scope} eq 'GO IDs'
        ? join( ', ',
            map { 'GO:' . sprintf( '%07d', $_ ) } @{ $self->{_QueryTextProc} } )
        : join( ', ', @{ $self->{_QueryTextProc} } )
    );

    my @ret = (
        $q->h2( { -id => 'caption' }, '' ),
        $q->p(
            { -id => 'subcaption' },
            sprintf( '%s search on %s', $self->{_match}, $self->{_scope}, )
              . ": $textToShow"
        ),
        $q->start_form(
            -id      => 'main_form',
            -method  => 'POST',
            -action  => $action_a,
            -enctype => 'application/x-www-form-urlencoded'
        ),
        $q->dl(
            $q->dt('Get probes for selected GO terms below:'),
            $q->dd(
                $q->hidden(
                    -id   => 'q',
                    -name => 'q'
                ),
                $q->hidden(
                    -name  => 'scope',
                    -value => 'GO IDs'
                ),
                $q->hidden(
                    -name  => 'match',
                    -value => 'Full-Word'
                ),
                (
                    ( $self->{_loc_spid} || $self->{_loc_pid} )
                    ? (
                        (
                            $self->{_loc_spid}
                            ? $q->hidden(
                                -name  => 'spid',
                                -value => $self->{_loc_spid}
                              )
                            : ()
                        ),
                        (
                            $self->{_loc_pid}
                            ? $q->hidden(
                                -name  => 'pid',
                                -value => $self->{_loc_pid}
                              )
                            : ()
                        ),
                        $q->hidden(
                            -name  => 'chr',
                            -value => $self->{_loc_chr}
                        ),
                        $q->hidden(
                            -name  => 'start',
                            -value => $self->{_loc_start}
                        ),
                        $q->hidden(
                            -name  => 'end',
                            -value => $self->{_loc_end}
                        )
                      )
                    : ()
                ),
                (
                    $self->{_extra_fields} > 1
                    ? $q->hidden(
                        -name  => 'extra_fields',
                        -value => 'on'
                      )
                    : ()
                ),
                @$extra_fields,
                $q->submit(
                    -class => 'button black bigrounded',
                    -name  => 'b',
                    -value => $action_b,
                    -title => 'Get related probes for GO terms below'
                )
            )
        ),
        $q->endform,
        $q->start_form(
            -id      => 'get_csv',
            -method  => 'POST',
            -action  => $q->url( absolute => 1 ) . '?a=findProbes',
            -enctype => 'application/x-www-form-urlencoded'
        ),
        join( $q->span( { -class => 'separator' }, ' / ' ), @actions ),
        $q->endform,
        $q->div( { -id => 'resulttable' }, '' )
    );
    return @ret;
}

#===  FUNCTION  ================================================================
#         NAME:  Search_body
#      PURPOSE:  display results table for Find Probes
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub Search_body {
    my $self = shift;

    my $q     = $self->{_cgi};
    my $type  = $self->{_scope} || '';
    my $match = $self->{_match} || '';

    my @actions = (
        $q->span(
            $q->hidden(
                -id    => 'q',
                -name  => 'q',
                -value => ''
            ),
            $q->hidden(
                -id    => 'q_old',
                -name  => 'q_old',
                -value => ''
            ),
            $q->hidden(
                -id    => 'scope_old',
                -name  => 'scope_old',
                -value => ''
            ),
            $q->hidden(
                -id    => 'match_old',
                -name  => 'match_old',
                -value => ''
            ),
            $q->submit(
                -class => 'plaintext',
                -name  => 'b',
                -value => 'Get CSV',
                -title => 'Get CSV report for these probes'
            )
        ),
        $q->a(
            {
                -id    => 'resulttable_astext',
                -title => 'Present data in this table in tab-delimited format'
            },
            'View as plain text'
        )
    );

    my $textToShow = (
        $self->{_scope} eq 'GO IDs'
        ? join( ', ',
            map { 'GO:' . sprintf( '%07d', $_ ) } @{ $self->{_QueryTextProc} } )
        : join( ', ', @{ $self->{_QueryTextProc} } )
    );

    my @ret = (
        $q->h2( { -id => 'caption' }, '' ),
        $q->p(
            { -id => 'subcaption' },
            sprintf( '%s search on %s', $self->{_match}, $self->{_scope}, )
              . ": $textToShow"
        ),
        $q->start_form(
            -id      => 'get_csv',
            -method  => 'POST',
            -action  => $q->url( absolute => 1 ) . '?a=findProbes',
            -enctype => 'application/x-www-form-urlencoded'
        ),
        join( $q->span( { -class => 'separator' }, ' / ' ), @actions ),
        $q->endform,
        $q->div( { -id => 'resulttable' }, '' )
    );

    if ( $self->{_graphs} ) {
        push @ret, (
            $q->p(<<"END_LEGEND"),
<strong>Dark bars</strong>: values meething the P threshold. 
<strong>Light bars</strong>: values above the P threshold. 
<strong>Green horizontal lines</strong>: fold-change threshold.
END_LEGEND
            $q->div( { -id => 'graphs' }, '' ),
            $q->p( $q->a( { -href => '#' }, '^ Back to top' ) )
        );
    }

    return @ret;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  mainFormDD
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub mainFormDD {
    my $self         = shift;
    my %args         = @_;
    my $species_data = $args{species_hash};
    my $q            = $self->{_cgi};

    return $q->div(
        { -id => 'property_editor', -class => 'yui-navset' },
        $q->ul(
            { -class => 'yui-nav' },
            $q->li(
                { -class => 'selected' },
                $q->a( { -href => "#terms" }, $q->em('Enter List') )
            ),
            $q->li( $q->a( { -href => "#upload" }, $q->em('Upload File') ) )
        ),
        $q->div(
            { -class => 'yui-content' },
            $q->div(
                $q->div(
                    { -id => 'terms' },
                    $q->p(
                        $q->textarea(
                            -name    => 'q',
                            -id      => 'q',
                            -rows    => 4,
                            -columns => 55,
                            -title =>
'Enter list of terms to search. Multiple entries have to be separated by commas or be on separate lines.'
                        )
                    )
                ),
                $q->div(
                    {
                        -id    => 'scope_container',
                        -class => 'input_container'
                    },
                    $q->input(
                        {
                            -type  => 'radio',
                            -name  => 'scope',
                            -value => 'Probe IDs',
                            -title => 'Look up probe IDs'
                        }
                    ),
                    $q->input(
                        {
                            -type    => 'radio',
                            -name    => 'scope',
                            -value   => 'Genes/Accession Nos.',
                            -checked => 'checked',
                            -title   => 'Look up gene symbols'
                        }
                    ),
                    $q->input(
                        {
                            -type  => 'radio',
                            -name  => 'scope',
                            -value => 'GO IDs',
                            -title => 'Look up GO IDs'
                        }
                    ),
                    $q->br(),
                    $q->input(
                        {
                            -type  => 'radio',
                            -name  => 'scope',
                            -value => 'Gene Names/Desc.',
                            -title => 'Search gene names'
                        }
                    ),
                    $q->input(
                        {
                            -type  => 'radio',
                            -name  => 'scope',
                            -value => 'GO Names',
                            -title => 'Search gene ontology term names'
                        }
                    ),
                    $q->input(
                        {
                            -type  => 'radio',
                            -name  => 'scope',
                            -value => 'GO Names/Desc.',
                            -title =>
                              'Search gene ontology term names + descriptions'
                        }
                    ),

                    # preserve state of radio buttons
                    $q->input(
                        {
                            -type => 'hidden',
                            -id   => 'scope_state'
                        }
                    )
                ),
                $q->p(
                    $q->a(
                        {
                            -id    => 'advanced',
                            -class => 'pluscol',
                            -title => 'Click to expand for more options'
                        },
                        '+ Advanced'
                    )
                ),
                $q->ul(
                    {
                        -id    => 'advanced_container',
                        -class => 'dd_collapsible'
                    },
                    $q->li(
                        { -id => 'pattern_div' },
                        $q->p(
                            $q->div(
                                'Search pattern: ',
                                $q->radio_group(
                                    -name => 'match',
                                    -values =>
                                      [ 'Full-Word', 'Prefix', 'Partial' ],
                                    -default    => 'Full-Word',
                                    -attributes => {
                                        'Full-Word' => {
                                            id    => 'full_word',
                                            title => 'Match full words'
                                        },
                                        'Prefix' => {
                                            id    => 'prefix',
                                            title => 'Match word prefixes'
                                        },
                                        'Partial' => {
                                            id => 'partial',
                                            title =>
'Match word fragments, regular expressions'
                                        }
                                    }
                                )
                            ),
                            $q->div(
                                {
                                    -class => 'hint',
                                    -id    => 'pattern_fullword_hint'
                                },
                                <<"END_EXAMPLE_TEXT"),
In 
<a target="_blank" title="Click for more info on full-word searching" href="http://dev.mysql.com/doc/refman/5.5/en/fulltext-boolean.html">full-word mode</a>
in this scope, the phrase
<span class="unbreakable-term">"brain development"</span> will match exactly,
<span class="unbreakable-term">brain -development</span> will match "brain" but not "development", 
<span class="unbreakable-term">+brain +development</span> will match both words
in any order, and <span class="unbreakable-term">brain development</span> 
will match any of the two words.
END_EXAMPLE_TEXT
                            $q->div(
                                {
                                    -class => 'hint',
                                    -id    => 'pattern_part_hint'
                                },
                                <<"END_EXAMPLE_TEXT"),
Matches word fragments or 
<a target="_blank" title="Click for more info on regular expressions" href="http://dev.mysql.com/doc/refman/5.5/en/regexp.html">regular expressions</a>.
For example, the expression 
<span class="unbreakable-term">^[A-Z]{2}[0-9]{6}\$</span> 
matches accession numbers that have the format of any two letters followed by
six digits (such as AK022913).
END_EXAMPLE_TEXT
                        ),
                    ),
                    $q->li(
                        $q->div(
                            'Limit to: ',
                            (
                                defined($species_data)
                                ? $q->popup_menu(
                                    -name   => 'spid',
                                    -id     => 'spid',
                                    -title  => 'Choose species to search',
                                    -values => [ keys %$species_data ],
                                    -labels => $species_data
                                  )
                                : $q->hidden(
                                    -name => 'pid',
                                    -id   => 'search_pid'
                                )
                            ),
                            $q->span(
                                {
                                    -id    => 'location_block',
                                    -class => 'input_container'
                                },
                                $q->label(
                                    'chr',
                                    $q->textfield(
                                        -name  => 'chr',
                                        -title => 'Type chromosome name',
                                        -size  => 3
                                    )
                                ),
                                $q->span(':'),
                                $q->textfield(
                                    -name => 'start',
                                    -title =>
                                      'Enter start position on the chromosome',
                                    -size => 14
                                ),
                                $q->span('-'),
                                $q->textfield(
                                    -name => 'end',
                                    -title =>
                                      'Enter end position on the chromosome',
                                    -size => 14
                                )
                            )
                        ),
                        $q->div(
                            {
                                -id    => 'chr_div',
                                -class => 'hint',
                                -style => 'display:block;'
                            },
                            <<"END_chr_note"
[Optional] Enter chromosome name (such as 2, M, or X) and, optionally, a numeric
range. Leave these fields blank to search entire genome.
END_chr_note
                        )
                    )
                )
            ),
            $q->div(
                { -id => 'upload' },
                $q->filefield(
                    -name => 'file',
                    -title =>
'File with probe ids, gene symbols, or accession numbers (one term per line)'
                ),
                file_opts_html( $q, 'fileOpts' ),
                $q->div(
                    {
                        -id    => 'scope_file_container',
                        -class => 'input_container'
                    },
                    $q->input(
                        {
                            -type  => 'radio',
                            -name  => 'scope_file',
                            -value => 'Probe IDs',
                            -title => 'Look up probe IDs'
                        }
                    ),
                    $q->input(
                        {
                            -type    => 'radio',
                            -name    => 'scope_file',
                            -checked => 'checked',
                            -value   => 'Genes/Accession Nos.',
                            -title   => 'Look up gene symbols'
                        }
                    ),
                    $q->input(
                        {
                            -type  => 'radio',
                            -name  => 'scope_file',
                            -value => 'GO IDs',
                            -title => 'Look up GO IDs'
                        }
                    ),
                    $q->input(
                        {
                            -type => 'hidden',
                            -id   => 'scope_file_state'
                        }
                    )
                )
            )
        )
    );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  default_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_body {
    my $self      = shift;
    my $q         = $self->{_cgi};
    my $curr_proj = $self->{_WorkingProject};

    return
      $q->h2('Find Probes'),

      $q->p(<<"END_H2P_TEXT"),
You can enter here a list of probes, accession numbers, or gene names. 
The results will contain probes that are related to the search terms.
END_H2P_TEXT
      $q->start_form(
        -id      => 'main_form',
        -method  => 'POST',
        -action  => $q->url( absolute => 1 ) . '?a=findProbes',
        -enctype => 'multipart/form-data'
      ),

      $q->dl(

        # Main Form
        $q->dt( $q->label( { -for => 'q' }, 'Search Term(s):' ) ),
        $q->dd( $self->mainFormDD( species_hash => $self->{_species_data} ) )
      ),

      # Output options
      $q->dl(
        $q->dt('Output options:'),
        $q->dd(
            $q->p(
                $q->a(
                    {
                        -id    => 'outputOpts',
                        -class => 'pluscol',
                        -title => 'Click to expand for more options'
                    },
                    '+ Display Options / Graphs'
                )
            ),
            $q->div(
                {
                    -id    => 'outputOpts_container',
                    -class => 'dd_collapsible'
                },
                $q->div(
                    { -class => 'input_container' },
                    $q->checkbox(
                        -name => 'extra_fields',
                        -title =>
'Show extra annotation including gene names and probe sequences',
                        -label => 'Show Extra Annotation'
                    )
                ),
                $q->div(
                    { -class => 'input_container' },
                    $q->checkbox(
                        -id    => 'show_graphs',
                        -name  => 'show_graphs',
                        -title => 'Show response graph for each probe',
                        -label => 'Show Response Graphs'
                    )
                ),
                $q->div(
                    {
                        -id    => 'graph_hint_container',
                        -class => 'dd_collapsible'
                    },
                    $q->p(
                        $q->label(
                            $q->input(
                                {
                                    -type => 'radio',
                                    -name => 'graph_type',
                                    -title =>
'Plot intensity ratios as fold change for each experiment',
                                    -value   => 'Fold Change',
                                    -checked => 'checked'
                                }
                            ),
                            'Fold Change'
                        ),
                        $q->label(
                            $q->input(
                                {
                                    -type => 'radio',
                                    -name => 'graph_type',
                                    -title =>
'Plot intensity ratios as base 2 logarithm for each experiment',
                                    -value => 'Log Ratio',
                                }
                            ),
                            'Log Ratio'
                        ),
                    ),
                    $q->p(
                        { -class => 'hint', style => 'display:block;' },
                        <<"END_graph_hint"
For graphs to display, your browser should support Scalable Vector Graphics
(SVG). Internet Explorer (IE) versions earlier than v9.0 can only display SVG
images via 
<a target="_blank" href="http://www.adobe.com/svg/viewer/install/" title="Download Adobe SVG plugin">Adobe SVG plugin</a>.
END_graph_hint
                    )
                )
            )
        ),

        $q->dt('&nbsp;'),
        $q->dd(
            $q->hidden( -name => 'proj', -value => $curr_proj ),
            $q->submit(
                -class => 'button black bigrounded',
                -name  => 'b',
                -value => 'Search',
                -title => 'Search the database'
            )
        ),
      ),
      $q->endform;
}

1;

__END__

=head1 NAME

SGX::FindProbes

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 AUTHORS
Michael McDuffie
Eugene Scherba

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut


