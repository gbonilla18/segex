
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

use JSON::XS;
use SGX::CSV;
use SGX::DropDownData;
use Data::Dumper;
use File::Temp;
use Carp;
use Switch;
use SGX::Exceptions;
use SGX::Model::PlatformStudyExperiment;
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

        #
        _PlatformStudyExperiment =>
          SGX::Model::PlatformStudyExperiment->new( dbh => $dbh ),

        # URL params
        _stid           => '',
        _pid            => '',
        _sample1        => '',
        _sample2        => '',
        _ExperimentDesc => '',
        _AdditionalInfo => '',

        #
        _recordsInserted => undef
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

    my ( $q,          $s )           = @$self{qw{_cgi _UserSession}};
    my ( $js_src_yui, $js_src_code ) = @$self{qw{_js_src_yui _js_src_code}};

    my $action =
      ( defined $q->param('b') )
      ? $q->param('b')
      : '';

    return if not $s->is_authorized('user');

    push @$js_src_yui, ('yahoo-dom-event/yahoo-dom-event.js');
    push @$js_src_code, { -src => 'PlatformStudyExperiment.js' };
    $self->{_PlatformStudyExperiment}->init(
        platforms         => 1,
        studies           => 1,
        platform_by_study => 1,
        empty_study       => 'Unassigned Experiments'
    );
    $self->init();

    switch ($action) {
        case 'Upload' {
            $self->uploadData();

            # show form
            push @$js_src_code, { -code => $self->getDropDownJS() };
        }
        else {

            # default: show form
            push @$js_src_code, {
                -code => $self->getDropDownJS()
            };
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

    my ( $q, $s ) = @$self{qw{_cgi _UserSession}};

    #my $action =
    #  ( defined $q->param('b') )
    #  ? $q->param('b')
    #  : '';

    # notice about rows added or error message
    print $q->pre( { -style => 'color:red; font-weight:bold;' },
        $self->{_error_message} )
      if $self->{_error_message};
    print $q->pre( { -style => 'font-weight:bold;' }, $self->{_message} )
      if $self->{_message};

    # always show form
    print $self->showForm();
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Get state (mostly from CGI parameters)
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my $self = shift;

    my $q = $self->{_cgi};

    $self->{_sample1} = $q->param('sample1');
    $self->{_sample2} = $q->param('sample2');
    my $stid = $q->param('stid');
    if ( defined $stid ) {
        $self->{_stid} = $stid;

        # If a study is set, use th corresponding platform while ignoring the
        # platform parameter. Also update the _pid field with the platform id
        # obtained from the lookup by study id.
        my $pid =
          $self->{_PlatformStudyExperiment}->getPlatformFromStudy($stid);
        $self->{_pid} = ( defined $pid ) ? $pid : $q->param('pid');
    }
    $self->{_ExperimentDesc} = $q->param('ExperimentDesc');
    $self->{_AdditionalInfo} = $q->param('AdditionalInfo');
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  getDropDownJS
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Returns JSON data plus JavaScript code required to build
#                platform and study dropdowns
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getDropDownJS {
    my $self = shift;

    my $PlatfStudyExp =
      encode_json( $self->{_PlatformStudyExperiment}->get_ByPlatform() );

    my $currentSelection = encode_json(
        {
            'platform' => {
                element   => undef,
                selected  => +{ $self->{_pid} => undef },
                elementId => 'pid'
            },
            'study' => {
                element   => undef,
                selected  => +{ $self->{_stid} => undef },
                elementId => 'stid'
            }
        }
    );

    return <<"END_ret";
var PlatfStudyExp = $PlatfStudyExp;
var currentSelection = $currentSelection;
YAHOO.util.Event.addListener(window, 'load', function() {
    populatePlatform.apply(currentSelection);
    populatePlatformStudy.apply(currentSelection);
});
YAHOO.util.Event.addListener(currentSelection.platform.elementId, 'change', function() {
    populatePlatformStudy.apply(currentSelection);
});
END_ret
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  showForm
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  returns array of HTML element strings
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub showForm {
    my $self = shift;
    my $q    = $self->{_cgi};

    return
      $q->h2('Upload Data to a New Experiment'),
      $q->start_form(
        -method  => 'POST',
        -action  => $q->url( -absolute => 1 ) . '?a=uploadData',
        -enctype => 'multipart/form-data',
        -onsubmit =>
          'return validate_fields(this, [\'sample1\',\'sample2\',\'file\']);'
      ),
      $q->p(<<"END_TEXT1"),
The data file must be in plain-text tab-delimited format with the following six
columns:
END_TEXT1
      $q->pre(
        'Probe Name, Ratio, Fold Change, P-value, Intensity 1, Intensity 2'),
      $q->p(<<"END_TEXT2"),
The first column can be either a number or a string; the remaining five columns
must be numeric.  Make sure the first row in the file contains a header (actual
data should start with the second row).
END_TEXT2
      $q->dl(
        $q->dt( $q->label( { -for => 'pid' }, 'Platform:' ) ),
        $q->dd(
            $q->popup_menu(
                -name => 'pid',
                -id   => 'pid'
            )
        ),
        $q->dt( $q->label( { -for => 'stid' }, 'Study:' ) ),
        $q->dd(
            $q->popup_menu(
                -name => 'stid',
                -id   => 'stid'
            )
        ),
        $q->dt( $q->label( { -for => 'sample1' }, 'Sample 1:' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'sample1',
                -id        => 'sample1',
                -maxlength => 120
            )
        ),
        $q->dt( $q->label( { -for => 'sample2' }, 'Sample 2:' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'sample2',
                -id        => 'sample2',
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
#       METHOD:  uploadData
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Main upload function: high-level control over
#                sanitizeUploadFile() and loadToDatabase() methods
#       THROWS:  SGX::Exception::Internal, Exception::Class::DBI
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub uploadData {
    my $self = shift;

    # upload data to new experiment
    my $recordsLoaded = 0;

    # This is where we put the temp file we will import. UNLINK option to
    # File::Temp constructor means that the File::Temp destructor will try to
    # unlink the temporary file on its own (we don't need to worry about
    # unlinking). Because we are initializing an instance of File::Temp in the
    # namespace of this function, the temporary file will be deleted when the
    # function exists (when the reference to File::Temp will go out of context).
    #
    my $tmp = File::Temp->new( SUFFIX => '.txt', UNLINK => 1 );
    my $outputFileName = $tmp->filename();

    my $recordsValid = eval { $self->sanitizeUploadFile($outputFileName) } || 0;

    if ( my $exception = $@ ) {

        # Notify user of User exception; rethrow Internal and other types of
        # exceptions.
        if ( $exception->isa('SGX::Exception::User') ) {
            $self->{_error_message} =
              'There was a problem with your input: ' . $exception->error;
        }
        else {
            $exception->throw();
        }
    }
    elsif ( $recordsValid == 0 ) {
        $self->{_error_message} = 'No valid records were uploaded.';
    }
    else {

        # some valid records uploaded -- now load to the database
        my $dbh = $self->{_dbh};

        # turn off auto-commit to allow rollback; cache old value
        my $old_AutoCommit = $dbh->{AutoCommit};
        $dbh->{AutoCommit} = 0;

        # prepare SQL statements (all prepare errors are fatal)
        my $sth_hash = $self->loadToDatabase_prepare($outputFileName);

        # execute SQL statements (catch some errors)
        $recordsLoaded = eval { $self->loadToDatabase_execute($sth_hash) } || 0;

        if ( my $exception = $@ ) {
            $dbh->rollback;

            # Catch User and DBI::STH exceptions; rethrow Internal and other
            # types of exceptions
            if (   $exception->isa('SGX::Exception::User')
                || $exception->isa('Exception::Class::DBI::STH') )
            {

                # Note: this block catches duplicate key record exceptions
                $self->{_error_message} = sprintf(
                    <<"END_error_message",
Error loading data into the database. The response was:

%s

No changes to the database were stored.
END_error_message
                    $exception->error
                );
            }
            else {
                $exception->throw();
            }
        }
        elsif ( $recordsLoaded == 0 ) {
            $dbh->rollback;
            $self->{_error_message} = 'Failed to add data to the database.';
        }
        else {
            $dbh->commit;
            $self->{_message} =
              sprintf( 'Success: %d records loaded', $recordsLoaded );
        }

        # restore old value of AutoCommit
        $dbh->{AutoCommit} = $old_AutoCommit;
    }
    return $recordsLoaded;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  sanitizeUploadFile
#   PARAMETERS:  $outputFileName - Name of the temporary file to write to
#      RETURNS:  Number of valid records found (also duplicated to _validRecords
#                field)
#  DESCRIPTION:  validate and rewrite the uploaded file
#       THROWS:  SGX::Exception::Internal, SGX::Exception::User
#     COMMENTS:   # :TODO:07/08/2011 12:55:45:es: Make headers optional
#     SEE ALSO:  n/a
#===============================================================================
sub sanitizeUploadFile {
    my ( $self, $outputFileName ) = @_;

    my $q = $self->{_cgi};

    # The is the file handle of the uploaded file.
    my $uploadedFile = $q->upload('file')
      or
      SGX::Exception::User->throw( error => "Failed to upload input file.\n" );

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

    # upload file should get deleted automatically on close
    close $uploadedFile;

    my $recordsValid = eval {
        SGX::CSV::csv_rewrite(
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
    } || 0;

    $self->{_validRecords} = $recordsValid;

    # In case of error, close files first and rethrow the exception
    if ( my $exception = $@ ) {
        close($OUTPUTTOSERVER);
        $exception->throw();
    }
    elsif ( $recordsValid < 1 ) {
        close($OUTPUTTOSERVER);
        SGX::Exception::User->throw(
            error => "No records found in input file\n" );
    }
    close($OUTPUTTOSERVER);

    return $recordsValid;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  loadToDatabase_prepare
#   PARAMETERS:  $self           - object instance
#                $outputFileName - Name of the sanitized file to use for database
#                                  loading.
#      RETURNS:  Hash reference containing prepared statements
#  DESCRIPTION:  Prepare SQL statements used for loading data. We prepare these
#                statements separately from where they are executed because we
#                want to separate possible prepare exceptions (which are fatal
#                and do not cause rollback) from execute exceptions (which are
#                currently fatal though may be caught in the future and which
#                *do* cause rollback).
#       THROWS:  Exception::Class::DBI
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadToDatabase_prepare {
    my ( $self, $outputFileName ) = @_;

    my $dbh = $self->{_dbh};

    # Give temporary table a unique ID using time and running process ID
    my $temp_table = time() . '_' . getppid();

    my $sth_hash = {};

    $sth_hash->{createTable} ||= $dbh->prepare(<<"END_createTable");
CREATE TEMPORARY TABLE $temp_table (
    reporter VARCHAR(150) NOT NULL,
    ratio DOUBLE,
    foldchange DOUBLE,
    pvalue DOUBLE,
    intensity1 DOUBLE,
    intensity2 DOUBLE
) ENGINE=MEMORY
END_createTable

    $sth_hash->{loadData} ||= $dbh->prepare(
        sprintf(
            <<"END_loadData",
LOAD DATA LOCAL INFILE %s
INTO TABLE $temp_table
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' STARTING BY '' (
    reporter,
    ratio,
    foldchange,
    pvalue,
    intensity1,
    intensity2
)
END_loadData
            $dbh->quote($outputFileName),
        )
    );

    $sth_hash->{insertResponse} ||= $dbh->prepare(<<"END_insert");
INSERT INTO microarray (rid,eid,ratio,foldchange,pvalue,intensity1,intensity2)
SELECT
    probe.rid,
    ? as eid,
    temptable.ratio,
    temptable.foldchange,
    temptable.pvalue,
    temptable.intensity1,
    temptable.intensity2
FROM probe
INNER JOIN $temp_table AS temptable USING(reporter)
WHERE probe.pid=?
END_insert

    $sth_hash->{insertExperiment} ||= $dbh->prepare(<<"END_insertExperiment");
INSERT INTO experiment (
    pid,
    sample1,
    sample2,
    ExperimentDescription,
    AdditionalInformation
) VALUES (?, ?, ?, ?, ?)
END_insertExperiment

    $sth_hash->{insertStudyExperiment} ||=
      ( defined $self->{_stid} )
      ? $dbh->prepare('INSERT INTO StudyExperiment (stid, eid) VALUES (?, ?)')
      : undef;

    return $sth_hash;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  loadToDatabase_execute
#   PARAMETERS:  $self        - object instance
#                $sth_hash    - reference to hash containing statement handles
#                               to be executed
#      RETURNS:  Number of records inserted into the microarray table (also
#                duplicated as _recordsInserted field). Fills _eid field
#                (corresponds to the id of the added experiment).
#  DESCRIPTION:  Runs SQL statements
#       THROWS:  SGX::Exception::Internal, SGX::Exception::User,
#                Exception::Class::DBI
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadToDatabase_execute {
    my ( $self, $sth_hash ) = @_;

    my ( $sth_createTable, $sth_loadData, $sth_insertExperiment,
        $sth_insertStudyExperiment, $sth_insertResponse )
      = @$sth_hash{
        qw(createTable loadData insertExperiment insertStudyExperiment insertResponse)
      };

    my $dbh = $self->{_dbh};

    # Create temporary table
    $sth_createTable->execute();

    # Insert a new experiment
    my $experimentsAdded = $sth_insertExperiment->execute(
        $self->{_pid}, $self->{_sample1}, $self->{_sample2},
        $self->{_ExperimentDesc},
        $self->{_AdditionalInfo}
    );

    # Check that experiment was actually added
    if ( $experimentsAdded < 1 ) {
        SGX::Exception::Internal->throw(
            error => "Failed to create new experiment\n" );
    }

    # Grab the id of the experiment inserted
    my $this_eid = $dbh->{mysql_insertid};
    $self->{_eid} = $this_eid;

    # Add experiment to study if study id is defined
    $sth_insertStudyExperiment->execute( $self->{_stid}, $this_eid )
      if defined($sth_insertStudyExperiment);

    # Suck in the data into the temporary table
    my $rowsLoaded = $sth_loadData->execute();

    # If no rows were loaded, bail out ASAP
    if ( $rowsLoaded < 1 ) {
        SGX::Exception::Internal->throw(
            error => "No rows were loaded into temporary table\n" );
    }

    # Copy data from temporary table to the microarray/reposnse table
    my $recordsInserted =
      $sth_insertResponse->execute( $this_eid, $self->{_pid} );
    $self->{_recordsInserted} = $recordsInserted;

    # Check row counts; throw errors if too few or too many records were
    # inserted into the microarray/reposnse table
    if ( $recordsInserted < $rowsLoaded ) {
        SGX::Exception::User->throw(
            error => sprintf(
                <<"END_WRONGPLATFORM",
Found %d rows in the uploaded file, but %d records were 
loaded into the database (failed to load %d probes). 
Check that you are uploading data to the correct platform.
END_WRONGPLATFORM
                $rowsLoaded,
                $recordsInserted,
                $rowsLoaded - $recordsInserted
            )
        );
    }
    elsif ( $recordsInserted > $rowsLoaded ) {
        SGX::Exception::Internal->throw(
            error => "More probe records were updated than rows uploaded\n" );
    }

    # Return the number of records inserted into the microarray/reposnse table
    return $recordsInserted;
}

1;
