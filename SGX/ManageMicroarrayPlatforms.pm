=head1 NAME

SGX::ManageMicroarrayPlatforms

=head1 SYNOPSIS

=head1 DESCRIPTION
Grouping of functions for managing platforms.

=head1 AUTHORS
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::ManageMicroarrayPlatforms;

use strict;
use warnings;

sub new {
	# This is the constructor
	my $class = shift;

	my $self = {
		_dbh		=> shift,
		_FormObject	=> shift,
		_LoadQuery	=> 'select pname, def_f_cutoff, def_p_cutoff, species,pid from platform;',
		_LoadSingleQuery=> 'select pname, def_f_cutoff, def_p_cutoff, species,pid from platform WHERE pid = {0};',
		_UpdateQuery	=> 'UPDATE platform SET pname = \'{0}\',def_f_cutoff = \'{1}\', def_p_cutoff = \'{2}\', species = \'{3}\' WHERE pid = {4};',
		_InsertQuery	=> 'INSERT INTO platform (pname,def_f_cutoff,def_p_cutoff,species) VALUES (\'{0}\',\'{1}\',\'{2}\',\'{3}\');',
		_DeleteQuery	=> 'DELETE FROM platform WHERE pid = {0};',
		_RecordCount	=> 0,
		_Records	=> '',
		_FieldNames	=> '',
		_Data		=> '',
		_pid		=> '',
		_PName		=> '',
		_def_f_cutoff	=> '',
		_def_p_cutoff	=> '',
		_Species	=> ''
	};

	bless $self, $class;
	return $self;
}

#Loads all platforms into the object from the database.
sub loadAllPlatforms
{
	my $self = shift;

	$self->{_Records} 	= $self->{_dbh}->prepare($self->{_LoadQuery}) or die $self->{_dbh}->errstr;
	$self->{_RecordCount}	= $self->{_Records}->execute or die $self->{_dbh}->errstr;
	$self->{_FieldNames} 	= $self->{_Records}->{NAME};
	$self->{_Data} 		= $self->{_Records}->fetchall_arrayref;
	$self->{_Records}->finish;
}

#Loads a single platform from the database based on the URL parameter.
sub loadSinglePlatform
{
	#Grab object and id from URL.
	my $self 	= shift;
	$self->{_pid} 	= $self->{_FormObject}->url_param('id');

	#Use a regex to replace the ID in the query to load a single platform.
	my $singleItemQuery 	= $self->{_LoadSingleQuery};
	$singleItemQuery 	=~ s/\{0\}/\Q$self->{_pid}\E/;

	#Run the SPROC and get the data into the object.
	$self->{_Records} 	= $self->{_dbh}->prepare($singleItemQuery) or die $self->{_dbh}->errstr;
	$self->{_RecordCount}	= $self->{_Records}->execute or die $self->{_dbh}->errstr;
	$self->{_Data} 		= $self->{_Records}->fetchall_arrayref;

	
	foreach (@{$self->{_Data}})
	{
		$self->{_PName}		= $_->[0];
		$self->{_def_f_cutoff}	= $_->[1];
		$self->{_def_p_cutoff}	= $_->[2];
		$self->{_Species}	= $_->[3];		
	}

	$self->{_Records}->finish;
}

#Load the data from the submitted form.
sub loadFromForm
{
	my $self = shift;

	$self->{_PName}		= ($self->{_FormObject}->param('pname')) 	if defined($self->{_FormObject}->param('pname'));
	$self->{_def_f_cutoff}	= ($self->{_FormObject}->param('def_f_cutoff')) if defined($self->{_FormObject}->param('def_f_cutoff'));
	$self->{_def_p_cutoff}	= ($self->{_FormObject}->param('def_p_cutoff')) if defined($self->{_FormObject}->param('def_p_cutoff'));
	$self->{_Species}	= ($self->{_FormObject}->param('species')) 	if defined($self->{_FormObject}->param('species'));
	$self->{_pid}		= ($self->{_FormObject}->url_param('id')) 	if defined($self->{_FormObject}->url_param('id'));
}

#Draw the javascript and HTML for the platform table.
sub showPlatforms 
{
	my $self = shift;
	my $error_string = "";
	my $JSPlatformList = "var JSPlatformList = {caption: \"Showing all Platforms\",records: [";

	#Loop through data and load into JavaScript array.
	foreach (sort {$a->[3] cmp $b->[3]} @{$self->{_Data}}) 
	{
		foreach (@$_) 
		{
			$_ = '' if !defined $_;
			$_ =~ s/"//g;	# strip all double quotes (JSON data are bracketed with double quotes)
		}

		$JSPlatformList .= '{0:"'.$_->[0].'",1:"'.$_->[1].'",2:"'.$_->[2].'",3:"'.$_->[3].'",4:"'.$_->[4].'",5:"'.$_->[4].'"},';
	}
	$JSPlatformList =~ s/,\s*$//;	# strip trailing comma
	$JSPlatformList .= ']};' . "\n";

	print	'<h2 name = "caption" id="caption"></h2>' . "\n";
	print	'<div><a id="PlatformTable_astext">View as plain text</a></div>' . "\n";
	print	'<div id="PlatformTable"></div>' . "\n";
	print	"<script type=\"text/javascript\">\n";
	print $JSPlatformList;

	printTableInformation($self->{_FieldNames},$self->{_FormObject});
	printExportTable();	
	printDrawResultsTableJS();

	print 	"</script>\n";

	print	'<br /><h2 name = "Add_Caption" id = "Add_Caption">Add Platform</h2>' . "\n";

	#.
	print $self->{_FormObject}->start_form(
		-method=>'POST',
		-action=>$self->{_FormObject}->url(-absolute=>1).'?a=managePlatforms&ManageAction=add',
		-onsubmit=>'return validate_fields(this, [\'pname\',\'species\']);'
	) .
	$self->{_FormObject}->dl(
		$self->{_FormObject}->dt('pname:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'pname',-id=>'pname',-maxlength=>20)),
		$self->{_FormObject}->dt('def_f_cutoff:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'def_f_cutoff',-id=>'def_f_cutoff')),
		$self->{_FormObject}->dt('def_p_cutoff:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'def_p_cutoff',-id=>'def_p_cutoff')),
		$self->{_FormObject}->dt('species:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'species',-id=>'species',-maxlength=>255)),
		$self->{_FormObject}->dt('&nbsp;'),
		$self->{_FormObject}->dd($self->{_FormObject}->submit(-name=>'AddPlatform',-id=>'AddPlatform',-value=>'Add Platform'),$self->{_FormObject}->span({-class=>'separator'},' / ')
		)
	) .
	$self->{_FormObject}->end_form;	
}

#This prints the results table to a printable text screen.
sub printExportTable
{

print '
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
}';

}

sub printDrawResultsTableJS
{
	print	'
	var myDataSource 		= new YAHOO.util.DataSource(JSPlatformList.records);
	myDataSource.responseType 	= YAHOO.util.DataSource.TYPE_JSARRAY;
	myDataSource.responseSchema 	= {fields: ["0","1","2","3","4","5"]};
	var myData_config 		= {paginator: new YAHOO.widget.Paginator({rowsPerPage: 50})};
	var myDataTable 		= new YAHOO.widget.DataTable("PlatformTable", myColumnDefs, myDataSource, myData_config);' . "\n";
}

sub printTableInformation
{
	my $arrayRef 	= shift;
	my @names 	= @$arrayRef;
	my $CGIRef 	= shift;
	my $deleteURL 	= $CGIRef->url(absolute=>1).'?a=managePlatforms&ManageAction=delete&id=';
	my $editURL	= $CGIRef->url(absolute=>1).'?a=managePlatforms&ManageAction=edit&id=';

	print	'
		YAHOO.widget.DataTable.Formatter.formatPlatformDeleteLink = function(elCell, oRecord, oColumn, oData) 
		{
			elCell.innerHTML = "<a title=\"Delete Platform\" target=\"_self\" href=\"' . $deleteURL . '" + oData + "\">Delete</a>";
		}
		YAHOO.widget.DataTable.Formatter.formatPlatformEditLink = function(elCell, oRecord, oColumn, oData) 
		{
			elCell.innerHTML = "<a title=\"Edit Platform\" target=\"_self\" href=\"' . $editURL . '" + oData + "\">Edit</a>";
		}

		YAHOO.util.Dom.get("caption").innerHTML = JSPlatformList.caption;
		var myColumnDefs = [
		{key:"0", sortable:true, resizeable:true, label:"'.$names[0].'"},
		{key:"1", sortable:true, resizeable:true, label:"'.$names[1].'"},
		{key:"2", sortable:true, resizeable:true, label:"'.$names[2].'"}, 
		{key:"3", sortable:true, resizeable:true, label:"'.$names[3].'"},
		{key:"4", sortable:false, resizeable:true, label:"Delete Platform",formatter:"formatPlatformDeleteLink"},
		{key:"5", sortable:false, resizeable:true, label:"Edit Platform",formatter:"formatPlatformEditLink"},
		];' . "\n";
}

sub insertNewPlatform
{
	my $self = shift;
	my $insertStatement 	= $self->{_InsertQuery};
	$insertStatement 	=~ s/\{0\}/\Q$self->{_PName}\E/;
	$insertStatement 	=~ s/\{1\}/\Q$self->{_def_f_cutoff}\E/;
	$insertStatement 	=~ s/\{2\}/\Q$self->{_def_p_cutoff}\E/;
	$insertStatement 	=~ s/\{3\}/\Q$self->{_Species}\E/;

	$self->{_dbh}->do($insertStatement) or die $self->{_dbh}->errstr;
}

sub deletePlatform
{
	my $self = shift;
	my $deleteStatement 	= $self->{_DeleteQuery};
	$deleteStatement 	=~ s/\{0\}/\Q$self->{_pid}\E/;

	$self->{_dbh}->do($deleteStatement) or die $self->{_dbh}->errstr;
}

sub editPlatform
{
	my $self = shift;

	#Edit existing platform.
	print $self->{_FormObject}->start_form(
		-method=>'POST',
		-action=>$self->{_FormObject}->url(-absolute=>1).'?a=managePlatforms&ManageAction=editSubmit&id=' . $self->{_pid},
		-onsubmit=>'return validate_fields(this, [\'pname\',\'species\']);'
	) .
	$self->{_FormObject}->dl(
		$self->{_FormObject}->dt('pname:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'pname',-id=>'pname',-maxlength=>20,-value=>$self->{_PName})),
		$self->{_FormObject}->dt('def_f_cutoff:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'def_f_cutoff',-id=>'def_f_cutoff',value=>$self->{_def_f_cutoff})),
		$self->{_FormObject}->dt('def_p_cutoff:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'def_p_cutoff',-id=>'def_p_cutoff',value=>$self->{_def_p_cutoff})),
		$self->{_FormObject}->dt('species:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'species',-id=>'species',-maxlength=>255,value=>$self->{_Species})),
		$self->{_FormObject}->dt('&nbsp;'),
		$self->{_FormObject}->dd($self->{_FormObject}->submit(-name=>'SaveEdits',-id=>'SaveEdits',-value=>'Save Edits'),$self->{_FormObject}->span({-class=>'separator'},' / ')
		)
	) .
	$self->{_FormObject}->end_form;	
}

sub editSubmitPlatform
{	
	my $self = shift;
	my $updateStatement 	= $self->{_UpdateQuery};
	$updateStatement 	=~ s/\{0\}/\Q$self->{_PName}\E/;
	$updateStatement 	=~ s/\{1\}/\Q$self->{_def_f_cutoff}\E/;
	$updateStatement 	=~ s/\{2\}/\Q$self->{_def_p_cutoff}\E/;
	$updateStatement 	=~ s/\{3\}/\Q$self->{_Species}\E/;
	$updateStatement 	=~ s/\{4\}/\Q$self->{_pid}\E/;

	$self->{_dbh}->do($updateStatement) or die $self->{_dbh}->errstr;
}
1;
