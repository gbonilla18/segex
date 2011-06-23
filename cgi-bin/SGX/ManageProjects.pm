
=head1 NAME

SGX::ManageProjects

=head1 SYNOPSIS

=head1 DESCRIPTION
Grouping of functions for managing projects.

=head1 AUTHORS
Eugene Scherba
Michael McDuffie

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
use SGX::Exceptions;
use Switch;
use Data::Dumper;
use JSON::XS;

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
    my ($class, $dbh, $cgi) = @_;

    my $self = {
        _dbh    => $dbh,
        _cgi    => $cgi,

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

        # _StudiesQuery: select (and describe by platform) all studies that are
        # a part of the given project

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
        _ExistingProjectQuery => 'SELECT prid, prname '
          . 'FROM project '
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
          . 'INNER JOIN ProjectStudy USING (stid) '
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
#       METHOD:  dispatch
#   PARAMETERS:  $self, actionName
#      RETURNS:  ????
#  DESCRIPTION:  executes appropriate method for the given action
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub dispatch {
    my ( $self, $action ) = @_;

    my $q = $self->{_cgi};
    $action = '' if not defined($action);
    switch ($action) {
        case 'add' {
            $self->loadFromForm();
            $self->insertNewProject();
            print 'Record added. Redirecting...';
        }
        case 'addExisting' {
            $self->loadFromForm();
            my $record_count = eval { $self->addExistingStudy() } || 0;
            my $msg = $q->p(
                ($record_count) ? 'Record added. ' : 'No records added. '
            );
            if ($@) {
                my $exception = SGX::Exception::Insert->caught();
                if ($exception) {
                    # only catching insertion errors
                    $msg .= $q->pre($exception->errstr);
                } else {
                    # rethrow
                    croak $@;
                }
            }
            print $msg . $q->p('Redirecting...');
        }
        case 'delete' {
            $self->loadFromForm();
            $self->deleteProject();
            print 'Record deleted. Redirecting...';
        }
        case 'deleteStudy' {
            $self->loadFromForm();
            $self->removeStudy();
            print 'Record removed. Redirecting...';
        }
        case 'edit' {
            $self->editProject();
        }
        case 'editSubmit' {
            $self->loadFromForm();
            $self->editSubmitProject();
            print "Record updated. Redirecting...";
        }
        case 'load' {
            $self->loadFromForm();
            $self->showProjects();
        }
        case '' {
            # default action: show Manage Projects main form
            $self->showProjects();
        }
        else {
            croak "Unknown action $action";
        }
    }
    if ( $action eq 'delete' || $action eq 'editSubmit' ) {
        my $redirectURI =
          $self->{_cgi}->url( -absolute => 1 ) . '?a=manageProjects';
        my $redirectString =
"<script type=\"text/javascript\">window.location = \"$redirectURI\"</script>";
        print "$redirectString";
    }
    elsif ($action eq 'add'
        || $action eq 'addExisting'
        || $action eq 'deleteStudy' )
    {
        my $redirectURI =
            $self->{_cgi}->url( -absolute => 1 ) . '?a=manageProjects&ManageAction=edit&id=' . $self->{_prid};
        my $redirectString =
"<script type=\"text/javascript\">window.location = \"$redirectURI\"</script>";
        print "$redirectString";
    }
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::ManageProjects
#       METHOD:  dispatch_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub dispatch_js
{
    # No printing to browser window done here
    my ( $self, $js_ref ) = @_;

    my $action = $self->{_cgi}->param('ManageAction');
    $action = '' if not defined($action);

    switch ($action) {
        case 'edit' {
            # method calls below moved here from dispatch()
            $self->loadSingleProject();
            $self->loadUserData();
            $self->loadAllStudiesFromProject();
            $self->buildUnassignedStudyDropDown();

            push @$js_ref,
                {-src=>'AddExisting.js'};
            push @$js_ref,
                {-code=>$self->editProject_js()};
        }
        case 'load' {
            $self->loadAllProjects();
            my $code = $self->showProjects_js();
            push @$js_ref, {-code=>$self->showProjects_js()};
        }
        case '' {
            $self->loadAllProjects();
            my $code = $self->showProjects_js();
            push @$js_ref, {-code=>$self->showProjects_js()};
        }
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::ManageProjects
#       METHOD:  editProject_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub editProject_js
{
    my $self = shift;
    my $JSRecordsForExistingDropDowns =
        $self->getJavaScriptRecordsForExistingDropDowns();
    my $JSStudyList = encode_json({
        headers => $self->getJSStudyHeaders(),
        records => $self->getJSStudyRecords()
    });
    my $StudyTableInfo = getStudyTableInfo( $self->{_StudyFieldNames},
        $self->{_cgi}, $self->{_prid} );
    my $DrawStudyResultsTableJS = getDrawStudyResultsTableJS();

    return <<"END_JSStudyList";
var project = $JSRecordsForExistingDropDowns;
YAHOO.util.Event.addListener(window, 'load', function() {
    var JSStudyList = $JSStudyList;
    $StudyTableInfo
    $DrawStudyResultsTableJS
    populateExisting(document.getElementById("project_exist"), project);
    populateSelectExisting(document.getElementById("study_exist"),document.getElementById("project_exist"), project);
});
YAHOO.util.Event.addListener(["project_exist"], 'change', function() {
    populateSelectExisting(document.getElementById("study_exist"),document.getElementById("project_exist"), project);
});
END_JSStudyList
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
#        CLASS:  SGX::ManageProjects
#       METHOD:  showProjects_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub showProjects_js {
    my $self = shift;
    my $JSProjectList = encode_json({
        caption => 'Showing all Projects',
        records => $self->getJSRecords(),
        headers => $self->getJSHeaders()
    });

    my $JSTableInfo = $self->getTableInfo();
    my $JSExportTable = getExportTable();
    my $JSResultsTable = getDrawResultsTableJS();

    return <<"END_ShowProjectsJS";
var JSProjectList = $JSProjectList;
$JSExportTable
YAHOO.util.Event.addListener(window, "load", function() {
    $JSTableInfo
    $JSResultsTable
});
END_ShowProjectsJS
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

    my $sth = $self->{_dbh}->prepare( $self->{_UserQuery} )
      or croak $self->{_dbh}->errstr;
    my $rc = $sth->execute
      or croak $self->{_dbh}->errstr;

    #Grab all users and build the hash and array for drop down.
    my @tempUsers = @{ $sth->fetchall_arrayref };

    # id -> name
    my %userList = map { $_->[0] => $_->[1] } @tempUsers;

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
    $self->{_prid} = $self->{_cgi}->url_param('id');

    #Run the SQL and get the data into the object.
    my $sth = $self->{_dbh}->prepare( $self->{_LoadSingleQuery} )
      or croak $self->{_dbh}->errstr;
    my $rc = $sth->execute( $self->{_prid} )
      or croak $self->{_dbh}->errstr;

    if ( $rc < 1 ) {
        croak "No project found with id = $self->{_prid}";
    } elsif ( $rc > 1) {
        croak "Internal error: Cannot have $rc projects sharing the same id.";
    }

    #
    # :TODO:05/31/2011 17:19:18:es: find out an optimal way to fetch single row
    #
    $self->{_Data} = $sth->fetchall_arrayref;

    ($self->{_prid}, $self->{_prname}, $self->{_prdesc}) = 
        @{ $self->{_Data}->[0] };

    #foreach ( @{ $self->{_Data} } ) {
    #    # should only execute once
    #    $self->{_prid}   = $_->[0];
    #    $self->{_prname} = $_->[1];
    #    $self->{_prdesc} = $_->[2];
    #}

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

    if ( defined( $self->{_cgi}->url_param('id') ) ) {
        $self->{_prid} = $self->{_cgi}->url_param('id');
    }
    if ( defined( $self->{_cgi}->param('name') ) ) {
        $self->{_prname} = $self->{_cgi}->param('name');
    }
    if ( defined( $self->{_cgi}->param('description') ) ) {
        $self->{_prdesc} = $self->{_cgi}->param('description');
    }
    if ( defined( $self->{_cgi}->param('manager') ) ) {
        $self->{_mgr} = $self->{_cgi}->param('manager');
    }
    if ( defined( $self->{_cgi}->param('project_exist') ) ) {
        $self->{_SelectedProject} = $self->{_cgi}->param('project_exist');
    }
    if ( defined( $self->{_cgi}->param('study_exist') ) ) {
        assert( not defined( $self->{_cgi}->param('study_exist_unassigned') ) );
        $self->{_SelectedStudy} = $self->{_cgi}->param('study_exist');
    }
    if ( defined( $self->{_cgi}->param('study_exist_unassigned') ) ) {
        assert( not defined( $self->{_cgi}->param('study_exist') ) );
        $self->{_SelectedStudy} =
          $self->{_cgi}->param('study_exist_unassigned');
    }
    if ( defined( $self->{_cgi}->url_param('removstid') ) ) {
        $self->{_delete_stid} = $self->{_cgi}->url_param('removstid');
    }
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

    print '<h2>Manage Projects</h2>' . "\n";
    print '<h3 id="caption"></h3>' . "\n";
    print '<div><a id="ProjectTable_astext" onclick="export_table(JSProjectList)">View as
plain text</a></div>' . "\n";
    print '<div id="ProjectTable"></div>' . "\n";

    print '<h3 id = "Add_Caption">Add Project</h3>' . "\n";

    print $self->{_cgi}->start_form(
        -method => 'POST',
        -action => $self->{_cgi}->url( -absolute => 1 )
          . '?a=manageProjects&ManageAction=add',
        -onsubmit => 'return validate_fields(this, [\'name\']);'
      )
      . $self->{_cgi}->dl(
        $self->{_cgi}->dt($self->{_cgi}->label({-for=>'name'},'Name:')),
        $self->{_cgi}->dd(
            $self->{_cgi}
              ->textfield( -name => 'name', -id => 'name', -maxlength => 255 )
        ),
        $self->{_cgi}->dt($self->{_cgi}->label({-for=>'description'},'Description:')),
        $self->{_cgi}->dd(
            $self->{_cgi}->textarea(
                -name      => 'description',
                -id        => 'description',
                -rows      => 8,
                -columns   => 50
            )
        ),
        $self->{_cgi}->dt('&nbsp;'),
        $self->{_cgi}->dd(
            $self->{_cgi}->submit(
                -name  => 'AddProject',
                -id    => 'AddProject',
                -class => 'css3button',
                -value => 'Add Project'
            )
        )
      ) . $self->{_cgi}->end_form;
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

    #Loop through data and load into JavaScript array.
    #foreach (sort {$a->[3] cmp $b->[3]} @{$self->{_Data}})

    #my $tempRecordList = '';
    
    my @tmp;
    foreach ( @{ $self->{_Data} } ) {
        push @tmp, {
            0 => $_->[1],
            1 => $_->[2],
            2 => $_->[0],
            3 => $_->[0]
        };

        #foreach (@$_) {
        #    $_ = '' if !defined $_;
        #    $_ =~ s/"//gx
        #      ; # strip all double quotes (JSON data are bracketed with double quotes)
        #}
        ## prid, name, description
        ## 0     1     2
        ##       ^     ^
        #$tempRecordList .= '{0:"' . $_->[1] . '",1:"' . $_->[2] . '",2:"' . $_->[0] . '",3:"' . $_->[0] . '"},';
    }
    #$tempRecordList =~ s/,\s*$//;    # strip trailing comma
    #return $tempRecordList;
    return \@tmp;
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
    #my $tempHeaderList = '';

    #Loop through data and load into JavaScript array.
    #foreach ( @{ $self->{_FieldNames} } ) {
    #    $tempHeaderList .= '"' . $_ . '",';
    #}
    #$tempHeaderList =~ s/,\s*$//;    # strip trailing comma

    #return $tempHeaderList;
    return $self->{_FieldNames};
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
    my $self = shift;

    my $uri_prefix = $self->{_cgi}->url( absolute => 1 );
    my $deleteURL = "$uri_prefix?a=manageProjects&ManageAction=delete&id=";
    my $editURL = "$uri_prefix?a=manageProjects&ManageAction=edit&id=";

    #This is the code to use the AJAXy update box for description..
    my $postBackURL = "'$uri_prefix?a=updateCell'";
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
    elCell.innerHTML = '<a title="Delete Project" target="_self" onclick="return deleteConfirmation();" href="$deleteURL' + oData + '">Delete</a>';
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

    $self->{_dbh}->do( 
        $self->{_InsertQuery}, 
        undef, 
        $self->{_prname}, 
        $self->{_prdesc},
        $self->{_manager} 
    )
      or croak $self->{_dbh}->errstr;

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

    my $q = $self->{_cgi};

    print
      $q->h2('Editing Project'), 
      $q->start_form(
        -method => 'POST',
        -action => $q->url( -absolute => 1 )
          . '?a=manageProjects&ManageAction=editSubmit&id='
          . $self->{_prid},
        -onsubmit => 'return validate_fields(this, [\'description\']);'
      )
      . $q->dl(
        $q->dt($q->label({-for=>'name'},'Name:')),
        $q->dd(
            $q->textfield(
                -name      => 'name',
                -id        => 'name',
                -maxlength => 255,
                -value     => $self->{_prname}
            )
        ),
        $q->dt($q->label({-for=>'description'},'Description:')),
        $q->dd(
            $q->textarea(
                -name      => 'description',
                -id        => 'description',
                -rows      => 8,
                -columns   => 50,
                -value     => $self->{_prdesc}
            )
        ),
        $q->dt($q->label({-for=>'manager'},'Managing User:')),
        $q->dd(
            $q->popup_menu(
                -name => 'manager',
                -id   => 'manager',
                -values => [ keys %{ $self->{_userList} }],
                -labels  => $self->{_userList},
                -default => $self->{_mgr}
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'editSaveProject',
                -id    => 'editSaveProject',
                -class => 'css3button',
                -value => 'Save Edits'
            )
        )
      ),
      $q->div({-style=>'clear:both;',-id=>'StudyTable',
              -class=>'clearfix'},'');

    print $q->end_form;
    print $q->br(), $q->br();

    print $q->h2('Add Existing Study to this Project'),
          $q->h3('Studies in other projects');

    print $q->start_form(
        -method => 'POST',
        -name   => 'AddExistingForm',
        -action => $q->url( -absolute => 1 )
          . '?a=manageProjects&ManageAction=addExisting&id='
          . $self->{_prid},
        -onsubmit => "return validate_fields(this,'');"
      )
      . $q->dl(
        $q->dt($q->label({-for=>'project_exist'},'Project:')),
        $q->dd(
            $q->popup_menu(
                -name    => 'project_exist',
                -id      => 'project_exist',
                -values  => [],
                -labels  => {}
            )
        ),
        $q->dt($q->label({-for=>'study_exist'},'Study:')),
        $q->dd(
            $q->popup_menu(
                -name    => 'study_exist',
                -id      => 'study_exist',
                -values  => [],
                -labels  => {}
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'AddExistingStudy',
                -id    => 'AddExistingStudy',
                -value => 'Add Study',
                -class => 'css3button'
            )
        )
      ) . $q->end_form;

    print $q->h3('Studies not in a project');

    my %unassignedList = %{ $self->{_unassignedList} };
    print $q->start_form(
        -method => 'POST',
        -name   => 'AddExistingUnassignedForm',
        -action => $q->url( -absolute => 1 )
          . '?a=manageProjects&ManageAction=addExisting&id='
          . $self->{_prid},
        -onsubmit => "return validate_fields(this,'');"
      )
      . $q->dl(
        $q->dt($q->label({-for=>'study_exist_unassigned'},'Study:')),
        $q->dd(
            $q->popup_menu(
                -name   => 'study_exist_unassigned',
                -id     => 'study_exist_unassigned',
                -values => [keys %{$self->{_unassignedList}} ],
                -labels => $self->{_unassignedList}
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'AddUnassignedStudy',
                -id    => 'AddUnassignedStudy',
                -class => 'css3button',
                -value => 'Add Study'
            )
        )
      ) . $q->end_form;
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
#       THROWS:  
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub addExistingStudy {
    my $self = shift;

    my $dbh = $self->{_dbh};
    my $sth = $dbh->prepare( $self->{_AddExistingStudy} )
        or SGX::Exception::Prepare->throw( errstr => $dbh->errstr );
    my $rc = $sth->execute( $self->{_prid}, $self->{_SelectedStudy} )
        or SGX::Exception::Insert->throw( errstr => $dbh->errstr );
    $sth->finish();
    if ($rc != 1) {
        SGX::Exception::Internal->throw( 
            errstr => "$rc records were modified though one was expected"
        );
    }
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
    elCell.innerHTML = '<a title="Remove" target="_self" href="$deleteURL' + oData + '">Remove</a>';
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
        #foreach (@$_) {
        #    $_ = '' if not defined;

        #    # Because JSON data are bracketed with double quotes, we strip all
        #    # double quotes we can find.
        #    $_ =~ s/"//gx;
        #}

        # stid, desc, pubmed, platform
        #       ^     ^       ^
        #       1     2       3
        #push @records, '{0:"' . $_->[0] . '",1:"' . $_->[1] . '",2:"' . $_->[2] . '",3:"' . $_->[3] . '"}';
        push @records, {
            0 => $_->[0],
            1 => $_->[1],
            2 => $_->[2],
            3 => $_->[3],
        };
    }
    #return join( ',', @records );
    return \@records;
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

    #my @headers;
    #foreach ( @{ $self->{_StudyFieldNames} } ) {
    #    push @headers, "\"$_\"";
    #}
    #return join( ',', @headers );
    return $self->{_StudyFieldNames};
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

    my $unassignedDropDown =
      SGX::DropDownData->new( $self->{_dbh},
        $self->{_ExistingUnassignedProjectQuery} );

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

    #my @out;

    my %out;
    while ( my @row = $sth->fetchrow_array ) {
        #foreach (@row) {
        #    $_ = '' if not defined;
        #}
        $out{$row[0]} = [$row[1], {}];
        #push @out, "project[ $row[0] ] = {};";
        #push @out, "project[ $row[0] ][0] = '$row[1]';";    # project description
        #push @out, "project[ $row[0] ][1] = {};";    # sample 1 name
        #push @out, "project[ $row[0] ][2] = {};";    # sample 2 name
        #push @out, "project[ $row[0] ][3] = '$row[2]';";    # user id
    }
    $sth->finish;

    # resetting $sth
    $sth = $self->{_dbh}->prepare( $self->{_ExistingStudyQuery} )
      or croak $self->{_dbh}->errstr;
    $rc = $sth->execute( $self->{_prid} )
      or croak $self->{_dbh}->errstr;

    ### populate the Javascript hash with the content of the study recordset
    while ( my @row = $sth->fetchrow_array ) {
        #warn Dumper(\@row);
        #push @out, "project[ $row[0] ][1][ $row[1] ] = '$row[2]';";
        $out{$row[0]}->[1]->{$row[1]} = $row[2];
    }
    $sth->finish;

    #my $out = join( "\n", @out );
    return encode_json(\%out);
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
      $self->{_dbh} ->do( 
          $self->{_UpdateQuery}, 
          undef, 
          $self->{_prname}, 
          $self->{_prdesc},
          $self->{_manager}, 
          $self->{_prid}
      )
      or croak $self->{_dbh}->errstr;
    return $rc;
}

1;
