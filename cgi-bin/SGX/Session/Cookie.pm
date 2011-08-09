
=head1 NAME

SGX::Session::Cookie

=head1 SYNOPSIS

Create an instance:
(1) $dbh must be an active database handle,
(2) 3600 is 60 * 60 s = 1 hour (session time to live),
(3) check_ip determines whether user IP is verified,
(4) cookie_name can be anything

    use SGX::Session::Cookie;
    my $s = SGX::Session::Cookie->new(
        dbh     => $dbh, 
        expire_in   => 3600,
        check_ip    => 1
    );

Restore previous session if it exists
    $s->restore;

Delete previous session, active session, or both if both exist
    $s->destroy;

To make a cookie and flush session data:
    $s->commit;

You can set another cookie by opening another session like this:

    my $t = SGX::Session::Cookie->new(
        dbh      => $dbh, 
        expire_in   => 3600*48, 
        check_ip    => 0
    );
    
    if (!$t->restore) $t->start;
    $t->commit;

You can create several instances of this class at the same time. The
@SGX::Session::Cookie::cookies array will contain the cookies created by all
instances of the SGX::Session::User or SGX::Session::Cookie classes. If the
array reference is sent to CGI::header, for example, as many cookies will be
created as there are members in the array.

To send a cookie to the user:

    $q = CGI->new();
    print $q->header(
        -type=>'text/html',
        -cookie=>\@SGX::Session::Cookie::cookies
    );

=head1 DESCRIPTION

This is mainly an interface to the Apache::Session module with
focus on user management.

The table `sessions' is created as follows:

    CREATE TABLE sessions (
        id CHAR(32) NOT NULL UNIQUE,
        a_session TEXT NOT NULL
    ) ENGINE=InnoDB;

=head1 AUTHORS

Written by Eugene Scherba <escherba@gmail.com>

=head1 SEE ALSO

http://search.cpan.org/~chorny/Apache-Session-1.88/Session.pm
http://search.cpan.org/dist/perl/pod/perlmodstyle.pod

=head1 COPYRIGHT

Copyright (c) 2009 Eugene Scherba

=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::Session::Cookie;

use strict;
use warnings;

use vars qw($VERSION);

$VERSION = '0.11';

use base qw/SGX::Session::Session/;
use CGI::Cookie;
use File::Basename;

# some (constant) globals
my $SESSION_NAME = 'session';
my $SID_FIELD    = 'sid';

#use SGX::Debug;
#use Data::Dumper;    # for debugging

# Variables declared as "our" within a class (package) scope will be shared between
# all instances of the class *and* can be addressed from the outside like so:
#
#   my $var = $PackageName::var;
#   my $array_reference = \@PackageName::array;
#
our @cookies;

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Cookie
#       METHOD:  session_cookie_store
#   PARAMETERS:  Variable-length list of arbitrary key-value pairs to be
#                stored in the session cookie
#      RETURNS:  ????
#  DESCRIPTION:  Stores key-value combinations to session cookie
#       THROWS:  no exceptions
#     COMMENTS:  Setting fields in $self->{session_cookie} directly won't
#                trigger the $self->{session_cookie_modified} state change so it
#                important that only the interface implemented by this method
#                is used for setting session cookie data.
#     SEE ALSO:  n/a
#===============================================================================
sub session_cookie_store {
    my ( $self, %param ) = @_;
    while ( my ( $key, $value ) = each(%param) ) {
        $self->{session_cookie}->{$key} = $value;
    }
    $self->{session_cookie_modified} = 1;
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Cookie
#       METHOD:  restore
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides SGX::Session::Session::restore. First tries to get
#                session from the provided id, and, on success stores the id in
#                the session cookie. If that fails, fetches cookies, looks for
#                one with name $SESSION_NAME, and tries to get the session id
#                from there.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub restore {
    my ($self, $id) = @_;

    # first try to restore session from provided id
    if ( defined($id) && $self->SUPER::restore($id) ) {
        $self->{session_cookie} = { $SID_FIELD => $id };
        #$self->{session_cookie_modified} = 1;
        return 1;
    }
 # :TODO:08/08/2011 23:46:18:es: When restoring from ?sid= URI parameter,
 # cookies are never fetched.
 #
    # on failure, try to get id from cookies
    my %cookies = fetch CGI::Cookie;
    $self->{fetched_cookies} = \%cookies;

    # in scalar context, the result of CGI::Cookie::value is a scalar
    my %session_cookie = eval { $cookies{$SESSION_NAME}->value };
    $id = $session_cookie{$SID_FIELD};

    if ( defined($id) && $self->SUPER::restore($id) ) {
        $self->{session_cookie} = \%session_cookie;
        #$self->{session_cookie_modified} = 1;
        return 1;
    }

    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Cookie
#       METHOD:  cookie_array
#   PARAMETERS:  n/a
#      RETURNS:  reference to the @cookies array
#  DESCRIPTION:  This is a getter method for the @cookies array.  Because the
#                @cookies array is shared among all instances, one can also call
#                this funciton as SGX::Session::Cookie::cookie_array()
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub cookie_array {
    return \@cookies;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Cookie
#       METHOD:  add_cookie
#   PARAMETERS:  key-value pairs to initialize CGI::Cookie (at the moment)
#      RETURNS:  n/a
#  DESCRIPTION:  Pushes a cookie to the shared @cookies array
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub add_cookie {
    my ($self, %param) = @_;

    # set defaults first
    my %cookie_opts = (

        #-domain   => $ENV{SERVER_NAME},
        -path     => dirname( $ENV{SCRIPT_NAME} ),
        -httponly => 1,
        %param
    );

    # prepare the cookie
    push @cookies, CGI::Cookie->new(%cookie_opts);
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Cookie
#       METHOD:  commit
#   PARAMETERS:  ????
#      RETURNS:  session id on success (session data stored in remote database)
#                or false value on failure
#  DESCRIPTION:  Overrides parent method: calls parent method first, then bakes
#                a session cookie on success if needed
#       THROWS:  no exceptions
#     COMMENTS:  Note that, when subclassing, that overridden methods return
#                the same values on same conditions
#     SEE ALSO:  n/a
#===============================================================================
sub commit {

    my $self = shift;

    if ( $self->SUPER::commit() ) {

        my $session_id = $self->get_session_id();

        # one-way sync with session data: if cookie is missing or doesn't match
        # what's stored in the session, update cookie with session data.
        if ( !defined( $self->{session_cookie}->{$SID_FIELD} )
            || $self->{session_cookie}->{$SID_FIELD} ne $session_id )
        {
            $self->session_cookie_store( $SID_FIELD => $session_id );
        }
        if ( $self->{session_cookie_modified} ) {

            # cookie could be modified either because of different session id
            # being set directly above this block or due to user calling
            # session_cookie_store().
            $self->add_cookie(
                -name  => $SESSION_NAME,
                -value => $self->{session_cookie}
            );
        }
        return 1;
    }
    return;
}

1;    # for require

__END__
