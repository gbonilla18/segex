package SGX::CSV;

use strict;
use warnings;

require File::Temp;
require Text::CSV;
use SGX::Util qw/all_match/;
use SGX::Abstract::Exception ();
use SGX::Debug;

#===  CLASS METHOD  ============================================================
#        CLASS:  CSV
#       METHOD:  sanitizeUploadWithMessages
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub sanitizeUploadWithMessages {
    my ( $delegate, $inputField, %args ) = @_;

    my $q = $delegate->{_cgi};

    my $recordsValid = 0;
    my $outputFileName =
      eval { sanitizeUploadFile( $q, $inputField, \$recordsValid, %args ); }
      || '';

    if ( my $exception = $@ ) {

        # Notify user of User exception; rethrow Internal and other types of
        # exceptions.
        if ( $exception->isa('SGX::Exception::User') ) {
            $delegate->add_message( { -class => 'error' },
                'There was a problem with your input: ' . $exception->error );
        }
        else {
            $exception->throw();
        }
        return 0;
    }
    elsif ( $recordsValid == 0 ) {
        $delegate->add_message( { -class => 'error' },
            'No valid records were uploaded.' );
        return 0;
    }
    return ( $outputFileName, $recordsValid );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  CSV
#       METHOD:  sanitizeUploadFile
#   PARAMETERS:  $outputFileName - Name of the temporary file to write to
#      RETURNS:  Number of valid records found
#  DESCRIPTION:  validate and rewrite the uploaded file
#       THROWS:  SGX::Exception::Internal, SGX::Exception::User
#     COMMENTS:   # :TODO:07/08/2011 12:55:45:es: Make headers optional
#     SEE ALSO:  n/a
#===============================================================================
sub sanitizeUploadFile {
    my ( $q, $inputField, $recordsValid, %args ) = @_;

    # This is where we put the temp file we will import. UNLINK option to
    # File::Temp constructor means that the File::Temp destructor will try to
    # unlink the temporary file on its own (we don't need to worry about
    # unlinking). Because we are initializing an instance of File::Temp in the
    # namespace of this function, the temporary file will be deleted when the
    # function exists (when the reference to File::Temp will go out of context).

    my $outputFileName =
      File::Temp->new( SUFFIX => '.txt', UNLINK => 1 )->filename();

    # The is the file handle of the uploaded file.
    my $uploadedFile = $q->upload($inputField)
      or SGX::Exception::User->throw( error => "Failed to upload file.\n" );

    #Open file we are writing to server.
    open my $OUTPUTTOSERVER, '>', $outputFileName
      or SGX::Exception::Internal->throw(
        error => "Could not open $outputFileName for writing: $!\n" );

    $$recordsValid =
      eval { csv_rewrite( $uploadedFile, $OUTPUTTOSERVER, %args ); }
      || 0;

    # In case of error, close files first and rethrow the exception
    if ( my $exception = $@ ) {

        close($OUTPUTTOSERVER);
        $exception->throw();
    }
    elsif ( $$recordsValid < 1 ) {
        close($OUTPUTTOSERVER);
        SGX::Exception::User->throw(
            error => "No records found in input file\n" );
    }
    close($OUTPUTTOSERVER);

    return $outputFileName;
}

#===  FUNCTION  ================================================================
#         NAME:  csv_rewrite
#      PURPOSE:  Validate user-uploaded microarray data and rewrite the file
#                provided into a new file for safe slurp-mode loading into the
#                database. The original idea was to input a tab-separated file,
#                validate it, and rewrite it as a pipe-separated file.
#   PARAMETERS:  Required:
#                    $in  - ARRAY reference to input file contents split by lines
#                    $out - output file handle
#                    $parse - array of functions to validate input fields
#
#                Optional (named) with default values:
#                    header => 0  - whether input contains a header
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
sub csv_rewrite {
    my ( $uploadedFile, $out, %args ) = @_;

    # Read uploaded file in "slurp" mode (at once), and break it on the
    # following combinations of line separators in respective order: (1) CRLF
    # (Windows), (2) LF (Unix), and (3) CR (Mac).
    my @lines = split(
        /\r\n|\n|\r/,
        do { local $/ = <$uploadedFile> }
    );

    # upload file should get deleted automatically on close
    close $uploadedFile;

    # whether input file contains a header
    my $header =
      ( exists $args{header} )
      ? $args{header}
      : 0;    # default: no header

    # Default value for sep_char is as indicated below unless overridden by
    # $args{csv_out_opts}. Also, other Text::CSV options can be set through
    # $args{csv_out_opts}.
    my %csv_in_opts = (
        sep_char         => "\t",
        allow_whitespace => 1,
        %{ $args{csv_in_opts} || {} }
    );

    # Default values for sep_char and eol are as indicated below unless
    # overridden by $args{csv_out_opts}. Also, other Text::CSV options can be
    # set through $args{csv_out_opts}.
    my %csv_out_opts = (
        sep_char => ',',
        eol      => "\n",
        %{ $args{csv_out_opts} || {} }
    );

    my $csv_in  = Text::CSV->new( \%csv_in_opts );
    my $csv_out = Text::CSV->new( \%csv_out_opts );
    my $record_num = 0;    # record is a non-empty line

    # Generate a custom function that will check whether array consists of
    # elements we consider to be empty. When "allow_whitespace" is set during
    # parsing, white space will be stripped off automatically from value bounds
    # by Text::CSV, in which case we define "empty" to mean empty string. When
    # "allow_whitespace" is not set, we define "empty" to mean any combination
    # of space characters *or* an empty string. In addition, we ignore undefined
    # values (they are equivalent to empty fields).
    my $is_empty =
      ( $csv_in_opts{allow_whitespace} )
      ? all_match( qr/^$/,    ignore_undef => 1 )
      : all_match( qr/^\s*$/, ignore_undef => 1 );

    #---------------------------------------------------------------------------
    #  default process routine
    #---------------------------------------------------------------------------
    my $parser = $args{parser} || [];

    my $process = $args{process} || sub {
        my $line_num = shift;
        my $fields   = shift;

        # check total number of fields present
        if ( @$fields < @$parser ) {
            SGX::Exception::User->throw(
                error => sprintf(
                    "Only %d field(s) found (%d required) at line %d\n",
                    scalar(@$fields), scalar(@$parser), $line_num
                )
            );
        }

        # perform validation on each column
        my @out_fields;
        eval {
            @out_fields =
              map {
                my $val = shift @$fields;
                ( defined $_ ) ? $_->( $val, $line_num ) : ()
              } @$parser;
            1;
        } or do {
            my $exception = $@;
            if ( $exception->isa('SGX::Exception::Skip') ) {
                @out_fields = ();    # skip line
            }
            else {
                $exception->throw();    # rethrow otherwise
            }
        };
        return [ \@out_fields ];
    };

    #---------------------------------------------------------------------------
    #  main loop
    #---------------------------------------------------------------------------
    for ( my $line_num = 1 ; $csv_in->parse( shift @lines ) ; $line_num++ ) {
        my @fields = $csv_in->fields();

        # skip blank lines
        next if $is_empty->(@fields);

        # skip header if requested to
        $record_num++;
        next if $record_num == 1 and $header;

        my $out_rows = $process->( $line_num, \@fields );
        @$_ == 0 || $csv_out->print( $out, $_ ) for @$out_rows;
    }

    # check for errors
    my ( $err_code, $err_string, $err_pos ) = $csv_in->error_diag();
    if ($err_code) {
        SGX::Exception::User->throw( error =>
"Text::CSV error code $err_code ($err_string), position $err_pos. Records written: $record_num"
        );
    }

    # return number of records written
    return $record_num;
}

1;

__END__

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
#  use Carp;
#  use SGX::CSV;
#
#  my ( $infile, $outfile ) = splice @ARGV, 0, 2;
#  exit unless (defined($infile) && defined($outfile));
#
#  print "Opening files...\n";
#  open( my $in,  '<', $infile )  or croak "$infile: $!";
#  open( my $out, '>', $outfile ) or croak "$outfile: $!";
#  print "Rewriting...\n";
#  my $ok = eval {
#      SGX::CSV::csv_rewrite(
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
#      croak $@;
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


