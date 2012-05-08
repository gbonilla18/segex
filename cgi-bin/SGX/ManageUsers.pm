package SGX::ManageUsers;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use SGX::Abstract::Exception ();
use Digest::SHA1 qw/sha1_hex/;

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageUsers
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD::init
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my ( $class, @param ) = @_;
    my $self = $class->SUPER::init(@param);

    $self->set_attributes( _permission_level => 'admin' );

    $self->set_attributes(
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
                        __confirm__ => 1,
                        __encode__  => sub {
                            my $value = shift;
                            require Email::Address;
                            my ($email_handle) = Email::Address->parse($value);
                            SGX::Exception::User->throw( error =>
"Could not parse email address from string '$value'"
                            ) unless defined $email_handle;
                            return $email_handle->address;
                          }
                    },
                    pwd => {
                        label      => 'Password',
                        -size      => 30,
                        __type__   => 'password_field',
                        __encode__ => sub {
                            my $value = shift;
                            SGX::Exception::User->throw( error =>
                                  'Passwords must be at least 6 characters long'
                            ) if length($value) < 6;
                            return sha1_hex($value);
                        },
                        __confirm__    => 1,
                        __createonly__ => 1,
                        __special__ => 1
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
                        label        => 'Full name',
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
                        __extra_html__  => <<"END_EXTRA",
<p class="hint visible">
An <strong>administrator</strong> has complete access; a <strong>user</strong>
is allowed to do everything an administrator is except to create/manage other
users; <strong>read-only user</strong> is only allowed to view and query
database but not to modify any data; a <strong>user with no grants</strong> only
has access to his/her profile but cannot view or change any data.
</p>
END_EXTRA
                        dropdownOptions => [
                            {
                                value => 'nogrants',
                                label => 'Not Granted'
                            },
                            {
                                value => 'readonly',
                                label => 'Read Only'
                            },
                            {
                                value => 'user',
                                label => 'User'
                            },
                            {
                                value => 'admin',
                                label => 'Administrator'
                            }
                        ]
                    },
                    email_confirmed => {
                        __type__        => 'checkbox',
                        label           => 'Verified email',
                        dropdownOptions => [
                            { value => '0', label => 'No' },
                            { value => '1', label => 'Yes' }
                        ],
                        __optional__ => 1
                    },
                    udate => { label => 'Created on', __readonly__ => 1 }
                },
            }
        },
        _default_table => 'users',
    );

    return $self;
}

1;

__END__


=head1 NAME

SGX::ManageUsers

=head1 SYNOPSIS

=head1 DESCRIPTION
Module for managing user table.

=head1 AUTHORS
Eugene Scherba
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut


