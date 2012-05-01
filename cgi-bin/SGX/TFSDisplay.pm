package SGX::TFSDisplay;

use strict;
use warnings;

use base qw/SGX::Strategy::Base/;

use SGX::Debug;
require Math::BigInt;
require Math::BigFloat;
use JSON qw/decode_json/;
require SGX::Abstract::JSEmitter;
use SGX::Abstract::Exception ();
use SGX::Util qw/car bind_csv_handle count_bits before_dot/;

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

    $self->set_attributes( _title => $self->get_subset_name() );

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

    $self->loadDataCSV();
    $self->displayDataCSV();
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

    $self->loadDataHTML();
    my $jsresults = $self->displayDataHTML();

    push @$js_src_code,
      ( { -code => $jsresults }, { -src => 'TFSDisplay.js' } );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  TFSDisplay
#       METHOD:  get_subset_name
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_subset_name {
    my $self = shift;
    my $fs   = $self->{_fs};
    return (
        defined($fs) ? "Subset $fs"
        : (
            $self->{_allProbes} ? 'Subset: all probes'
            : 'Subset: all significant probes'
        )
    );
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
    my $q    = $self->{_cgi};

    return $q->h2( { -id => 'summary_caption' }, $self->get_subset_name() ),
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

    $self->{_xExpList}     = decode_json( car $q->param('user_selection') );
    $self->{_allProbes}    = $q->param('includeAllProbes') || '';
    $self->{_searchFilter} = $q->param('searchFilter') || '';

    $self->{_opts} = $q->param('opts') || '0';

    # The $self->{_fs} parameter is the flagsum for which we filter data
    my $fs = car $q->param('selectedFS');
    $self->{_fs} = $fs ne '' ? $fs : undef;
    $self->{_expected} = decode_json( car( $q->param('selectedExp') ) || '{}' );
    $self->{_format} = car $q->param('get');

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
#       METHOD:  loadDataHTML
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  LOAD TFS DATA
#       THROWS:  no exceptions
#     COMMENTS:  This code is very old... Refactoring it would be desirable.
#     SEE ALSO:  n/a
#===============================================================================
sub loadDataHTML {
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
    # one _searchFilter before being inserted into WHERE statement.
    # Fix this by using prepare/execute with placeholders.
    my $probeListQuery =
      ( defined( $self->{_searchFilter} ) && $self->{_searchFilter} ne '' )
      ? " WHERE rid IN (" . $self->{_searchFilter} . ") "
      : '';

    my @query_proj;
    my @query_join;
    my @query_body;

    my $allProbes = $self->{_allProbes};
    my $i         = 1;
    foreach my $row ( @{ $self->{_xExpList} } ) {
        my $eid       = $row->{eid};
        my $fc        = $row->{fchange};
        my $pval      = $row->{pval};
        my $pValClass = $row->{pValClass};
        my $pval_sql  = "pvalue$pValClass";
        my $reverse   = $row->{reverse};

        my $abs_flag = 1 << $i - 1;
        my $dir_flag = $reverse ? "$abs_flag,0" : "0,$abs_flag";
        push @query_proj,
          (
            $reverse
            ? "1/m$eid.ratio AS '$eid: Ratio', m$eid.$pval_sql AS '$eid: P-$pValClass'"
            : "m$eid.ratio AS '$eid: Ratio', m$eid.$pval_sql AS '$eid: P-$pValClass'"
          );

        if ( $self->{_opts} ne 'basic' ) {
            push @query_proj,
              (
                $reverse
                ? "-m$eid.foldchange AS '$eid: FC'"
                : "m$eid.foldchange AS '$eid: FC'"
              );
            push @query_proj,
              (
                $reverse
                ? "IFNULL(m$eid.intensity2,0) AS '$eid: Intensity-1', IFNULL(m$eid.intensity1,0) AS '$eid: Intensity-2'"
                : "IFNULL(m$eid.intensity1,0) AS '$eid: Intensity-1', IFNULL(m$eid.intensity2,0) AS '$eid: Intensity-2'"
              );
            push @query_proj, "m$eid.$pval_sql AS '$eid: P-$pValClass'";
        }

        push @query_join,
          "LEFT JOIN microarray m$eid ON m$eid.rid=d2.rid AND m$eid.eid=$eid";

        #This is part of the query when we are including all probes.
        push @query_body, ($allProbes)
          ? <<"END_yes_allProbes"
SELECT
    rid, 
    IF($pval_sql < $pval AND ABS(foldchange) > $fc, $abs_flag, 0) AS abs_flag,
    IF($pval_sql < $pval AND ABS(foldchange) > $fc, 
       IF(foldchange > 0, $dir_flag), 
       0
    ) AS dir_flag
FROM microarray
WHERE eid=$eid
END_yes_allProbes
          : <<"END_no_allProbes";
SELECT
    rid, 
    $abs_flag AS abs_flag,
    IF(foldchange > 0, $dir_flag) AS dir_flag
FROM microarray 
WHERE eid = $eid 
  AND $pval_sql < $pval 
  AND ABS(foldchange) > $fc
END_no_allProbes

        $i++;
    }

    $self->{_headerRecords} = +{
        map {
            $_->{eid} => +{
                experimentHeading => (
                    (
                        $_->{study_desc} . ': '
                          . (
                            $_->{reverse}
                            ? ( $_->{sample1} . '/' . $_->{sample2} )
                            : ( $_->{sample2} . '/' . $_->{sample1} )
                          )
                    )
                )
            };
          } @{ $self->{_xExpList} }
    };

    if ( $self->{_opts} eq 'annot' ) {
        $self->{_numStart} += 3;
        unshift @query_proj,
          (
            qq{probe.probe_sequence AS 'Probe Sequence'},
qq{GROUP_CONCAT(DISTINCT IF(gene.gname='', NULL, gene.gname) SEPARATOR '; ') AS 'Gene Description'}
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
    probe.reporter AS 'Probe ID',
    GROUP_CONCAT(DISTINCT if(gene.gtype=0, gene.gsymbol, NULL) separator ' ') AS 'Accession No.',
    GROUP_CONCAT(DISTINCT if(gene.gtype=1, gene.gsymbol, NULL) separator ' ') AS 'Gene Symbol',
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
LEFT JOIN ProbeGene ON d2.rid        = ProbeGene.rid
LEFT JOIN gene      ON ProbeGene.gid = gene.gid
LEFT JOIN (select platform.pid, species.sname FROM platform LEFT JOIN species USING(sid)) AS platform_species USING(pid)
GROUP BY probe.rid
ORDER BY abs_fs DESC
END_query

    my $dbh = $self->{_dbh};
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
    my $self      = shift;
    my $dbh       = $self->{_dbh};
    my $data_rows = $self->{_xExpList};

    my @eidList = map { $_->{eid} } @$data_rows;
    my $placeholders =
      (@$data_rows)
      ? join( ',', map { '?' } @eidList )
      : 'NULL';

  # :TODO:07/25/2011 02:39:05:es: Since experiments from different platforms
  # cannot be comoared using Compare Experiments, this query is a little bit too
  # fat for what we need.
    my $singleItemQuery = <<"END_LoadQuery";
SELECT
    platform.pname            AS 'Platform',
    species.sname             AS 'Species',
    probes.id_count           AS 'Probe Count',
    probes.sequence_count     AS 'Sequences Loaded'
FROM platform
LEFT JOIN species USING(sid)
LEFT JOIN (
    SELECT
        pid,
        COUNT(probe.rid) AS id_count,
        COUNT(probe_sequence) AS sequence_count
    FROM probe
    WHERE probe.pid IN (SELECT DISTINCT pid FROM experiment WHERE eid IN($placeholders))
    GROUP BY pid
) AS probes USING(pid)
WHERE pid IN (SELECT DISTINCT pid FROM experiment WHERE eid IN($placeholders))
GROUP BY platform.pid
END_LoadQuery

    my $sth = $dbh->prepare($singleItemQuery);
    my $rc = $sth->execute( @eidList, @eidList );
    $self->{_FieldNames}   = $sth->{NAME};
    $self->{_DataPlatform} = $sth->fetchall_arrayref;
    $sth->finish;

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::TFSDisplay
#       METHOD:  loadDataCSV
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  LOAD ALL DATA FOR CSV OUTPUT
#       THROWS:  no exceptions
#     COMMENTS:  This code is very old... Refactoring it would be desirable.
#     SEE ALSO:  n/a
#===============================================================================
sub loadDataCSV {
    my $self = shift;

    #This is the different parts of the experiment and titles query.
    my @query_body;
    my @query_proj;
    my @query_join;

    #If we got a list to filter on, build the string.
    my $probeListQuery =
      ( defined( $self->{_searchFilter} ) && $self->{_searchFilter} ne '' )
      ? " WHERE rid IN (" . $self->{_searchFilter} . ") "
      : '';

    my $i = 1;
    foreach my $row ( @{ $self->{_xExpList} } ) {
        my $eid       = $row->{eid};
        my $fc        = $row->{fchange};
        my $pval      = $row->{pval};
        my $reverse   = $row->{reverse};
        my $pValClass = $row->{pValClass};
        my $pval_sql  = "pvalue$pValClass";

        my $abs_flag = 1 << $i - 1;
        my $dir_flag = $reverse ? "$abs_flag,0" : "0,$abs_flag";

        push @query_proj,
          (
            $reverse
            ? "1/m$eid.ratio AS '$eid: Ratio'"
            : "m$eid.ratio AS '$eid: Ratio'"
          );

        push @query_proj,
          (
            $reverse
            ? "-m$eid.foldchange AS '$eid: FC'"
            : "m$eid.foldchange AS '$eid: FC'"
          );

        push @query_proj,
          (
            $reverse
            ? "IFNULL(m$eid.intensity2,0) AS '$eid: Intensity-1', IFNULL(m$eid.intensity1,0) AS '$eid: Intensity-2'"
            : "IFNULL(m$eid.intensity1,0) AS '$eid: Intensity-1', IFNULL(m$eid.intensity2,0) AS '$eid: Intensity-2'"
          );

        push @query_proj, "m$eid.$pval_sql AS '$eid: P-$pValClass'";

        push @query_join,
          "LEFT JOIN microarray m$eid ON m$eid.rid=d2.rid AND m$eid.eid=$eid";

        push @query_body, ( $self->{_allProbes} )
          ? <<"END_yes_allProbesCSV"
SELECT
    rid,
    IF($pval_sql < $pval AND ABS(foldchange) > $fc, $abs_flag, 0) AS abs_flag,
    IF($pval_sql < $pval AND ABS(foldchange) > $fc, IF(foldchange > 0, $dir_flag), 0) AS dir_flag
FROM microarray
WHERE eid=$eid
END_yes_allProbesCSV
          : <<"END_no_allProbesCSV";
SELECT
    rid, 
    $abs_flag AS abs_flag,
    IF(foldchange > 0, $dir_flag) AS dir_flag
FROM microarray 
WHERE eid = $eid 
  AND $pval_sql < $pval 
  AND ABS(foldchange) > $fc
END_no_allProbesCSV

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
qq{GROUP_CONCAT(DISTINCT IF(gene.gname='', NULL, gene.gname) SEPARATOR '; ') AS 'Gene Description'}
      );

    my $d1SubQuery   = join( ' UNION ALL ', @query_body );
    my $selectSQL    = join( ',',           @query_proj );
    my $predicateSQL = join( "\n",          @query_join );

    # pad TFS decimal portion with the correct number of zeroes
    my $query = <<"END_queryCSV";
SELECT
    abs_fs, 
    dir_fs, 
    probe.reporter AS 'Probe ID', 
    GROUP_CONCAT(DISTINCT if(gene.gtype=0, gene.gsymbol, NULL) separator ' ') AS 'Accession No.',
    GROUP_CONCAT(DISTINCT if(gene.gtype=1, gene.gsymbol, NULL) separator ' ') AS 'Gene Symbol',
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
LEFT JOIN ProbeGene ON d2.rid        = ProbeGene.rid
LEFT JOIN gene      ON ProbeGene.gid = gene.gid
LEFT JOIN (select platform.pid, species.sname FROM platform LEFT JOIN species USING(sid)) AS platform_species USING(pid)
GROUP BY probe.rid
ORDER BY abs_fs DESC
END_queryCSV

    $self->{_headerRecords} = +{
        map {
            $_->{eid} => +{
                experimentHeading => (
                    $_->{study_desc} . ': '
                      . (
                        $_->{reverse}
                        ? ( $_->{sample1} . '/' . $_->{sample2} )
                        : ( $_->{sample2} . '/' . $_->{sample1} )
                      )
                )
            };
          } @{ $self->{_xExpList} }
    };

    #Run the query for the actual data records.
    my $dbh = $self->{_dbh};
    $self->{_Records}     = $dbh->prepare($query);
    $self->{_RowCountAll} = $self->{_Records}->execute;

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::TFSDisplay
#       METHOD:  displayDataCSV
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  DISPLAY PLATFORM,EXPERIMENT INFO, AND EXPERIMENT DATA TO A CSV
#  FILE
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub displayDataCSV {
    my $self      = shift;
    my $data_rows = $self->{_xExpList};

    my $print = bind_csv_handle( \*STDOUT );

    my $sth_records = $self->{_Records};

    # get name array from statement handle
    my $record_names = $sth_records->{NAME};
    shift @$record_names;
    shift @$record_names;
    unshift @$record_names, 'TFS';

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
            'Experiment No.',
            'Experiment Heading',
            '|FC| >',
            'P-value used',
            'P <',
            'Significant in'
        ]
    );

    # The line with the experiment name and eid above the data columns has 6
    # fields: TFS, Probe ID, Accession No., Gene Symbol, Probe Sequence, Gene
    # Name
    my @experimentNameHeader = (undef) x 6;

    # Print Experiment info.
    my $headerRecords = $self->{_headerRecords};
    my $currFS        = $self->{_fs};

    my $signExpCount = 0;
    for ( my $i = 0 ; $i < @$data_rows ; $i++ ) {
        my $row      = $data_rows->[$i];
        my $eid      = $row->{eid};
        my $eid_node = $headerRecords->{$eid};

        # Form the line that displays experiment names above data columns.
        # Offsetting by 4 fields: FC, Intensity-1, Intensity-2, P-value
        push @experimentNameHeader,
          $eid . ':' . $eid_node->{experimentHeading},
          (undef) x 4;

        my $signCell = '';
        if ( defined $currFS ) {

            # Test for bit presence, print out 'Yes' if present, 'No' if absent
            if ( 1 << $i & $currFS ) {

                # significant experiment
                $signCell = 'Y';
                $signExpCount++;

            }
            else {

                # not significant experiment
                $signCell = 'N';
            }
        }
        my $currLine = [
            $eid,            $eid_node->{experimentHeading},
            $row->{fchange}, $row->{pValClass},
            $row->{pval},    $signCell
        ];
        $print->($currLine);
    }
    $print->();

    # Calculate TFS along with distinct counts
    my $eid_count = @{ $self->{_xExpList} };
    my %TFSCounts;

    my $data_array = $sth_records->fetchall_arrayref;
    $sth_records->finish;

    foreach (@$data_array) {

        # for each row
        my $currentTFS = get_tfs( shift @$_, shift @$_, $eid_count );
        unshift @$_, $currentTFS;
        $TFSCounts{$currentTFS} =
          ( defined $TFSCounts{$currentTFS} )
          ? 1 + $TFSCounts{$currentTFS}
          : 1;
    }

    # print comparison stats
    Math::BigFloat->accuracy(3);
    my $observed = scalar(@$data_array);
    my $expected = $self->{_expected};
    $print->( ['TFS Summary'] );
    $print->( [ 'TFS', 'Probe Count', 'Log Odds Over Expected' ] );
    $print->(
        [
            $currFS,
            $observed,

            # log_odds
            eval {
                Math::BigFloat->new( log( $observed / $expected->{null} ) );
            }
        ]
    );
    $print->(
        [
            $_,
            $TFSCounts{$_},

            # log_odds
            eval {
                Math::BigFloat->new(
                    log(
                        $TFSCounts{$_} /
                          $expected->{ ( before_dot($_) ) } *
                          ( 1 << count_bits( before_dot($_) ) + 0.0 )
                    )
                );
            }
        ]
      )
      for sort { $TFSCounts{$b} <=> $TFSCounts{$a} }
      keys %TFSCounts;
    $print->();

    # Print header line.
    $print->( \@experimentNameHeader );

    # Experiment Data header.
    $print->($record_names);

    # Print Experiment data sorting by TFS in descending order, then by gene
    # name in ascending order.
    $print->($_)
      for sort { $b->[0] cmp $a->[0] || ( $a->[3] || '' ) cmp( $b->[3] || '' ) }
      @$data_array;

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::TFSDisplay
#       METHOD:  displayDataHTML
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Display TFS info
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub displayDataHTML {
    my $self = shift;
    my $q    = $self->{_cgi};

    # Fields with indexes less num_start are formatted as strings, fields with
    # indexes equal to or greater than num_start are formatted as numbers.
    my @table_header;
    my @table_parser;
    my @table_format;

    my $sth_records  = $self->{_Records};
    my $record_names = $sth_records->{NAME};

    for ( my $j = 2 ; $j < $self->{_numStart} ; $j++ ) {
        push @table_header, $record_names->[$j];
        push @table_parser, 'string';
        push @table_format, 'formatText';
    }
    for ( my $j = $self->{_numStart} ; $j < @$record_names ; $j++ ) {
        push @table_header, $record_names->[$j];
        push @table_parser, 'number';
        push @table_format, 'formatNumber';
    }

    # wrapping block below in curly brackets because of "Insecure dependency
    # when running with -T" (taint mode) Perl message
    my %format_template;
    {
        my $findProbesHTML = $q->a(
            {
                -title  => 'Find all %1$ss related to %1$s {0}',
                -target => '_blank',
                -href   => $self->url( -absolute => 1 )
                  . '?a=findProbes&b=Search&scope=%1$s&q={0}',
            },
            '{0}'
        );
        $format_template{probe} = sprintf( $findProbesHTML, 'Probe IDs' );
        $format_template{accnum} =
          sprintf( $findProbesHTML, 'Genes/Accession Nos.' );
        $format_template{gene} =
          sprintf( $findProbesHTML, 'Genes/Accession Nos.' );
    };

    $table_format[0] = 'formatProbe';
    $table_format[1] = 'formatAccNum';
    $table_format[2] = 'formatGene';

    if ( $self->{_opts} eq 'annot' ) {
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
    my $data_array = $sth_records->fetchall_arrayref;
    $sth_records->finish;

    my $eid_count = @{ $self->{_xExpList} };
    unshift( @$_, get_tfs( shift @$_, shift @$_, $eid_count ) )
      for @$data_array;

    my $js = SGX::Abstract::JSEmitter->new( pretty => 0 );
    return '' . $js->let(
        [
            _xExpList => $self->{_xExpList},
            _expected => $self->{_expected},
            _fs       => $self->{_fs},
            tfs       => {
                caption => sprintf( 'This subset includes %d probes',
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
        ],
        declare => 1
    );
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


