
=head1 NAME

SGX::Cookie

=head1 SYNOPSIS

Create an instance:
(1) $dbh must be an active database handle,
(2) 3600 is 60 * 60 s = 1 hour (session time to live),
(3) check_ip determines whether user IP is verified,
(4) cookie_name can be anything

    use SGX::Cookie;
    my $s = SGX::Cookie->new(
        -handle     => $dbh, 
        -expire_in   => 3600,
        -check_ip    => 1,
        -cookie_name => 'chocolate_chip'
    );

Restore previous session if it exists
    $s->restore;

Delete previous session, active session, or both if both exist
    $s->destroy;

To make a cookie and flush session data:
    $s->commit;

You can set another cookie by opening another session like this:

    my $t = SGX::Cookie->new(
        -cookie_name => 'girlscout_mint', 
        -handle      => $dbh, 
        -expire_in   => 3600*48, 
        -check_ip    => 0
    );
    
    if (!$t->restore) $t->commence;
    $t->commit;

You can create several instances of this class at the same time. The 
@SGX::Cookie::cookies array will contain the cookies created by all instances
of the SGX::User or SGX::Cookie classes. If the array reference is sent to CGI::header, for 
example, as many cookies will be created as there are members in the array.

To send a cookie to the user:

    $q = CGI->new();
    print $q->header(
        -type=>'text/html',
        -cookie=>\@SGX::Cookie::cookies
    );

=head1 DESCRIPTION

This is mainly an interface to the Apache::Session module with
focus on user management.

The table `sessions' is created as follows:

    CREATE TABLE sessions (
        id CHAR(32) NOT NULL UNIQUE,
        a_session TEXT NOT NULL
    );

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

package SGX::Cookie;

use strict;
use warnings;

use vars qw($VERSION);

$VERSION = '0.10';

use base qw/SGX::Session/;
use CGI::Cookie;
use File::Basename;

# some (constant) globals
my $SESSION_NAME     = 'session';
my $SESSION_ID_FIELD = 'sid';

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
#        CLASS:  SGX::Cookie
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is the constructor. Redefining the constructor from
#                SGX::Session -- try to obtain an id from a cookie first.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {

    my ( $class, %p ) = @_;

    # :TODO:06/05/2011 22:48:28:es: figure out a more reliable way to
    # tell whether a session is active than relying on the `active'
    # property.

    my %cookies = fetch CGI::Cookie;

    # in scalar context, the result of CGI::Cookie::value is a scalar
    my %session_cookie = eval { $cookies{$SESSION_NAME}->value };

    my $self = {
        dbh             => $p{-handle},
        ttl             => $p{-expire_in},
        check_ip        => $p{-check_ip},
        fetched_cookies => \%cookies,
        session_obj     => {},                 # actual session object
        session_stash   => {},                 # shallow copy of session object
        session_cookie  => \%session_cookie,
        session_id => $session_cookie{$SESSION_ID_FIELD},
        active     => 0
    };

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session
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
    my ( $self, %p ) = @_;
    while ( my ( $key, $value ) = each(%p) ) {
        $self->{session_cookie}->{$key} = $value;
    }
    $self->{session_cookie_modified} = 1;
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Cookie
#       METHOD:  cookie_array
#   PARAMETERS:  n/a
#      RETURNS:  reference to the @cookies array
#  DESCRIPTION:  This is a getter method for the @cookies array.
#                Because the @cookies array is shared among all instances, one
#                can also call this funciton as SGX::Cookies::cookie_array()
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub cookie_array {
    return \@cookies;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Cookie
#       METHOD:  add_cookie
#   PARAMETERS:  key-value pairs to initialize CGI::Cookie (at the moment)
#      RETURNS:  n/a
#  DESCRIPTION:  Pushes a cookie to the shared @cookies array
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub add_cookie {
    my ( $self, %p ) = @_;

    # set default values
    $p{-path} = dirname( $ENV{SCRIPT_NAME} ) if not defined( $p{-path} );
    $p{-httponly} = 1 if not defined( $p{-httponly} );

    # prepare the cookie
    push @cookies, CGI::Cookie->new(%p);
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Cookie
#       METHOD:  commit
#   PARAMETERS:  ????
#      RETURNS:  1 on success (session data stored in remote database) or 0 on
#                failure
#  DESCRIPTION:  Overrides parent method: calls parent method first, then bakes
#                a session cookie on success if needed
#       THROWS:  no exceptions
#     COMMENTS:  Note that, when subclassing, that overridden methods return
#                the same values on same conditions
#     SEE ALSO:  n/a
#===============================================================================
sub commit {

    my $self = shift;

    # one-way sync with session data: if cookie is missing or doesn't match
    # what's stored in the session, update cookie with session data.
    if (
        defined( $self->{session_stash}->{_session_id} )
        && ( !defined( $self->{session_cookie}->{$SESSION_ID_FIELD} )
            || $self->{session_cookie}->{$SESSION_ID_FIELD} ne
            $self->{session_stash}->{_session_id} )
      )
    {
        $self->session_cookie_store(
            $SESSION_ID_FIELD => $self->{session_stash}->{_session_id} );
    }

    if ( $self->SUPER::commit() ) {
        return 1 if not $self->{session_cookie_modified};
        $self->add_cookie(
            -name  => $SESSION_NAME,
            -value => $self->{session_cookie}
        );

        #   -domain    => $ENV{SERVER_NAME},
        return 1;
    }
    return 0;
}

1;    # for require

__END__
