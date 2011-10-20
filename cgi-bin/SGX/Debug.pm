package SGX::Debug;

use strict;
use warnings;

#use Time::HiRes qw/clock/;
#use Benchmark;
use Data::Dumper qw/Dumper/;

use base qw/Exporter/;
our @EXPORT = qw/dump_cookies_sent_to_user print_truth_table Dumper/;

BEGIN {
    use CGI::Carp qw/carpout fatalsToBrowser warningsToBrowser croak/;
    use Carp qw/carp/;
#---------------------------------------------------------------------------
#  Log the location of warnings which is sometimes not reported without the
#  below signal handler. For example, without handler often see: 
#
#  [Thu Oct 20 14:49:04 2011] index.cgi: Use of uninitialized value $rest[0] in
#  join or string at (eval 65) line 15.
#
#  With the __WARN__ handler, however:
#
#  Warning generated at line 94 in SGX/Body.pm:
#  Use of uninitialized value $rest[0] in join or string at (eval 65) line 15.
#
#---------------------------------------------------------------------------
    $SIG{__WARN__} = sub {
        my @loc = caller(1);
        warn "Warning generated at line $loc[2] in $loc[1]:\n", @_, "\n";
        return 1;
    };

    #use constant LOG_PATH => '/var/www/error_log/segex_dev_log'; # Linux
    use constant LOG_PATH =>
      '/Users/escherba/log/apache2/segex_dev_log';    # Mac OS X

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
    my $s = shift;

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

__END__

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
