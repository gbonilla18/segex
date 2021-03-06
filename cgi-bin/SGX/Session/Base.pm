package SGX::Session::Base;

use strict;
use warnings;

use vars qw($VERSION);

$VERSION = '0.12';

require Apache::Session::MySQL;
use Scalar::Util qw/looks_like_number/;
use SGX::Abstract::Exception ();

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Base
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
    my $class = shift;

    # set defaults first
    my %param = (
        expire_in => 3600,    # default: one hour
        check_ip  => 1,       # default: true
        @_
    );

    my $self = {
        dbh => $param{dbh},
        %param,
        session_obj   => {},    # actual session object
        session_stash => {}     # shallow copy of session object
    };
    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Base
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

    # :TRICKY:06/21/2011 15:24:13:es: Writing this without mapping to 1/True and
    # ()/False will copy reference to tied and result in the following error
    # when calling untie():
    #
    # "untie attempted while 1 inner references still exist at ..."
    #
    # "Bad" version of this function include:
    #    return defined(tied %{ $self->{session_obj} });
    #    return defined(tied %{ $self->{session_obj} }) ? 1 : ();
    #
    my $ref = tied %{ $self->{session_obj} };
    if ( defined $ref ) {
        return 1;
    }
    else {
        return;
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Base
#       METHOD:  tie_session
#   PARAMETERS:  ????
#      RETURNS:  returns 1 if a new session was started or an old one restored *by
#                this subroutine*, 0 otherwise
#  DESCRIPTION:
#       THROWS:  SGX::Exception::Internal::Session
#     COMMENTS:  Deals with session_obj only
#     SEE ALSO:  n/a
#===============================================================================
sub tie_session {
    my ( $self, $id ) = @_;

    # throw exception -- attempting to tie a session to a hash that's currently
    # occupied
    if ( $self->session_is_tied() ) {
        SGX::Exception::Internal::Session->throw( error =>
              'Cannot tie to session hash: another session is currently active'
        );
    }

    # Tie session_obj; catch tie exceptions
    eval {
        tie %{ $self->{session_obj} }, 'Apache::Session::MySQL', $id,
          {
            Handle     => $self->{dbh},
            LockHandle => $self->{dbh},
          };
        1;
    } or do {
        return;    # return false on error
    };
    my $generated_id = $self->{session_obj}->{_session_id};
    if ( defined($id) and $id ne $generated_id ) {

        # :TRICKY:05/06/2012 00:17:00:es: Because SGX::Profile module
        # automatically tries to restore session from sid= parameter, this
        # exception can be triggered if we use input elements in that module
        # with name attribute set to 'sid' for example.
        SGX::Exception::Internal::Session->throw(
            error => 'Generated session id does not match requested' );
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Base
#       METHOD:  session_store
#   PARAMETERS:  ????
#      RETURNS:  True value on success
#  DESCRIPTION:  Stores key-value combinations to session object and updates
#                session view
#       THROWS:  no exceptions
#     COMMENTS:  Counterpart to session_delete()
#     SEE ALSO:  n/a
#===============================================================================
sub session_store {
    my ( $self, %param ) = @_;

    my $session_obj   = $self->{session_obj};
    my $session_stash = $self->{session_stash};

    while ( my ( $key, $value ) = each(%param) ) {
        $session_obj->{$key}   = $value;
        $session_stash->{$key} = $value;
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Base
#       METHOD:  session_delete
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  Counterpart to session_store()
#     SEE ALSO:  n/a
#===============================================================================
sub session_delete {
    my ( $self, @keys ) = @_;

    #$self->session_store(map { $_ => undef} @keys);

    my $session_obj   = $self->{session_obj};
    my $session_stash = $self->{session_stash};

    foreach my $key (@keys) {
        delete $session_obj->{$key};
        delete $session_stash->{$key};
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Base
#       METHOD:  expire
#   PARAMETERS:  ????
#      RETURNS:  1 if session was non-expired, 0 otherwise
#  DESCRIPTION:  Expires current session by setting time-to-live (ttl) to the
#                difference between now and time-last-accessed (tla)
#       THROWS:  no exceptions
#     COMMENTS:  Only deals with session_obj
#     SEE ALSO:  n/a
#===============================================================================
sub expire {
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
#        CLASS:  SGX::Session::Base
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
        SGX::Exception::Internal::Session->throw(
            error => 'No session attached: cannot checkin' );
    }

    my $curr_time = now();

    my $obj = $self->{session_obj};
    if (
           $obj
        && looks_like_number( $obj->{tla} )
        && looks_like_number( $obj->{ttl} )
        && $curr_time < $obj->{tla} + $obj->{ttl}
        && defined( $obj->{_session_id} )
        && ( !defined($required_session_id)
            || $obj->{_session_id} eq $required_session_id )
        && (
            !$self->{check_ip}
            || (   defined( $obj->{ip} )
                && defined( $ENV{REMOTE_ADDR} )
                && $ENV{REMOTE_ADDR} eq $obj->{ip} )
        )
      )
    {

    # :IMPORTANT:06/20/2011 16:41:13:es: This is a typical pattern that shoud be
    # adhered to: attempt to do something and, on success, assign some value
    # nearby, e.g. to one of the fields of the current instance.

        # also update time last accessed
        $obj->{tla} = $curr_time;
        $obj->{ttl} = $self->{expire_in};
        return 1;
    }
    else {
        return;
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Base
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
        SGX::Exception::Internal::Session->throw(
            error => 'Undefined session id' );
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Base
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
#        CLASS:  SGX::Session::Base
#       METHOD:  restore
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Attempt to attach to a session. On fail, return false.
#       THROWS:  SGX::Exception::Internal::Session
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub restore {
    my ( $self, $id ) = @_;

    if ( !defined($id) ) {
        SGX::Exception::Internal::Session->throw(
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
#        CLASS:  SGX::Session::Base
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
    return ( $self->tie_session(undef)
          && $self->init_session()
          && $self->stash_session() );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Base
#       METHOD:  renew
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  "Untaint" (renew) impure session (one whose id has been
#                shared with the outside). Accomplishes this by deleting session
#                object from the database store, creating a new one and
#                populating the new object from the stash. Assumes that the
#                session stash already contains a copy of session object.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub renew {
    my ($self) = @_;

    # delete session_obj and create a new one
    tied( %{ $self->{session_obj} } )->delete;
    untie( %{ $self->{session_obj} } );
    $self->tie_session(undef);

    # Copy all keys except _session_id from session_stash to session_obj.
    # Likewise, copy _session_id from session_obj to session_stash
    my $session_obj   = $self->{session_obj};
    my $session_stash = $self->{session_stash};

    $session_stash->{_session_id} = $session_obj->{_session_id};
    while ( my ( $key, $value ) = each(%$session_stash) ) {
        $session_obj->{$key} = $value;
    }

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Base
#       METHOD:  init_session
#   PARAMETERS:  ????
#      RETURNS:  True value on success
#  DESCRIPTION:  Initialize a freshly tied session object with values
#       THROWS:  SGX::Exception::Internal::Session
#     COMMENTS:  Call after opening a new session. After initialization,
#                checkin(), if called, must return true.
#     SEE ALSO:  n/a
#===============================================================================
sub init_session {
    my $self = shift;

    if ( !defined( $self->{session_obj}->{_session_id} ) ) {
        SGX::Exception::Internal::Session->throw( error =>
              'Session hash does not contain required field _session_id' );
    }
    if ( !$self->session_is_tied() ) {
        SGX::Exception::Internal::Session->throw(
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
        SGX::Exception::Internal::Session->throw( error => 'Cannot checkin' );
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
#        CLASS:  SGX::Session::Base
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
        untie( %{ $self->{session_obj} } );
        return 1;
    }
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Base
#       METHOD:  detach
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Detach session
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub detach {
    my $self = shift;

    # Note: this does place everything currently stored in session_obj to data
    # store.
    if ( $self->session_is_tied() ) {
        untie( %{ $self->{session_obj} } );
    }

    # clear session data (results in empty anonymous hash)
    undef %{ $self->{session_stash} };
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session::Base
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

    # clear session data (results in empty anonymous hash)
    undef %{ $self->{session_stash} };
    return 1;
}

1;    # for require

__END__


=head1 NAME

SGX::Session::Base

=head1 SYNOPSIS

Create an instance:
(1) $dbh must be an active database handle,
(2) 3600 is 60 * 60 s = 1 hour (session time to live),
(3) check_ip determines whether user IP is verified,
(4) id is old session id (either from a cookie or from a query string).

    use SGX::Session::Base;
    my $s = SGX::Session::Base->new(
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


