package SGX::Config;

# Don't forget to put the names of your exported subroutines into the EXPORT array

use strict;
use warnings;
use base qw/Exporter/;

#use lib '/opt/local/lib/perl5/site_perl/5.8.8';
#use lib '/opt/local/lib/perl5/site_perl/5.8.8/darwin-2level';

use File::Basename;
use List::Util qw/min max/;
use CGI::Carp qw/croak/;

#use DBI;

# CGI::Carp module sends warnings and errors to the browser;
# this is for debugging purposes only -- it will be removed in
# production code.
#BEGIN {
#    use CGI::Carp qw/carpout fatalsToBrowser warningsToBrowser/;
#    open(LOG, ">>/Users/junior/log/error_log")
#        or die "Unable to append to error_log: $!";
#    carpout(*LOG);
#}

our @EXPORT =
  qw/max min bounds label_format mysql_connect PROJECT_NAME CGI_ROOT YUI_ROOT DOCUMENTS_ROOT IMAGES_DIR JS_DIR CSS_DIR SPECIES/;

sub mysql_connect {

    # connects to the database and returns the handle
    my $dbh =
         DBI->connect( 'dbi:mysql:segex_dev', 'segex_dev_user', 'b00g3yk1d' )
      or croak $DBI::errstr;
    return $dbh;
}

#===  FUNCTION  ================================================================
#         NAME:  replace
#      PURPOSE:  Syntatic sugar for the replace regular expression;
#                allows for writing a one-liner:
#                  $a = regexp($b, $text_to_match, $replacement);
#                instead of the usual two lines:
#                  $a = $b;
#                  $a =~ s/$text_to_match/$replacement/;
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub replace {
    my ( $var, $match, $replacement ) = @_;
    $var =~ s/$match/$replacement/x;
    return $var;
}

use constant PROJECT_NAME => 'SEGEX';
use constant SPECIES      => 'mouse';    # hardcoding species for now

# convert cgi root to documents root by dropping /cgi-bin prefix
use constant CGI_ROOT => dirname( $ENV{SCRIPT_NAME} );    # current script path
use constant DOCUMENTS_ROOT => replace( CGI_ROOT, '^\/cgi-bin', '' );
use constant YUI_ROOT       => '/yui';

use constant IMAGES_DIR => DOCUMENTS_ROOT . '/images';
use constant JS_DIR     => DOCUMENTS_ROOT . '/js';
use constant CSS_DIR    => DOCUMENTS_ROOT . '/css';

# ===== VARIOUS FUNCTIONS (NOT STRICTLY CONFIGURATION CODE =========================

#sub max {
#
#    # returns the greatest value in a list
#    my $max = shift;
#    foreach (@_) {
#        $max = $_ if $_ > $max;
#    }
#    return $max;
#}
#
#sub min {
#
#    # returns the smallest value in a list
#    my $min = shift;
#    foreach (@_) {
#        $min = $_ if $_ < $min;
#    }
#    return $min;
#}

sub bounds {

    # returns the bounds of an array,
    # assuming undefined values to be zero
    my $a    = shift;
    my $mina = ( defined( $a->[0] ) ) ? $a->[0] : 0;
    my $maxa = $mina;
    for ( my $i = 1 ; $i < @$a ; $i++ ) {
        my $val = ( defined( $a->[$i] ) ) ? $a->[$i] : 0;
        if    ( $val < $mina ) { $mina = $val }
        elsif ( $val > $maxa ) { $maxa = $val }
    }
    return ( $mina, $maxa );
}

sub label_format {

    # first rounds the number to only one significant figure,
    # then further rounds the significant figure to 1, 2, 5, or 10
    # (useful for making labels for graphs)
    my $num = shift;
    $num = sprintf( '%e', sprintf( '%.1g', $num ) );
    my $fig = substr( $num, 0, 1 );
    my $remainder = substr( $num, 1 );

    # choose "nice" numbers:
    if ( $fig < 2 ) {

        # 1 => 1
        # do nothing here
    }
    elsif ( $fig < 4 ) {

        # 2, 3 => 1
        $fig = 2;
    }
    elsif ( $fig < 8 ) {

        # 4, 5, 6, 7 => 5
        $fig = 5;
    }
    else {

        # 8, 9 => 10
        $fig = 10;
    }
    return $fig . $remainder;
}

1;
