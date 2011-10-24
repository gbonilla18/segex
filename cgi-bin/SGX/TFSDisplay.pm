package SGX::TFSDisplay;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;

use SGX::Debug;
require Math::BigInt;
use JSON qw/encode_json/;
use SGX::Abstract::Exception ();
use SGX::Util qw/car bind_csv_handle/;

#===  FUNCTION  ================================================================
#         NAME:  get_tfs
#      PURPOSE:  Get total flagsum (TFS), which is a sum of absolute flagsum and
#                directional flagsum.
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_tfs {
    my ( $abs_fs, $dir_fs, $num ) = @_;
    return sprintf(
        "$abs_fs.%0${num}s",
        Math::BigInt->badd(
            substr( unpack( 'b32', pack( 'V', $abs_fs ) ), 0, $num ),
            substr( unpack( 'b32', pack( 'V', $dir_fs ) ), 0, $num )
        )
    );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::TFSDisplay
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

    $self->set_attributes( _title => 'View Slice' );

    # find out what the current project is set to
    $self->getSessionOverrideCGI();

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  TFSDisplay
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my $self = shift;
    $self->SUPER::init();

    $self->loadDataFromSubmission();    # sets _format attribute

    # two lines below modify action value and therefore affect which hook will
    # get called
    my $action = $self->{_format} || '';
    $self->{_cgi}->param( -name => 'b', -value => $action );

    $self->register_actions(
        CSV => { head => 'CSV_head', body => 'CSV_body' } );

    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  TFSDisplay
#       METHOD:  CSV_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub CSV_head {
    my $self = shift;
    my ( $s, $js_src_yui, $js_src_code ) =
      @$self{qw{_UserSession _js_src_yui _js_src_code}};

    #Clear our headers so all we get back is the CSV file.
    print $self->{_cgi}->header(
        -type       => 'text/csv',
        -attachment => 'results.csv',
        -cookie     => $s->cookie_array()
    );

    $s->commit();
    $self->getPlatformData();
    $self->loadAllData();

    # print CSV and exit
    $self->displayTFSInfoCSV();
    exit;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  TFSDisplay
#       METHOD:  default_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Override CRUD default_head
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_head {
    my $self = shift;
    my ( $s, $js_src_yui, $js_src_code ) =
      @$self{qw{_UserSession _js_src_yui _js_src_code}};

    push @{ $self->{_css_src_yui} },
      (
        'paginator/assets/skins/sam/paginator.css',
        'datatable/assets/skins/sam/datatable.css'
      );
    push @$js_src_yui,
      (
        'yahoo-dom-event/yahoo-dom-event.js', 'element/element-min.js',
        'paginator/paginator-min.js',         'datasource/datasource-min.js',
        'datatable/datatable-min.js',         'yahoo/yahoo.js'
      );

    $self->loadTFSData();
    push @$js_src_code, { -code => $self->displayTFSInfo() };
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  TFSDisplay
#       METHOD:  default_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_body {
    my $self = shift;

    my $q = $self->{_cgi};

    return
      $q->h2( { -id => 'summary_caption' }, '' ),
      $q->div( $q->a( { -id => 'summ_astext' }, 'View as plain text' ) ),
      $q->div( { -id => 'summary_table', -class => 'table_cont' }, '' ),
      $q->h2( { -id => 'tfs_caption' }, '' ),
      $q->div( $q->a( { -id => 'tfs_astext' }, 'View as plain text' ) ),
      $q->div( { -id => 'tfs_table', -class => 'table_cont' } );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::TFSDisplay
#       METHOD:  loadDataFromSubmission
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  LOAD DATA FROM FORM
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadDataFromSubmission {
    my $self = shift;
    my $q    = $self->{_cgi};

    # The $self->{_fs} parameter is the flagsum for which the data will be
    # filtered If the $self->{_fs} is zero or undefined, all data will be
    # output.
    my $split_on_commas = qr/\s*,\s*/;
    $self->{_eids} =
      [ map { [ split /\|/ ] } split( $split_on_commas, $q->param('eid') ) ];
    $self->{_reverses} = [ split( $split_on_commas, $q->param('rev') ) ];
    $self->{_fcs}      = [ split( $split_on_commas, $q->param('fc') ) ];
    $self->{_pvals}    = [ split( $split_on_commas, $q->param('pval') ) ];

    $self->{_allProbes}     = $q->param('allProbes')    || '';
    $self->{_searchFilters} = $q->param('searchFilter') || '';
    $self->{_fs}            = $q->param('get')          || '';
    $self->{_opts}          = $q->param('opts')         || '0';

    if ( ( car $q->param('get') ) =~ m/^\s*TFS\s*(\d*)\s*\((CSV|HTML)\)\s*$/i )
    {
        ( $self->{_fs}, $self->{_format} ) = ( $1, $2 );
        $self->{_fs} = undef if $self->{_fs} eq '';
    }
    else {
        ( $self->{_fs}, $self->{_format} ) = ( undef, undef );
    }

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
    my $self = shift;
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
#        CLASS:  SGX::TFSDisplay
#       METHOD:  loadTFSData
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  LOAD TFS DATA
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadTFSData {
    my $self = shift;

    # Build the SQL query that does the TFS calculation
    my $having =
      ( defined( $self->{_fs} ) ) ? "HAVING abs_fs=$self->{_fs}" : '';

    # index of the column that is the beginning of the "numeric" half of the
    # table (required for table sorting)
    $self->{_numStart} = 5;

    #If we got a list to filter on, build the string.
    #
    # :TODO:07/07/2011 12:38:40:es: SQL injection risk: no validation done
    # one _searchFilters before being inserted into WHERE statement.
    # Fix this by using prepare/execute with placeholders.
    my $probeListQuery =
      ( defined( $self->{_searchFilters} ) && $self->{_searchFilters} ne '' )
      ? " WHERE rid IN (" . $self->{_searchFilters} . ") "
      : '';

    my $i = 1;

    my @query_proj;
    my @query_join;
    my @query_body;
    my @query_titles;
    my $allProbes = $self->{_allProbes};
    foreach my $eid ( @{ $self->{_eids} } ) {
        my ( $currentSTID, $currentEID ) = @$eid;

        my ( $fc, $pval ) =
          ( $self->{_fcs}->[ $i - 1 ], $self->{_pvals}->[ $i - 1 ] );

        my $abs_flag = 1 << $i - 1;
        my $dir_flag =
          ( $self->{_reverses}->[ $i - 1 ] ) ? "$abs_flag,0" : "0,$abs_flag";
        push @query_proj,
          ( $self->{_reverses}->[ $i - 1 ] )
          ? "1/m$i.ratio AS \'$i: Ratio\', m$i.pvalue AS \'$i: P-value\'"
          : "m$i.ratio AS \'$i: Ratio\', m$i.pvalue AS \'$i: P-value\'";

        if ( $self->{_opts} > 0 ) {
            push @query_proj,
              ( $self->{_reverses}->[ $i - 1 ] )
              ? "-m$i.foldchange AS \'$i: Fold Change\'"
              : "m$i.foldchange AS \'$i: Fold Change\'";
            push @query_proj,
              ( $self->{_reverses}->[ $i - 1 ] )
              ? "IFNULL(m$i.intensity2,0) AS \'$i: Intensity-1\', IFNULL(m$i.intensity1,0) AS \'$i: Intensity-2\'"
              : "IFNULL(m$i.intensity1,0) AS \'$i: Intensity-1\', IFNULL(m$i.intensity2,0) AS \'$i: Intensity-2\'";
            push @query_proj, "m$i.pvalue AS \'$i: P-value\'";
        }

        push @query_join,
          "LEFT JOIN microarray m$i ON m$i.rid=d2.rid AND m$i.eid=$currentEID";

        #This is part of the query when we are including all probes.
        push @query_body, ($allProbes)
          ? <<"END_yes_allProbes"
SELECT
    rid, 
    IF(pvalue < $pval AND ABS(foldchange) > $fc, $abs_flag, 0) AS abs_flag,
    IF(pvalue < $pval AND ABS(foldchange) > $fc, 
       IF(foldchange > 0, $dir_flag), 
       0
    ) AS dir_flag
FROM microarray
WHERE eid=$currentEID
END_yes_allProbes
          : <<"END_no_allProbes";
SELECT
    rid, 
    $abs_flag AS abs_flag,
    IF(foldchange > 0, $dir_flag) AS dir_flag
FROM microarray 
WHERE eid = $currentEID 
  AND pvalue < $pval 
  AND ABS(foldchange) > $fc
END_no_allProbes

        # account for sample order when building title query
        my $title =
          ( $self->{_reverses}->[ $i - 1 ] )
          ? "experiment.sample1, ' / ', experiment.sample2"
          : "experiment.sample2, ' / ', experiment.sample1";

        push @query_titles, <<"END_query_titles";
SELECT 
    experiment.eid, 
    CONCAT(study.description, ': ', $title) AS title, 
    CONCAT($title) AS experimentHeading,
    study.description,
    experiment.ExperimentDescription 
FROM experiment 
NATURAL JOIN StudyExperiment 
NATURAL JOIN study 
WHERE eid=$currentEID AND study.stid = $currentSTID
END_query_titles

        $i++;
    }

    my $dbh = $self->{_dbh};
    my $sth = $dbh->prepare( join( ' UNION ALL ', @query_titles ) );
    my $rc  = $sth->execute;
    $self->{_headerRecords} = $sth->fetchall_hashref('eid');
    $sth->finish;

    if ( $self->{_opts} > 1 ) {
        $self->{_numStart} += 3;
        unshift @query_proj,
          (
            qq{probe.probe_sequence AS 'Probe Sequence'},
qq{GROUP_CONCAT(DISTINCT IF(gene.description='', NULL, gene.description) SEPARATOR '; ') AS 'Gene Description'},
            qq{platform.species AS 'Species'}
          );
    }

    my $d1SubQuery   = join( ' UNION ALL ', @query_body );
    my $selectSQL    = join( ',',           @query_proj );
    my $predicateSQL = join( "\n",          @query_join );

    # pad TFS decimal portion with the correct number of zeroes
    my $query = <<"END_query";
SELECT
    abs_fs, 
    dir_fs, 
    probe.reporter AS Probe, 
    GROUP_CONCAT(DISTINCT accnum SEPARATOR '+') AS 'Accession Number', 
    GROUP_CONCAT(DISTINCT seqname SEPARATOR '+') AS 'Gene', 
    $selectSQL
FROM (
    SELECT 
        rid, 
        BIT_OR(abs_flag) AS abs_fs, 
        BIT_OR(dir_flag) AS dir_fs 
    FROM ($d1SubQuery) AS d1 
    $probeListQuery
    GROUP BY rid $having
) AS d2
$predicateSQL
LEFT JOIN probe     ON d2.rid        = probe.rid
LEFT JOIN annotates ON d2.rid        = annotates.rid
LEFT JOIN gene      ON annotates.gid = gene.gid
LEFT JOIN platform  ON platform.pid  = probe.pid
GROUP BY probe.rid
ORDER BY abs_fs DESC
END_query

    $self->{_Records}     = $dbh->prepare($query);
    $self->{_RowCountAll} = $self->{_Records}->execute;

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::TFSDisplay
#       METHOD:  getPlatformData
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  LOAD PLATFORM DATA FOR CSV OUTPUT
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getPlatformData {
    my $self = shift;

    my $dbh = $self->{_dbh};

    my @eidList = map { $_->[1] } @{ $self->{_eids} };

    my $placeholders =
      ( @eidList > 0 )
      ? join( ',', map { '?' } @eidList )
      : 'NULL';

  # :TODO:07/25/2011 02:39:05:es: Since experiments from different platforms
  # cannot be comoared using Compare Experiments, this query is a little bit too
  # fat for what we need.
    my $singleItemQuery = <<"END_LoadQuery";
SELECT
    platform.pname              AS 'Platform',
    platform.def_f_cutoff       AS 'FC-cutoff',
    platform.def_p_cutoff       AS 'P-cutoff',
    platform.species            AS 'Species',
    IF(isAnnotated, 'Y', 'N')   AS 'Is Annotated',
    COUNT(probe.rid)            AS 'ProbeCount',
    COUNT(probe.probe_sequence) AS 'Sequences Loaded',
    COUNT(probe.location)       AS 'Probe Locations',
    COUNT(annotates.gid)        AS 'Accession Numbers',
    COUNT(gene.seqname)         AS 'Gene Names'
FROM platform
LEFT JOIN probe      ON probe.pid = platform.pid
LEFT JOIN annotates  ON annotates.rid = probe.rid
LEFT JOIN gene       ON gene.gid = annotates.gid
WHERE platform.pid IN (SELECT DISTINCT pid FROM experiment WHERE eid IN($placeholders))
GROUP BY platform.pid
END_LoadQuery

    my $sth = $dbh->prepare($singleItemQuery);
    my $rc  = $sth->execute(@eidList);
    $self->{_FieldNames}   = $sth->{NAME};
    $self->{_DataPlatform} = $sth->fetchall_arrayref;
    $sth->finish;

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::TFSDisplay
#       METHOD:  loadAllData
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  LOAD ALL DATA FOR CSV OUTPUT
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadAllData {
    my $self = shift;

    #This is the different parts of the experiment and titles query.
    my @query_body;
    my @query_proj;
    my @query_join;
    my @query_titles;

    #If we got a list to filter on, build the string.
    my $probeListQuery =
      ( defined( $self->{_searchFilters} ) && $self->{_searchFilters} ne '' )
      ? " WHERE rid IN (" . $self->{_searchFilters} . ") "
      : '';

    my $i = 1;

    foreach my $eid ( @{ $self->{_eids} } ) {
        my ( $currentSTID, $currentEID ) = @$eid;

        my ( $fc, $pval ) =
          ( $self->{_fcs}->[ $i - 1 ], $self->{_pvals}->[ $i - 1 ] );
        my $abs_flag = 1 << $i - 1;
        my $dir_flag =
          ( $self->{_reverses}->[ $i - 1 ] ) ? "$abs_flag,0" : "0,$abs_flag";

        push @query_proj,
          ( $self->{_reverses}->[ $i - 1 ] )
          ? "1/m$i.ratio AS \'$i: Ratio\'"
          : "m$i.ratio AS \'$i: Ratio\'";

        push @query_proj,
          ( $self->{_reverses}->[ $i - 1 ] )
          ? "-m$i.foldchange AS \'$i: Fold Change\'"
          : "m$i.foldchange AS \'$i: Fold Change\'";

        push @query_proj,
          ( $self->{_reverses}->[ $i - 1 ] )
          ? "IFNULL(m$i.intensity2,0) AS \'$i: Intensity-1\', IFNULL(m$i.intensity1,0) AS \'$i: Intensity-2\'"
          : "IFNULL(m$i.intensity1,0) AS \'$i: Intensity-1\', IFNULL(m$i.intensity2,0) AS \'$i: Intensity-2\'";

        push @query_proj, "m$i.pvalue AS \'$i: P\'";

        push @query_join,
          "LEFT JOIN microarray m$i ON m$i.rid=d2.rid AND m$i.eid=$currentEID";

        push @query_body, ( $self->{_allProbes} )
          ? <<"END_yes_allProbesCSV"
SELECT
    rid,
    IF(pvalue < $pval AND ABS(foldchange) > $fc, $abs_flag, 0) AS abs_flag,
    IF(pvalue < $pval AND ABS(foldchange) > $fc, IF(foldchange > 0, $dir_flag), 0) AS dir_flag
FROM microarray
WHERE eid=$currentEID
END_yes_allProbesCSV
          : <<"END_no_allProbesCSV";
SELECT
    rid, 
    $abs_flag AS abs_flag,
    IF(foldchange > 0, $dir_flag) AS dir_flag
FROM microarray 
WHERE eid = $currentEID 
  AND pvalue < $pval 
  AND ABS(foldchange) > $fc
END_no_allProbesCSV

        # account for sample order when building title query
        my $title =
          ( $self->{_reverses}->[ $i - 1 ] )
          ? "experiment.sample1, ' / ', experiment.sample2"
          : "experiment.sample2, ' / ', experiment.sample1";

        push @query_titles, <<"END_query_titlesCSV";
SELECT
    experiment.eid,
    CONCAT(study.description, ': ', $title) AS title,
    CONCAT($title) AS experimentHeading,
    study.description,
    experiment.ExperimentDescription 
FROM experiment 
NATURAL JOIN StudyExperiment 
NATURAL JOIN study 
WHERE eid=$currentEID AND study.stid = $currentSTID
END_query_titlesCSV

        $i++;
    }

    #This is the having part of the data query.
    my $having =
      ( defined( $self->{_fs} ) && $self->{_fs} )
      ? "HAVING abs_fs=$self->{_fs}"
      : '';

    unshift @query_proj,
      (
        qq{probe.probe_sequence AS 'Probe Sequence'},
qq{GROUP_CONCAT(DISTINCT IF(gene.description='', NULL, gene.description) SEPARATOR '; ') AS 'Gene Description'},
qq{GROUP_CONCAT(DISTINCT gene_note ORDER BY seqname ASC SEPARATOR '; ') AS 'Gene Ontology'},
        qq{platform.species AS 'Species'}
      );

    my $d1SubQuery   = join( ' UNION ALL ', @query_body );
    my $selectSQL    = join( ',',           @query_proj );
    my $predicateSQL = join( "\n",          @query_join );

    # pad TFS decimal portion with the correct number of zeroes
    my $query = <<"END_queryCSV";
SELECT
    abs_fs, 
    dir_fs, 
    probe.reporter AS Probe, 
    GROUP_CONCAT(DISTINCT accnum SEPARATOR '+') AS 'Accession Number', 
    GROUP_CONCAT(DISTINCT seqname SEPARATOR '+') AS 'Gene', 
    $selectSQL
FROM (
    SELECT
       rid, 
       BIT_OR(abs_flag) AS abs_fs, 
       BIT_OR(dir_flag) AS dir_fs 
    FROM ($d1SubQuery) AS d1 
    $probeListQuery
    GROUP BY rid $having
) AS d2
$predicateSQL
LEFT JOIN probe     ON d2.rid        = probe.rid
LEFT JOIN annotates ON d2.rid        = annotates.rid
LEFT JOIN gene      ON annotates.gid = gene.gid
LEFT JOIN platform  ON platform.pid  = probe.pid
GROUP BY probe.rid
ORDER BY abs_fs DESC
END_queryCSV

    #Run the query for the experiment headers.
    my $dbh = $self->{_dbh};
    my $sth = $dbh->prepare( join( ' UNION ALL ', @query_titles ) );
    my $rc  = $sth->execute;

    # :TODO:10/24/2011 11:48:10:es: Do we really need a hashref here? Maybe an
    # arrayref will do?
    $self->{_headerRecords} = $sth->fetchall_hashref('eid');
    $sth->finish;

    #Run the query for the actual data records.
    $self->{_Records}     = $dbh->prepare($query);
    $self->{_RowCountAll} = $self->{_Records}->execute;
    $self->{_Data}        = $self->{_Records}->fetchall_arrayref;

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::TFSDisplay
#       METHOD:  displayTFSInfoCSV
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  DISPLAY PLATFORM,EXPERIMENT INFO, AND EXPERIMENT DATA TO A CSV
#  FILE
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub displayTFSInfoCSV {
    my $self = shift;

    my $print = bind_csv_handle( \*STDOUT );

    # Report Header
    $print->( [ 'Compare Experiments Report', scalar localtime() ] );
    $print->( [ 'Generated By',               $self->{_UserFullName} ] );
    $print->( [ 'Working Project',            $self->{_WorkingProjectName} ] );
    $print->();

    # Print Platform info.
    $print->( $self->{_FieldNames} );
    $print->($_) for @{ $self->{_DataPlatform} };
    $print->();

    # Print Experiment info header.
    $print->(
        [
            'Experiment Number',
            'Study Description',
            'Experiment Heading',
            'Experiment Description',
            '|Fold Change| >',
            'P'
        ]
    );

    # This is the line with the experiment name and eid above the data columns.
    my @experimentNameHeader = (undef) x 8;

    my $eid_count = @{ $self->{_eids} };
    my @eidList;

    # Print Experiment info.
    for ( my $i = 0 ; $i < $eid_count ; $i++ ) {
        my ( $currentSTID, $currentEID ) = @{ $self->{_eids}->[$i] };

        push @eidList, $currentEID;

        # Form the line that displays experiment names above data columns.
        push @experimentNameHeader,
          $currentEID . ':' . $self->{_headerRecords}->{$currentEID}->{title},
          (undef) x 4;

        my @currentLine = (
            $currentEID,
            $self->{_headerRecords}->{$currentEID}->{description},
            $self->{_headerRecords}->{$currentEID}->{experimentHeading},
            $self->{_headerRecords}->{$currentEID}->{ExperimentDescription},
            $self->{_fcs}->[$i],
            $self->{_pvals}->[$i]
        );

        # Test for bit presence and print out 1 if present, 0 if absent
        push( @currentLine, ( 1 << $i & $self->{_fs} ) ? 'x' : '' )
          if defined $self->{_fs};

        $print->( \@currentLine );
    }
    $print->();

    # Calculate TFS along with distinct counts
    my %TFSCounts;
    my $data_array = $self->{_Data};
    foreach (@$data_array) {

        # for each row
        my $currentTFS = get_tfs( shift @$_, shift @$_, $eid_count );
        unshift @$_, $currentTFS;
        $TFSCounts{$currentTFS} =
          ( defined $TFSCounts{$currentTFS} )
          ? 1 + $TFSCounts{$currentTFS}
          : 1;
    }

    $print->( ['TFS Summary'] );
    $print->( [ 'TFS' => 'Probe Count' ] );
    $print->( [ $_ => $TFSCounts{$_} ] )
      for sort { $TFSCounts{$b} <=> $TFSCounts{$a} }
      keys %TFSCounts;
    $print->();

    # Print header line.
    $print->( \@experimentNameHeader );

    # Experiment Data header.
    $print->(
        [
            'TFS',
            'Probe ID',
            'Accession Number',
            'Gene',
            'Probe Sequence',
            'Gene Name',
            'Gene Ontology',
            'Species',
            map {
                (
                    "$_:Ratio",       "$_:Fold Change",
                    "$_:Intensity-1", "$_:Intensity-2",
                    "$_:P"
                  )
              } @eidList
        ]
    );

    # Print Experiment data sorting by TFS in descending order, then by gene
    # name in ascending order.
    $print->($_)
      for sort { $b->[0] cmp $a->[0] || ( $a->[3] || '' ) cmp( $b->[3] || '' ) }
      @$data_array;

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::TFSDisplay
#       METHOD:  displayTFSInfo
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Display TFS info
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub displayTFSInfo {
    my $self = shift;
    my $q    = $self->{_cgi};

    my @tmpArrayHead;
    my $eid_count = @{ $self->{_eids} };
    for ( my $i = 0 ; $i < $eid_count ; $i++ ) {
        my ( $currentSTID, $currentEID ) = @{ $self->{_eids}->[$i] };
        my $this_eid                 = $self->{_headerRecords}->{$currentEID};
        my $currentTitle             = $this_eid->{title};
        my $currentStudyDescription  = $this_eid->{description};
        my $currentExperimentHeading = $this_eid->{experimentHeading};
        my $currentExperimentDescription = $this_eid->{ExperimentDescription};

        # test for bit presence (store in 7:)
        push @tmpArrayHead,
          [
            ( $i + 1 ),
            $currentEID,
            $currentStudyDescription,
            $currentExperimentHeading,
            $currentExperimentDescription,
            $self->{_fcs}->[$i],
            $self->{_pvals}->[$i],
            (
                ( defined( $self->{_fs} ) && 1 << $i & $self->{_fs} )
                ? 'x'
                : ''
            )
          ];
    }

    my $out = sprintf(
        'var summary = %s;',
        encode_json(
            {
                caption => 'Experiments compared',
                headers => [
                    '&nbsp;',
                    'Experiment Number',
                    'Study Description',
                    'Sample2/Sample1',
                    'Experiment Description',
                    '&#124;Fold Change&#124; &gt;',
                    'P &lt;',
                    '&nbsp;'
                ],
                parsers => [
                    'number', 'number', 'string', 'string',
                    'string', 'number', 'number', 'string'
                ],
                records => \@tmpArrayHead
            }
        )
    );

# Fields with indexes less num_start are formatted as strings,
# fields with indexes equal to or greater than num_start are formatted as numbers.
    my @table_header;
    my @table_parser;
    my @table_format;

    for ( my $j = 2 ; $j < $self->{_numStart} ; $j++ ) {
        push @table_header, $self->{_Records}->{NAME}->[$j];
        push @table_parser, 'string';
        push @table_format, 'formatText';
    }

    for (
        my $j = $self->{_numStart} ;
        $j < @{ $self->{_Records}->{NAME} } ;
        $j++
      )
    {
        push @table_header, $self->{_Records}->{NAME}->[$j];
        push @table_parser, 'number';
        push @table_format, 'formatNumber';
    }

    my %format_template;
    {
        my $find_probes = $q->a(
            {
                -title  => 'Find all %1$ss related to %1$s {0}',
                -target => '_blank',
                -href   => $self->url( -absolute => 1 )
                  . '?a=findProbes&b=Search&match=full&graph=on&type=%1$s&terms={0}',
            },
            '{0}'
        );
        $format_template{probe}  = sprintf( $find_probes, 'probe' );
        $format_template{accnum} = sprintf( $find_probes, 'accnum' );
        $format_template{gene}   = sprintf( $find_probes, 'gene' );
    }

    $table_format[0] = 'formatProbe';
    $table_format[1] = 'formatAccNum';
    $table_format[2] = 'formatGene';

    if ( $self->{_opts} > 1 ) {
        $table_format[3] = 'formatProbeSequence';
        $format_template{probeseq} = $q->a(
            {
                -title  => 'UCSC BLAT on DNA',
                -target => '_blank',
                -href =>
'http://genome.ucsc.edu/cgi-bin/hgBlat?org={1}&type=DNA&userSeq={0}'
            },
            '{0}'
        );
    }

    #---------------------------------------------------------------------------
    #  print table body
    #---------------------------------------------------------------------------
    my $data_array = $self->{_Records}->fetchall_arrayref;
    $self->{_Records}->finish;

    unshift( @$_, get_tfs( shift @$_, shift @$_, $eid_count ) )
      for @$data_array;

    $out .= sprintf(
        'var tfs = %s;',
        encode_json(
            {
                caption => sprintf( 'Your selection includes %d probes',
                    $self->{_RowCountAll} ),
                headers => [ 'TFS',        @table_header ],
                parsers => [ 'string',     @table_parser ],
                formats => [ 'formatText', @table_format ],
                frm_tpl => \%format_template,
                records => [
                    sort {
                        $b->[0] cmp $a->[0]
                          || ( $a->[3] || '' ) cmp( $b->[3] || '' )
                      } @$data_array
                ]
            }
        )
    );

    return <<"END_JS";
$out
YAHOO.util.Event.addListener("summ_astext", "click", export_table, summary, true);
YAHOO.util.Event.addListener("tfs_astext", "click", export_table, tfs, true);
YAHOO.util.Event.addListener(window, "load", function() {
    var Dom = YAHOO.util.Dom;
    var Formatter = YAHOO.widget.DataTable.Formatter;
    var lang = YAHOO.lang;

    Dom.get("summary_caption").innerHTML = summary.caption;
    var summary_table_defs = [];
    var summary_schema_fields = [];
    for (var i=0, sh = summary.headers, sp = summary.parsers, al=sh.length; i<al; i++) {
        summary_table_defs.push({key:String(i), sortable:true, label:sh[i]});
        summary_schema_fields.push({key:String(i), parser:sp[i]});
    }
    var summary_data = new YAHOO.util.DataSource(summary.records);
    summary_data.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    summary_data.responseSchema = { fields: summary_schema_fields };
    var summary_table = new YAHOO.widget.DataTable("summary_table", summary_table_defs, summary_data, {});

    Formatter.formatProbe = function (elCell, oRecord, oColumn, oData) {
        var clean = (oData === null) ? '' : oData;
        elCell.innerHTML = lang.substitute(tfs.frm_tpl.probe, {"0":clean});
    }
    Formatter.formatAccNum = function (elCell, oRecord, oColumn, oData) {
        var clean = (oData === null) ? '' : oData;
        elCell.innerHTML = lang.substitute(tfs.frm_tpl.accnum, {"0":clean});
    }
    Formatter.formatGene = function (elCell, oRecord, oColumn, oData) {
        var clean = (oData === null) ? '' : oData;
        elCell.innerHTML = lang.substitute(tfs.frm_tpl.gene, {"0":clean});
    }
    Formatter.formatProbeSequence = function (elCell, oRecord, oColumn, oData) {
        var clean = (oData === null) ? '' : oData;
        elCell.innerHTML = lang.substitute(lang.substitute(tfs.frm_tpl.probeseq, {"0":clean}),{"1":oRecord.getData("6")});

    }
    Formatter.formatNumber = function(elCell, oRecord, oColumn, oData) {
        // Overrides the built-in formatter
        if (oData !== null) {
            elCell.innerHTML = oData.toPrecision(3);
        }
    }
    Dom.get("tfs_caption").innerHTML = tfs.caption;
    var tfs_table_defs = [];
    var tfs_schema_fields = [];
    for (var i=0, th = tfs.headers, tp = tfs.parsers, tf=tfs.formats, al=th.length; i<al; i++) {
        tfs_table_defs.push({key:String(i), sortable:true, label:th[i], formatter:tf[i]});
        tfs_schema_fields.push({key:String(i), parser:tp[i]});
    }
    var tfs_config = {
        paginator: new YAHOO.widget.Paginator({
            rowsPerPage: 500 
        })
    };
    var tfs_data = new YAHOO.util.DataSource(tfs.records);
    tfs_data.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    tfs_data.responseSchema = { fields: tfs_schema_fields };
    var tfs_table = new YAHOO.widget.DataTable("tfs_table", tfs_table_defs, tfs_data, tfs_config);
});
END_JS
}

1;

__END__


=head1 NAME

SGX::TFSDisplay

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 AUTHORS
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut


