
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

package SGX::TFSDisplay;

use strict;
use warnings;

use Math::BigInt;
use Data::Dumper;
use JSON::XS;

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
    my ( $class, $dbh, %param ) = @_;

    my $self = {
        _dbh             => $dbh,
        _cgi             => $param{cgi},
        _UserSession     => $param{user_session},
        _Records         => '',
        _RecordsPlatform => '',
        _RowCountAll     => 0,
        _headerTitles    => '',
        _headerRecords   => '',
        _headerCount     => 0,
        _PlatformCount   => '',
        _DataPlatform    => '',
        _Data            => '',
        _eids            => '',
        _reverses        => '',
        _fcs             => '',
        _pvals           => '',
        _fs              => '',
        _outType         => '',
        _numStart        => 0,
        _opts            => '',
        _allProbes       => '',
        _searchFilters   => ''
    };

    # find out what the current project is set to
    if ( defined( $self->{_UserSession} ) ) {
        $self->{_WorkingProject} =
          $self->{_UserSession}->{session_cookie}->{curr_proj};
        $self->{_WorkingProjectName} =
          $self->{_UserSession}->{session_cookie}->{proj_name};
        $self->{_UserFullName} =
          $self->{_UserSession}->{session_cookie}->{full_name};
    }

    bless $self, $class;
    return $self;
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

    # The $output_format parameter is either 'html' or 'text'; The $self->{_fs}
    # parameter is the flagsum for which the data will be filtered If the
    # $self->{_fs} is zero or undefined, all data will be output
    #
    my $regex_split_on_commas = qr/ *, */;
    my @eidsArray =
      split( $regex_split_on_commas, $self->{_cgi}->param('eid') );
    my @reversesArray =
      split( $regex_split_on_commas, $self->{_cgi}->param('rev') );
    my @fcsArray = split( $regex_split_on_commas, $self->{_cgi}->param('fc') );
    my @pvalArray =
      split( $regex_split_on_commas, $self->{_cgi}->param('pval') );

    $self->{_eids}     = \@eidsArray;
    $self->{_reverses} = \@reversesArray;
    $self->{_fcs}      = \@fcsArray;
    $self->{_pvals}    = \@pvalArray;

    $self->{_allProbes}     = $self->{_cgi}->param('allProbes');
    $self->{_searchFilters} = $self->{_cgi}->param('searchFilter');
    $self->{_fs}            = $self->{_cgi}->param('get');
    $self->{_outType}       = $self->{_cgi}->param('outType');
    $self->{_opts}          = $self->{_cgi}->param('opts');

    if ( $self->{_fs} =~ m/^HTML-formatted$/i ) {
        undef $self->{_fs};
    }
    else {
        $self->{_fs} =~ s/^TFS: //i;
    }

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
    # Fix this by writing a validate_numeric_list function which will take
    # a string of comma-delimited numbers, split it, make sure every member
    # is a number, and concatenate it again.
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
        my @IDSplit     = split( /\|/, $eid );
        my $currentSTID = $IDSplit[0];
        my $currentEID  = $IDSplit[1];

        my ( $fc, $pval ) =
          ( $self->{_fcs}->[ $i - 1 ], $self->{_pvals}->[ $i - 1 ] );

        my $abs_flag = 1 << $i - 1;
        my $dir_flag =
          ( $self->{_reverses}[ $i - 1 ] ) ? "$abs_flag,0" : "0,$abs_flag";
        push @query_proj,
          ( $self->{_reverses}[ $i - 1 ] )
          ? "1/m$i.ratio AS \'$i: Ratio\', m$i.pvalue"
          : "m$i.ratio AS \'$i: Ratio\', m$i.pvalue";

        if ( $self->{_opts} > 0 ) {
            push @query_proj,
              ( $self->{_reverses}[ $i - 1 ] )
              ? "-m$i.foldchange AS \'$i: Fold Change\'"
              : "m$i.foldchange AS \'$i: Fold Change\'";
            push @query_proj,
              ( $self->{_reverses}[ $i - 1 ] )
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
          ( $self->{_reverses}[ $i - 1 ] )
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

    $self->{_headerTitles} =
      $self->{_dbh}->prepare( join( ' UNION ALL ', @query_titles ) );
    $self->{_headerCount}   = $self->{_headerTitles}->execute;
    $self->{_headerRecords} = $self->{_headerTitles}->fetchall_hashref('eid');
    $self->{_headerTitles}->finish;

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

    $self->{_Records}     = $self->{_dbh}->prepare($query);
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

    my @eidList;
    foreach ( @{ $self->{_eids} } ) {

        #The EID is actually STID|EID. We need to split the string on '|'.
        my ( $currentSTID, $currentEID ) = split /\|/;
        push @eidList, $currentEID;
    }

    my $placeholders = join( ',', map { '?' } @eidList );

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

    $self->{_RecordsPlatform} = $self->{_dbh}->prepare($singleItemQuery);
    $self->{_PlatformCount}   = $self->{_RecordsPlatform}->execute(@eidList);
    $self->{_FieldNames}      = $self->{_RecordsPlatform}->{NAME};
    $self->{_DataPlatform}    = $self->{_RecordsPlatform}->fetchall_arrayref;
    $self->{_RecordsPlatform}->finish;

    return 1;
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

    $self->{_fs}            = $q->param('get');
    $self->{_outType}       = $q->param('outType');
    $self->{_opts}          = $q->param('opts');
    $self->{_allProbes}     = $q->param('allProbes');
    $self->{_searchFilters} = $q->param('searchFilter');

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

    if ( defined( $self->{_fs} ) ) {
        if ( $self->{_fs} =~ m/^HTML-formatted$/i ) {
            undef $self->{_fs};
        }
        else {
            $self->{_fs} =~ s/^FS: //i;
        }
    }

    if ( defined( $self->{_cgi}->param('CSV') ) ) {
        if ( $self->{_cgi}->param('CSV') =~ m/^(CSV)$/i ) {
            undef $self->{_fs};
        }
        else {
            if ( $self->{_cgi}->param('CSV') =~ m/^\(TFS\:\s*(\d*)\s*CSV\)/i ) {
                $self->{_fs} = $1;
            }
        }
    }

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
        my @IDSplit = split( /\|/, $eid );

        my $currentSTID = $IDSplit[0];
        my $currentEID  = $IDSplit[1];

        my ( $fc, $pval ) =
          ( ${ $self->{_fcs} }[ $i - 1 ], ${ $self->{_pvals} }[ $i - 1 ] );
        my $abs_flag = 1 << $i - 1;
        my $dir_flag =
          ( $self->{_reverses}[ $i - 1 ] ) ? "$abs_flag,0" : "0,$abs_flag";

        push @query_proj,
          ( $self->{_reverses}[ $i - 1 ] )
          ? "1/m$i.ratio AS \'$i: Ratio\'"
          : "m$i.ratio AS \'$i: Ratio\'";

        push @query_proj,
          ( $self->{_reverses}[ $i - 1 ] )
          ? "-m$i.foldchange AS \'$i: Fold Change\'"
          : "m$i.foldchange AS \'$i: Fold Change\'";

        push @query_proj,
          ( $self->{_reverses}[ $i - 1 ] )
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
          ( $self->{_reverses}[ $i - 1 ] )
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
    $self->{_headerTitles} =
      $self->{_dbh}->prepare( join( ' UNION ALL ', @query_titles ) );
    $self->{_headerCount}   = $self->{_headerTitles}->execute;
    $self->{_headerRecords} = $self->{_headerTitles}->fetchall_hashref('eid');
    $self->{_headerTitles}->finish;

    #Run the query for the actual data records.
    $self->{_Records}     = $self->{_dbh}->prepare($query);
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

    #Clear our headers so all we get back is the CSV file.
    $self->{_UserSession}->commit() if defined( $self->{_UserSession} );
    my $cookie_array =
      ( defined $self->{_UserSession} )
      ? $self->{_UserSession}->cookie_array()
      : [];
    print $self->{_cgi}->header(
        -type       => 'text/csv',
        -attachment => 'results.csv',
        -cookie     => $cookie_array
    );

    #Print a line to tell us what report this is.
    my $workingProjectText =
      ( defined( $self->{_WorkingProjectName} ) )
      ? $self->{_WorkingProjectName}
      : 'N/A';

    my $generatedByText =
      ( defined( $self->{_UserFullName} ) )
      ? $self->{_UserFullName}
      : '';

    #Print a line to tell us what report this is.
    print 'Compare Experiments Report,' . localtime() . "\n";
    print "Generated by,$generatedByText\n";
    print "Working Project,$workingProjectText\n\n";

    #Print Platform header.
    print
"Platform, FC-cutoff, P-cutoff, Species, Is Annotated, Probe Count, Sequences Loaded, Accession Numbers, Gene Symbols, Gene Names\n";

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

        my @IDSplit = split( /\|/, ${ $self->{_eids} }[$i] );
        my $currentEID = $IDSplit[1];

        my @currentLine = (
            $currentEID,
            $self->{_headerRecords}->{$currentEID}->{description},
            $self->{_headerRecords}->{$currentEID}->{experimentHeading},
            $self->{_headerRecords}->{$currentEID}->{ExperimentDescription},
            ${ $self->{_fcs} }[$i],
            ${ $self->{_pvals} }[$i]
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
        if ( defined $TFSCounts{$currentTFS} ) {
            $TFSCounts{$currentTFS} = $TFSCounts{$currentTFS} + 1.0;
        }
        else {
            $TFSCounts{$currentTFS} = 1.0;
        }
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
        my @IDSplit = split( /\|/, $eid );
        my $currentEID = $IDSplit[1];

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

        my @IDSplit = split( /\|/, ${ $self->{_eids} }[$i] );
        my $currentEID = $IDSplit[1];

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
            5 => ${ $self->{_fcs} }[$i],
            6 => ${ $self->{_pvals} }[$i],
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
    $out .= encode_json( \@tmpArray ) . '
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
    $out;
}

1;
