
=head1 NAME

SGX::ManageProjects

=head1 SYNOPSIS

=head1 DESCRIPTION
Grouping of functions for managing projects.

=head1 AUTHORS
Eugene Scherba

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::ManageProjects;

use strict;
use warnings;

use CGI::Carp qw/croak/;

use SGX::Debug;
use SGX::DropDownData;
use SGX::DrawingJavaScript;

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my $class = shift;

    my $self = {
        _dbh        => shift,
        _FormObject => shift,
        _js_dir     => shift,

        # _UserQuery: load all users
        _UserQuery =>
'SELECT uid, CONCAT(uname ,\' \\\\ \', full_name) FROM users WHERE email_confirmed',

        # _LoadQuery: show all projects
        _LoadQuery => 'SELECT prid, prname, prdesc, users.uname as mgr_name  '
          . 'FROM project '
          . 'LEFT JOIN users ON project.manager = users.uid',

        # _LoadSingleQuery: show single project
        _LoadSingleQuery =>
          'SELECT prid, prname, prdesc FROM project WHERE prid=?',

        # _UpdateQuery: update project description
        _UpdateQuery =>
          'UPDATE project SET prname=?, prdesc=?, manager=? WHERE prid=?',

        # _InsertQuery: insert into project (what about ProjectStudy?)
        _InsertQuery =>
          'INSERT INTO project (prname, prdesc, manager) VALUES (?, ?, ?)',

        # _DeleteQuery: delete from both ProjectStudy and project
        _DeleteQuery => 'DELETE FROM project WHERE prid=?',

# _StudiesQuery:
# select (and describe by platform) all studies that are a part of the given project
        _StudiesQuery => 'SELECT study.stid AS stid, '
          . '       study.description AS study_desc, '
          . '       study.pubmed AS pubmed, '
          . '       platform.pname '
          . 'FROM study '
          . 'RIGHT JOIN ProjectStudy USING (stid) '
          . 'LEFT JOIN platform USING (pid) '
          . 'WHERE ProjectStudy.prid = ?',
        _StudyRecordCount => 0,
        _StudyRecords     => '',
        _StudyFieldNames  => '',
        _StudyData        => '',

       # _ExistingProjectQuery: select all projects that are not current project
        _ExistingProjectQuery => 'SELECT prid, prname, users.uid '
          . 'FROM project '
          . 'LEFT JOIN users ON project.manager = users.uid '
          . 'WHERE prid <> ? ',

        # _ExistingUnassignedProjectQuery:
        # select all studies that are not in current project
        # and which have not been assigned to any project
        _ExistingUnassignedProjectQuery => 'SELECT stid, description '
          . 'FROM study '
          . 'LEFT JOIN ProjectStudy USING (stid) '
          . 'WHERE ProjectStudy.prid IS NULL '
          . 'GROUP BY stid ',

        # _ExistingStudyQuery:
        # select all studies that are not in current project
        # and which have been assigned to other projects
        _ExistingStudyQuery => 'SELECT prid, stid, description '
          . 'FROM study '
          . 'RIGHT JOIN ProjectStudy USING (stid) '
          . 'WHERE ProjectStudy.prid<>? '
          . 'GROUP BY stid ',

        # _AddExistingStudy: add study to project
        _AddExistingStudy =>
          'INSERT INTO ProjectStudy (prid,stid) VALUES (?, ?);',

        # _RemoveStudy: remove study from project
        _RemoveStudy    => 'DELETE FROM ProjectStudy WHERE prid=? AND stid=?',
        _delete_stid    => '',
        _FieldNames     => '',
        _Data           => '',
        _prid           => undef,
        _prname         => undef,
        _prdesc         => undef,
        _mgr            => undef,
        _userList       => {},
        _unassignedList => {}
    };
    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  loadAllProjects
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Loads all projects
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadAllProjects {
    my $self = shift;

    my $sth = $self->{_dbh}->prepare( $self->{_LoadQuery} )
      or croak $self->{_dbh}->errstr;
    my $rc = $sth->execute()
      or croak $self->{_dbh}->errstr;

    $self->{_FieldNames} = $sth->{NAME};
    $self->{_Data}       = $sth->fetchall_arrayref;
    $sth->finish;
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  loadUserData
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Load data about all users (to be loaded into a popup box)
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadUserData {
    my $self = shift;

    #Temp variables used to create the hash and array for the dropdown.
    my %userList;

    my $sth = $self->{_dbh}->prepare( $self->{_UserQuery} )
      or croak $self->{_dbh}->errstr;
    my $rc = $sth->execute
      or croak $self->{_dbh}->errstr;

    #Grab all users and build the hash and array for drop down.
    my @tempUsers = @{ $sth->fetchall_arrayref };

    foreach (@tempUsers) {

        # id -> name
        $userList{ $_->[0] } = $_->[1];
    }

    #Assign members variables reference to the hash and array.
    $self->{_userList} = \%userList;

    #Finish with database.
    $sth->finish;
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  loadSingleProject
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadSingleProject {

    #Grab object and id from URL.
    my $self = shift;
    $self->{_prid} = $self->{_FormObject}->url_param('id');

    #Run the SQL and get the data into the object.
    my $sth = $self->{_dbh}->prepare( $self->{_LoadSingleQuery} )
      or croak $self->{_dbh}->errstr;
    my $rc = $sth->execute( $self->{_prid} )
      or croak $self->{_dbh}->errstr;

    assert( $rc == 1 );

    #
    # :TODO:05/31/2011 17:19:18:es:
    # Find out an optimal way to fetch single row
    #
    $self->{_Data} = $sth->fetchall_arrayref;

    foreach ( @{ $self->{_Data} } ) {

        # should only execute once
        $self->{_prid}   = $_->[0];
        $self->{_prname} = $_->[1];
        $self->{_prdesc} = $_->[2];
    }

    $sth->finish;
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  loadAllStudiesFromProject
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Loads all studies belonging to a given project
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadAllStudiesFromProject {
    my $self = shift;

    $self->{_StudyRecords} = $self->{_dbh}->prepare( $self->{_StudiesQuery} )
      or croak $self->{_dbh}->errstr;

    $self->{_StudyRecordCount} =
      $self->{_StudyRecords}->execute( $self->{_prid} )
      or croak $self->{_dbh}->errstr;
    $self->{_StudyFieldNames} = $self->{_StudyRecords}->{NAME};
    $self->{_StudyData}       = $self->{_StudyRecords}->fetchall_arrayref;
    $self->{_StudyRecords}->finish;
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  loadFromForm
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Load data from submitted form
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadFromForm {
    my $self = shift;

    $self->{_prid} = ( $self->{_FormObject}->url_param('id') )
      if defined( $self->{_FormObject}->url_param('id') );
    $self->{_prname} = ( $self->{_FormObject}->param('name') )
      if defined( $self->{_FormObject}->param('name') );
    $self->{_prdesc} = ( $self->{_FormObject}->param('description') )
      if defined( $self->{_FormObject}->param('description') );
    $self->{_mgr} = ( $self->{_FormObject}->param('manager') )
      if defined( $self->{_FormObject}->param('manager') );
    $self->{_SelectedProject} = ( $self->{_FormObject}->param('project_exist') )
      if defined( $self->{_FormObject}->param('project_exist') );
    $self->{_SelectedStudy} = ( $self->{_FormObject}->param('study_exist') )
      if defined( $self->{_FormObject}->param('study_exist') );
    $self->{_SelectedStudy} =
      ( $self->{_FormObject}->param('study_exist_unassigned') )
      if defined( $self->{_FormObject}->param('study_exist_unassigned') );
    $self->{_delete_stid} = ( $self->{_FormObject}->url_param('removstid') )
      if defined( $self->{_FormObject}->url_param('removstid') );
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  showProjects
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Draw the javascript and HTML for the project table
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub showProjects {
    my $self         = shift;
    my $error_string = "";

    my $JSProjectList =
        "var JSProjectList =\n" . "{\n"
      . "    caption: \"Showing all Projects\",\n"
      . "    records: ["
      . getJSRecords($self) . "],\n"
      . "    headers: ["
      . getJSHeaders($self) . "]\n" . "};\n";

    print '<font size="5">Manage Projects</font><br /><br />' . "\n";

    print '<h2 name = "caption" id="caption"></h2>' . "\n";
    print
'<div><a id="ProjectTable_astext" onClick = "export_table(JSProjectList)">View as plain text</a></div>'
      . "\n";
    print '<div id="ProjectTable"></div>' . "\n";
    print "<script type=\"text/javascript\">\n";
    print $JSProjectList;

    print getTableInfo( $self->{_FieldNames}, $self->{_FormObject} );
    print getExportTable();
    print getDrawResultsTableJS();

    print "</script>\n";
    print '<br /><h2 name = "Add_Caption" id = "Add_Caption">Add Project</h2>'
      . "\n";

    print $self->{_FormObject}->start_form(
        -method => 'POST',
        -action => $self->{_FormObject}->url( -absolute => 1 )
          . '?a=manageProjects&ManageAction=add',
        -onsubmit => 'return validate_fields(this, [\'name\']);'
      )
      . $self->{_FormObject}->dl(
        $self->{_FormObject}->dt('name'),
        $self->{_FormObject}->dd(
            $self->{_FormObject}
              ->textfield( -name => 'name', -id => 'name', -maxlength => 255 )
        ),
        $self->{_FormObject}->dt('description:'),
        $self->{_FormObject}->dd(
            $self->{_FormObject}->textarea(
                -name      => 'description',
                -id        => 'description',
                -rows      => 8,
                -columns   => 50,
                -maxlength => 1023
            )
        ),
        $self->{_FormObject}->dt('&nbsp;'),
        $self->{_FormObject}->dd(
            $self->{_FormObject}->submit(
                -name  => 'AddProject',
                -id    => 'AddProject',
                -value => 'Add Project'
            ),
            $self->{_FormObject}->span( { -class => 'separator' }, ' / ' )
        )
      ) . $self->{_FormObject}->end_form;
    return;
}

#
#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  getExportTable
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  prints the results table to a printable text screen
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getExportTable {
    return <<"END_EXPORT_TABLE";
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
            d.write(r[i][j] + "\\t");
        }
        d.write("\\n");
    }
    d.write("</pre>");
    d.close();
    w.focus();
}
END_EXPORT_TABLE
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  getDrawResultsTableJS
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  print draw results table in JavaScript
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getDrawResultsTableJS {
    return <<"END_DrawResultsTableJS";
var myDataSource            = new YAHOO.util.DataSource(JSProjectList.records);
myDataSource.responseType   = YAHOO.util.DataSource.TYPE_JSARRAY;
myDataSource.responseSchema = {fields: ["0","1","2","3"]};
var myData_config           = {paginator: new YAHOO.widget.Paginator({rowsPerPage: 50})};
var myDataTable             = new YAHOO.widget.DataTable("ProjectTable", myColumnDefs, myDataSource, myData_config);

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

END_DrawResultsTableJS
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  getJSRecords
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  print Javascript records
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getJSRecords {
    my $self           = shift;
    my $tempRecordList = '';

    #Loop through data and load into JavaScript array.
    #foreach (sort {$a->[3] cmp $b->[3]} @{$self->{_Data}})
    foreach ( @{ $self->{_Data} } ) {
        foreach (@$_) {
            $_ = '' if !defined $_;
            $_ =~ s/"//gx
              ; # strip all double quotes (JSON data are bracketed with double quotes)
        }

        # prid, name, description
        # 0     1     2
        #       ^     ^
        $tempRecordList .= '{0:"'
          . $_->[1] . '",1:"'
          . $_->[2] . '",2:"'
          . $_->[0] . '",3:"'
          . $_->[0] . '"},';
    }
    $tempRecordList =~ s/,\s*$//x;    # strip trailing comma

    return $tempRecordList;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  getJSHeaders
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  print JavaScript headers
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getJSHeaders {
    my $self           = shift;
    my $tempHeaderList = '';

    #Loop through data and load into JavaScript array.
    foreach ( @{ $self->{_FieldNames} } ) {
        $tempHeaderList .= '"' . $_ . '",';
    }
    $tempHeaderList =~ s/,\s*$//x;    # strip trailing comma

    return $tempHeaderList;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  getTableInfo
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  print table information
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getTableInfo {
    my $arrayRef  = shift;
    my @names     = @$arrayRef;
    my $CGIRef    = shift;
    my $deleteURL = $CGIRef->url( absolute => 1 )
      . '?a=manageProjects&ManageAction=delete&id=';
    my $editURL =
      $CGIRef->url( absolute => 1 ) . '?a=manageProjects&ManageAction=edit&id=';

    #This is the code to use the AJAXy update box for description..
    my $postBackURL = '"' . $CGIRef->url( -absolute => 1 ) . '?a=updateCell"';
    my $postBackQueryParametersDesc =
'"type=project&name=" + escape(record.getData("0")) + "&desc=" + escape(newValue) + "&old_name=" + encodeURI(record.getData("0"))';
    my $postBackQueryParametersName =
'"type=project&name=" + escape(newValue) + "&desc=" + escape(record.getData("1")) + "&old_name=" + encodeURI(record.getData("0"))';
    my $textCellEditorObjectDescr =
      SGX::DrawingJavaScript->new( $postBackURL, $postBackQueryParametersDesc );
    my $textCellEditorObjectName =
      SGX::DrawingJavaScript->new( $postBackURL, $postBackQueryParametersName );

    my $name_editor = $textCellEditorObjectName->printTextCellEditorCode();
    my $desc_editor = $textCellEditorObjectDescr->printTextCellEditorCode();
    return <<"END_TableInfo";
YAHOO.widget.DataTable.Formatter.formatProjectDeleteLink = function(elCell, oRecord, oColumn, oData)
{
    elCell.innerHTML = '<a title="Delete Project" target="_self" onClick="return deleteConfirmation();" href="$deleteURL' + oData + '">Delete</a>';
}
YAHOO.widget.DataTable.Formatter.formatProjectEditLink = function(elCell, oRecord, oColumn, oData)
{
    elCell.innerHTML = '<a title="Edit Project" target="_self" href="$editURL' + oData + '">Edit</a>';
}

YAHOO.util.Dom.get("caption").innerHTML = JSProjectList.caption;
var myColumnDefs = [
    {key:"0", sortable:true, resizeable:true, label:"Name", editor:$name_editor},
    {key:"1", sortable:true, resizeable:true,
    label:"Description",editor:$desc_editor},
    {key:"2", sortable:false, resizeable:true, label:"Delete Project",formatter:"formatProjectDeleteLink"},
    {key:"3", sortable:false, resizeable:true, label:"Edit Project",formatter:"formatProjectEditLink"}
];

END_TableInfo
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  insertNewProject
#   PARAMETERS:  ????
#      RETURNS:  Id of the inserted project
#  DESCRIPTION:  Insert new project
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub insertNewProject {
    my $self = shift;

    $self->{_dbh}
      ->do( $self->{_InsertQuery}, undef, $self->{_prname}, $self->{_prdesc},
        $self->{_manager} )
      or croak $self->{_dbh}->errstr;

    #carp "Inserted id: " . $self->{_dbh}->{'mysql_insertid'};
    $self->{_prid} = $self->{_dbh}->{'mysql_insertid'};
    return $self->{_prid};
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  deleteProject
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Deletes a project
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub deleteProject {
    my $self = shift;

    $self->{_dbh}->do( $self->{_DeleteQuery}, undef, $self->{_prid} )
      or croak $self->{_dbh}->errstr;
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  removeStudy
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Remove Study from project
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub removeStudy {
    my $self = shift;

    $self->{_dbh}->do( $self->{_RemoveStudy}, undef, $self->{_prid},
        $self->{_delete_stid} )
      or croak $self->{_dbh}->errstr;
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  editProject
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  edit project
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub editProject {
    my $self = shift;
    print '<font size="5">Editing Project</font><br /><br />' . "\n";

    #Edit existing
    #

    my %userList = %{ $self->{_userList} };
    print $self->{_FormObject}->start_form(
        -method => 'POST',
        -action => $self->{_FormObject}->url( -absolute => 1 )
          . '?a=manageProjects&ManageAction=editSubmit&id='
          . $self->{_prid},
        -onsubmit => 'return validate_fields(this, [\'description\']);'
      )
      . $self->{_FormObject}->dl(
        $self->{_FormObject}->dt('name:'),
        $self->{_FormObject}->dd(
            $self->{_FormObject}->textfield(
                -name      => 'prname',
                -id        => 'prname',
                -maxlength => 255,
                -value     => $self->{_prname}
            )
        ),
        $self->{_FormObject}->dt('description:'),
        $self->{_FormObject}->dd(
            $self->{_FormObject}->textarea(
                -name      => 'prdesc',
                -id        => 'prdesc',
                -maxlength => 1023,
                -rows      => 8,
                -columns   => 50,
                -value     => $self->{_prdesc}
            )
        ),
        $self->{_FormObject}->dt('project manager:'),
        $self->{_FormObject}->dd(
            $self->{_FormObject}->popup_menu(
                -name => 'manager',
                -id   => 'manager',
                -values =>
                  [ sort { $userList{$a} cmp $userList{$b} } keys %userList ],
                -labels  => \%userList,
                -default => $self->{_mgr}
            )
        ),
        $self->{_FormObject}->dt('&nbsp;'),
        $self->{_FormObject}->dd(
            $self->{_FormObject}->submit(
                -name  => 'editSaveProject',
                -id    => 'editSaveProject',
                -value => 'Save Edits'
            ),
            $self->{_FormObject}->span( { -class => 'separator' } )
        )
      );

    print '<div id="StudyTable"></div>', "\n";

    my $JSStudyList_records = getJSStudyRecords($self);
    my $JSStudyList_headers = getJSStudyHeaders($self);
    my $StudyTableInfo      = getStudyTableInfo( $self->{_StudyFieldNames},
        $self->{_FormObject}, $self->{_prid} );
    my $DrawStudyResultsTableJS = getDrawStudyResultsTableJS();

    print <<"END_JSStudyList";
<script type="text/javascript">
var JSStudyList = {
    records: [$JSStudyList_records],
    headers: [$JSStudyList_headers]
};
$StudyTableInfo
$DrawStudyResultsTableJS
</script>
END_JSStudyList

    print $self->{_FormObject}->end_form;

    print '<script src="'
      . $self->{_js_dir}
      . '/AddExisting.js" type="text/javascript"></script>';
    print
'<br /><h2 name = "Add_Caption" id = "Add_Caption">Add Existing Study to this Project</h2>'
      . "\n";

    print
'<br /><h2 name = "Add_Caption1" id = "Add_Caption1">Studies in other projects.</h2>'
      . "\n";

    print "<script>\n";
    print getJavaScriptRecordsForExistingDropDowns($self);
    print "</script>\n";

    print $self->{_FormObject}->start_form(
        -method => 'POST',
        -name   => 'AddExistingForm',
        -action => $self->{_FormObject}->url( -absolute => 1 )
          . '?a=manageProjects&ManageAction=addExisting&id='
          . $self->{_prid},
        -onsubmit => "return validate_fields(this,'');"
      )
      . $self->{_FormObject}->dl(
        $self->{_FormObject}->dt('Project : '),
        $self->{_FormObject}->dd(
            $self->{_FormObject}->popup_menu(
                -name    => 'project_exist',
                -id      => 'project_exist',
                -values  => [],
                -labels  => {},
                -default => $self->{_SelectedProject},
                -onChange =>
"populateSelectExisting(document.getElementById(\"study_exist\"),document.getElementById(\"project_exist\"),project);"
            )
        ),
        $self->{_FormObject}->dt('Study : '),
        $self->{_FormObject}->dd(
            $self->{_FormObject}->popup_menu(
                -name    => 'study_exist',
                -id      => 'study_exist',
                -values  => [],
                -labels  => {},
                -default => $self->{_SelectedStudy}
            )
        ),
        $self->{_FormObject}->dt('&nbsp;'),
        $self->{_FormObject}->dd(
            $self->{_FormObject}->submit(
                -name  => 'AddStudy',
                -id    => 'AddStudy',
                -value => 'Add Study'
            ),
            $self->{_FormObject}->span( { -class => 'separator' }, ' / ' )
        )
      ) . $self->{_FormObject}->end_form;

    #
    print
'<br /><h2 name = "Add_Caption2" id = "Add_Caption2">Studies not in a project.</h2>',
      "\n";

    my %unassignedList = %{ $self->{_unassignedList} };
    print $self->{_FormObject}->start_form(
        -method => 'POST',
        -name   => 'AddExistingUnassignedForm',
        -action => $self->{_FormObject}->url( -absolute => 1 )
          . '?a=manageProjects&ManageAction=addExisting&id='
          . $self->{_prid},
        -onsubmit => "return validate_fields(this,'');"
      )
      . $self->{_FormObject}->dl(
        $self->{_FormObject}->dt('Study : '),
        $self->{_FormObject}->dd(
            $self->{_FormObject}->popup_menu(
                -name   => 'study_exist_unassigned',
                -id     => 'study_exist_unassigned',
                -values => [
                    sort { $unassignedList{$a} cmp $unassignedList{$b} }
                      keys %unassignedList
                ],
                -labels => \%unassignedList
            )
        ),
        $self->{_FormObject}->dt('&nbsp;'),
        $self->{_FormObject}->dd(
            $self->{_FormObject}->submit(
                -name  => 'AddStudy',
                -id    => 'AddStudy',
                -value => 'Add Study'
            ),
            $self->{_FormObject}->span( { -class => 'separator' }, ' / ' )
        )
      ) . $self->{_FormObject}->end_form;
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  getDrawStudyResultsTableJS
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  print draw study results table in Javascript
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getDrawStudyResultsTableJS {
    return <<"END_DrawStudyResultsTableJS"
var myDataSourceExp            = new YAHOO.util.DataSource(JSStudyList.records);
myDataSourceExp.responseType   = YAHOO.util.DataSource.TYPE_JSARRAY;
myDataSourceExp.responseSchema = {fields: ["0","1","2","3","4","5","6"]};
var myData_configExp           = {paginator: new YAHOO.widget.Paginator({rowsPerPage: 50})};
var myDataTableExp             = new YAHOO.widget.DataTable("StudyTable", myStudyColumnDefs, myDataSourceExp, myData_configExp);

END_DrawStudyResultsTableJS
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  addExistingStudy
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Add existing study
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub addExistingStudy {
    my $self = shift;

    my $sth = $self->{_dbh}->prepare( $self->{_AddExistingStudy} )
      or croak $self->{_dbh}->errstr;
    my $rc = $sth->execute( $self->{_prid}, $self->{_SelectedStudy} )
      or croak $self->{_dbh}->errstr;
    $sth->finish();
    return $rc;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  getStudyTableInfo
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  print study table information
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getStudyTableInfo {
    my $arrayRef  = shift;
    my @names     = @$arrayRef;
    my $CGIRef    = shift;
    my $projectID = shift;
    my $deleteURL = $CGIRef->url( absolute => 1 )
      . "?a=manageProjects&ManageAction=deleteStudy&id=$projectID&removstid=";

    return <<"END_StudyTableInfo"
YAHOO.widget.DataTable.Formatter.formatStudyDeleteLink = function(elCell, oRecord, oColumn, oData)
{
    elCell.innerHTML = '<a title="Remove" onClick="return removeStudyConfirmation();" target="_self" href="$deleteURL' + oData + '">Remove</a>';
}

var myStudyColumnDefs = [
    {key:"1", sortable:true, resizeable:true, label:"Study"},
    {key:"2", sortable:true, resizeable:true, label:"Pubmed ID"},
    {key:"3", sortable:true, resizeable:true, label:"Platform"},
    {key:"0", sortable:false, resizeable:true, label:"Remove Study",formatter:"formatStudyDeleteLink"}
];
END_StudyTableInfo
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  getJSStudyRecords
#   PARAMETERS:  ????
#      RETURNS:  JSON string
#  DESCRIPTION:  List studies
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getJSStudyRecords {
    my $self = shift;

    my @records;
    foreach ( @{ $self->{_StudyData} } ) {
        foreach (@$_) {
            $_ = '' if not defined;

            # Because JSON data are bracketed with double quotes, we strip all
            # double quotes we can find.
            $_ =~ s/"//gx;
        }

        # stid, desc, pubmed, platform
        #       ^     ^       ^
        #       1     2       3
        push @records,
            '{0:"'
          . $_->[0] . '",1:"'
          . $_->[1] . '",2:"'
          . $_->[2] . '",3:"'
          . $_->[3] . '"}';
    }
    return join( ',', @records );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  getJSStudyHeaders
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  print Javascript Study Headers
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getJSStudyHeaders {
    my $self = shift;

    my @headers;
    foreach ( @{ $self->{_StudyFieldNames} } ) {
        push @headers, "\"$_\"";
    }
    return join( ',', @headers );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  buildUnassignedStudyDropDown
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  build unassigned study drop down
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub buildUnassignedStudyDropDown {
    my $self = shift;

    my $unassignedDropDown = SGX::DropDownData->new(
        $self->{_dbh},
        $self->{_ExistingUnassignedProjectQuery}
    );

    $self->{_unassignedList} = $unassignedDropDown->loadDropDownValues();
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  getJavaScriptRecordsForExistingDropDowns
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  print JavaScript records for drop down menu showing existing
#                   studies
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getJavaScriptRecordsForExistingDropDowns {
    my $self = shift;

    my $sth = $self->{_dbh}->prepare( $self->{_ExistingProjectQuery} )
      or croak $self->{_dbh}->errstr;
    my $rc = $sth->execute( $self->{_prid} )
      or croak $self->{_dbh}->errstr;

    my @out;

    while ( my @row = $sth->fetchrow_array ) {
        foreach (@row) {
            $_ = '' if not defined;
        }
        push @out, 'project[' . $row[0] . "] = {};";
        push @out,
            'project['
          . $row[0]
          . '][0] = \''
          . $row[1]
          . "';";    # project description
        push @out, 'project[' . $row[0] . "][1] = {};";    # sample 1 name
        push @out, 'project[' . $row[0] . "][2] = {};";    # sample 2 name
        push @out,
          'project[' . $row[0] . '][3] = \'' . $row[2] . "';";    # user id
    }
    $sth->finish;

    # resetting $sth
    $sth = $self->{_dbh}->prepare( $self->{_ExistingStudyQuery} )
      or croak $self->{_dbh}->errstr;
    $rc = $sth->execute( $self->{_prid} )
      or croak $self->{_dbh}->errstr;

    ### populate the Javascript hash with the content of the study recordset
    while ( my @row = $sth->fetchrow_array ) {
        push @out,
          'project[' . $row[0] . '][1][' . $row[1] . '] = \'' . $row[2] . "';";
        push @out,
          'project[' . $row[0] . '][2][' . $row[1] . '] = \'' . $row[3] . "';";
    }
    $sth->finish;

    my $out = join( "\n", @out );

    return <<"END_JavaScriptRecordsForExistingDropDowns"
Event.observe(window, "load", init);
var project = {};
$out;
function init() {
    populateExisting("project_exist", project);
    populateSelectExisting(document.getElementById("study_exist"),document.getElementById("project_exist"), project);
}

END_JavaScriptRecordsForExistingDropDowns
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  editSubmitProject
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Update project description
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub editSubmitProject {
    my $self = shift;

    my $rc =
      $self->{_dbh}
      ->do( $self->{_UpdateQuery}, undef, $self->{_name}, $self->{_prdesc},
        $self->{_manager}, $self->{_prid} )
      or croak $self->{_dbh}->errstr;
    return $rc;
}

1;