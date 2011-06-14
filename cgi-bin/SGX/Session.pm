
=head1 NAME

SGX::Session

=head1 SYNOPSIS

Create an instance:
(1) $dbh must be an active database handle,
(2) 3600 is 60 * 60 s = 1 hour (session time to live),
(3) check_ip determines whether user IP is verified,
(4) id is old session id (either from a cookie or from a query string).

    use SGX::Session;
    my $s = SGX::Session->new(
        -handle    => $dbh, 
        -expire_in => 3600,
        -check_ip  => 1,
        -id        => '1c287c065fc22df74e3e57c63ceedd20'
    );

Restore previous session if it exists:
    $s->restore();

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

package SGX::Session;

use strict;
use warnings;

use vars qw($VERSION);

$VERSION = '0.10';

use Apache::Session::MySQL;
use SGX::Debug;
use Carp;

#use Data::Dumper;    # for debugging

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {

    my ( $class, %p ) = @_;

    # :TODO:06/05/2011 22:48:28:es: figure out a more reliable way to
    # tell whether a session is active than relying on the `active'
    # property.

    my $self = {
        dbh          => $p{-handle},
        ttl          => $p{-expire_in},
        check_ip     => $p{-check_ip},
        session_id   => $p{-id},
        session_obj  => {},
        session_view => {},
        active       => 0
    };
    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session
#       METHOD:  safe_tie
#   PARAMETERS:  ????
#      RETURNS:  returns 1 if a new session was commenced or an old one restored *by
#                this subroutine*, 0 otherwise
#  DESCRIPTION:
#       THROWS:  croak() if active session present
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub safe_tie {

    my ( $self, $id ) = @_;
    if ( $self->{active} ) {
        croak 'Cannot tie to session hash: another session is currently active';
    }
    my $ret = eval {
        tie %{ $self->{session_obj} }, 'Apache::Session::MySQL', $id,
          {
            Handle     => $self->{dbh},
            LockHandle => $self->{dbh},
          };
    };
    if ( !$ret || $@ ) {

        # error
        #carp "Could not tie session object (session id: $@)";
        return 0;
    }

    # no error
    $self->{active} = 1;
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session
#       METHOD:  session_store
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Stores key-value combinations to session object and updates
#                session view
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub session_store {
    my ( $self, %p ) = @_;
    while ( my ( $key, $value ) = each(%p) ) {
        $self->{session_obj}->{$key}  = $value;
        $self->{session_view}->{$key} = $value;
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session
#       METHOD:  expire_session
#   PARAMETERS:  ????
#      RETURNS:  1 if session was non-expired, 0 otherwise
#  DESCRIPTION:  Expires current session by setting time-to-live (ttl) to the
#                difference between now and time-last-accessed (tla)
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub expire_session {
    my $self      = shift;
    my $curr_time = now();
    if (
        $curr_time < $self->{session_obj}->{tla} + $self->{session_obj}->{ttl} )
    {
        $self->{session_obj}->{ttl} = $curr_time - $self->{session_obj}->{tla};
        return 1;
    }
    return 0;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session
#       METHOD:  session_is_mint
#   PARAMETERS:  ????
#      RETURNS:  true value if yes, false if no
#  DESCRIPTION:  a) if not expired then
#                b) if not check ip -> OK
#                c) if check ip then
#                d) if stored_ip = ip -> OK
#                e) if stored_ip != ip -> not OK
#
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub session_is_mint {
    my $self  = shift;
    my $store = $self->{session_obj};
    my $tla   = $store->{tla};
    my $ttl   = $store->{ttl};
    my $ip    = $store->{ip};

    my $solid =
      ( now() < $tla + $ttl
          and ( !$self->{check_ip} or $ENV{REMOTE_ADDR} eq $ip ) );

    return $solid;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session
#       METHOD:  try_commence
#   PARAMETERS:  ????
#      RETURNS:  returns the same value as safe_tie method
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub try_commence {

    my ( $self, $id ) = @_;
    if ( !$self->safe_tie($id) ) {
        return 0;
    }

    # check that safe_tie() set the "active" property
    assert( $self->{active} );
    if ( defined($id) ) {

    # old session has been restored. At this point, %{session_view} does not yet
    # reflect %{session_obj}
        if ( $self->session_is_mint() ) {

            # update TLA (time last accessed)
            $self->{session_obj}->{tla} = now();

            # sync all session data
            while ( my ( $key, $value ) = each( %{ $self->{session_obj} } ) ) {
                $self->{session_view}->{$key} = $value;
            }
        }
        else {

       # delete if tla + ttl < cur_time or if user IP doesn't match stored value
            $self->delete_object();
        }
    }
    else {

        # new session has been commenced
        # store remote user IP address if ip_check is set to 1
        $self->{session_obj}->{ip} = $ENV{REMOTE_ADDR} if $self->{check_ip};

        # store time info
        $self->{session_obj}->{tla} = now();
        $self->{session_obj}->{ttl} = $self->{ttl};

        # sync all session data
        while ( my ( $key, $value ) = each( %{ $self->{session_obj} } ) ) {
            $self->{session_view}->{$key} = $value;
        }
    }

    # checks that _session_id has been obtained and synced correctly
    #if ($self->{active}) {
    #    assert($id eq $self->{session_view}->{_session_id});
    #}
    return 1;
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
#        CLASS:  SGX::Session
#       METHOD:  restore
#   PARAMETERS:  ????
#      RETURNS:  Returns the same value as safe_tie (meaning an old session was found
#                but not necessarily validated and attached to). For the status of the
#                currect session, use $self->{active}
#  DESCRIPTION:  If no session is active at the moment, attach to an old session.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub restore {

    my $self           = shift;
    my $old_session_id = $self->{session_id};
    if ( defined($old_session_id) && !$self->{active} ) {
        if ( $self->try_commence($old_session_id) ) {

            # successfully restored an old session. Now that old session
            # id is the same as the active session id, undefine the old.
            $self->{session_id} = undef;
            return 1;
        }

        #if (!$self->{active}) {
        #    # if restoring a saved session fails, create a new one
        #    $self->{session_id} = undef;
        #    $self->try_commence(undef);
        #}
    }
    return 0;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session
#       METHOD:  commence
#   PARAMETERS:  ????
#      RETURNS:  Returns 1 if a new session was commenced *within this subroutine*, 0
#                otherwise
#  DESCRIPTION:  If no session is active at the moment, commence a new one.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub commence {

    my $self = shift;
    if ( !$self->{active} ) {
        return $self->try_commence(undef);
    }
    return 0;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session
#       METHOD:  commit
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  commits the active session object to object store
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub commit {

    my $self = shift;
    if ( $self->{active} ) {
        untie( %{ $self->{session_obj} } );
        $self->{active} = 0;
        return 1;
    }
    return 0;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session
#       METHOD:  destroy
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  deletes all referenced sessions from object store in this order:
#                (1) delete active if it exists, (2) delete old if it exists
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub destroy {
    my $self = shift;

    # (1) delete active if it exists
    if ( $self->{active} ) {
        $self->delete_object();

        # clear copied session data
        undef %{ $self->{session_view} };

        #while ( my ( $key, $value ) = each( %{ $self->{session_view} } ) ) {
        #    $self->{session_view}->{$key} = undef;
        #}
    }

    # (2) delete old if it exists
    my $old_session_id = $self->{session_id};
    if ( defined($old_session_id) ) {

        # Warning: if we do not check whether {old_session_id} is defined,
        # an undef will be passed to safe_tie and a new session will be
        # commenced as a result -- only to be deleted in the current block.
        if ( $self->safe_tie($old_session_id) ) {
            $self->delete_object();

            #$self->{session_id} = undef;
        }
    }
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session
#       METHOD:  delete_object
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  no status/error checking in this subroutine -- use with caution
#     SEE ALSO:  n/a
#===============================================================================
sub delete_object {

    my $self = shift;
    $self->expire_session();
    untie( %{ $self->{session_obj} } );

    #tied( %{ $self->{session_obj} } )->delete();
    $self->{active} = 0;
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Session
#       METHOD:  fresh
#   PARAMETERS:  ????
#      RETURNS:  Returns 1 if a new session was commenced *within this subroutine*, 0
#                otherwise
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub fresh {

    my $self = shift;
    $self->destroy;

    # commence a new session
    return $self->try_commence(undef);
}
1;    # for require

__END__
