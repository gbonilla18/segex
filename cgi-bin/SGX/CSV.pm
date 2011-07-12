#
#===============================================================================
#
#         FILE:  CSV.pm
#
#  DESCRIPTION:  Routines for handling CSV files
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:
#
#  use SGX::CSV;
#
#  my ( $infile, $outfile ) = splice @ARGV, 0, 2;
#  exit if not defined($infile) or not defined($outfile);
#
#  print "Opening files...\n";
#  open( my $in,  '<', $infile )  or die "$infile: $!";
#  open( my $out, '>', $outfile ) or die "$outfile: $!";
#  print "Rewriting...\n";
#  my $ok = eval {
#      SGX::CSV::csv_rewrite_keynum(
#          $in,
#          $out,
#          input_header => 1,
#          data_fields  => 5,
#          csv_in_opts  => { sep_char => "\t" }
#      );
#  };
#
#  if ( not $ok or $@ ) {
#      print "Closing files...\n";
#      close $in;
#      close $out;
#      die $@;
#  }
#  print "Closing files...\n";
#  close $in;
#  close $out;
#
#       AUTHOR:  Eugene Scherba (es), escherba@gmail.com
#      COMPANY:  Boston University
#      VERSION:  1.0
#      CREATED:  07/09/2011 16:22:21
#     REVISION:  ---
#===============================================================================

package SGX::CSV;

use strict;
use warnings;

use Text::CSV;
use Scalar::Util qw/looks_like_number/;
use SGX::Exceptions;

#===  FUNCTION  ================================================================
#         NAME:  csv_rewrite_keynum
#      PURPOSE:  Validate user-uploaded microarray data and rewrite the file
#                provided into a new file for safe slurp-mode loading into the
#                database. The original idea was to input a tab-separated file,
#                validate it, and rewrite it as a pipe-separated file.
#   PARAMETERS:  Required:
#                    $in  - input file handle
#                    $out - output file handle
#
#                Optional (named) with default values:
#                    input_header => 0  - whether input contains a header
#                    data_fields  => 0  - how many data fields follow the key
#                                         field
#                    csv_in_opts  => {} - Input Text::CSV options, e.g.
#                                         csv_in_opts => { sep_char => "\t" }
#                    csv_out_opts => {} - Output Text::CSV options, e.g.
#                                         csv_out_opts => {
#                                             eol => "\n",
#                                             sep_char => ','
#                                         }
#      RETURNS:  True value on success; raises exception on failure
#  DESCRIPTION:  Takes in a CSV-formatted plain-text file (either with header
#                present or not) such that the first column is a string "key"
#                and the first n columns after it are numeric. Rewrites this
#                file while dropping the header. The following options should be
#                used for MySQL LOAD DATA INFILE statement:
#
#                   FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
#                   LINES TERMINATED BY '\n' STARTING BY ''
#
#       THROWS:  SGX::Exception::User
#     COMMENTS:  Would be nice if this was rewritten as a class that, on object
#                instantiation, generates a custom method for field validation
#                (see Higher Order Perl etc.)
#
#     SEE ALSO:  perldoc Text::CSV
#                http://search.cpan.org/~makamaka/Text-CSV-1.21/lib/Text/CSV.pm
#===============================================================================
sub csv_rewrite_keynum {
    my ( $in, $out, %param ) = @_;

    # minimum required number of data fields
    my $req_data_fields =
      defined( $param{data_fields} )
      ? $param{data_fields}
      : 0;    # default: no data fields

    # whether input file contains a header
    my $input_header =
      defined( $param{input_header} )
      ? $param{input_header}
      : 0;    # default: no header

    # Text::CSV options for input file
    my $param_csv_in_opts =
      defined( $param{csv_in_opts} )
      ? $param{csv_in_opts}
      : {};

    # Default value for sep_char is as indicated below unless overridden by
    # $param{csv_out_opts}. Also, other Text::CSV options can be set through
    # $param{csv_out_opts}.
    my %csv_in_opts = ( sep_char => ',', %$param_csv_in_opts );

    # Text::CSV options for output file
    my $param_csv_out_opts =
      defined( $param{csv_out_opts} )
      ? $param{csv_out_opts}
      : {};

    # Default values for sep_char and eol are as indicated below unless
    # overridden by $param{csv_out_opts}. Also, other Text::CSV options can be
    # set through $param{csv_out_opts}.
    my %csv_out_opts = ( sep_char => ',', eol => "\n", %$param_csv_out_opts );

    my $csv_in    = Text::CSV->new( \%csv_in_opts );
    my $csv_out   = Text::CSV->new( \%csv_out_opts );
    my $record_no = 0;

    while ( my $row = $csv_in->getline($in) ) {
        my @fields = @$row;
        next if all_empty(@fields);    # skip blank lines
        $record_no++;
        next if $input_header and $record_no == 1;    # skip header if needed
        my $first_field = shift @fields;
        SGX::Exception::User->throw( error => "Key field empty at line $." )
          if all_empty($first_field);
        my $data_fields = scalar(@fields);
        SGX::Exception::User->throw(
            error => "At least $req_data_fields data fields required"
              . " but only $data_fields found at line $." )
          if $data_fields < $req_data_fields;
        SGX::Exception::User->throw(
            error => "Non-numeric value where numeric was expected at line $." )
          if not all_numbers(@fields);

        $csv_out->print( $out, [ $first_field, @fields ] );
    }
    my $ret = $csv_in->eof
      or SGX::Exception::User->throw( $csv_in->error_diag() );
    return $ret;
}

#===  FUNCTION  ================================================================
#         NAME:  all_numbers
#      PURPOSE:  Checks whether array consists solely of values that look like
#                numbers. Can also take a scalar.
#   PARAMETERS:  Array or scalar to check
#      RETURNS:  True/False
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  Uses looks_like_number from Scalar::Util. Returns true when run
#                on a zero-length array (of no elements).
#     SEE ALSO:  n/a
#===============================================================================
sub all_numbers { looks_like_number($_) || return for @_; return 1 }

#===  FUNCTION  ================================================================
#         NAME:  all_empty
#      PURPOSE:  Checks whether array (or scalar) consists entirely of
#                empty-space characters.
#   PARAMETERS:  Array of scalar to check
#      RETURNS:  True/False
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  Returns true when run on a zero-length array (of no elements)
#     SEE ALSO:  n/a
#===============================================================================
sub all_empty { m/^\s*$/ || return for @_; return 1 }

1;
