
=head1 NAME

SGX::UploadData

=head1 SYNOPSIS

=head1 DESCRIPTION
Grouping of functions for adding experiments.

=head1 AUTHORS
Michael McDuffie
Eugene Scherba

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::UploadData;

use strict;
use warnings;
use SGX::CSV;
use SGX::DropDownData;
use Data::Dumper;
use File::Temp;
use Carp;
use Switch;
use SGX::Exceptions;
use Scalar::Util qw/looks_like_number/;

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ( $class, %param ) = @_;

    my ( $dbh, $q, $s, $js_src_yui, $js_src_code ) =
      @param{qw{dbh cgi user_session js_src_yui js_src_code}};

    my $self = {
        _dbh         => $dbh,
        _cgi         => $q,
        _UserSession => $s,
        _js_src_yui  => $js_src_yui,
        _js_src_code => $js_src_code,

        _InsertQuery => <<"END_InsertQuery",
INSERT INTO experiment (
    sample1,
    sample2,
    ExperimentDescription,
    AdditionalInformation
) VALUES (?, ?, ?, ?)
END_InsertQuery

        _stid => '',
        _pid  => '',

        _PlatformQuery => <<"END_PlatformQuery",
SELECT pid, CONCAT(pname, ' \\\\ ', species)
FROM platform
END_PlatformQuery

        _StudyPlatformQuery => <<"END_StudyPlatformQuery",
SELECT pid, stid, description
FROM study
END_StudyPlatformQuery

        _platformList          => {},
        _sample1               => '',
        _sample2               => '',
        _ExperimentDescription => '',
        _AdditionalInfo        => '',
        _rowsInserted          => undef
    };

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  dispatch_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub dispatch_js {
    my ($self) = @_;

    my ( $dbh, $q, $s ) = @$self{qw{_dbh _cgi _UserSession}};
    my ( $js_src_yui, $js_src_code ) = @$self{qw{_js_src_yui _js_src_code}};

    my $action =
      ( defined $q->param('b') )
      ? $q->param('b')
      : '';

    push @$js_src_yui, ('yahoo-dom-event/yahoo-dom-event.js');

    switch ($action) {
        case 'Upload' {

            # upload data to new experiment
            return if not $s->is_authorized('user');
            $self->loadFromForm();
            my $rows_inserted = eval { $self->addNewExperiment() };

            if ( my $exception = $@ ) {
                if ( $exception->isa('SGX::Exception::User') ) {

                    # Notify user of user exceptions
                    $self->{_error_message} =
                      'Error in input: ' . $exception->error;
                }
                else {
                    $exception->throw();    # rethrow internal or DBI exceptions
                }
            }
            elsif ( !$rows_inserted ) {
                $self->{_error_message} = 'No records were added';
            }
            else {
                $self->{_message} = "Success! Records added: $rows_inserted";
            }

            # view needs this
            $self->loadPlatformData();
        }
        else {

            # default: show form
            return if not $s->is_authorized('user');
            $self->loadFromForm();

            # view needs this
            $self->loadPlatformData();
        }
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  dispatch
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub dispatch {
    my ($self) = @_;

    my ( $dbh, $q, $s ) = @$self{qw{_dbh _cgi _UserSession}};

    my $action =
      ( defined $q->param('b') )
      ? $q->param('b')
      : '';

    # notice about rows added or error message
    print $q->p( { -style => 'color:red; font-weight:bold;' },
        $self->{_error_message} )
      if $self->{_error_message};
    print $q->p( { -style => 'font-weight:bold;' }, $self->{_message} )
      if $self->{_message};

    # always show form
    print $self->drawUploadDataMenu();
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  loadFromForm
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Loads CGI parameters
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadFromForm {
    my $self = shift;

    $self->{_sample1} = ( $self->{_cgi}->param('Sample1') )
      if defined( $self->{_cgi}->param('Sample1') );
    $self->{_sample2} = ( $self->{_cgi}->param('Sample2') )
      if defined( $self->{_cgi}->param('Sample2') );
    $self->{_stid} = ( $self->{_cgi}->param('stid') )
      if defined( $self->{_cgi}->param('stid') );
    $self->{_stid} = ( $self->{_cgi}->url_param('stid') )
      if defined( $self->{_cgi}->url_param('stid') );
    $self->{_pid} = ( $self->{_cgi}->param('pid') )
      if defined( $self->{_cgi}->param('pid') );
    $self->{_ExperimentDescription} = ( $self->{_cgi}->param('ExperimentDesc') )
      if defined( $self->{_cgi}->param('ExperimentDesc') );
    $self->{_AdditionalInfo} = ( $self->{_cgi}->param('AdditionalInfo') )
      if defined( $self->{_cgi}->param('AdditionalInfo') );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  loadPlatformData
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Loads information into the object that is used to create the
#  study dropdown
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadPlatformData {
    my $self = shift;

    my $platformDropDown =
      SGX::DropDownData->new( $self->{_dbh}, $self->{_PlatformQuery} );

    $self->{_platformList} = $platformDropDown->loadDropDownValues();
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  loadStudyData
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadStudyData {
    my $self = shift;

    my $sth = $self->{_dbh}->prepare( $self->{_StudyPlatformQuery} );
    my $rc  = $sth->execute();

    $self->{_studyList} = $sth->fetchall_hashref();

    $sth->finish();

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  drawUploadDataMenu
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  returns array of HTML element strings
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub drawUploadDataMenu {
    my $self = shift;
    my $q    = $self->{_cgi};

    return
      $q->h2('Upload Data to a New Experiment'),
      $q->start_form(
        -method  => 'POST',
        -action  => $q->url( -absolute => 1 ) . '?a=uploadData',
        -enctype => 'multipart/form-data',
        -onsubmit =>
          'return validate_fields(this, [\'Sample1\',\'Sample2\',\'file\']);'
      ),
      $q->p(
'The data file must be in plain-text tab-delimited format with the following
columns:'
      ),
      $q->pre(
        'Reporter Name, Ratio, Fold Change, P-value, Intensity 1, Intensity 2'
      ),
      $q->p(
'Make sure the first row is the column headings and the second row starts the data.'
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'pid' }, 'Platform:' ) ),
        $q->dd(
            $q->popup_menu(
                -name   => 'pid',
                -id     => 'pid',
                -values => [ keys %{ $self->{_platformList} } ],
                -labels => $self->{_platformList}
            )
        ),
        $q->dt( $q->label( { -for => 'Sample1' }, 'Sample 1:' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'Sample1',
                -id        => 'Sample1',
                -maxlength => 120
            )
        ),
        $q->dt( $q->label( { -for => 'Sample2' }, 'Sample 2:' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'Sample2',
                -id        => 'Sample2',
                -maxlength => 120
            )
        ),
        $q->dt(
            $q->label( { -for => 'ExperimentDesc' }, 'Experiment Description' )
        ),
        $q->dd(
            $q->textfield(
                -name      => 'ExperimentDesc',
                -id        => 'ExperimentDesc',
                -maxlength => 1000
            )
        ),
        $q->dt(
            $q->label(
                { -for => 'AdditionalInfo' }, 'Additional Information:'
            )
        ),
        $q->dd(
            $q->textfield(
                -name      => 'AdditionalInfo',
                -id        => 'AdditionalInfo',
                -maxlength => 1000
            )
        ),
        $q->dt( $q->label( { -for => 'file' }, 'Data File to Upload:' ) ),
        $q->dd(
            $q->filefield(
                -name => 'file',
                -id   => 'file'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'b',
                -id    => 'b',
                -class => 'css3button',
                -value => 'Upload'
            )
        )
      ),
      $q->end_form;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  addNewExperiment
#   PARAMETERS:  ????
#      RETURNS:  True value on success. Also fills out _eid and _rowsInserted
#                fields.
#  DESCRIPTION:  Performs actual upload and data validation
#       THROWS:  SGX::Exception::Internal, SGX::Exception::User
#     COMMENTS:   # :TODO:07/08/2011 12:55:45:es: Make headers optional
#     SEE ALSO:  n/a
#===============================================================================
sub addNewExperiment {

    #Get reference to our object.
    my $self = shift;

    #The is the file handle of the uploaded file.
    my $uploadedFile = $self->{_cgi}->upload('file');

    if ( !$uploadedFile ) {
        SGX::Exception::User->throw( error => 'File failed to upload. '
              . "Be sure to enter a valid file to upload\n" );
    }

    $self->{_dbh}->do(
        $self->{_InsertQuery}, undef, $self->{_sample1}, $self->{_sample2},
        $self->{_ExperimentDescription},
        $self->{_AdditionalInfo}
      )
      or SGX::Exception::Internal->throw( error => "No rows were inserted\n" );

    # Fills out _eid field
    $self->{_eid} = $self->{_dbh}->{'mysql_insertid'};

    #This is where we put the temp file we will import.
    my $tmp            = File::Temp->new();
    my $outputFileName = $tmp->filename();

    #Open file we are writing to server.
    open my $OUTPUTTOSERVER, '>', $outputFileName
      or SGX::Exception::Internal->throw(
        error => "Could not open $outputFileName for writing: $!\n" );

    # Read uploaded file in "slurp" mode (at once), and break it on the
    # following combinations of line separators in respective order: (1) CRLF
    # (Windows), (2) LF (Unix), and (3) CR (Mac).
    my @lines = split(
        /\r\n|\n|\r/,
        do { local $/ = <$uploadedFile> }
    );

    # :TODO:07/12/2011 21:21:33:es: check whether the file gets deleted
    # automatically on close
    close $uploadedFile;

    my $valid_records = eval {
        SGX::CSV::csv_rewrite_keynum(
            \@lines,
            $OUTPUTTOSERVER,
            [
                sub { shift =~ m/[^\s]/ },
                sub { looks_like_number(shift) },
                sub { looks_like_number(shift) },
                sub { looks_like_number(shift) },
                sub { looks_like_number(shift) },
                sub { looks_like_number(shift) }
            ],
            input_header => 1,
            csv_in_opts  => { sep_char => "\t" }
        );
    };

    # in case of error, close files first and rethrow the exception
    if ( my $exception = $@ ) {
        close($OUTPUTTOSERVER);
        $exception->throw();
    }
    elsif ( !$valid_records ) {
        close($OUTPUTTOSERVER);
        SGX::Exception::User->throw(
            error => "No input records found in file\n" );
    }
    close($OUTPUTTOSERVER);

    #--------------------------------------------
    #Now get the temp file into a temp MYSQL table.

    #Get time to make our unique ID.
    #Make idea with the time and ID of the running application.
    my $processID = time() . '_' . getppid();

    #Command to create temp table.
    my $createTableStatement = sprintf(
        <<"END_createTableStatement",
CREATE TABLE %s (
    reporter VARCHAR(150),
    ratio DOUBLE,
    foldchange DOUBLE,
    pvalue DOUBLE,
    intensity1 DOUBLE,
    intensity2 DOUBLE
)
END_createTableStatement
        $processID
    );

    #This is the mysql command to suck in the file.
    my $inputStatement = sprintf(
        <<"END_inputStatement",
LOAD DATA LOCAL INFILE %s
INTO TABLE %s
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' STARTING BY '' (
    reporter,
    ratio,
    foldchange,
    pvalue,
    intensity1,
    intensity2
)
END_inputStatement
        $self->{_dbh}->quote($outputFileName),
        $processID
    );

    # This is the mysql command to get results from temp file into the
    # microarray table.
    my $this_eid        = $self->{_eid};
    my $this_pid        = $self->{_pid};
    my $insertStatement = sprintf(
        <<"END_insertStatement",
INSERT INTO microarray (rid,eid,ratio,foldchange,pvalue,intensity2,intensity1)
SELECT
    probe.rid,
    ? as eid,
    temptable.ratio,
    temptable.foldchange,
    temptable.pvalue,
    temptable.intensity2,
    temptable.intensity1
FROM probe
INNER JOIN %s AS temptable USING(reporter)
WHERE probe.pid=?
END_insertStatement
        $processID
    );

    #This is the command to drop the temp table.
    my $dropStatement = sprintf( 'DROP TABLE %s', $processID );

    #--------------------------------------------

    #---------------------------------------------
    #Run the command to create the temp table.
    $self->{_dbh}->do($createTableStatement);

    #Run the command to suck in the data.
    $self->{_dbh}->do($inputStatement);

    #Run the command to insert the data.
    my $rowsInserted =
      $self->{_dbh}->do( $insertStatement, undef, $this_eid, $this_pid );

    # remove temporary file
    unlink $outputFileName;

    #Run the command to drop the temp table.
    $self->{_dbh}->do($dropStatement);

    #--------------------------------------------

    # :TODO:07/08/2011 10:47:36:es: find out why "< 2" is used below
    if ( $rowsInserted < 2 ) {
        SGX::Exception::User->throw(
            error => "Experiment data could not be added. "
              . "Verify that you are using the correct annotations for the platform\n"
        );
    }

    # Fills out _rowsInserted field
    $self->{_rowsInserted} = $rowsInserted;

    return $rowsInserted;
}

1;
