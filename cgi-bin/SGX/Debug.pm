package SGX::Debug;

# This is a module for any debugging or testing subroutines.
# Expect any code you put in here to be removed from the production version.

use strict;
use warnings;
use base qw(Exporter);

use Carp::Assert;

#use constant LOG_PATH => '/var/www/error_log/error_log'; # Linux
use constant LOG_PATH => '/Users/escherba/log/apache2/segex_dev_log'; # Mac OS X

BEGIN {
    use CGI::Carp qw(carpout fatalsToBrowser warningsToBrowser croak);
    open( my $LOG, '>>', LOG_PATH )
      or croak 'Unable to append to log file at ' . LOG_PATH . " $!";
    carpout($LOG);
}

our @EXPORT = qw(assert);

1;
