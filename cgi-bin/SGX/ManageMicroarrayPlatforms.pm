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

use Switch;
use SGX::DrawingJavaScript;
use SGX::JavaScriptDeleteConfirm;

sub new {
	# This is the constructor
	my $class = shift;

	my @deleteStatementList;

	push @deleteStatementList,'DELETE FROM annotates WHERE rid IN (SELECT rid FROM probe WHERE pid = {0});';
	push @deleteStatementList,'DELETE FROM experiment WHERE eid IN (SELECT eid FROM StudyExperiemnt WHERE stid IN (SELECT stid FROM study WHERE pid = {0}));';
	push @deleteStatementList,'DELETE FROM StudyExperiemnt WHERE stid IN (SELECT stid FROM study WHERE pid = {0});';
	push @deleteStatementList,'DELETE FROM microarray WHERE rid in (SELECT rid FROM probe WHERE pid = {0});';
	push @deleteStatementList,'DELETE FROM probe WHERE pid = {0};';
	push @deleteStatementList,'DELETE FROM study WHERE pid = {0};';
	push @deleteStatementList,'DELETE FROM platform WHERE pid = {0};';

	my $self = {
		_dbh		=> shift,
		_cgi	=> shift,
		_LoadQuery	=> 'select 	platform.pname, 
						platform.def_f_cutoff AS \'Default Fold Change\', 
						platform.def_p_cutoff AS \'Default P-Value\', 
						platform.species AS \'Species\',
						platform.pid,
						CASE 
							WHEN isAnnotated THEN \'Y\' 
							ELSE \'N\' 
						END AS \'Annotated\',
						COUNT(probe.rid) AS \'Probe Count\',
						SUM(IF(IFNULL(probe.probe_sequence,\'\') <> \'\' ,1,0)) AS \'Probe Sequences Loaded\',
						SUM(IF(IFNULL(annotates.gid,\'\') <> \'\',1,0)) AS \'Probes with Annotations\',
						SUM(IF(IFNULL(gene.seqname,\'\') <> \'\',1,0)) AS \'Gene Symbol\',
						SUM(IF(IFNULL(gene.description,\'\') <> \'\',1,0)) AS \'Gene Name\'	
					FROM platform
					LEFT JOIN probe 		ON probe.pid = platform.pid
					LEFT JOIN annotates 	ON annotates.rid = probe.rid
					LEFT JOIN gene 			ON gene.gid = annotates.gid
					GROUP BY pname, 
					def_f_cutoff, 
					def_p_cutoff, 
					species,
					pid,
					isAnnotated;',
		_LoadSingleQuery=> 'select pname, def_f_cutoff, def_p_cutoff, species,pid,CASE WHEN isAnnotated THEN \'Y\' ELSE \'N\' END AS \'Is Annotated\' from platform WHERE pid = {0};',
		_UpdateQuery	=> 'UPDATE platform SET pname = \'{0}\',def_f_cutoff = \'{1}\', def_p_cutoff = \'{2}\', species = \'{3}\' WHERE pid = {4};',
		_InsertQuery	=> 'INSERT INTO platform (pname,def_f_cutoff,def_p_cutoff,species) VALUES (\'{0}\',\'{1}\',\'{2}\',\'{3}\');',
		_DeleteQuery	=> \@deleteStatementList,
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

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageMicroarrayPlatforms
#       METHOD:  dispatch
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  executes appropriate method for the given action
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub dispatch
{
    my ( $self, $action ) = @_;

    $action = '' if not defined($action);
    switch($action)
    {
        case 'add' 
        {
            $self->loadFromForm();
            $self->insertNewPlatform();
            print "<br />Record added - Redirecting...<br />";

            my $redirectSite   = $self->{_cgi}->url(-absolute=>1).'?a=form_uploadAnnot&newpid=' . $self->{_pid};
            my $redirectString = "<script type=\"text/javascript\">window.location = \"$redirectSite\"</script>";
            print "$redirectString";
        }
        case 'delete'
        {
            $self->loadFromForm();
            $self->deletePlatform();
            print "<br />Record deleted - Redirecting...<br />";

            my $redirectSite   = $self->{_cgi}->url(-absolute=>1).'?a=managePlatforms';
            my $redirectString = "<script type=\"text/javascript\">window.location = \"$redirectSite\"</script>";
            print "$redirectString";
        }       
        else
        {
            # default action: just display the Manage Platforms form
            $self->loadAllPlatforms();
            $self->showPlatforms();

            my $javaScriptDeleteConfirm = SGX::JavaScriptDeleteConfirm->new();
            $javaScriptDeleteConfirm->drawJavaScriptCode();
        }
    }
}

#Loads all platforms into the object from the database.
sub loadAllPlatforms
{
	my $self = shift;

	$self->{_Records} 		= $self->{_dbh}->prepare($self->{_LoadQuery}) or die $self->{_dbh}->errstr;
	$self->{_RecordCount}	= $self->{_Records}->execute or die $self->{_dbh}->errstr;
	$self->{_FieldNames} 	= $self->{_Records}->{NAME};
	$self->{_Data} 			= $self->{_Records}->fetchall_arrayref;
	$self->{_Records}->finish;
}

#Loads a single platform from the database based on the URL parameter.
sub loadSinglePlatform
{
	#Grab object and id from URL.
	my $self 	= shift;
	$self->{_pid} 	= $self->{_cgi}->url_param('id');

	#Use a regex to replace the ID in the query to load a single platform.
	my $singleItemQuery 	= $self->{_LoadSingleQuery};
	$singleItemQuery 	=~ s/\{0\}/\Q$self->{_pid}\E/;

	#Run the SQL and get the data into the object.
	$self->{_Records} 	= $self->{_dbh}->prepare($singleItemQuery) or die $self->{_dbh}->errstr;
	$self->{_RecordCount}	= $self->{_Records}->execute or die $self->{_dbh}->errstr;
	$self->{_Data} 		= $self->{_Records}->fetchall_arrayref;

	
	foreach (@{$self->{_Data}})
	{
		$self->{_PName}			= $_->[0];
		$self->{_def_f_cutoff}	= $_->[1];
		$self->{_def_p_cutoff}	= $_->[2];
		$self->{_Species}		= $_->[3];		
	}

	$self->{_Records}->finish;
}

#Load the data from the submitted form.
sub loadFromForm
{
	my $self = shift;

	$self->{_PName}		= ($self->{_cgi}->param('pname')) 	if defined($self->{_cgi}->param('pname'));
	$self->{_def_f_cutoff}	= ($self->{_cgi}->param('def_f_cutoff')) if defined($self->{_cgi}->param('def_f_cutoff'));
	$self->{_def_p_cutoff}	= ($self->{_cgi}->param('def_p_cutoff')) if defined($self->{_cgi}->param('def_p_cutoff'));
	$self->{_Species}	= ($self->{_cgi}->param('species')) 	if defined($self->{_cgi}->param('species'));
	$self->{_pid}		= ($self->{_cgi}->url_param('id')) 	if defined($self->{_cgi}->url_param('id'));
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

		$JSPlatformList .= '{0:"'.$_->[0].'",1:"'.$_->[1].'",2:"'.$_->[2].'",3:"'.$_->[3].'",4:"'.$_->[4].'",5:"'.$_->[5].'",6:"'.$_->[6].'",7:"'.$_->[7].'",8:"'.$_->[8].'",9:"'.$_->[9].'",10:"'.$_->[10].'"},';
	}
	$JSPlatformList =~ s/,\s*$//;	# strip trailing comma
	$JSPlatformList .= ']};' . "\n";
	print	'<h2>Manage Platforms</h2><br /><br />' . "\n";
	print	'<h3 name = "caption" id="caption"></h3>' . "\n";
	print	'<div><a id="PlatformTable_astext">View as plain text</a></div>' . "\n";
	print	'<div id="PlatformTable"></div>' . "\n";
	print	"<script type=\"text/javascript\">\n";
	print $JSPlatformList;

	printTableInformation($self->{_FieldNames},$self->{_cgi});
	printExportTable();	
	printDrawResultsTableJS();

	print 	"</script>\n";

	print	'<br /><h3 name = "Add_Caption" id = "Add_Caption">Add Platform</h3>' . "\n";

	#.
	print $self->{_cgi}->start_form(
		-method=>'POST',
		-action=>$self->{_cgi}->url(-absolute=>1).'?a=managePlatforms&ManageAction=add',
		-onsubmit=>'return validate_fields(this, [\'pname\',\'species\']);'
	) .
	$self->{_cgi}->dl(
		$self->{_cgi}->dt('pname:'),
		$self->{_cgi}->dd($self->{_cgi}->textfield(-name=>'pname',-id=>'pname',-maxlength=>120)),
		$self->{_cgi}->dt('def_f_cutoff:'),
		$self->{_cgi}->dd($self->{_cgi}->textfield(-name=>'def_f_cutoff',-id=>'def_f_cutoff')),
		$self->{_cgi}->dt('def_p_cutoff:'),
		$self->{_cgi}->dd($self->{_cgi}->textfield(-name=>'def_p_cutoff',-id=>'def_p_cutoff')),
		$self->{_cgi}->dt('species:'),
		$self->{_cgi}->dd($self->{_cgi}->textfield(-name=>'species',-id=>'species',-maxlength=>255)),
		$self->{_cgi}->dt('&nbsp;'),
		$self->{_cgi}->dd($self->{_cgi}->submit(-name=>'AddPlatform',-id=>'AddPlatform',-value=>'Add Platform'),$self->{_cgi}->span({-class=>'separator'},' / ')
		)
	) .
	$self->{_cgi}->end_form;	
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
	myDataSource.responseSchema 	= {fields: ["0","1","2","3","4","5","6","7","8","9","10"]};
	var myData_config 		= {paginator: new YAHOO.widget.Paginator({rowsPerPage: 50})};
	var myDataTable 		= new YAHOO.widget.DataTable("PlatformTable", myColumnDefs, myDataSource, myData_config);' . "\n" . '
	
	// Set up editing flow 
	var highlightEditableCell = function(oArgs) { 
		var elCell = oArgs.target; 
		if(YAHOO.util.Dom.hasClass(elCell, "yui-dt-editable")) { 
		this.highlightCell(elCell); 
		} 
	}; 
	
	myDataTable.subscribe("cellMouseoverEvent", highlightEditableCell); 
	myDataTable.subscribe("cellMouseoutEvent", myDataTable.onEventUnhighlightCell); 
	myDataTable.subscribe("cellClickEvent", myDataTable.onEventShowCellEditor);';
	
}

sub printTableInformation
{
	my $arrayRef 	= shift;
	my @names 	= @$arrayRef;
	my $CGIRef 	= shift;
	my $deleteURL 	= $CGIRef->url(absolute=>1).'?a=managePlatforms&ManageAction=delete&id=';
	my $editURL	= $CGIRef->url(absolute=>1).'?a=managePlatforms&ManageAction=edit&id=';

	#This is the code to use the AJAXy update box for platform name..
	my $postBackURLpname				= '"'.$CGIRef->url(-absolute=>1).'?a=updateCell"';
	my $postBackQueryParameterspname 	= '"type=platform&pname=" + escape(newValue) + "&fold=" + encodeURI(record.getData("1")) + "&pvalue=" + encodeURI(record.getData("2")) + "&pid=" + encodeURI(record.getData("4"))';
	my $textCellEditorObjectpname		= new SGX::DrawingJavaScript($postBackURLpname,$postBackQueryParameterspname);	
	
	#This is the code to use the AJAXy update box for Default Fold Change..
	my $postBackURLfold				= '"'.$CGIRef->url(-absolute=>1).'?a=updateCell"';
	my $postBackQueryParametersfold	= '"type=platform&pname=" + encodeURI(record.getData("0")) + "&fold=" + escape(newValue) + "&pvalue=" + encodeURI(record.getData("2")) + "&pid=" + encodeURI(record.getData("4"))';
	my $textCellEditorObjectfold	= new SGX::DrawingJavaScript($postBackURLfold,$postBackQueryParametersfold);		
	
	#This is the code to use the AJAXy update box for P-value..
	my $postBackURLpvalue				= '"'.$CGIRef->url(-absolute=>1).'?a=updateCell"';
	my $postBackQueryParameterspvalue	= '"type=platform&pname=" + encodeURI(record.getData("0")) + "&fold=" + encodeURI(record.getData("1")) + "&pvalue=" + escape(newValue) + "&pid=" + encodeURI(record.getData("4"))';
	my $textCellEditorObjectpvalue		= new SGX::DrawingJavaScript($postBackURLpvalue,$postBackQueryParameterspvalue);		
	
	print	'
		YAHOO.widget.DataTable.Formatter.formatPlatformDeleteLink = function(elCell, oRecord, oColumn, oData) 
		{
			elCell.innerHTML = "<a title=\"Delete Platform\" onClick = \"alert(\'This feature has been disabled till password protection can be implemented.\');return false;\" target=\"_self\" href=\"' . $deleteURL . '" + oData + "\">Delete</a>";
		}

		YAHOO.util.Dom.get("caption").innerHTML = JSPlatformList.caption;
		var myColumnDefs = [
		{key:"0", sortable:true, resizeable:true, label:"'.$names[0].'",editor:' . $textCellEditorObjectpname->printTextCellEditorCode() . '},
		{key:"1", sortable:true, resizeable:true, label:"'.$names[1].'",editor:' . $textCellEditorObjectfold->printTextCellEditorCode() . '},
		{key:"2", sortable:true, resizeable:true, label:"'.$names[2].'",editor:' . $textCellEditorObjectpvalue->printTextCellEditorCode() . '}, 
		{key:"3", sortable:true, resizeable:true, label:"'.$names[3].'"},
		{key:"5", sortable:true, resizeable:true, label:"'.$names[5].'"},
		{key:"4", sortable:false, resizeable:true, label:"Delete Platform",formatter:"formatPlatformDeleteLink"},
		{key:"6", sortable:false, resizeable:true, label:"Probe Count"},
		{key:"7", sortable:false, resizeable:true, label:"Probe Sequences Loaded"},
		{key:"8", sortable:false, resizeable:true, label:"Probes with Annotations"},
		{key:"9", sortable:false, resizeable:true, label:"Gene Symbols"},
		{key:"10", sortable:false, resizeable:true, label:"Gene Names"}
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

	$self->{_pid}		= $self->{_dbh}->{'mysql_insertid'};
}

sub deletePlatform
{
	my $self = shift;

	foreach (@{$self->{_DeleteQuery}})
	{
		my $deleteStatement 	= $_;
		$deleteStatement 	=~ s/\{0\}/\Q$self->{_pid}\E/;
		
		$self->{_dbh}->do($deleteStatement) or die $self->{_dbh}->errstr;
	}

}

sub editPlatform
{
	my $self = shift;

	print	'<h2>Editing Platform</h2><br /><br />' . "\n";

	#Edit existing platform.
	print $self->{_cgi}->start_form(
		-method=>'POST',
		-action=>$self->{_cgi}->url(-absolute=>1).'?a=managePlatforms&ManageAction=editSubmit&id=' . $self->{_pid},
		-onsubmit=>'return validate_fields(this, [\'pname\',\'species\']);'
	) .
	$self->{_cgi}->dl(
		$self->{_cgi}->dt('pname:'),
		$self->{_cgi}->dd($self->{_cgi}->textfield(-name=>'pname',-id=>'pname',-maxlength=>120,-value=>$self->{_PName})),
		$self->{_cgi}->dt('def_f_cutoff:'),
		$self->{_cgi}->dd($self->{_cgi}->textfield(-name=>'def_f_cutoff',-id=>'def_f_cutoff',value=>$self->{_def_f_cutoff})),
		$self->{_cgi}->dt('def_p_cutoff:'),
		$self->{_cgi}->dd($self->{_cgi}->textfield(-name=>'def_p_cutoff',-id=>'def_p_cutoff',value=>$self->{_def_p_cutoff})),
		$self->{_cgi}->dt('species:'),
		$self->{_cgi}->dd($self->{_cgi}->textfield(-name=>'species',-id=>'species',-maxlength=>255,value=>$self->{_Species})),
		$self->{_cgi}->dt('&nbsp;'),
		$self->{_cgi}->dd($self->{_cgi}->submit(-name=>'SaveEdits',-id=>'SaveEdits',-value=>'Save Edits'),$self->{_cgi}->span({-class=>'separator'},' / ')
		)
	) .
	$self->{_cgi}->end_form;	
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
