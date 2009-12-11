package SGX::Debug;

# This is a module for any debugging or testing subroutines.
# Expect any code you put in here to be removed from the production version.
# Don't forget to put the names of your exported subroutines into the EXPORT array

use strict;
use warnings;
use base qw/Exporter/;
#use Data::Dumper;

# CGI::Carp module sends warnings and errors to the browser;
# this is for debugging purposes only -- it will be removed in
# production code.
BEGIN { 
        use CGI::Carp qw/carpout fatalsToBrowser warningsToBrowser/;
        open(LOG, '>>/www/html/images/students_09/group_2/error_log')
                or die "Unable to append to error_log: $!";
        carpout(*LOG);
}

our @EXPORT = qw/assert/;

sub assert {
        # this is similar to the equinomial C function except it also checks for undef status.
        my $arg = shift;
        if (!defined($arg) || !$arg) {
                # confess() from Carp module gives a traceback of callers.
                # Since confess() will do things like writing values of runtime variables (which can contain
                # passwords!) to the web server log, need to comment out the line below in production code
		# or remove the SGX::Debug module from the project
                confess 'Internal assertion failed: argument is undefined or condition is false';
        }
}

1;
