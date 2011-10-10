#
#===============================================================================
#
#         FILE:  Debug.pm
#
#  DESCRIPTION:  This is a module for any debugging or testing subroutines.
#                Expect any code you put in here to be removed from the
#                production version.
#                Avoid adding exported symbols to this module -- and if you do
#                add them, structure your code such that it would still
#                function when this module is removed.
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Eugene Scherba (es), escherba@gmail.com
#      COMPANY:  Boston University
#      VERSION:  1.0
#      CREATED:
#     REVISION:  ---
#===============================================================================
package SGX::Debug;

use strict;
use warnings;

#use Time::HiRes qw/clock/;
#use Benchmark;
use Data::Dumper;

use base qw/Exporter/;
our @EXPORT = qw/dump_cookies_sent_to_user print_truth_table Dumper/;

#use constant LOG_PATH => '/var/www/error_log/segex_dev_log'; # Linux
use constant LOG_PATH => '/Users/escherba/log/apache2/segex_dev_log'; # Mac OS X

BEGIN {
    use CGI::Carp qw(carpout fatalsToBrowser warningsToBrowser croak);
    open( my $LOG, '>>', LOG_PATH )
      or croak 'Unable to append to log file at ' . LOG_PATH . " $!";
    carpout($LOG);
}

#===  FUNCTION  ================================================================
#         NAME:  print_truth_table
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub print_truth_table {
    return join( ' ', map { $_ ? 1 : 0 } @_ );
}

#===  FUNCTION  ================================================================
#         NAME:  get_cookies_sent_to_user
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub dump_cookies_sent_to_user {
    my ($s) = @_;

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

1;
