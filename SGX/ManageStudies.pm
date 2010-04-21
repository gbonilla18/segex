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

sub new {
	# This is the constructor
	my $class = shift;

	my @deleteStatementList;

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

	$self->{_description}	= ($self->{_FormObject}->param('description')) 	if defined($self->{_FormObject}->param('description'));
	$self->{_pubmed}	= ($self->{_FormObject}->param('pubmed')) 	if defined($self->{_FormObject}->param('pubmed'));
	$self->{_pid}		= ($self->{_FormObject}->param('platform')) 	if defined($self->{_FormObject}->param('platform'));
	$self->{_stid}		= ($self->{_FormObject}->url_param('id')) 	if defined($self->{_FormObject}->url_param('id'));

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
		$self->{_FormObject}->dd($self->{_FormObject}->popup_menu(-name=>'platform',-id=>'platform',-values=>\@{$self->{_platformValue}},-labels=>\%{$self->{_platformList}},-default=>$self->{_pid})),
		$self->{_FormObject}->dt('&nbsp;'),
		$self->{_FormObject}->dd($self->{_FormObject}->submit(-name=>'editSaveStudy',-id=>'editSaveStudy',-value=>'Save Edits'),$self->{_FormObject}->span({-class=>'separator'},' / ')
		)
	) .
	$self->{_FormObject}->end_form;	
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
