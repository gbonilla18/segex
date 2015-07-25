package SGX::ManageUsers;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use SGX::Util qw/car/;
use SGX::Abstract::Exception ();

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

    $self->set_attributes(
        _permission_level => 'admin',
        _table_defs       => {
            'users' => {
                item_name => 'user',
                key       => [qw/uid/],

                # table key to the left, URI param to the right
                selectors => { uname => 'uname' },
                base => [qw/uname email full_name address phone level/],
                view => [
                    qw/uname full_name address phone level email email_confirmed udate/
                ],
                resource => 'users',
                names    => [qw/uname/],
                meta     => {
                    email => {
                        label       => 'Email',
                        formatter   => sub { 'formatEmail' },
                        -size       => 30,
                        __confirm__ => 1,
                        __encode__  => sub {
                            my $value = shift;
                            require Email::Address;
                            my ($email_handle) = Email::Address->parse($value);
                            SGX::Exception::User->throw( error =>
"Could not parse email address from string '$value'"
                            ) unless defined $email_handle;
                            return $email_handle->address;
                        },
                        __extra_html__ =>
'<p class="hint visible">When a new user is created, an email is sent to the specified address requesting to choose a password.</p>'
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
                        -size        => 45,
                        __optional__ => 1
                    },
                    address => {
                        label        => 'Address',
                        __type__     => 'textarea',
                        __optional__ => 1
                    },
                    phone => { label => 'Contact Phone', __optional__ => 1 },
                    level => {
                        label          => 'Permissions',
                        __type__       => 'popup_menu',
                        __extra_html__ => <<"END_EXTRA",
<p class="hint visible">
<strong>Not Granted:</strong> plain user account without access to any data.
<strong>Read Only:</strong> can view and query all data but not to modify it.
<strong>User:</strong> can do everything except create and manage other users.
<strong>Administrator:</strong> unlimited account.
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
                        label           => 'Verified email',
                        dropdownOptions => [
                            { value => '0', label => 'No' },
                            { value => '1', label => 'Yes' }
                        ],
                        __type__     => 'checkbox',
                        __readonly__ => 1,
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

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageUsers
#       METHOD:  default_create
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD::default_create
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_create {
    my $self = shift;
    my ( $q, $s ) = @$self{qw/_cgi _UserSession/};

    if ( my @ret = $self->SUPER::default_create() ) {
        $s->reset_password(
            new_user          => 1,
            username_or_email => car( $q->param('uname') ),
            project_name      => 'Segex',
            login_uri         => $q->url( -full => 1 )
              . '?a=profile&b=form_changePassword'
        );
        return @ret;
    }
    else {
        return;
    }
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


