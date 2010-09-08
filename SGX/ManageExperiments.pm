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
						AdditionalInformation,
						IFNULL(study.description,'No Study'),
						platform.pname
					FROM	experiment 
					LEFT JOIN study ON study.stid = experiment.stid
					LEFT JOIN platform ON platform.pid = study.pid
					LEFT JOIN microarray ON microarray.eid = experiment.eid
					WHERE experiment.stid = {0}
					GROUP BY experiment.eid,
						study.pid,
						experiment.sample1,
						experiment.sample2,
						ExperimentDescription,
						AdditionalInformation
					ORDER BY experiment.eid ASC;
				   ",
		_LoadAllExperimentsQuery	=> "	SELECT 	experiment.eid,
						study.pid,
						experiment.sample1,
						experiment.sample2,
						COUNT(1),
						ExperimentDescription,
						AdditionalInformation,
						IFNULL(study.description,'No Study'),
						platform.pname						
					FROM	experiment 
					LEFT JOIN study 	ON study.stid = experiment.stid
					LEFT JOIN platform 	ON platform.pid = study.pid					
					LEFT JOIN microarray 	ON microarray.eid = experiment.eid
					LEFT JOIN probe 	ON probe.rid = microarray.rid
					WHERE (probe.pid = {1} OR {1} = 0)
					GROUP BY experiment.eid,
						study.pid,
						experiment.sample1,
						experiment.sample2,
						ExperimentDescription,
						AdditionalInformation
					ORDER BY experiment.eid ASC;
				   ",
		_LoadSingleQuery=> "SELECT	eid,
						sample1,
						sample2,
						ExperimentDescription,
						AdditionalInformation
					FROM	experiment 
					INNER JOIN study ON study.stid = experiment.stid
					WHERE	experiment.eid = {0}
					GROUP BY experiment.eid,
						experiment.sample1,
						experiment.sample2,
						ExperimentDescription,
						AdditionalInformation
					ORDER BY experiment.eid ASC;
				",				   
		
		_UpdateQuery	=> 'UPDATE experiment SET ExperimentDescription = \'{0}\', AdditionalInformation = \'{1}\', sample1 = \'{2}\', sample2 = \'{3}\' WHERE eid = {4};',
		_DeleteQuery	=> \@deleteStatementList,
		_StudyQuery	=> 'SELECT 0,\'ALL\' UNION SELECT stid,description FROM study;',
		_StudyPlatformQuery	=> 'SELECT pid,stid,description FROM study;',
		_PlatformQuery			=> "SELECT 0,\'ALL\' UNION SELECT pid,CONCAT(pname ,\' \\\\ \',species) FROM platform;",
		_PlatformList		=> '',
		_PlatformValues		=> '',
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
		_ExistingExperimentList	=> {},
		_ExistingExperimentValue => (),
		_sample1	=> '',
		_sample2	=> '',
		_ExperimentDescription => '',
		_AdditionalInformation => '',
		_SelectedStudy	=> 0,
		_SelectExperiment => 0
	};

	bless $self, $class;
	return $self;
}

#Loads all expriments from a specific study.
sub loadAllExperimentsFromStudy
{
	my $self 	= shift;
	my $loadQuery 	= "";

	if($self->{_stid} == 0)
	{
		$loadQuery = $self->{_LoadAllExperimentsQuery};
	}
	else
	{
		$loadQuery = $self->{_LoadQuery};
	}
			
	$loadQuery 	=~ s/\{0\}/\Q$self->{_stid}\E/g;
	$loadQuery 	=~ s/\{1\}/\Q$self->{_pid}\E/g;

	$self->{_Records} 		= $self->{_dbh}->prepare($loadQuery) or die $self->{_dbh}->errstr;
	$self->{_RecordCount}	= $self->{_Records}->execute or die $self->{_dbh}->errstr;
	$self->{_FieldNames} 	= $self->{_Records}->{NAME};
	$self->{_Data} 			= $self->{_Records}->fetchall_arrayref;
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
	$singleItemQuery 	=~ s/\{0\}/\Q$self->{_eid}\E/g;

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
	}

	$self->{_Records}->finish;
}

#Loads information into the object that is used to create the study dropdown.
sub loadStudyData
{
	my $self		= shift;

	my $studyDropDown	= new SGX::DropDownData($self->{_dbh},$self->{_StudyQuery},0);

	$studyDropDown->loadDropDownValues();

	$self->{_studyList} 	= $studyDropDown->{_dropDownList};
	$self->{_studyValue} 	= $studyDropDown->{_dropDownValue};
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

#Load the data from the submitted form.
sub loadFromForm
{
	my $self = shift;

	$self->{_pid}			= ($self->{_FormObject}->param('platform_load'))		if defined($self->{_FormObject}->param('platform_load'));
	$self->{_eid}			= ($self->{_FormObject}->param('eid')) 				if defined($self->{_FormObject}->param('eid'));
	$self->{_stid}			= ($self->{_FormObject}->param('stid'))				if defined($self->{_FormObject}->param('stid'));
	$self->{_stid}			= ($self->{_FormObject}->url_param('stid'))			if defined($self->{_FormObject}->url_param('stid'));	
	$self->{_eid}			= ($self->{_FormObject}->url_param('id')) 			if defined($self->{_FormObject}->url_param('id'));
}

#######################################################################################
#PRINTING HTML AND JAVASCRIPT STUFF
#######################################################################################
#Draw the javascript and HTML for the experiment table.
sub showExperiments
{
	my $self = shift;
	my $error_string = "";

	#This block of logic controls our double dropdowns for platform/study.
	print	'<script src="./js/PlatformStudySelection.js" type="text/javascript"></script>';
	print	"<script type=\"text/javascript\">\n";
	printJavaScriptRecordsForFilterDropDowns($self);	
	print 	"</script>\n";		
	
	print	'<font size="5">Manage Experiments</font><br /><br />' . "\n";

	#Load the study dropdown to choose which experiments to load into table.
	print $self->{_FormObject}->start_form(
		-method=>'POST',
		-action=>$self->{_FormObject}->url(-absolute=>1).'?a=form_manageExperiments&ManageAction=load',
		-onsubmit=>'return validate_fields(this, [\'study\']);'
	) .
	$self->{_FormObject}->dl(
		$self->{_FormObject}->dt('Platform:'),
		$self->{_FormObject}->dd($self->{_FormObject}->popup_menu(-name=>'platform_load',-id=>'platform_load',-values=>\@{$self->{_platformValue}},-labels=>\%{$self->{_platformList}},onChange=>"populateSelectFilterStudy(document.getElementById(\"stid\"),document.getElementById(\"platform_load\"));")),	
		$self->{_FormObject}->dt('Study:'),
		$self->{_FormObject}->dd($self->{_FormObject}->popup_menu(-name=>'stid',-id=>'stid',-values=>\@{$self->{_studyValue}},-labels=>\%{$self->{_studyList}},-default=>$self->{_stid})),
		$self->{_FormObject}->dt('&nbsp;'),
		$self->{_FormObject}->dd($self->{_FormObject}->submit(-name=>'SelectStudy',-id=>'SelectStudy',-value=>'Load Study'),$self->{_FormObject}->span({-class=>'separator'})
		)
	) .
	$self->{_FormObject}->end_form;
	
	#If we have selected and loaded an experiment, load the table.
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

		my $addExperimentInfo = new SGX::AddExperiment($self->{_dbh},$self->{_FormObject},'manageExperiments');
		$addExperimentInfo->loadFromForm();
		$addExperimentInfo->loadPlatformData();
		$addExperimentInfo->drawAddExperimentMenu();
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

sub printTextCellEditor
{
	my $self = shift;

	print '
	YAHOO.widget.TextareaCellEditor
	(
		{
			disableBtns: false,
			asyncSubmitter: function(callback, newValue) 
			{ 
				var record = this.getRecord();
				if (this.value == newValue) 
				{ 
					callback(); 
				} 

				YAHOO.util.Connect.asyncRequest
				(
					"POST", 
					"'.$self->{_FormObject}->url(-absolute=>1).'?a=updateCell", 
					{ 
						success:function(o) 
						{ 
							if(o.status === 200) 
							{
								// HTTP 200 OK
								callback(true, newValue); 
							} 
							else 
							{ 
								alert(o.statusText);
								//callback();
							} 
						}, 
						failure:function(o) 
						{ 
							alert(o.statusText); 
							callback(); 
						},
						scope:this 
					}, 
					"type=probe&note=" + 
						escape(newValue) + 
						"&pname=" + 
						encodeURI(record.getData("1")) + 
						"&reporter=" + 
						encodeURI(record.getData("0"))
				);
			}
		}
	);';


}

sub printDrawResultsTableJS
{
	print	'
	var myDataSource 		= new YAHOO.util.DataSource(JSStudyList.records);
	myDataSource.responseType 	= YAHOO.util.DataSource.TYPE_JSARRAY;
	myDataSource.responseSchema 	= {fields: ["0","1","2","3","4","5","6","7","8"]};
	var myData_config 		= {paginator: new YAHOO.widget.Paginator({rowsPerPage: 50})};
	var myDataTable 		= new YAHOO.widget.DataTable("StudyTable", myColumnDefs, myDataSource, myData_config);' . "\n";
}

sub printJSRecords
{
	my $self = shift;
	my $tempRecordList = '';

	#Loop through data and load into JavaScript array.
	foreach (@{$self->{_Data}}) 
	{
		foreach (@$_) 
		{
			$_ = '' if !defined $_;
			$_ =~ s/"//g;	# strip all double quotes (JSON data are bracketed with double quotes)
		}
		#eid,pid,sample1,sample2,count(1),ExperimentDescription,AdditionalInfo,Study Description,platform name
		$tempRecordList .= '{0:"'.$_->[2].'",1:"'.$_->[3].'",2:"'.$_->[4].'",3:"'.$_->[0].'",4:"' . $_->[0] . '",5:"' . $_->[5] . '",6:"' . $_->[6] . '",7:"' . $_->[7] . '",8:"' . $_->[8] . '"},';
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
	my $deleteURL 	= $CGIRef->url(absolute=>1).'?a=manageExperiments&ManageAction=delete&stid=' . $studyID . '&id=';
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

		YAHOO.util.Dom.get("caption").innerHTML = JSStudyList.caption;
		var myColumnDefs = [
		{key:"3", sortable:true, resizeable:true, label:"Experiment Number"},
		{key:"0", sortable:true, resizeable:true, label:"Sample 1"},
		{key:"1", sortable:true, resizeable:true, label:"Sample 2"},
		{key:"2", sortable:true, resizeable:true, label:"Probe Count"},
		{key:"5", sortable:false, resizeable:true, label:"Experiment Description"},
		{key:"6", sortable:false, resizeable:true, label:"Additional Information"},
		{key:"3", sortable:false, resizeable:true, label:"Delete Experiment",formatter:"formatExperimentDeleteLink"},
		{key:"7", sortable:true, resizeable:true, label:"Study Description"},
		{key:"8", sortable:true, resizeable:true, label:"Platform Name"}
		];' . "\n";
}


sub printJavaScriptRecordsForFilterDropDowns
{
	my $self 		= shift;

	my $studyQuery 		= $self->{_StudyPlatformQuery};

	my $tempRecords 	= $self->{_dbh}->prepare($studyQuery) or die $self->{_dbh}->errstr;
	my $tempRecordCount	= $tempRecords->execute or die $self->{_dbh}->errstr;

	print 	"var studies = {};";

	my $out = "";

	while (my @row = $tempRecords->fetchrow_array) {
		$out .= 'studies['.$row[1]."] = {};\n"; # Study ID
		$out .= 'studies['.$row[1].'][0] = \''.$row[2]."';\n"; #Study Description
		$out .= 'studies['.$row[1].'][1] = \''.$row[0]."';\n"; #PID
	}
	$tempRecords->finish;
	
	print $out;
	
}



#######################################################################################


#######################################################################################
#ADD/DELETE/EDIT METHODS
#######################################################################################
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

sub addNewExperiment
{
	my $self = shift;
	
	my $addExperimentInfo = new SGX::AddExperiment($self->{_dbh},$self->{_FormObject},'manageExperiments');
	$addExperimentInfo->loadFromForm();
	$addExperimentInfo->addNewExperiment();
}

#######################################################################################

1;
