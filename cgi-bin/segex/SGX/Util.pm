package SGX::Util;

use strict;
use warnings;
use base qw/Exporter/;

our @EXPORT_OK = qw/trim label_format replace build_matchp inherit_hash
list_keys list_values tuples car cdr equal notp file_opts_html file_opts_columns
dec2indexes32 coord2int writeFlags count_bits before_dot uniq uniq_i
format_phrase/; 

#===  FUNCTION  ================================================================
#         NAME:  format_phrase
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Strip spaces from beginning and end, also replace all multiple
#  spaces and space-like characters with a single space. Return undef if
#  undefined.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub format_phrase {
    my $phrase = shift;
    return undef unless defined $phrase;    ## no critic
    if ( $phrase =~ m/^\s*(.+)\s*$/ ) {
        $phrase = $1;

        # also replace all multiple spaces and space-like characters with a
        # single white space.
        $phrase =~ s/\s+/ /g;
    }
    else {
        $phrase = '';
    }
    return $phrase;
}

#===  FUNCTION  ================================================================
#         NAME:  uniq
#      PURPOSE:  Extract unique elements from an array
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub uniq {    ## no critic
    my %seen;
    return grep { !$seen{$_}++ } @_;
}

#===  FUNCTION  ================================================================
#         NAME:  uniq_i
#      PURPOSE:  Case-insensitive version of uniq()
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub uniq_i {    ## no critic
    my %seen;
    return grep { !$seen{ lc($_) }++ } @_;
}

#===  FUNCTION  ================================================================
#         NAME:  before_dot
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub before_dot {
    my $x = shift;
    my @arr = split( '\.', "$x" );
    return $arr[0];
}

#===  FUNCTION  ================================================================
#         NAME:  writeFlags
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub writeFlags {    ## no critic
    my $flagsum = 0;
    for ( my $i = 0 ; $i < @_ ; $i++ ) {
        if ( $_[$i] ) {
            $flagsum |= ( 1 << $i );
        }
    }
    return $flagsum;
}

#===  FUNCTION  ================================================================
#         NAME:  coord2int
#      PURPOSE:  Convert string coordinate into unsigned integer
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub coord2int {
    my $coord = shift;
    $coord = '' if not defined $coord;
    $coord =~ tr/,//d;    # rid of thousands separators
    if ( $coord =~ m/^\+*(\d+)$/ ) {
        return int($1);
    }
    else {
        return;
    }
}

#===  FUNCTION  ================================================================
#         NAME:  dec2indexes
#      PURPOSE:  Convert decimal number to an array of indexes corresponding to
#                set bits.
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Can also use Bit::Vector package
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub dec2indexes32 {
    my @a = reverse( split( '', unpack( 'B32', pack( 'N', shift ) ) ) );
    return grep { $a[$_] } 0 .. $#a;
}

#===  FUNCTION  ================================================================
#         NAME:  build_matchp
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
#  DESCRIPTION:  Build match predicate
#       THROWS:  no exceptions
#     COMMENTS:  This is a higher-order function. It is similar to every()
#                array method in ECMAScript 5 / Javascript 1.6. Like its
#                Javascript counterpart, it returns true when run on a
#                zero-length array (of no elements).
#
#                # Example usage:
#                my $foo = build_matchp(qr/^\s*$/);
#                $foo->();                       # true
#                $foo->('', ' ', "\n");          # true
#                $foo->('', 'foo');              # false
#                $foo->('', undef);              # false
#
#                my $bar = build_matchp(qr/^\s*$/, ignore_undef => 1);
#                $bar->();                       # true
#                $bar->('', undef);              # true
#                $bar->('', 'foo');              # false
#
#     SEE ALSO:
# https://developer.mozilla.org/en/JavaScript/Reference/Global_Objects/Array/every
#===============================================================================
sub build_matchp {
    my ( $regex, %args ) = @_;
    return ( $args{ignore_undef} )
      ? sub { !defined || m/$regex/ || return for @_; return 1 }
      : sub { ( defined && m/$regex/ ) || return for @_; return 1 };
}

#===  FUNCTION  ================================================================
#         NAME:  is_false
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  'not' predicate
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub notp {    ## no critic
    !$_ || return for @_;
    return 1;
}

#===  FUNCTION  ================================================================
#         NAME:  print_truth_table
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  For debugging only
#     SEE ALSO:  n/a
#===============================================================================
sub print_truth_table {    ## no critic
    return join( ' ', map { $_ ? 1 : 0 } @_ );
}

#===  FUNCTION  ================================================================
#         NAME:  equal
#      PURPOSE:  Check whether all members of a list are equal to each other
#   PARAMETERS:  ????
#      RETURNS:  Returns first member if yes, empty list if otherwise
#  DESCRIPTION:  eq predicate
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub equal {    ## no critic
    my $first = shift;
    return unless defined $first;
    defined($_) && $first eq $_ || return for @_;
    return 1;
}

#===  FUNCTION  ================================================================
#         NAME:  count_bits
#      PURPOSE:  Count number of '1'-s in binary representation of number
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub count_bits {
    return unpack( '%32b*', pack( 'I', shift ) );
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
    if ( defined $string ) {
        $string =~ s/^\s*//;
        $string =~ s/\s*$//;
    }
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
    my ( $x, $y ) = ( shift || {}, shift || {} );
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
#         NAME:  tuples
#      PURPOSE:
#   PARAMETERS:  anonymous array
#      RETURNS:  ????
#  DESCRIPTION:  Takes a list and returns a list of tuples composed of elements
#                of the list arranged in pairs.
#       THROWS:  no exceptions
#     COMMENTS:  if main argument is undef, map it to empty list.
#     SEE ALSO:  n/a
#===============================================================================
sub tuples {
    use integer;
    my $list = shift || [];
    return unless @$list;
    return
      map { [ $list->[ $_ + $_ ] => $list->[ $_ + $_ + 1 ] ] }
      0 .. ( $#$list / 2 );
}

#===  FUNCTION  ================================================================
#         NAME:  list_keys
#      PURPOSE:  analogue to built-in keys function, except for lists, not
#                hashes
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub list_keys {    ## no critic
    return @_[ grep { !( $_ % 2 ) } 0 .. $#_ ];
}

#===  FUNCTION  ================================================================
#         NAME:  list_values
#      PURPOSE:  analogue to built-in values function, except for lists, not
#                hashes
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub list_values {    ## no critic
    return @_[ grep { $_ % 2 } 0 .. $#_ ];
}

#===  FUNCTION  ================================================================
#         NAME:  car
#      PURPOSE:  return first element (head) of an array (list)
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  car List -> Atom
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  http://okmij.org/ftp/Perl/Scheme-in-Perl.txt
#===============================================================================
sub car {
    return shift;
}

#===  FUNCTION  ================================================================
#         NAME:  cdr
#      PURPOSE:  return tail of an array (list)
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  cdr List -> List
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  http://okmij.org/ftp/Perl/Scheme-in-Perl.txt
#===============================================================================
sub cdr {    ## no critic
    shift;
    return @_;
}

#===  FUNCTION  ================================================================
#         NAME:  cgi_file_opts
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub file_opts_html {
    my $q  = shift;
    my $id = shift;
    return $q->p(
        $q->a(
            {
                -id    => $id,
                -class => 'pluscol',
                -title => 'Click to specify file format'
            },
            '+ File options'
        )
      )
      . $q->div(
        {
            -id    => "${id}_container",
            -class => 'dd_collapsible',
        },
        $q->p(
            $q->radio_group(
                -name   => 'separator',
                -values => [ "\t", ',' ],
                -labels => {
                    ','  => 'Comma-separated',
                    "\t" => 'Tab-separated'
                },
                -default => (
                    defined $q->param('separator')
                    ? $q->param('separator')
                    : "\t"
                )
            )
        ),
        $q->p(
            $q->checkbox(
                -name     => 'header',
                -checked  => ( defined( $q->param('header') ) ? 1 : 0 ),
                -label    => 'First line is a header',
                -override => 1
            )
        )
      );
}

#===  FUNCTION  ================================================================
#         NAME:  file_opts_columns
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub file_opts_columns {
    my ( $q, %args ) = @_;

    my $id    = $args{id};
    my $items = $args{items};
    return $q->p(
        $q->a(
            {
                -id    => $id,
                -class => 'pluscol',
                -title => 'Click to customize which columns to upload'
            },
            '+ Columns in file'
        )
      ),
      $q->div(
        { -id => "${id}_container", -class => 'dd_collapsible' },
        (
            (
                map {    ## no critic
                    my ( $key, $val ) = @$_;
                    my $title = $val->{-title} || ( $val->{-value} || $key );
                    $q->input(
                        {
                            -type  => 'checkbox',
                            -name  => $key,
                            -title => $title,
                            %$val
                        }
                      )
                  } tuples($items)
            ),

            # preserve state of radio buttons
            $q->input( { -type => 'hidden', -id => "${id}_state" } )
        ),
        $q->div(
            {
                -class => 'hint visible',
                -id    => "${id}_hint"
            },
            ''
        )
      );
}


1;
