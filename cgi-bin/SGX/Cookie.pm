
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

    my $self = {
        dbh             => $p{-handle},
        ttl             => $p{-expire_in},
        check_ip        => $p{-check_ip},
        fetched_cookies => \%cookies,
        session_name    => 'session',
        session_obj     => {},
        session_view    => {},
        active          => 0
    };

    # in scalar context, the result of CGI::Cookie::value is a scalar
    my $session_id = eval { $cookies{ $self->{session_name} }->value };
    $self->{session_id} = $session_id;

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Cookie
#       METHOD:  commit
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  calls the parent method and bakes a cookie on success
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub commit {

    my $self = shift;
    if ( $self->SUPER::commit() ) {
        push @cookies,
          CGI::Cookie->new(
            -name     => $self->{session_name},
            -value    => $self->{session_view}->{_session_id},
            -path     => dirname( $ENV{SCRIPT_NAME} ),
            -httponly => 1
          );

        #   -domain    => $ENV{SERVER_NAME},
        #warn Dumper(\@cookies);
    }
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Cookie
#       METHOD:  add_perm_cookie
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub add_perm_cookie {
    my ( $self, $cookie_name, %p ) = @_;
    push @cookies,
      CGI::Cookie->new(
        -name     => $cookie_name,
        -value    => \%p,
        -path     => dirname( $ENV{SCRIPT_NAME} ),
        -httponly => 1,
        -expires  => '+3M'
      );
}

1;    # for require

__END__
