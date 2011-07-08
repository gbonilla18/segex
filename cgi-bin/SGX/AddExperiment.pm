
=head1 NAME

SGX::AddExperiment

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

package SGX::AddExperiment;

use strict;
use warnings;
use SGX::DropDownData;
use Data::Dumper;
use File::Temp;
use File::Path qw/remove_tree/;
use Carp;
use Switch;
use SGX::Exceptions;

#===  CLASS METHOD  ============================================================
#        CLASS:  AddExperiment
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
        _rowsInserted          => 0
    };

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  AddExperiment
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
            my $rc = eval { $self->addNewExperiment() } || 0;

            if (my $exception = $@) {
                if ( $exception->isa('SGX::Exception::User') ) {
                    # User exception
                    $self->{_error_message} = $exception->error;
                } else {
                    # Internal or DBI exception: re-throw
                    $exception-throw();
                }
            } else {
                # no error
                $self->{_message} = "Success! Rows inserted: $rc";
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
#        CLASS:  AddExperiment
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
    print $q->p({-style=>'color:red; font-weight:bold;'}, 
       $self->{_error_message}) if $self->{_error_message};
    print $q->p({-style=>'font-weight:bold;'}, 
       $self->{_message}) if $self->{_message};

    # always show form
    print $self->drawAddExperimentMenu();
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  AddExperiment
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
#        CLASS:  AddExperiment
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
#        CLASS:  AddExperiment
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
#        CLASS:  AddExperiment
#       METHOD:  drawAddExperimentMenu
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  returns array of HTML element strings
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub drawAddExperimentMenu {
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
'In order to upload experiment data the file must be in a tab separated format and the columns be as follows:'
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
#        CLASS:  AddExperiment
#       METHOD:  addNewExperiment
#   PARAMETERS:  ????
#      RETURNS:  Fills out _eid and _rowsInserted fields. Returns the number of
#      rows inserted.
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

    # :TRICKY:07/08/2011 12:52:00:es: Fills out _eid field
    $self->{_eid} = $self->{_dbh}->{'mysql_insertid'};

    #Regex to strip quotes.
    my $regex_strip_quotes = qr/^("?)(.*)\1$/;

    #We need to create an output directory in /tmp
    my $tmp       = File::Temp->new();
    my $direc_out = $tmp->filename();
    mkdir $direc_out;

    #This is where we put the temp file we will import.
    my $outputFileName = $direc_out . 'StudyData';

    #This is the temp file we use to convert.
    my $outputFileName_final = $direc_out . 'StudyData_final';

    open my $OUTPUTTEMP, '>', $outputFileName_final
      or SGX::Exception::Internal->throw(
        error => "Could not open $outputFileName_final for writing: $!\n" );

    #Write the contents of the upload to the new file.
    while (<$uploadedFile>) {
        s/\r\n|\n|\r/\n/g;
        print {$OUTPUTTEMP} $_;
    }
    close($OUTPUTTEMP);

    #Open the converted file that was uploaded.
    open my $FINALUPLOAD, '<', $outputFileName_final
      or SGX::Exception::Internal->throw(
        error => "Could not open $outputFileName_final for reading: $!\n" );

    #Open file we are writing to server.
    open my $OUTPUTTOSERVER, '>', $outputFileName
      or SGX::Exception::Internal->throw(
        error => "Could not open $outputFileName for writing: $!\n" );

    #Check each line in the uploaded file and write it to our temp file.
    while (<$FINALUPLOAD>) {
        my @row = split(/ *\t */);

        # The first line should be "Reporter Name" in the first column. We don't
        # process this line.
        if ( !( $row[0] eq '"Reporter Name"' ) ) {
            for ( my $i = 0 ; $i < 6 ; $i++ ) {
                $row[$i] = '' if not defined $row[$i];
            }
            if ( $row[0] =~ $regex_strip_quotes ) {
                $row[0] = $2;
                $row[0] =~ s/,//g;
            }
            if ( $row[1] =~ $regex_strip_quotes ) {
                $row[1] = $2;
                $row[1] =~ s/,//g;
            }
            if ( $row[2] =~ $regex_strip_quotes ) {
                $row[2] = $2;
                $row[2] =~ s/,//g;
            }
            if ( $row[3] =~ $regex_strip_quotes ) {
                $row[3] = $2;
                $row[3] =~ s/,//g;
            }
            if ( $row[4] =~ $regex_strip_quotes ) {
                $row[4] = $2;
                $row[4] =~ s/,//g;
            }
            if ( $row[5] =~ $regex_strip_quotes ) {
                $row[5] = $2 . "\n";
                $row[5] =~ s/,//g;
                $row[5] =~ s/\"//g;
            }

            #Make sure we have a value for each column.
            if (   !exists( $row[0] )
                || !exists( $row[1] )
                || !exists( $row[2] )
                || !exists( $row[3] )
                || !exists( $row[4] )
                || !exists( $row[5] ) )
            {
                SGX::Exception::User->throw(
                    error => "File not in correct format\n" );
            }

            print {$OUTPUTTOSERVER}
              join( '|', ( $self->{_stid}, @row[ 0 .. 5 ] ) );
        }
    }
    close($OUTPUTTOSERVER);
    close($FINALUPLOAD);

    #--------------------------------------------
    #Now get the temp file into a temp MYSQL table.

    #Get time to make our unique ID.
    #Make idea with the time and ID of the running application.
    my $processID = time() . '_' . getppid();

    #Command to create temp table.
    my $createTableStatement = sprintf(
        <<"END_createTableStatement",
CREATE TABLE %s (
    stid INT(1),
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
FIELDS TERMINATED BY '|'
LINES TERMINATED BY '\n' (
    stid,
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

    #Run the command to drop the temp table.
    $self->{_dbh}->do($dropStatement);

    #--------------------------------------------

    #Remove the temp directory.
    remove_tree($direc_out);

    # :TODO:07/08/2011 10:47:36:es: find out why "< 2" is used below
    if ( $rowsInserted < 2 ) {
        SGX::Exception::User->throw(
            error => "Experiment data could not be added. "
              . "Verify that you are using the correct annotations for the platform\n"
        );
    }

    # :TRICKY:07/08/2011 12:52:24:es: Fills out _rowsInserted field
    $self->{_rowsInserted} = $rowsInserted;

    return $rowsInserted;
}

1;
