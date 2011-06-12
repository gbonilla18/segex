
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
use CGI::Carp qw/croak/;

#use Data::Dumper;    # for debugging

# Variables declared as "our" within a class (package) scope will be shared between
# all instances of the class *and* can be addressed from the outside like so:
#
#   my $var = $PackageName::var;
#   my $array_reference = \@PackageName::array;
#

sub new {

    # This is the constructor
    my ($class, %p) = @_;

    # :TODO:06/05/2011 22:48:28:es: figure out a more reliable way to
    # tell whether a session is active than relying on the `active'
    # property.

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

# returns 1 if a new session was commenced or an old one restored *by this subroutine*, 0 otherwise
    my ( $self, $id ) = @_;
    if ( $self->{active} ) {
        croak 'Cannot tie to session hash: another session is currently active';
    }
    my $ret = eval {
        tie %{ $self->{object} }, 'Apache::Session::MySQL', $id,
          {
            Handle     => $self->{dbh},
            LockHandle => $self->{dbh},
          };
    };
    if (!$ret || $@) {
        # error
        #carp "Could not tie session object (session id: $@)";
        return 0;
    };

    # no error
    $self->{active} = 1;
    return 1;
}

sub try_commence {

    # returns the same value as safe_tie
    my ( $self, $id ) = @_;
    if ( $self->safe_tie($id) ) {
        if ( defined($id) ) {

            # old session has been restored
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

            # new session has been commenced
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
        if ( $self->try_commence( $self->{old_session_id} ) ) {

            # successfully restored an old session. Now that old session
            # id is the same as the active session id, undefine the old.
            assert( $self->{old_session_id} eq $self->{data}->{_session_id} )
              if $self->{active};
            $self->{old_session_id} = undef;
            return 1;
        }

        #if (!$self->{active}) {
        #    # if restoring a saved session fails, create a new one
        #    $self->{old_session_id} = undef;
        #    $self->try_commence(undef);
        #}
    }
    return 0;
}

sub commence {

   # If no session is active at the moment, commence a new one.
   # Returns 1 if a new session was commenced *within this subroutine*, 0 otherwise
    my $self = shift;
    if ( !$self->{active} ) {
        return $self->try_commence(undef);
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
        $self->delete_object();

        # set all copied session data to undef
        while ( my ( $key, $value ) = each( %{ $self->{data} } ) ) {
            $self->{data}->{$key} = undef;
        }
    }

    # (2) delete old if it exists
    if ( defined( $self->{old_session_id} ) ) {

        # Warning: if we do not check whether {old_session_id} is defined,
        # an undef will be passed to safe_tie and a new session will be
        # commenced as a result -- only to be deleted in the current block.
        if ( $self->safe_tie( $self->{old_session_id} ) ) {
            $self->delete_object();
            $self->{old_session_id} = undef;
        }
    }
    return;
}

sub delete_object {

    # no status/error checking in this subroutine -- use with caution
    my $self = shift;
    tied( %{ $self->{object} } )->delete();
    $self->{active} = 0;
    return;
}

sub fresh {

   # Returns 1 if a new session was commenced *within this subroutine*, 0 otherwise
    my $self = shift;
    $self->destroy;

    # commence a new session
    return $self->try_commence(undef);
}
1;    # for require

__END__
