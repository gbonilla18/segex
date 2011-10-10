
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
#        CLASS:  ManageUsers
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

        _table_defs => {
            'users' => {
                key => [qw/uid/],

                # table key to the left, URI param to the right
                selectors => { uname => 'uname' },
                proto     => [
                    qw/uname full_name address phone level email email_confirmed/
                ],
                view => [
                    qw/uname full_name address phone level email email_confirmed/
                ],
                resource => 'users',
                names    => [qw/uname/],
                meta     => {
                    email => { label => 'Email' },
                    uid   => {
                        label  => 'ID',
                        parser => 'number'
                    },
                    uname     => { label => 'Login ID' },
                    full_name => { label => 'Full Name', -size => 55 },
                    address => {
                        label    => 'Address',
                        __type__ => 'textarea',
                    },
                    phone           => { label => 'Phone' },
                    level           => { label => 'Permissions' },
                    email_confirmed => {
                        label     => 'Email Confirmed',
                        parser    => 'number',
                        -disabled => 'disabled'
                    }
                },
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
#        CLASS:  ManageUsers
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
      $q->h3('Create New User'),

      # Resource URI: /projects
      $q->start_form(
        -method   => 'POST',
        -action   => $self->get_resource_uri(),
        -onsubmit => 'return validate_fields(this, [\'prname\']);'
      ),
      $q->dl(
        $self->_body_edit_fields( mode => 'create' ),
        $q->dt('&nbsp;') => $q->dd(
            $q->hidden( -name => 'b', -value => 'create' ),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Create User',
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
    #  Form: Set User Attributes
    #---------------------------------------------------------------------------
    # :TODO:08/11/2011 16:35:27:es:  here breadcrumbs would be useful
    return $q->h2('Editing User'),

      $self->_body_create_read_menu( 'read' => [ undef, 'Edit User' ] ),
      $q->h3('Set User Attributes'),

      # Resource URI: /projects/id
      $q->start_form(
        -method   => 'POST',
        -action   => $self->get_resource_uri(),
        -onsubmit => 'return validate_fields(this, [\'prname\']);'
      ),
      $q->dl(
        $self->_body_edit_fields( mode => 'update' ),
        $q->dt('&nbsp;') => $q->dd(
            $q->hidden( -name => 'b', -value => 'update' ),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Set Attributes',
                -title => 'Change project attributes'
            )
        )
      ),
      $q->end_form;
}

1;
