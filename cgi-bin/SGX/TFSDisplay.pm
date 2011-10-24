package SGX::TFSDisplay;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;

#use SGX::Debug;
require Math::BigInt;
use JSON qw/encode_json/;
use SGX::Abstract::Exception ();

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

    $self->set_attributes( _title => 'View Slice', );

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

    # :TODO:08/06/2011 14:25:39:es: instead of printing directly to
    # browser window in the function below, have it return a string

    # Dynamically load Text::CSV module (use require)

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

    my $q = $self->{_cgi};

    # The $self->{_fs} parameter is the flagsum for which the data will be
    # filtered If the $self->{_fs} is zero or undefined, all data will be
    # output.
    my $split_on_commas = qr/\s*,\s*/;
    my @eidsArray       = split( $split_on_commas, $q->param('eid') );
    my @reversesArray   = split( $split_on_commas, $q->param('rev') );
    my @fcsArray        = split( $split_on_commas, $q->param('fc') );
    my @pvalArray       = split( $split_on_commas, $q->param('pval') );

    $self->{_eids}     = \@eidsArray;
    $self->{_reverses} = \@reversesArray;
    $self->{_fcs}      = \@fcsArray;
    $self->{_pvals}    = \@pvalArray;

    $self->{_allProbes}     = $q->param('allProbes')    || '';
    $self->{_searchFilters} = $q->param('searchFilter') || '';
    $self->{_fs}            = $q->param('get')          || '';
    $self->{_opts}          = $q->param('opts')         || '0';

    my $get   = $q->param('get');
    my $regex = qr/^\s*TFS\s*(\d*)\s*\((CSV|HTML)\)\s*$/i;

    if ( $get =~ m/$regex/i ) {
        ( $self->{_fs}, $self->{_format} ) = ( $1, $2 );
    }
    else {
        ( $self->{_fs}, $self->{_format} ) = ( undef, undef );
    }
    $self->{_fs} = undef if $self->{_fs} eq '';

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

        #The EID is actually STID|EID. We need to split the string on '|' and
        #extract the app
        my ( $currentSTID, $currentEID ) = split( /\|/, $eid );

        my ( $fc, $pval ) =
          ( $self->{_fcs}->[ $i - 1 ], $self->{_pvals}->[ $i - 1 ] );

        my $abs_flag = 1 << $i - 1;
        my $dir_flag =
          ( $self->{_reverses}->[ $i - 1 ] ) ? "$abs_flag,0" : "0,$abs_flag";
        push @query_proj,
          ( $self->{_reverses}->[ $i - 1 ] )
          ? "1/m$i.ratio AS \'$i: Ratio\', m$i.pvalue"
          : "m$i.ratio AS \'$i: Ratio\', m$i.pvalue";

        if ( $self->{_opts} > 0 ) {
            push @query_proj,
              ( $self->{_reverses}->[ $i - 1 ] )
              ? "-m$i.foldchange AS \'$i: Fold Change\'"
              : "m$i.foldchange AS \'$i: Fold Change\'";
            push @query_proj,
              ( $self->{_reverses}->[ $i - 1 ] )
              ? "IFNULL(m$i.intensity2,0) AS \'$i: Intensity-1\', IFNULL(m$i.intensity1,0) AS \'$i: Intensity-2\'"
              : "IFNULL(m$i.intensity1,0) AS \'$i: Intensity-1\', IFNULL(m$i.intensity2,0) AS \'$i: Intensity-2\'";
            push @query_proj, "m$i.pvalue AS \'$i: P\'";
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

    my @eidList;
    foreach ( @{ $self->{_eids} } ) {

        #The EID is actually STID|EID. We need to split the string on '|'.
        my ( $currentSTID, $currentEID ) = split /\|/;
        push @eidList, $currentEID;
    }

    my $placeholders =
      ( @eidList > 0 )
      ? join( ',', map { '?' } @eidList )
      : 'NULL';

  # :TODO:07/25/2011 02:39:05:es: Since experiments from different platforms
  # cannot be comoared using Compare Experiments, this query is a little bit too
  # fat for what we need.
    my $singleItemQuery = <<"END_LoadQuery";
SELECT 
    platform.pname, 
    platform.def_f_cutoff, 
    platform.def_p_cutoff, 
    platform.species,
    IF(isAnnotated, 'Y', 'N')                           AS 'Is Annotated',
    COUNT(probe.rid)                                    AS 'ProbeCount',
    SUM(IF(IFNULL(probe.probe_sequence,'') <> '',1,0))  AS 'Sequences Loaded',
    SUM(IF(IFNULL(annotates.gid,'') <> '',1,0))         AS 'Accession Number IDs',
    SUM(IF(IFNULL(gene.seqname,'') <> '',1,0))          AS 'Gene Names',
    SUM(IF(IFNULL(gene.description,'') <> '',1,0))      AS 'Gene Description'    
FROM platform
INNER JOIN probe      ON probe.pid = platform.pid
INNER JOIN experiment ON platform.pid = experiment.pid
LEFT JOIN annotates   ON annotates.rid = probe.rid
LEFT JOIN gene        ON gene.gid = annotates.gid
WHERE experiment.eid  IN ($placeholders)
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
        my ( $currentSTID, $currentEID ) = split( /\|/, $eid );

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

    #Print a line to tell us what report this is.
    my $workingProjectText = $self->{_WorkingProjectName};
    my $generatedByText    = $self->{_UserFullName};

    #Print a line to tell us what report this is.
    print 'Compare Experiments Report,' . localtime() . "\n";
    print "Generated by,$generatedByText\n";
    print "Working Project,$workingProjectText\n\n";

    #Print Platform header.
    print
"Platform, FC-cutoff, P-cutoff, Species, Is Annotated, Probe Count, Sequences Loaded, Accession Numbers, Gene Symbols, Gene Names\n";

    # :TODO:08/06/2011 14:37:20:es: replace this with Text::CSV
    #Print Platform info.
    foreach my $row ( @{ $self->{_DataPlatform} } ) {
        print join(
            ',',
            map {
                if (defined) { s/,//g; $_ }
                else         { '' }
              } @$row
          ),
          "\n";
    }

    #Print a blank line.
    print "\n";

    #Print Experiment info header.
    print
"Experiment Number,Study Description, Experiment Heading,Experiment Description,|Fold Change| >, P\n";

    #This is the line with the experiment name and eid above the data columns.
    my $experimentNameHeader = ",,,,,,,,";

    #Print Experiment info.
    for ( my $i = 0 ; $i < @{ $self->{_eids} } ; $i++ ) {

        my ( $currentSTID, $currentEID ) =
          split( /\|/, $self->{_eids}->[$i] );

        my @currentLine = (
            $currentEID,
            $self->{_headerRecords}->{$currentEID}->{description},
            $self->{_headerRecords}->{$currentEID}->{experimentHeading},
            $self->{_headerRecords}->{$currentEID}->{ExperimentDescription},
            $self->{_fcs}->[$i],
            $self->{_pvals}->[$i]
        );

        #Form the line that displays experiment names above data columns.
        $experimentNameHeader .= $currentEID . ":"
          . $self->{_headerRecords}->{$currentEID}->{title} . ",,,,,";

        #Test for bit presence and print out 1 if present, 0 if absent
        if ( defined( $self->{_fs} ) ) {
            push @currentLine, ( 1 << $i & $self->{_fs} ) ? 'x' : '';
        }

        print join( ',', @currentLine ), "\n";
    }

    #Print a blank line.
    print "\n";

    #Print TFS list along with distinct counts.
    my %TFSCounts;

    # Loop through data and create a hash entry for each TFS, increment the
    # counter.
    foreach my $row ( @{ $self->{_Data} } ) {
        my $abs_fs = $row->[0];
        my $dir_fs = $row->[1];

        # Math::BigInt->badd(x,y) is used to add two very large numbers x and y
        # actually Math::BigInt library is supposed to overload Perl addition
        # operator, but if fails to do so for some reason in this CGI program.
        my $currentTFS = sprintf(
            "$abs_fs.%0" . @{ $self->{_eids} } . 's',
            Math::BigInt->badd(
                substr(
                    unpack( 'b32', pack( 'V', $abs_fs ) ),
                    0, @{ $self->{_eids} }
                ),
                substr(
                    unpack( 'b32', pack( 'V', $dir_fs ) ),
                    0, @{ $self->{_eids} }
                )
            )
        );

        #Increment our counter if it exists.
        $TFSCounts{$currentTFS} =
          ( defined $TFSCounts{$currentTFS} )
          ? 1.0 + $TFSCounts{$currentTFS}
          : 1.0;
    }

    #Print a blank line.
    print "TFS Summary\n";

    # Sort on hash values
    foreach
      my $TFS ( sort { $TFSCounts{$a} <=> $TFSCounts{$b} } keys %TFSCounts )
    {
        print "$TFS,$TFSCounts{$TFS}\n";
    }

    #Print a blank line.
    print "\n";

    #Print header line.
    print "$experimentNameHeader\n";

    #Experiment Data header.
    my @currentLine = (
        'TFS',
        'Probe ID',
        'Accession Number',
        'Gene',
        'Probe Sequence',
        'Gene Name',
        'Gene Ontology',
        'Species'
    );

    foreach my $eid ( @{ $self->{_eids} } ) {
        my ( $currentSTID, $currentEID ) = split( /\|/, $eid );

        push @currentLine,
          (
            "$currentEID:Ratio",       "$currentEID:Fold Change",
            "$currentEID:Intensity-1", "$currentEID:Intensity-2",
            "$currentEID:P"
          );
    }
    print join( ',', @currentLine ), "\n";

    #Print Experiment data.
    foreach my $row ( @{ $self->{_Data} } ) {

        # remove first two elements from @$row and place them into ($abs_fs,
        # $dir_fs)
        my ( $abs_fs, $dir_fs ) = splice @$row, 0, 2;

        # Math::BigInt->badd(x,y) is used to add two very large numbers x and y
        # actually Math::BigInt library is supposed to overload Perl addition
        # operator, but if fails to do so for some reason in this CGI program.
        my $TFS = sprintf(
            "$abs_fs.%0" . @{ $self->{_eids} } . 's',
            Math::BigInt->badd(
                substr(
                    unpack( 'b32', pack( 'V', $abs_fs ) ),
                    0, @{ $self->{_eids} }
                ),
                substr(
                    unpack( 'b32', pack( 'V', $dir_fs ) ),
                    0, @{ $self->{_eids} }
                )
            )
        );

        # :TODO:08/06/2011 14:38:16:es: Replace this block with Text::CSV
        print "$TFS,", join(
            ',',
            map {
                if (defined) { s/,//g; $_ }
                else         { '' }
              } @$row
          ),
          "\n";
    }

    exit;
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
    my $i    = 0;

    my $out = '
var summary = {
caption: "Experiments compared",
headers: ["&nbsp;","Experiment Number", "Study Description", "Sample2/Sample1", "Experiment Description", "&#124;Fold Change&#124; &gt;", "P &lt;", "&nbsp;"],
parsers: ["number","number", "string", "string", "string", "number", "number", "string"],
records: 
';

    my @tmpArrayHead;
    for ( $i = 0 ; $i < @{ $self->{_eids} } ; $i++ ) {

        my ( $currentSTID, $currentEID ) =
          split( /\|/, $self->{_eids}->[$i] );

        my $this_eid     = $self->{_headerRecords}->{$currentEID};
        my $currentTitle = $this_eid->{title};

        my $currentStudyDescription      = $this_eid->{description};
        my $currentExperimentHeading     = $this_eid->{experimentHeading};
        my $currentExperimentDescription = $this_eid->{ExperimentDescription};

        # test for bit presence (store in 7:)
        push @tmpArrayHead,
          {
            0 => ( $i + 1 ),
            1 => $currentEID,
            2 => $currentStudyDescription,
            3 => $currentExperimentHeading,
            4 => $currentExperimentDescription,
            5 => $self->{_fcs}->[$i],
            6 => $self->{_pvals}->[$i],
            7 => ( defined( $self->{_fs} ) && 1 << $i & $self->{_fs} )
            ? 'x'
            : ''
          };
    }

    $out .= encode_json( \@tmpArrayHead ) . '
};
';

    #0:Counter
    #1:EID
    #2:Study Description
    #3:Experiment Heading
    #4:Experiment Description
    #5:Fold Change
    #6:p-value

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

    my $find_probes = $self->{_cgi}->a(
        {
            -target => '_blank',
            -href   => $self->{_cgi}->url( -absolute => 1 )
              . '?a=findProbes&b=Search&match=full&graph=on&type=%1$s&terms={0}',
            -title => 'Find all %1$ss related to %1$s {0}'
        },
        '{0}'
    );
    $find_probes =~ s/"/\\"/g;    # prepend all double quotes with backslashes

    my @format_template;
    push @format_template, sprintf( $find_probes, 'probe' );
    push @format_template, sprintf( $find_probes, 'accnum' );
    push @format_template, sprintf( $find_probes, 'gene' );

    $table_format[0] = 'formatProbe';
    $table_format[1] = 'formatAccNum';
    $table_format[2] = 'formatGene';

    if ( $self->{_opts} > 1 ) {
        my $blat = $self->{_cgi}->a(
            {
                -target => '_blank',
                -title  => 'UCSC BLAT on DNA',
                -href =>
'http://genome.ucsc.edu/cgi-bin/hgBlat?org={1}&type=DNA&userSeq={0}'
            },
            '{0}'
        );
        $blat =~ s/"/\\"/g;    # prepend all double quotes with backslashes
        $table_format[3]    = 'formatProbeSequence';
        $format_template[3] = $blat;
    }

    $out .= '
var tfs = {
caption: "Your selection includes ' . $self->{_RowCountAll} . ' probes",
headers: ["TFS",         "' . join( '","', @table_header ) . '" ],
parsers: ["string",     "' . join( '","', @table_parser ) . '" ],
formats: ["formatText", "' . join( '","', @table_format ) . '" ],
frm_tpl: ["",             "' . join( '","', @format_template ) . '" ],
records: 
';

    # print table body
    my @tmpArray;
    while ( my @row = $self->{_Records}->fetchrow_array ) {
        my ( $abs_fs, $dir_fs ) = splice @row, 0, 2;

 # Math::BigInt->badd(x,y) is used to add two very large numbers x and y
 # actually Math::BigInt library is supposed to overload Perl addition operator,
 # but if fails to do so for some reason in this CGI program.
        my $TFS = sprintf(
            "$abs_fs.%0" . @{ $self->{_eids} } . 's',
            Math::BigInt->badd(
                substr(
                    unpack( 'b32', pack( 'V', $abs_fs ) ),
                    0, @{ $self->{_eids} }
                ),
                substr(
                    unpack( 'b32', pack( 'V', $dir_fs ) ),
                    0, @{ $self->{_eids} }
                )
            )
        );

        push @tmpArray, { 0 => $TFS, map { $_ => $row[ $_ - 1 ] } 1 .. @row };
    }
    $self->{_Records}->finish;
    return $out . encode_json( \@tmpArray ) . '
};

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

    var template_probe = tfs.frm_tpl[1];
    var template_accnum = tfs.frm_tpl[2];
    var template_gene = tfs.frm_tpl[3];
    var template_probeseq = tfs.frm_tpl[4];
    Formatter.formatProbe = function (elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = lang.substitute(template_probe, {"0":oData});
    }
    Formatter.formatAccNum = function (elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = lang.substitute(template_accnum, {"0":oData});
    }
    Formatter.formatGene = function (elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = lang.substitute(template_gene, {"0":oData});
    }
    Formatter.formatProbeSequence = function (elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = lang.substitute(lang.substitute(template_probeseq, {"0":oData}),{"1":oRecord.getData("6")});

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
';
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


