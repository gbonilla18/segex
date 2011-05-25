=head1 NAME

SGX::AddExperiment

=head1 SYNOPSIS

=head1 DESCRIPTION
Grouping of functions for adding experiments.

=head1 AUTHORS
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::AddExperiment;

use strict;
use warnings;
use SGX::DropDownData;
use Data::Dumper;

sub new {
	# This is the constructor
	my $class = shift;

	my $self = {
		_dbh					=> shift,
		_FormObject				=> shift,
		_QueryingPage			=> shift,
		_InsertQuery			=> 'INSERT INTO experiment (sample1,sample2,ExperimentDescription,AdditionalInformation) VALUES (\'{0}\',\'{1}\',\'{2}\',\'{3}\');',		
		_stid					=> '',
		_pid					=> '',
		_PlatformQuery			=> "SELECT pid,CONCAT(pname ,\' \\\\ \',species) FROM platform;",		
		_platformList			=> {},
		_platformValue			=> (),
		_sample1				=> '',
		_sample2				=> '',
		_ExperimentDescription 	=> '',
		_AdditionalInformation 	=> ''
	};

	bless $self, $class;
	return $self;
}

sub loadFromForm()
{
	my $self = shift;
	
	$self->{_sample1}				= ($self->{_FormObject}->param('Sample1'))			if defined($self->{_FormObject}->param('Sample1'));
	$self->{_sample2}				= ($self->{_FormObject}->param('Sample2'))			if defined($self->{_FormObject}->param('Sample2'));
	$self->{_stid}					= ($self->{_FormObject}->param('stid'))				if defined($self->{_FormObject}->param('stid'));
	$self->{_stid}					= ($self->{_FormObject}->url_param('stid'))			if defined($self->{_FormObject}->url_param('stid'));	
	$self->{_pid}					= ($self->{_FormObject}->param('platform_addNew'))	if defined($self->{_FormObject}->param('platform_addNew'));	
	$self->{_ExperimentDescription}	= ($self->{_FormObject}->param('ExperimentDescription'))	if defined($self->{_FormObject}->param('ExperimentDescription'));
	$self->{_AdditionalInformation}	= ($self->{_FormObject}->param('AdditionalInformation'))	if defined($self->{_FormObject}->param('AdditionalInformation'));
}

#Loads information into the object that is used to create the study dropdown.
sub loadPlatformData
{
	my $self		= shift;

	my $platformDropDown	= new SGX::DropDownData($self->{_dbh},$self->{_PlatformQuery},0);

	$platformDropDown->loadDropDownValues();
	
	$self->{_platformList} 	= $platformDropDown->{_dropDownList};
	$self->{_platformValue} = $platformDropDown->{_dropDownValue};
}

sub drawAddExperimentMenu
{
	my $self = shift;

	print	'<br /><h2 name = "Add_Caption" id = "Add_Caption">Add New Experiment</h2>' . "\n";

	print $self->{_FormObject}->start_form(
		-method=>'POST',
		-action=>$self->{_FormObject}->url(-absolute=>1).'?a=' . $self->{_QueryingPage} . '&ManageAction=addNew&stid=' . $self->{_stid},
		-onsubmit=>'return validate_fields(this, [\'Sample1\',\'Sample2\',\'uploaded_data_file\']);'
	) .
	$self->{_FormObject}->p('In order to upload experiment data the file must be in a tab separated format and the columns be as follows.')
	.
	$self->{_FormObject}->p('<b>Reporter Name, Ratio, Fold Change, P-value, Intensity 1, Intensity 2</b>')
	.
	$self->{_FormObject}->p('Make sure the first row is the column headings and the second row starts the data.')
	.
	$self->{_FormObject}->dl(
		$self->{_FormObject}->dt('Platform:'),
		$self->{_FormObject}->dd($self->{_FormObject}->popup_menu(-name=>'platform_addNew',-id=>'platform_addNew',-values=>\@{$self->{_platformValue}},-labels=>\%{$self->{_platformList}})),	
		$self->{_FormObject}->dt('Sample 1:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'Sample1',-id=>'Sample1',-maxlength=>120)),
		$self->{_FormObject}->dt('Sample 2:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'Sample2',-id=>'Sample2',-maxlength=>120)),
		$self->{_FormObject}->dt('Experiment Description:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'ExperimentDescription',-id=>'ExperimentDescription',-maxlength=>1000)),
		$self->{_FormObject}->dt('Additional Information:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'AdditionalInformation',-id=>'AdditionalInformation',-maxlength=>1000)),
		$self->{_FormObject}->dt("Data File to upload:"),
		$self->{_FormObject}->dd($self->{_FormObject}->filefield(-name=>'uploaded_data_file',-id=>'uploaded_data_file')),
		$self->{_FormObject}->dt('&nbsp;'),
		$self->{_FormObject}->dd($self->{_FormObject}->submit(-name=>'AddExperiment',-id=>'AddExperiment',-value=>'Add Experiment'),$self->{_FormObject}->span({-class=>'separator'},' / '))
	) .
	$self->{_FormObject}->end_form;

}

sub addNewExperiment
{	
	#Get reference to our object.
	my $self 	= shift;

	#The is the file handle of the uploaded file.
	my $uploadedFile 	= $self->{_FormObject}->upload('uploaded_data_file');
	
	if(!$uploadedFile)
	{
		print "File failed to upload. Please press the back button on your browser and try again.<br />\n";
		exit;
	}
	else
	{

		my $insertStatement	= $self->{_InsertQuery};

		$insertStatement 	=~ s/\{0\}/\Q$self->{_sample1}\E/;
		$insertStatement 	=~ s/\{1\}/\Q$self->{_sample2}\E/;
		$insertStatement 	=~ s/\{2\}/\Q$self->{_ExperimentDescription}\E/;
		$insertStatement 	=~ s/\{3\}/\Q$self->{_AdditionalInformation}\E/;

		$self->{_dbh}->do($insertStatement) or die $self->{_dbh}->errstr;

		$self->{_eid}		= $self->{_dbh}->{'mysql_insertid'};

		#Get time to make our unique ID.
		my $time      	= time();

		#Make idea with the time and ID of the running application.
		my $processID 	= $time. '_' . getppid();

		#Regex to strip quotes.
		my $regex_strip_quotes = qr/^("?)(.*)\1$/;

		#We need to create this output directory.
		my $direc_out	 = "/var/www/temp_files/$processID/";
		system("mkdir $direc_out");
		
		#This is where we put the temp file we will import.
		my $outputFileName 	= $direc_out . "StudyData";
		
		#This is the temp file we use to convert.
		my $outputFileName_temp = $direc_out . "StudyData_temp";

		#This is the temp file we use to convert.
		my $outputFileName_final = $direc_out . "StudyData_final";
		
		#Open a file that we save the uploaded content to.
		open(OUTPUTTEMP,">$outputFileName_temp");
		
		#Write the contents of the upload to the new file.
		while ( <$uploadedFile> )
		{
			print OUTPUTTEMP;
		}
		
		close(OUTPUTTEMP);
		
		#Run a conversion on the file we just uploaded.
		system("perl -pe 's/\r\n|\n|\r/\n/g' $outputFileName_temp > $outputFileName_final");
		
		#Open the converted file that was uploaded.
		open (FINALUPLOAD, "$outputFileName_final");
		
		#Open file we are writing to server.
		open(OUTPUTTOSERVER,">$outputFileName");
		
		#Check each line in the uploaded file and write it to our temp file.
		while ( <FINALUPLOAD> )
		{
			my @row = split(/ *\t */);

			#The first line should be "Reporter Name" in the first column. We don't process this line.
			if(!($row[0] eq '"Reporter Name"'))
			{
				if($row[0] =~ $regex_strip_quotes){$row[0] = $2;$row[0] =~ s/,//g;}
				if($row[1] =~ $regex_strip_quotes){$row[1] = $2;$row[1] =~ s/,//g;}
				if($row[2] =~ $regex_strip_quotes){$row[2] = $2;$row[2] =~ s/,//g;}
				if($row[3] =~ $regex_strip_quotes){$row[3] = $2;$row[3] =~ s/,//g;}
				if($row[4] =~ $regex_strip_quotes){$row[4] = $2;$row[4] =~ s/,//g;}
				if($row[5] =~ $regex_strip_quotes){$row[5] = $2 . "\n";$row[5] =~ s/,//g;$row[5] =~ s/\"//g;}

				#Make sure we have a value for each column.
				if(!exists($row[0]) || !exists($row[1]) || !exists($row[2]) || !exists($row[3]) || !exists($row[4]) || !exists($row[5]))
				{
					print "File not found to be in correct format. Please press the back button on your browser and try again.<br />\n";
					exit;
				}

				print OUTPUTTOSERVER $self->{_stid} . '|' . $row[0] . '|' . $row[1] . '|' . $row[2] . '|' . $row[3] . '|' . $row[4] . '|' . $row[5];
	
			}
		}

		close(OUTPUTTOSERVER);
		close(FINALUPLOAD);
		#--------------------------------------------
		#Now get the temp file into a temp MYSQL table.

		#Command to create temp table.
		my $createTableStatement = "CREATE TABLE $processID (stid INT(1),Reporter VARCHAR(150),ratio DOUBLE,foldchange DOUBLE,pvalue DOUBLE,intensity1 DOUBLE,intensity2 DOUBLE)";

		#This is the mysql command to suck in the file.
		my $inputStatement	= "
						LOAD DATA LOCAL INFILE '$outputFileName'
						INTO TABLE $processID
						FIELDS TERMINATED BY '|'
						LINES TERMINATED BY '\n'
						(stid,Reporter, ratio, foldchange,pvalue,intensity1,intensity2); 
					";

		#This is the mysql command to get results from temp file into the microarray table.
		$insertStatement 	= "INSERT INTO microarray (rid,eid,ratio,foldchange,pvalue,intensity2,intensity1)
		SELECT	probe.rid,
			" . $self->{_eid} . " as eid,
			temptable.ratio,
			temptable.foldchange,
			temptable.pvalue,
			temptable.intensity2,
			temptable.intensity1
		FROM	 probe
		INNER JOIN $processID AS temptable ON temptable.reporter = probe.reporter
		WHERE	probe.pid = " . $self->{_pid} . ";";
		
		#This is the command to drop the temp table.
		my $dropStatement = "DROP TABLE $processID;";
		#--------------------------------------------

		#---------------------------------------------
		#Run the command to create the temp table.
		$self->{_dbh}->do($createTableStatement) or die $self->{_dbh}->errstr;

		#Run the command to suck in the data.
		$self->{_dbh}->do($inputStatement) or die $self->{_dbh}->errstr;

		my $rowsInserted = $self->{_dbh}->do($insertStatement);
		
		#Run the command to insert the data.
		if(!$rowsInserted)
		{
			die $self->{_dbh}->errstr;
		}

		#Run the command to drop the temp table.
		$self->{_dbh}->do($dropStatement) or die $self->{_dbh}->errstr;
		#--------------------------------------------
		
		#Remove the temp directory.
		system("rm -rf $direc_out");
				
		if($rowsInserted < 2)
		{
			print "Experiment data could not be added. Please verify you are using the correct annotations for the platform. <br />\n";
			exit;
		}
		else
		{
			print "Experiment data added. $rowsInserted probes found. <br />\n";
		}
	}
}

1;
