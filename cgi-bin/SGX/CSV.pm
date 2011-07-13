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
use SGX::Exceptions;

#===  FUNCTION  ================================================================
#         NAME:  csv_rewrite_keynum
#      PURPOSE:  Validate user-uploaded microarray data and rewrite the file
#                provided into a new file for safe slurp-mode loading into the
#                database. The original idea was to input a tab-separated file,
#                validate it, and rewrite it as a pipe-separated file.
#   PARAMETERS:  Required:
#                    $in  - ARRAY reference to input file contents split by lines
#                    $out - output file handle
#                    $is_valid - array of functions to validate input fields
#
#                Optional (named) with default values:
#                    input_header => 0  - whether input contains a header
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
#     COMMENTS:  n/a
#
#     SEE ALSO:  perldoc Text::CSV
#                http://search.cpan.org/~makamaka/Text-CSV-1.21/lib/Text/CSV.pm
#===============================================================================
sub csv_rewrite_keynum {
    my ( $in, $out, $is_valid, %param ) = @_;

    # whether input file contains a header
    my $input_header =
      ( exists $param{input_header} )
      ? $param{input_header}
      : 0;    # default: no header

    # Text::CSV options for input file
    my $param_csv_in_opts =
      ( exists $param{csv_in_opts} )
      ? $param{csv_in_opts}
      : {};

    # Default value for sep_char is as indicated below unless overridden by
    # $param{csv_out_opts}. Also, other Text::CSV options can be set through
    # $param{csv_out_opts}.
    my %csv_in_opts = ( sep_char => ',', %$param_csv_in_opts );

    # Text::CSV options for output file
    my $param_csv_out_opts =
      ( exists $param{csv_out_opts} )
      ? $param{csv_out_opts}
      : {};

    # Default values for sep_char and eol are as indicated below unless
    # overridden by $param{csv_out_opts}. Also, other Text::CSV options can be
    # set through $param{csv_out_opts}.
    my %csv_out_opts = ( sep_char => ',', eol => "\n", %$param_csv_out_opts );

    my $csv_in  = Text::CSV->new( \%csv_in_opts );
    my $csv_out = Text::CSV->new( \%csv_out_opts );
    my $record_num = 0;    # record is a non-empty line

    # require as many fields as have validating functions
    my $req_fields = @$is_valid;

    for ( my $line_num = 1 ; $csv_in->parse( shift(@$in) ) ; $line_num++ ) {
        my @fields = $csv_in->fields();

        # skip blank lines
        next if all_empty(@fields);

        # skip header if requested to
        $record_num++;
        next if $input_header and $record_num == 1;

        # check total number of fields present
        if ( ( my $fc = @fields ) < $req_fields ) {
            SGX::Exception::User->throw( error =>
"Only $fc field(s) found ($req_fields required) at line $line_num\n"
            );
        }

        # perform validation on each column
        foreach ( 0 .. ( $req_fields - 1 ) ) {
            if ( !$is_valid->[$_]->( $fields[$_] ) ) {
                my $col_num = $_ + 1;
                SGX::Exception::User->throw( error =>
                      "Invalid formatting at line $line_num column $col_num\n"
                );
            }
        }

        # write to output
        $csv_out->print( $out, \@fields );
    }

    # check for errors
    if ( my $error = $csv_in->error_diag() ) {
        SGX::Exception::User->throw($error);
    }

    # return number of records written
    return $record_num;
}

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
