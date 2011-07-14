
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
        _PlatformStudyExperiment =>
          SGX::Model::PlatformStudyExperiment->new( dbh => $dbh ),
        _stid                  => '',
        _pid                   => '',
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

    my ( $q, $s ) = @$self{qw{_cgi _UserSession}};
    my ( $js_src_yui, $js_src_code ) = @$self{qw{_js_src_yui _js_src_code}};

    my $action =
      ( defined $q->param('b') )
      ? $q->param('b')
      : '';

    return if not $s->is_authorized('user');

    push @$js_src_yui, ('yahoo-dom-event/yahoo-dom-event.js');
    push @$js_src_code, { -src => 'PlatformStudyExperiment.js' };
    $self->{_PlatformStudyExperiment}->init(
        platforms          => 1,
        studies            => 1,
        platform_by_study  => 1,
        empty_platform     => 'Create New Platform',
        empty_study        => 'Do not assign'
    );
    $self->init();

    switch ($action) {
        case 'Upload' {

            # upload data to new experiment
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
            elsif ( $rows_inserted == 0 ) {
                $self->{_error_message} = 'No records were added.';
            }
            else {
                $self->{_message} = "Success! Records added: $rows_inserted";
            }

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
    print $q->p( { -style => 'color:red; font-weight:bold;' },
        $self->{_error_message} )
      if $self->{_error_message};
    print $q->p( { -style => 'font-weight:bold;' }, $self->{_message} )
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

    $self->{_sample1} = $q->param('Sample1');
    $self->{_sample2} = $q->param('Sample2');
    my $stid = $q->param('stid');
    if ( defined $stid ) {
        $self->{_stid} = $stid;
        my $pid =
          $self->{_PlatformStudyExperiment}->get_ByStudy()->{$stid}->{pid};
        $self->{_pid} = ( defined $pid ) ? $pid : $q->param('pid');
    }
    $self->{_ExperimentDescription} = $q->param('ExperimentDesc');
    $self->{_AdditionalInfo}        = $q->param('AdditionalInfo');
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

    return <<"END_ret";
var PlatfStudyExp = $PlatfStudyExp;
YAHOO.util.Event.addListener(window, 'load', function() {
    populatePlatform();
    populatePlatformStudy();
});
YAHOO.util.Event.addListener('pid', 'change', function() {
    populatePlatformStudy();
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
    my $self = shift;

    my $dbh = $self->{_dbh};

    #---------------------------------------------------------------------------
    #  First we rewrite and validate the uploaded file
    #---------------------------------------------------------------------------
    # The is the file handle of the uploaded file.
    my $uploadedFile = $self->{_cgi}->upload('file')
      or SGX::Exception::User->throw( error => 'File failed to upload. '
          . "Be sure to enter a valid file to upload\n" );

    # This is where we put the temp file we will import. UNLINK option to
    # File::Temp constructor means that the File::Temp destructor will try to
    # unlink the temporary file on its own (we don't need to worry about
    # unlinking).
    my $tmp = File::Temp->new( SUFFIX => '.txt', UNLINK => 1 );
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
    };

    # in case of error, close files first and rethrow the exception
    if ( my $exception = $@ ) {
        close($OUTPUTTOSERVER);

        # :TRICKY:07/14/2011 13:38:58:es: this rewrites exception message
        $exception->throw(
            error => 'Failed to create new experiment: ' . $exception->error );
    }
    elsif ( $valid_records < 1 ) {
        close($OUTPUTTOSERVER);
        SGX::Exception::User->throw(
            error => 'Failed to create new experiment: '
              . "No records found in input file\n" );
    }
    close($OUTPUTTOSERVER);

    #---------------------------------------------------------------------------
    #  Create various MySQL statements
    #---------------------------------------------------------------------------
    #Make our unique ID using time and running process ID
    my $temp_table = time() . '_' . getppid();

    #Command to create temp table.
    my $createTableStatement = <<"END_createTableStatement";
CREATE TABLE $temp_table (
    reporter VARCHAR(150),
    ratio DOUBLE,
    foldchange DOUBLE,
    pvalue DOUBLE,
    intensity1 DOUBLE,
    intensity2 DOUBLE
)
END_createTableStatement

    #This is the mysql command to suck in the file into the temp table.
    my $loadDataStatement = sprintf(
        <<"END_inputStatement",
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
END_inputStatement
        $dbh->quote($outputFileName),
    );

    # This is the mysql command to insert results from the temp table into
    # microarray table.
    my $insertStatement = <<"END_insertStatement";
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
END_insertStatement

    my $addExperimentStatement = <<"END_InsertExperiment";
INSERT INTO experiment (
    pid,
    sample1,
    sample2,
    ExperimentDescription,
    AdditionalInformation
) VALUES (?, ?, ?, ?, ?)
END_InsertExperiment

    my $addStudyExperimentStatement =
      'INSERT INTO StudyExperiment (stid, eid) VALUES (?, ?)';

    my $dropExperimentStatement = 'DELETE FROM experiment WHERE eid=?';

    my $dropTableStatement = "DROP TABLE $temp_table";

    #---------------------------------------------------------------------------
    #  Run MySQL statements
    #---------------------------------------------------------------------------
    #Run the command to create the temp table.
    $dbh->do($createTableStatement);

    #Run the command to suck in the data.
    my $rowsLoaded = $dbh->do($loadDataStatement);

    # If $rowsLoaded is zero or negative, bail out ASAP
    if ( $rowsLoaded < 1 ) {
        $dbh->do($dropTableStatement);    # drop temporary table
        SGX::Exception::Internal->throw(
            error => 'Failed to create new experiment: '
              . "No rows were loaded into temporary table\n" );
    }

    # Adding a new experiment into database as late as possible
    my $this_eid;
    if (
        $dbh->do(
            $addExperimentStatement, undef,
            $self->{_pid},           $self->{_sample1},
            $self->{_sample2},       $self->{_ExperimentDescription},
            $self->{_AdditionalInfo}
        )
      )
    {

        # Grab the id of the experiment inserted
        $this_eid = $dbh->{mysql_insertid};
        $self->{_eid} = $this_eid;
    }
    else {
        $dbh->do($dropTableStatement);
        SGX::Exception::Internal->throw(
            error => "Failed to create new experiment\n" );
    }

    if ( defined $self->{_stid} ) {
        $dbh->do( $addStudyExperimentStatement, undef, $self->{_stid},
            $this_eid );
    }

    #Run the command to insert the data.
    my $recordsInserted =
      $dbh->do( $insertStatement, undef, $this_eid, $self->{_pid} );
    $self->{_rowsInserted} = $recordsInserted;

    #Run the command to drop the temp table.
    $dbh->do($dropTableStatement);

    # :TODO:07/14/2011 14:15:47:es: implement commit/rollback mechanism for data
    # upload
    #
    if ( $recordsInserted < $rowsLoaded ) {
        my $failedProbes = $rowsLoaded - $recordsInserted;
        my $prefix       = '';

        # drop experiment entirely if zero records were inserted
        if ( $recordsInserted < 1 ) {
            $dbh->do( $dropExperimentStatement, undef, $this_eid );
            $prefix = 'Failed to create new experiment: ';
        }

        SGX::Exception::User->throw(
            error => sprintf(
                <<"END_WRONGPLATFORM",
${prefix}Found %d rows in the uploaded file, but %d records were 
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
    return $recordsInserted;
}

1;
