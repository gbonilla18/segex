
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

use base qw/SGX::Strategy::CRUD/;

use SGX::Abstract::JSEmitter qw/true false/;
use SGX::Abstract::Exception;
use SGX::Model::ProjectStudyExperiment;

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Override parent constructor; add attributes to object instance
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ( $class, @param ) = @_;

    my $self = $class->SUPER::new(@param);

    $self->_set_attributes(

#_table_defs: hash with keys corresponding to the names of tables handled by this module.
# key: values required for lookup. The first element always corresponds to $self->{_id}.
# mutable: fields that can be modified independently of each other (or other elements).
# proto: fields that are filled out on insert/creation of new records.
        _table_defs => {
            'ProjectStudy' => {
                key     => [qw/prid stid/],
                mutable => [],
                proto   => [qw/prid stid/]
            },
            'project' => {
                key     => [qw/prid/],
                mutable => [qw/prname prdesc/],
                proto   => [qw/prname prdesc manager/],
                indexed => [qw/manager/],
                names   => [qw/prname/],
            },
            'study' => {
                key     => [qw/stid/],
                mutable => [],
                proto   => [],
                indexed => [],
                names   => [qw/description/]
            }
        },
        _default_table => 'project',
        _title         => 'Manage Projects',

        _ProjectStudyExperiment =>
          SGX::Model::ProjectStudyExperiment->new( dbh => $self->{_dbh} ),

        _id                => undef,
        _id_data           => {},
        _Field_IndexToName => undef,
        _data              => undef,
    );

    $self->_register_actions(
        'head' => {
            form_create => 'form_create_head',
            form_assign => 'form_assign_head'
        },
        'body' => {
            form_create => 'form_create_body',
            form_assign => 'form_assign_body'
        }
    );

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  readrow
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub readrow_head {

    my $self = shift;

    $self->_readrow_command()->();

    #  Sets up _Field_SymbolToIndex and _Field_SymbolToName
    $self->_readall_setup(
        stid        => 'No.',
        description => 'Description',
        pubmed      => 'PubMed ID',
        pname       => 'Platform'
    );

    my $table = 'study';

    $self->_readall_command( <<"END_StudiesQuery", $table )->();
INNER JOIN ProjectStudy USING(stid)
LEFT JOIN platform USING(pid)
END_StudiesQuery

    push @{ $self->{_js_src_code} },
      (
        {
            -code =>
              $self->_head_data_table( $table, 'ProjectStudy', 'unassign', 0 )
        }
      );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  readall
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub readall_head {

    my $self = shift;

    my $q = $self->{_cgi};

    # delete 'prid' parameter when it is set to 'all'
    $q->delete('prid')
      if ( defined $q->param('prid') )
      and ( $q->param('prid') eq 'all' );

    $self->_readall_setup(
        prid   => 'No.',
        prname => 'Name',
        prdesc => 'Description',
        uname  => 'Managing User'
    );

    my $table = $self->{_default_table};
    $self->_readall_command( "LEFT JOIN users ON $table.manager = users.uid",
        $table )->();

    push @{ $self->{_js_src_code} },
      ( { -code => $self->_head_data_table( $table, undef, 'delete', 1 ) } );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  form_create
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_create_head {
    my $self = shift;
    return if defined $self->{_id};    # no _id

    return 1;
}

#######################################################################################
#PRINTING HTML AND JAVASCRIPT STUFF
#######################################################################################
sub readall_body {

    # Form HTML for the project table.
    my $self = shift;
    my $q    = $self->{_cgi};

    #---------------------------------------------------------------------------
    #  Project dropdown
    #---------------------------------------------------------------------------
    my $resource_uri = $self->get_resource_uri();
    return $q->h2( $self->{_title} ),
      $self->_body_create_read_menu(
        'read'   => [ undef,         'View Existing' ],
        'create' => [ 'form_create', 'Create New' ]
      ),

    #---------------------------------------------------------------------------
    #  Table showing all projects in all projects
    #---------------------------------------------------------------------------
      $q->h3( { -id => 'caption' }, '' ),
      $q->div(
        $q->a( { -id => $self->{dom_export_link_id} }, 'View as plain text' ) ),
      $q->div( { -id => $self->{dom_table_id} }, '' );
}
#######################################################################################
sub form_create_body {

    my $self = shift;
    my $q    = $self->{_cgi};

    return $q->h2( $self->{_title} ),
      $self->_body_create_read_menu(
        'read'   => [ undef,         'View Existing' ],
        'create' => [ 'form_create', 'Create New' ]
      ),
      $q->h3('Create New Project'),

      # Resource URI: /projects
      $q->start_form(
        -method   => 'POST',
        -action   => $self->get_resource_uri(),
        -onsubmit => 'return validate_fields(this, [\'prname\']);'
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'prname' }, 'Name:' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'prname',
                -id        => 'prname',
                -maxlength => 100,
                -title => 'Enter brief project escription (up to 100 letters)'
            )
        ),
        $q->dt( $q->label( { -for => 'prdesc' }, 'description:' ) ),
        $q->dd(
            $q->textarea(
                -name  => 'prdesc',
                -id    => 'prdesc',
                -title => 'Enter description'
            )
        ),

        $q->dt('&nbsp;'),
        $q->dd(
            $q->hidden( -name => 'b', -value => 'create' ),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Create Project',
                -title => 'Create a new project'
            )
        )
      ),
      $q->end_form;
}

#######################################################################################
sub form_assign_head {
    my $self = shift;
    return if not defined $self->{_id};    # _id must be present
    $self->_readrow_command()->();

    push @{ $self->{_js_src_code} },
      (
        { -src => 'ProjectStudyExperiment.js' },
        {
            -code => $self->get_pse_dropdown_js(
                extra_projects   => { 
                    'all' => { name => '@All Projects' },
                    '' => { name => '@Unassigned Studies' }
                },
                projects         => 1,
                project_by_study => 1,
                studies          => 1
            )
        }
      );

    return 1;
}
#######################################################################################
sub form_assign_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    #---------------------------------------------------------------------------
    #  Form: Assign Study to this Project
    #---------------------------------------------------------------------------

    return $q->h2('Editing Project'),

      $self->_body_create_read_menu(
        'read'   => [ undef,         'Edit Project' ],
        'create' => [ 'form_assign', 'Assign Studies' ]
      ),
      $q->h3('Assign Studies:'),
      $q->dl(
        $q->dt( $q->label( { -for => 'prid' }, 'From project:' ) ),
        $q->dd(
            $q->popup_menu(
                -name   => 'prid',
                -id     => 'prid',
                -title  => qq/Choose a project/,
                -values => [],
                -labels => {}
            )
        )
      ),

      # Resource URI: /projects/id
      $q->start_form(
        -method => 'POST',
        -action => $self->get_resource_uri()
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'stid' }, 'Study:' ) ),
        $q->dd(
            $q->popup_menu(
                -name     => 'stid',
                -id       => 'stid',
                -multiple => 'multiple',
                -title =>
qq/You can select multiple studies here by holding down Control or Command key before clicking./,
                -size   => 7,
                -values => [],
                -labels => {}
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->hidden( -name => 'table', -value => 'ProjectStudy' ),
            $q->hidden( -name => 'b',     -value => 'assign' ),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Assign',
                -title => qq/Assign selected study to this project/
            )
        )
      ),
      $q->end_form;
}
#######################################################################################
sub readrow_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    #---------------------------------------------------------------------------
    #  Form: Set Project Attributes
    #---------------------------------------------------------------------------
    # :TODO:08/11/2011 16:35:27:es:  here breadcrumbs would be useful
    return $q->h2('Editing Project'),

      $self->_body_create_read_menu(
        'read'   => [ undef,         'Edit Project' ],
        'create' => [ 'form_assign', 'Assign Studies' ]
      ),
      $q->h3('Set Project Attributes'),

      # Resource URI: /projects/id
      $q->start_form(
        -method   => 'POST',
        -action   => $self->get_resource_uri(),
        -onsubmit => 'return validate_fields(this, [\'prname\']);'
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'prname' }, 'Project name:' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'prname',
                -id        => 'prname',
                -title     => 'Edit project name',
                -maxlength => 100,
                -value     => $self->{_id_data}->{prname}
            )
        ),
        $q->dt( $q->label( { -for => 'prdesc' }, 'Description:' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'prdesc',
                -id        => 'prdesc',
                -title     => 'Edit to change description',
                -maxlength => 20,
                -value     => $self->{_id_data}->{prdesc}
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->hidden( -name => 'b', -value => 'update' ),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Set Attributes',
                -title => 'Change project attributes'
            )
        )
      ),
      $q->end_form,

    #---------------------------------------------------------------------------
    #  Studies table
    #---------------------------------------------------------------------------
      $q->h3('All Studies in the Project'),
      $q->div(
        $q->a( { -id => $self->{dom_export_link_id} }, 'View as plain text' ) ),
      $q->div( { -style => 'clear:both;', -id => $self->{dom_table_id} } );
}

#######################################################################################
sub get_pse_dropdown_js {
    my ( $self, %args ) = @_;

    my $pse = $self->{_ProjectStudyExperiment};
    $pse->init(
        projects => 1,
        %args
    );

    my $js = SGX::Abstract::JSEmitter->new( pretty => 0 );

    my $q    = $self->{_cgi};
    my $prid = $self->{_id};
    $prid = $q->param('prid') if not defined $prid;

    return $js->bind(
        {
            ProjStudyExp =>
              $self->{_ProjectStudyExperiment}->get_ByProject(),
            currentSelection => {
                'project' => {
                    elementId => 'prid',
                    element   => undef,
                    selected  => ( defined $prid ) ? { $prid => undef } : {}
                },
                (
                    ( $args{projects} )
                    ? (
                        'project' => {
                            elementId => 'prid',
                            element   => undef,
                            selected  => {}
                        }
                      )
                    : ()
                ),
                (
                    ( $args{studies} )
                    ? (
                        'study' => {
                            elementId => 'stid',
                            element   => undef,
                            selected  => {}
                        }
                      )
                    : ()
                )
            }
        },
        declare => 1
      )
      . $js->call(
        'YAHOO.util.Event.addListener',
        [
            sub { 'window' },
            'load',
            $js->lambda(
                $js->call(
                    'populateProject.apply',
                    [ sub { 'currentSelection' } ],
                ),
                (
                    ( $args{projects} && $args{studies} )
                    ? (
                        $js->call(
                            'populateProjectStudy.apply',
                            [ sub { 'currentSelection' } ],
                        )
                      )
                    : ()
                )
            )
        ]
      )
      . (
        ( $args{projects} || $args{studies} )
        ? (
            $js->call(
                'YAHOO.util.Event.addListener',
                [
                    'prid', 'change',
                    $js->lambda(
                        (
                            ( $args{projects} && $args{studies} )
                            ? (
                                $js->call(
                                    'populateProjectStudy.apply',
                                    [ sub { 'currentSelection' } ],
                                )
                              )
                            : ()
                        )
                    )
                ]
              )
          )
        : ''
      )
      . (
        ( $args{projects} && $args{studies} )
        ? (
            $js->call(
                'YAHOO.util.Event.addListener',
                [
                    'prid', 'change',
                    $js->lambda(
                        $js->call(
                            'populateProjectStudy.apply',
                            [ sub { 'currentSelection' } ],
                            void => 1
                        )
                    )
                ],
              )
          )
        : ''
      );
}

1;
