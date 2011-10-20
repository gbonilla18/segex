package SGX::Abstract::JSEmitter;

use strict;
use warnings;
use base qw/Exporter/;

use Data::Dumper;
use JSON;
use SGX::Abstract::Exception;
use Tie::Hash;

#use Scalar::Util qw/looks_like_number/;
#use SGX::Util qw/trim/;

our @EXPORT_OK = qw/true false/;

BEGIN {
    my %reserved_words = map { $_ => undef }
      qw/break do if switch typeof case else in this var catch false instanceof
      throw void continue finally new true while default for null try with
      delete function return abstract double goto native static boolean enum
      implements package super byte export import private synchronized char
      extends int protected throws class final interface public transient const
      float long short volatile debugger/;

    my %bad_words = map { $_ => undef }
      qw/arguments encodeURI Infinity Object String Array Error isFinite
      parseFloat SyntaxError Boolean escape isNaN parseInt TypeError Date eval
      Math RangeError undefined decodeURI EvalError NaN ReferenceError unescape
      decodeURIComponent Function Number RegExp URIError/;

#===  FUNCTION  ================================================================
#         NAME:  _validate_identifier
#      PURPOSE:  checks whether argument is a valid ECMA 262 identifier
#                (excluding Unicode).
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:
# Javascript: The Definitive Guide (6th ed.): section 2.4 (Identifiers and
# Reserved Words).
# http://stackoverflow.com/questions/1661197/valid-characters-for-javascript-variable-names
#===============================================================================
    sub _validate_identifier {
        my ($symbol) = @_;
        ( $symbol =~ m/^[a-zA-Z_\$][0-9a-zA-Z_\$]*$/
              and not exists $reserved_words{$symbol} )
          or SGX::Exception::Internal::JS->throw( error =>
              "Symbol name $symbol is not a valid ECMA 262 identifier\n" );
        return $symbol;
    }

#===  FUNCTION  ================================================================
#         NAME:  _validate_chain
#      PURPOSE:  same as above except allows for dot operator
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
    sub _validate_chain {
        my ($symbol) = @_;
        ( $symbol =~ m/^[a-zA-Z_\$][\.0-9a-zA-Z_\$]*$/
              and not exists $reserved_words{$symbol} )
          or SGX::Exception::Internal::JS->throw(
            error => "Symbol name $symbol is not a valid ECMA 262 chain\n" );
        return $symbol;
    }
}

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
#       METHOD:  true
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub true {
    return JSON::true;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Abstract::JS
#       METHOD:  flase
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub false {
    return JSON::false;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Abstract::JS
#       METHOD:  register_var
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Generates unique identifiers for a given set of words returning
#                two hashes: one to lookup unique identifier by name and another
#                to return an anonymous subroutine (lambda) which evaluates to
#                the name. Uses Safe::Hash infile package to lock down hash keys
#                after hashes has been filled.
#       THROWS:  no exceptions
#     COMMENTS:
#
#     my ($name, $bare) = $self->create_id_tables('_a', [qw/cat meow/]);
#     $name->{cat};     # returns '_a0'
#     $name->{meow};    # returns '_a1'
#     $bare->{cat}->(); # returns '_a0'
#     $name->{tiger};   # throws an exception
#
#     SEE ALSO:
# http://stackoverflow.com/questions/3381159/make-perl-shout-when-trying-to-access-undefined-hash-key/3382500#3382500
# Perl Cookbook, 2nd ed.: 5.3. Creating a Hash with Immutable Keys or Values
#===============================================================================
{

    package Safe::Hash;

    use strict;
    use warnings;

    use base qw/Tie::StdHash/;

    sub FETCH {
        my ( $self, $key ) = @_;
        exists $self->{$key}
          or SGX::Exception::Internal::JS->throw(
            error => "Symbol '$key' absent from id hash" );
        return $self->{$key};
    }

    1;
}

#---------------------------------------------------------------------------
#  uses Safe::Hash as defined above
#---------------------------------------------------------------------------
sub register_var {
    my ( $self, $prefix, $ids ) = @_;
    tie my %barewords => 'Safe::Hash';
    %barewords =
        ( $self->{pretty} )
      ? ( map { $_ => $self->literal($_) } @$ids )
      : ( map { $ids->[$_] => $self->literal( $prefix . $_ ) } 0 .. $#$ids );
    return \%barewords;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Abstract::JS
#       METHOD:  literal
#   PARAMETERS:  ????
#      RETURNS:  Returns a lambda capable of adding identifiers to chain.
#  DESCRIPTION:  Example:
#
#       $self->literal('ee')->('e')->('ppppp')->('er','re','r')->();
#
#   evaluates to (note empty parantheses needed for termination):
#
#       ee.e.ppppp.er.re.r
#
#   Intermediate values can be cached:
#
#        my $cache = $self->literal('ee')->('e');
#        $cache->('test')->();
#
#    evaluates to:
#
#        ee.e.test
#
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub literal {
    my ( $self, @rest ) = @_;
    return sub {
        my $tmp = join( '.', @rest, @_ );
        return (@_) ? $self->literal($tmp) : $tmp;
    };
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
    $self->{function_template} =
      ($arg_pretty) ? "function %s(%s) {\n%s}" : 'function %s(%s){%s}';
    $self->{assignment_operator} = ($arg_pretty) ? ' = ' : '=';
    $self->{line_terminator}     = ($arg_pretty) ? ";\n" : ';';
    $self->{type_declaration}    = $type_declaration;
    my $list_separator = ',';
    $self->{type_declaration_separator} =
      ($arg_pretty)
      ? "$list_separator\n" . ' ' x length($type_declaration)
      : $list_separator;

    $self->{list_separator} =
      ($arg_pretty)
      ? "$list_separator "
      : $list_separator;

    $self->{pretty} = $arg_pretty;

    # 'Orcish' operator (||=): assign value to property only if that property
    # evaluates to false. A valid reference will never evaluate to false.
    $self->{json} ||= JSON->new->allow_nonref;

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Abstract::JSEncode
#       METHOD:  let
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub let {
    my ( $self, $href, %args ) = @_;

    # @assignments holds the list of assignments to be emitted...
    my @assignments;

    my $arg_declare = ( exists $args{declare} ? $args{declare} : 1 );
    my $validate = ($arg_declare) ? \&_validate_identifier : \&_validate_chain;

    while ( my ( $key, $value ) = splice( @$href, 0, 2 ) ) {
        push @assignments,
            $validate->( _evaluate($key) )
          . $self->{assignment_operator}
          . $self->encode($value);
    }

    # :TODO:07/30/2011 15:00:54:es: at the moment, this function simply emits
    # Javascript assignments. Instead, consider simply pushing assignments to an
    # encapsulated stack which would be dumped using a dump() method (to be
    # written).
    my $terminator = $self->{line_terminator};
    my $code = ( $arg_declare ? $self->{type_declaration} : '' )
      . join(
        ($arg_declare)
        ? $self->{type_declaration_separator}
        : $self->{line_terminator},
        @assignments
      );
    return ( wantarray() )
      ? sub { $code }
      : $code . $terminator;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Abstract::JSEncode
#       METHOD:  function
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  function declaration
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub defun {
    my ( $self, $id, $param, $statements ) = @_;
    if ( defined $id ) {
        _validate_identifier($id);
    }
    else {
        $id = '';
    }
    $param = [] if not defined($param);
    return sub {
        return sprintf(
            $self->{function_template},
            $id,
            join( $self->{list_separator}, map { $self->encode($_) } @$param ),
            join(
                $self->{line_terminator},
                map { $self->encode($_) } @$statements
            )
        );
    };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Abstract::JSEncode
#       METHOD:  lambda
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub lambda {
    my ( $self, @args ) = @_;
    return $self->defun( undef, shift(@args), \@args );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Abstract::JSEncode
#       METHOD:  _evaluate
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub _evaluate {
    my $val     = shift;
    my $key_ref = ref $val;
    if ( $key_ref eq '' ) {

        # scalar
        return $val;
    }
    elsif ( $key_ref eq 'CODE' ) {

        # anonymous function
        return $val->();
    }
    elsif ( $key_ref eq 'SCALAR' or $key_ref eq 'REF' ) {

        # reference to reference or scalar
        return _evaluate($$val);
    }
    else {

        # not a scalar
        SGX::Exception::Internal::JS->throw(
            error => "Invalid reftype $key_ref in bind symbol" );
    }
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Abstract::JSEncode
#       METHOD:  json_encode
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub json_encode {
    return shift->{json}->encode(shift);
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Abstract::JSEncode
#       METHOD:  encode
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Recursively encode a nested data structure. Nearly the same
#                functionality as the encode() method in JSON module except that
#                CODE blocks (anonymous subroutines) are executed if found,
#                allowing us to encode not only literal object representations,
#                but also function calls, etc.
#       THROWS:  SGX::Exception::Internal::JS, JSON
#     COMMENTS:  Circular references will cause this method to hang (i.e. we do
#                not break on reaching maximum depth, unlike what JSON module
#                does).
#     SEE ALSO:  n/a
#===============================================================================
sub encode {
    my ( $self, $value ) = @_;

    # switch on reference type
    my $value_reftype = ref $value;
    if ( $value_reftype eq '' ) {

        # Most common type -- unreferenced (direct) scalar (maps to Javascript
        # literal)
        return $self->json_encode($value);
    }
    elsif ( $value_reftype eq 'ARRAY' ) {

        # Perl array (maps to Javascript Array object)
        my $separator = $self->{list_separator};
        return
          '[' . join( $separator, map { $self->encode($_) } @$value ) . ']';
    }
    elsif ( $value_reftype eq 'HASH' ) {

        # Perl hash (maps to generic Javascript object)
        my @tmp;
        while ( my ( $id, $obj ) = each %$value ) {
            push @tmp, $self->json_encode($id) . ':' . $self->encode($obj);
        }
        my $separator = $self->{list_separator};
        return '{' . join( $separator, @tmp ) . '}';
    }
    elsif ( $value_reftype eq 'CODE' ) {

        # anonymous subroutine (execute on stringification)
        return $value->();
    }
    elsif ( $value_reftype eq 'SCALAR' or $value_reftype eq 'REF' ) {

        # Don't expect many of those -- either referenced scalar (follow
        # reference) or a reference to a reference. WARNING: circular references
        # will cause this to hang.
        return $self->encode($$value);
    }
    else {

        # try to use JSON module first and fail on error
        my $ret = eval { $self->json_encode($value); };
        if ( my $error = $@ ) {
            SGX::Exception::Internal::JS->throw( error => $error );
        }
        return $ret;
    }
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Abstract::JSEncode
#       METHOD:  apply
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub apply {
    my ( $self, $id, $list, %args ) = @_;
    my $terminator = $self->{line_terminator};
    my $prefix     = ( $args{new_object} ) ? 'new ' : '';
    my $separator  = $self->{list_separator};
    my $arguments  = join( $separator, map { $self->encode($_) } @$list );

    # by returning a subroutine reference, we can delay execution
    my $code = $prefix . _evaluate($id) . "($arguments)";
    return ( wantarray() )
      ? sub { $code }
      : $code . $terminator;
}

1;

__END__

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


