=head1 NAME

SGX::ManageMicroarrayPlatforms

=head1 SYNOPSIS

 

=head1 DESCRIPTION


=head1 AUTHORS



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
		_LoadQuery	=> 'select pname, def_f_cutoff, def_p_cutoff, species,pid from platform',
		_UpdateQuery	=> 'UPDATE platform SET pname = {0},def_f_cutoff = {1}, def_p_cutoff = {2}, species = {3} WHERE pid = {4}',
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

	$self->{_Records} 	= $self->{_dbh}->prepare($self->{_LoadQuery}) or die $self->{_dbh}->errstr;
	$self->{_RecordCount}	= $self->{_Records}->execute or die $self->{_dbh}->errstr;
	$self->{_FieldNames} 	= $self->{_Records}->{NAME};
	$self->{_Data} 		= $self->{_Records}->fetchall_arrayref;
	$self->{_PName}		= ($self->{_FormObject}->param('pname')) 	if defined($self->{_FormObject}->param('pname'));
	$self->{_def_f_cutoff}	= ($self->{_FormObject}->param('def_f_cutoff')) if defined($self->{_FormObject}->param('def_f_cutoff'));
	$self->{_def_p_cutoff}	= ($self->{_FormObject}->param('def_p_cutoff')) if defined($self->{_FormObject}->param('def_p_cutoff'));
	$self->{_Species}	= ($self->{_FormObject}->param('species')) 	if defined($self->{_FormObject}->param('species'));
	$self->{_pid}		= ($self->{_FormObject}->url_param('deleteid')) if defined($self->{_FormObject}->url_param('deleteid'));

	$self->{_Records}->finish;

	bless $self, $class;
	return $self;
}

sub showPlatforms 
{
	my $self = shift;
	my $error_string = "";
	my $JSPlatformList = "var JSPlatformList = {caption: \"Showing all Platforms\",records: [";

	#Loop through data
	foreach (sort {$a->[3] cmp $b->[3]} @{$self->{_Data}}) 
	{
		foreach (@$_) 
		{
			$_ = '' if !defined $_;
			$_ =~ s/"//g;	# strip all double quotes (JSON data are bracketed with double quotes)
		}

		$JSPlatformList .= '{0:"'.$_->[0].'",1:"'.$_->[1].'",2:"'.$_->[2].'",3:"'.$_->[3].'",4:"'.$_->[4].'"},';
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

	#Add new platform.
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
	myDataSource.responseSchema 	= {fields: ["0","1","2","3","4"]};
	var myData_config 		= {paginator: new YAHOO.widget.Paginator({rowsPerPage: 50})};
	var myDataTable 		= new YAHOO.widget.DataTable("PlatformTable", myColumnDefs, myDataSource, myData_config);' . "\n";
}

sub printTableInformation
{
	my $arrayRef = shift;
	my @names = @$arrayRef;
	my $CGIRef = shift;
	my $deleteURL = $CGIRef->url(absolute=>1).'?a=managePlatforms&ManageAction=delete&deleteid=';

	print	'
		YAHOO.widget.DataTable.Formatter.formatPlatformDeleteLink = function(elCell, oRecord, oColumn, oData) 
		{
			elCell.innerHTML = "<a title=\"Delete Platform\" target=\"_self\" href=\"' . $deleteURL . '" + oData + "\">Delete</a>";
		}

		YAHOO.util.Dom.get("caption").innerHTML = JSPlatformList.caption;
		var myColumnDefs = [
		{key:"0", sortable:true, resizeable:true, label:"'.$names[0].'"},
		{key:"1", sortable:true, resizeable:true, label:"'.$names[1].'"},
		{key:"2", sortable:true, resizeable:true, label:"'.$names[2].'"}, 
		{key:"3", sortable:true, resizeable:true, label:"'.$names[3].'"},
		{key:"4", sortable:false, resizeable:true, label:"Delete Platform",formatter:"formatPlatformDeleteLink"}];' . "\n";
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

1;
