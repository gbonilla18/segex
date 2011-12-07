package SGX::UploadData;

use strict;
use warnings;

use SGX::Debug;
use SGX::Abstract::Exception ();
use Scalar::Util qw/looks_like_number/;

# Note: expression 'my ($x) = shift =~ /(.*)/' untaints input value and
# assigns it to $x (untainting is important when perl -T option is used).
my @parser = (
    sub {

        # Regular expression for the first column (probe/reporter id) reads as
        # follows: from beginning to end, match any character other than [space,
        # forward/back slash, comma, equal or pound sign, opening or closing
        # parentheses, double quotation mark] from 1 to 18 times.
        if ( shift =~ m/^([^\s,\/\\=#()"]{1,18})$/ ) {
            return $1;
        }
        else {
            SGX::Exception::User->throw(
                error => 'Cannot parse probe ID at line ' . shift );
        }
    },
    sub {

        # :TODO:07/31/2011 22:45:15:es: add bounds checking for numeric input
        my ($x) = shift =~ /(.*)/;
        if ( looks_like_number($x) ) {
            return $x;
        }
        else {
            SGX::Exception::User->throw(
                error => 'Second column not numeric at line ' . shift );
        }
    },
    sub {

        # :TODO:07/31/2011 22:45:15:es: add bounds checking for numeric input
        my ($x) = shift =~ /(.*)/;
        if ( looks_like_number($x) ) {
            return $x;
        }
        else {
            SGX::Exception::User->throw(
                error => 'Third column not numeric at line ' . shift );
        }
    },
    sub {

        # :TODO:07/31/2011 22:45:15:es: add bounds checking for numeric input
        my ($x) = shift =~ /(.*)/;
        if ( looks_like_number($x) ) {
            return $x;
        }
        else {
            SGX::Exception::User->throw(
                error => 'Fourth column not numeric at line ' . shift );
        }
    },
    sub {

        # :TODO:07/31/2011 22:45:15:es: add bounds checking for numeric input
        my ($x) = shift =~ /(.*)/;
        if ( looks_like_number($x) ) {
            return $x;
        }
        else {
            SGX::Exception::User->throw(
                error => 'Fifth column not numeric at line ' . shift );
        }
    },
    sub {

        # :TODO:07/31/2011 22:45:15:es: add bounds checking for numeric input

        my ($x) = shift =~ /(.*)/;
        if ( looks_like_number($x) ) {
            return $x;
        }
        else {
            SGX::Exception::User->throw(
                error => 'Sixth column not numeric at line ' . shift );
        }
    }
);

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
    my $class = shift;

    my %args          = @_;
    my $delegate_data = $args{delegate}->{_id_data};

    my $self = {
        _stid => $delegate_data->{stid},
        _pid  => $delegate_data->{pid},

        _recordsInserted => undef,

        @_
    };

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  uploadData
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Upload data to new experiment. Main upload function: high-level
#                control over sanitizeUploadFile() and loadToDatabase() methods
#       THROWS:  SGX::Exception::Internal, Exception::Class::DBI
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub uploadData {
    my ( $self, $inputField ) = @_;

    my $delegate = $self->{delegate};
    require SGX::CSV;
    my $outputFileName =
      SGX::CSV::sanitizeUploadWithMessages( $delegate, $inputField, \@parser );

    # some valid records uploaded -- now load to the database
    my $dbh = $delegate->{_dbh};

    # turn off auto-commit to allow rollback; cache old value
    my $old_AutoCommit = $dbh->{AutoCommit};
    $dbh->{AutoCommit} = 0;

    # prepare SQL statements (all prepare errors are fatal)
    my $sth_hash = $self->loadToDatabase_prepare();

    # execute SQL statements (catch some errors)
    my $recordsLoaded =
      eval { $self->loadToDatabase_execute( $sth_hash, $outputFileName ) }
      || 0;

    if ( my $exception = $@ ) {
        $dbh->rollback;
        $self->loadToDatabase_finish($sth_hash);

        if ( $exception->isa('SGX::Exception::User') ) {

            # Catch User exceptions
            $delegate->add_message(
                { -class => 'error' },
                sprintf(
                    <<"END_User_exception",
Error loading data into the database:\n\n%s\n
No changes to the database were stored.
END_User_exception
                    $exception->error
                )
            );
        }
        elsif ( $exception->isa('Exception::Class::DBI::STH') ) {

            # Catch DBI::STH exceptions. Note: this block catches duplicate
            # key record exceptions.
            $delegate->add_message(
                { -class => 'error' },
                sprintf(
                    <<"END_DBI_STH_exception",
Error loading data into the database. The database response was:\n\n%s\n
No changes to the database were stored.
END_DBI_STH_exception
                    $exception->error
                )
            );
        }
        else {

            # Rethrow Internal and other types of exceptions.
            $exception->throw();
        }
    }
    elsif ( $recordsLoaded == 0 ) {
        $dbh->rollback;
        $self->loadToDatabase_finish($sth_hash);
        $delegate->add_message( { -class => 'error' },
            'Failed to add data to the database.' );
    }
    else {
        $dbh->commit;
        $self->loadToDatabase_finish($sth_hash);

        my $totalProbes = $self->probesPerPlatform();
        if ( $recordsLoaded == $totalProbes ) {
            $delegate->add_message(
                sprintf(
                    <<"END_FULL_SUCCESS",
Success! Data for all %d probes from the selected platform 
were added to the database.
END_FULL_SUCCESS
                    $recordsLoaded
                )
            );
        }
        elsif ( $recordsLoaded < $totalProbes ) {
            $delegate->add_message(
                sprintf(
                    <<"END_PARTIAL_SUCCESS",
You added data for %d probes out of total %d in the selected platform
(no data were added for %d probes).
END_PARTIAL_SUCCESS
                    $recordsLoaded,
                    $totalProbes,
                    $totalProbes - $recordsLoaded
                )
            );
        }
        else {

            # restore old value of AutoCommit
            $dbh->{AutoCommit} = $old_AutoCommit;

            # shouldn't happen
            SGX::Exception::Internal->throw(
                error => sprintf(
                    "Platform contains %d probes but %d were loaded\n",
                    $totalProbes, $recordsLoaded
                )
            );
        }
    }

    # restore old value of AutoCommit
    $dbh->{AutoCommit} = $old_AutoCommit;
    return $recordsLoaded;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  probesPerPlatform
#   PARAMETERS:  $pid - [optional] - platform id; if absent, will use
#                                    $self->{_pid}
#      RETURNS:  Count of probes
#  DESCRIPTION:  Returns number of probes that the current platform has
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub probesPerPlatform {
    my ( $self, $pid ) = @_;
    $pid = $self->{_pid} unless defined($pid);

    my $dbh = $self->{delegate}->{_dbh};

    my $sth = $dbh->prepare('SELECT COUNT(*) FROM probe WHERE pid=?');
    my $rc  = $sth->execute($pid);

    my ($count) = $sth->fetchrow_array;
    $sth->finish;

    return $count;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  loadToDatabase_prepare
#   PARAMETERS:  $self           - object instance
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
    my $self = shift;

    my $dbh = $self->{delegate}->{_dbh};

    # Give temporary table a unique ID using time and running process ID
    my $temp_table = time() . '_' . getppid();

    my $sth_hash = {};

    $sth_hash->{createTable} ||= $dbh->prepare(<<"END_createTable");
CREATE TEMPORARY TABLE $temp_table (
    reporter CHAR(18) NOT NULL,
    ratio DOUBLE,
    foldchange DOUBLE,
    pvalue DOUBLE,
    intensity1 DOUBLE,
    intensity2 DOUBLE
) ENGINE=MEMORY
END_createTable

    $sth_hash->{loadData} ||= $dbh->prepare(<<"END_loadData");
LOAD DATA LOCAL INFILE ?
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

    $sth_hash->{insertExperiment} = $self->{delegate}->_create_command();

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
#                $outputFileName - Name of the sanitized file to use for database
#                                  loading.
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
    my ( $self, $sth_hash, $outputFileName ) = @_;

    my ( $sth_createTable, $sth_loadData, $insertExperiment,
        $sth_insertStudyExperiment, $sth_insertResponse )
      = @$sth_hash{
        qw(createTable loadData insertExperiment insertStudyExperiment insertResponse)
      };

    #SGX::Exception::User->throw(
    #    error => "Sample 1 name is the same as that of sample 2.\n" )
    #  if ( $self->{_sample1} eq $self->{_sample2} );

    my $dbh = $self->{delegate}->{_dbh};

    # Create temporary table
    $sth_createTable->execute();

    # insert a new experiment
    my $experimentsAdded = $insertExperiment->();

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
    my $rowsLoaded = $sth_loadData->execute($outputFileName);

    # If no rows were loaded, bail out ASAP
    if ( $rowsLoaded < 1 ) {
        SGX::Exception::Internal->throw(
            error => "No rows were loaded into temporary table\n" );
    }

    # Copy data from temporary table to the microarray/reposnse table
    my $recordsInserted =
      $sth_insertResponse->execute( $this_eid, $self->{_pid} );
    $self->{_recordsInserted} = $recordsInserted;

    # Check row counts; throw error if too few or too many records were
    # inserted into the microarray/response table
    if ( my $extraRecords = $rowsLoaded - $recordsInserted ) {
        SGX::Exception::User->throw(
            error => sprintf(
                <<"END_WRONGPLATFORM",
The input file contains %d records absent from the platform you entered.
Make sure you are uploading data from a correct platform.
END_WRONGPLATFORM
                $extraRecords
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

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  loadToDatabase_finish
#   PARAMETERS:  $self        - object instance
#                $sth_hash    - reference to hash containing statement handles
#                             to be executed
#      RETURNS:  True on success
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub loadToDatabase_finish {
    my ( $self, $sth_hash ) = @_;

    for my $sth ( values %$sth_hash ) {
        $sth->finish() if ref $sth ne 'CODE';
    }

    return 1;
}

1;

__END__


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


