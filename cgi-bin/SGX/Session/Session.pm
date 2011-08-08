
=head1 NAME

SGX::Session::Session

=head1 SYNOPSIS

Create an instance:
(1) $dbh must be an active database handle,
(2) 3600 is 60 * 60 s = 1 hour (session time to live),
(3) check_ip determines whether user IP is verified,
(4) id is old session id (either from a cookie or from a query string).

    use SGX::Session::Session;
    my $s = SGX::Session::Session->new(
        dbh    => $dbh, 
        expire_in => 3600,
        check_ip  => 1
    );

Restore previous session if it exists:
    $s->restore('1c287c065fc22df74e3e57c63ceedd20');

Delete previous session, active session, or both if both exist:
    $s->destroy();

Flush session data (writes to data store)
    $s->commit();

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

package SGX::Session::Session;

use strict;
use warnings;

use vars qw($VERSION);

$VERSION = '0.11';

use Apache::Session::MySQL;
use Scalar::Util qw/looks_like_number/;
use SGX::Debug;
use Data::Dumper;
use SGX::Abstract::Exception;

#use Data::Dumper;    # for debugging

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Session
#       METHOD:  new
#   PARAMETERS:  dbh    - DBI handle
#                expire_in - if new session is started, it will given this
#                            property (called time-to-live, it specifies the
#                            number of seconds of inactivity before the session
#                            expires; use expire_in => 3600 for 1 hour)
#                check_ip  - whether to check IP address. If new sessions are
#                            started, they will track IP addresses.
#
#      RETURNS:  ????
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  When expire_in is set to one value but the session being
#                restored has ttl set to another value that is not expired,
#                the new value from expire_in should be used (i.e. honor
#                current request).
#
#                When -check_ip is false but session is tracking IPs (has 'ip'
#                field), we should not check IPs (i.e. honor current request).
#
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ( $class, %args ) = @_;

    # set defaults first
    my %param = (
        expire_in => 3600,    # default: one hour
        check_ip  => 1,       # default: true
        %args
    );

    my $self = {
        dbh           => $param{dbh},
        expire_in     => $param{expire_in},
        check_ip      => $param{check_ip},
        session_obj   => {},                  # actual session object
        session_stash => {}                   # shallow copy of session object
    };
    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Session
#       METHOD:  session_is_tied
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Simply a wrapper for tied()
#       THROWS:  no exceptions
#     COMMENTS:  Only deals with session_obj
#     SEE ALSO:  n/a
#===============================================================================
sub session_is_tied {
    my $self = shift;

    # :TRICKY:06/21/2011 15:24:13:es: if we write this as a one-liner, we will
    # be returning a referene to the tied object instead of Boolean, which will
    # eventually result in the following error when we call untie():
    #
    # "untie attempted while 1 inner references still exist at ..."
    #
    # # One-liner version:
    #    return defined(tied %{ $self->{session_obj} });
    #
    my $ref = tied %{ $self->{session_obj} };
    if ( defined($ref) ) {
        return 1;
    }
    else {
        return;
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Session
#       METHOD:  tie_session
#   PARAMETERS:  ????
#      RETURNS:  returns 1 if a new session was started or an old one restored *by
#                this subroutine*, 0 otherwise
#  DESCRIPTION:
#       THROWS:  SGX::Abstract::Exception::Internal::Session
#     COMMENTS:  Deals with session_obj only
#     SEE ALSO:  n/a
#===============================================================================
sub tie_session {
    my ( $self, $id ) = @_;

    # throw exception -- attempting to tie a session to a hash that's currently
    # occupied
    if ( $self->session_is_tied() ) {
        SGX::Abstract::Exception::Internal::Session->throw( error =>
              'Cannot tie to session hash: another session is currently active'
        );
    }

    # Tie session_obj. Catch exceptions -- failure here is normal.
    my $ret = eval {
        tie %{ $self->{session_obj} }, 'Apache::Session::MySQL', $id,
          {
            Handle     => $self->{dbh},
            LockHandle => $self->{dbh},
          };
    };
    if ( $ret && !$@ ) {
        my $generated_id = $self->{session_obj}->{_session_id};
        if ( defined($id) && !( $generated_id eq $id ) ) {
            SGX::Abstract::Exception::Internal::Session->throw(
                error => 'Internal error' );
        }
        return 1;
    }
    else {
        return;
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Session
#       METHOD:  session_store
#   PARAMETERS:  ????
#      RETURNS:  True value on success
#  DESCRIPTION:  Stores key-value combinations to session object and updates
#                session view
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub session_store {
    my ( $self, %param ) = @_;
    while ( my ( $key, $value ) = each(%param) ) {
        $self->{session_obj}->{$key}   = $value;
        $self->{session_stash}->{$key} = $value;
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Session
#       METHOD:  expire_session
#   PARAMETERS:  ????
#      RETURNS:  1 if session was non-expired, 0 otherwise
#  DESCRIPTION:  Expires current session by setting time-to-live (ttl) to the
#                difference between now and time-last-accessed (tla)
#       THROWS:  no exceptions
#     COMMENTS:  Only deals with session_obj
#     SEE ALSO:  n/a
#===============================================================================
sub expire_session {
    my $self      = shift;
    my $obj       = $self->{session_obj};
    my $curr_time = now();

    if ( $curr_time < $obj->{tla} + $obj->{ttl} ) {
        $obj->{ttl} = $curr_time - $obj->{tla};
        return 1;
    }
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Session
#       METHOD:  checkin
#   PARAMETERS:  $required_session_id - (optional) require that session being
#                checked into has the given id.
#      RETURNS:  true value if checkin is successful, false if not
#  DESCRIPTION:  Checks if the tied session object is not expired, that it has
#                the required _sesion_id field (and optionally if that fields
#                matches the argument), and that the IP field matches the
#                current IP if check_ip is true.
#
#       THROWS:  Internal error in case no session is tied. That a session is tied
#                is important because even if the session_obj field passes all
#                checks, it has to be upated and stored in the database (namely
#                the tla and ttl subfields are update).
#     COMMENTS:  only deals with session_obj
#     SEE ALSO:  n/a
#===============================================================================
sub checkin {
    my ( $self, $required_session_id ) = @_;

    if ( !$self->session_is_tied() ) {

        # Internal error -- no session tied
        SGX::Abstract::Exception::Internal::Session->throw(
            error => 'No session attached: cannot checkin' );
    }

    my $curr_time = now();

    if (
           $self->{session_obj}
        && looks_like_number( $self->{session_obj}->{tla} )
        && looks_like_number( $self->{session_obj}->{ttl} )
        && $curr_time <
        $self->{session_obj}->{tla} + $self->{session_obj}->{ttl}
        && defined( $self->{session_obj}->{_session_id} )
        && ( !defined($required_session_id)
            || $self->{session_obj}->{_session_id} eq $required_session_id )
        && (
            !$self->{check_ip}
            || (   defined( $self->{session_obj}->{ip} )
                && defined( $ENV{REMOTE_ADDR} )
                && $ENV{REMOTE_ADDR} eq $self->{session_obj}->{ip} )
        )
      )
    {

    # :IMPORTANT:06/20/2011 16:41:13:es: This is a typical pattern that shoud be
    # adhered to: attempt to do something and, on success, assign some value
    # nearby, e.g. to one of the fields of the current instance.

        # also update time last accessed
        $self->{session_obj}->{tla} = $curr_time;
        $self->{session_obj}->{ttl} = $self->{expire_in};
        return 1;
    }
    else {
        return;
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Session
#       METHOD:  stash_session
#   PARAMETERS:  ????
#      RETURNS:  True value on success
#  DESCRIPTION:  Copies data from session_obj to session_stash
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub stash_session {
    my $self = shift;

    # copy everything
    while ( my ( $key, $value ) = each( %{ $self->{session_obj} } ) ) {
        $self->{session_stash}->{$key} = $value;
    }

    # _session_id is the only required value in object
    my $session_id = $self->get_session_id();

    if ( !defined($session_id) ) {
        SGX::Abstract::Exception::Internal::Session->throw(
            error => 'Undefined session id' );
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Session
#       METHOD:  get_session_id
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_session_id {
    my $self = shift;

    return $self->{session_stash}->{_session_id};
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Session
#       METHOD:  restore
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Attempt to attach to a session. On fail, return false.
#       THROWS:  SGX::Abstract::Exception::Internal::Session
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub restore {
    my ( $self, $id ) = @_;

    if ( !defined($id) ) {
        SGX::Abstract::Exception::Internal::Session->throw(
            error => 'Cannot restore session from unspecified id' );
    }

    if ( !$self->tie_session($id) ) {
        return;
    }

    # doing checkin() without initialization -- will only work if using a
    # recovered session, not a new one.
    if ( $self->checkin($id) ) {
        return $self->stash_session();
    }
    else {
        $self->destroy();
        return;
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Session
#       METHOD:  start
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Attempt to attach to a session if id is passed or start a new
#                session if the single argument is undef. If a session could not
#                be recaptured from the id, start a new session.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub start {
    my ( $self, $id ) = @_;

    # first try to restore using passed id if it is defined
    return $self->restore($id) if defined($id);

    # on failure start new session
    return ($self->tie_session(undef) && $self->init_session() &&
        $self->stash_session());
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Session
#       METHOD:  init_session
#   PARAMETERS:  ????
#      RETURNS:  True value on success
#  DESCRIPTION:  Initialize a freshly tied session object with values
#       THROWS:  SGX::Abstract::Exception::Internal::Session
#     COMMENTS:  Call after opening a new session. After initialization,
#                checkin(), if called, must return true.
#     SEE ALSO:  n/a
#===============================================================================
sub init_session {
    my $self = shift;

    if ( !defined( $self->{session_obj}->{_session_id} ) ) {
        SGX::Abstract::Exception::Internal::Session->throw( error =>
              'Session hash does not contain required field _session_id' );
    }
    if ( !$self->session_is_tied() ) {
        SGX::Abstract::Exception::Internal::Session->throw(
            error => 'Cannot initialize untied session hash' );
    }

    # New session has been started. Store remote user IP address if
    # ip_check is set to 1
    $self->{session_obj}->{ip} = $ENV{REMOTE_ADDR} if $self->{check_ip};

    # store time info
    $self->{session_obj}->{ttl} = $self->{expire_in};
    $self->{session_obj}->{tla} = now();

    # debugging mode: must pass checkin()
    my $ok = $self->checkin();

    if ( !$ok ) {
        SGX::Abstract::Exception::Internal::Session->throw(
            error => 'Cannot checkin' );
    }

    return $ok;
}

#===  FUNCTION  ================================================================
#         NAME:  now
#      PURPOSE:  Returns time
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub now {

# MySQL timestamp format:
#my @t = localtime();
#sprintf('%04d-%02d-%02d %02d:%02d:%02d',$t[5]+1900,$t[4]+1,$t[3],$t[2],$t[1],$t[0]);
    return time;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Session
#       METHOD:  commit
#   PARAMETERS:  ????
#      RETURNS:  1 on success (session data stored in remote database) or 0 on
#                failure
#  DESCRIPTION:  commits the active session object to object store
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub commit {

    my $self = shift;
    if ( $self->session_is_tied() ) {
        my $session_id = $self->get_session_id();
        untie( %{ $self->{session_obj} } );
        return 1;
    }
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Session
#       METHOD:  unset
#   PARAMETERS:  ????
#      RETURNS:  True on success
#  DESCRIPTION:  Unset session variables
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub unset {
    my $self = shift;
    undef %{ $self->{session_stash} };
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Session
#       METHOD:  destroy
#   PARAMETERS:  ????
#      RETURNS:  True on success
#  DESCRIPTION:  deletes all referenced sessions from object store in this order:
#                (1) delete active if it exists, (2) delete old if it exists
#       THROWS:  no exceptions
#     COMMENTS:  When no session is active, this method should do nothing and
#                exit cleanly
#     SEE ALSO:  n/a
#===============================================================================
sub destroy {
    my $self = shift;

    if ( $self->session_is_tied() ) {
        tied( %{ $self->{session_obj} } )->delete;
        untie( %{ $self->{session_obj} } );
    }

    # clear session data
    return $self->unset();
}

1;    # for require

__END__
