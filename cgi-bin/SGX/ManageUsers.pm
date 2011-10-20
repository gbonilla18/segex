
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

use SGX::Abstract::Exception;
use Digest::SHA1 qw/sha1_hex/;

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

    $self->set_attributes(

        _permission_level => 'admin',

        _table_defs => {
            'users' => {
                item_name => 'user',
                key       => [qw/uid/],

                # table key to the left, URI param to the right
                selectors => { uname => 'uname' },
                base      => [
                    qw/uname pwd full_name address phone level email email_confirmed/
                ],
                view => [
                    qw/uname full_name address phone level email email_confirmed udate/
                ],
                resource => 'users',
                names    => [qw/uname/],
                meta     => {
                    email => {
                        label       => 'Email',
                        formatter   => sub { 'formatEmail' },
                        -size       => 35,
                        __confirm__ => 1
                    },
                    pwd => {
                        label        => 'Password',
                        -size        => 30,
                        __encode__   => sub { sha1_hex(shift) },
                        __confirm__  => 1,
                        __createonly__ => 1,
                        __valid__    => sub {
                            SGX::Exception::User->throw( error =>
                                  'Passwords must be at least 6 characters long'
                            ) if length(shift) < 6;
                          }
                    },
                    uid => {
                        label  => 'ID',
                        parser => 'number'
                    },
                    uname => {
                        label => 'Login ID',
                        -size => 30
                    },
                    full_name => {
                        label        => 'Full Name',
                        -size        => 55,
                        __optional__ => 1
                    },
                    address => {
                        label        => 'Address',
                        __type__     => 'textarea',
                        __optional__ => 1
                    },
                    phone => { label => 'Phone', __optional__ => 1 },
                    level => {
                        label           => 'Permissions',
                        __type__        => 'popup_menu',
                        dropdownOptions => [
                            { value => '',      label => 'Not Granted' },
                            { value => 'user',  label => 'User' },
                            { value => 'admin', label => 'Administrator' }
                        ]
                    },
                    email_confirmed => {
                        __type__        => 'checkbox',
                        label           => 'Email Confirmed',
                        dropdownOptions => [
                            { value => '0', label => 'No' },
                            { value => '1', label => 'Yes' }
                        ],
                        __optional__ => 1
                    },
                    udate => { label => 'Date Created', }
                },
            }
        },
        _default_table => 'users',
    );

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageUsers
#       METHOD:  default_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD default_body
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_body {

    # Form HTML for the project table.
    my $self = shift;
    my $q    = $self->{_cgi};

    #---------------------------------------------------------------------------
    #  Project dropdown
    #---------------------------------------------------------------------------
    my $resource_uri = $self->get_resource_uri();
    return $q->h2( $self->{_title} ),
      $self->body_create_read_menu(
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

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageUsers
#       METHOD:  readrow_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD readrow_body
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub readrow_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    #---------------------------------------------------------------------------
    #  Form: Set User Attributes
    #---------------------------------------------------------------------------
    # :TODO:08/11/2011 16:35:27:es:  here breadcrumbs would be useful
    return $q->h2( 'Editing User: ' . $self->{_id_data}->{full_name} ),

      $self->body_create_read_menu(
        'read'   => [ undef,         'Edit User' ],
        'create' => [ 'form_assign', '' ]
      ),
      $q->h3('Set User Attributes'),

      # Resource URI: /projects/id
      $self->body_create_update_form( mode => 'update' );
}

1;
