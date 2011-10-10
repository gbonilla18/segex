
=head1 NAME

SGX::ManageUsers

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

package SGX::ManageUsers;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use SGX::Abstract::JSEmitter qw/true false/;
use SGX::Abstract::Exception;

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
            'users' => {
                key       => [qw/uid/],
                selectors => [qw/uname/],
                proto =>
                  [qw/uname full_name address phone level email_confirmed/],
                view =>
                  [qw/uname full_name address phone level email_confirmed/],
                mutable  => [qw/uname full_name address phone level/],
                resource => 'users',
                names    => [qw/uname/],
                labels   => {
                    uid             => 'ID',
                    uname           => 'Login ID',
                    full_name       => 'Full Name',
                    address         => 'Address',
                    phone           => 'Phone',
                    level           => 'Permissions',
                    email_confirmed => 'Email Confirmed'
                }
            }
        },
        _default_table     => 'users',
        _title             => 'Manage Users',
        _id                => undef,
        _id_data           => {},
        _Field_IndexToName => undef,
        _data              => undef,
    );

    $self->_register_actions(
        'head' => { form_create => 'form_create_head' },
        'body' => { form_create => 'form_create_body' }
    );

    bless $self, $class;
    return $self;
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
sub readrow_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    #---------------------------------------------------------------------------
    #  Form: Set Project Attributes
    #---------------------------------------------------------------------------
    # :TODO:08/11/2011 16:35:27:es:  here breadcrumbs would be useful
    return $q->h2('Editing Project'),

      $self->_body_create_read_menu( 'read' => [ undef, 'Edit Project' ] ),
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

1;
