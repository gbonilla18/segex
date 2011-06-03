
=head1 NAME

SGX::Session

=head1 SYNOPSIS

  use SGX::Session;

  # create an instance:
  # -    $dbh must be an active database handle
  # -    3600 is 60 * 60 s = 1 hour (session time to live)
  # -   check_ip determines whether user IP is verified
  # -   id is old session id (either from a cookie or from a query string)
  #
  my $s = SGX::Session->new(-handle        =>$dbh, 
               -expire_in    =>3600,
               -check_ip    =>1,
               -id        =>'1c287c065fc22df74e3e57c63ceedd20');

  # restore previous session if it exists
  $s->restore;

  # delete previous session, active session, or both if both exist
  $s->destroy;

  $s->commit;    # flushes the session data (writes to data store)

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

$VERSION = '0.09';
$VERSION = eval $VERSION;

use Apache::Session::MySQL;
use SGX::Debug;

#use Data::Dumper;    # for debugging

# Variables declared as "our" within a class (package) scope will be shared between
# all instances of the class *and* can be addressed from the outside like so:
#
#   my $var = $PackageName::var;
#   my $array_reference = \@PackageName::array;
#

sub new {

    # This is the constructor
    my $class = shift;

    # The `active' property is temporary, until I find a more reliable
    # way to tell whether a session is active.

    my %p = @_;

    my $self = {
        dbh            => $p{-handle},
        ttl            => $p{-expire_in},
        check_ip       => $p{-check_ip},
        old_session_id => $p{-id},
        active         => 0,
        object         => {},
        data           => {}
    };
    bless $self, $class;
    return $self;
}

sub safe_tie {

# returns 1 if a new session was opened or an old one restored *by this subroutine*, 0 otherwise
    my ( $self, $id ) = @_;
    if ( $self->{active} ) {
        die('Cannot tie to session hash: another session is currently active');
    }
    else {
        eval {
            tie %{ $self->{object} }, 'Apache::Session::MySQL', $id,
              {
                Handle     => $self->{dbh},
                LockHandle => $self->{dbh},
              };
        };
        if ( !$@ ) {

            # no error
            $self->{active} = 1;
            return 1;
        }
    }
    return 0;
}

sub try_open {

    # returns the same value as safe_tie
    my ( $self, $id ) = @_;
    if ( $self->safe_tie($id) ) {
        if ( defined($id) ) {

            # old session was opened
            if (   $self->{object}->{tla} + $self->{object}->{ttl} < $self->now
                || $self->{check_ip}
                && $ENV{REMOTE_ADDR} ne $self->{object}->{ip} )
            {

       # delete if tla + ttl < cur_time or if user IP doesn't match stored value
                $self->delete_object;
            }
            else {

                # update TLA (time last accessed)
                $self->{object}->{tla} = $self->now;

                # sync all session data
                while ( my ( $key, $value ) = each( %{ $self->{object} } ) ) {
                    $self->{data}->{$key} = $value;
                }
            }
        }
        else {

            # new session was opened
            # store remote user IP address if ip_check is set to 1
            $self->{object}->{ip} = $ENV{REMOTE_ADDR} if $self->{check_ip};

            # store time info
            $self->{object}->{tla} = $self->now;
            $self->{object}->{ttl} = $self->{ttl};

            # sync all session data
            while ( my ( $key, $value ) = each( %{ $self->{object} } ) ) {
                $self->{data}->{$key} = $value;
            }
        }
        return 1;
    }
    return 0;
}

sub now {

# MySQL timestamp format:
#my @t = localtime();
#sprintf('%04d-%02d-%02d %02d:%02d:%02d',$t[5]+1900,$t[4]+1,$t[3],$t[2],$t[1],$t[0]);
    return time;
}

sub restore {

# If no session is active at the moment, attach to an old session.
# Returns the same value as safe_tie (meaning an old session was found but not
# necessarily validated and attached to). For the status of the currect session,
# use $self->{active}.
    my $self = shift;
    if ( defined( $self->{old_session_id} ) && !$self->{active} ) {
        if ( $self->try_open( $self->{old_session_id} ) ) {

            # successfully opened an old session. Now that old session
            # id is the same as the active session id, undefine the old.
            assert( $self->{old_session_id} eq $self->{data}->{_session_id} )
              if $self->{active};
            $self->{old_session_id} = undef;
            return 1;
        }

        #if (!$self->{active}) {
        #    # if opening a saved session fails, create a new one
        #    $self->{old_session_id} = undef;
        #    $self->try_open(undef);
        #}
    }
    return 0;
}

sub open {

   # If no session is active at the moment, open a new one.
   # Returns 1 if a new session was opened *within this subroutine*, 0 otherwise
    my $self = shift;
    if ( !$self->{active} ) {
        return $self->try_open(undef);
    }
    return 0;
}

sub commit {

    # commits the active session object to object store
    my $self = shift;
    if ( $self->{active} ) {
        untie( %{ $self->{object} } );
        $self->{active} = 0;
        return 1;
    }
    return 0;
}

sub destroy {
    my $self = shift;

    # deletes all referenced sessions from object store in this order:

    # (1) delete active if it exists
    if ( $self->{active} ) {
        $self->delete_object;

        # set all copied session data to undef
        while ( my ( $key, $value ) = each( %{ $self->{data} } ) ) {
            $self->{data}->{$key} = undef;
        }
    }

    # (2) delete old if it exists
    if ( defined( $self->{old_session_id} ) ) {

        # Warning: if we do not check whether {old_session_id} is defined,
        # an undef will be passed to safe_tie and a new session will be
        # opened as a result -- only to be deleted in the current block.
        if ( $self->safe_tie( $self->{old_session_id} ) ) {
            $self->delete_object;
            $self->{old_session_id} = undef;
        }
    }
}

sub delete_object {

    # no status/error checking in this subroutine -- use with caution
    my $self = shift;
    tied( %{ $self->{object} } )->delete;
    $self->{active} = 0;
}

sub fresh {

   # Returns 1 if a new session was opened *within this subroutine*, 0 otherwise
    my $self = shift;
    $self->destroy;

    # open a new session
    return $self->try_open(undef);
}
1;    # for require

__END__
