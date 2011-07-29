package SGX::Util;

use strict;
use warnings;
use base qw/Exporter/;

use List::Util qw/min max/;
use URI::Escape;
use JSON;
use SGX::Exceptions;
use Scalar::Util qw/looks_like_number/;

our @EXPORT_OK =
  qw/trim max min bounds label_format replace all_match declare_js_var/;

#===  FUNCTION  ================================================================
#         NAME:  declare_js_var
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  :TODO:07/29/2011 15:23:00:es: use either a closure or
#                object-oriented interface to initialize a JSON object at the
#                beginning and then reuse it during calls. Also allow setting
#                options such as whether to insert new line characters, for
#                example.
#     SEE ALSO:  n/a
#===============================================================================
sub declare_js_var {
    my ($href) = @_;
    my @ret;

    my $json = JSON->new->allow_nonref;
    while ( my ( $key, $value ) = each %$href ) {

# check all keys for ECMA 262 validity -- whether they can be used as
# valid Javascript variable names:
# http://stackoverflow.com/questions/1661197/valid-characters-for-javascript-variable-names
        if ( $key !~ m/^[a-zA-Z_\$][0-9a-zA-Z_\$]*$/ ) {
            SGX::Exception::Internal->throw( error =>
"Cannot form Javascript: Variable name $key does not comply with ECMA 262\n"
            );
        }
        my $value_reftype = ref $value;
        my $encoded_value;
        if ( $value_reftype eq '' ) {

            # direct scalar
            $encoded_value =
              ( looks_like_number($value) )
              ? trim($value)
              : ( ( defined $value ) ? $json->encode($value) : 'undefined' );
        }
        elsif ( $value_reftype eq 'SCALAR' ) {

            # referenced scalar
            $encoded_value =
              ( looks_like_number($$value) )
              ? trim($$value)
              : ( ( defined $$value ) ? $json->encode($$value) : 'undefined' );
        }
        elsif ( $value_reftype eq 'ARRAY' or $value_reftype eq 'HASH' ) {

            # array or hash reference
            $encoded_value = $json->encode($value);
        }
        else {
            SGX::Exception::Internal->throw( error =>
"Cannot form Javascript: do not know how to handle Perl literals having ref eq $value_reftype\n"
            );
        }
        push @ret, sprintf( 'var %s=%s;', $key, $encoded_value );
    }

    return join( "\n", @ret ) . "\n";
}

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
#     COMMENTS:  This is a higher-order function. Returns true when run on a
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
#     SEE ALSO:  n/a
#===============================================================================
sub all_match {
    my ( $regex, %args ) = @_;
    return ( $args{ignore_undef} )
      ? sub { !defined || m/$regex/ || return for @_; return 1 }
      : sub { ( defined && m/$regex/ ) || return for @_; return 1 };
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
#      PURPOSE:  choose "nice" numbers, for example for making labels on plots
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  first rounds the number to only one significant figure, then further
#                rounds the significant figure to 1, 2, 5, or 10
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

1;
