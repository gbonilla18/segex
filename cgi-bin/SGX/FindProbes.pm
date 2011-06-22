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

use base qw/Exporter/;

use Switch;
use CGI::Carp;
use Tie::IxHash;
use Data::Dumper;
use File::Basename;
use JSON::XS;
use File::Temp qw/tempfile/;

use SGX::Util qw/trim/;
use SGX::Debug qw/assert/;

our @EXPORT_OK =
  qw/getform_findProbes/;

sub new {
    # This is the constructor
    my ($class, $dbh, %param) = @_;

    my $self = {
        _dbh            => $dbh,
        _cgi        => $param{cgi},
        _UserSession    => $param{user_session},
        _SearchType        => undef,
        _SearchText        => undef,
        _ProbeRecords        => '',
        _ProbeCount        => 0,
        _ProbeColNames        => '',        
        _ProbeData        => '',
        _RecordsPlatform    => '',
        _ProbeHash        => '',
        _RowCountAll        => 0,
        _ProbeExperimentHash=> '',
        _Data            => '',        
        _eids            => '',
        _ExperimentRec        => '',
        _ExperimentCount    => 0,
        _ExperimentData        => '',
        _FullExperimentRec        => '',
        _FullExperimentCount    => 0,
        _FullExperimentData        => '',        
        _InsideTableQuery     => '',
        _SearchItems        => '',
        _PlatformInfoQuery    => "SELECT pid, pname FROM platform",
        _PlatformInfoHash    => '',
        _ProbeQuery         => '',

        _ProbeReporterQuery        => <<"END_ProbeReporterQuery",
SELECT DISTINCT rid
FROM (
    SELECT gid
    FROM ({0}) AS g1
    INNER JOIN gene ON (g1.accnum=gene.accnum OR g1.seqname=gene.seqname)
    GROUP BY gid
) as g0
INNER JOIN annotates USING(gid)
INNER JOIN probe USING(rid)
END_ProbeReporterQuery

        _ExperimentListHash     => '',
        _ExperimentStudyListHash    => '',        
        _TempTableID            => '',
        _ExperimentNameListHash     => '',
        _ExperimentDataQuery     => undef,
        _ReporterList        => undef
    };

    # find out what the current project is set to
    if (defined($self->{_UserSession})) {
        #$self->{_UserSession}->read_perm_cookie();
        $self->{_WorkingProject} = 
            $self->{_UserSession}->{session_cookie}->{curr_proj};
        $self->{_WorkingProjectName} = 
            $self->{_UserSession}->{session_cookie}->{proj_name};
        $self->{_UserFullName} =
            $self->{_UserSession}->{session_cookie}->{full_name};
    }

    #Reporter,Accession Number, Gene Name, Probe Sequence, {Ratio,FC,P-Val,Intensity1,Intensity2}    
    
    bless $self, $class;
    return $self;
}
#######################################################################################

sub build_ExperimentDataQuery
{
    my $self = shift;
    my $whereSQL;
    my $curr_proj = $self->{_WorkingProject};
    if (defined($curr_proj) && $curr_proj ne '') {
        $curr_proj = $self->{_dbh}->quote($curr_proj);
        $whereSQL = <<"END_whereSQL";
INNER JOIN ProjectStudy USING(stid)
WHERE prid=$curr_proj AND rid=?
END_whereSQL
    } else {
        $whereSQL = 'WHERE rid=?';
    }
    $self->{_ExperimentDataQuery} = <<"END_ExperimentDataQuery";
SELECT
    experiment.eid, 
    microarray.ratio,
    microarray.foldchange,
    microarray.pvalue,
    IFNULL(microarray.intensity1,0),
    IFNULL(microarray.intensity2,0),
    CONCAT(
        study.description, ': ', 
        experiment.sample2, '/', experiment.sample1
    ) AS 'Name',
    study.stid,
    study.pid
FROM microarray 
INNER JOIN experiment USING(eid)
INNER JOIN StudyExperiment USING(eid)
INNER JOIN study USING(stid)
$whereSQL
ORDER BY experiment.eid ASC
END_ExperimentDataQuery
}

sub set_SearchItems
{
    my ($self, $mode) = @_;

    # 'text' must always be set
    my $text = $self->{_cgi}->param('text') 
        or croak 'No search terms specified';

    #This will be the array that holds all the splitted items.
    my @textSplit;    
    #If we find a comma, split on that, otherwise we split on new lines.
    if ($text =~ m/,/) {
        #Split the input on commas.    
        @textSplit = split(/\,/,trim($text));
    } else {
        #Split the input on the new line.    
        @textSplit = split(/\r\n/,$text);
    }
    
    #Get the count of how many search terms were found.
    my $searchesFound = @textSplit;
    my $qtext;
    if($searchesFound < 2) {
        my $match = (defined($self->{_cgi}->param('match'))) 
                    ? $self->{_cgi}->param('match') 
                    : 'full';
        switch ($match) {
            case 'full'    { $qtext = '^'.$textSplit[0].'$' }
            case 'prefix'  { $qtext = '^'.$textSplit[0] }
            case 'part'    { $qtext = $textSplit[0] } 
            else           { croak "Invalid match value $match" }
        }
    } else {
        if ($mode == 0) {
            $qtext = join('|',
                map { '^' . trim($_) . '$' } @textSplit);
        } else {
            $qtext = '^' . join('|',
                map { trim($_) } @textSplit) . '$';
        }
    }
    $self->{_SearchItems} = $qtext;
    return;
}
#######################################################################################
#This is the code that generates part of the SQL statement.
#######################################################################################
sub createInsideTableQuery
{
    my $self = shift;
    $self->set_SearchItems(0);

    # 'type' must always be set
    my $type = $self->{_cgi}->param('type') 
        or croak "You did not specify where to search";

    $self->build_InsideTableQuery($type);
    return;
}

#######################################################################################
#This is the code that generates part of the SQL statement (From a file instead of a list of genes).
#######################################################################################
sub createInsideTableQueryFromFile
{
    #Get the probe object.
    my $self = shift;

    #This is the type of search.
    # 'type' must always be set
    my $type = $self->{_cgi}->param('type') 
        or croak "You did not specify where to search";
    
    #This is the file that was uploaded.
    my $uploadedFile = $self->{_cgi}->upload('gene_file')
        or croak "No file to upload";

    #We need to get the list from the user into SQL, We need to do some temp table/file trickery for this.
    #Get time to make our unique ID.
    my $time          = time();
    #Make idea with the time and ID of the running application.
    my $processID     = $time. '_' . getppid();
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
    while ( <$uploadedFile> )
    {
        #Grab the current line (Or Whole file if file is using Mac line endings).
        #Replace all carriage returns, or carriage returns and line feed with just a line feed.
        $_ =~ s/(\r\n|\r)/\n/g;
        print {$outputToServer} $_;
    }
    close($outputToServer);

    #--------------------------------------------
    #Now get the temp file into a temp MYSQL table.

    #Command to create temp table.
    my $createTableStatement = "CREATE TABLE $processID (searchField VARCHAR(200))";

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
    $self->{_dbh}->do($createTableStatement)
        or croak $self->{_dbh}->errstr;

    #Run the command to suck in the data.
    $self->{_dbh}->do($inputStatement, undef, $outputFileName)
        or croak $self->{_dbh}->errstr;

    # Delete the temporary file we created:
    #unlink($outputFileName);
    #--------------------------------------------

    $self->build_InsideTableQuery($type, tmp_table => $processID);
    $self->{_SearchItems} = undef;
    return;
}

#######################################################################################
#Return the inside table query.
#######################################################################################
sub getInsideTableQuery
{
    my $self = shift;
    return $self->{_InsideTableQuery};
}

#######################################################################################
#Return the search terms used in the query.
#######################################################################################
sub getQueryTerms
{
    my $self = shift;
    return $self->{_SearchItems};
}

#######################################################################################
#Fill a hash with platform name and ID so we print it for the seperators.
#######################################################################################
sub fillPlatformHash
{
    my $self = shift;

    my $tempPlatformQuery = $self->{_PlatformInfoQuery};
    my $platformRecords = $self->{_dbh}->prepare($tempPlatformQuery)
        or croak $self->{_dbh}->errstr;
    my $platformCount = $platformRecords->execute()
        or croak $self->{_dbh}->errstr;
    my $platformData = $platformRecords->fetchall_arrayref;
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
sub loadProbeReporterData
{
    my ($self, $qtext) = @_;
    
    my $probeQuery                = $self->{_ProbeReporterQuery};
    
    $probeQuery                 =~ s/\{0\}/\Q$self->{_InsideTableQuery}\E/;
    $probeQuery                 =~ s/\\//g;

    $self->{_ProbeRecords}    = $self->{_dbh}->prepare($probeQuery)
        or croak $self->{_dbh}->errstr;
    $self->{_ProbeCount}    = $self->{_ProbeRecords}->execute()
        or croak $self->{_dbh}->errstr;    
    $self->{_ProbeColNames} = @{$self->{_ProbeRecords}->{NAME}};
    $self->{_Data}            = $self->{_ProbeRecords}->fetchall_arrayref;
    
    $self->{_ProbeRecords}->finish;
    
    $self->{_ProbeHash}     = {};
    
    my $DataCount            = @{$self->{_Data}};
    
    # For the situation where we created a temp table for the user input, 
    # we need to drop that temp table. This is the command to drop the temp table.
    my $dropStatement = 'DROP TABLE ' . $self->{_TempTableID} . ';';    
    
    #Run the command to drop the temp table.
    $self->{_dbh}->do($dropStatement) 
        or croak $self->{_dbh}->errstr;
    
    if($DataCount < 1)
    {
        print $self->{_cgi}->header(-type=>'text/html',
            -cookie=>SGX::Cookie::cookie_array());
        print 'No records found! Please click back on your browser and search again!';
        exit;
    }
    
    #foreach (@{$self->{_Data}}) {
    #    foreach (@$_) {
    #        $_ = '' if !defined $_;
    #        $_ =~ s/"//g;
    #    }
    #    $self->{_ReporterList} .= "'$_->[0]',";
    #}    
    ##Trim trailing comma off.
    #$self->{_ReporterList} =~ s/\,$//;    

    my $dbh = $self->{_dbh};
    $self->{_ReporterList} = join(',',
        map { $_->[0] } @{$self->{_Data}});

    return;
}

#######################################################################################
#Get a list of the probes here so that we can get all experiment data for each probe in another query.
#######################################################################################
sub loadProbeData
{
    my ($self, $qtext) = @_;
    
    $self->{_ProbeRecords} = $self->{_dbh}->prepare($self->{_ProbeQuery})
        or croak $self->{_dbh}->errstr;
    $self->{_ProbeCount} = $self->{_ProbeRecords}->execute($qtext)
        or croak $self->{_dbh}->errstr;    
    $self->{_ProbeColNames} = @{$self->{_ProbeRecords}->{NAME}};
    $self->{_Data} = $self->{_ProbeRecords}->fetchall_arrayref;
    $self->{_ProbeRecords}->finish;
    
    if(scalar(@{$self->{_Data}}) < 1)
    {
        print $self->{_cgi}->header(-type=>'text/html',
            -cookie=>SGX::Cookie::cookie_array());
        print 'No records found! Please click back on your browser and search again!';
        exit;
    }

    # Find the number of columns and subtract one to get the index of the last column
    # This index value is needed for slicing of rows...
    my $last_index = scalar(@{$self->{_ProbeRecords}->{NAME}}) - 1;

    # From each row in _Data, create a key-value pair such that the first column
    # becomes the key and the rest of the columns are sliced off into an anonymous array
    my %trans_hash = map { $_->[0] => [@$_[1..$last_index]] } @{$self->{_Data}};
    $self->{_ProbeHash} = \%trans_hash; 

    #$self->{_ProbeHash}     = {};
    #foreach (@{$self->{_Data}}) 
    #{
    #    #foreach (@$_)
    #    #{
    #    #    $_ = '' if !defined $_;
    #    #    $_ =~ s/"//g;
    #    #}
    #    $self->{_ProbeHash}->{$_->[0]} = [@$_[1..$last_index]];
    #    #[$_->[1], $_->[2], $_->[3], $_->[4], $_->[5], $_->[6]];
    #    #"$_->[1]|$_->[2]|$_->[3]|$_->[4]|$_->[5]|$GOField|";
    #}
    return;
}

#######################################################################################
#For each probe in the list get all the experiment data.
#######################################################################################
sub loadExperimentData
{
    my $self                         = shift;
    my $experimentDataString        = '';
    
    $self->{_ProbeExperimentHash}        = {};
    $self->{_ExperimentListHash}        = {};
    $self->{_ExperimentStudyListHash}    = {};
    $self->{_ExperimentNameListHash}    = {};
    
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

    #while (my ($key, $splitPlatformID) = each %{$self->{_ProbeHash}})
    foreach my $key (keys %{$self->{_ProbeHash}})
    {
        $self->build_ExperimentDataQuery();
        my $tempReportQuery = $self->{_ExperimentDataQuery};
        #$tempReportQuery                 =~ s/\{1\}/\Q$sql_trans\E/;
        #$tempReportQuery                 =~ s/\\//g;

        $self->{_ExperimentRec} = $self->{_dbh}->prepare($tempReportQuery)     
            or croak $self->{_dbh}->errstr;
        $self->{_ExperimentCount} = $self->{_ExperimentRec}->execute($key)
            or croak $self->{_dbh}->errstr;    
        $self->{_ExperimentData} = $self->{_ExperimentRec}->fetchall_arrayref;
        $self->{_ExperimentRec}->finish;
        
        #We use a temp hash that gets added to the _ProbeExperimentHash.
        my %tempHash;
        
        #For each experiment we get, stash the results in a string 
        foreach(@{$self->{_ExperimentData}})
        {
            #This is a | seperated string with all the experiment info.
            #$experimentDataString = $_->[1] . '|' . $_->[2] . '|' . $_->[3] . '|' . $_->[4] . '|' . $_->[5];

            #Add this experiment to the hash which will have all the experiments and their data for a given reporter.
            #$tempHash{$_->[0]} = $experimentDataString;
            $tempHash{$_->[0]} = [@$_[1..5]];

            #Keep a hash of EID and PID.
            $self->{_ExperimentListHash}->{$_->[0]} = $_->[8];

            #Keep a hash of EID and STID.
            $self->{_ExperimentStudyListHash}->{$_->[0] . '|' . $_->[7]} = 1;
            
            #Keep a hash of experiment names and EID.            
            $self->{_ExperimentNameListHash}->{$_->[0]} = $_->[6];
            
        }

        #Add the hash of experiment data to the hash of reporters.
        $self->{_ProbeExperimentHash}->{$key} = \%tempHash;

    }
    return;    
}

#######################################################################################
#Print the data from the hashes into a CSV file.
#######################################################################################
sub printFindProbeCSV
{
    my $self                     = shift;
    my $currentPID                = 0;

    #Clear our headers so all we get back is the CSV file.
    print $self->{_cgi}->header(-type=>'text/csv',-attachment => 'results.csv',
        -cookie=>SGX::Cookie::cookie_array());

    #Print a line to tell us what report this is.
    my $workingProjectText = 
        (defined($self->{_WorkingProjectName}))
        ? $self->{_WorkingProjectName}
        : 'N/A';

    my $generatedByText = 
        (defined($self->{_UserFullName}))
        ? $self->{_UserFullName}
        : '';

    print 'Find Probes Report,' . localtime() . "\n";
    print "Generated by,$generatedByText\n";
    print "Working Project,$workingProjectText\n\n";
    
    #Sort the hash so the PID's are together.
    foreach my $key (
        sort { $self->{_ProbeHash}->{$a}->[0] cmp $self->{_ProbeHash}->{$b}->[0] } 
        keys %{$self->{_ProbeHash}})
    {
        # This lets us know if we should print the headers.
        my $printHeaders            = 0;    
    
        # Extract the PID from the string in the hash.
        my $row = $self->{_ProbeHash}->{$key};
    
        if ($currentPID == 0) {
            # grab first PID from the hash 
            $currentPID = $row->[0];
            $printHeaders = 1;
        } elsif($row->[0] != $currentPID) {
            # if different from the current one, print a seperator
            print "\n\n";
            $currentPID = $row->[0];
            $printHeaders = 1;
        }
        
        if($printHeaders==1)
        {
            #Print the name of the current platform.
            print "\"$self->{_PlatformInfoHash}->{$currentPID}\"\n";
            print "Experiment Number,Study Description, Experiment Heading,Experiment Description\n";
            
            #String representing the list of experiment names.
            my $experimentList = ",,,,,,,";
            
            #Temporarily hold the string we are to output so we can trim the trailing ",".
            my $outLine = "";

            #Loop through the list of experiments and print out the ones for this platform.
            foreach my $value (sort{$a <=> $b} keys %{$self->{_ExperimentListHash}})
            {
                #warn 'val '  .$self->{_ExperimentListHash}->{$value};
                #warn 'currentPID: ' . $currentPID;
                if($self->{_ExperimentListHash}->{$value} == $currentPID)
                {
                    my $currentLine = "";
                
                    $currentLine .= $value . ",";
                    $currentLine .= $self->{_FullExperimentData}->{$value}->{description} . ",";
                    $currentLine .= $self->{_FullExperimentData}->{$value}->{experimentHeading} . ",";
                    $currentLine .= $self->{_FullExperimentData}->{$value}->{ExperimentDescription};
                    
                    #Current experiment name.
                    my $currentExperimentName = $self->{_ExperimentNameListHash}->{$value};
                    $currentExperimentName =~ s/\,//g;
                    
                    #Experiment Number,Study Description, Experiment Heading,Experiment Description
                    print "$currentLine\n";
                    
                    #The list of experiments goes with the Ratio line for each block of 5 columns.
                    $experimentList .= "$value : $currentExperimentName,,,,,,";                    
                    
                    #Form the line that goes above the data. Each experiment gets a set of 5 columns.
                    $outLine .= ",$value:Ratio,$value:FC,$value:P-Val,$value:Intensity1,$value:Intensity2,";                    
                }
            }
            
            #Trim trailing comma off experiment list.
            $experimentList =~ s/\,$//;
            
            #Trim trailing comma off data row header.
            $outLine =~ s/\,$//;
            
            #Print list of experiments.
            print "$experimentList\n";

            #Print header line for probe rows.
            print "Reporter ID,Accession Number, Gene Name,Probe Sequence,Gene Description,Gene Ontology,$outLine\n";
        }

        #Trim any commas out of the Gene Name, Gene Description, and Gene Ontology
        my $geneName        = (defined($row->[4])) ? $row->[4] : '';
        $geneName           =~ s/\,//g;
        my $probeSequence   = (defined($row->[6])) ? $row->[6] : '';
        $probeSequence      =~ s/\,//g;
        my $geneDescription = (defined($row->[7])) ? $row->[7] : '';
        $geneDescription    =~ s/\,//g;
        my $geneOntology    = (defined($row->[8])) ? $row->[8] : '';
        $geneOntology        =~ s/\,//g;
        
        # Print the probe info: 
        # Reporter ID,Accession,Gene Name, Probe Sequence, Gene description, Gene Ontology
        my $outRow = "$row->[1],$row->[3],$geneName,$probeSequence,$geneDescription,$geneOntology,,";
                
        #For this reporter we print out a column for all the experiments that we have data for.
        foreach my $EIDvalue (sort{$a <=> $b} keys %{$self->{_ExperimentListHash}})
        {
            #Only try to see the EID's for platform $currentPID.
            if($self->{_ExperimentListHash}->{$EIDvalue} == $currentPID)
            {
                #my %currentProbeExperimentHash;
                #%currentProbeExperimentHash = %{$self->{_ProbeExperimentHash}->{$key}};
                #Split the output string.
                #my @outputColumns = split(/\|/,$currentProbeExperimentHash{$EIDvalue});
                #foreach(@outputColumns)
                #{
                #    $outRow .= "$_,";
                #}
                #$outRow .= ",";
               
                # Add all the experiment data to the output string.
                my $outputColumns = $self->{_ProbeExperimentHash}->{$key}->{$EIDvalue};
                $outRow .= join(',', @$outputColumns) . ',,'; 
            }
        }
        
        print "$outRow\n";
    }
    return;
}

#######################################################################################
#Loop through the list of Reporters we are filtering on and create a list.
#######################################################################################
sub setProbeList
{
    my $self                     = shift;
    #$self->{_ReporterList}        = '';
    #foreach(keys %{$self->{_ProbeHash}}) {
    #    $self->{_ReporterList} .= "'$_',";
    #}
    ##Trim trailing comma off.
    #$self->{_ReporterList} =~ s/\,$//;    

    my $dbh = $self->{_dbh};    
    $self->{_ReporterList} = join(',', keys %{$self->{_ProbeHash}});
    return;
}

#######################################################################################
#Loop through the list of Reporters we are filtering on and create a list.
#######################################################################################
sub getProbeList
{
    my $self = shift;
    return $self->{_ReporterList};
}
#######################################################################################
#Loop through the list of experiments we are displaying and get the information on each. 
# We need eid and stid for each.
#######################################################################################
sub getFullExperimentData
{
    my $self = shift;

    my @eid_list;
    my @stid_list;

    foreach (keys %{$self->{_ExperimentStudyListHash}})
    {
        my ($eid, $stid) = split /\|/;
        push @eid_list, $eid;
        push @stid_list, $stid;
    }

    my $eid_string = join(',', @eid_list);
    my $stid_string = join(',', @stid_list);

    my $whereSQL;
    my $curr_proj = $self->{_WorkingProject};
    if (defined($curr_proj) && $curr_proj ne '') {
        $curr_proj = $self->{_dbh}->quote($curr_proj);
        $whereSQL = <<"END_whereTitlesSQL";
INNER JOIN ProjectStudy USING(stid)
WHERE prid=$curr_proj AND eid IN ($eid_string) AND study.stid IN ($stid_string)
END_whereTitlesSQL
    } else {
        $whereSQL = "WHERE eid IN ($eid_string) AND study.stid IN ($stid_string)";
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

    $self->{_FullExperimentRec} = $self->{_dbh}->prepare($query_titles) 
        or croak $self->{_dbh}->errstr;
    $self->{_FullExperimentCount} = $self->{_FullExperimentRec}->execute()
        or croak $self->{_dbh}->errstr;    
    $self->{_FullExperimentData} = $self->{_FullExperimentRec}->fetchall_hashref('eid');
    
    $self->{_FullExperimentRec}->finish;
    return;
}

#######################################################################################
sub list_yui_deps
{
    my ($self, $list) = @_;
    push @$list, (
        'yahoo-dom-event/yahoo-dom-event.js',
        'connection/connection-min.js',
        'dragdrop/dragdrop-min.js',
        'container/container-min.js',
        'element/element-min.js',
        'datasource/datasource-min.js',
        'paginator/paginator-min.js',
        'datatable/datatable-min.js',
        'selector/selector-min.js'
    );
    return;
}

#===  FUNCTION  ================================================================
#         NAME:  getform_findProbes
#      PURPOSE:  display Find Probes form
#   PARAMETERS:  $q - CGI object
#                $a - name of the top-level action
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getform_findProbes {
    my ($q, $a) = @_;

    my %type_dropdown;
    my $type_dropdown_t = tie(%type_dropdown, 'Tie::IxHash',
        'gene'=>'Gene Symbols',
        'transcript'=>'Transcripts',
        'probe'=>'Probes'
    );
    my %match_dropdown;
    my $match_dropdown_t = tie(%match_dropdown, 'Tie::IxHash',
        'full'=>'Full Word',
        'prefix'=>'Prefix',
        'part'=>'Part of the Word / Regular Expression*'
    );
    my %opts_dropdown;
    my $opts_dropdown_t = tie(%opts_dropdown, 'Tie::IxHash',
        '1'=>'Basic (names and ids only)',
        '2'=>'Full annotation',
        '3'=>'Full annotation with experiment data (CSV)'
    );
    my %trans_dropdown;
    my $trans_dropdown_t = tie(%trans_dropdown, 'Tie::IxHash',
        'fold' => 'Fold Change +/- 1', 
        'ln'=>'Log2 Ratio'
    );

    return $q->start_form(-method=>'GET',
        -action=>$q->url(absolute=>1),
        -enctype=>'application/x-www-form-urlencoded') .
    $q->h2('Find Probes') .
    $q->p('You can enter here a list of probes, transcript accession numbers, or gene names. The results will contain probes that are related to the search terms.') .
    $q->dl(
        $q->dt('Search term(s):'),
        $q->dd(
            $q->textarea(-name=>'address',-id=>'address',-rows=>10,-columns=>50,-tabindex=>1,
                -name=>'text'),
            $q->p({-style=>'color:#777'},'Multiple entries have to be separated by commas or be on separate lines')
        ),
        $q->dt('Search type :'),
        $q->dd($q->popup_menu(
                -name=>'type',
                -default=>'gene',
                -values=>[keys %type_dropdown],
                -labels=>\%type_dropdown
        )),
        $q->dt('Pattern to match :'),
        $q->dd(
            $q->radio_group(
                -tabindex=>2, 
                -name=>'match', 
                -linebreak=>'true', 
                -default=>'full', 
                -values=>[keys %match_dropdown], 
                -labels=>\%match_dropdown
            ), 
            $q->p({-style=>'color:#777'},'* Example: "^cyp.b" (no quotation marks) would retrieve all genes starting with cyp.b where the period represents any one character (2, 3, 4, "a", etc.). See <a href="http://dev.mysql.com/doc/refman/5.0/en/regexp.html">this page</a> for more examples.')
        ),
        $q->dt('Display options :'),
        $q->dd($q->popup_menu(
                -tabindex=>3, 
                -name=>'opts',
                -values=>[keys %opts_dropdown], 
                -default=>'1',
                -labels=>\%opts_dropdown
        )),
        $q->dt('Graph(s) :'),
        $q->dd($q->checkbox(-tabindex=>4, id=>'graph', -onclick=>'sgx_toggle(this.checked, [\'graph_option_names\', \'graph_option_values\']);', -checked=>0, -name=>'graph',-label=>'Show Differential Expression Graph')),
        $q->dt({id=>'graph_option_names'}, "Response variable:"),
        $q->dd({id=>'graph_option_values'}, $q->radio_group(
                -tabindex=>5, 
                -name=>'trans', 
                -linebreak=>'true', 
                -default=>'fold', 
                -values=>[keys %trans_dropdown], 
                -labels=>\%trans_dropdown
        )),
        $q->dt('&nbsp;'),
        $q->dd($q->submit(-tabindex=>6, -class=>'css3button', -name=>'a', -value=>$a, -override=>1)),
    ) 
    .
    $q->endform;
}
#######################################################################################
sub build_InsideTableQuery
{
    my ($self, $type, %optarg) = @_;

    my $tmpTable = $optarg{tmp_table};
    switch ($type) 
    {
        case 'probe' {
            my $clause = (defined $tmpTable)
                ? "INNER JOIN $tmpTable tmpTable ON tmpTable.searchField=reporter"
                : 'WHERE reporter REGEXP ?';
            $self->{_InsideTableQuery} = <<"END_InsideTableQuery_probe";
SELECT DISTINCT accnum, seqname
        FROM gene 
        RIGHT JOIN annotates USING(gid)
        RIGHT JOIN probe USING(rid)
        $clause
END_InsideTableQuery_probe
        }
        case 'gene' {
            my $clause = (defined $tmpTable)
                ? "INNER JOIN $tmpTable tmpTable ON tmpTable.searchField=seqname"
                : 'WHERE seqname REGEXP ?';
            $self->{_InsideTableQuery} = <<"END_InsideTableQuery_gene"
SELECT DISTINCT accnum, seqname
        FROM gene 
        $clause
END_InsideTableQuery_gene
        }
        case 'transcript' {
            my $clause = (defined $tmpTable)
                ? "INNER JOIN $tmpTable tmpTable ON tmpTable.searchField=accnum"
                : 'WHERE accnum REGEXP ?';
            $self->{_InsideTableQuery} = <<"END_InsideTableQuery_transcript";
SELECT DISTINCT accnum, seqname
        FROM gene 
        $clause
END_InsideTableQuery_transcript
        } 
        else {
            croak "Unknown request parameter value type=$type";
        }
    }
    return;
}
#######################################################################################
sub build_ProbeQuery
{
    my ($self, %p) = @_;
    my $sql_select_fields = '';
    my $sql_subset_by_project = '';
    my $curr_proj = $self->{_WorkingProject};

    assert(defined($p{extra_fields}));

    switch ($p{extra_fields}) {
        case 0 {
            # only probe ids (rid)
            $sql_select_fields = <<"END_select_fields_rid";
probe.rid,
platform.pid,
probe.reporter,
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
probe.reporter AS Probe, 
platform.pname AS Platform,
GROUP_CONCAT(
    DISTINCT IF(ISNULL(g0.accnum), '', g0.accnum) 
    ORDER BY g0.seqname ASC SEPARATOR ','
) AS 'Transcript', 
IF(ISNULL(g0.seqname), '', g0.seqname) AS 'Gene',
platform.species AS 'Species' 
END_select_fields_basic
        }
        else {
            # with extras
            $sql_select_fields = <<"END_select_fields_extras";
probe.rid AS ID,
platform.pid AS PID,
probe.reporter AS Probe, 
platform.pname AS Platform,
GROUP_CONCAT(
    DISTINCT IF(ISNULL(g0.accnum), '', g0.accnum) 
    ORDER BY g0.seqname ASC SEPARATOR ','
) AS 'Transcript', 
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

    if (defined($curr_proj) && $curr_proj ne '') {
        $curr_proj = $self->{_dbh}->quote($curr_proj);
        $sql_subset_by_project = <<"END_sql_subset_by_project"
INNER JOIN study USING(pid) 
INNER JOIN ProjectStudy USING(stid) 
WHERE prid=$curr_proj 
END_sql_subset_by_project
    }
    my $InsideTableQuery = $self->{_InsideTableQuery};
    $self->{_ProbeQuery} = <<"END_ProbeQuery";
SELECT
$sql_select_fields
FROM (
    SELECT 
        gid, 
        COALESCE(g1.accnum, gene.accnum) AS accnum, 
        COALESCE(g1.seqname, gene.seqname) AS seqname, 
        description, 
        gene_note
    FROM (
        $InsideTableQuery
    ) AS g1
    INNER JOIN gene ON (g1.accnum=gene.accnum OR g1.seqname=gene.seqname)
    GROUP BY gid
) AS g0
INNER JOIN annotates USING(gid)
INNER JOIN probe USING(rid)
INNER JOIN platform USING(pid)
$sql_subset_by_project
GROUP BY probe.rid
END_ProbeQuery
    return;
}
#######################################################################################
sub findProbes_js 
{
    my $self = shift;

    $self->set_SearchItems(1);
    my $qtext = $self->{_SearchItems};

    # 'type' must always be set
    my $type = $self->{_cgi}->param('type') 
        or croak "You did not specify where to search";

    $self->build_InsideTableQuery($type);

    my $opts = (defined($self->{_cgi}->param('opts'))) ? $self->{_cgi}->param('opts') : 1;
    $self->build_ProbeQuery(extra_fields => $opts);

    my $trans = (defined($self->{_cgi}->param('trans'))) ? $self->{_cgi}->param('trans') : 'fold';

    if ($opts == 3) {
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
        my $sth = $self->{_dbh}->prepare($self->{_ProbeQuery})
            or croak $self->{_dbh}->errstr;
        my $rowcount = $sth->execute($qtext) 
            or croak $self->{_dbh}->errstr;

        my $caption = sprintf("Found %d probe", $rowcount) .(($rowcount != 1) ? 's' : '')." annotated with $type groups matching '$qtext' (${type}s grouped by gene symbol or transcript accession number)";

        my @json_records;
        my %json_probelist = (
            caption => $caption,
            records => \@json_records
        );

        # cache the field name array; 
        # skip first two columns (probe.rid, platform.pid)
        my $all_names = $sth->{NAME};
        my $last_index = scalar(@$all_names) - 1;
        my @names = @$all_names[2..$last_index];

        my $data = $sth->fetchall_arrayref;
        $sth->finish;

        # data are sent as a JSON object plus Javascript code
        #foreach (sort {$a->[3] cmp $b->[3]} @$data) {
        foreach my $array_ref (@$data) {
            # the below "trick" converts an array into a hash such that array elements
            # become hash values and array indexes become hash keys
            my $i = 0;
            my %row = map { $i++ => $_ } @$array_ref[2..$last_index];
            push @json_records, \%row;
        }

        my $out = sprintf(<<"END_JSON_DATA",
var table_labels = %s;
var probelist = %s;
var url_prefix = "%s";
var response_transform = "%s";
var show_graphs = %s;
var extra_fields = %s;
END_JSON_DATA
            encode_json(\@names),
            encode_json(\%json_probelist),
            $self->{_cgi}->url(-absolute=>1),
            $trans,
            (defined($self->{_cgi}->param('graph'))) ? 'true' : 'false',
            ($opts > 1) ? 'true' : 'false'
        );

        return $out;
    }
}

1;
