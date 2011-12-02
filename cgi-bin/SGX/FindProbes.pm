package SGX::FindProbes;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;

require Tie::IxHash;
use File::Basename;
use JSON qw/encode_json/;
use File::Temp;
use SGX::Abstract::Exception ();
use SGX::Util qw/car all_match trim min bind_csv_handle/;
use SGX::Debug;

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
    my ( $s, $js_src_yui, $js_src_code ) =
      @$self{qw{_UserSession _js_src_yui _js_src_code}};

    push @{ $self->{_css_src_yui} }, 'button/assets/skins/sam/button.css';
    push @$js_src_yui,
      (
        'yahoo-dom-event/yahoo-dom-event.js',
        'element/element-min.js', 'button/button-min.js'
      );
    $self->getSessionOverrideCGI();
    push @$js_src_code, ( { -src => 'FormFindProbes.js' } );

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
    my $rc   = $sth->execute;
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

    if ( !$self->FindProbes_init() ) {
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

    $self->getSessionOverrideCGI();
    push @$js_src_code, { -code => $self->findProbes_js($s) };
    push @$js_src_code, { -src  => 'FindProbes.js' };
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
    my ( $self, $fh ) = @_;
    my $q = $self->{_cgi};

    $self->{_scope} = $q->param('scope');
    $self->{_match} = $q->param('match');
    $self->{_graph} = $q->param('graph');
    $self->{_opts}  = $q->param('opts');

    my $match = $q->param('match');
    $match = 'Full Word' unless defined $match;

    my @textSplit;

    if ( defined $fh ) {
        my @lines = split(
            /\r\n|\n|\r/,
            do { local $/ = <$fh> }
        );
        require Text::CSV;
        my $csv_in =
          Text::CSV->new( { sep_char => "\t", allow_whitespace => 1 } );

        # Generate a custom function that matches all members of an array to see
        # if they all are empty strings.
        my $is_empty = all_match( qr/^$/, ignore_undef => 1 );
        while ( $csv_in->parse( shift @lines ) ) {

            # grab first field of each row
            my @fields = $csv_in->fields();
            my $term   = shift @fields;
            next if $is_empty->($term);
            push @textSplit, $term;
        }

        # check for errors
        if ( my $error = $csv_in->error_diag() ) {
            SGX::Exception::User->throw( error => $error );
        }
    }
    else {

        #Split the input on commas and spaces
        my $text = car $q->param('q');
        @textSplit = split( /[,\s]+/, trim($text) );
    }

    $self->{_match}       = $match;
    $self->{_SearchTerms} = \@textSplit;

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
    my $items = $self->{_SearchTerms};

    my $qtext;
    my $predicate;
    my %translate_fields = (
        'Probe IDs'         => 'reporter',
        'Gene Names'        => 'seqname',
        'Accession Numbers' => 'accnum'
    );
    my $type = $translate_fields{ $self->{_scope} };

    if ( $match eq 'Full Word' ) {
        ( $predicate => $qtext ) =
          @$items
          ? ( [ "$type IN (" . join( ',', map { '?' } @$items ) . ')' ] =>
              $items )
          : ( [] => [] );
    }
    elsif ( $match eq 'Prefix' ) {
        ( $predicate => $qtext ) =
          @$items
          ? ( ["$type REGEXP ?"] => [ join( '|', map { "^$_" } @$items ) ] )
          : ( [] => [] );
    }
    elsif ( $match eq 'Partial' ) {
        ( $predicate => $qtext ) =
          @$items
          ? ( ["$type REGEXP ?"] => [ join( '|', @$items ) ] )
          : ( [] => [] );
    }
    else {
        SGX::Exception::Internal->throw(
            error => "Invalid match value $match\n" );
    }

    if ( @$predicate == 0 ) {
        push @$predicate, "$type IN (NULL)";
    }
    $self->{_Predicate} = 'WHERE ' . join( ' AND ', @$predicate );
    $self->{_SearchTerms} = $qtext;
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
    my $self = shift;
    my $q    = $self->{_cgi};
    my $query;
    my @param;

    #---------------------------------------------------------------------------
    # Filter by chromosomal location
    #---------------------------------------------------------------------------
    my $loc_sid = car $q->param('spid');
    if ( defined $loc_sid and $loc_sid ne '' ) {
        $query = 'location.sid=?';
        push @param, $loc_sid;

        # chromosome is meaningless unless species was specified.
        my $loc_chr = car $q->param('chr');
        if ( defined $loc_chr and $loc_chr ne '' ) {
            $query .= ' AND location.chromosome=?';
            push @param, $loc_chr;

            # starting and ending interval positions are meaningless if no
            # chromosome was specified.
            my $loc_start = car $q->param('start');
            if ( defined $loc_start and $loc_start ne '' ) {
                $query .= ' AND location.start<=?';
                push @param, $loc_start;
            }
            my $loc_end = car $q->param('end');
            if ( defined $loc_end and $loc_end ne '' ) {
                $query .= ' AND location.end>=?';
                push @param, $loc_end;
            }
        }
    }
    return ( $query, \@param );
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
    my ($self) = @_;

    my $dbh         = $self->{_dbh};
    my $searchItems = $self->{_SearchTerms};
    my $filterItems = $self->{_FilterItems};
    my $sth         = $dbh->prepare( $self->{_ProbeQuery} );
    my $rc = $sth->execute( @$searchItems, @$searchItems, @$filterItems );
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

    $self->{_ProbeExperimentHash}     = {};
    $self->{_ExperimentListHash}      = {};
    $self->{_ExperimentStudyListHash} = [];
    $self->{_ExperimentNameListHash}  = {};

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
            push @{ $self->{_ExperimentStudyListHash} }, [ $_->[0], $_->[7] ];

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
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Loop through the list of experiments we are displaying and get
#  the information on each. We need eid and stid for each.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getFullExperimentData {
    my $self = shift;

    my $dbh = $self->{_dbh};
    my @eid_list;
    my @stid_list;

    foreach ( @{ $self->{_ExperimentStudyListHash} } ) {
        my ( $eid, $stid ) = @$_;
        push @eid_list,  $eid;
        push @stid_list, $stid;
    }

    my $eid_string  = join( ',', @eid_list );
    my $stid_string = join( ',', @stid_list );

    my $whereSQL;
    my $curr_proj = $self->{_WorkingProject};
    if ( defined($curr_proj) && $curr_proj ne '' ) {
        $curr_proj = $dbh->quote($curr_proj);
        $whereSQL  = <<"END_whereTitlesSQL";
INNER JOIN ProjectStudy USING(stid)
WHERE prid=$curr_proj AND eid IN ($eid_string) AND study.stid IN ($stid_string)
END_whereTitlesSQL
    }
    else {
        $whereSQL =
          "WHERE eid IN ($eid_string) AND study.stid IN ($stid_string)";
    }
    my $query_titles = <<"END_query_titles_element";
SELECT experiment.eid, 
    CONCAT(study.description, ': ', experiment.sample2, ' / ', experiment.sample1) AS title, 
    CONCAT(experiment.sample2, ' / ', experiment.sample1) AS experimentHeading,
    study.description,
    experiment.ExperimentDescription 
FROM experiment 
INNER JOIN StudyExperiment USING(eid)
INNER JOIN study USING(stid)
$whereSQL
ORDER BY study.stid ASC, experiment.eid ASC
END_query_titles_element

    my $sth = $dbh->prepare($query_titles);
    my $rc  = $sth->execute();
    $self->{_FullExperimentData} = $sth->fetchall_hashref('eid');

    $sth->finish;
    return;
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
                join( ', ', @{ $self->{_SearchTerms} } )
            )
        ),
        $q->div(
            $q->a( { -id => 'probetable_astext' }, 'View as plain text' )
        ),
        $q->div( { -id => 'probetable' }, '' )
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

    return $q->start_form(
        -id      => 'main_form',
        -method  => 'POST',
        -action  => $q->url( absolute => 1 ) . '?a=findProbes',
        -enctype => 'application/x-www-form-urlencoded'
      ),
      $q->h2('Find Probes'),
      $q->p(<<"END_H2P_TEXT"),
You can enter here a list of probes, accession numbers, or gene names. 
The results will contain probes that are related to the search terms.
END_H2P_TEXT
      $q->dl(
        $q->dt( $q->label( { -for => 'q' }, 'Search Term(s):' ) ),
        $q->dd(
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
        ),
        $q->dt( $q->label( { -for => 'type' }, 'Scope:' ) ),
        $q->dd(
            $q->div(
                { -id => 'scope_container', -class => 'input_container' },
                $q->input(
                    {
                        -type    => 'radio',
                        -name    => 'scope',
                        -value   => 'Gene Names',
                        -checked => 'checked',
                        -title   => 'Search gene names'
                    }
                ),
                $q->input(
                    {
                        -type  => 'radio',
                        -name  => 'scope',
                        -value => 'Accession Numbers',
                        -title => 'Search accession numbers'
                    }
                ),
                $q->input(
                    {
                        -type  => 'radio',
                        -name  => 'scope',
                        -value => 'Probe IDs',
                        -title => 'Search probe IDs'
                    }
                )
            )
        ),
        $q->dt('More Search Options:'),
        $q->dd(
            $q->p( $q->a( { -id => 'patternMatcher' }, '+ Pattern to match' ) ),
            $q->div(
                { -id => 'pattern_hint_container', -class => 'dd_collapsible' },
                $q->div(
                    { -id => 'pattern_container', -class => 'input_container' },
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
                            -value => 'Prefix',
                            -title => 'Match word prefixes'
                        }
                    ),
                    $q->input(
                        {
                            -type  => 'radio',
                            -name  => 'match',
                            -value => 'Partial',
                            -title => 'Match word fragments or regular expressions'
                        }
                    )
                ),
                $q->p(
                    { -class => 'hint', -id => 'pattern_part_hint' },
                    <<"END_EXAMPLE_TEXT") ),
Partial matching allows you to enter parts of a word or regular
expressions as search terms.  Example of a regular expression:
<strong>^cyp.b</strong> tells the database to retrieve all genes starting with
<strong>cyp.b</strong> where the period represents any single letter or digit (2, 3, 4,
"a", etc.).  See <a target="_blank" href="http://dev.mysql.com/doc/refman/5.0/en/regexp.html">this page</a> for more
examples.
END_EXAMPLE_TEXT
            $q->p(
                $q->a(
                    { -id => 'locusFilter' },
                    '+ Filter by species / chromosomal location'
                )
            ),
            $q->div(
                { -id => 'locus_container', -class => 'dd_collapsible' },
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
                    $q->div({ -class => 'input_container' },
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
'Enter a numeric interval preceded by chromosome name, for example 16, 7, M, or
X. Leave these fields blank to search all chromosomes.'
                    ),
                ),
            ),
            $q->p( $q->a( { -id => 'outputOpts' }, '+ Output options' ) ),
            $q->div(
                { -id => 'opts_hint_container', -class => 'dd_collapsible' },
                $q->p(
                    $q->div(
                        { -id => 'opts_container', -class => 'input_container' },
                        $q->input(
                            {
                                -type    => 'radio',
                                -name    => 'opts',
                                -value   => 'Basic',
                                -title   => 'List gene names and accession numbers only',
                                -checked => 'checked'
                            }
                        ),
                        $q->input(
                            {
                                -type  => 'radio',
                                -name  => 'opts',
                                -title => 'Also include probe annotation and GO terms',
                                -value => 'Complete',
                            }
                        ),
                        $q->input(
                            {
                                -type  => 'radio',
                                -name  => 'opts',
                                -title => 'Output results in CSV format for easy spreadsheet import',
                                -value => 'Complete (CSV)',
                            }
                        )
                    )
                ),
                $q->p(
                    $q->div(
                        { -id => 'graph_container', -class => 'input_container' },
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
                                -type  => 'radio',
                                -name  => 'graph',
                                -title => 'Plot intensity ratios as fold change for each experiment',
                                -value => 'Fold Change',
                            }
                        ),
                        $q->input(
                            {
                                -type  => 'radio',
                                -name  => 'graph',
                                -title => 'Plot intensity ratios as base 2 logarithm for each experiment',
                                -value => 'Log Ratio',
                            }
                        ),
                    ),
                    $q->p(
                        { -id => 'graph_hint', -class => 'hint' },
'For graphs to display, your browser should support Scalable Vector Graphics (SVG). Internet Explorer (IE)
versions earlier than version nine can only display SVG images via <a target="_blank" href="http://www.adobe.com/svg/viewer/install/" title="Download Adobe SVG plugin">Adobe SVG plugin</a>.'
                    )
                )
            )
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
#       METHOD:  build_InsideTableQuery
#   PARAMETERS:  $type - query type (probe|gene|accnum)
#                tmp_table => $tmpTable - uploaded table to join on
#      RETURNS:  true value
#  DESCRIPTION:  Fills _InsideTableQuery field
#       THROWS:  SGX::Exception::User
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub build_InsideTableQuery {
    my $self      = shift;
    my $predicate = $self->{_Predicate};

    my $probe_spec_fields =
      ( $self->{_scope} eq 'Probe IDs' )
      ? 'rid, reporter, probe_sequence, pid'
      : 'NULL AS rid, NULL AS reporter, NULL AS probe_sequence, NULL AS pid';

    $self->{_InsideTableQuery} = <<"END_InsideTableQuery_probe";
select $probe_spec_fields,
g2.gid, 
g2.accnum,
g2.seqname, 
g2.description, 
g2.gene_note 

from gene g2 right join
(select probe.rid, probe.reporter, probe.probe_sequence, probe.pid,
    accnum from probe left join annotates on annotates.rid=probe.rid left join
gene on gene.gid=annotates.gid $predicate GROUP BY accnum) as g1
on g2.accnum=g1.accnum where rid is not NULL

union

select $probe_spec_fields,
g4.gid, 
g4.accnum,
g4.seqname, 
g4.description, 
g4.gene_note 

from gene g4 right join
(select probe.rid, probe.reporter, probe.probe_sequence, probe.pid,
    seqname from probe left join annotates on annotates.rid=probe.rid left join
    gene on gene.gid=annotates.gid $predicate GROUP BY seqname) as g3
on g4.seqname=g3.seqname where rid is not NULL

END_InsideTableQuery_probe

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
LEFT JOIN annotates USING(gid)
INNER JOIN probe ON probe.rid=COALESCE(annotates.rid, g0.rid)
$sql_subset_by_project
END_ProbeQuery

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  build_ProbeQuery
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub build_ProbeQuery {
    my ( $self, %args ) = @_;
    my $sql_select_fields = '';

    if ( !$args{extra_fields} ) {

        # basic output
        $sql_select_fields = <<"END_select_fields_basic";
probe.rid,
platform.pid,
probe.reporter                          AS 'Probe ID',
platform.pname                          AS 'Platform',
GROUP_CONCAT(
    DISTINCT COALESCE(g0.accnum, '')
    ORDER BY g0.seqname ASC SEPARATOR ' '
)                                       AS 'Accession No.', 
GROUP_CONCAT(
    DISTINCT COALESCE(g0.seqname, '')
    ORDER BY g0.seqname ASC SEPARATOR ' '
)                                       AS 'Gene Symb.',
species.sname                        AS 'Species' 
END_select_fields_basic
    }
    else {

        # extra fields in output
        $sql_select_fields = <<"END_select_fields_extras";
probe.rid,
platform.pid,
probe.reporter                          AS 'Probe ID', 
platform.pname                          AS 'Platform',
GROUP_CONCAT(
    DISTINCT COALESCE(g0.accnum, '')
    ORDER BY g0.seqname ASC SEPARATOR ' '
)                                       AS 'Accession No.', 
GROUP_CONCAT(
    DISTINCT COALESCE(g0.seqname, '')
    ORDER BY g0.seqname ASC SEPARATOR ' '
)                                       AS 'Gene Symb.', 
species.sname                        AS 'Species', 
probe.probe_sequence                    AS 'Probe Sequence',
GROUP_CONCAT(
    DISTINCT g0.description ORDER BY g0.seqname ASC SEPARATOR '; '
)                                       AS 'Offic. Gene Name',
GROUP_CONCAT(
    DISTINCT gene_note ORDER BY g0.seqname ASC SEPARATOR '; '
)                                       AS 'Gene Ontology'
END_select_fields_extras
    }

    # only return results for platforms that belong to the current working
    # project (as determined through looking up studies linked to the current
    # project).
    my $curr_proj             = $self->{_WorkingProject};
    my $sql_subset_by_project = '';
    if ( defined($curr_proj) && $curr_proj ne '' ) {
        $curr_proj             = $self->{_dbh}->quote($curr_proj);
        $sql_subset_by_project = <<"END_sql_subset_by_project"
INNER JOIN study ON study.pid=platform.pid
INNER JOIN ProjectStudy USING(stid) 
WHERE prid=$curr_proj 
END_sql_subset_by_project
    }

    #---------------------------------------------------------------------------
    # Filter by chromosomal location (use platform table to look up species when
    # only species is specified and not an actual chromosomal location).
    #---------------------------------------------------------------------------
    my ( $subquery, $subparam ) = $self->build_location_predparam();
    my $location_predicate = '';
    my $species_predicate  = '';
    my $join_species_on    = 'platform.sid';
    if ( @$subparam == 1 ) {

        #species only
        $species_predicate = 'AND platform.sid=?';
        push @{ $self->{_FilterItems} }, @$subparam;
    }
    elsif ( @$subparam > 1 ) {
        $location_predicate =
          'INNER JOIN location ON probe.rid=location.rid AND ' . $subquery;
        push @{ $self->{_FilterItems} }, @$subparam;
        $join_species_on = 'location.sid';
    }

    my $InsideTableQuery = $self->{_InsideTableQuery};
    $self->{_ProbeQuery} = <<"END_ProbeQuery";
SELECT
$sql_select_fields
FROM ( $InsideTableQuery ) AS g0
LEFT JOIN annotates USING(gid)
INNER JOIN probe ON probe.rid=COALESCE(annotates.rid, g0.rid)
$location_predicate
INNER JOIN platform ON probe.pid=platform.pid $species_predicate
LEFT JOIN species ON species.sid=$join_species_on
INNER JOIN (SELECT pid, pname, sname FROM platform LEFT JOIN species USING(sid)) AS platform_species ON platform_species.pid=probe.pid
$sql_subset_by_project
GROUP BY probe.rid
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

    $self->build_SearchPredicate();
    $self->build_InsideTableQuery();
    $self->build_ProbeQuery( extra_fields => ( $self->{_opts} ne 'Basic' ) );

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
            'Probe IDs'         => '1',
            'Accession Numbers' => '3',
            'Gene Names'        => '4'
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
var probelist = %s;
var url_prefix = "%s";
var show_graphs = "%s";
var extra_fields = "%s";
var project_id = "%s";
END_JSON_DATA
            $type_to_column{$type},
            encode_json(
                ( $match eq 'Full Word' )
                ? +{ map { lc($_) => undef } @{ $self->{_SearchTerms} } }
                : $self->{_SearchTerms}
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


