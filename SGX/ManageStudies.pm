=head1 NAME

SGX::ManageStudies

=head1 SYNOPSIS

=head1 DESCRIPTION
Grouping of functions for managing studies.

=head1 AUTHORS
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::ManageStudies;

use strict;
use warnings;

use SGX::AddExperiment;

sub new {
	# This is the constructor
	my $class = shift;

	my @deleteStatementList;
	my @addExistingExperimentList;

	push @deleteStatementList,'DELETE FROM microarray WHERE eid in (SELECT eid FROM experiment WHERE stid = {0});';
	push @deleteStatementList,'DELETE FROM experiment WHERE stid = {0};';
	push @deleteStatementList,'DELETE FROM study WHERE stid = {0};';

	my $self = {
		_dbh		=> shift,
		_FormObject	=> shift,
		_LoadQuery	=> 'SELECT stid,description,pubmed,platform.pid,platform.pname,platform.species FROM study INNER JOIN platform ON platform.pid = study.pid AND platform.isAnnotated;',
		_LoadSingleQuery=> 'SELECT stid,description,pubmed,platform.pid,platform.pname,platform.species FROM study INNER JOIN platform ON platform.pid = study.pid WHERE study.stid = {0};',
		_UpdateQuery	=> 'UPDATE study SET description = \'{0}\', pubmed = \'{1}\', pid = \'{2}\' WHERE stid = {3};',
		_InsertQuery	=> 'INSERT INTO study (description,pubmed,pid) VALUES (\'{0}\',\'{1}\',\'{2}\');',
		_DeleteQuery	=> \@deleteStatementList,
		_PlatformQuery	=> 'SELECT pid,CONCAT(pname ,\' \\\\ \',species) FROM platform WHERE isAnnotated;',
		_ExperimentsQuery=>"	SELECT 	experiment.eid,
						study.pid,
						experiment.sample1,
						experiment.sample2,
						COUNT(1),
						ExperimentDescription,
						AdditionalInformation,
						study.description,
						platform.pname
					FROM	experiment 
					NATURAL JOIN StudyExperiment
					NATURAL JOIN study
					INNER JOIN platform ON platform.pid = study.pid
					LEFT JOIN microarray ON microarray.eid = experiment.eid
					WHERE study.stid = {0}
					GROUP BY experiment.eid,
						study.pid,
						experiment.sample1,
						experiment.sample2,
						ExperimentDescription,
						AdditionalInformation
					ORDER BY experiment.eid ASC;
				   ",
		_ExpRecordCount	=> 0,
		_ExpRecords	=> '',
		_ExpFieldNames	=> '',
		_ExpData	=> '',
		_ExistingStudyQuery 		=> 'SELECT stid,description FROM study WHERE pid IN (SELECT pid FROM study WHERE stid = {0}) AND stid <> {0};',
		_ExistingExperimentQuery 	=> "SELECT	stid,eid,sample2,sample1 FROM experiment NATURAL JOIN StudyExperiment NATURAL JOIN study WHERE pid IN (SELECT pid FROM study WHERE stid = {0}) AND stid <> {0} ORDER BY experiment.eid ASC;",	
		_AddExistingExperiment 		=> 'INSERT INTO StudyExperiment (stid,eid) VALUES ({1},{0});',
		_RecordCount	=> 0,
		_Records	=> '',
		_FieldNames	=> '',
		_Data		=> '',
		_stid		=> '',
		_description	=> '',
		_pubmed		=> '',
		_pid		=> '',
		_platformList	=> {},
		_platformValue	=> ()
	};

	bless $self, $class;
	return $self;
}

#Loads all platforms into the object from the database.
sub loadAllStudies
{
	my $self = shift;

	$self->{_Records} 	= $self->{_dbh}->prepare($self->{_LoadQuery}) or die $self->{_dbh}->errstr;
	$self->{_RecordCount}	= $self->{_Records}->execute or die $self->{_dbh}->errstr;
	$self->{_FieldNames} 	= $self->{_Records}->{NAME};
	$self->{_Data} 		= $self->{_Records}->fetchall_arrayref;
	$self->{_Records}->finish;
}

#Loads a single platform from the database based on the URL parameter.
sub loadSingleStudy
{
	#Grab object and id from URL.
	my $self 	= shift;
	$self->{_stid} 	= $self->{_FormObject}->url_param('id');

	#Use a regex to replace the ID in the query to load a single platform.
	my $singleItemQuery 	= $self->{_LoadSingleQuery};
	$singleItemQuery 	=~ s/\{0\}/\Q$self->{_stid}\E/;

	#Run the SQL and get the data into the object.
	$self->{_Records} 	= $self->{_dbh}->prepare($singleItemQuery) or die $self->{_dbh}->errstr;
	$self->{_RecordCount}	= $self->{_Records}->execute or die $self->{_dbh}->errstr;
	$self->{_Data} 		= $self->{_Records}->fetchall_arrayref;

	foreach (@{$self->{_Data}})
	{
		$self->{_description}	= $_->[1];
		$self->{_pubmed}	= $_->[2];
		$self->{_pid}		= $_->[3];		
	}

	$self->{_Records}->finish;
}

#Loads all expriments from a specific study.
sub loadAllExperimentsFromStudy
{
	my $self 	= shift;
	my $loadQuery 	= "";

	$loadQuery = $self->{_ExperimentsQuery};

	$loadQuery 	=~ s/\{0\}/\Q$self->{_stid}\E/g;

	$self->{_ExpRecords} 		= $self->{_dbh}->prepare($loadQuery) or die $self->{_dbh}->errstr;
	$self->{_ExpRecordCount}	= $self->{_ExpRecords}->execute or die $self->{_dbh}->errstr;
	$self->{_ExpFieldNames} 	= $self->{_ExpRecords}->{NAME};
	$self->{_ExpData} 		= $self->{_ExpRecords}->fetchall_arrayref;
	$self->{_ExpRecords}->finish;
}

#Loads information into the object that is used to create the platform dropdown.
sub loadPlatformData
{
	my $self		= shift;
	#Temp variables used to create the hash and array for the dropdown.
	my %platformLabel;
	my @platformValue;

	#Variables used to temporarily hold the database information.
	my $tempRecords		= '';
	my $tempRecordCount	= '';
	my @tempPlatforms	= '';

	$tempRecords 		= $self->{_dbh}->prepare($self->{_PlatformQuery}) or die $self->{_dbh}->errstr;
	$tempRecordCount	= $tempRecords->execute or die $self->{_dbh}->errstr;

	#Grab all platforms and build the hash and array for drop down.
	@tempPlatforms 		= @{$tempRecords->fetchall_arrayref};

	foreach (sort {$a->[0] cmp $b->[0]} @tempPlatforms)
	{
		$platformLabel{$_->[0]} = $_->[1];
		push(@platformValue,$_->[0]);
	}

	#Assign members variables reference to the hash and array.
	$self->{_platformList} 		= \%platformLabel;
	$self->{_platformValue} 	= \@platformValue;
	
	#Finish with database.
	$tempRecords->finish;
}

#Load the data from the submitted form.
sub loadFromForm
{
	my $self = shift;

	$self->{_description}		= ($self->{_FormObject}->param('description')) 	if defined($self->{_FormObject}->param('description'));
	$self->{_pubmed}		= ($self->{_FormObject}->param('pubmed')) 	if defined($self->{_FormObject}->param('pubmed'));
	$self->{_pid}			= ($self->{_FormObject}->param('platform')) 	if defined($self->{_FormObject}->param('platform'));
	$self->{_stid}			= ($self->{_FormObject}->url_param('id')) 	if defined($self->{_FormObject}->url_param('id'));
	$self->{_SelectedStudy}		= ($self->{_FormObject}->param('study_exist'))			if defined($self->{_FormObject}->param('study_exist'));
	$self->{_SelectedExperiment}	= ($self->{_FormObject}->param('experiment_exist'))		if defined($self->{_FormObject}->param('experiment_exist'));

}

#######################################################################################
#PRINTING HTML AND JAVASCRIPT STUFF
#######################################################################################
#Draw the javascript and HTML for the study table.
sub showStudies
{
	my $self = shift;
	my $error_string = "";

	my $JSStudyList = "var JSStudyList = 
	{
		caption: \"Showing all Studies\",
		records: [". printJSRecords($self) ."],
		headers: [". printJSHeaders($self) . "]
	};" . "\n";

	print	'<font size="5">Manage Studies</font><br /><br />' . "\n";
	print	'<h2 name = "caption" id="caption"></h2>' . "\n";
	print	'<div><a id="StudyTable_astext" onClick = "export_table(JSStudyList)">View as plain text</a></div>' . "\n";
	print	'<div id="StudyTable"></div>' . "\n";
	print	"<script type=\"text/javascript\">\n";
	print $JSStudyList;

	printTableInformation($self->{_FieldNames},$self->{_FormObject});
	printExportTable();	
	printDrawResultsTableJS();

	print 	"</script>\n";
	print	'<br /><h2 name = "Add_Caption" id = "Add_Caption">Add Study</h2>' . "\n";

	print $self->{_FormObject}->start_form(
		-method=>'POST',
		-action=>$self->{_FormObject}->url(-absolute=>1).'?a=manageStudy&ManageAction=add',
		-onsubmit=>'return validate_fields(this, [\'description\']);'
	) .
	$self->{_FormObject}->dl(
		$self->{_FormObject}->dt('description:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'description',-id=>'description',-maxlength=>100)),
		$self->{_FormObject}->dt('pubmed:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'pubmed',-id=>'pubmed',-maxlength=>20)),
		$self->{_FormObject}->dt('platform:'),
		$self->{_FormObject}->dd($self->{_FormObject}->popup_menu(-name=>'platform',-id=>'platform',-values=>\@{$self->{_platformValue}},-labels=>\%{$self->{_platformList}})),
		$self->{_FormObject}->dt('&nbsp;'),
		$self->{_FormObject}->dd($self->{_FormObject}->submit(-name=>'AddStudy',-id=>'AddStudy',-value=>'Add Study'),$self->{_FormObject}->span({-class=>'separator'},' / ')
		)
	) .
	$self->{_FormObject}->end_form;	
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
	myDataSource.responseSchema 	= {fields: ["0","1","2","3","4","5"]};
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
		$tempRecordList .= '{0:"'.$_->[1].'",1:"'.$_->[2].'",2:"'.$_->[4].'",3:"'.$_->[5].'",4:"'.$_->[0].'",5:"'.$_->[0].'"},';
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
	my $deleteURL 	= $CGIRef->url(absolute=>1).'?a=manageStudy&ManageAction=delete&id=';
	my $editURL	= $CGIRef->url(absolute=>1).'?a=manageStudy&ManageAction=edit&id=';

	print	'
		YAHOO.widget.DataTable.Formatter.formatStudyDeleteLink = function(elCell, oRecord, oColumn, oData) 
		{
			elCell.innerHTML = "<a title=\"Delete Study\" target=\"_self\" onClick = \"return deleteConfirmation();\" href=\"' . $deleteURL . '" + oData + "\">Delete</a>";
		}
		YAHOO.widget.DataTable.Formatter.formatStudyEditLink = function(elCell, oRecord, oColumn, oData) 
		{
			elCell.innerHTML = "<a title=\"Edit Study\" target=\"_self\" href=\"' . $editURL . '" + oData + "\">Edit</a>";
		}

		YAHOO.util.Dom.get("caption").innerHTML = JSStudyList.caption;
		var myColumnDefs = [
		{key:"0", sortable:true, resizeable:true, label:"Description"},
		{key:"1", sortable:true, resizeable:true, label:"PubMed"},
		{key:"2", sortable:true, resizeable:true, label:"Platform"}, 
		{key:"3", sortable:true, resizeable:true, label:"Species"},
		{key:"4", sortable:false, resizeable:true, label:"Delete Study",formatter:"formatStudyDeleteLink"},
		{key:"5", sortable:false, resizeable:true, label:"Edit Study",formatter:"formatStudyEditLink"}
		];' . "\n";
}
#######################################################################################


#######################################################################################
#ADD/DELETE/EDIT METHODS
#######################################################################################
sub insertNewStudy
{
	my $self = shift;
	my $insertStatement 	= $self->{_InsertQuery};
	$insertStatement 	=~ s/\{0\}/\Q$self->{_description}\E/;
	$insertStatement 	=~ s/\{1\}/\Q$self->{_pubmed}\E/;
	$insertStatement 	=~ s/\{2\}/\Q$self->{_pid}\E/;

	$self->{_dbh}->do($insertStatement) or die $self->{_dbh}->errstr;

	$self->{_stid} = $self->{_dbh}->{'mysql_insertid'};
}

sub deleteStudy
{
	my $self = shift;

	foreach (@{$self->{_DeleteQuery}})
	{
		my $deleteStatement 	= $_;
		$deleteStatement 	=~ s/\{0\}/\Q$self->{_stid}\E/;
		
		$self->{_dbh}->do($deleteStatement) or die $self->{_dbh}->errstr;
	}
}

sub editStudy
{
	my $self = shift;
	print	'<font size="5">Editing Study</font><br /><br />' . "\n";
	#Edit existing platform.
	print $self->{_FormObject}->start_form(
		-method=>'POST',
		-action=>$self->{_FormObject}->url(-absolute=>1).'?a=manageStudy&ManageAction=editSubmit&id=' . $self->{_stid},
		-onsubmit=>'return validate_fields(this, [\'description\']);'
	) .
	$self->{_FormObject}->dl
		(
		$self->{_FormObject}->dt('description:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'description',-id=>'description',-maxlength=>100,-value=>$self->{_description})),
		$self->{_FormObject}->dt('pubmed:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'pubmed',-id=>'pubmed',-maxlength=>20,-value=>$self->{_pubmed})),
		$self->{_FormObject}->dt('platform:'),
		$self->{_FormObject}->dd($self->{_FormObject}->popup_menu(-name=>'platform',-id=>'platform',-values=>\@{$self->{_platformValue}},-labels=>\%{$self->{_platformList}}, -readonly => 'readonly',-default=>$self->{_pid})),
		$self->{_FormObject}->dt('&nbsp;'),
		$self->{_FormObject}->dd($self->{_FormObject}->submit(-name=>'editSaveStudy',-id=>'editSaveStudy',-value=>'Save Edits'),$self->{_FormObject}->span({-class=>'separator'},' / ')
		)
	);

	my $JSExperimentList = "var JSExperimentList = 
	{
		records: [". printJSExperimentRecords($self) ."],
		headers: [". printJSExperimentHeaders($self) . "]
	};" . "\n";

	print	'<div id="ExperimentTable"></div>' . "\n";
	print	"<script type=\"text/javascript\">\n";
	print $JSExperimentList;

	printExperimentTableInformation($self->{_ExpFieldNames},$self->{_FormObject},$self->{_stid});
	printDrawExperimentResultsTableJS();

	print 	"</script>\n";
	print $self->{_FormObject}->end_form;

	print	'<script src="./js/AddExistingExperiment.js" type="text/javascript"></script>';
	print	'<br /><h2 name = "Add_Caption" id = "Add_Caption">Add Existing Experiment to this Study</h2>' . "\n";

	print 	"<script>\n";
	printJavaScriptRecordsForExistingDropDowns($self);
	print 	"</script>\n";

	print $self->{_FormObject}->start_form(
		-method=>'POST',
		-name=>'AddExistingForm',
		-action=>$self->{_FormObject}->url(-absolute=>1).'?a=manageStudy&ManageAction=addExisting&id=' . $self->{_stid},
		-onsubmit=>"return validate_fields(this,'');"
	) .
	$self->{_FormObject}->dl(
		$self->{_FormObject}->dt('Study : '),
		$self->{_FormObject}->dd($self->{_FormObject}->popup_menu(-name=>'study_exist', -id=>'study_exist',-values=>\@{$self->{_ExistingStudyValue}},-labels=>\%{$self->{_ExistingStudyList}},-default=>$self->{_SelectedStudy}, -onChange=>"populateSelectExistingExperiments(document.getElementById(\"experiment_exist\"),document.getElementById(\"study_exist\"));")),
		$self->{_FormObject}->dt('Experiment : '),
		$self->{_FormObject}->dd($self->{_FormObject}->popup_menu(-name=>'experiment_exist', -id=>'experiment_exist',-values=>\@{$self->{_ExistingExperimentValue}}, -labels=>\%{$self->{_ExistingExperimentList}},-default=>$self->{_SelectedExperiment})),
		$self->{_FormObject}->dt('&nbsp;'),
		$self->{_FormObject}->dd($self->{_FormObject}->submit(-name=>'AddExperiment',-id=>'AddExperiment',-value=>'Add Experiment'),$self->{_FormObject}->span({-class=>'separator'},' / ')
		)
	) .
	$self->{_FormObject}->end_form;

}

sub printDrawExperimentResultsTableJS
{
	print	'
	var myDataSourceExp 		= new YAHOO.util.DataSource(JSExperimentList.records);
	myDataSourceExp.responseType 	= YAHOO.util.DataSource.TYPE_JSARRAY;
	myDataSourceExp.responseSchema 	= {fields: ["0","1","2","3","4","5","6"]};
	var myData_configExp 		= {paginator: new YAHOO.widget.Paginator({rowsPerPage: 50})};
	var myDataTableExp 		= new YAHOO.widget.DataTable("ExperimentTable", myExperimentColumnDefs, myDataSourceExp, myData_configExp);' . "\n";
}


sub addExistingExperiment
{
	my $self = shift;

	my $insertStatement 	= $self->{_AddExistingExperiment};
	$insertStatement	=~ s/\{0\}/\Q$self->{_SelectedExperiment}\E/;
	$insertStatement	=~ s/\{1\}/\Q$self->{_stid}\E/;

	print $insertStatement;

	$self->{_dbh}->do($insertStatement) or die $self->{_dbh}->errstr;

}

sub printExperimentTableInformation
{
	my $arrayRef 	= shift;
	my @names 	= @$arrayRef;
	my $CGIRef 	= shift;
	my $studyID	= shift;
	my $deleteURL 	= $CGIRef->url(absolute=>1).'?a=manageStudies&ManageAction=deleteExperiment&stid=' . $studyID . '&id=';

	print	'
		YAHOO.widget.DataTable.Formatter.formatExperimentDeleteLink = function(elCell, oRecord, oColumn, oData) 
		{
			elCell.innerHTML = "<a title=\"Delete Experiment\" onClick = \"return deleteConfirmation();\" target=\"_self\" href=\"' . $deleteURL . '" + oData + "\">Delete</a>";
		}

		var myExperimentColumnDefs = [
		{key:"3", sortable:true, resizeable:true, label:"Experiment Number"},
		{key:"0", sortable:true, resizeable:true, label:"Sample 1"},
		{key:"1", sortable:true, resizeable:true, label:"Sample 2"},
		{key:"2", sortable:true, resizeable:true, label:"Probe Count"},
		{key:"5", sortable:false, resizeable:true, label:"Experiment Description"},
		{key:"6", sortable:false, resizeable:true, label:"Additional Information"},
		{key:"3", sortable:false, resizeable:true, label:"Delete Experiment",formatter:"formatExperimentDeleteLink"}
		];' . "\n";
}



#Print the Java Script records for the experiment.
sub printJSExperimentRecords
{
	my $self = shift;
	my $tempRecordList = '';

	#Loop through data and load into JavaScript array.
	foreach (@{$self->{_ExpData}}) 
	{
		foreach (@$_) 
		{
			$_ = '' if !defined $_;
			$_ =~ s/"//g;	# strip all double quotes (JSON data are bracketed with double quotes)
		}
		#eid,pid,sample1,sample2,count(1),ExperimentDescription,AdditionalInfo
		$tempRecordList .= '{0:"'.$_->[2].'",1:"'.$_->[3].'",2:"'.$_->[4].'",3:"'.$_->[0].'",4:"' . $_->[0] . '",5:"' . $_->[5] . '",6:"' . $_->[6] . '"},';
	}
	$tempRecordList =~ s/,\s*$//;	# strip trailing comma

	return $tempRecordList;
}

sub printJSExperimentHeaders
{
	my $self = shift;
	my $tempHeaderList = '';

	#Loop through data and load into JavaScript array.
	foreach (@{$self->{_ExpFieldNames}})
	{
		$tempHeaderList .= '"' . $_ . '",';
	}
	$tempHeaderList =~ s/,\s*$//;	# strip trailing comma

	return $tempHeaderList;
}

sub printJavaScriptRecordsForExistingDropDowns
{
	my $self 		= shift;

	my $studyQuery 		= $self->{_ExistingStudyQuery};
	$studyQuery 		=~ s/\{0\}/\Q$self->{_stid}\E/g;	

	my $experimentQuery	= $self->{_ExistingExperimentQuery};
	$experimentQuery 	=~ s/\{0\}/\Q$self->{_stid}\E/g;	

	my $tempRecords 	= $self->{_dbh}->prepare($studyQuery) or die $self->{_dbh}->errstr;
	my $tempRecordCount	= $tempRecords->execute or die $self->{_dbh}->errstr;

	print	'Event.observe(window, "load", init);';
	print 	"var study = {};";

	my $out = "";

	while (my @row = $tempRecords->fetchrow_array) {
		$out .= 'study['.$row[0]."] = {};\n";
		$out .= 'study['.$row[0].'][0] = \''.$row[1]."';\n"; # study description
		$out .= 'study['.$row[0]."][1] = {};\n";     # sample 1 name
		$out .= 'study['.$row[0]."][2] = {};\n";     # sample 2 name
		$out .= 'study['.$row[0].'][3] = \''.$row[2]."';\n"; # platform id
	}
	$tempRecords->finish;

	$tempRecords 		= $self->{_dbh}->prepare($experimentQuery) or die $self->{_dbh}->errstr;
	$tempRecordCount	= $tempRecords->execute or die $self->{_dbh}->errstr;

	### populate the Javascript hash with the content of the experiment recordset
	while (my @row = $tempRecords->fetchrow_array) {
		$out .= 'study['.$row[0].'][1]['.$row[1].'] = \''.$row[2]."';\n";
		$out .= 'study['.$row[0].'][2]['.$row[1].'] = \''.$row[3]."';\n";
	}
	$tempRecords->finish;

	print $out;
	print 'function init() {';
	print 'populateExistingStudy("study_exist");';
	print 'populateSelectExistingExperiments(document.getElementById("experiment_exist"),document.getElementById("study_exist"));';
	print '}';
}


sub editSubmitStudy
{	
	my $self = shift;
	my $updateStatement 	= $self->{_UpdateQuery};
	
	$updateStatement 	=~ s/\{0\}/\Q$self->{_description}\E/;
	$updateStatement 	=~ s/\{1\}/\Q$self->{_pubmed}\E/;
	$updateStatement 	=~ s/\{2\}/\Q$self->{_pid}\E/;
	$updateStatement 	=~ s/\{3\}/\Q$self->{_stid}\E/;

	$self->{_dbh}->do($updateStatement) or die $self->{_dbh}->errstr;
}
#######################################################################################

1;
