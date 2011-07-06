
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

    # This is the constructor
    my $class = shift;

    my $self = {
        _dbh          => shift,
        _cgi          => shift,
        _QueryingPage => shift,
        _InsertQuery =>
'INSERT INTO experiment (sample1,sample2,ExperimentDescription,AdditionalInformation) VALUES (\'{0}\',\'{1}\',\'{2}\',\'{3}\');',
        _stid => '',
        _pid  => '',
        _PlatformQuery =>
          "SELECT pid,CONCAT(pname ,\' \\\\ \',species) FROM platform;",
        _platformList => {},

        #_platformValue            => (),
        _sample1               => '',
        _sample2               => '',
        _ExperimentDescription => '',
        _AdditionalInfo        => ''
    };

    bless $self, $class;
    return $self;
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
    $self->{_ExperimentDescription} = ( $self->{_cgi}->param('ExperimentName') )
      if defined( $self->{_cgi}->param('ExperimentName') );
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
        -action  => $q->url( -absolute => 1 ) . '?a=' . $self->{_QueryingPage},
        -enctype => 'multipart/form-data',
        -onsubmit =>
'return validate_fields(this, [\'Sample1\',\'Sample2\',\'UploadFile\']);'
      ),
      $q->p(
'In order to upload experiment data the file must be in a tab separated format and the columns be as follows.'
      ),
      $q->p(
'<b>Reporter Name, Ratio, Fold Change, P-value, Intensity 1, Intensity 2</b>'
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
        $q->dt( $q->label( { -for => 'ExperimentName' }, 'Experiment Name:' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'ExperimentName',
                -id        => 'ExperimentName',
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
        $q->dt( $q->label( { -for => 'UploadFile' }, 'Data File to Upload:' ) ),
        $q->dd(
            $q->filefield(
                -name => 'UploadFile',
                -id   => 'UploadFile'
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->submit(
                -name  => 'AddExperiment',
                -id    => 'AddExperiment',
                -class => 'css3button',
                -value => 'Add Experiment'
            )
        )
      ),
      $q->end_form;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  AddExperiment
#       METHOD:  addNewExperiment
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Performs actual upload and data validation
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub addNewExperiment {

    #Get reference to our object.
    my $self = shift;

    #The is the file handle of the uploaded file.
    my $uploadedFile = $self->{_cgi}->upload('UploadFile');

    if ( !$uploadedFile ) {
        print
"File failed to upload. Please press the back button on your browser and try again.<br />\n";
        exit;
    }
    else {
        my $insertStatement = $self->{_InsertQuery};

        $insertStatement =~ s/\{0\}/\Q$self->{_sample1}\E/;
        $insertStatement =~ s/\{1\}/\Q$self->{_sample2}\E/;
        $insertStatement =~ s/\{2\}/\Q$self->{_ExperimentDescription}\E/;
        $insertStatement =~ s/\{3\}/\Q$self->{_AdditionalInfo}\E/;

        $self->{_dbh}->do($insertStatement);

        $self->{_eid} = $self->{_dbh}->{'mysql_insertid'};

        #Get time to make our unique ID.
        my $time = time();

        #Make idea with the time and ID of the running application.
        my $processID = $time . '_' . getppid();

        #Regex to strip quotes.
        my $regex_strip_quotes = qr/^("?)(.*)\1$/;

        my $tmp = File::Temp->new();

        #We need to create this output directory.
        my $direc_out = $tmp->filename();
        mkdir $direc_out;

        #This is where we put the temp file we will import.
        my $outputFileName = $direc_out . "StudyData";

        #This is the temp file we use to convert.
        my $outputFileName_final = $direc_out . "StudyData_final";

        open my $OUTPUTTEMP, '>', $outputFileName_final
          or croak "Could not open $outputFileName_final for writing: $!";

        #Write the contents of the upload to the new file.
        while (<$uploadedFile>) {
            s/\r\n|\n|\r/\n/g;
            print {$OUTPUTTEMP} $_;
        }
        close($OUTPUTTEMP);

        #Open the converted file that was uploaded.
        open my $FINALUPLOAD, '<', $outputFileName_final
          or croak "Could not open $outputFileName_final for reading $!";

        #Open file we are writing to server.
        open my $OUTPUTTOSERVER, '>', $outputFileName
          or croak "Could not open $outputFileName for writing: $!";

        #Check each line in the uploaded file and write it to our temp file.
        while (<$FINALUPLOAD>) {
            my @row = split(/ *\t */);

#The first line should be "Reporter Name" in the first column. We don't process this line.
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
                    print
"File not found to be in correct format. Please press the back button on your browser and try again.\n";
                    exit;
                }
                print {$OUTPUTTOSERVER}
                  join( '|', ( $self->{_stid}, @row[ 0 .. 5 ] ) );
            }
        }
        close($OUTPUTTOSERVER);
        close($FINALUPLOAD);

        #--------------------------------------------
        #Now get the temp file into a temp MYSQL table.

        #Command to create temp table.
        my $createTableStatement = <<"END_createTableStatement";
CREATE TABLE $processID (
    stid INT(1),
    reporter VARCHAR(150),
    ratio DOUBLE,
    foldchange DOUBLE,
    pvalue DOUBLE,
    intensity1 DOUBLE,
    intensity2 DOUBLE
)
END_createTableStatement

        #This is the mysql command to suck in the file.
        my $inputStatement = <<"END_inputStatement";
LOAD DATA LOCAL INFILE '$outputFileName'
INTO TABLE $processID
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

#This is the mysql command to get results from temp file into the microarray table.
        my $this_eid = $self->{_eid};
        my $this_pid = $self->{_pid};
        $insertStatement = <<"END_insertStatement";
INSERT INTO microarray (rid,eid,ratio,foldchange,pvalue,intensity2,intensity1)
SELECT
    probe.rid,
    $this_eid as eid,
    temptable.ratio,
    temptable.foldchange,
    temptable.pvalue,
    temptable.intensity2,
    temptable.intensity1
FROM probe
INNER JOIN $processID AS temptable USING(reporter)
WHERE probe.pid=$this_pid
END_insertStatement

        #This is the command to drop the temp table.
        my $dropStatement = "DROP TABLE $processID;";

        #--------------------------------------------

        #---------------------------------------------
        #Run the command to create the temp table.
        $self->{_dbh}->do($createTableStatement);

        #Run the command to suck in the data.
        $self->{_dbh}->do($inputStatement);

        #Run the command to insert the data.
        my $rowsInserted = $self->{_dbh}->do($insertStatement)
          or croak "No rows inserted!";

        #Run the command to drop the temp table.
        $self->{_dbh}->do($dropStatement);

        #--------------------------------------------

        #Remove the temp directory.
        remove_tree($direc_out);

        if ( $rowsInserted < 2 ) {
            print
"Experiment data could not be added. Please verify you are using the correct annotations for the platform.\n";
            exit;
        }
        else {
            print "Experiment data added. $rowsInserted probes found.\n";
        }
    }
    return 1;
}

1;
