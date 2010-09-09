=head1 NAME

SGX::FindProbes

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

package SGX::FindProbes;

use strict;
use warnings;
use Switch;

use Data::Dumper;

sub new {
	# This is the constructor
	my $class = shift;

	my $self = {
		_dbh			=> shift,
		_FormObject		=> shift,
		_ProbeRecords		=> '',
		_ProbeCount		=> 0,
		_ProbeColNames		=> '',		
		_ProbeData		=> '',
		_RecordsPlatform	=> '',
		_ProbeHash		=> '',
		_RowCountAll		=> 0,
		_ProbeExperimentHash=> '',
		_Data			=> '',		
		_eids			=> '',
		_ExperimentRec		=> '',
		_ExperimentCount	=> 0,
		_ExperimentData		=> '',
		_InsideTableQuery 	=> '',
		_SearchItems		=> '',
		_PlatformInfoQuery	=> "SELECT	pid,
							pname
					    FROM	platform",
		_PlatformInfoHash	=> '',
		_ProbeQuery		=> "
				select DISTINCT 
					coalesce(probe.reporter, g0.reporter) as Probe,
					platform.pid,					
					group_concat(DISTINCT IF(ISNULL(g0.accnum),'NONE',g0.accnum) ORDER BY g0.seqname ASC separator ' # ') AS 'Accession',
					IF(ISNULL(g0.seqname),'NONE',g0.seqname)                                                            AS 'Gene',
					coalesce(probe.probe_sequence, g0.probe_sequence) AS 'Probe Sequence'					
					from
					({0}) as g0
			left join (annotates natural join probe) on annotates.gid=g0.gid
			left join platform on platform.pid=coalesce(probe.pid, g0.pid)
			group by coalesce(probe.rid, g0.rid)
							",
		_ExperimentListHash 	=> '',
		_ExperimentNameListHash 	=> '',
		_ExperimentDataQuery 	=> "
					select 	experiment.eid, 
						microarray.ratio,
						microarray.foldchange,
						microarray.pvalue,
						IFNULL(microarray.intensity1,0),
						IFNULL(microarray.intensity2,0),
						concat(study.description, ': ', experiment.sample2, '/', experiment.sample1) AS 'Name'
					from	microarray 
					right join 
					(
						select distinct rid 
						from probe 
						where reporter='{0}'
					) as d3 on microarray.rid=d3.rid 
					NATURAL JOIN experiment 
					NATURAL JOIN StudyExperiment
					NATURAL JOIN study
					ORDER BY experiment.eid ASC
					",
		_ReporterList		=> ''
	};

	#Reporter,Accession Number, Gene Name, Probe Sequence, {Ratio,FC,P-Val,Intensity1,Intensity2}	
	
	bless $self, $class;
	return $self;
}

#######################################################################################
#This is the code that generates part of the SQL statement.
#######################################################################################
sub createInsideTableQuery
{
	my $self		= shift;

	my $text 		= $self->{_FormObject}->param('text') or die "You did not specify what to search for";	# must be always set -- no defaults
	my $type 		= $self->{_FormObject}->param('type') or die "You did not specify where to search";	# must be always set -- no defaults
	my $trans 		= (defined($self->{_FormObject}->param('trans'))) ? $self->{_FormObject}->param('trans') : 'fold';
	my $match 		= (defined($self->{_FormObject}->param('match'))) ? $self->{_FormObject}->param('match') : 'full';
	my $opts 		= (defined($self->{_FormObject}->param('opts'))) ? $self->{_FormObject}->param('opts') : 1;
	my $speciesColumn	= 5;

	my @extra_fields;

	switch ($opts) {
	case 0 {}
	case 1 { @extra_fields = ('coalesce(probe.note, g0.note) as \'Probe Specificity - Comment\', coalesce(probe.probe_sequence, g0.probe_sequence) AS \'Probe Sequence\'', 'group_concat(distinct g0.description order by g0.seqname asc separator \'; \') AS \'Gene Description\'', 'group_concat(distinct gene_note order by g0.seqname asc separator \'; \') AS \'Gene Specificity - Comment\'') }
	case 2 {}
	}

	my $extra_sql = (@extra_fields) ? ', '.join(', ', @extra_fields) : '';

	my $qtext;
	
	#This will be the array that holds all the splitted items.
	my @textSplit;	
	
	#If we find a comma, split on that, otherwise we split on new lines.
	if($text =~ m/,/)
	{
		#Split the input on commas.	
		@textSplit = split(/\,/,trim($text));
	}
	else
	{
		#Split the input on the new line.	
		@textSplit = split(/\r\n/,$text);
	}
	
	#Get the count of how many search terms were found.
	my $searchesFound = @textSplit;
	
	#This will be the string we output.
	my $out = "";

	if($searchesFound < 2)
	{
		switch ($match) 
		{
			case 'full'		{ $qtext = '^'.$textSplit[0].'$' }
			case 'prefix'	{ $qtext = '^'.$textSplit[0] }
			case 'part'		{ $qtext = $textSplit[0] } 
			else			{ assert(0) }
		}
	}
	else
	{
		#Begining of the SQL regex.
		$qtext = '^';
		
		#Add the search items seperated by a bar.
		foreach(@textSplit)
		{
			if($_)
			{
				$qtext .= trim($_) . "|";
			}
		}
		
		#Remove the double backslashes.
		$qtext =~ s/\|$//;
		
		#Add the closing regex character.
		$qtext .= '$';
	}
	
	my $g0_sql;
	switch ($type) 
	{
		case 'probe' 
		{
			$g0_sql = "
			select rid, reporter, note, probe_sequence, g1.pid, g2.gid, g2.accnum, g2.seqname, g2.description, g2.gene_note from gene g2 right join 
			(select distinct probe.rid, probe.reporter, probe.note, probe.probe_sequence, probe.pid, accnum from probe left join annotates on annotates.rid=probe.rid left join gene on gene.gid=annotates.gid where reporter REGEXP ?) as g1
			on g2.accnum=g1.accnum where rid is not NULL
			
			union

			select rid, reporter, note, probe_sequence, g3.pid, g4.gid, g4.accnum, g4.seqname, g4.description, g4.gene_note from gene g4 right join
			(select distinct probe.rid, probe.reporter, probe.note, probe.probe_sequence, probe.pid, seqname from probe left join annotates on annotates.rid=probe.rid left join gene on gene.gid=annotates.gid where reporter REGEXP ?) as g3
			on g4.seqname=g3.seqname where rid is not NULL
			";

		}
		case 'gene' 
		{
			$g0_sql = "
			select NULL as rid, NULL as note, NULL as reporter, NULL as probe_sequence, NULL as pid, g2.gid, g2.accnum, g2.seqname, g2.description, g2.gene_note from gene g2 right join
			(select distinct accnum from gene where seqname REGEXP ? and accnum is not NULL) as g1
			on g2.accnum=g1.accnum where g2.gid is not NULL

			union

			select NULL as rid, NULL as note, NULL as reporter, NULL as probe_sequence, NULL as pid, g4.gid, g4.accnum, g4.seqname, g4.description, g4.gene_note from gene g4 right join
			(select distinct seqname from gene where seqname REGEXP ? and seqname is not NULL) as g3
			on g4.seqname=g3.seqname where g4.gid is not NULL
			";
		}
		case 'transcript' 
		{
			$g0_sql = "
			select NULL as rid, NULL as note, NULL as reporter, NULL as probe_sequence, NULL as pid, g2.gid, g2.accnum, g2.seqname, g2.description, g2.gene_note from gene g2 right join
			(select distinct accnum from gene where accnum REGEXP ? and accnum is not NULL) as g1
			on g2.accnum=g1.accnum where g2.gid is not NULL

			union

			select NULL as rid, NULL as note, NULL as reporter, NULL as probe_sequence, NULL as pid, g4.gid, g4.accnum, g4.seqname, g4.description, g4.gene_note from gene g4 right join
			(select distinct seqname from gene where accnum REGEXP ? and seqname is not NULL) as g3
			on g4.seqname=g3.seqname where g4.gid is not NULL
			";
		} 
		else 
		{
			assert(0); # shouldn't happen
		}
	}
	
	$self->{_InsideTableQuery} 	= $g0_sql;
	$self->{_SearchItems} 		= $qtext;
}
#######################################################################################

#######################################################################################
#This gets set in the index.cgi page based on input parameters.
#######################################################################################
sub setInsideTableQuery
{
	my $self		= shift;
	my $tableQuery 	= shift;
	
	$self->{_InsideTableQuery} = $tableQuery;
}
#######################################################################################

#######################################################################################
#Return the inside table query.
#######################################################################################
sub getInsideTableQuery
{
	my $self		= shift;
		
	return $self->{_InsideTableQuery};
}
#######################################################################################

#######################################################################################
#Return the search terms used in the query.
#######################################################################################
sub getQueryTerms
{
	my $self		= shift;

	return $self->{_SearchItems};
}
#######################################################################################

#######################################################################################
#Fill a hash with platform name and ID so we print it for the seperators.
#######################################################################################
sub fillPlatformHash
{
	my $self		= shift;

	my $tempPlatformQuery 	= $self->{_PlatformInfoQuery};
	my $platformRecords	= $self->{_dbh}->prepare($tempPlatformQuery) 	or die $self->{_dbh}->errstr;
	my $platformCount 	= $platformRecords->execute() 					or die $self->{_dbh}->errstr;	
	my $platformData	= $platformRecords->fetchall_arrayref;

	$platformRecords->finish;

	#Initialize our hash.
	$self->{_PlatformInfoHash} = {};

	#For each probe we get add an item to the hash. 
	foreach(@{$platformData})
	{
		${$self->{_PlatformInfoHash}{$_->[0]}} = $_->[1];
	}
}
#######################################################################################

#######################################################################################
#Get a list of the probes here so that we can get all experiment data for each probe in another query.
#######################################################################################
sub loadProbeData
{
	my $self				= shift;
	my $qtext				= shift;
	
	my $probeQuery				= $self->{_ProbeQuery};
	
	$probeQuery 				=~ s/\{0\}/\Q$self->{_InsideTableQuery}\E/;
	$probeQuery 				=~ s/\\//g;
	
	$self->{_ProbeRecords}	= $self->{_dbh}->prepare($probeQuery) 				or die $self->{_dbh}->errstr;
	$self->{_ProbeCount}	= $self->{_ProbeRecords}->execute($qtext, $qtext) 	or die $self->{_dbh}->errstr;	
	$self->{_ProbeColNames} = @{$self->{_ProbeRecords}->{NAME}};
	$self->{_Data}			= $self->{_ProbeRecords}->fetchall_arrayref;
	
	$self->{_ProbeRecords}->finish;
	
	$self->{_ProbeHash} 	= {};
	
	my $DataCount			= @{$self->{_Data}};

	if($DataCount < 1)
	{
		print $self->{_FormObject}->header(-type=>'text/html', -cookie=>\@SGX::Cookie::cookies);
		print "No records found! Please click back on your browser and search again!";
		exit;
	}
	
	foreach (sort {$a->[1] cmp $b->[1]} @{$self->{_Data}}) 
	{
		foreach (@$_) 
		{
			$_ = '' if !defined $_;
			$_ =~ s/"//g;	# strip all double quotes (JSON data are bracketed with double quotes)
		}
		
		${$self->{_ProbeHash}}{$_->[0]} = "$_->[1]|$_->[2]|$_->[3]|$_->[4]";
	}	

}
#######################################################################################

#######################################################################################
#For each probe in the list get all the experiment data.
#######################################################################################
sub loadExperimentData
{
	my $self 						= shift;
	my $experimentDataString		= '';
	my $transform					= '';
	my $sql_trans					= '';
	
	$self->{_ProbeExperimentHash}		= {};
	$self->{_ExperimentListHash}		= {};
	$self->{_ExperimentNameListHash}	= {};
	
	#Grab the format for the output from the form.
	$transform 	= ($self->{_FormObject}->param('trans')) 	if defined($self->{_FormObject}->param('trans'));
	
	#Build SQL statement based on desired output type.
	switch ($transform) 
	{
		case 'fold'
		{
			$sql_trans = 'if(foldchange>0,foldchange-1,foldchange+1)';
		}
		case 'ln'
		{
			$sql_trans = 'if(foldchange>0, log2(foldchange), log2(-1/foldchange))';
		}
	}	
	
	foreach(keys %{$self->{_ProbeHash}})
	{
		my $tempReportQuery = $self->{_ExperimentDataQuery};

		$tempReportQuery 				=~ s/\{0\}/\Q$_\E/;
		$tempReportQuery 				=~ s/\{1\}/\Q$sql_trans\E/;
		$tempReportQuery 				=~ s/\\//g;
			
		$self->{_ExperimentRec} 		= $self->{_dbh}->prepare($tempReportQuery) 	or die $self->{_dbh}->errstr;
		$self->{_ExperimentCount} 		= $self->{_ExperimentRec}->execute() 		or die $self->{_dbh}->errstr;	
		$self->{_ExperimentData}		= $self->{_ExperimentRec}->fetchall_arrayref;
		$self->{_ExperimentRec}->finish;
		
		#We use a temp hash that gets added to the _ProbeExperimentHash.
		my %tempHash;
		
		#Extract the PID from the string in the hash.
		my @splitPlatformID = split(/\|/,${$self->{_ProbeHash}}{$_});
		
		#We need this platform ID to use later on.
		my $currentPID = $splitPlatformID[0];
		
		#For each experiment we get, stash the results in a string 
		foreach(@{$self->{_ExperimentData}})
		{
			#This is a | seperated string with all the experiment info.
			$experimentDataString = $_->[1] . '|' . $_->[2] . '|' . $_->[3] . '|' . $_->[4] . '|' . $_->[5];

			#Add this experiment to the hash which will have all the experiments and their data for a given reporter.
			$tempHash{$_->[0]} = $experimentDataString;

			#Keep a hash of EID and PID.
			${$self->{_ExperimentListHash}{$_->[0]}} = $currentPID;

			#Keep a hash of experiment names and EID.			
			${$self->{_ExperimentNameListHash}{$_->[0]}} = $_->[6];
			
		}

		#Add the hash of experiment data to the hash of reporters.
		${$self->{_ProbeExperimentHash}}{$_} = \%tempHash;

	}
	
}
#######################################################################################

#######################################################################################
#Print the data from the hashes into a CSV file.
#######################################################################################
sub printFindProbeCSV
{
	my $self 					= shift;
	my $currentPID				= 0;

	#Clear our headers so all we get back is the CSV file.
	print $self->{_FormObject}->header(-type=>'text/csv',-attachment => 'results.csv', -cookie=>\@SGX::Cookie::cookies);

	#Print a line to tell us what report this is.
	print "Find Probes Report," . localtime . "\n\n";	
	
	#Sort the hash so the PID's are together.
	foreach my $value (sort {$self->{_ProbeHash}{$a} cmp $self->{_ProbeHash}{$b} } keys %{$self->{_ProbeHash}})
	{

		#This lets us know if we should print the headers.
		my $printHeaders			= 0;	
	
		#Extract the PID from the string in the hash.
		my @splitPlatformID = split(/\|/,${$self->{_ProbeHash}}{$value});
	
		#If this is the first PID then grab it from the hash. If the hash is different from the current one put in a seperator.
		if($currentPID == 0)
		{
			$currentPID = $splitPlatformID[0];
			$printHeaders = 1;
		}
		elsif($splitPlatformID[0] != $currentPID)
		{
			print "\n";

			$currentPID = $splitPlatformID[0];
			$printHeaders = 1;
		}
		
		if($printHeaders==1)
		{
			#Print the name of the current platform.
			print "\"${$self->{_PlatformInfoHash}{$currentPID}}\"";
			print "\n";
			
			#String representing the list of experiment names.
			my $experimentList = ",,,,,";
			
			#Temporarily hold the string we are to output so we can trim the trailing ",".
			my $outLine = "";
			
			#Loop through the list of experiments and print out the ones for this platform.
			foreach my $value (sort{$a <=> $b} keys %{$self->{_ExperimentListHash}})
			{
				if(${$self->{_ExperimentListHash}{$value}} == $currentPID)
				{
					
					#Current experiment name.
					my $currentExperimentName = ${$self->{_ExperimentNameListHash}{$value}};
					$currentExperimentName =~ s/\,//g;
					
					#Print out current Experiment name with its eid.
					print "$value : $currentExperimentName\n";
					
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
			print $experimentList;
			print "\n";

			#Print header line for probe rows.
			print "Reporter ID,Accession Number, Gene Name,Probe Sequence,";
			
			print "$outLine\n";
					
		}
		
		#This is the line of data we will output. We need to trim the trailing comma.
		my $outRow = '';		
		
		#Print the probe ID.
		$outRow .= "$value,";

		#Trim any commas out of the Gene Name.
		my $geneName 	= $splitPlatformID[2];
		$geneName 		=~ s/\,//;
		
		#Print the probe info. (Accession,Gene Name, Probe Sequence).
		$outRow .= "$splitPlatformID[1],$geneName,$splitPlatformID[3],,";
				
		#For this reporter we print out a column for all the experiments that we have data for.
		foreach my $EIDvalue (sort{$a <=> $b} keys %{$self->{_ExperimentListHash}})
		{
			#Only try to see the EID's for platform $currentPID.
			if(${$self->{_ExperimentListHash}{$EIDvalue}} == $currentPID)
			{
				my %currentProbeExperimentHash;
				%currentProbeExperimentHash = %{${$self->{_ProbeExperimentHash}}{$value}};
							
				#Split the output string.
				my @outputColumns = split(/\|/,$currentProbeExperimentHash{$EIDvalue});
				
				#Add all the experiment data to the output string.
				foreach(@outputColumns)
				{
					$outRow .= "$_,";
				}
				
				$outRow .= ",";
			}
		}
		
		print "$outRow\n";
	}
}
#######################################################################################

#######################################################################################
#Loop through the list of Reporters we are filtering on and create a list.
#######################################################################################
sub setProbeList
{
	my $self 					= shift;
	$self->{_ReporterList}		= '';
	
	foreach(keys %{$self->{_ProbeHash}})
	{
		$self->{_ReporterList} .= "'$_',";
	}
	
	#Trim trailing comma off.
	$self->{_ReporterList} =~ s/\,$//;	
}
#######################################################################################

#######################################################################################
#Loop through the list of Reporters we are filtering on and create a list.
#######################################################################################
sub getProbeList
{
	my $self 					= shift;
	return $self->{_ReporterList};
}
#######################################################################################

#######################################################################################
# Perl trim function to remove whitespace from the start and end of the string
sub trim($)
{
	my $string = shift;
	
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	
	$string =~ s/\n+$//;
	$string =~ s/^\n+//;	
	
	$string =~ s/\r+$//;
	$string =~ s/^\r+//;	


	return $string;
}
#######################################################################################


1;
