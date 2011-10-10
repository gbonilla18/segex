package SGX::Util;

use strict;
use warnings;
use base qw/Exporter/;

use List::Util qw/min max/;
use Scalar::Util qw/looks_like_number/;

our @EXPORT_OK =
  qw/trim max min bounds label_format replace all_match count_gtzero
  inherit_hash enum_array/;

#===  FUNCTION  ================================================================
#         NAME:  all_empty
#      PURPOSE:  Generates a function that checks whether all element of an
#                array conform to some predefined regular expression.
#   PARAMETERS:  REQUIRED
#                qr//
#                   regular expression in precompiled form
#                OPTIONAL
#                ignore_undef => T/F
#                   (default: false). If true, the resulting function will not
#                   check undefined values for a match to the provided regex
#                   (undefined values have no effect); if false, will the
#                   resulting function will return false when it encounters such
#                   values.
#      RETURNS:  True/False
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  This is a higher-order function. It is similar to every()
#                array method in ECMAScript 5 / Javascript 1.6. Like its
#                Javascript counterpart, it returns true when run on a
#                zero-length array (of no elements).
#
#                # Example usage:
#                my $foo = all_match(qr/^\s*$/);
#                $foo->();                       # true
#                $foo->('', ' ', "\n");          # true
#                $foo->('', 'foo');              # false
#                $foo->('', undef);              # false
#
#                my $bar = all_match(qr/^\s*$/, ignore_undef => 1);
#                $bar->();                       # true
#                $bar->('', undef);              # true
#                $bar->('', 'foo');              # false
#
#     SEE ALSO:
# https://developer.mozilla.org/en/JavaScript/Reference/Global_Objects/Array/every
#===============================================================================
sub all_match {
    my ( $regex, %args ) = @_;
    return ( $args{ignore_undef} )
      ? sub { !defined || m/$regex/ || return for @_; return 1 }
      : sub { ( defined && m/$regex/ ) || return for @_; return 1 };
}

#===  FUNCTION  ================================================================
#         NAME:  count_gtzero
#      PURPOSE:  Returns the number of elements in the argument array that are
#                greater than zero, ignoring undefined values
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  This function is conceptually similar to Javascript some()
#                array method.
#     SEE ALSO:
# https://developer.mozilla.org/en/JavaScript/Reference/Global_Objects/Array/some
#===============================================================================
sub count_gtzero { my $c = 0; defined && $_ > 0 && $c++ for @_; return $c }

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
#      PURPOSE:  returns the bounds of an array, ignoring undefined values
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub bounds {
    my $defined_only = [ grep { defined } @_ ];
    return ( min(@$defined_only), max(@$defined_only) );
}

#===  FUNCTION  ================================================================
#         NAME:  label_format
#      PURPOSE:  choose "nice" numbers, for example for making labels on plots
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  First rounds the number to only one significant figure, then
#                further rounds the significant figure to 1, 2, 5, or 10.
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
    if ( $fig < 3 ) {

        # do nothing here
        # 0 => 0
        # 1 => 1
        # 2 => 2
    }
    elsif ( $fig < 4 ) {

        # 3 => 2
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
sub trim {
    my $string = shift;

    $string =~ s/^\s*//;
    $string =~ s/\s*$//;

    return $string;
}

#===  FUNCTION  ================================================================
#         NAME:  inherit_hash
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Designed such that it could also be read as:
#                $x->inherit_hash({}). Hash %$x overrides keys present in %$y
#                unless those keys are other hashes, in which case the function
#                descends recursively. %$y is not modified; %$x is. Also
#                allowing syntax:
#
#                my $x = inherit_hash({ prop1 => 'val2'}, { prop2 => 'val2'});
#
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub inherit_hash {
    my ( $x, $y ) = @_;
    foreach my $ykey ( keys %$y ) {
        my $yval = $y->{$ykey};
        if ( exists $x->{$ykey} ) {
            my $xval = $x->{$ykey};
            if ( ref $yval eq 'HASH' and ref $xval eq 'HASH' ) {
                inherit_hash( $xval, $yval );
            }
        }
        else {
            $x->{$ykey} = $yval;
        }
    }
    return $x;
}

#===  FUNCTION  ================================================================
#         NAME:  enum_array
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub enum_array {
    my $i = 0;
    return +{ map { $_ => $i++ } @$_ };
}

1;
