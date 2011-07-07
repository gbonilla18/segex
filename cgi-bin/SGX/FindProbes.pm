
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

package SGX::FindProbes;

use strict;
use warnings;

use Switch;
use CGI::Carp;
use Tie::IxHash;
use Data::Dumper;
use File::Basename;
use JSON::XS;
use File::Temp;
use SGX::Exceptions;

use SGX::Util qw/trim/;
use SGX::Debug qw/assert/;

sub new {

    # This is the constructor
    my ( $class, %param ) = @_;

    my ( $dbh, $q, $s ) = @param{qw{dbh cgi user_session}};
    my $self = {
        _dbh                 => $dbh,
        _cgi                 => $q,
        _UserSession         => $s,
        _SearchType          => undef,
        _SearchText          => undef,
        _ProbeRecords        => '',
        _ProbeCount          => 0,
        _ProbeColNames       => '',
        _ProbeData           => '',
        _RecordsPlatform     => '',
        _ProbeHash           => '',
        _RowCountAll         => 0,
        _ProbeExperimentHash => '',
        _Data                => '',
        _eids                => '',
        _FullExperimentRec   => '',
        _FullExperimentCount => 0,
        _FullExperimentData  => '',
        _InsideTableQuery    => '',
        _SearchItems         => '',
        _PlatformInfoQuery   => "SELECT pid, pname FROM platform",
        _PlatformInfoHash    => '',
        _ProbeQuery          => '',
        _ExperimentListHash      => '',
        _ExperimentStudyListHash => '',
        _TempTableID             => '',
        _ExperimentNameListHash  => '',
        _ExperimentDataQuery     => undef,
        _ReporterList            => undef
    };

    # find out what the current project is set to
    if ( defined($s) ) {
        $self->{_UserFullName} = $s->{session_cookie}->{full_name};
    }

  # :TRICKY:06/28/2011 13:47:09:es: We implement the following behavior: if, in
  # the URI option string, "proj" is set to some value (e.g. "proj=32") or to an
  # empty string (e.g. "proj="), we set the data field _WorkingProject to that
  # value; if the "proj" option is missing from the URI, we use the value of
  # "curr_proj" from session data. This allows us to have all portions of the
  # data accessible via a REST-style interface regardless of current user
  # preferences.
    my $cgi_proj = $q->param('proj');
    if ( defined($cgi_proj) ) {
        $self->{_WorkingProject} = $cgi_proj;
        if ( $cgi_proj ne '' ) {

            # now need to obtain project name from the database
            my $sth =
              $dbh->prepare(qq{SELECT prname FROM project WHERE prid=?});
            my $rc = $sth->execute($cgi_proj);
            if ( $rc != 0 ) {

                # name exists
                my $result = $sth->fetchrow_arrayref;
                $self->{_WorkingProject} = $cgi_proj;
                ( $self->{_WorkingProjectName} ) = @$result;
            }
            else {

                # name doesn't exist
                $self->{_WorkingProject}     = '';
                $self->{_WorkingProjectName} = undef;
            }
            $sth->finish;
        }
        else {
            $self->{_WorkingProjectName} = undef;
        }
    }
    elsif ( defined($s) ) {
        $self->{_WorkingProject}     = $s->{session_cookie}->{curr_proj};
        $self->{_WorkingProjectName} = $s->{session_cookie}->{proj_name};
    }

#Reporter,Accession Number, Gene Name, Probe Sequence, {Ratio,FC,P-Val,Intensity1,Intensity2}

    bless $self, $class;
    return $self;
}

#######################################################################################
sub build_ExperimentDataQuery {
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
}

#######################################################################################
sub set_SearchItems {
    my ( $self, $mode ) = @_;

    # 'text' must always be set
    my $text = $self->{_cgi}->param('terms');

    #This will be the array that holds all the splitted items.
    my @textSplit;

    #If we find a comma, split on that, otherwise we split on new lines.
    if ( $text =~ m/,/ ) {

        #Split the input on commas.
        @textSplit = split( /\,/, trim($text) );
    }
    else {

        #Split the input on the new line.
        @textSplit = split( /\r\n/, $text );
    }

    #Get the count of how many search terms were found.
    my $searchesFound = @textSplit;
    my $qtext;
    if ( $searchesFound < 2 ) {
        my $match =
          ( defined( $self->{_cgi}->param('match') ) )
          ? $self->{_cgi}->param('match')
          : 'full';
        switch ($match) {
            case 'full'   { $qtext = '^' . $textSplit[0] . '$' }
            case 'prefix' { $qtext = '^' . $textSplit[0] }
            case 'part'   { $qtext = $textSplit[0] }
            else { croak "Invalid match value $match" }
        }
    }
    else {
        $qtext =
          ( $mode == 0 )
          ? join( '|', map { '^' . trim($_) . '$' } @textSplit )
          : '^' . join( '|', map { trim($_) } @textSplit ) . '$';
    }
    $self->{_SearchItems} = $qtext;
    return;
}
#######################################################################################
#This is the code that generates part of the SQL statement.
# Call to this function is always followed by a call to build_ProbeQuery()
#######################################################################################
sub createInsideTableQuery {
    my $self = shift;
    $self->set_SearchItems(0);

    # 'type' must always be set
    my $type = $self->{_cgi}->param('type');

    $self->build_InsideTableQuery($type);
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  FindProbes
#       METHOD:  createInsideTableQueryFromFile
#   PARAMETERS:  $self - current instance
#                $fh - file handle (usually to uploaded file)
#      RETURNS:  ????
#  DESCRIPTION:  generates part of the SQL statement (From a file instead of a
#  list of genes).
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub createInsideTableQueryFromFile {

    #Get the probe object.
    my ( $self, $fh ) = @_;

    # We need to get the list from the user into SQL, We need to do some temp
    # table/file trickery for this.

    #Get time to make our unique ID.
    my $time = time();

    #Make idea with the time and ID of the running application.
    my $processID = $time . '_' . getppid();

    #Regex to strip quotes.
    my $regex_strip_quotes = qr/^("?)(.*)\1$/;

    #Store the temp Table id so we can drop the table later.
    $self->{_TempTableID} = $processID;

    #We need to create this output directory.
    my $tmp = File::Temp->new();

    #This is where we put the temp file we will import.
    my $outputFileName = $tmp->filename();

    #Open file we are writing to server.
    open my $outputToServer, '>', $outputFileName
      or croak "Could not open $outputFileName for writing: $!";

    #Each line is an item to search on.
    while (<$fh>) {

#Grab the current line (Or Whole file if file is using Mac line endings).
#Replace all carriage returns, or carriage returns and line feed with just a line feed.
        $_ =~ s/(\r\n|\r)/\n/g;
        print {$outputToServer} $_;
    }
    close($outputToServer);

    #--------------------------------------------
    #Now get the temp file into a temp MYSQL table.

    #Command to create temp table.
    my $createTableStatement =
      "CREATE TABLE $processID (searchField VARCHAR(200))";

    #This is the mysql command to suck in the file.
    my $inputStatement = <<"END_inputStatement";
LOAD DATA LOCAL INFILE ?
INTO TABLE $processID
LINES TERMINATED BY '\n'
(searchField);
END_inputStatement

    #--------------------------------------------

    #When using the file from the user we join on the temp table we create.
    #---------------------------------------------
    #Run the command to create the temp table.
    $self->{_dbh}->do($createTableStatement);

    #Run the command to suck in the data.
    $self->{_dbh}->do( $inputStatement, undef, $outputFileName );

    # Delete the temporary file we created:
    #unlink($outputFileName);
    #--------------------------------------------

    #This is the type of search. 'type' must always be set
    my $type = $self->{_cgi}->param('type');

    $self->build_InsideTableQuery( $type, tmp_table => $processID );
    $self->{_SearchItems} = undef;
    return 1;
}

#######################################################################################
#Return the inside table query.
#######################################################################################
sub getInsideTableQuery {
    my $self = shift;
    return $self->{_InsideTableQuery};
}

#######################################################################################
#Return the search terms used in the query.
#######################################################################################
sub getQueryTerms {
    my $self = shift;
    return $self->{_SearchItems};
}

#######################################################################################
#Fill a hash with platform name and ID so we print it for the seperators.
#######################################################################################
sub fillPlatformHash {
    my $self = shift;

    my $tempPlatformQuery = $self->{_PlatformInfoQuery};
    my $platformRecords   = $self->{_dbh}->prepare($tempPlatformQuery);
    my $platformCount     = $platformRecords->execute();
    my $platformData      = $platformRecords->fetchall_arrayref;
    $platformRecords->finish;

    #Initialize our hash.
    $self->{_PlatformInfoHash} = {};

    #For each probe we get add an item to the hash.
    my %PlatformInfoHash =
      map { $_->[0] => $_->[1] } @{$platformData};
    $self->{_PlatformInfoHash} = \%PlatformInfoHash;
    return;
}

#######################################################################################
#Get a list of the probes (Only the reporter field).
#######################################################################################
sub loadProbeReporterData {
    my ( $self, $qtext ) = @_;

    my $InsideTableQuery = $self->{_InsideTableQuery};
    my $probeQuery = <<"END_ProbeReporterQuery";
SELECT DISTINCT probe.rid
FROM ( $InsideTableQuery ) as g0
LEFT JOIN annotates USING(gid)
INNER JOIN probe ON probe.rid=COALESCE(g0.rid, annotates.rid)
END_ProbeReporterQuery

    #$probeQuery =~ s/\{0\}/\Q$self->{_InsideTableQuery}\E/;
    #$probeQuery =~ s/\\//g;

    $self->{_ProbeRecords}  = $self->{_dbh}->prepare($probeQuery);
    $self->{_ProbeCount}    = $self->{_ProbeRecords}->execute();
    $self->{_ProbeColNames} = @{ $self->{_ProbeRecords}->{NAME} };
    $self->{_Data}          = $self->{_ProbeRecords}->fetchall_arrayref;

    $self->{_ProbeRecords}->finish;

    $self->{_ProbeHash} = {};

    my $DataCount = @{ $self->{_Data} };

  # For the situation where we created a temp table for the user input,
  # we need to drop that temp table. This is the command to drop the temp table.
    my $dropStatement = 'DROP TABLE ' . $self->{_TempTableID} . ';';

    #Run the command to drop the temp table.
    $self->{_dbh}->do($dropStatement);

    if ( $DataCount < 1 ) {
        $self->{_UserSession}->commit() if defined($self->{_UserSession});
        my $cookie_array = (defined $self->{_UserSession})
            ? $self->{_UserSession}->cookie_array()
            : [];
        print $self->{_cgi}->header(
            -type   => 'text/html',
            -cookie => $cookie_array
        );
        print
'No records found! Please click back on your browser and search again!';
        exit;
    }

    my $dbh = $self->{_dbh};
    $self->{_ReporterList} = join( ',', map { $_->[0] } @{ $self->{_Data} } );

    return;
}

#######################################################################################
#Get a list of the probes here so that we can get all experiment data for each probe in another query.
#######################################################################################
sub loadProbeData {
    my ( $self, $qtext ) = @_;

    $self->{_ProbeRecords}  = $self->{_dbh}->prepare( $self->{_ProbeQuery} );
    $self->{_ProbeCount}    = $self->{_ProbeRecords}->execute($qtext);
    $self->{_ProbeColNames} = @{ $self->{_ProbeRecords}->{NAME} };
    $self->{_Data}          = $self->{_ProbeRecords}->fetchall_arrayref;
    $self->{_ProbeRecords}->finish;

    if ( scalar( @{ $self->{_Data} } ) < 1 ) {
        $self->{_UserSession}->commit() if defined($self->{_UserSession});
        my $cookie_array = (defined $self->{_UserSession})
            ? $self->{_UserSession}->cookie_array()
            : [];
        print $self->{_cgi}->header(
            -type   => 'text/html',
            -cookie => $cookie_array
        );
        print
'No records found! Please click back on your browser and search again!';
        exit;
    }

# Find the number of columns and subtract one to get the index of the last column
# This index value is needed for slicing of rows...
    my $last_index = scalar( @{ $self->{_ProbeRecords}->{NAME} } ) - 1;

# From each row in _Data, create a key-value pair such that the first column
# becomes the key and the rest of the columns are sliced off into an anonymous array
    my %trans_hash =
      map { $_->[0] => [ @$_[ 1 .. $last_index ] ] } @{ $self->{_Data} };
    $self->{_ProbeHash} = \%trans_hash;

    return;
}

#######################################################################################
#For each probe in the list get all the experiment data.
#######################################################################################
sub loadExperimentData {
    my $self                 = shift;
    my $experimentDataString = '';

    $self->{_ProbeExperimentHash}     = {};
    $self->{_ExperimentListHash}      = {};
    $self->{_ExperimentStudyListHash} = {};
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
    my $sth   = $self->{_dbh}->prepare($self->{_ExperimentDataQuery});

    foreach my $key ( keys %{ $self->{_ProbeHash} } ) {
        my $rc    = $sth->execute($key);
        my $tmp = $sth->fetchall_arrayref;

        #We use a temp hash that gets added to the _ProbeExperimentHash.
        my %tempHash;

        #For each experiment
        foreach ( @$tmp ) {
            # EID => [ratio, foldchange, pvalue, intensity1, intensity2]
            $tempHash{ $_->[0] } = [ @$_[ 1 .. 5 ] ];

            # EID => PID
            $self->{_ExperimentListHash}->{ $_->[0] } = $_->[8];

            # [EID, STID] => 1
            $self->{_ExperimentStudyListHash}->{ $_->[0] . '|' . $_->[7] } = 1;

            # EID => Name
            $self->{_ExperimentNameListHash}->{ $_->[0] } = $_->[6];

        }

        #Add the hash of experiment data to the hash of reporters.
        $self->{_ProbeExperimentHash}->{$key} = \%tempHash;

    }
    $sth->finish;
    return;
}

#######################################################################################
#Print the data from the hashes into a CSV file.
#######################################################################################
sub printFindProbeCSV {
    my $self       = shift;
    my $currentPID = 0;

    #Clear our headers so all we get back is the CSV file.
    $self->{_UserSession}->commit() if defined($self->{_UserSession});
    my $cookie_array = (defined $self->{_UserSession}) 
        ?  $self->{_UserSession}->cookie_array() 
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

    print 'Find Probes Report,' . localtime() . "\n";
    print "Generated by,$generatedByText\n";
    print "Working Project,$workingProjectText\n\n";

    #Sort the hash so the PID's are together.
    foreach my $key (
        sort {
            $self->{_ProbeHash}->{$a}->[0] cmp $self->{_ProbeHash}->{$b}->[0]
        }
        keys %{ $self->{_ProbeHash} }
      )
    {

        # This lets us know if we should print the headers.
        my $printHeaders = 0;

        # Extract the PID from the string in the hash.
        my $row = $self->{_ProbeHash}->{$key};

        if ( $currentPID == 0 ) {

            # grab first PID from the hash
            $currentPID   = $row->[0];
            $printHeaders = 1;
        }
        elsif ( $row->[0] != $currentPID ) {

            # if different from the current one, print a seperator
            print "\n\n";
            $currentPID   = $row->[0];
            $printHeaders = 1;
        }

        if ( $printHeaders == 1 ) {

            #Print the name of the current platform.
            print "\"$self->{_PlatformInfoHash}->{$currentPID}\"\n";
            print
"Experiment Number,Study Description, Experiment Heading,Experiment Description\n";

            #String representing the list of experiment names.
            my $experimentList = ",,,,,,,";

  #Temporarily hold the string we are to output so we can trim the trailing ",".
            my $outLine = "";

 #Loop through the list of experiments and print out the ones for this platform.
            foreach my $value ( sort { $a <=> $b }
                keys %{ $self->{_ExperimentListHash} } )
            {
                if ( $self->{_ExperimentListHash}->{$value} == $currentPID ) {
                    my $currentLine = "";

                    $currentLine .= $value . ",";
                    $currentLine .=
                      $self->{_FullExperimentData}->{$value}->{description}
                      . ",";
                    $currentLine .=
                      $self->{_FullExperimentData}->{$value}
                      ->{experimentHeading} . ",";
                    $currentLine .=
                      $self->{_FullExperimentData}->{$value}
                      ->{ExperimentDescription};

                    #Current experiment name.
                    my $currentExperimentName =
                      $self->{_ExperimentNameListHash}->{$value};
                    $currentExperimentName =~ s/\,//g;

 #Experiment Number,Study Description, Experiment Heading,Experiment Description
                    print "$currentLine\n";

  #The list of experiments goes with the Ratio line for each block of 5 columns.
                    $experimentList .= "$value : $currentExperimentName,,,,,,";

#Form the line that goes above the data. Each experiment gets a set of 5 columns.
                    $outLine .=
",$value:Ratio,$value:FC,$value:P-Val,$value:Intensity1,$value:Intensity2,";
                }
            }

            #Trim trailing comma off experiment list.
            $experimentList =~ s/\,$//;

            #Trim trailing comma off data row header.
            $outLine =~ s/\,$//;

            #Print list of experiments.
            print "$experimentList\n";

            #Print header line for probe rows.
            print
"Reporter ID,Accession Number, Gene Name,Probe Sequence,Gene Description,Gene Ontology,$outLine\n";
        }

      #Trim any commas out of the Gene Name, Gene Description, and Gene Ontology
        my $geneName = ( defined( $row->[4] ) ) ? $row->[4] : '';
        $geneName =~ s/\,//g;
        my $probeSequence = ( defined( $row->[6] ) ) ? $row->[6] : '';
        $probeSequence =~ s/\,//g;
        my $geneDescription = ( defined( $row->[7] ) ) ? $row->[7] : '';
        $geneDescription =~ s/\,//g;
        my $geneOntology = ( defined( $row->[8] ) ) ? $row->[8] : '';
        $geneOntology =~ s/\,//g;

# Print the probe info:
# Reporter ID,Accession,Gene Name, Probe Sequence, Gene description, Gene Ontology
        my $outRow =
"$row->[1],$row->[3],$geneName,$probeSequence,$geneDescription,$geneOntology,,";

#For this reporter we print out a column for all the experiments that we have data for.
        foreach my $EIDvalue ( sort { $a <=> $b }
            keys %{ $self->{_ExperimentListHash} } )
        {
            #Only try to see the EID's for platform $currentPID.
            if ( $self->{_ExperimentListHash}->{$EIDvalue} == $currentPID ) {

                # Add all the experiment data to the output string.
                my $outputColumns =
                  $self->{_ProbeExperimentHash}->{$key}->{$EIDvalue};
                my @outputColumns_array = (defined $outputColumns) 
                                        ? @$outputColumns
                                        : map {undef} 1..5;
                $outRow .= join( ',', 
                    map {(defined $_) ? $_ : ''} @outputColumns_array 
                ) . ',,';
            }
        }

        print "$outRow\n";
    }
    return;
}

#######################################################################################
#Loop through the list of Reporters we are filtering on and create a list.
#######################################################################################
sub setProbeList {
    my $self = shift;

    my $dbh = $self->{_dbh};
    $self->{_ReporterList} = join( ',', keys %{ $self->{_ProbeHash} } );
    return;
}

#######################################################################################
#Loop through the list of Reporters we are filtering on and create a list.
#######################################################################################
sub getProbeList {
    my $self = shift;
    return $self->{_ReporterList};
}
#######################################################################################
#Loop through the list of experiments we are displaying and get the information on each.
# We need eid and stid for each.
#######################################################################################
sub getFullExperimentData {
    my $self = shift;

    my @eid_list;
    my @stid_list;

    foreach ( keys %{ $self->{_ExperimentStudyListHash} } ) {
        my ( $eid, $stid ) = split /\|/;
        push @eid_list,  $eid;
        push @stid_list, $stid;
    }

    my $eid_string  = join( ',', @eid_list );
    my $stid_string = join( ',', @stid_list );

    my $whereSQL;
    my $curr_proj = $self->{_WorkingProject};
    if ( defined($curr_proj) && $curr_proj ne '' ) {
        $curr_proj = $self->{_dbh}->quote($curr_proj);
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
    CONCAT(study.description, ': ', experiment.sample1, ' / ', experiment.sample2) AS title, 
    CONCAT(experiment.sample1, ' / ', experiment.sample2) AS experimentHeading,
    study.description,
    experiment.ExperimentDescription 
FROM experiment 
INNER JOIN StudyExperiment USING(eid)
INNER JOIN study USING(stid)
$whereSQL
END_query_titles_element

    $self->{_FullExperimentRec}   = $self->{_dbh}->prepare($query_titles);
    $self->{_FullExperimentCount} = $self->{_FullExperimentRec}->execute();
    $self->{_FullExperimentData} =
      $self->{_FullExperimentRec}->fetchall_hashref('eid');

    $self->{_FullExperimentRec}->finish;
    return;
}

#######################################################################################
sub list_yui_deps {
    my ( $self, $list ) = @_;
    push @$list,
      (
        'yahoo-dom-event/yahoo-dom-event.js', 'connection/connection-min.js',
        'dragdrop/dragdrop-min.js',           'container/container-min.js',
        'element/element-min.js',             'datasource/datasource-min.js',
        'paginator/paginator-min.js',         'datatable/datatable-min.js',
        'selector/selector-min.js'
      );
    return;
}

#===  FUNCTION  ================================================================
#         NAME:  getResultTableHTML
#      PURPOSE:  display results table for Find Probes
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getResultTableHTML {
    my $q   = shift;
    my @ret = (
        $q->h2( { -id => 'caption' }, '' ),
        $q->div(
            $q->a( { -id => 'probetable_astext' }, 'View as plain text' )
        ),
        $q->div( { -id => 'probetable' }, '' )
    );
    if ( $q->param('graph') ) {
        push @ret, $q->ul( { -id => 'graphs' }, '' );
    }
    return @ret;
}

#===  FUNCTION  ================================================================
#         NAME:  getFormHTML
#      PURPOSE:  display Find Probes form
#   PARAMETERS:  $q - CGI object
#                $action - name of the top-level action
#                $curr_proj - current working project
#      RETURNS:  List of strings representing HTML entities. The list can be
#      printed directly by calling `print @list'.
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getFormHTML {
    my ( $q, $action, $curr_proj ) = @_;

    my %type_dropdown;
    my $type_dropdown_t = tie(
        %type_dropdown, 'Tie::IxHash',
        'gene'       => 'Gene Symbols',
        'accnum' => 'Accession Numbers',
        'probe'      => 'Probes'
    );
    my %match_dropdown;
    my $match_dropdown_t = tie(
        %match_dropdown, 'Tie::IxHash',
        'full'   => 'Full Word',
        'prefix' => 'Prefix',
        'part'   => 'Part of the Word / Regular Expression*'
    );
    my %opts_dropdown;
    my $opts_dropdown_t = tie(
        %opts_dropdown, 'Tie::IxHash',
        '1' => 'Basic (names and ids only)',
        '2' => 'Full annotation',
        '3' => 'Full annotation with experiment data (CSV)'
    );
    my %trans_dropdown;
    my $trans_dropdown_t = tie(
        %trans_dropdown, 'Tie::IxHash',
        'fold' => 'Fold Change +/- 1',
        'ln'   => 'Log2 Ratio'
    );

    return $q->start_form(
        -method  => 'GET',
        -action  => $q->url( absolute => 1 ),
        -enctype => 'application/x-www-form-urlencoded'
      ),
      $q->h2('Find Probes'),
      $q->p('You can enter here a list of probes, accession numbers, or gene names. 
          The results will contain probes that are related to the search terms.'),
      $q->dl(
        $q->dt( $q->label( { -for => 'terms' }, 'Search term(s):' ) ),
        $q->dd(
            $q->textarea(
                -name     => 'terms',
                -id       => 'terms',
                -rows     => 10,
                -columns  => 50,
                -tabindex => 1
            ),
            $q->p( { -style => 'color:#777' }, 'Multiple entries have to be
                separated by commas or be on separate lines')
        ),
        $q->dt( $q->label( { -for => 'type' }, 'Search type:' ) ),
        $q->dd(
            $q->popup_menu(
                -name    => 'type',
                -id      => 'type',
                -default => 'gene',
                -values  => [ keys %type_dropdown ],
                -labels  => \%type_dropdown
            )
        ),
        $q->dt('Pattern to match:'),
        $q->dd(
            $q->radio_group(
                -tabindex  => 2,
                -name      => 'match',
                -linebreak => 'true',
                -default   => 'full',
                -values    => [ keys %match_dropdown ],
                -labels    => \%match_dropdown
            ),
            $q->p( { -style => 'color:#777' }, '* Example: "^cyp.b" (no
                quotation marks) would retrieve all genes starting with cyp.b
            where the period represents any one character (2, 3, 4, "a", etc.).
            See <a
            href="http://dev.mysql.com/doc/refman/5.0/en/regexp.html">this
            page</a> for more examples.')
        ),
        $q->dt( $q->label( { -for => 'opts' }, 'Display options:' ) ),
        $q->dd(
            $q->popup_menu(
                -tabindex => 3,
                -name     => 'opts',
                -id       => 'opts',
                -values   => [ keys %opts_dropdown ],
                -default  => '1',
                -labels   => \%opts_dropdown
            )
        ),
        $q->dt( { -id => 'graph_names' }, 
                $q->label({-for => 'graph'}, 'Differential Expression Graphs:') ),
        $q->dd(
            { -id => 'graph_values' },
            $q->checkbox(
                -tabindex => 4,
                -id       => 'graph',
                -checked  => 0,
                -name     => 'graph',
                -label    => ''
            ),
            $q->span({-style=>'color:#777;'}, '(Works best with Firefox; SVG
                support on Internet Explorer (IE) requires either IE 9 or Adobe
                SVG plugin)')
        ),
        $q->dt( { -id => 'graph_option_names' }, "Response variable:" ),
        $q->dd(
            { -id => 'graph_option_values' },
            $q->radio_group(
                -tabindex  => 5,
                -name      => 'trans',
                -linebreak => 'true',
                -default   => 'fold',
                -values    => [ keys %trans_dropdown ],
                -labels    => \%trans_dropdown
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->hidden( -name => 'proj', -value => $curr_proj ),
            $q->submit(
                -tabindex => 6,
                -class    => 'css3button',
                -name     => 'a',
                -value    => $action
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
    my ( $self, $type, %optarg ) = @_;

    my $tmpTable = $optarg{tmp_table};
    my $clause =
      ( defined $tmpTable )
      ? "INNER JOIN $tmpTable tmpTable ON tmpTable.searchField=%s"
      : 'WHERE %s REGEXP ?';

    switch ($type) {
        case 'probe' {
            $self->{_InsideTableQuery} = sprintf(<<"END_InsideTableQuery_probe",
SELECT
    g1.rid, g1.reporter, g1.note, g1.probe_sequence, g1.pid, 
    gid,
    COALESCE(g1.accnum, gene.accnum) AS accnum, 
    COALESCE(g1.seqname, gene.seqname) AS seqname, 
    description, 
    gene_note
FROM ( SELECT probe.rid, probe.reporter, probe.note, probe.probe_sequence, probe.pid, 
       accnum, seqname
        FROM gene 
        RIGHT JOIN annotates USING(gid)
        RIGHT JOIN probe USING(rid)
        $clause
        GROUP BY accnum, seqname
) AS g1
LEFT JOIN gene ON (g1.accnum=gene.accnum OR g1.seqname=gene.seqname)
GROUP BY gid

END_InsideTableQuery_probe
                'reporter'
            );
        }
        case 'gene' {
            $self->{_InsideTableQuery} = sprintf(<<"END_InsideTableQuery_gene",
SELECT 
    NULL AS rid, NULL AS reporter, NULL AS note, NULL AS probe_sequence, NULL AS pid, 
    gid, 
    COALESCE(g1.accnum, gene.accnum) AS accnum, 
    COALESCE(g1.seqname, gene.seqname) AS seqname, 
    description, 
    gene_note
FROM ( SELECT accnum, seqname
        FROM gene 
        $clause
        GROUP BY accnum, seqname
) AS g1
LEFT JOIN gene ON (g1.accnum=gene.accnum OR g1.seqname=gene.seqname)
GROUP BY gid

END_InsideTableQuery_gene
                'seqname'
            );
        }
        case 'accnum' {
            $self->{_InsideTableQuery} = sprintf(<<"END_InsideTableQuery_accnum",
SELECT 
    NULL AS rid, NULL AS reporter, NULL AS note, NULL AS probe_sequence, NULL AS pid, 
    gid, 
    COALESCE(g1.accnum, gene.accnum) AS accnum, 
    COALESCE(g1.seqname, gene.seqname) AS seqname, 
    description, 
    gene_note
FROM ( SELECT accnum, seqname
        FROM gene 
        $clause
        GROUP BY accnum, seqname
) AS g1
LEFT JOIN gene ON (g1.accnum=gene.accnum OR g1.seqname=gene.seqname)
GROUP BY gid

END_InsideTableQuery_accnum
                'accnum'
            );
        }
        else {
            SGX::Exception::User->throw( 
                error => "Unknown request parameter value type=$type\n"
            );
        }
    }
    return 1;
}
#######################################################################################
sub build_ProbeQuery {
    my ( $self, %p ) = @_;
    my $sql_select_fields     = '';
    my $sql_subset_by_project = '';
    my $curr_proj             = $self->{_WorkingProject};

    assert( defined( $p{extra_fields} ) );

    switch ( $p{extra_fields} ) {
        case 0 {

            # only probe ids (rid)
            $sql_select_fields = <<"END_select_fields_rid";
probe.rid,
platform.pid,
COALESCE(probe.reporter, g0.reporter) AS reporter,
GROUP_CONCAT(DISTINCT IF(ISNULL(g0.accnum),'NONE',g0.accnum) ORDER BY g0.seqname ASC separator ' # ') AS 'Accession',
IF(ISNULL(g0.seqname),'NONE',g0.seqname) AS 'Gene',
probe.probe_sequence AS 'Probe Sequence',
GROUP_CONCAT(DISTINCT g0.description ORDER BY g0.seqname ASC SEPARATOR '; ') AS 'Gene Description',
GROUP_CONCAT(DISTINCT gene_note ORDER BY g0.seqname ASC SEPARATOR '; ') AS 'Gene Ontology - Comment'
END_select_fields_rid
        }
        case 1 {

            # basic
            $sql_select_fields = <<"END_select_fields_basic";
probe.rid AS ID,
platform.pid AS PID,
COALESCE(probe.reporter, g0.reporter) AS Probe, 
platform.pname AS Platform,
GROUP_CONCAT(
    DISTINCT IF(ISNULL(g0.accnum), '', g0.accnum) 
    ORDER BY g0.seqname ASC SEPARATOR ','
) AS 'Accession No.', 
IF(ISNULL(g0.seqname), '', g0.seqname) AS 'Gene',
platform.species AS 'Species' 
END_select_fields_basic
        }
        else {

            # with extras
            $sql_select_fields = <<"END_select_fields_extras";
probe.rid AS ID,
platform.pid AS PID,
COALESCE(probe.reporter, g0.reporter) AS Probe, 
platform.pname AS Platform,
GROUP_CONCAT(
    DISTINCT IF(ISNULL(g0.accnum), '', g0.accnum) 
    ORDER BY g0.seqname ASC SEPARATOR ','
) AS 'Accession No.', 
IF(ISNULL(g0.seqname), '', g0.seqname) AS 'Gene',
platform.species AS 'Species', 
probe.probe_sequence AS 'Probe Sequence',
GROUP_CONCAT(
    DISTINCT g0.description ORDER BY g0.seqname ASC SEPARATOR '; '
) AS 'Gene Description',
GROUP_CONCAT(
    DISTINCT gene_note ORDER BY g0.seqname ASC SEPARATOR '; '
) AS 'Gene Ontology - Comment'
END_select_fields_extras
        }
    }

    if ( defined($curr_proj) && $curr_proj ne '' ) {
        $curr_proj             = $self->{_dbh}->quote($curr_proj);
        $sql_subset_by_project = <<"END_sql_subset_by_project"
INNER JOIN study ON study.pid=platform.pid
INNER JOIN ProjectStudy USING(stid) 
WHERE prid=$curr_proj 
END_sql_subset_by_project
    }
    my $InsideTableQuery = $self->{_InsideTableQuery};
    $self->{_ProbeQuery} = <<"END_ProbeQuery";
SELECT
$sql_select_fields
FROM ( $InsideTableQuery ) AS g0
LEFT JOIN annotates USING(gid)
INNER JOIN probe ON probe.rid=COALESCE(g0.rid, annotates.rid)
INNER JOIN platform ON platform.pid=COALESCE(probe.pid, g0.pid)
$sql_subset_by_project
GROUP BY COALESCE(g0.rid, annotates.rid)
END_ProbeQuery

    return;
}
#######################################################################################
sub findProbes_js {
    my $self = shift;

    $self->set_SearchItems(1);
    my $qtext = $self->{_SearchItems};

    # 'type' must always be set
    my $type = $self->{_cgi}->param('type');

    # call to build_InsideTableQuery() followed by one to build_ProbeQuery()
    $self->build_InsideTableQuery($type);

    my $opts =
      ( defined( $self->{_cgi}->param('opts') ) )
      ? $self->{_cgi}->param('opts')
      : 1;
    $self->build_ProbeQuery( extra_fields => $opts );

    my $trans =
      ( defined( $self->{_cgi}->param('trans') ) )
      ? $self->{_cgi}->param('trans')
      : 'fold';

    if ( $opts == 3 ) {

    #---------------------------------------------------------------------------
    #  CSV output
    #---------------------------------------------------------------------------
        $self->{_UserSession}->commit();

#print $self->{_cgi}->header(-type=>'text/html', -cookie=>\@SGX::Cookie::cookies);
        $self->{_SearchType} = $type;
        $self->{_SearchText} = $qtext;

        #$self->setInsideTableQuery($g0_sql);
        $self->loadProbeData($qtext);
        $self->loadExperimentData();
        $self->fillPlatformHash();
        $self->getFullExperimentData();
        $self->printFindProbeCSV();
        exit;
    }
    else {

    #---------------------------------------------------------------------------
    #  HTML output
    #---------------------------------------------------------------------------
        my $sth      = $self->{_dbh}->prepare( $self->{_ProbeQuery} );
        my $rowcount = $sth->execute($qtext);

        my $proj_name = $self->{_WorkingProjectName};
        my $caption =
            sprintf( <<"END_caption",
%sFound %d probe%s annotated with $type groups matching '$qtext' (${type}s grouped
by gene symbol or accession number)
END_caption
            (defined($proj_name) and $proj_name ne '') ? "${proj_name}: " : '',
            $rowcount,
            ( $rowcount == 1 ) ? '' : 's'
        );

        # cache the field name array; skip first two columns (probe.rid,
        # platform.pid)
        my $all_names  = $sth->{NAME};
        my $last_index = scalar(@$all_names) - 1;
        my @names      = @$all_names[ 2 .. $last_index ];

        # data are sent as a JSON object plus Javascript code
        my @json_records;
        my $data = $sth->fetchall_arrayref;
        $sth->finish;
        foreach my $array_ref (@$data) {

      # the below "trick" converts an array into a hash such that array elements
      # become hash values and array indexes become hash keys
            my $i = 0;
            my %row = map { $i++ => $_ } @$array_ref[ 2 .. $last_index ];
            push @json_records, \%row;
        }

        my %json_probelist = (
            caption => $caption,
            records => \@json_records,
            headers => \@names
        );

        my $print_graphs = $self->{_cgi}->param('graph');
        my $out = sprintf(
            <<"END_JSON_DATA",
var probelist = %s;
var url_prefix = "%s";
var response_transform = "%s";
var show_graphs = %s;
var extra_fields = %s;
var project_id = "%s";
END_JSON_DATA
            encode_json( \%json_probelist ),
            $self->{_cgi}->url( -absolute => 1 ),
            $trans,
            ( $print_graphs ) ? 'true' : 'false',
            ( $opts > 1 )     ? 'true' : 'false',
            $self->{_WorkingProject}
        );

        return $out;
    }
}

1;
