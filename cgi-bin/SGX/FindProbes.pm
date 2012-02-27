package SGX::FindProbes;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;

require Tie::IxHash;
use File::Basename;
use JSON qw/encode_json/;
use File::Temp;
use SGX::Abstract::Exception ();
use SGX::Util qw/car trim min bind_csv_handle distinct file_opts_html/;
use SGX::Debug;
use SGX::Config qw/$IMAGES_DIR $YUI_BUILD_ROOT/;
use Data::UUID;

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ( $class, @param ) = @_;

    my $self = $class->SUPER::new(@param);

    $self->set_attributes(
        _title               => 'Find Probes',
        _ProbeHash           => undef,
        _Names               => undef,
        _ProbeCount          => undef,
        _ExperimentDataQuery => undef,
        _SearchTerms         => [],
        _FilterItems         => [],

        _scope => undef,
        _graph => undef,
    );

    bless $self, $class;
    return $self;
}

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

    $self->register_actions(
        Search => { head => 'Search_head', body => 'Search_body' } );
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
    push @{ $self->{_js_src_code} }, +{ -code => <<"END_onload"};
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
        'yahoo-dom-event/yahoo-dom-event.js', 'connection/connection-min.js',
        'dragdrop/dragdrop-min.js',           'container/container-min.js',
        'element/element-min.js',             'datasource/datasource-min.js',
        'paginator/paginator-min.js',         'datatable/datatable-min.js',
        'selector/selector-min.js'
      );

    if ( $next_action == 1 ) {
        push @$js_src_code,
          ( { -code => $self->findProbes_js($s) },
            { -src => 'FindProbes.js' } );
    }
    elsif ( $next_action == 2 ) {
        push @$js_src_code,
          ( { -code => $self->goTerms_js($s) }, { -src => 'GoTerms.js' } );
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
    my $data = $self->{_GoTerms};

    my $rowcount = scalar(@$data);
    my $caption =
      sprintf( 'Found %d GO term%s', $rowcount, ( $rowcount == 1 ) ? '' : 's',
      );

    my %type_to_column = (
        'Probe IDs'            => 'reporter',
        'Genes/Accession Nos.' => 'gsymbol',
        'Gene Names/Desc.'     => 'gsymbol+gname+gdesc',
        'GO Term Defs.'        => 'goterms'
    );

    my %json_probelist = (
        caption => $caption,
        records => $data,
        headers => $self->{_GoTerms_Names}
    );

    my ( $type, $match ) = @$self{qw/_scope _match/};
    my $out = sprintf(
        <<"END_JSON_DATA",
var queriedItems = %s;
var data = %s;
var url_prefix = "%s";
var project_id = "%s";
END_JSON_DATA
        encode_json(
            ( $match eq 'Full Word' )
            ? +{ map { lc($_) => undef } @{ $self->{_SearchTerms} } }
            : [ distinct( @{ $self->{_SearchTerms} } ) ]
        ),
        encode_json( \%json_probelist ),
        $self->{_cgi}->url( -absolute => 1 ),
        $self->{_WorkingProject}
    );

    return $out;
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
    my $q    = $self->{_cgi};

    my $text  = car $q->param('q');
    my $match = car $q->param('match');

    my $predicate =
      ( $match eq 'Full Word' )
      ? 'where match (go_name, go_term_definition) against (?)'
      : 'where go_name regexp ? or go_term_definition regexp ?';
    my @param = ( $match eq 'Full Word' ) ? ($text) : ( $text, $text );

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
    #  query itself
    #---------------------------------------------------------------------------
    my $sql = <<"END_query1";
select
    go_acc              AS 'GO Acc. No.',
    go_name             AS 'Term Name and Description',
    go_term_definition  AS 'Go Term Def.',
    go_term_type        AS 'Term Type',
    count(distinct rid) AS probe_count
from go_term
INNER join GeneGO    USING(go_acc) 
INNER join ProbeGene USING(gid)
$predicate
group by go_acc
ORDER BY probe_count DESC
END_query1

    my $sth = $dbh->prepare($sql);

    my $rc    = $sth->execute(@param);
    my @names = @{ $sth->{NAME} };
    $names[4] = 'Probes';
    my $data = $sth->fetchall_arrayref();
    $sth->finish();
    $self->{_GoTerms}       = $data;
    $self->{_GoTerms_Names} = \@names;

    return 2;
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
    my $q    = $self->{_cgi};

    my $loc_sid       = car $q->param('spid');
    my $text          = car $q->param('q');
    my $filefield_val = car $q->param('file');
    my $upload_file   = defined($filefield_val) && ( $filefield_val ne '' );

    if (   $text =~ /^\s*$/
        && !$upload_file
        && !( defined($loc_sid) and $loc_sid ne '' ) )
    {
        $self->add_message( { -class => 'error' },
            'No search criteria specified' );
        return;
    }

    # split on spaces or commas
    my @textSplit = split( /[,\s]+/, trim($text) );

    my $scope =
      ($upload_file)
      ? car( $q->param('scope_file') )
      : car( $q->param('scope_list') );
    my $match = car $q->param('match');
    $match = 'Full Word'
      if $upload_file
          || !defined($match)
          || ( $scope eq 'Probe IDs' );

    $self->{_scope} = $scope;
    $self->{_match} = $match;
    $self->{_graph} = car $q->param('graph');
    $self->{_opts}  = car $q->param('opts');

    if ( $scope eq 'GO Term Defs.' ) {
        $self->{_SearchTerms} = [$text];
        return $self->getGOTerms();
    }

    my $temp_table;

    my @sth;
    my @param;
    my @check;

    if (
        !$upload_file
        and (  @textSplit < 2
            or !( $scope eq 'Probe IDs' or $scope eq 'Genes/Accession Nos.' )
            or $match ne 'Full Word' )
      )
    {
        $self->{_SearchTerms} = \@textSplit;
        return 1;
    }

    #----------------------------------------------------------------------
    #  More than one terms entered and matching is exact.
    #  Try to load file if uploading a file.
    #----------------------------------------------------------------------
    my $outputFileName;

    require SGX::CSV;
    if ($upload_file) {
        my ( $outputFileNames, $recordsValid ) =
          SGX::CSV::sanitizeUploadWithMessages(
            $self, 'file',
            csv_in_opts => { quote_char => undef },
            parser      => [
                ( $scope eq 'Probe IDs' )

                #------------------------------------------------------
                #   Probe IDs
                #------------------------------------------------------
                ? sub {

        # Regular expression for the first column (probe/reporter id) reads as
        # follows: from beginning to end, match any character other than [space,
        # forward/back slash, comma, equal or pound sign, opening or closing
        # parentheses, double quotation mark] from 1 to 18 times.
                    if ( shift =~ m/^([^\s,\/\\=#()"]{1,18})$/ ) {
                        return $1;
                    }
                    else {
                        SGX::Exception::User->throw(
                            error => 'Cannot parse probe ID on line ' . shift );
                    }
                  }

                  #-------------------------------------------------------
                  #  Gene symbols
                  #-------------------------------------------------------
                : sub {
                    if ( shift =~ /^([^\+\s]+)$/ ) {
                        return $1;
                    }
                    else {
                        SGX::Exception::User->throw(
                            error => 'Invalid gene symbol format on line '
                              . shift );
                    }
                  }
            ]
          );
        $outputFileName = $outputFileNames->[0];
    }

    #----------------------------------------------------------------------
    #  Set up temporary table
    #----------------------------------------------------------------------
    my $ug = Data::UUID->new();
    $temp_table = $ug->to_string( $ug->create() );
    $temp_table =~ s/-/_/g;
    $temp_table = "tmp$temp_table";
    $self->{_TempTable} = $temp_table;

    #----------------------------------------------------------------------
    #  now load into temporary table
    #----------------------------------------------------------------------
    my $symbol_type =
      ( $scope eq 'Probe IDs' ) ? 'char(18) NOT NULL' : 'char(32) NOT NULL';
    push @sth, <<"END_createTable";
CREATE TEMPORARY TABLE $temp_table (
    symbol $symbol_type, 
    UNIQUE KEY symbol (symbol)
) ENGINE=MEMORY
END_createTable
    push @param, [];
    push @check, undef;

    #-----------------------------------------------------------------------
    #  load symbols into temporary table
    #-----------------------------------------------------------------------
    if ( defined $outputFileName ) {

        #-----------------------------------------------------------------
        #  file is uploaded -- slurp data
        #-----------------------------------------------------------------
        push @sth, <<"END_loadData";
LOAD DATA LOCAL INFILE ?
INTO TABLE $temp_table
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' STARTING BY '' (symbol)
END_loadData
        push @param, [$outputFileName];
        push @check, undef;
    }
    else {

        #------------------------------------------------------------------
        #  file is not uploaded -- multiple insert statements
        #------------------------------------------------------------------
        $self->{_SearchTerms} = \@textSplit;
        foreach my $term (@textSplit) {
            push @sth, "INSERT IGNORE INTO $temp_table (symbol) VALUES (?)";
            push @param, [$term];
            push @check, undef;
        }
    }
    return SGX::CSV::delegate_fileUpload(
        success_message => 0,
        delegate        => $self,
        statements      => \@sth,
        parameters      => \@param,
        validators      => \@check,
        filename        => $outputFileName
    );
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
    my $items = $self->{_SearchTerms};

    my $qtext;
    my $predicate        = [];
    my %translate_fields = (
        'Probe IDs'            => ['reporter'],
        'Genes/Accession Nos.' => ['gsymbol'],
        'Gene Names/Desc.'     => [ 'gsymbol', 'gname', 'gdesc' ],
        'GO Term Defs.'        => []
    );
    my $type = $translate_fields{ $self->{_scope} };

    if ( $match eq 'Full Word' ) {
        ( $predicate => $qtext ) = @$items
          ? (
            [
                join(
                    ' OR ',
                    map {
                        "$_ IN ("
                          . join( ',', map { '?' } @$items ) . ')'
                      } @$type
                )
            ] => [ map { @$items } @$type ]
          )
          : ( [] => [] );
    }
    elsif ( $match eq 'Prefix' ) {
        ( $predicate => $qtext ) = @$items
          ? (
            [ join( ' OR ', map { "$_ REGEXP ?" } @$type ) ] => [
                map {
                    join( '|', map { "^$_" } @$items )
                  } @$type
            ]
          )
          : ( [] => [] );
    }
    elsif ( $match eq 'Partial' ) {
        ( $predicate => $qtext ) =
          @$items
          ? ( [ join( ' OR ', map { "$_ REGEXP ?" } @$type ) ] =>
              [ map { join( '|', @$items ) } @$type ] )
          : ( [] => [] );
    }
    else {
        SGX::Exception::Internal->throw(
            error => "Invalid match value $match\n" );
    }

    if ( @$predicate == 0 ) {
        push @$predicate, map { "$_ IN (NULL)" } @$type;
    }
    $self->{_Predicate} = 'WHERE ' . join( ' AND ', @$predicate );
    $self->{_SearchTermsProc} = $qtext;

    return 1;
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
    my $self  = shift;
    my $q     = $self->{_cgi};
    my $query = 'INNER JOIN platform ON probe.pid=platform.pid';
    my @param;

    $self->{_FilterItems} = \@param;

    #---------------------------------------------------------------------------
    # Filter by chromosomal location
    #---------------------------------------------------------------------------
    my $loc_sid = car $q->param('spid');
    if ( defined $loc_sid and $loc_sid ne '' ) {
        $query .= ' AND platform.sid=?';
        push @param, $loc_sid;

 # where Intersects(LineString(Point(0,93160788), Point(0,103160849)), # locus);
 # chromosome is meaningless unless species was specified.
        my $loc_chr = car $q->param('chr');
        if ( defined $loc_chr and $loc_chr ne '' ) {
            $query .=
              ' INNER JOIN locus ON probe.rid=locus.rid AND locus.chr=?';
            push @param, $loc_chr;

            # starting and ending interval positions are meaningless if no
            # chromosome was specified.
            my $loc_start = car $q->param('start');
            my $loc_end   = car $q->param('end');
            if (   ( defined $loc_start and $loc_start ne '' )
                && ( defined $loc_end and $loc_end ne '' ) )
            {
                $query .=
' AND Intersects(LineString(Point(0,?), Point(0,?)), zinterval)';
                push @param, ( $loc_start, $loc_end );
            }
        }
    }
    return $query;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  build_ExperimentDataQuery
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub build_ExperimentDataQuery {

    # :TODO:07/24/2011 10:56:30:es: Move this function to a separate
    # class in SGX::Model namespace.
    my $self = shift;
    my $whereSQL;
    my $curr_proj = $self->{_WorkingProject};
    if ( defined($curr_proj) && $curr_proj ne '' ) {
        $curr_proj = $self->{_dbh}->quote($curr_proj);
        $whereSQL  = <<"END_whereSQL";
INNER JOIN ProjectStudy USING(stid)
WHERE prid=$curr_proj AND rid=?
END_whereSQL
    }
    else {
        $whereSQL = 'WHERE rid=?';
    }
    $self->{_ExperimentDataQuery} = <<"END_ExperimentDataQuery";
SELECT
    experiment.eid, 
    microarray.ratio,
    microarray.foldchange,
    microarray.pvalue,
    microarray.intensity1,
    microarray.intensity2,
    CONCAT(
        GROUP_CONCAT(study.description SEPARATOR ','), ': ', 
        experiment.sample2, '/', experiment.sample1
    ) AS 'Name',
    GROUP_CONCAT(study.stid SEPARATOR ','),
    study.pid
FROM microarray 
INNER JOIN experiment USING(eid)
INNER JOIN StudyExperiment USING(eid)
INNER JOIN study USING(stid)
$whereSQL
GROUP BY experiment.eid
ORDER BY experiment.eid ASC
END_ExperimentDataQuery

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  loadProbeData
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Get a list of the probes here so that we can get all experiment
#                data for each probe in another query.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadProbeData {
    my $self = shift;

    my $dbh             = $self->{_dbh};
    my $searchItems     = $self->{_SearchTerms};
    my $searchItemsProc = $self->{_SearchTermsProc};
    my $filterItems     = $self->{_FilterItems};
    my $sth             = $dbh->prepare( $self->{_XTableQuery} );
    my @param           = (
        ( ( $self->{_scope} ne 'Probe IDs' ) ? @$searchItemsProc : () ),
        @$filterItems
    );
    my $rc = $sth->execute(@param);
    $self->{_ProbeCount} = $rc;

    # :TRICKY:07/24/2011 12:27:32:es: accessing NAME array will fail if is done
    # after any data were fetched. The line below splices off all
    # elements of the NAME array but the first two.

    $self->{_Names} =
      [ splice( @{ $sth->{NAME} }, min( 2, scalar( @{ $sth->{NAME} } ) ) ) ];
    my $result = $sth->fetchall_arrayref;

    $sth->finish;

    # From each row in the result, create a key-value pair such that the first
    # column becomes the key and the rest of the columns are sliced off into an
    # anonymous array.
    $self->{_ProbeHash} = +{ map { ( shift @$_ ) => $_ } @$result };

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  loadExperimentData
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  For each probe in the list get all the experiment data.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadExperimentData {
    my $self                 = shift;
    my $experimentDataString = '';

    $self->{_ProbeExperimentHash}    = {};
    $self->{_ExperimentListHash}     = {};
    $self->{_eid_stid_tuples}        = [];
    $self->{_ExperimentNameListHash} = {};

#Grab the format for the output from the form.
#$transform = (defined($self->{_cgi}->param('trans'))) ? $self->{_cgi}->param('trans') : '';
#Build SQL statement based on desired output type.
#my $sql_trans                    = '';
#switch ($transform)
#{
#    case 'fold' {
#        $sql_trans = 'if(foldchange>0,foldchange-1,foldchange+1)';
#    }
#    case 'ln' {
#        $sql_trans = 'if(foldchange>0, log2(foldchange), log2(-1/foldchange))';
#    }
#    else  {
#        $sql_trans = '';
#    }
#}

    $self->build_ExperimentDataQuery();
    my $sth = $self->{_dbh}->prepare( $self->{_ExperimentDataQuery} );

    foreach my $key ( keys %{ $self->{_ProbeHash} } ) {
        my $rc  = $sth->execute($key);
        my $tmp = $sth->fetchall_arrayref;

        #We use a temp hash that gets added to the _ProbeExperimentHash.
        my %tempHash;

        #For each experiment
        foreach (@$tmp) {

            # EID => [ratio, foldchange, pvalue, intensity1, intensity2]
            $tempHash{ $_->[0] } = [ @$_[ 1 .. 5 ] ];

            # EID => PID
            $self->{_ExperimentListHash}->{ $_->[0] } = $_->[8];

            # [EID, STID] => 1
            push @{ $self->{_eid_stid_tuples} }, [ $_->[0], $_->[7] ];

            # EID => Name
            $self->{_ExperimentNameListHash}->{ $_->[0] } = $_->[6];
        }

        #Add the hash of experiment data to the hash of reporters.
        $self->{_ProbeExperimentHash}->{$key} = \%tempHash;
    }

    $sth->finish;
    return;
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
    $s->commit() if defined $s;
    print $q->header(
        -type       => 'text/csv',
        -attachment => 'results.csv',
        -cookie     => ( ( defined $s ) ? $s->cookie_array() : [] )
    );

    my $print = bind_csv_handle( \*STDOUT );

    # Report Header
    $print->( [ 'Find Probes Report', scalar localtime() ] );
    $print->( [ 'Generated By',       $self->{_UserFullName} ] );
    $print->( [ 'Working Project',    $self->{_WorkingProjectName} ] );
    $print->();

    # initialize platform model
    require SGX::Model::PlatformStudyExperiment;
    my $platforms =
      SGX::Model::PlatformStudyExperiment->new( dbh => $self->{_dbh} );
    $platforms->init( platforms => 1 );

    my $currentPID;

    my $ProbeHash              = $self->{_ProbeHash};
    my $ExperimentListHash     = $self->{_ExperimentListHash};
    my $ProbeExperimentHash    = $self->{_ProbeExperimentHash};
    my $FullExperimentData     = $self->{_FullExperimentData};
    my $ExperimentNameListHash = $self->{_ExperimentNameListHash};

    # Sort the hash so the PID's are together.
    foreach my $key (
        sort { $ProbeHash->{$a}->[0] cmp $ProbeHash->{$b}->[0] }
        keys %{$ProbeHash}
      )
    {

        # This lets us know if we should print the headers.
        my $printHeaders = 0;

        # Extract the PID from the string in the hash.
        my $row = $ProbeHash->{$key};

        if ( not defined $currentPID ) {

            # grab first PID from the hash
            $currentPID   = $row->[0];
            $printHeaders = 1;
        }
        elsif ( $row->[0] != $currentPID ) {

            # if different from the current one, print a seperator
            $print->();
            $print->();
            $currentPID   = $row->[0];
            $printHeaders = 1;
        }

        if ( $printHeaders == 1 ) {

            # Print the name of the current platform.
            $print->( [ $platforms->getPlatformNameFromPID($currentPID) ] );
            $print->();
            $print->(
                [
                    'Experiment Number',
                    'Study Description',
                    'Experiment Heading',
                    'Experiment Description'
                ]
            );

            # String representing the list of experiment names.
            my @experimentList = (undef) x 6;

            my @outLine;

            # Loop through the list of experiments and print out the ones for
            # this platform.
            foreach my $value (
                sort { $a <=> $b }
                keys %$ExperimentListHash
              )
            {
                if ( $ExperimentListHash->{$value} == $currentPID ) {

                    #Experiment Number, Study Description, Experiment
                    #Heading, Experiment Description
                    my $fullExperimentDataValue = $FullExperimentData->{$value};
                    $print->(
                        [
                            $value,
                            $fullExperimentDataValue->{description},
                            $fullExperimentDataValue->{experimentHeading},
                            $fullExperimentDataValue->{ExperimentDescription}
                        ]
                    );

                    # The list of experiments goes with the Ratio line for each
                    # block of 5 columns.
                    push @experimentList,
                      $value . ':' . $ExperimentNameListHash->{$value},
                      (undef) x 4;

                    # Form the line that goes above the data. Each experiment
                    # gets a set of 5 columns.
                    push @outLine,
                      "$value:Ratio", "$value:FC", "$value:P-Val",
                      "$value:Intensity1", "$value:Intensity2";
                }
            }

            #Print list of experiments.
            $print->( \@experimentList );

            #Print header line for probe rows.
            $print->(
                [
                    'Probe ID',
                    'Accession Number',
                    'Gene',
                    'Probe Sequence',
                    'Official Gene Name',
                    'Gene Ontology',
                    @outLine
                ]
            );
        }

        # Print the probe info: Probe ID, Accession, Gene Name, Probe
        # Sequence, Gene description, Gene Ontology
        my @outRow = @$row[ 1, 3, 4, 6, 7, 8 ];

        # For this reporter we print out a column for all the experiments that
        # we have data for.
        foreach my $eid (
            sort { $a <=> $b }
            keys %$ExperimentListHash
          )
        {

            # Only try to see the EID's for platform $currentPID.  Add all the
            # experiment data to the output string.
            push( @outRow,
                @{ $ProbeExperimentHash->{$key}->{$eid} || [ (undef) x 5 ] } )
              if $ExperimentListHash->{$eid} == $currentPID;
        }
        $print->( \@outRow );
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  getProbeList
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Loop through the list of probes we are filtering on and create
#                a list.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getProbeList {
    return [ keys %{ shift->{_ProbeHash} } ];
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  getFullExperimentData
#   PARAMETERS:  _eid_stid_tuples, _WorkingProject
#      RETURNS:  _FullExperimentData
#  DESCRIPTION:  Loop through the list of experiments we are displaying and get
#  the information on each. We need eid and stid for each.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getFullExperimentData {
    my $self = shift;

    my $dbh             = $self->{_dbh};
    my $eid_stid_tuples = $self->{_eid_stid_tuples};
    my $curr_proj       = $self->{_WorkingProject};

    my @eid_list;
    my @stid_list;

    foreach (@$eid_stid_tuples) {
        my ( $eid, $stid ) = @$_;
        push @eid_list,  $eid;
        push @stid_list, $stid;
    }

    my $eid_sql =
      ( @eid_list > 0 ) ? join( ',', map { '?' } @eid_list ) : 'NULL';
    my $stid_sql =
      ( @stid_list > 0 ) ? join( ',', map { '?' } @stid_list ) : 'NULL';
    my @params = ( @eid_list, @stid_list );

    my @where_conditions = ( "eid IN ($eid_sql)", "study.stid IN ($stid_sql)" );
    if ( defined($curr_proj) && $curr_proj ne '' ) {
        unshift @params,           $curr_proj;
        unshift @where_conditions, 'prid=?';
    }
    my $where_sql = 'WHERE ' . join( ' AND ', @where_conditions );

    my $sth = $dbh->prepare(<<"END_query_titles_element");
SELECT
    experiment.eid, 
    CONCAT(study.description, ': ', experiment.sample2, ' / ', experiment.sample1) AS title, 
    CONCAT(experiment.sample2, ' / ', experiment.sample1) AS experimentHeading,
    study.description,
    experiment.ExperimentDescription 
FROM experiment 
INNER JOIN StudyExperiment USING(eid)
INNER JOIN study USING(stid)
$where_sql
ORDER BY study.stid ASC, experiment.eid ASC
END_query_titles_element

    my $rc = $sth->execute(@params);
    $self->{_FullExperimentData} = $sth->fetchall_hashref('eid');

    $sth->finish;
    return 1;
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

    my @ret = (
        $q->h2( { -id => 'caption' }, '' ),
        $q->p(
            { -id => 'subcaption' },
            sprintf(
                'Searched %s (%s): %s',
                lc( $self->{_scope} ),
                lc( $self->{_match} ),
                join( ', ', distinct( @{ $self->{_SearchTerms} } ) )
            )
        ),
        $q->div(
            $q->a( { -id => 'resulttable_astext' }, 'View as plain text' )
        ),
        $q->div( { -id => 'resulttable' }, '' )
    );

    if ( defined $self->{_graph} and $self->{_graph} ne 'No Graphs' ) {
        push @ret, $q->p(<<"END_LEGEND");
<strong>Dark bars</strong>: values meething the P threshold. 
<strong>Light bars</strong>: values above the P threshold. 
<strong>Green horizontal lines</strong>: fold-change threshold.
END_LEGEND
        push @ret, $q->ul( { -id => 'graphs' }, '' );
    }
    return @ret;
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
        $q->dt( $q->label( { -for => 'q' }, 'Search Term(s):' ) ),
        $q->dd(
            $q->div(
                { -id => 'property_editor', -class => 'yui-navset' },
                $q->ul(
                    { -class => 'yui-nav' },
                    $q->li(
                        { -class => 'selected' },
                        $q->a( { -href => "#terms" }, $q->em('Enter List') )
                    ),
                    $q->li(
                        $q->a( { -href => "#upload" }, $q->em('Upload File') )
                    )
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
                                    -rows    => 10,
                                    -columns => 50,
                                    -title   => <<"END_terms_title"
Enter list of terms to search. Multiple entries have to be separated by commas
or be on separate lines.
END_terms_title
                                )
                            )
                        ),
                        $q->div(
                            {
                                -id    => 'scope_list_container',
                                -class => 'input_container'
                            },
                            $q->input(
                                {
                                    -type  => 'radio',
                                    -name  => 'scope_list',
                                    -value => 'Probe IDs',
                                    -title => 'Search probe IDs'
                                }
                            ),
                            $q->input(
                                {
                                    -type    => 'radio',
                                    -name    => 'scope_list',
                                    -value   => 'Genes/Accession Nos.',
                                    -checked => 'checked',
                                    -title   => 'Search gene symbols'
                                }
                            ),
                            $q->input(
                                {
                                    -type  => 'radio',
                                    -name  => 'scope_list',
                                    -value => 'Gene Names/Desc.',
                                    -title => 'Search gene names'
                                }
                            ),
                            $q->input(
                                {
                                    -type  => 'radio',
                                    -name  => 'scope_list',
                                    -value => 'GO Term Defs.',
                                    -title => 'Search gene ontology terms'
                                }
                            ),

                            # preserve state of radio buttons
                            $q->input(
                                {
                                    -type => 'hidden',
                                    -id   => 'scope_list_state'
                                }
                            )
                        ),
                        $q->div(
                            { -id => 'pattern_div' },
                            $q->p(
                                $q->a(
                                    {
                                        -id    => 'patternMatcher',
                                        -class => 'pluscol'
                                    },
                                    '+ Patterns in input terms'
                                )
                            ),
                            $q->div(
                                {
                                    -id    => 'patternMatcher_container',
                                    -class => 'dd_collapsible'
                                },
                                $q->div(
                                    {
                                        -id    => 'pattern_container',
                                        -class => 'input_container'
                                    },
                                    $q->input(
                                        {
                                            -type    => 'radio',
                                            -name    => 'match',
                                            -value   => 'Full Word',
                                            -checked => 'checked',
                                            -title   => 'Match full words'
                                        }
                                    ),
                                    $q->input(
                                        {
                                            -type  => 'radio',
                                            -name  => 'match',
                                            -value => 'Partial',
                                            -title =>
'Match word parts, regular expressions'
                                        }
                                    ),
                                    $q->input(
                                        {
                                            -id    => 'prefix',
                                            -type  => 'radio',
                                            -name  => 'match',
                                            -value => 'Prefix',
                                            -title => 'Match word prefixes'
                                        }
                                    ),

                                    # preserve state of radio buttons
                                    $q->input(
                                        {
                                            -type => 'hidden',
                                            -id   => 'pattern_state'
                                        }
                                    )
                                ),
                                $q->p(
                                    {
                                        -class => 'hint',
                                        -id    => 'pattern_part_hint'
                                    },
                                    <<"END_EXAMPLE_TEXT") ) ),
Partial matching lets you search for word parts and regular expressions.
For example, <strong>^cyp.b</strong> means "all genes starting with
<strong>cyp.b</strong> where the fourth character (the dot) is any single letter or
digit."  See <a target="_blank"
href="http://dev.mysql.com/doc/refman/5.0/en/regexp.html">this page</a> for more
information.
END_EXAMPLE_TEXT
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
                                    -type    => 'radio',
                                    -name    => 'scope_file',
                                    -checked => 'checked',
                                    -value   => 'Probe IDs',
                                    -title   => 'Search probe IDs'
                                }
                            ),
                            $q->input(
                                {
                                    -type  => 'radio',
                                    -name  => 'scope_file',
                                    -value => 'Genes/Accession Nos.',
                                    -title => 'Search gene symbols'
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
            )
        )
      ),
      $q->dl(
        $q->dt('Scope and Options:'),
        $q->dd(
            $q->div(
                $q->div(
                    { -class => 'input_container' },
                    $q->popup_menu(
                        -name   => 'spid',
                        -id     => 'spid',
                        -title  => 'Choose species to search',
                        -values => [ keys %{ $self->{_species_data} } ],
                        -labels => $self->{_species_data}
                    )
                ),
                $q->div(
                    {
                        -id    => 'chr_div',
                        -style => 'display:none;'
                    },
                    $q->div(
                        { -class => 'input_container' },
                        $q->label( { -for => 'chr' }, 'chr' ),
                        $q->textfield(
                            -name  => 'chr',
                            -id    => 'chr',
                            -title => 'Type chromosome name',
                            -size  => 3
                        ),
                        $q->label( { -for => 'start' }, ':' ),
                        $q->textfield(
                            -name  => 'start',
                            -id    => 'start',
                            -title => 'Enter start position on the chromosome',
                            -size  => 14
                        ),
                        $q->label( { -for => 'end' }, '-' ),
                        $q->textfield(
                            -name  => 'end',
                            -id    => 'end',
                            -title => 'Enter end position on the chromosome',
                            -size  => 14
                        )
                    ),
                    $q->p(
                        { -class => 'hint', -style => 'display:block;' },
'Enter a numeric interval preceded by chromosome name, for example 16, 7, M, or X. Leave these fields blank to search all chromosomes.'
                    ),
                ),
            ),
            $q->p(
                $q->a(
                    { -id => 'outputOpts', -class => 'pluscol' },
                    '+ Output options'
                )
            ),
            $q->div(
                { -id => 'outputOpts_container', -class => 'dd_collapsible' },
                $q->p( { -class => 'radio_heading' }, 'Format:' ),
                $q->div(
                    {
                        -id    => 'opts_container',
                        -class => 'input_container'
                    },
                    $q->input(
                        {
                            -type  => 'radio',
                            -name  => 'opts',
                            -value => 'Basic',
                            -title =>
                              'Only list gene symbols and accession numbers',
                            -checked => 'checked'
                        }
                    ),
                    $q->input(
                        {
                            -type => 'radio',
                            -name => 'opts',
                            -title =>
                              'Also include probe annotation and GO terms',
                            -value => 'With Annotation',
                        }
                    ),
                    $q->input(
                        {
                            -type => 'radio',
                            -name => 'opts',
                            -title =>
'Get results in CSV format, including experimental data',
                            -value => 'Complete (CSV)',
                        }
                    ),

                    # preserve state of radio buttons
                    $q->input(
                        {
                            -type => 'hidden',
                            -id   => 'opts_state'
                        }
                    )
                ),
                $q->div(
                    {
                        -id    => 'graph_everything_container',
                        -class => 'input_container'
                    },
                    $q->p( { -class => 'radio_heading' }, 'Graphs:' ),
                    $q->div(
                        { -id => 'graph_hint_container' },
                        $q->div(
                            {
                                -id    => 'graph_container',
                                -class => 'input_container'
                            },
                            $q->input(
                                {
                                    -type    => 'radio',
                                    -name    => 'graph',
                                    -value   => 'No Graphs',
                                    -title   => 'Do not display graphs',
                                    -checked => 'checked'
                                }
                            ),
                            $q->input(
                                {
                                    -type => 'radio',
                                    -name => 'graph',
                                    -title =>
'Plot intensity ratios as fold change for each experiment',
                                    -value => 'Fold Change',
                                }
                            ),
                            $q->input(
                                {
                                    -type => 'radio',
                                    -name => 'graph',
                                    -title =>
'Plot intensity ratios as base 2 logarithm for each experiment',
                                    -value => 'Log Ratio',
                                }
                            ),

                            # preserve state of radio buttons
                            $q->input(
                                {
                                    -type => 'hidden',
                                    -id   => 'graph_state'
                                }
                            )
                        ),
                        $q->p(
                            { -id => 'graph_hint', -class => 'hint' },
'For graphs to display, your browser should support Scalable Vector Graphics (SVG). Internet Explorer (IE) versions earlier than v9.0 can only display SVG images via <a target="_blank" href="http://www.adobe.com/svg/viewer/install/" title="Download Adobe SVG plugin">Adobe SVG plugin</a>.'
                        )
                    )
                )
            ),
        ),

        # END GRAPH STUFF

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

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  build_XTableQuery
#   PARAMETERS:  $type - query type (probe|gene)
#                tmp_table => $tmpTable - uploaded table to join on
#      RETURNS:  true value
#  DESCRIPTION:  Fills _InsideTableQuery field
#       THROWS:  SGX::Exception::User
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub build_XTableQuery {

    my $self      = shift;
    my $dbh       = $self->{_dbh};
    my $tmp_table = $self->{_TempTable};
    my $haveTable = ( defined($tmp_table) and ( $tmp_table ne '' ) );

    #---------------------------------------------------------------------------
    #  innermost SELECT statement differs depending on whether we are searching
    #  the probe table or the gene table
    #---------------------------------------------------------------------------
    my $innerSQL;

    if ($haveTable) {
        $innerSQL =
          ( $self->{_scope} eq 'Probe IDs' )
          ? "SELECT rid, gid FROM probe INNER JOIN $tmp_table AS tmp ON probe.reporter=tmp.symbol LEFT JOIN ProbeGene USING(rid)"
          : <<"END_table_gene";
SELECT rid, gid
FROM ProbeGene
INNER JOIN (
    SELECT DISTINCT rid FROM ProbeGene INNER JOIN gene USING(gid) INNER JOIN $tmp_table AS tmp ON gene.gsymbol=tmp.symbol
) AS d1 USING(rid)
END_table_gene
    }
    else {
        $self->build_SearchPredicate();
        my $predicate = $self->{_Predicate};
        $innerSQL =
          ( $self->{_scope} eq 'Probe IDs' )
          ? "SELECT rid, gid FROM probe LEFT JOIN ProbeGene USING(rid) $predicate"
          : <<"END_no_table_gene";
SELECT rid, gid
FROM ProbeGene
INNER join (
    SELECT DISTINCT rid FROM ProbeGene INNER JOIN gene USING(gid) $predicate
) AS d1 USING(rid)
END_no_table_gene
    }

    #---------------------------------------------------------------------------
    # only return results for platforms that belong to the current working
    # project (as determined through looking up studies linked to the current
    # project).
    #---------------------------------------------------------------------------
    my $curr_proj             = $self->{_WorkingProject};
    my $sql_subset_by_project = '';
    if ( defined($curr_proj) && $curr_proj ne '' ) {
        $curr_proj             = $dbh->quote($curr_proj);
        $sql_subset_by_project = <<"END_sql_subset_by_project"
INNER JOIN study ON study.pid=platform.pid
INNER JOIN ProjectStudy ON prid=$curr_proj AND ProjectStudy.stid=study.stid
END_sql_subset_by_project
    }

    #---------------------------------------------------------------------------
    # Filter by chromosomal location (use platform table to look up species when
    # only species is specified and not an actual chromosomal location).
    #---------------------------------------------------------------------------
    my $limit_predicate = $self->build_location_predparam();

    #---------------------------------------------------------------------------
    #  fields to select
    #---------------------------------------------------------------------------
    my @select_fields = (
        'probe.rid',
        'platform.pid',
        "probe.reporter  AS 'Probe ID'",
        "platform.pname  AS 'Platform'",
"group_concat(if(gene.gtype=0, gene.gsymbol, NULL) separator ' ') AS 'Accession No.'",
"group_concat(if(gene.gtype=1, gene.gsymbol, NULL) separator ' ') AS 'Gene'",
        "species.sname   AS 'Species'"
    );

    if ( $self->{_opts} ne 'Basic' ) {

        # extra fields
        push @select_fields,
          (
            "probe.probe_sequence AS 'Probe Sequence'",
"group_concat(concat(gene.gname, if(isnull(gene.gdesc), '', concat(', ', gene.gdesc))) separator '; ') AS 'Gene Name/Desc.'"
          );
    }
    my $selectFieldsSQL = join( ',', @select_fields );

    #---------------------------------------------------------------------------
    #  inner query -- allow for plain dump if location is specified but no
    #  search terms entered.
    #
    #  TODO: if uploading a file, only return info for probes uploaded?
    #---------------------------------------------------------------------------

    my $searchTerms = $self->{_SearchTerms};
    $innerSQL =
      ( !$haveTable and ( defined $searchTerms && @$searchTerms == 0 ) )
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
    $self->{_XTableQuery} = <<"END_XTableQuery";
SELECT
$selectFieldsSQL
FROM probe
$innerSQL
LEFT join ProbeGene ON probe.rid=ProbeGene.rid
LEFT join gene ON gene.gid=ProbeGene.gid
$limit_predicate
LEFT JOIN species ON species.sid=platform.sid
$sql_subset_by_project
group by probe.rid
END_XTableQuery

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  build_SimpleProbeQuery
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  Currently only used by SGX::CompareExperiments
#     SEE ALSO:  n/a
#===============================================================================
sub build_SimpleProbeQuery {
    my ($self) = @_;

    my $InsideTableQuery = $self->{_InsideTableQuery};

    # only return results for platforms that belong to the current working
    # project (as determined through looking up studies linked to the current
    # project).
    my $curr_proj             = $self->{_WorkingProject};
    my $sql_subset_by_project = '';
    if ( defined($curr_proj) && $curr_proj ne '' ) {
        $curr_proj             = $self->{_dbh}->quote($curr_proj);
        $sql_subset_by_project = <<"END_sql_subset_by_project"
INNER JOIN study ON study.pid=probe.pid
INNER JOIN ProjectStudy USING(stid) 
WHERE prid=$curr_proj 
END_sql_subset_by_project
    }

    $self->{_ProbeQuery} = <<"END_ProbeQuery";
SELECT DISTINCT probe.rid
FROM ( $InsideTableQuery ) as g0
LEFT JOIN ProbeGene USING(gid)
INNER JOIN probe ON probe.rid=COALESCE(ProbeGene.rid, g0.rid)
$sql_subset_by_project
END_ProbeQuery

    return 1;
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

    $self->build_XTableQuery();

    if ( $self->{_opts} eq 'Complete (CSV)' ) {

    #---------------------------------------------------------------------------
    #  CSV output
    #---------------------------------------------------------------------------
        $self->{_UserSession}->commit();
        $self->loadProbeData();
        $self->loadExperimentData();
        $self->getFullExperimentData();
        $self->printFindProbeCSV();
        exit;
    }
    else {

    #---------------------------------------------------------------------------
    #  HTML output
    #---------------------------------------------------------------------------
        $self->loadProbeData();
        my $rowcount  = $self->{_ProbeCount};
        my $proj_name = $self->{_WorkingProjectName};
        my $caption   = sprintf(
            '%sFound %d probe%s',
            ( defined($proj_name) and $proj_name ne '' )
            ? "$proj_name: "
            : '',
            $rowcount,
            ( $rowcount == 1 ) ? '' : 's',
        );

        my @json_records;
        while ( my ( $rid, $row ) = each %{ $self->{_ProbeHash} } ) {

            # Skipping the first value in the array (it's platform ID)
            push @json_records,
              +{ 0 => $rid, map { $_ => $row->[$_] } 1 .. $#$row };
        }

        my %type_to_column = (
            'Probe IDs'            => 'reporter',
            'Genes/Accession Nos.' => 'gsymbol',
            'Gene Names/Desc.'     => 'gsymbol+gname+gdesc',
            'GO Term Defs.'        => 'goterms'
        );

        my %json_probelist = (
            caption => $caption,
            records => \@json_records,
            headers => $self->{_Names}
        );

        my ( $type, $match ) = @$self{qw/_scope _match/};
        my $out = sprintf(
            <<"END_JSON_DATA",
var searchColumn = "%s";
var queriedItems = %s;
var data = %s;
var url_prefix = "%s";
var show_graphs = "%s";
var extra_fields = "%s";
var project_id = "%s";
END_JSON_DATA
            $type_to_column{$type},
            encode_json(
                ( $match eq 'Full Word' )
                ? +{ map { lc($_) => undef } @{ $self->{_SearchTerms} } }
                : [ distinct( @{ $self->{_SearchTerms} } ) ]
            ),
            encode_json( \%json_probelist ),
            $self->{_cgi}->url( -absolute => 1 ),
            $self->{_graph},
            $self->{_opts},
            $self->{_WorkingProject}
        );

        return $out;
    }
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


