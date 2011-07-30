#
#===============================================================================
#
#         FILE:  JSEmitter.pm
#
#  DESCRIPTION:
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Eugene Scherba (es), escherba@gmail.com
#      COMPANY:  Boston University
#      VERSION:  1.0
#      CREATED:  07/30/2011 13:48:58
#     REVISION:  ---
#===============================================================================

package SGX::Abstract::JSEmitter;

use strict;
use warnings;

use JSON;
use SGX::Abstract::Exception;
use Scalar::Util qw/looks_like_number/;
use SGX::Util qw/trim/;

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Abstract::JS
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ( $class, %args ) = @_;

    my $self = {};
    bless $self, $class;

    $self->init(%args);

    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Abstract::JS
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Performs object initialization. Always called by new()
#                constructor but could also be called separately and after
#                object construction.
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my ( $self, %args ) = @_;

    # The optional 'pretty' input symbol overrides object property under the
    # same name. When neither the input symbol nor the corresponding object
    # property are set, use default value of 1.
    #
    my $arg_pretty = (
        exists $args{pretty}
        ? $args{pretty}
        : ( exists $self->{pretty} ? $self->{pretty} : 1 )
    );

    my $type_declaration = 'var ';
    $self->{assignment_operator} = ($arg_pretty) ? ' = ' : '=';
    $self->{line_terminator}     = ($arg_pretty) ? ";\n" : ';';
    $self->{type_declaration}    = $type_declaration;
    $self->{type_declaration_separator} =
      ($arg_pretty) ? ",\n" . ' ' x length($type_declaration) : ',';

    $self->{pretty} = $arg_pretty;

    # 'orcish' operator: assign value to property only if property evaluates to
    # false:
    $self->{json} ||= JSON->new->allow_nonref;

    return 1;
}

#===  FUNCTION  ================================================================
#         NAME:  _is_valid_ECMA262
#      PURPOSE:  check argument for ECMA 262 validity -- whether it can be used
#                as valid Javascript symbol.
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:
# http://stackoverflow.com/questions/1661197/valid-characters-for-javascript-variable-names
#===============================================================================
sub _is_valid_ECMA262 {
    my ($symbol) = @_;
    return ( $symbol =~ m/^[a-zA-Z_\$][0-9a-zA-Z_\$]*$/ );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Abstract::JS
#       METHOD:  encode
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Wrapper for JSON::encode
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub encode {
    my ( $self, $arg ) = @_;
    return $self->{json}->encode($arg);
}

#===  FUNCTION  ================================================================
#         NAME:  define
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  n/a
#     SEE ALSO:  n/a
#===============================================================================
sub define {
    my ( $self, $href, %args ) = @_;

    # @assignments holds the list of assignments to be emitted...
    my @assignments;

    my $arg_declare = ( exists $args{declare} ? $args{declare} : 1 );

    while ( my ( $key, $value ) = each %$href ) {

        if ( !_is_valid_ECMA262($key) ) {
            SGX::Abstract::Exception::Internal::JS->throw(
                error => "Symbol name $key does not comply with ECMA 262\n" );
        }

        # Fill out $encoded_value in a way that depends on reference type of
        # $value:
        my $encoded_value;
        my $value_reftype = ref $value;
        if ( $value_reftype eq '' ) {

            # direct scalar
            $encoded_value =
              ( looks_like_number($value) )
              ? trim($value)
              : ( ( defined $value ) ? $self->encode($value) : 'undefined' );
        }
        elsif ( $value_reftype eq 'SCALAR' ) {

            # referenced scalar
            $encoded_value =
              ( looks_like_number($$value) )
              ? trim($$value)
              : ( ( defined $$value ) ? $self->encode($$value) : 'undefined' );
        }
        elsif ( $value_reftype eq 'ARRAY' or $value_reftype eq 'HASH' ) {

            # array or hash reference
            $encoded_value = $self->encode($value);
        }
        else {
            SGX::Abstract::Exception::Internal::JS->throw( error =>
"Do not know how to handle Perl literals having ref eq $value_reftype\n"
            );
        }
        push @assignments, $key . $self->{assignment_operator} . $encoded_value;
    }

    # :TODO:07/30/2011 15:00:54:es: at the moment, this function simply emits
    # Javascript assignments. Instead, consider simply pushing assignments to an
    # encapsulated stack which would be dumped using a dump() method (to be
    # written).
    return
        ( $arg_declare ? $self->{type_declaration} : '' )
      . join( $self->{type_declaration_separator}, @assignments )
      . $self->{line_terminator};
}

1;
