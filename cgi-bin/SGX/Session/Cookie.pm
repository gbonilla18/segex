package SGX::Session::Cookie;

use strict;
use warnings;

use vars qw($VERSION);

$VERSION = '0.12';

use base qw/SGX::Session::Base/;

use Readonly ();
require Digest::SHA1;
require CGI::Cookie;
use File::Basename qw/dirname/;
use SGX::Abstract::Exception ();

# some (constant) globals
Readonly::Scalar my $SESSION_NAME => 'session';
Readonly::Scalar my $SID_FIELD    => 'sid';

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
#                trigger the $self->{_session_cookie_modified} state change so it
#                important that only the interface implemented by this method
#                is used for setting session cookie data.
#     SEE ALSO:  n/a
#===============================================================================
sub session_cookie_store {
    my ( $self, %param ) = @_;
    while ( my ( $key, $value ) = each(%param) ) {
        $self->{session_cookie}->{$key} = $value;
    }
    $self->{_session_cookie_modified} = 1;
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Cookie
#       METHOD:  encrypt
#   PARAMETERS:  string
#      RETURNS:  SHA1 hash of input string
#  DESCRIPTION:  Generate a sha1_hex hash of an input string. If input is
#                undefined, returns an undefined value as well.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub encrypt {
    my $self  = shift;
    my $input = shift;
    return defined($input) ? Digest::SHA1::sha1_hex($input) : undef;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Cookie
#       METHOD:  restore
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides SGX::Session::Base::restore. First tries to get
#                session from the provided id, and, on success stores the id in
#                the session cookie. If that fails, fetches cookies, looks for
#                one with name $SESSION_NAME, and tries to get the session id
#                from there.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub restore {
    my ( $self, $id ) = @_;

    # Makes sure cookies are fetched when restoring from ?sid= URI parameter,
    my %cookies = CGI::Cookie->fetch;
    $self->{fetched_cookies} = \%cookies;

    # first try to restore session from provided id
    if ( defined($id) && $self->SUPER::restore($id) ) {
        $self->{session_cookie} = { $SID_FIELD => $id };
        $self->{_session_cookie_modified} = 1;
        return 1;
    }

    # in scalar context, the result of CGI::Cookie::value is a scalar
    my %session_cookie = eval { $cookies{$SESSION_NAME}->value };
    $id = $session_cookie{$SID_FIELD};
    if ( defined($id) && $self->SUPER::restore($id) ) {

        # do not set _session_cookie_modified here to 1 -- otherwise a cookie
        # will be sent every time a page is loaded.
        $self->{session_cookie} = \%session_cookie;
        return 1;
    }

    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Base
#       METHOD:  authenticate
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub authenticate {
    my ( $self, $args ) = @_;
    my ( $session_id, $username, $password ) =
      @$args{qw(session_id username password)};

    # default: true
    my $reset_session =
      ( exists $args->{reset_session} )
      ? $args->{reset_session}
      : 1;

    ( defined($session_id) && $session_id ne '' )
      or SGX::Exception::Internal::Session->throw(
        error => 'No session id provided' );
    ( defined($username) && $username ne '' )
      or SGX::Exception::User->throw( error => 'No username provided' );
    ( defined($password) && $password ne '' )
      or SGX::Exception::User->throw( error => 'No password provided' );

    # convert password to SHA1 hash right away
    $password = $self->encrypt($password);

    #---------------------------------------------------------------------------
    #  authenticate
    #---------------------------------------------------------------------------
    SGX::Exception::Session::Expired->throw(
        error => 'Your session has expired' )
      unless $self->SUPER::restore($session_id);

    my $stash              = $self->{session_stash};
    my $session_username   = $stash->{username};
    my $session_password   = $stash->{password};
    my $session_user_level = $stash->{user_level};
    my $session_full_name  = $stash->{full_name};
    my $session_email      = $stash->{email};

    if ( !defined($session_username) || !defined($session_password) ) {

        # Eat up this session; we are not keen on keeping session info in the
        # database
        $self->destroy();
        SGX::Exception::Internal::Session->throw( error => 'Bad session' );
    }
    elsif ( $session_username ne $username || $session_password ne $password ) {
        $self->detach();
        SGX::Exception::User->throw( error => 'Login incorrect' );
    }

    #---------------------------------------------------------------------------
    #  authenticated OK
    #---------------------------------------------------------------------------
    if ($reset_session) {

        # :TRICKY:08/08/2011 10:09:29:es: We invalidate previous session id by
        # calling destroy() followed by start() to prevent Session Fixation
        # vulnerability: https://www.owasp.org/index.php/Session_Fixation

        $self->destroy();
        $self->start();
    }

    # Login username and user level are sensitive data: we only store them
    # remotely as part of session data. Note: by setting user_level field in
    # session data, we grant the owner of the current session access to the site
    # under that specific authorization level. In other words, this is the
    # specific line where the "magic" act of granting access happens. Note that
    # we only grant access to a new session handle, destroying the old one.
    SGX::Exception::Internal::Session->throw(
        error => 'Could not store session info' )
      unless $self->session_store(
        username   => $username,
        user_level => $session_user_level
      );

    # Note: read permanent cookie before setting session cookie fields here:
    # this helps preserve the flow: database -> session -> (session_cookie,
    # perm_cookie), since reading permanent cookie synchronizes everything in it
    # with the session cookie.
    $self->read_perm_cookie($username);

    # Full user name is not sensitive from database perspective and can be
    # stored on the cliend in a can be stored on the client in a session cookie.
    # Note that there is no need to store it in a permanent cookie on the client
    # because the authentication process will involve a database transaction
    # anyway and a full name can be looked up from there.
    $self->session_cookie_store(
        full_name => $session_full_name,
        email     => $session_email
    );

    return 1;
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
    my $self = shift;

    # set defaults first
    my %cookie_opts = (

        #-domain   => $ENV{SERVER_NAME},
        -path     => dirname( $ENV{SCRIPT_NAME} ),
        -httponly => 1,
        @_
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
        if ( $self->{_session_cookie_modified} ) {

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

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Cookie
#       METHOD:  dump_cookies_sent_to_user
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  
#       THROWS:  no exceptions
#     COMMENTS:  For debugging only
#     SEE ALSO:  n/a
#===============================================================================
sub dump_cookies_sent_to_user {
    my $s = shift;

    use Data::Dumper qw/Dumper/;
    my $cookie_array  = Dumper( $s->cookie_array()  || [] );
    my $session_stash = Dumper( $s->{session_stash} || {} );
    my $ttl = $s->{session_stash}->{ttl} || '?';

    #my $ttl           = $s->{session_obj}->{ttl};

    return <<"END_COOKIE_BLOCK";
<pre>
------------------------------------------------------
Cookies sent to user:

$cookie_array
------------------------------------------------------
Object stored in the "sessions" table in the database:

$session_stash
------------------------------------------------------
session expires after $ttl seconds of inactivity
------------------------------------------------------
</pre>
END_COOKIE_BLOCK
}

1;    # for require

__END__


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


