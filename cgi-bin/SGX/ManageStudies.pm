
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

use Carp::Assert;
use SGX::DrawingJavaScript;
use Switch;
use SGX::Abstract::JSEmitter;

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageStudies
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  In Perl, class attributes cannot be inherited, which means we
#                should not use them for anything that is very specific to the
#                problem domain of the given class.
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

        # model
        _PlatformStudyExperiment =>
          SGX::Model::PlatformStudyExperiment->new( dbh => $dbh ),

        _ExpFieldNames      => undef,
        _ExpData            => undef,
        _deleteEid          => undef,
        _FieldNames         => undef,
        _Data               => undef,
        _stid               => undef,
        _description        => undef,
        _pubmed             => undef,
        _pid                => undef,
        _SelectedExperiment => undef
    };

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::ManageStudies
#       METHOD:  dispatch_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  Must not print to browser window
#     SEE ALSO:  n/a
#===============================================================================
sub dispatch_js {

    my ($self) = @_;
    my ( $q,          $s )           = @$self{qw{_cgi _UserSession}};
    my ( $js_src_yui, $js_src_code ) = @$self{qw{_js_src_yui _js_src_code}};

    my $action =
      ( defined $q->param('b') )
      ? $q->param('b')
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
        case 'Create Study' {
            return unless $s->is_authorized('user');
            $self->loadFromForm();
            $self->insertNewStudy();
            $self->redirectInternal(
                '?a=manageStudies&b=edit&id=' . $self->{_stid} );
        }
        case 'Assign Experiment' {
            return unless $s->is_authorized('user');
            $self->loadFromForm();
            $self->addExistingExperiment();
            $self->redirectInternal(
                '?a=manageStudies&b=edit&id=' . $self->{_stid} );
        }
        case 'delete' {
            return unless $s->is_authorized('user');
            $self->loadFromForm();
            $self->deleteStudy();
            $self->redirectInternal('?a=manageStudies');
        }
        case 'deleteExperiment' {
            return unless $s->is_authorized('user');
            $self->loadFromForm();
            $self->removeExperiment();
            $self->redirectInternal(
                '?a=manageStudies&b=edit&id=' . $self->{_stid} );
        }
        case 'Set Attributes' {
            return unless $s->is_authorized('user');
            $self->loadFromForm();
            $self->editSubmitStudy();
            $self->redirectInternal('?a=manageStudies');
        }
        case 'new' {
            return unless $s->is_authorized('user');
            $self->{_PlatformStudyExperiment}->init( platforms => 1 );
            $self->loadFromForm();

            push @$js_src_code,
              (
                +{ -src  => 'PlatformStudyExperiment.js' },
                +{ -code => $self->getJSPlatformDropdown() }
              );
        }
        case 'update' {

            # ajax_update takes care of authorization...
            $self->ajax_update(
                valid_fields => [qw{description pubmed}],
                table        => 'study',
                key          => 'stid'
            );
        }
        case 'edit' {
            return unless $s->is_authorized('user');
            $self->{_PlatformStudyExperiment}->init(
                platforms         => 1,
                platform_by_study => 1,
                studies           => 1,
                experiments       => 1
            );
            $self->loadFromForm();
            $self->loadSingleStudy();
            $self->loadAllExperimentsFromStudy();

            push @$js_src_code,
              (
                +{ -src  => 'PlatformStudyExperiment.js' },
                +{ -code => $self->getJSPlatformStudyExperimentDropdown() },
                +{ -code => $self->editStudy_js() }
              );
        }
        else {

            # default: show all studies or studies for a specific platform
            return unless $s->is_authorized('user');
            $self->{_PlatformStudyExperiment}->init( platforms => 1 );
            $self->loadFromForm();
            $self->loadAllStudies();

            push @$js_src_code,
              (
                +{ -src  => 'CellUpdater.js' },
                +{ -src  => 'PlatformStudyExperiment.js' },
                +{ -code => $self->getJSPlatformDropdown() },
                +{ -code => $self->showStudies_js() }
              );
        }
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageStudies
#       METHOD:  dispatch
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Dispatches actions sent to ManageStudies
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
            print $self->editStudy();
        }
        case 'new' {
            print $self->form_createStudy();
        }
        else {

            # default action: show Manage Studies main form
            print $self->showStudies();
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
#######################################################################################
sub loadAllStudies {
    my $self = shift;

    my $dbh = $self->{_dbh};

    my $predicate    = '';
    my @query_params = ();
    if ( defined( $self->{_pid} ) && $self->{_pid} ne '' ) {
        $predicate = 'WHERE platform.pid=?';
        push @query_params, $self->{_pid};
    }

    my $query = <<"END_loadAllStudies";
SELECT 
    stid,
    description,
    pubmed,
    platform.pid,
    platform.pname,
    platform.species 
FROM study 
INNER JOIN platform USING(pid)
$predicate
GROUP BY stid
END_loadAllStudies

    my $sth = $dbh->prepare($query);
    my $rc  = $sth->execute(@query_params);
    $self->{_FieldNames} = $sth->{NAME};
    $self->{_Data}       = $sth->fetchall_arrayref;
    $sth->finish;

    return 1;
}

#######################################################################################
sub loadSingleStudy {

    #Grab object and id from URL.
    my $self = shift;

    my $dbh = $self->{_dbh};

    my $stid = $self->{_stid};

    #Run the SQL and get the data into the object.
    my $sth = $dbh->prepare(<<"END_loadSingleStudy");
SELECT 
    stid,
    description,
    pubmed,
    platform.pid,
    platform.pname,
    platform.species 
FROM study 
INNER JOIN platform USING(pid) 
WHERE stid=? 
GROUP BY stid
END_loadSingleStudy
    my $rc = $sth->execute($stid);
    $self->{_Data} = $sth->fetchall_arrayref;

    foreach ( @{ $self->{_Data} } ) {
        $self->{_description} = $_->[1];
        $self->{_pubmed}      = $_->[2];
        $self->{_pid}         = $_->[3];
    }

    $sth->finish;
    return 1;
}

#######################################################################################
#Loads all expriments from a specific study.
sub loadAllExperimentsFromStudy {
    my $self = shift;

    my $dbh = $self->{_dbh};

    my $sth = $dbh->prepare(<<"END_ExperimentsQuery");
SELECT 
    experiment.eid,
    study.pid,
    experiment.sample1,
    experiment.sample2,
    COUNT(1),
    ExperimentDescription,
    AdditionalInformation,
    study.description,
    platform.pname
FROM experiment 
NATURAL JOIN StudyExperiment
NATURAL JOIN study
INNER JOIN platform ON platform.pid = study.pid
LEFT JOIN microarray ON microarray.eid = experiment.eid
WHERE study.stid = ?
GROUP BY experiment.eid
ORDER BY experiment.eid ASC
END_ExperimentsQuery

    my $rc = $sth->execute( $self->{_stid} );
    $self->{_ExpFieldNames} = $sth->{NAME};
    $self->{_ExpData}       = $sth->fetchall_arrayref;
    $sth->finish;
    return 1;
}

#######################################################################################
#Load the data from the submitted form.
sub loadFromForm {
    my $self = shift;

    my $q = $self->{_cgi};

    # id is always a URL parameter
    my $stid = $q->url_param('id');
    if ( defined $stid ) {
        $self->{_stid} = $stid;

        # If a study is set, use the corresponding platform while ignoring the
        # platform parameter. Also update the _pid field with the platform id
        # obtained from the lookup by study id.
        my $pid;
        if ( $self->{_PlatformStudyExperiment} ) {
            $pid =
              $self->{_PlatformStudyExperiment}->getPlatformFromStudy($stid);
        }
        $self->{_pid} = ( defined $pid ) ? $pid : $q->param('pid');
    }

    $self->{_description}        = $q->param('description');
    $self->{_pubmed}             = $q->param('pubmed');
    $self->{_pid}                = $q->param('pid');
    $self->{_SelectedExperiment} = $q->param('eid');

    # first try to get from POST, then from the URL
    $self->{_deleteEid} = $q->param('removeid');
    $self->{_deleteEid} = $q->url_param('removeid')
      if not defined $self->{_deleteEid};

    return 1;
}

#######################################################################################
#PRINTING HTML AND JAVASCRIPT STUFF
#######################################################################################
sub showStudies_js {

    # Form Javascript for the study table.
    my $self = shift;

    my $js = SGX::Abstract::JSEmitter->new( pretty => 1 );

    return $js->define(
        {
            JSStudyList => {
                caption => 'Showing all Studies',
                records => $self->getJSRecords(),
                headers => $self->getJSHeaders()
            }
        },
        declare => 1
    ) . $self->getTableInformation();
}

#######################################################################################
sub showStudies {

    # Form HTML for the study table.
    my $self = shift;
    my $q    = $self->{_cgi};

    #---------------------------------------------------------------------------
    #  Platform dropdown
    #---------------------------------------------------------------------------
    return $q->h2('Manage Studies'),

      # Resource URI: /manageStudies
      $q->start_form(
        -method => 'POST',
        -action => $q->url( -absolute => 1 ) . '?a=manageStudies'
      ),
      $q->dl(
        $q->dt('Platform:'),
        $q->dd(
            $q->popup_menu(
                -name => 'pid',
                -id   => 'pid'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'b',
                -class => 'css3button',
                -value => 'Load from Platform'
            )
        )
      ),
      $q->end_form,

    #---------------------------------------------------------------------------
    #  Table showing all studies in all platforms
    #---------------------------------------------------------------------------
      $q->h3( { -id => 'caption' }, '' ),
      $q->div( $q->a( { -id => 'StudyTable_astext' }, 'View as plain text' ) ),
      $q->div( { -id => 'StudyTable' }, '' );
}
#######################################################################################
sub form_createStudy {

    my $self = shift;
    my $q    = $self->{_cgi};

    return
      $q->h3('Create New Study'),

      # Resource URI: /manageStudies
      $q->start_form(
        -method   => 'POST',
        -action   => $q->url( -absolute => 1 ) . '?a=manageStudies',
        -onsubmit => 'return validate_fields(this, [\'description\']);'
      ),
      $q->dl(
        $q->dt('description:'),
        $q->dd(
            $q->textfield(
                -name      => 'description',
                -id        => 'description',
                -maxlength => 100
            )
        ),
        $q->dt('pubmed:'),
        $q->dd(
            $q->textfield(
                -name      => 'pubmed',
                -id        => 'pubmed',
                -maxlength => 20
            )
        ),
        $q->dt('platform:'),
        $q->dd(
            $q->popup_menu(
                -name => 'pid',
                -id   => 'pid'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'b',
                -class => 'css3button',
                -value => 'Create Study'
            )
        )
      ),
      $q->end_form;
}

#######################################################################################
sub getJSRecords {
    my $self = shift;

    # declare data sources and options
    my $data     = $self->{_Data};          # data source
    my @columns  = ( 1, 2, 4, 5, 0, 0 );    # columns to include in output
    my $sort_col = 3;                       # column to sort on

    #stid,description,pubmed,platform.pid,platform.pname,platform.species

    # :TODO:08/02/2011 01:15:25:es: the body of this function (containing the
    # loop) is relatively generic -- see also getJSExperimentRecords() method in
    # this class.  Can abstract out the body into a function called
    # encodeColumns() or something similar.

    my @tmp;
    foreach my $row ( sort { $a->[$sort_col] cmp $b->[$sort_col] } @$data ) {
        my $i = 0;
        push @tmp, +{ map { $i++ => $_ } @$row[@columns] };
    }
    return \@tmp;
}

#######################################################################################
sub getJSHeaders {
    my $self = shift;
    return $self->{_FieldNames};
}

#######################################################################################
sub getTableInformation {
    my $self = shift;

    #my $arrayRef = $self->{_FieldNames};
    #my @names     = @$arrayRef;

    my $q = $self->{_cgi};

    my $url_prefix = $q->url( -absolute => 1 );
    my $deleteURL  = $url_prefix . '?a=manageStudies&b=delete&id=';
    my $editURL    = $url_prefix . '?a=manageStudies&b=edit&id=';

    return <<"END_TableInformation";
function createExperimentCellUpdater(field) {
    /*
     * this functions makes a hammer after it first builds a factory in the
     * neighborhood that makes hammers using the hammer construction factory
     * spec sheet in CellUpdater.js 
     */
    return createCellUpdater(field, "$url_prefix?a=manageStudies", "4");
}
YAHOO.util.Event.addListener("StudyTable_astext", "click", export_table, JSStudyList, true);
YAHOO.util.Event.addListener(window, 'load', function() {
    YAHOO.widget.DataTable.Formatter.formatStudyDeleteLink = function(elCell, oRecord, oColumn, oData) 
    {
        elCell.innerHTML = '<a title="Delete Study" target="_self" onclick="return deleteConfirmation();" href="$deleteURL' + oData + '">Delete</a>';
    }
    YAHOO.widget.DataTable.Formatter.formatStudyEditLink = function(elCell, oRecord, oColumn, oData) 
    {
        elCell.innerHTML = '<a title="Edit Study" target="_self" href="$editURL' + oData + '">Edit</a>';
    }
    
    var myColumnDefs = [
        {key:"0", sortable:true, resizeable:true, label:"Description", editor:createExperimentCellUpdater("description")},
        {key:"1", sortable:true, resizeable:true, label:"PubMed", editor:createExperimentCellUpdater("pubmed")},
        {key:"2", sortable:true, resizeable:true, label:"Platform"}, 
        {key:"3", sortable:true, resizeable:true, label:"Species"},
        {key:"4", sortable:false, resizeable:true, label:"Delete Study",formatter:"formatStudyDeleteLink"},
        {key:"5", sortable:false, resizeable:true, label:"Edit Study",formatter:"formatStudyEditLink"}
    ];

    var myDataSource         = new YAHOO.util.DataSource(JSStudyList.records);
    myDataSource.responseType     = YAHOO.util.DataSource.TYPE_JSARRAY;
    myDataSource.responseSchema     = {fields: ["0","1","2","3","4","5"]};
    var myData_config         = {paginator: new YAHOO.widget.Paginator({rowsPerPage: 50})};
    var myDataTable         = new YAHOO.widget.DataTable("StudyTable", myColumnDefs, myDataSource, myData_config);

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
END_TableInformation
}

#######################################################################################
#ADD/DELETE/EDIT METHODS
#######################################################################################
sub insertNewStudy {
    my $self = shift;

    my $dbh = $self->{_dbh};
    my $sth = $dbh->prepare(
        'INSERT INTO study (description, pubmed, pid) VALUES (?, ?, ?)');
    my $rc =
      $sth->execute( $self->{_description}, $self->{_pubmed}, $self->{_pid} );
    $sth->finish;
    $self->{_stid} = $dbh->{mysql_insertid};
    return 1;
}

#######################################################################################
sub deleteStudy {
    my $self = shift;

    # :TODO:08/01/2011 17:07:09:es: ON DELETE CASCADE should remove the need to
    # delete from StudyExperiment.
    my $dbh = $self->{_dbh};
    my @deleteStatements = map { $dbh->prepare($_) } (
        'DELETE FROM StudyExperiment WHERE stid=?',
        'DELETE FROM study WHERE stid=?'
    );

    foreach my $sth (@deleteStatements) {
        $sth->execute( $self->{_stid} );
        $sth->finish;
    }
    return 1;
}

#######################################################################################
sub removeExperiment {
    my $self = shift;

    my $dbh = $self->{_dbh};

    my $sth =
      $dbh->prepare('DELETE FROM StudyExperiment WHERE stid=? AND eid=?');
    my $rc = $sth->execute( $self->{_stid}, $self->{_deleteEid} );
    $sth->finish;
    assert( $rc == 1 );
    return 1;
}

#######################################################################################
sub editStudy_js {
    my $self = shift;

    my $js = SGX::Abstract::JSEmitter->new( pretty => 1 );
    return $js->define(
        {
            JSExperimentList => {
                records => $self->getJSExperimentRecords(),
                headers => $self->getJSExperimentHeaders()
            }
        },
        declare => 1
    ) . $self->getExperimentTableInformation();

}
#######################################################################################
sub editStudy {
    my $self = shift;
    my $q    = $self->{_cgi};

    #---------------------------------------------------------------------------
    #  Form: Set Study Attributes
    #---------------------------------------------------------------------------
    return $q->h2('Editing Study'), $q->h3('Set Study Attributes'),

      $q->dl(
        $q->dt( $q->label( { -for => 'platform' }, 'platform:' ) ),
        $q->dd(
            $q->popup_menu(
                -name     => 'pid',
                -id       => 'pid',
                -disabled => 'disabled'
            )
        )
      ),

      # Resource URI: /manageStudies/id
      $q->start_form(
        -method => 'POST',
        -action => $q->url( -absolute => 1 )
          . '?a=manageStudies&id='
          . $self->{_stid},
        -onsubmit => 'return validate_fields(this, [\'description\']);'
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'description' }, 'description:' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'description',
                -id        => 'description',
                -maxlength => 100,
                -value     => $self->{_description}
            )
        ),
        $q->dt( $q->label( { -for => 'pubmed' }, 'pubmed:' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'pubmed',
                -id        => 'pubmed',
                -maxlength => 20,
                -value     => $self->{_pubmed}
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'b',
                -class => 'css3button',
                -value => 'Set Attributes'
            )
        )
      ),
      $q->end_form,

    #---------------------------------------------------------------------------
    #  Form: Assign Experiment to this Study
    #---------------------------------------------------------------------------
      $q->h3('Assign Experiment to this Study'),
      $q->dl(
        $q->dt( $q->label( { -for => 'stid' }, 'Study:' ) ),
        $q->dd(
            $q->popup_menu(
                -name   => 'stid',
                -id     => 'stid',
                -values => [],
                -labels => {}
            )
        )
      ),

      # Resource URI: /manageStudies/id
      $q->start_form(
        -method => 'POST',
        -action => $q->url( -absolute => 1 )
          . '?a=manageStudies&id='
          . $self->{_stid}
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'eid' }, 'Experiment:' ) ),
        $q->dd(
            $q->popup_menu(
                -name   => 'eid',
                -id     => 'eid',
                -values => [],
                -labels => {}
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'b',
                -class => 'css3button',
                -value => 'Assign Experiment'
            )
        )
      ),
      $q->end_form,

    #---------------------------------------------------------------------------
    #  Experiments table
    #---------------------------------------------------------------------------
      $q->h3('Showing Experiments in this Study'),
      $q->div( { -style => 'clear:both;', -id => 'ExperimentTable' } );
}

#######################################################################################
sub addExistingExperiment {
    my $self = shift;

    my $dbh = $self->{_dbh};

    my $sth =
      $dbh->prepare('INSERT INTO StudyExperiment (eid, stid) VALUES (?,?)');

    my $rc = $sth->execute( $self->{_SelectedExperiment}, $self->{_stid} );
    $sth->finish;
    assert( $rc == 1 );

    return 1;
}

#######################################################################################
sub getExperimentTableInformation {
    my $self = shift;

    #my $arrayRef = $self->{_ExpFieldNames};
    #my @names    = @$arrayRef;
    my $q    = $self->{_cgi};
    my $stid = $self->{_stid};

    my $deleteURL = $q->url( absolute => 1 )
      . "?a=manageStudies&b=deleteExperiment&id=$stid&removeid=";

    return <<"END_ExperimentTableInformation";
YAHOO.widget.DataTable.Formatter.formatExperimentDeleteLink = function(elCell, oRecord, oColumn, oData) 
{
    elCell.innerHTML = '<a title="Remove" onclick="return deleteConfirmation({itemName: \\\'experiment\\\'});" target="_self" href="$deleteURL' + oData + '">Remove</a>';
};

var myExperimentColumnDefs = [
    {key:"3", sortable:true, resizeable:true, label:"Experiment Number"},
    {key:"0", sortable:true, resizeable:true, label:"Sample 1"},
    {key:"1", sortable:true, resizeable:true, label:"Sample 2"},
    {key:"2", sortable:true, resizeable:true, label:"Probe Count"},
    {key:"5", sortable:false, resizeable:true, label:"Experiment Description"},
    {key:"6", sortable:false, resizeable:true, label:"Additional Information"},
    {key:"3", sortable:false, resizeable:true, label:"Remove Experiment",formatter:"formatExperimentDeleteLink"}
];

YAHOO.util.Event.addListener(window, 'load', function(){
    var myDataSourceExp            = new YAHOO.util.DataSource(JSExperimentList.records);
    myDataSourceExp.responseType   = YAHOO.util.DataSource.TYPE_JSARRAY;
    myDataSourceExp.responseSchema = {fields: ["0","1","2","3","4","5","6"]};
    var myData_configExp           = {paginator: new YAHOO.widget.Paginator({rowsPerPage: 50})};
    var myDataTableExp             = new YAHOO.widget.DataTable("ExperimentTable", myExperimentColumnDefs, myDataSourceExp, myData_configExp);
});
END_ExperimentTableInformation
}

#######################################################################################
sub getJSExperimentRecords {

    #Print the Java Script records for the experiment.
    my $self = shift;

    my $data     = $self->{_ExpData};          # data source
    my @columns  = ( 2, 3, 4, 0, 0, 5, 6 );    # columns to include in output
    my $sort_col = 3;                          # column to sort on

    #eid,pid,sample1,sample2,count(1),ExperimentDescription,AdditionalInfo

    # :TODO:08/02/2011 01:15:25:es: the body of this function (containing the
    # loop) is relatively generic -- see also getJSRecords() method in this
    # class.  Can abstract out the body into a function called encodeColumns()
    # or something similar.

    my @tmp;
    foreach my $row (@$data) {
        my $i = 0;
        push @tmp, +{ map { $i++ => $_ } @$row[@columns] };
    }
    return \@tmp;
}

#######################################################################################
sub getJSExperimentHeaders {
    my $self = shift;
    return $self->{_ExpFieldNames};
}
#######################################################################################
sub getJSPlatformDropdown {
    my $self = shift;

    my $js = SGX::Abstract::JSEmitter->new( pretty => 1 );

    my $pid = $self->{_pid};

    return $js->define(
        {
            PlatfStudyExp =>
              $self->{_PlatformStudyExperiment}->get_ByPlatform(),
            currentSelection => {
                'platform' => {
                    element   => undef,
                    selected  => ( defined $pid ) ? { $pid => undef } : {},
                    elementId => 'pid'
                }
            }
        },
        declare => 1
    ) . <<"END_ret";
YAHOO.util.Event.addListener(window, 'load', function() {
    populatePlatform.apply(currentSelection);
});
END_ret
}
#######################################################################################
sub getJSPlatformStudyExperimentDropdown {
    my $self = shift;

    my $js = SGX::Abstract::JSEmitter->new( pretty => 1 );

    my $pid  = $self->{_pid};
    my $stid = $self->{_stid};

    return $js->define(
        {
            PlatfStudyExp =>
              $self->{_PlatformStudyExperiment}->get_ByPlatform(),
            currentSelection => {
                'platform' => {
                    element   => undef,
                    selected  => ( defined $pid ) ? { $pid => undef } : {},
                    elementId => 'pid'
                },
                'study' => {
                    element   => undef,
                    selected  => ( defined $stid ) ? { $stid => undef } : {},
                    elementId => 'stid'
                },
                'experiment' => {
                    element   => undef,
                    selected  => {},
                    elementId => 'eid'
                }
            }
        },
        declare => 1
    ) . <<"END_ret";
YAHOO.util.Event.addListener(window, 'load', function() {
    populatePlatform.apply(currentSelection);
    populatePlatformStudy.apply(currentSelection);
    populateStudyExperiment.apply(currentSelection);
});
YAHOO.util.Event.addListener('pid', 'change', function() {
    populatePlatformStudy.apply(currentSelection);
    populateStudyExperiment.apply(currentSelection);
});
YAHOO.util.Event.addListener('stid', 'change', function() {
    populateStudyExperiment.apply(currentSelection);
});
END_ret
}

#######################################################################################
sub editSubmitStudy {
    my $self = shift;

    my $dbh = $self->{_dbh};
    my $sth =
      $dbh->prepare('UPDATE study SET description=?, pubmed=? WHERE stid=?');
    my $rc =
      $sth->execute( $self->{_description}, $self->{_pubmed}, $self->{_stid} );
    $sth->finish;
    assert( $rc == 1 );

    return 1;
}

1;
