
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

use SGX::Debug;
use SGX::DropDownData;
use SGX::Abstract::Exception;
use SGX::Abstract::JSEmitter;

use Switch;
use Data::Dumper;

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
    my ( $class, %param ) = @_;

    my ( $dbh, $q, $s, $js_src_yui, $js_src_code ) =
      @param{qw{dbh cgi user_session js_src_yui js_src_code}};

    my $self = {
        _dbh         => $dbh,
        _cgi         => $q,
        _UserSession => $s,
        _js_src_yui  => $js_src_yui,
        _js_src_code => $js_src_code,

        _StudyFieldNames => undef,
        _StudyData       => undef,
        _SelectedStudy   => undef,
        _SelectedProject => undef,
        _delete_stid     => undef,
        _FieldNames      => undef,
        _Data            => undef,
        _prid            => undef,
        _prname          => undef,
        _prdesc          => undef,
        _mgr             => undef,
        _userList        => undef,
        _unassignedList  => undef
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
    my ($self) = @_;

    my $q = $self->{_cgi};
    my $action =
      ( defined $q->param('b') )
      ? $q->param('b')
      : '';

    switch ($action) {
        case 'edit' {
            print $self->editProject();
        }
        else {

            # default action: show Manage Projects main form
            print $self->showProjects();
        }
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::ManageProjects
#       METHOD:  dispatch_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  No printing to browser window done here
#     SEE ALSO:  n/a
#===============================================================================
sub dispatch_js {

    my ($self) = @_;
    my ( $q,          $s )           = @$self{qw{_cgi _UserSession}};
    my ( $js_src_yui, $js_src_code ) = @$self{qw{_js_src_yui _js_src_code}};

    my $action =
      ( defined $self->{_cgi}->param('b') )
      ? $self->{_cgi}->param('b')
      : '';

    push @$js_src_yui,
      (
        'yahoo-dom-event/yahoo-dom-event.js', 'connection/connection-min.js',
        'dragdrop/dragdrop-min.js',           'container/container-min.js',
        'element/element-min.js',             'datasource/datasource-min.js',
        'paginator/paginator-min.js',         'datatable/datatable-min.js',
        'selector/selector-min.js'
      );

    switch ($action) {
        case 'add' {
            return unless $s->is_authorized('user');
            $self->loadFromForm();
            $self->insertNewProject();
            $self->redirectInternal(
                '?a=manageProjects&b=edit&id=' . $self->{_prid} );
        }
        case 'addExisting' {
            return unless $s->is_authorized('user');
            $self->loadFromForm();

     # :TODO:07/08/2011 13:02:50:es: adding existing study should be done in the
     # section of the controller that deals with model (dispatch_js), not the
     # section that deals with the view (this one).
     # TRY:
            my $record_count = eval { $self->addExistingStudy() } || 0;
            my $msg = $q->p("$record_count record(s) added. ");

            # CATCH:
            if ( my $exception = $@ ) {
                if ( $exception->isa('Exception::Class::DBI::STH') ) {

# :TODO:07/08/2011 13:00:37:es:
# :TRICKY:07/08/2011 13:00:29:es:
#  Throwing descriptive errors from DBI may be insecure. Consider throwing
#  custon SGX::Abstract::Exception::User instead when no records where inserted.
# only catching statement errors. Typical error: duplicate
# record is being inserted.
                    $msg .= $q->pre( $exception->error );
                }
                else {

                    # unexpected error: rethrow
                    $exception->throw();
                }
            }
            $self->redirectInternal(
                '?a=manageProjects&b=edit&id=' . $self->{_prid} );
        }
        case 'delete' {
            return unless $s->is_authorized('user');
            $self->loadFromForm();
            $self->deleteProject();
            $self->redirectInternal('?a=manageProjects');
        }
        case 'deleteStudy' {
            return unless $s->is_authorized('user');
            $self->loadFromForm();
            $self->removeStudy();
            $self->redirectInternal(
                '?a=manageProjects&b=edit&id=' . $self->{_prid} );
        }
        case 'editSubmit' {
            return unless $s->is_authorized('user');
            $self->loadFromForm();
            $self->editSubmitProject();
            $self->redirectInternal('?a=manageProjects');
        }
        case 'edit' {
            return unless $s->is_authorized('user');
            $self->loadSingleProject();
            $self->loadUserData();
            $self->loadAllStudiesFromProject();
            $self->buildUnassignedStudyDropDown();

            push @$js_src_code,
              (
                +{ -src  => 'AddExisting.js' },
                +{ -code => $self->editProject_js() }
              );
        }
        case 'update' {

            # ajax_update takes care of authorization...
            $self->ajax_update(
                valid_fields => [qw{prname prdesc}],
                table        => 'project',
                key          => 'prid'
            );
        }
        else {

            # default action: load all projects
            return unless $s->is_authorized('user');
            $self->loadFromForm();
            $self->loadAllProjects();
            push @$js_src_code,
              (
                +{ -src  => 'CellUpdater.js' },
                +{ -code => $self->showProjects_js() }
              );
        }
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  ajax_update
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Update part of CRUD operations. This is a *very generic* method
#                handling AJAX request -- basically update a key-value pair in a
#                specified row in the table.
#       THROWS:  no exceptions
#     COMMENTS:  :TODO:07/04/2011 16:48:45:es: Abstract out this method into a
#                base class for SGX modules.
#                :TODO:07/28/2011 00:38:55:es: Abstract out the model part of
#                this method into the model composable of the abstract class.
#     SEE ALSO:  n/a
#===============================================================================
sub ajax_update {

    my ( $self, %args ) = @_;

    my ( $dbh, $q, $s ) = @$self{qw{_dbh _cgi _UserSession}};

    my $valid_fields = $args{valid_fields};
    my $table        = $args{table};
    my $column       = $args{key};

    my %is_valid_field = map { $_ => 1 } @$valid_fields;

    if ( !$s->is_authorized('user') ) {

        # Send 401 Unauthorized header
        print $q->header( -status => 401 );
        $s->commit;    # must commit session before exit
        exit(0);
    }
    my $field = $q->param('field');
    if ( !defined($field) || $field eq '' || !$is_valid_field{$field} ) {

        # Send 400 Bad Request header
        print $q->header( -status => 400 );
        $s->commit;    # must commit session before exit
        exit(0);
    }

    # after field name has been checked against %valid_fields hash, it
    # is safe to fill it in directly:
    my $query = "update $table set $field=? where $column=?";

    # :TODO:07/27/2011 23:42:00:es: implement transactional updates. Separate
    # statement preparation from execution.

    # Note that when $q->param('value') is undefined, DBI should fill in
    # NULL into the corresponding placeholder.
    my $rc =
      eval { $dbh->do( $query, undef, $q->param('value'), $q->param('id') ); }
      || 0;

    if ( $rc > 0 ) {

        # Normal condition -- at least some rows were updated:
        # Send 200 OK header
        print $q->header( -status => 200 );
        $s->commit;    # must commit session before exit
        exit(1);
    }
    elsif ( my $exception = $@ ) {

        # Error condition -- no rows updated:
        # Send 400 Bad Request header
        print $q->header( -status => 400 );
        $s->commit;    # must commit session before exit
        $exception->throw();
    }
    else {

        # Normal condition -- no rows updated:
        # Send 404 Not Found header
        print $q->header( -status => 404 );
        $s->commit;    # must commit session before exit
        exit(0);
    }
    $s->commit;        # must commit session before exit
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  redirectInternal
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub redirectInternal {
    my ( $self, $query ) = @_;
    my ( $q,    $s )     = @$self{qw{_cgi _UserSession}};

    # redirect if we know where to... will send a redirect header, so
    # commit the session to data store now
    my $redirectURI =
      ( defined $q->url_param('destination') )
      ? $q->url( -base     => 1 ) . uri_unescape( $q->url_param('destination') )
      : $q->url( -absolute => 1 ) . $query;

    $s->commit();
    print $q->redirect(
        -uri    => $redirectURI,
        -status => 302,                 # 302 Found
        -cookie => $s->cookie_array()
    );
    return 1;
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
sub editProject_js {
    my $self = shift;

    my $q         = $self->{_cgi};
    my $prid      = $self->{_prid};
    my $deleteURL = $q->url( absolute => 1 )
      . "?a=manageProjects&b=deleteStudy&id=$prid&removstid=";

    my $js = SGX::Abstract::JSEmitter->new( pretty => 1 );
    return $js->define(
        {
            project     => $self->getJSRecordsForExistingDropDowns(),
            JSStudyList => {
                headers => $self->getJSStudyHeaders(),
                records => $self->getJSStudyRecords()
            }
        },
        declare => 1
    ) . <<"END_JSStudyList";

YAHOO.util.Event.addListener(window, 'load', function() {
    YAHOO.widget.DataTable.Formatter.formatStudyDeleteLink = function(elCell, oRecord, oColumn, oData)
    {
        elCell.innerHTML = '<a title="Remove" target="_self" href="$deleteURL' + oData + '">Remove</a>';
    }
    var myStudyColumnDefs = [
        {key:"1", sortable:true, resizeable:true, label:"Study"},
        {key:"2", sortable:true, resizeable:true, label:"Pubmed ID"},
        {key:"3", sortable:true, resizeable:true, label:"Platform"},
        {key:"0",sortable:false,resizeable:true,label:"Remove Study",formatter:"formatStudyDeleteLink"}
    ];
    var myDataSourceExp            = new YAHOO.util.DataSource(JSStudyList.records);
    myDataSourceExp.responseType   = YAHOO.util.DataSource.TYPE_JSARRAY;
    myDataSourceExp.responseSchema = {fields: ["0","1","2","3","4","5","6"]};
    var myData_configExp           = {paginator: new YAHOO.widget.Paginator({rowsPerPage: 50})};
    var myDataTableExp             = new YAHOO.widget.DataTable("StudyTable", myStudyColumnDefs, myDataSourceExp, myData_configExp);

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
    my $dbh  = $self->{_dbh};

    # _LoadQuery: show all projects
    my $sth = $dbh->prepare(<<"END_LoadQuery");
SELECT prid, prname, prdesc, users.uname as mgr_name
FROM project
LEFT JOIN users ON project.manager = users.uid
END_LoadQuery

    my $rc = $sth->execute();

    #$self->{_FieldNames} = $sth->{NAME};
    # only first two columns will be used for plain-text export
    $self->{_FieldNames} = [ 'Name', 'Description' ];
    $self->{_Data} = $sth->fetchall_arrayref;
    $sth->finish;
    return 1;
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

    my $q = $self->{_cgi};

    my $url_prefix = $q->url( absolute => 1 );
    my $deleteURL  = "$url_prefix?a=manageProjects&b=delete&id=";
    my $editURL    = "$url_prefix?a=manageProjects&b=edit&id=";

    my $js = SGX::Abstract::JSEmitter->new( pretty => 1 );
    return $js->define(
        {
            JSProjectList => {
                caption => 'Showing all Projects',
                records => $self->getJSRecords(),
                headers => $self->getJSHeaders()
            }
        },
        declare => 1
    ) . <<"END_ShowProjectsJS";
YAHOO.util.Event.addListener("ProjectTable_astext", "click", export_table, JSProjectList, true);
YAHOO.util.Event.addListener(window, "load", function() {
    function createExperimentCellUpdater(field) {
        /*
         * this functions makes a hammer after it first builds a factory in the
         * neighborhood that makes hammers using the hammer construction factory
         * spec sheet in CellUpdater.js 
         */
        return createCellUpdater(field, "$url_prefix?a=manageProjects", "2");
    }
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
        {key:"0", sortable:true, resizeable:true, label:JSProjectList.headers[0], editor:createExperimentCellUpdater("prname")},
        {key:"1", sortable:true, resizeable:true, label:JSProjectList.headers[1], editor:createExperimentCellUpdater("prdesc")},
        {key:"2", sortable:false, resizeable:true, label:"Delete Project",formatter:"formatProjectDeleteLink"},
        {key:"3", sortable:false, resizeable:true, label:"Edit Project",formatter:"formatProjectEditLink"}
    ];

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
    my $dbh  = $self->{_dbh};

    # _UserQuery: load all users
    my $sth = $dbh->prepare(<<"END_UserQuery");
SELECT uid, CONCAT(uname, ' \\\\ ', full_name) 
FROM users 
WHERE email_confirmed
END_UserQuery
    my $rc = $sth->execute;

    #Grab all users and build the hash and array for drop down.
    my $tempUsers = $sth->fetchall_arrayref;
    $sth->finish;

    #Assign members variables reference to the hash and array.
    # id -> name
    $self->{_userList} = +{ map { $_->[0] => $_->[1] } @$tempUsers };

    return $rc;
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
    my $dbh  = $self->{_dbh};
    my $q    = $self->{_cgi};

    # first try to get project id from the POST parameters, second from URL
    $self->{_prid} = $q->param('id');
    $self->{_prid} = $q->url_param('id') if not defined $self->{_prid};

    #Run the SQL and get the data into the object.

    # _LoadSingleQuery: show single project
    my $sth = $dbh->prepare(<<"END_LoadSingleQuery");
SELECT prid, prname, prdesc 
FROM project 
WHERE prid=?
END_LoadSingleQuery

    my $rc = $sth->execute( $self->{_prid} );

    if ( $rc < 1 ) {
        SGX::Abstract::Exception::User->throw(
            error => "No project found with id = $self->{_prid}\n" );
    }
    elsif ( $rc > 1 ) {
        SGX::Abstract::Exception::Internal->throw(
            error => "Cannot have $rc projects sharing the same id.\n" );
    }

    #
    # :TODO:05/31/2011 17:19:18:es: find out an optimal way to fetch single row
    #
    $self->{_Data} = $sth->fetchall_arrayref;

    ( $self->{_prid}, $self->{_prname}, $self->{_prdesc} ) =
      @{ $self->{_Data}->[0] };

    $sth->finish;
    return $rc;
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
    my $dbh  = $self->{_dbh};

    # _StudiesQuery: select (and describe by platform) all studies that are
    # a part of the given project
    my $sth = $dbh->prepare(<<"END_StudiesQuery");
SELECT study.stid AS stid,
       study.description AS study_desc,
       study.pubmed AS pubmed,
       platform.pname
FROM study
RIGHT JOIN ProjectStudy USING (stid)
LEFT JOIN platform USING (pid)
WHERE ProjectStudy.prid = ?
END_StudiesQuery

    my $rc = $sth->execute( $self->{_prid} );
    $self->{_StudyFieldNames} = $sth->{NAME};
    $self->{_StudyData}       = $sth->fetchall_arrayref;
    $sth->finish;
    return $rc;
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

    my $q = $self->{_cgi};

    # first try to get project id from POST parameter, second from the URL
    $self->{_prid} = $q->param('id');
    $self->{_prid} = $q->url_param('id') if not defined $self->{_prid};

    $self->{_prname}          = $q->param('name');
    $self->{_prdesc}          = $q->param('description');
    $self->{_mgr}             = $q->param('manager');
    $self->{_SelectedProject} = $q->param('project_exist');

    #assert( not defined( $q->param('study_exist_unassigned') ) );
    $self->{_SelectedStudy} = $q->param('study_exist');

    #assert( not defined( $q->param('study_exist') ) );
    $self->{_SelectedStudy} = $q->param('study_exist_unassigned');

    # first try to get stid from POST parameter, second from the URL
    $self->{_delete_stid} = $q->param('removstid');
    $self->{_delete_stid} = $q->url_param('removstid')
      if not defined $self->{_delete_stid};
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  showProjects
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Creates Manage Projects form
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub showProjects {
    my $self       = shift;
    my $q          = $self->{_cgi};
    my $url_prefix = $q->url( -absolute => 1 );

    return $q->h2('Manage Projects'), $q->h3( { -id => 'caption' }, '' ),
      $q->div(
        $q->a( { -id => 'ProjectTable_astext' }, 'View as plain text' ) ),
      $q->div( { -id => 'ProjectTable' }, '' ),
      $q->h3( { -id => 'Add_Caption' }, 'Add Project' ),
      $q->start_form(
        -method   => 'POST',
        -action   => "$url_prefix?a=manageProjects&b=add",
        -onsubmit => 'return validate_fields(this, ["name"]);'
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'name' }, 'Name:' ) ),
        $q->dd(
            $q->textfield( -name => 'name', -id => 'name', -maxlength => 255 )
        ),
        $q->dt( $q->label( { -for => 'description' }, 'Description:' ) ),
        $q->dd(
            $q->textarea(
                -name    => 'description',
                -id      => 'description',
                -rows    => 8,
                -columns => 50
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'AddProject',
                -id    => 'AddProject',
                -class => 'button black bigrounded',
                -value => 'Add Project'
            )
        )
      ),
      $q->end_form;
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
    my $self = shift;

    my $data = $self->{_Data};       # data source
    my @columns = ( 1, 2, 0, 0 );    # columns to include in output

    my @tmp;
    foreach my $row (@$data) {
        my $i = 0;
        push @tmp, +{ map { $i++ => $_ } @$row[@columns] };
    }
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
    my $self = shift;

    return $self->{_FieldNames};
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
    my $dbh  = $self->{_dbh};

    # _InsertQuery: insert into project (what about ProjectStudy?)
    my $sth = $dbh->prepare(<<"END_InsertQuery");
INSERT INTO project 
(prname, prdesc, manager) 
VALUES (?, ?, ?)
END_InsertQuery

    $sth->execute( $self->{_prname}, $self->{_prdesc}, $self->{_manager} );
    $sth->finish;

    $self->{_prid} = $dbh->{mysql_insertid};

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
    my $dbh  = $self->{_dbh};

    # _DeleteQuery: delete from both ProjectStudy and project
    my $sth = $dbh->prepare(<<"END_DeleteQuery");
DELETE FROM project 
WHERE prid=?
END_DeleteQuery

    my $rc = $sth->execute( $self->{_prid} );
    $sth->finish;
    return $rc;
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
    my $dbh  = $self->{_dbh};

    # _RemoveStudy: remove study from project
    my $sth = $dbh->prepare(<<"END_RemoveStudy");
DELETE FROM ProjectStudy 
WHERE prid=? AND stid=?
END_RemoveStudy

    my $rc = $sth->execute( $self->{_prid}, $self->{_delete_stid} );
    $sth->finish;
    return $rc;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  editProject
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Creates Edit Project form
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub editProject {
    my $self = shift;

    my $q = $self->{_cgi};

 # :TODO:08/02/2011 13:44:46:es:  there shouldn't bet two forms for assigned and
 # unassigned studies... Everything should be in the same form aka ManageStudies
 #
    my $editSubmit =
        $q->url( -absolute => 1 )
      . '?a=manageProjects&b=editSubmit&id='
      . $self->{_prid};

    my $addExisting =
        $q->url( -absolute => 1 )
      . '?a=manageProjects&b=addExisting&id='
      . $self->{_prid};

    return $q->h2('Editing Project'),
      $q->start_form(
        -method   => 'POST',
        -action   => $editSubmit,
        -onsubmit => 'return validate_fields(this, [\'description\']);'
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'name' }, 'Name:' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'name',
                -id        => 'name',
                -maxlength => 255,
                -value     => $self->{_prname}
            )
        ),
        $q->dt( $q->label( { -for => 'description' }, 'Description:' ) ),
        $q->dd(
            $q->textarea(
                -name    => 'description',
                -id      => 'description',
                -rows    => 8,
                -columns => 50,
                -value   => $self->{_prdesc}
            )
        ),
        $q->dt( $q->label( { -for => 'manager' }, 'Managing User:' ) ),
        $q->dd(
            $q->popup_menu(
                -name    => 'manager',
                -id      => 'manager',
                -values  => [ keys %{ $self->{_userList} } ],
                -labels  => $self->{_userList},
                -default => $self->{_mgr}
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'editSaveProject',
                -id    => 'editSaveProject',
                -class => 'button black bigrounded',
                -value => 'Save Edits'
            )
        )
      ),
      $q->div(
        {
            -style => 'clear:both;',
            -id    => 'StudyTable',
            -class => 'clearfix'
        },
        ''
      ),
      $q->end_form,

      $q->h2('Add Existing Study to this Project'),

      $q->h3('Studies in other projects'),

      $q->start_form(
        -method   => 'POST',
        -name     => 'AddExistingForm',
        -action   => $addExisting,
        -onsubmit => "return validate_fields(this,'');"
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'project_exist' }, 'Project:' ) ),
        $q->dd(
            $q->popup_menu(
                -name   => 'project_exist',
                -id     => 'project_exist',
                -values => [],
                -labels => {}
            )
        ),
        $q->dt( $q->label( { -for => 'study_exist' }, 'Study:' ) ),
        $q->dd(
            $q->popup_menu(
                -name   => 'study_exist',
                -id     => 'study_exist',
                -values => [],
                -labels => {}
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'AddExistingStudy',
                -id    => 'AddExistingStudy',
                -value => 'Add Study',
                -class => 'button black bigrounded'
            )
        )
      ),
      $q->end_form, $q->h3('Studies not in a project'),
      $q->start_form(
        -method   => 'POST',
        -name     => 'AddExistingUnassignedForm',
        -action   => $addExisting,
        -onsubmit => "return validate_fields(this,'');"
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'study_exist_unassigned' }, 'Study:' ) ),
        $q->dd(
            $q->popup_menu(
                -name   => 'study_exist_unassigned',
                -id     => 'study_exist_unassigned',
                -values => [ keys %{ $self->{_unassignedList} } ],
                -labels => $self->{_unassignedList}
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'AddUnassignedStudy',
                -id    => 'AddUnassignedStudy',
                -class => 'button black bigrounded',
                -value => 'Add Study'
            )
        )
      ),
      $q->end_form;
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

    # _AddExistingStudy: add study to project
    my $sth = $dbh->prepare(<<"END_AddExistingStudy");
INSERT INTO ProjectStudy
(prid,stid)
VALUES (?, ?)
END_AddExistingStudy

    my $rc = $sth->execute( $self->{_prid}, $self->{_SelectedStudy} );
    $sth->finish();
    if ( $rc != 1 ) {

        # Failure to insert a row (when $rc == 0) will be caught by
        # Exception::Class::DBI::STH handler. In case that fails, or in the
        # crazy case where no primary key was defined in the database, we throw
        # an exception here signaling an internal error:
        SGX::Abstract::Exception::Internal->throw(
            error => "$rc records were modified though one was expected\n" );
    }
    return $rc;
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

    my $data = $self->{_StudyData};    # data source
    my @columns = ( 0, 1, 2, 3 );      # columns to include in output

    my @tmp;
    foreach my $row (@$data) {
        my $i = 0;
        push @tmp, +{ map { $i++ => $_ } @$row[@columns] };
    }
    return \@tmp;
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

    # _UnassignedProjectQuery: select all studies that are not in current
    # project and which have not been assigned to any project
    my $sql = <<"END_UnassignedProjectQuery";
SELECT stid, description
FROM study
LEFT JOIN ProjectStudy USING (stid)
WHERE ProjectStudy.prid IS NULL
GROUP BY stid
END_UnassignedProjectQuery

 # :TODO:08/03/2011 10:17:28:es: Rely on PlatformStudyExperiment for a similar
 # hierarchy
    my $unassignedDropDown =
      SGX::DropDownData->new( $self->{_dbh}, $sql );

    $self->{_unassignedList} = $unassignedDropDown->loadDropDownValues();
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  getJSRecordsForExistingDropDowns
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  print JavaScript records for drop down menu showing existing
#                   studies
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getJSRecordsForExistingDropDowns {
    my $self = shift;
    my $dbh  = $self->{_dbh};

    # _ExistingProjectQuery: select all projects that are not current project
    my $sth = $dbh->prepare(<<"END_ExistingProjectQuery");
SELECT prid, prname
FROM project
WHERE prid <> ?
END_ExistingProjectQuery
    my $rc = $sth->execute( $self->{_prid} );

    my %out;
    while ( my @row = $sth->fetchrow_array ) {
        $out{ $row[0] } = [ $row[1], {} ];
    }
    $sth->finish;

    # resetting $sth

    # _ExistingStudyQuery: select all studies that are not in current
    # project and which have been assigned to other projects
    $sth = $dbh->prepare(<<"END_ExistingStudyQuery");
SELECT prid, stid, description
FROM study
INNER JOIN ProjectStudy USING (stid)
WHERE ProjectStudy.prid <> ?
GROUP BY stid
END_ExistingStudyQuery

    $rc = $sth->execute( $self->{_prid} );

    ### populate the Javascript hash with the content of the study recordset
    while ( my @row = $sth->fetchrow_array ) {
        $out{ $row[0] }->[1]->{ $row[1] } = $row[2];
    }
    $sth->finish;

    return \%out;
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
    my $dbh  = $self->{_dbh};

    # _UpdateQuery: update project description
    my $sth = $dbh->prepare(<<"END_UpdateQuery");
UPDATE project 
SET prname=?, prdesc=?, manager=? 
WHERE prid=?
END_UpdateQuery

    my $rc = $sth->execute(
        $self->{_prname},  $self->{_prdesc},
        $self->{_manager}, $self->{_prid}
    );
    $sth->finish;
    return $rc;
}

1;
