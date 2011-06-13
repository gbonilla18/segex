package SGX::Util;

use strict;
use warnings;
use base qw/Exporter/;

use List::Util qw/min max/;

our @EXPORT_OK =
  qw/trim max min bounds label_format replace/;

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
    $var =~ s/$match/$replacement/;
    return $var;
}

#===  FUNCTION  ================================================================
#         NAME:  bounds
#      PURPOSE:  returns the bounds of an array, assuming undefined values to be zero
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub bounds {

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

#===  FUNCTION  ================================================================
#         NAME:  label_format
#      PURPOSE:  first rounds the number to only one significant figure, then further
#                rounds the significant figure to 1, 2, 5, or 10 (useful for making
#                labels for graphs)
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub label_format {

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

#===  FUNCTION  ================================================================
#         NAME:  trim
#      PURPOSE:  remove whitespace from the beginning and the end of a string
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub trim
{
    my $string = shift;
    
    $string =~ s/^\s*//;
    $string =~ s/\s*$//;
    
    return $string;
}

1;
