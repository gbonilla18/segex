package SGX::CSV;

use strict;
use warnings;

require File::Temp;
require Text::CSV;
use Benchmark qw/timediff timestr/;
use SGX::Util qw/all_match car/;
use SGX::Abstract::Exception ();

#===  FUNCTION  ================================================================
#         NAME:  bind_handle
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:
#
# :TODO:10/21/2011 00:49:20:es: Use Text::CSV types:
# http://search.cpan.org/~makamaka/Text-CSV-1.21/lib/Text/CSV.pm#types
#
#     SEE ALSO:  n/a
#===============================================================================
sub bind_handle {
    my $handle = shift;
    my $csv = eval { Text::CSV->new( { eol => "\r\n", sep_char => "," } ); }
      or do {
        my $exception = Exception::Class->caught();
        my $msg = "$exception" || 'Unknown error';
        SGX::Exception::Internal->throw(
            error => "Can't load Text::CSV: $msg" );
      };
    return sub {
        return $csv->print( $handle, shift || [] );
    };
}

#===  CLASS METHOD  ============================================================
#        CLASS:  CSV
#       METHOD:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub delegate_fileUpload {
    my %args            = @_;
    my $self            = $args{delegate};
    my $sql             = $args{statements};
    my $validators      = $args{validators};
    my $parameters      = $args{parameters};
    my $index_for_count = $args{index_for_count};
    my $filename        = $args{filename};

    # will use last return code by default (index -1)
    my $return_code_to_report =
      exists( $args{return_code_to_report} )
      ? $args{return_code_to_report}
      : -1;

    my $success_message =
      exists( $args{success_message} ) ? $args{success_message} : 1;

    my $dbh = $self->{_dbh};
    my @statements = map { $dbh->prepare($_) } @$sql;

    my $old_AutoCommit = $dbh->{AutoCommit};
    $dbh->{AutoCommit} = 0;
    my $t0 = Benchmark->new();

    my @return_codes;
    eval {
        foreach my $sth (@statements)
        {
            my $param = shift @$parameters;
            my @proc_param =
              map { ( ref($_) eq 'CODE' ) ? $_->() : $_ } @$param;
            push @return_codes, 0 + $sth->execute(@proc_param);
            $sth->finish();
            if ( defined $validators ) {
                my $validator = shift @$validators;
                $validator->( \@return_codes ) if defined $validator;
            }
        }
        1;
    } or do {
        my $exception;
        if ( $exception =
            Exception::Class->caught('Exception::Class::DBI::STH') )
        {

            # catch dbi::sth exceptions. note: this block catches duplicate
            # key record exceptions.
            $self->add_message( {}, 'No changes to the database were stored' );
            $self->add_message(
                { -class => 'error' },
                sprintf(
                    'DBI Error %d: %s',
                    $exception->err, $exception->errstr
                )
            );
        }
        elsif ( $exception = Exception::Class->caught() ) {
            my $msg =
              eval { $exception->error } || "$exception" || 'Unknown error';
            $self->add_message( {}, 'No changes to the database were stored' );
            $self->add_message( { -class => 'error' }, $msg );
        }
        else {
            $self->add_message( {},
'Unknown error occured when loading data into the database. No changes to the database were stored.'
            );
        }
        $dbh->rollback;
        unlink $filename if defined $filename;
        $_->finish() for @statements;

        $dbh->{AutoCommit} = $old_AutoCommit;
        return;
    };
    $dbh->commit;
    $_->finish() for @statements;
    $dbh->{AutoCommit} = $old_AutoCommit;
    my $t1 = Benchmark->new();
    unlink $filename if defined $filename;

    my $records_added = $return_codes[$return_code_to_report];
    my $time_diff = timestr( timediff( $t1, $t0 ) );
    if ($success_message) {
        my $msg =
"Success! Added $records_added entries to the database. The operation took $time_diff.";
        $self->add_message( { -class => 'success' }, $msg );
    }
    return 1;
}

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

    # field separator character
    $args{csv_in_opts} ||= {};
    $args{csv_in_opts}->{sep_char} = ( car( $q->param('separator') ) || "\t" )
      if not defined $args{csv_in_opts}->{sep_char};

    # whether first line is a header or not
    $args{header} = ( defined( $q->param('header') ) ? 1 : 0 )
      if not defined $args{header};

    my $recordsValid = 0;
    my $outputFileNames =
      eval { sanitizeUploadFile( $q, $inputField, \$recordsValid, %args ); }
      || [];

    my $exception;
    if ( $exception = Exception::Class->caught('SGX::Exception::User') ) {

        # Notify user of User exception; rethrow Internal and other types of
        # exceptions.
        $delegate->add_message( { -class => 'error' },
            'There was a problem with your input: ' . $exception->error );
    }
    elsif ( $exception = Exception::Class->caught() ) {
        $exception->rethrow();
    }
    elsif ( $recordsValid == 0 ) {
        $delegate->add_message( { -class => 'error' },
            'No valid records were uploaded.' );
    }
    return ( $outputFileNames, $recordsValid );
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

    my $rewrite = ( exists $args{rewrite} ) ? $args{rewrite} : 1;

    # The is the file handle of the uploaded file.
    my $uploadedFile = $q->upload($inputField)
      or SGX::Exception::User->throw( error => "Failed to upload file.\n" );

    #Open file we are writing to server.
    my @outputFileName;
    my @OUTPUTTOSERVER;

    for ( my $i = 0 ; $i < $rewrite ; $i++ ) {
        my $outputFileName = File::Temp->new(
            SUFFIX => '.txt',
            UNLINK => 1
        )->filename();
        open my $OUTPUTTOSERVER, '>', $outputFileName    ## no critic
          or SGX::Exception::Internal->throw(
            error => "Could not open $outputFileName for writing: $!\n" );
        push @outputFileName, $outputFileName;
        push @OUTPUTTOSERVER, $OUTPUTTOSERVER;
    }

    $$recordsValid =
      eval { csv_rewrite( $uploadedFile, \@OUTPUTTOSERVER, %args ); }
      || 0;

    if ( my $exception = Exception::Class->caught() ) {

        # In case of error, close files first and rethrow the exception
        close($_) for @OUTPUTTOSERVER;

        if ( eval { $exception->can('rethrow') } ) {
            $exception->rethrow();
        }
        else {

            # Internal error details do not diplay to browser window
            SGX::Exception::Internal->throw( error => "$exception\n" );
        }
    }
    elsif ( $$recordsValid < 1 ) {
        SGX::Exception::User->throw(
            error => "No records found in input file\n" );
    }

    return \@outputFileName;
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
    my $min_field_count = $args{required_fields};
    $min_field_count = @$parser if not defined $min_field_count;

    my @sub_print;
    foreach my $fh (@$out) {
        push @sub_print, sub { $csv_out->print( $fh, \@_ ) };
    }
    my $process = $args{process} || sub {
        my $printfun = shift;
        my $line_num = shift;
        my $fields   = shift;

        # check total number of fields present
        if ( @$fields < $min_field_count ) {
            SGX::Exception::User->throw(
                error => sprintf(
                    "Only %d field(s) found (%d required) on line %d\n",
                    scalar(@$fields), $min_field_count, $line_num
                )
            );
        }

        # perform validation on each column
        eval {
            $printfun->[0]->(
                map {    ## no critic
                    my $val = shift @$fields;
                    ( defined $_ ) ? $_->( $val, $line_num ) : ()
                  } @$parser
            );
            1;
        } or do {
            my $exception;
            if ( $exception = Exception::Class->caught('SGX::Exception::Skip') )
            {

                # only skip 'Skip' exception (which means: skip line)
            }
            elsif ( $exception = Exception::Class->caught() ) {
                if ( eval { $exception->can('rethrow') } ) {
                    $exception->rethrow();
                }
                else {

                    # Internal error details do not diplay to browser window
                    SGX::Exception::Internal->throw( error => "$exception\n" );
                }
            }
        };
        return 1;
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

        $process->( \@sub_print, $line_num, \@fields );
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
#       AUTHOR:  Eugene Scherba (es), escherba@gmail.com
#      COMPANY:  Boston University
#      VERSION:  1.0
#      CREATED:  07/09/2011 16:22:21
#     REVISION:  ---
#===============================================================================


