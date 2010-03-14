=head1 NAME

SGX::ManageExperiments

=head1 SYNOPSIS

=head1 DESCRIPTION
Grouping of functions for managing experiments.

=head1 AUTHORS
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::ManageExperiments;

use SGX::DropDownData;
use strict;
use warnings;

sub new {
	# This is the constructor
	my $class = shift;

	my @deleteStatementList;

	push @deleteStatementList,'DELETE FROM microarray WHERE eid = {0};';
	push @deleteStatementList,'DELETE FROM experiment WHERE eid = {0};';

	my $self = {
		_dbh		=> shift,
		_FormObject	=> shift,
		_LoadQuery	=> "	SELECT 	experiment.eid,
						study.pid,
						experiment.sample1,
						experiment.sample2,
						COUNT(1),
						ExperimentDescription,
						AdditionalInformation
					FROM	experiment 
					INNER JOIN study ON study.stid = experiment.stid
					LEFT JOIN microarray ON microarray.eid = experiment.eid
					WHERE experiment.stid = {0}
					GROUP BY experiment.eid,
						study.pid,
						experiment.sample1,
						experiment.sample2,
						ExperimentDescription,
						AdditionalInformation;
				   ",
		_LoadSingleQuery=> "SELECT	eid,
						sample1,
						sample2,
						ExperimentDescription,
						AdditionalInformation,
						COUNT(1)
					FROM	experiment 
					INNER JOIN study ON study.stid = experiment.stid
					WHERE	experiment.eid = {0}
					GROUP BY experiment.eid,
						experiment.sample1,
						experiment.sample2,
						ExperimentDescription,
						AdditionalInformation;
				",
		_UpdateQuery	=> 'UPDATE experiment SET ExperimentDescription = \'{0}\', AdditionalInformation = \'{1}\', sample1 = \'{2}\', sample2 = \'{3}\' WHERE eid = {4};',
		_InsertQuery	=> 'INSERT INTO experiment (sample1,sample2,stid,ExperimentDescription,AdditionalInformation) VALUES (\'{0}\',\'{1}\',\'{2}\',\'{3}\',\'{4}\');',
		_DeleteQuery	=> \@deleteStatementList,
		_StudyQuery	=> 'SELECT stid,description FROM study;',
		_RecordCount	=> 0,
		_Records	=> '',
		_FieldNames	=> '',
		_Data		=> '',
		_stid		=> '',
		_description	=> '',
		_pubmed		=> '',
		_pid		=> '',
		_eid		=> '',
		_studyList	=> {},
		_studyValue	=> (),
		_sample1	=> '',
		_sample2	=> '',
		_rowCount	=> 0,
		_ExperimentDescription => '',
		_AdditionalInformation => ''
	};

	bless $self, $class;
	return $self;
}

#Loads all expriments from a specific study.
sub loadAllExperimentsFromStudy
{
	my $self 	= shift;
	my $loadQuery 	= $self->{_LoadQuery};

	$loadQuery 	=~ s/\{0\}/\Q$self->{_stid}\E/;

	$self->{_Records} 	= $self->{_dbh}->prepare($loadQuery) or die $self->{_dbh}->errstr;
	$self->{_RecordCount}	= $self->{_Records}->execute or die $self->{_dbh}->errstr;
	$self->{_FieldNames} 	= $self->{_Records}->{NAME};
	$self->{_Data} 		= $self->{_Records}->fetchall_arrayref;
	$self->{_Records}->finish;
}

#Loads a single platform from the database based on the URL parameter.
sub loadSingleExperiment
{
	#Grab object and id from URL.
	my $self 	= shift;
	$self->{_eid} 	= $self->{_FormObject}->url_param('id');
	$self->{_stid}	= ($self->{_FormObject}->url_param('stid')) if defined($self->{_FormObject}->url_param('stid'));
	
	#Use a regex to replace the ID in the query to load a single platform.
	my $singleItemQuery 	= $self->{_LoadSingleQuery};
	$singleItemQuery 	=~ s/\{0\}/\Q$self->{_eid}\E/;

	#Run the SPROC and get the data into the object.
	$self->{_Records} 	= $self->{_dbh}->prepare($singleItemQuery) or die $self->{_dbh}->errstr;
	$self->{_RecordCount}	= $self->{_Records}->execute or die $self->{_dbh}->errstr;
	$self->{_Data} 		= $self->{_Records}->fetchall_arrayref;

	foreach (@{$self->{_Data}})
	{
		$self->{_sample1}		= $_->[1];
		$self->{_sample2}		= $_->[2];
		$self->{_ExperimentDescription}	= $_->[3];
		$self->{_AdditionalInformation}	= $_->[4];
		$self->{_rowCount}		= $_->[5];
	}

	$self->{_Records}->finish;
}

#Loads information into the object that is used to create the study dropdown.
sub loadStudyData
{
	my $self		= shift;

	my $studyDropDown	= new SGX::DropDownData($self->{_dbh},$self->{_StudyQuery});

	$studyDropDown->loadDropDownValues();

	$self->{_studyList} 	= $studyDropDown->{_dropDownList};
	$self->{_studyValue} 	= $studyDropDown->{_dropDownValue};
}

#Load the data from the submitted form.
sub loadFromForm
{
	my $self = shift;

	$self->{_eid}			= ($self->{_FormObject}->param('eid')) 				if defined($self->{_FormObject}->param('eid'));
	$self->{_stid}			= ($self->{_FormObject}->param('stid'))				if defined($self->{_FormObject}->param('stid'));
	$self->{_stid}			= ($self->{_FormObject}->url_param('stid'))			if defined($self->{_FormObject}->url_param('stid'));	
	$self->{_eid}			= ($self->{_FormObject}->url_param('id')) 			if defined($self->{_FormObject}->url_param('id'));
	$self->{_sample1}		= ($self->{_FormObject}->param('Sample1'))			if defined($self->{_FormObject}->param('Sample1'));
	$self->{_sample2}		= ($self->{_FormObject}->param('Sample2'))			if defined($self->{_FormObject}->param('Sample2'));
	$self->{_ExperimentDescription}	= ($self->{_FormObject}->param('ExperimentDescription'))	if defined($self->{_FormObject}->param('ExperimentDescription'));
	$self->{_AdditionalInformation}	= ($self->{_FormObject}->param('AdditionalInformation'))	if defined($self->{_FormObject}->param('AdditionalInformation'));
}

#######################################################################################
#PRINTING HTML AND JAVASCRIPT STUFF
#######################################################################################
#Draw the javascript and HTML for the experiment table.
sub showExperiments
{
	my $self = shift;
	my $error_string = "";

	print	'<font size="5">Manage Experiments</font><br /><br />' . "\n";

	#Load the study dropdown to choose which experiments to load into table.
	print $self->{_FormObject}->start_form(
		-method=>'POST',
		-action=>$self->{_FormObject}->url(-absolute=>1).'?a=form_manageExperiments&ManageAction=load',
		-onsubmit=>'return validate_fields(this, [\'study\']);'
	) .
	$self->{_FormObject}->dl(
		$self->{_FormObject}->dt('Study:'),
		$self->{_FormObject}->dd($self->{_FormObject}->popup_menu(-name=>'stid',-id=>'stid',-values=>\@{$self->{_studyValue}},-labels=>\%{$self->{_studyList}},-default=>$self->{_stid})),
		$self->{_FormObject}->dt('&nbsp;'),
		$self->{_FormObject}->dd($self->{_FormObject}->submit(-name=>'SelectStudy',-id=>'SelectStudy',-value=>'Load Study'),$self->{_FormObject}->span({-class=>'separator'})
		)
	) .
	$self->{_FormObject}->end_form;

	#If we have selected and loaded an expriment, load the table.
	if(!$self->{_Data} == '')
	{
		my $JSStudyList = "var JSStudyList = 
		{
			caption: \"Showing all Experiments\",
			records: [". printJSRecords($self) ."],
			headers: [". printJSHeaders($self) . "]
		};" . "\n";

		print	'<h2 name = "caption" id="caption"></h2>' . "\n";
		print	'<div><a id="StudyTable_astext" onClick = "export_table(JSStudyList)">View as plain text</a></div>' . "\n";
		print	'<div id="StudyTable"></div>' . "\n";
		print	"<script type=\"text/javascript\">\n";
		print $JSStudyList;

		printTableInformation($self->{_FieldNames},$self->{_FormObject},$self->{_stid});
		printExportTable();	
		printDrawResultsTableJS();

		print 	"</script>\n";
		print	'<br /><h2 name = "Add_Caption" id = "Add_Caption">Add New Experiment</h2>' . "\n";

		print $self->{_FormObject}->start_form(
			-method=>'POST',
			-action=>$self->{_FormObject}->url(-absolute=>1).'?a=manageExperiments&ManageAction=add&stid=' . $self->{_stid},
			-onsubmit=>'return validate_fields(this, [\'Sample1\',\'Sample2\']);'
		) .
		$self->{_FormObject}->dl(
			$self->{_FormObject}->dt('Sample 1:'),
			$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'Sample1',-id=>'Sample1',-maxlength=>120)),
			$self->{_FormObject}->dt('Sample 2:'),
			$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'Sample2',-id=>'Sample2',-maxlength=>120)),
			$self->{_FormObject}->dt('Experiment Description:'),
			$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'ExperimentDescription',-id=>'ExperimentDescription',-maxlength=>1000)),
			$self->{_FormObject}->dt('Additional Information:'),
			$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'AdditionalInformation',-id=>'AdditionalInformation',-maxlength=>1000)),
			$self->{_FormObject}->dt('&nbsp;'),
			$self->{_FormObject}->dd($self->{_FormObject}->submit(-name=>'AddExperiment',-id=>'AddExperiment',-value=>'Add Experiment'),$self->{_FormObject}->span({-class=>'separator'},' / ')
			)
		) .
		$self->{_FormObject}->end_form;

		print	'<br /><h2 name = "Add_Caption" id = "Add_Caption">Add New Experiment</h2>' . "\n";

		print $self->{_FormObject}->start_form(
			-method=>'POST',
			-action=>$self->{_FormObject}->url(-absolute=>1).'?a=manageExperiments&ManageAction=addExisting&stid=' . $self->{_stid},
			-onsubmit=>'return validate_fields(this, [\'Sample1\',\'Sample2\']);'
		) .
		$self->{_FormObject}->dl(
			$self->{_FormObject}->dt('Sample 1:'),
			$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'Sample1',-id=>'Sample1',-maxlength=>120)),
			$self->{_FormObject}->dt('Sample 2:'),
			$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'Sample2',-id=>'Sample2',-maxlength=>120)),
			$self->{_FormObject}->dt('Experiment Description:'),
			$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'ExperimentDescription',-id=>'ExperimentDescription',-maxlength=>1000)),
			$self->{_FormObject}->dt('Additional Information:'),
			$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'AdditionalInformation',-id=>'AdditionalInformation',-maxlength=>1000)),
			$self->{_FormObject}->dt('&nbsp;'),
			$self->{_FormObject}->dd($self->{_FormObject}->submit(-name=>'AddExperiment',-id=>'AddExperiment',-value=>'Add Experiment'),$self->{_FormObject}->span({-class=>'separator'},' / ')
			)
		) .
		$self->{_FormObject}->end_form;
		
	}


}

#This prints the results table to a printable text screen.
sub printExportTable
{

print '
function export_table(e) {
	var r = e.records;
	var bl = e.headers.length;
	var w = window.open("");
	var d = w.document.open("text/html");
	d.title = "Tab-Delimited Text";
	d.write("<pre>");
	for (var i=0, al = r.length; i < al; i++) 
	{
		for (var j=0; j < bl; j++) 
		{
			d.write(r[i][j] + "\t");
		}
		d.write("\n");
	}
	d.write("</pre>");
	d.close();
	w.focus();
}

';

}

sub printDrawResultsTableJS
{
	print	'
	var myDataSource 		= new YAHOO.util.DataSource(JSStudyList.records);
	myDataSource.responseType 	= YAHOO.util.DataSource.TYPE_JSARRAY;
	myDataSource.responseSchema 	= {fields: ["0","1","2","3","4","5","6"]};
	var myData_config 		= {paginator: new YAHOO.widget.Paginator({rowsPerPage: 50})};
	var myDataTable 		= new YAHOO.widget.DataTable("StudyTable", myColumnDefs, myDataSource, myData_config);' . "\n";
}

sub printJSRecords
{
	my $self = shift;
	my $tempRecordList = '';

	#Loop through data and load into JavaScript array.
	foreach (sort {$a->[3] cmp $b->[3]} @{$self->{_Data}}) 
	{
		foreach (@$_) 
		{
			$_ = '' if !defined $_;
			$_ =~ s/"//g;	# strip all double quotes (JSON data are bracketed with double quotes)
		}
		#stid,description,pubmed,platform.pid,platform.pname,platform.species
		$tempRecordList .= '{0:"'.$_->[2].'",1:"'.$_->[3].'",2:"'.$_->[4].'",3:"'.$_->[0].'",4:"' . $_->[0] . '",5:"' . $_->[5] . '",6:"' . $_->[6] . '"},';
	}
	$tempRecordList =~ s/,\s*$//;	# strip trailing comma

	return $tempRecordList;
}

sub printJSHeaders
{
	my $self = shift;
	my $tempHeaderList = '';

	#Loop through data and load into JavaScript array.
	foreach (@{$self->{_FieldNames}})
	{
		$tempHeaderList .= '"' . $_ . '",';
	}
	$tempHeaderList =~ s/,\s*$//;	# strip trailing comma

	return $tempHeaderList;


}

sub printTableInformation
{
	my $arrayRef 	= shift;
	my @names 	= @$arrayRef;
	my $CGIRef 	= shift;
	my $studyID	= shift;
	my $deleteURL 	= $CGIRef->url(absolute=>1).'?a=manageExperiments&ManageAction=delete&id=';
	my $editURL	= $CGIRef->url(absolute=>1).'?a=manageExperiments&ManageAction=edit&stid=' . $studyID . '&id=';

	print	'
		YAHOO.widget.DataTable.Formatter.formatExperimentDeleteLink = function(elCell, oRecord, oColumn, oData) 
		{
			elCell.innerHTML = "<a title=\"Delete Experiment\" onClick = \"return deleteConfirmation();\" target=\"_self\" href=\"' . $deleteURL . '" + oData + "\">Delete</a>";
		}
		YAHOO.widget.DataTable.Formatter.formatExperimentEditLink = function(elCell, oRecord, oColumn, oData) 
		{
			elCell.innerHTML = "<a title=\"Edit Experiment\" target=\"_self\" href=\"' . $editURL . '" + oData + "\">Edit</a>";
		}
		YAHOO.widget.DataTable.Formatter.formatExperimentDataPresent = function(elCell, oRecord, oColumn, oData) 
		{
			if(oData<2)
			{
				elCell.innerHTML = "No";
			}
			else
			{
				elCell.innerHTML = "Yes";
			}
		}

		YAHOO.util.Dom.get("caption").innerHTML = JSStudyList.caption;
		var myColumnDefs = [
		{key:"0", sortable:true, resizeable:true, label:"Sample 1"},
		{key:"1", sortable:true, resizeable:true, label:"Sample 2"},
		{key:"2", sortable:true, resizeable:true, label:"Experiment Data Present",formatter:"formatExperimentDataPresent"},
		{key:"5", sortable:false, resizeable:true, label:"Experiment Description"},
		{key:"6", sortable:false, resizeable:true, label:"Additional Information"},
		{key:"3", sortable:false, resizeable:true, label:"Delete Experiment",formatter:"formatExperimentDeleteLink"},
		{key:"4", sortable:false, resizeable:true, label:"Edit Experiment",formatter:"formatExperimentEditLink"}
		];' . "\n";
}
#######################################################################################


#######################################################################################
#ADD/DELETE/EDIT METHODS
#######################################################################################
sub insertNewExperiment
{
	my $self = shift;
	my $insertStatement 	= $self->{_InsertQuery};
	$insertStatement 	=~ s/\{0\}/\Q$self->{_sample1}\E/;
	$insertStatement 	=~ s/\{1\}/\Q$self->{_sample2}\E/;
	$insertStatement 	=~ s/\{2\}/\Q$self->{_stid}\E/;
	$insertStatement 	=~ s/\{3\}/\Q$self->{_ExperimentDescription}\E/;
	$insertStatement 	=~ s/\{4\}/\Q$self->{_AdditionalInformation}\E/;

	$self->{_dbh}->do($insertStatement) or die $self->{_dbh}->errstr;
}

sub deleteExperiment
{
	my $self = shift;

	foreach (@{$self->{_DeleteQuery}})
	{
		my $deleteStatement 	= $_;
		$deleteStatement 	=~ s/\{0\}/\Q$self->{_eid}\E/;
		
		$self->{_dbh}->do($deleteStatement) or die $self->{_dbh}->errstr;
	}
}

sub editExperiment
{
	my $self = shift;

	#Edit existing platform.
	print $self->{_FormObject}->start_form(
		-method=>'POST',
		-action=>$self->{_FormObject}->url(-absolute=>1).'?a=manageExperiments&ManageAction=editSubmit&id=' . $self->{_eid} . '&stid=' . $self->{_stid},
		-onsubmit=>'return validate_fields(this, [\'Sample1\']);',
		-enctype=>'multipart/form-data'
	) 	.
		'<font size="5">Editing Experiment</font><br /><br />' . "\n"
		.
		$self->{_FormObject}->h2('Uploading Experiment Data')
		.
		$self->{_FormObject}->p('In order to upload an experiment the file must be in .CSV (Comma separated value) format and the columns be as follows.')
		.
		$self->{_FormObject}->p('<b>Reporter Name, Ratio, Fold Change, P-value, Intensity 1, Intensity 2</b>')
		.
		$self->{_FormObject}->p('Make sure the first row is the column headings and the second row starts the data.')
		.
	$self->{_FormObject}->dl
		(
			$self->{_FormObject}->dt('Sample 1:'),
			$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'Sample1',-readonly => 'readonly',-id=>'Sample1',-value=>$self->{_sample1})),
			$self->{_FormObject}->dt('Sample 2:'),
			$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'Sample2',-readonly => 'readonly',-id=>'Sample2',-value=>$self->{_sample2})),
			$self->{_FormObject}->dt("Data File to upload:"),
			$self->{_FormObject}->dd($self->{_FormObject}->filefield(-name=>'uploaded_data_file')),
			$self->{_FormObject}->dt('Experiment Description:'),
			$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'ExperimentDescription',-id=>'ExperimentDescription',-maxlength=>1000,-value=>$self->{_ExperimentDescription})),
			$self->{_FormObject}->dt('Additional Information:'),
			$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'AdditionalInformation',-id=>'AdditionalInformation',-maxlength=>1000,-value=>$self->{_AdditionalInformation})),
			$self->{_FormObject}->dt('&nbsp;'),			
			$self->{_FormObject}->dd($self->{_FormObject}->submit(-name=>'editStudy',-id=>'editStudy',-value=>'Save Edits'),$self->{_FormObject}->span({-class=>'separator'},' / ')
		)
	) .
	$self->{_FormObject}->end_form;	
}

sub editSubmitExperiment
{	
	#Get reference to our object.
	my $self 	= shift;

	my $updateStatement	= $self->{_UpdateQuery};

	$updateStatement 	=~ s/\{0\}/\Q$self->{_ExperimentDescription}\E/;
	$updateStatement 	=~ s/\{1\}/\Q$self->{_AdditionalInformation}\E/;
	$updateStatement 	=~ s/\{2\}/\Q$self->{_sample1}\E/;
	$updateStatement 	=~ s/\{3\}/\Q$self->{_sample2}\E/;
	$updateStatement 	=~ s/\{4\}/\Q$self->{_eid}\E/;

	$self->{_dbh}->do($updateStatement) or die $self->{_dbh}->errstr;

	#If we don't have data, save the excel file.
	if($self->{_rowCount} < 2)
	{

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

		#The is the file handle of the uploaded file.
		my $uploadedFile 	= $self->{_FormObject}->upload('uploaded_data_file');
	
		if(!$uploadedFile)
		{
			print "File failed to upload.<br />\n";
		}
		else
		{
			#Open file we are writing to server.
			open(OUTPUTTOSERVER,">$outputFileName");

			#Check each line in the uploaded file and write it to our temp file.
			while ( <$uploadedFile> )
			{
				my @row = split(/\s*,\s*/);

				#The first line should be "Reporter Name" in the first column. We don't process this line.
				if(!($row[0] eq '"Reporter Name"'))
				{
					if($row[0] =~ $regex_strip_quotes)
					{
						$row[0] = $2;
					}
				
					#Make sure we have a value for each column.
					if(!exists($row[0]) || !exists($row[1]) || !exists($row[2]) || !exists($row[3]) || !exists($row[4]) || !exists($row[5]))
					{
						print "File not found to be in correct format.<br />\n";
						#exit;
					}

					print OUTPUTTOSERVER $self->{_stid} . ',' . $row[0] . ',' . $row[1] . ',' . $row[2] . ',' . $row[3] . ',' . $row[4] . ',' . $row[5];
		
				}
			}

			close(OUTPUTTOSERVER);

			#--------------------------------------------
			#Now get the temp file into a temp MYSQL table.

			#Command to create temp table.
			my $createTableStatement = "CREATE TABLE $processID (stid INT(1),Reporter VARCHAR(150),ratio DOUBLE,foldchange DOUBLE,pvalue DOUBLE,intensity1 DOUBLE,intensity2 DOUBLE)";

			#This is the mysql command to suck in the file.
			my $inputStatement	= "
							LOAD DATA LOCAL INFILE '$outputFileName'
							INTO TABLE $processID
							FIELDS TERMINATED BY ','
							LINES TERMINATED BY '\n'
							(stid,Reporter, ratio, foldchange,pvalue,intensity1,intensity2); 
						";
	
			#This is the mysql command to get results from temp file into the microarray table.
			my $insertStatement 	= "INSERT INTO microarray (rid,eid,ratio,foldchange,pvalue,intensity2,intensity1)
			SELECT	probe.rid,
				" . $self->{_eid} . " as eid,
				temptable.ratio,
				temptable.foldchange,
				temptable.pvalue,
				temptable.intensity2,
				temptable.intensity1
			FROM	 probe
			INNER JOIN $processID AS temptable ON temptable.reporter = probe.reporter
			INNER JOIN study 	ON study.stid 	= temptable.stid
			INNER JOIN platform 	ON platform.pid = study.pid
			WHERE	platform.pid = probe.pid;";

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

			if($rowsInserted < 1)
			{
				print "Experiment data could not be added. Please verify you are using the correct annotations for the platform. <br />\n";
			}
			else
			{
				print "Experiment data added. $rowsInserted probes found. <br />\n";
			}
		}
	}

}
#######################################################################################

1;
