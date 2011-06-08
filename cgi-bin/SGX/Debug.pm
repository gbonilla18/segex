package SGX::Debug;

# This is a module for any debugging or testing subroutines.
# Expect any code you put in here to be removed from the production version.
# Don't forget to put the names of your exported subroutines into the EXPORT array

use strict;
use warnings;
use base qw(Exporter);

use Carp::Assert;

#use constant LOG_PATH => '/var/www/error_log/error_log'; # Linux
use constant LOG_PATH => '/Users/escherba/log/apache2/segex_dev_log'; # Mac OS X

# CGI::Carp module sends warnings and errors to the browser;
# this is for debugging purposes only -- it will be removed in
# production code.
BEGIN {
    use CGI::Carp qw(carpout fatalsToBrowser warningsToBrowser croak);
    open( LOG, '>>', LOG_PATH )
      or croak 'Unable to append to log file at ' . LOG_PATH . " $!";
    carpout(*LOG);
}

our @EXPORT = qw(assert);

1;
