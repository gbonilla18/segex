
=head1 NAME

SGX::Cookie

=head1 SYNOPSIS

  use SGX::Cookie;

  # create an instance:
  # -   $dbh must be an active database handle
  # -   3600 is 60 * 60 s = 1 hour (session time to live)
  # -   check_ip determines whether user IP is verified
  # -   cookie_name can be anything
  #
  my $s = SGX::Cookie->new(-handle          =>$dbh, 
                       -expire_in       =>3600,
                       -check_ip        =>1,
                       -cookie_name    =>'chocolate_chip');

  # restore previous session if it exists
  $s->restore;

  # delete previous session, active session, or both if both exist
  $s->destroy;

  $s->commit;    # necessary to make a cookie. Also flushes the session data

  # can set another cookie by opening another session like this:
  my $t = SGX::Cookie->new(-cookie_name=>'girlscout_mint', -handle=>$dbh, -expire_in=>3600*48, -check_ip=> 0);
  if (!$t->restore) $t->open;
  $t->commit;

  # You can create several instances of this class at the same time. The 
  # @SGX::Cookie::cookies array will contain the cookies created by all instances
  # of the SGX::User or SGX::Cookie classes. If the array reference is sent to CGI::header, for 
  # example, as many cookies will be created as there are members in the array.
  #
  # To send a cookie to the user:
  $q = new CGI;
  print $q->header(-type=>'text/html', -cookie=>\@SGX::Cookie::cookies);

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

$VERSION = '0.09';
$VERSION = eval $VERSION;

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

sub new {

    # This is the constructor
    my $class = shift;

    # The `active' property is temporary, until I find a more reliable
    # way to tell whether a session is active.

    my %p = @_;

    my %cookies = fetch CGI::Cookie;
    my $id;
    eval { $id = $cookies{ $p{-cookie_name} }->value; };

    my $self = {
        dbh            => $p{-handle},
        ttl            => $p{-expire_in},
        check_ip       => $p{-check_ip},
        old_session_id => $id,
        cookie_name    => $p{-cookie_name},
        active         => 0,
        object         => {},
        data           => {}
    };
    bless $self, $class;
    return $self;
}

sub commit {

    # calls the parent method and bakes a cookie on success
    my $self = shift;
    if ( $self->SUPER::commit ) {
        push @cookies, new CGI::Cookie(
            -name  => $self->{cookie_name},
            -value => $self->{data}->{_session_id},
            -path  => dirname( $ENV{SCRIPT_NAME} )
        );

        #   -domain    => $ENV{SERVER_NAME},
        #warn Dumper(\@cookies);
    }
}
1;    # for require

__END__
