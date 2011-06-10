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
		_cgi		=> shift,
		_SearchType		=> shift,
		_SearchText		=> shift,
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
		_FullExperimentRec		=> '',
		_FullExperimentCount	=> 0,
		_FullExperimentData		=> '',		
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
					coalesce(probe.probe_sequence, g0.probe_sequence) AS 'Probe Sequence',
					group_concat(distinct g0.description order by g0.seqname asc separator '; ') AS 'Gene Description',
					group_concat(distinct gene_note order by g0.seqname asc separator '; ') AS 'Gene Ontology - Comment'					
					from
					({0}) as g0
			left join (annotates natural join probe) on annotates.gid=g0.gid
			left join platform on platform.pid=coalesce(probe.pid, g0.pid)
			group by coalesce(probe.rid, g0.rid)
							",
		_ProbeReporterQuery		=> "
				select DISTINCT 
					coalesce(probe.reporter, g0.reporter) as Probe					
					from
					({0}) as g0
			left join (annotates natural join probe) on annotates.gid=g0.gid
			left join platform on platform.pid=coalesce(probe.pid, g0.pid)
			group by coalesce(probe.rid, g0.rid)
							",							
		_ExperimentListHash 	=> '',
		_ExperimentStudyListHash	=> '',		
		_TempTableID			=> '',
		_ExperimentNameListHash 	=> '',
		_ExperimentDataQuery 	=> "
					select 	experiment.eid, 
						microarray.ratio,
						microarray.foldchange,
						microarray.pvalue,
						IFNULL(microarray.intensity1,0),
						IFNULL(microarray.intensity2,0),
						concat(study.description, ': ', experiment.sample2, '/', experiment.sample1) AS 'Name',
						study.stid,
						study.pid
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

	my $text 		= $self->{_cgi}->param('text') or die "You did not specify what to search for";	# must be always set -- no defaults
	my $type 		= $self->{_cgi}->param('type') or die "You did not specify where to search";	# must be always set -- no defaults
	my $trans 		= (defined($self->{_cgi}->param('trans'))) ? $self->{_cgi}->param('trans') : 'fold';
	my $match 		= (defined($self->{_cgi}->param('match'))) ? $self->{_cgi}->param('match') : 'full';
	my $opts 		= (defined($self->{_cgi}->param('opts'))) ? $self->{_cgi}->param('opts') : 1;
	my $speciesColumn	= 5;

	my @extra_fields;

	switch ($opts) {
	case 0 {}
	case 1 { @extra_fields = ('coalesce(probe.note, g0.note) as \'Probe Specificity - Comment\', coalesce(probe.probe_sequence, g0.probe_sequence) AS \'Probe Sequence\'', 'group_concat(distinct g0.description order by g0.seqname asc separator \'; \') AS \'Gene Description\'', 'group_concat(distinct gene_note order by g0.seqname asc separator \'; \') AS \'Gene Ontology - Comment\'') }
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
		#Add the search items seperated by a bar.
		foreach(@textSplit)
		{
			if($_)
			{
				$qtext .= '^' . trim($_) . '$|';
			}
		}
		
		#Remove the last bar.
		$qtext =~ s/\|$//;
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
#This is the code that generates part of the SQL statement (From a file instead of a list of genes).
#######################################################################################
sub createInsideTableQueryFromFile
{
	#Get the probe object.
	my $self		= shift;

	#This is the type of search.
	my $type 		= $self->{_cgi}->param('type') or die "You did not specify where to search";	# must be always set -- no defaults
	
	#The options will determine what columns we select.
	my $opts 		= (defined($self->{_cgi}->param('opts'))) ? $self->{_cgi}->param('opts') : 1;
	my $speciesColumn	= 5;

	my @extra_fields;

	switch ($opts) {
	case 0 {}
	case 1 { @extra_fields = ('coalesce(probe.note, g0.note) as \'Probe Specificity - Comment\', coalesce(probe.probe_sequence, g0.probe_sequence) AS \'Probe Sequence\'', 'group_concat(distinct g0.description order by g0.seqname asc separator \'; \') AS \'Gene Description\'', 'group_concat(distinct gene_note order by g0.seqname asc separator \'; \') AS \'Gene Ontology - Comment\'') }
	case 2 {}
	}

	my $extra_sql = (@extra_fields) ? ', '.join(', ', @extra_fields) : '';

	my $qtext;

	#We need to get the list from the user into SQL, We need to do some temp table/file trickery for this.
	#Get time to make our unique ID.
	my $time      	= time();
	#Make idea with the time and ID of the running application.
	my $processID 	= $time. '_' . getppid();
	#Regex to strip quotes.
	my $regex_strip_quotes = qr/^("?)(.*)\1$/;
	
	#Store the temp Table id so we can drop the table later.
	$self->{_TempTableID} = $processID;
	
	#We need to create this output directory.
	my $direc_out	 = "/var/www/temp_files/$processID/";
	system("mkdir $direc_out");

	#This is where we put the temp file we will import.
	my $outputFileName 	= $direc_out . "JoinFindProbes";

	#Open file we are writing to server.
	open(OUTPUTTOSERVER,">$outputFileName");

	#This is the file that was uploaded.
	my $uploadedFile = $self->{_cgi}->upload('gene_file');
	
	#Each line is an item to search on.
	while ( <$uploadedFile> )
	{
		#Grab the current line (Or Whole file if file is using Mac line endings).
		my $currentLine = $_;

		#Replace all carriage returns, or carriage returns and line feed with just a line feed.
		$currentLine =~ s/(\r\n|\r)/\n/g;
	
		print OUTPUTTOSERVER "$currentLine";
	}

	close(OUTPUTTOSERVER);

	#--------------------------------------------
	#Now get the temp file into a temp MYSQL table.

	#Command to create temp table.
	my $createTableStatement = "CREATE TABLE $processID (searchField VARCHAR(200))";

	#This is the mysql command to suck in the file.
	my $inputStatement	= "
					LOAD DATA LOCAL INFILE '$outputFileName'
					INTO TABLE $processID
					LINES TERMINATED BY '\n'
					(searchField); 
				";
	#--------------------------------------------

	#---------------------------------------------
	#Run the command to create the temp table.
	$self->{_dbh}->do($createTableStatement) or die $self->{_dbh}->errstr;

	#Run the command to suck in the data.
	$self->{_dbh}->do($inputStatement) or die $self->{_dbh}->errstr;
	#--------------------------------------------

	#When using the file from the user we join on the temp table we create.
	my $g0_sql;
	switch ($type) 
	{
		case 'probe' 
		{
			$g0_sql = "
			select rid, reporter, note, probe_sequence, g1.pid, g2.gid, g2.accnum, g2.seqname, g2.description, g2.gene_note from gene g2 right join 
			(select distinct probe.rid, probe.reporter, probe.note, probe.probe_sequence, probe.pid, accnum from probe left join annotates on annotates.rid=probe.rid left join gene on gene.gid=annotates.gid INNER JOIN $processID tempTable ON tempTable.searchField = reporter) as g1
			on g2.accnum=g1.accnum where rid is not NULL
			
			union

			select rid, reporter, note, probe_sequence, g3.pid, g4.gid, g4.accnum, g4.seqname, g4.description, g4.gene_note from gene g4 right join
			(select distinct probe.rid, probe.reporter, probe.note, probe.probe_sequence, probe.pid, seqname from probe left join annotates on annotates.rid=probe.rid left join gene on gene.gid=annotates.gid INNER JOIN $processID tempTable ON tempTable.searchField = reporter) as g3
			on g4.seqname=g3.seqname where rid is not NULL
			";

		}
		case 'gene' 
		{
			$g0_sql = "
			select NULL as rid, NULL as note, NULL as reporter, NULL as probe_sequence, NULL as pid, g2.gid, g2.accnum, g2.seqname, g2.description, g2.gene_note from gene g2 right join
			(select distinct accnum from gene INNER JOIN $processID tempTable ON tempTable.searchField = seqname where accnum is not NULL) as g1
			on g2.accnum=g1.accnum where g2.gid is not NULL

			union

			select NULL as rid, NULL as note, NULL as reporter, NULL as probe_sequence, NULL as pid, g4.gid, g4.accnum, g4.seqname, g4.description, g4.gene_note from gene g4 right join
			(select distinct seqname from gene INNER JOIN $processID tempTable ON tempTable.searchField = seqname where seqname is not NULL) as g3
			on g4.seqname=g3.seqname where g4.gid is not NULL
			";
		}
		case 'transcript' 
		{
			$g0_sql = "
			select NULL as rid, NULL as note, NULL as reporter, NULL as probe_sequence, NULL as pid, g2.gid, g2.accnum, g2.seqname, g2.description, g2.gene_note from gene g2 right join
			(select distinct accnum from gene INNER JOIN $processID tempTable ON tempTable.searchField = accnum where accnum is not NULL) as g1
			on g2.accnum=g1.accnum where g2.gid is not NULL

			union

			select NULL as rid, NULL as note, NULL as reporter, NULL as probe_sequence, NULL as pid, g4.gid, g4.accnum, g4.seqname, g4.description, g4.gene_note from gene g4 right join
			(select distinct seqname from gene INNER JOIN $processID tempTable ON tempTable.searchField = accnum where seqname is not NULL) as g3
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
#Get a list of the probes (Only the reporter field).
#######################################################################################
sub loadProbeReporterData
{
	my $self				= shift;
	my $qtext				= shift;
	
	my $probeQuery				= $self->{_ProbeReporterQuery};
	
	$probeQuery 				=~ s/\{0\}/\Q$self->{_InsideTableQuery}\E/;
	$probeQuery 				=~ s/\\//g;

	$self->{_ProbeRecords}	= $self->{_dbh}->prepare($probeQuery) 				or die $self->{_dbh}->errstr;
	$self->{_ProbeCount}	= $self->{_ProbeRecords}->execute() 	or die $self->{_dbh}->errstr;	
	$self->{_ProbeColNames} = @{$self->{_ProbeRecords}->{NAME}};
	$self->{_Data}			= $self->{_ProbeRecords}->fetchall_arrayref;
	
	$self->{_ProbeRecords}->finish;
	
	$self->{_ProbeHash} 	= {};
	
	my $DataCount			= @{$self->{_Data}};
	
	#For the situation where we created a temp table for the user input, we need to drop that temp table.
	#This is the command to drop the temp table.
	my $dropStatement = "DROP TABLE " . $self->{_TempTableID} . ";";	
	
	#Run the command to drop the temp table.
	$self->{_dbh}->do($dropStatement) or die $self->{_dbh}->errstr;
	
	if($DataCount < 1)
	{
		print $self->{_cgi}->header(-type=>'text/html', -cookie=>\@SGX::Cookie::cookies);
		print "No records found! Please click back on your browser and search again!";
		exit;
	}
	
	foreach (@{$self->{_Data}}) 
	{
		foreach (@$_)
		{
			$_ = '' if !defined $_;
			$_ =~ s/"//g;
		}

		$self->{_ReporterList} .= "'$_->[0]',";

	}	

	#Trim trailing comma off.
	$self->{_ReporterList} =~ s/\,$//;	
	
	
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
		print $self->{_cgi}->header(-type=>'text/html', -cookie=>\@SGX::Cookie::cookies);
		print "No records found! Please click back on your browser and search again!";
		exit;
	}
	
	foreach (sort {$a->[1] cmp $b->[1]} @{$self->{_Data}}) 
	{
		foreach (@$_)
		{
			$_ = '' if !defined $_;
			$_ =~ s/"//g;
		}
		
		#The GO field uses "|" to delimit, so we need to use something else.
		my $GOField 	= "$_->[6]";
		$GOField 		=~ s/\|/\;/g;		
		
		${$self->{_ProbeHash}}{$_->[0]} = "$_->[1]|$_->[2]|$_->[3]|$_->[4]|$_->[5]|$GOField|";
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
	$self->{_ExperimentStudyListHash}	= {};
	$self->{_ExperimentNameListHash}	= {};
	
	#Grab the format for the output from the form.
	$transform 	= ($self->{_cgi}->param('trans')) 	if defined($self->{_cgi}->param('trans'));
	
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
			${$self->{_ExperimentListHash}{$_->[0]}} = $_->[8];

			#Keep a hash of EID and STID.
			${$self->{_ExperimentStudyListHash}{$_->[0] . '|' . $_->[7]}} = 1;
			
			#Keep a hash of experiment names and EID.			
			${$self->{_ExperimentNameListHash}{$_->[0]}} = $_->[6];
			
		}

		#Add the hash of experiment data to the hash of reporters.
		${$self->{_ProbeExperimentHash}}{$_} = \%tempHash;

	}
	
}
#######################################################################################

#######################################################################################
sub printFindProbeToScreen
{
		my $self		= shift;
		my $caption 		= sprintf("Found %d probe", $self->{_ProbeCount}) .(($self->{_ProbeCount} != 1) ? 's' : '')." annotated with $self->{_SearchType} groups matching '$self->{_SearchText}' ($self->{_SearchType}s grouped by gene symbol or transcript accession number)";
		my $trans 		= (defined($self->{_cgi}->param('trans'))) ? $self->{_cgi}->param('trans') : 'fold';
		my $speciesColumn	= 4;
		
		my $out .= "
		var probelist = {
		caption: \"$caption\",
		records: [
		";

		my @names = $self->{_ProbeColNames};	# cache the field name array

		my $data = $self->{_Data};

		# data are sent as a JSON object plus Javascript code (at the moment)
		foreach (sort {$a->[3] cmp $b->[3]} @$data) 
		{
			foreach (@$_) 
			{
				$_ = '' if !defined $_;
				$_ =~ s/"//g;
			}

			my $currentPID = $_->[1];
			
			$out .= '{0:"'.${$self->{_PlatformInfoHash}{$currentPID}}.'",1:"'.$_->[0].'",2:"'.$_->[2].'",3:"'.$_->[3].'",4:"'.$_->[4].'",5:"'.$_->[5].'",6:"'.$_->[6].'",7:"'.$_->[7].'",8:"'.$_->[8].'",9:"'.$_->[9].'"';
			$out .= "},\n";
		}
		$out =~ s/,\s*$//;	# strip trailing comma

		my $tableOut = '';

		$out .= '
	]}

	function export_table(e) {
		var r = this.records;
		var bl = this.headers.length;
		var w = window.open("");
		var d = w.document.open("text/html");
		d.title = "Tab-Delimited Text";
		d.write("<pre>");
		for (var i=0, al = r.length; i < al; i++) {
			for (var j=0; j < bl; j++) {
				d.write(r[i][j] + "\t");
			}
			d.write("\n");
		}
		d.write("</pre>");
		d.close();
		w.focus();
	}

	YAHOO.util.Event.addListener("probetable_astext", "click", export_table, probelist, true);
	YAHOO.util.Event.addListener(window, "load", function() {
		';
		if (defined($self->{_cgi}->param('graph'))) {
			$out .= 'var graph_content = "";
		var graph_ul = YAHOO.util.Dom.get("graphs");';
		}
		$out .= '
		YAHOO.util.Dom.get("caption").innerHTML = probelist.caption;

		YAHOO.widget.DataTable.Formatter.formatProbe = function(elCell, oRecord, oColumn, oData) {
			var i = oRecord.getCount();
			';
			if (defined($self->{_cgi}->param('graph'))) {
				$out .= 'graph_content += "<li id=\"reporter_" + i + "\"><object type=\"image/svg+xml\" width=\"555\" height=\"880\" data=\"./graph.cgi?reporter=" + oData + "&trans='.$trans.'\"><embed src=\"./graph.cgi?reporter=" + oData + "&trans='.$trans.'\" width=\"555\" height=\"880\" /></object></li>";
			elCell.innerHTML = "<div id=\"container" + i + "\"><a title=\"Show differental expression graph\" href=\"#reporter_" + i + "\">" + oData + "</a></div>";';
			} else {
				$out .= 'elCell.innerHTML = "<div id=\"container" + i + "\"><a title=\"Show differental expression graph\" id=\"show" + i + "\">" + oData + "</a></div>";';
			}
		$out .= '
		}
		YAHOO.widget.DataTable.Formatter.formatTranscript = function(elCell, oRecord, oColumn, oData) {
			var a = oData.split(/ *, */);
			var out = "";
			for (var i=0, al=a.length; i < al; i++) {
				var b = a[i];
				if (b.match(/^ENS[A-Z]{4}\d{11}/i)) {
					out += "<a title=\"Search Ensembl for " + b + "\" target=\"_blank\" href=\"http://www.ensembl.org/Search/Summary?species=all;q=" + b + "\">" + b + "</a>, ";
				} else {
					out += "<a title=\"Search NCBI Nucleotide for " + b + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=Nucleotide&term=" + oRecord.getData("' . $speciesColumn . '") + "[ORGN]+AND+" + b + "[NACC]\">" + b + "</a>, ";
				}
			}
			elCell.innerHTML = out.replace(/,\s*$/, "");
		}
		YAHOO.widget.DataTable.Formatter.formatGene = function(elCell, oRecord, oColumn, oData) {
			if (oData.match(/^ENS[A-Z]{4}\d{11}/i)) {
				elCell.innerHTML = "<a title=\"Search Ensembl for " + oData + "\" target=\"_blank\" href=\"http://www.ensembl.org/Search/Summary?species=all;q=" + oData + "\">" + oData + "</a>";
			} else {
				elCell.innerHTML = "<a title=\"Search NCBI Gene for " + oData + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=gene&term=" + oRecord.getData("' . $speciesColumn . '") + "[ORGN]+AND+" + oData + "\">" + oData + "</a>";
			}
		}
		YAHOO.widget.DataTable.Formatter.formatExperiment = function(elCell, oRecord, oColumn, oData) {
			elCell.innerHTML = "<a title=\"View Experiment Data\" target=\"_blank\" href=\"?a=getTFS&eid=" + oRecord.getData("6") + "&rev=0&fc=" + oRecord.getData("9") + "&pval=" + oRecord.getData("8") + "&opts=2\">" + oData + "</a>";
		}
		YAHOO.widget.DataTable.Formatter.formatSequence = function(elCell, oRecord, oColumn, oData) {
			elCell.innerHTML = "<a href=\"http://genome.ucsc.edu/cgi-bin/hgBlat?userSeq=" + oData + "&type=DNA&org=" + oRecord.getData("' . $speciesColumn . '") + "\" title=\"UCSC BLAT on " + oRecord.getData("' . $speciesColumn . '") + " DNA\" target=\"_blank\">" + oData + "</a>";
		}
		var myColumnDefs = [
			{key:"0", sortable:true, resizeable:true, label:"Platform"},
			{key:"1", sortable:true, resizeable:true, label:"Reporter ID", formatter:"formatProbe"},
			{key:"2", sortable:true, resizeable:true, label:"Accession Number", formatter:"formatTranscript"}, 
			{key:"3", sortable:true, resizeable:true, label:"Gene Name", formatter:"formatGene"},
			{key:"4", sortable:true, resizeable:true, label:"Probe Sequence"},
			{key:"5", sortable:true, resizeable:true, label:"Experiment Number",formatter:"formatExperiment"}];

		var myDataSource = new YAHOO.util.DataSource(probelist.records);
		myDataSource.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
		myDataSource.responseSchema = {
			fields: ["0","1","2","3","4","5","6","7","8","9"]
		};
		var myData_config = {
			paginator: new YAHOO.widget.Paginator({
				rowsPerPage: 50 
			})
		};

		var myDataTable = new YAHOO.widget.DataTable("probetable", myColumnDefs, myDataSource, myData_config);

		// Set up editing flow 
		var highlightEditableCell = function(oArgs) { 
			var elCell = oArgs.target; 
			if(YAHOO.util.Dom.hasClass(elCell, "yui-dt-editable")) { 
			this.highlightCell(elCell); 
			} 
		}; 
		myDataTable.subscribe("cellMouseoverEvent", highlightEditableCell); 
		myDataTable.subscribe("cellMouseoutEvent", myDataTable.onEventUnhighlightCell); 
		myDataTable.subscribe("cellClickEvent", myDataTable.onEventShowCellEditor);

		var nodes = YAHOO.util.Selector.query("#probetable tr td.yui-dt-col-0 a");
		var nl = nodes.length;

		// Ideally, would want to use a "pre-formatter" event to clear graph_content
		// TODO: fix the fact that when cells are updated via cell editor, the graphs are rebuilt unnecessarily.
		myDataTable.doBeforeSortColumn = function(oColumn, sSortDir) {
			graph_content = "";
			return true;
		};
		myDataTable.doBeforePaginatorChange = function(oPaginatorState) {
			graph_content = "";
			return true;
		};
		myDataTable.subscribe("renderEvent", function () {
		';

		if (defined($self->{_cgi}->param('graph'))) 
		{
			$out .= '
			graph_ul.innerHTML = graph_content;
			';

		} else {
			$out .=
		'
			// if the line below is moved to window.load closure,
			// panels will no longer show up after sorting
			var manager = new YAHOO.widget.OverlayManager();
			var myEvent = YAHOO.util.Event;
			var i;
			var imgFile;
			for (i = 0; i < nl; i++) {
				myEvent.addListener("show" + i, "click", function () {
					var index = this.getAttribute("id").substring(4);
					var panel_old = manager.find("panel" + index);

					if (panel_old === null) {
						imgFile = this.innerHTML;	// replaced ".text" with ".innerHTML" because of IE problem
						var panel =  new YAHOO.widget.Panel("panel" + index, { close:true, visible:true, draggable:true, constraintoviewport:false, context:["container" + index, "tl", "br"] } );
						panel.setHeader(imgFile);
						panel.setBody("<object type=\"image/svg+xml\" width=\"555\" height=\"880\" data=\"./graph.cgi?reporter=" + imgFile + "&trans='.$trans.'\"><embed src=\"./graph.cgi?reporter=" + imgFile + "&trans='.$trans.'\" width=\"555\" height=\"880\" /></object>");
						manager.register(panel);
						panel.render("container" + index);
						// panel.show is unnecessary here because visible:true is set
					} else {
						panel_old.show();
					}
				}, nodes[i], true);
			}
		'};
		$out .= '
		});

		return {
			oDS: myDataSource,
			oDT: myDataTable
		};
	});
	';
	$out;

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
	print $self->{_cgi}->header(-type=>'text/csv',-attachment => 'results.csv', -cookie=>\@SGX::Cookie::cookies);

	#Print a line to tell us what report this is.
	print "Find Probes Report," . localtime() . "\n\n";	
	
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
			print "Experiment Number,Study Description, Experiment Heading,Experiment Description\n";
			
			#String representing the list of experiment names.
			my $experimentList = ",,,,,,,";
			
			#Temporarily hold the string we are to output so we can trim the trailing ",".
			my $outLine = "";

			#Loop through the list of experiments and print out the ones for this platform.
			foreach my $value (sort{$a <=> $b} keys %{$self->{_ExperimentListHash}})
			{
				if(${$self->{_ExperimentListHash}{$value}} == $currentPID)
				{
					my $currentLine = "";
				
					$currentLine .= $value . ",";
					$currentLine .= $self->{_FullExperimentData}->{$value}->{description} . ",";
					$currentLine .= $self->{_FullExperimentData}->{$value}->{experimentHeading} . ",";
					$currentLine .= $self->{_FullExperimentData}->{$value}->{ExperimentDescription};
					
					#Current experiment name.
					my $currentExperimentName = ${$self->{_ExperimentNameListHash}{$value}};
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
			print $experimentList;
			print "\n";

			#Print header line for probe rows.
			print "Reporter ID,Accession Number, Gene Name,Probe Sequence,Gene Description,Gene Ontology,";
			
			print "$outLine\n";
					
		}
		
		#This is the line of data we will output. We need to trim the trailing comma.
		my $outRow = '';		
		
		#Print the probe ID.
		$outRow .= "$value,";

		#Trim any commas out of the Gene Name.
		my $geneName 	= $splitPlatformID[2];
		$geneName 		=~ s/\,//g;
		
		my $geneDescription = $splitPlatformID[4];
		$geneDescription	=~ s/\,//g;

		my $geneOntology = $splitPlatformID[5];
		$geneOntology	=~ s/\,//g;
		$geneOntology	=~ s/\;/\|/g;
		
		#Print the probe info. (Accession,Gene Name, Probe Sequence, Gene description, Gene Ontology).
		$outRow .= "$splitPlatformID[1],$geneName,$splitPlatformID[3],$geneDescription,$geneOntology,,";
				
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

#######################################################################################
#Loop through the list of experiments we are displaying and get the information on each. We need eid and stid for each.
#######################################################################################
sub getFullExperimentData
{
	my $self 					= shift;
	my $query_titles			= "";
	
	foreach my $currentRecord (keys %{$self->{_ExperimentStudyListHash}})
	{	
	
		my @IDSplit = split(/\|/,$currentRecord);
		
		my $currentEID = $IDSplit[0];	
		my $currentSTID = $IDSplit[1];
	
		$query_titles .= " SELECT 	experiment.eid, 
									CONCAT(study.description, ': ', experiment.sample1, ' / ', experiment.sample2) AS title, 
									CONCAT(experiment.sample1, ' / ', experiment.sample2) AS experimentHeading,
									study.description,
									experiment.ExperimentDescription 
							FROM experiment 
							NATURAL JOIN StudyExperiment 
							NATURAL JOIN study 
							WHERE eid=$currentEID AND study.stid = $currentSTID UNION ALL ";
	}
	
	# strip trailing 'UNION ALL' plus any trailing white space
	$query_titles =~ s/UNION ALL\s*$//i;
	
	$self->{_FullExperimentRec}		= $self->{_dbh}->prepare($query_titles) or die $self->{_dbh}->errstr;
	$self->{_FullExperimentCount}	= $self->{_FullExperimentRec}->execute() 	or die $self->{_dbh}->errstr;	
	$self->{_FullExperimentData}	= $self->{_FullExperimentRec}->fetchall_hashref('eid');
	
	$self->{_FullExperimentRec}->finish;

}
#######################################################################################

1;
