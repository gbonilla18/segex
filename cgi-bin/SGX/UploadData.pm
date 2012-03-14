package SGX::UploadData;

use strict;
use warnings;

use SGX::Debug;
use SGX::Abstract::Exception ();
use Scalar::Util qw/looks_like_number/;
require Data::UUID;

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
                error => 'Cannot parse probe ID on line ' . shift );
        }
    },
    (
        $upload_ratio
        ? sub {

       # Note: expression 'my ($x) = shift =~ /(.*)/' untaints input value and
       # assigns it to $x (untainting is important when perl -T option is used).
            my ($x) = shift =~ /(.*)/;
            if ( looks_like_number($x) && $x >= 0 ) {
                return $x;
            }
            else {
                SGX::Exception::User->throw(
                    error => 'Ratio not a decimal r >= 0.0 on line ' . shift );
            }
          }
        : ()
    ),
    (
        $upload_fchange
        ? sub {
            my ($x) = shift =~ /(.*)/;
            if ( looks_like_number($x) && abs($x) >= 1.0 ) {
                return $x;
            }
            else {
                SGX::Exception::User->throw(
                    error => 'Fold change not a decimal |fc| >= 1.0 ' . shift );
            }
          }
        : ()
    ),
    (
        $upload_intensity1
        ? sub {
            my ($x) = shift =~ /(.*)/;
            if ( looks_like_number($x) && $x >= 0.0 ) {
                return $x;
            }
            else {
                SGX::Exception::User->throw(
                    error => 'Intensity 1 not a decimal i1 >= 0 on line '
                      . shift );
            }
          }
        : ()
    ),
    (
        $upload_intensity2
        ? sub {
            my ($x) = shift =~ /(.*)/;
            if ( looks_like_number($x) && $x >= 0.0 ) {
                return $x;
            }
            else {
                SGX::Exception::User->throw(
                    error => 'Intensity 2 not a decimal i2 >= 0 on line '
                      . shift );
            }
          }
        : ()
    ),
    (
        $upload_pvalue
        ? sub {
            my ($x) = shift =~ /(.*)/;
            if ( looks_like_number($x) && $x >= 0.0 && $x <= 1.0 ) {
                return $x;
            }
            else {
                SGX::Exception::User->throw(
                    error => 'P-value not a decimal 0.0 <= p <= 1.0 on line '
                      . shift );
            }
          }
        : ()
    )
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
    my ( $self, %args ) = @_;
    my $delegate = $self->{delegate};

    my $q                 = $delegate->{_cgi};
    my $upload_ratio      = defined( $q->param('ratio') );
    my $upload_fchange    = defined( $q->param('fold_change') );
    my $upload_intensity1 = defined( $q->param('intensity1') );
    my $upload_intensity2 = defined( $q->param('intensity2') );
    my $upload_pvalue     = defined( $q->param('pvalue') );
    my $upload_pvalue2    = defined( $q->param('pvalue2') );
    my $upload_pvalue3    = defined( $q->param('pvalue3') );

    require SGX::CSV;
    my ( $outputFileNames, $recordsValid ) =
      SGX::CSV::sanitizeUploadWithMessages( $delegate, $args{filefield},
        parser => \@parser );

    my ($outputFileName) = @$outputFileNames;

    my $totalProbes = $self->countProbes();

    my $ug         = Data::UUID->new();
    my $temp_table = $ug->to_string( $ug->create() );
    $temp_table =~ s/-/_/g;
    $temp_table = "tmp$temp_table";

    my @sth;
    my @param;
    my @check;

    #---------------------------------------------------------------------------
    #  0
    #---------------------------------------------------------------------------
    push @sth,
      sprintf(
        "CREATE TEMPORARY TABLE $temp_table (%s) ENGINE=MyISAM",
        join( ',',
            'reporter CHAR(18) NOT NULL',
            ( $upload_ratio      ? 'ratio DOUBLE'      : () ),
            ( $upload_fchange    ? 'foldchange DOUBLE' : () ),
            ( $upload_intensity1 ? 'intensity1 DOUBLE' : () ),
            ( $upload_intensity2 ? 'intensity2 DOUBLE' : () ),
            ( $upload_pvalue     ? 'pvalue DOUBLE'     : () ),
            ( $upload_pvalue2    ? 'pvalue2 DOUBLE'    : () ),
            ( $upload_pvalue3    ? 'pvalue3 DOUBLE'    : () ) )
      );
    push @param, [];
    push @check, undef;

    #---------------------------------------------------------------------------
    #  1
    #---------------------------------------------------------------------------
    push @sth, sprintf(
        <<"END_loadData",
LOAD DATA LOCAL INFILE ?
INTO TABLE $temp_table
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n' STARTING BY '' (%s)
END_loadData
        join( ',',
            'reporter',
            ( $upload_ratio      ? 'ratio'      : () ),
            ( $upload_fchange    ? 'foldchange' : () ),
            ( $upload_intensity1 ? 'intensity1' : () ),
            ( $upload_intensity2 ? 'intensity2' : () ),
            ( $upload_pvalue     ? 'pvalue'     : () ),
            ( $upload_pvalue2    ? 'pvalue2'    : () ),
            ( $upload_pvalue3    ? 'pvalue3'    : () ) )
    );
    push @param, [$outputFileName];
    push @check, sub {
        my $responses    = shift;
        my $recordsFound = $responses->[$#$responses];
        if ( $recordsFound == 0 ) {
            SGX::Exception::User->throw( error => "No records in file.\n" );
        }
        elsif ( $totalProbes > 0 && $recordsFound > $totalProbes ) {
            SGX::Exception::User->throw( error =>
"File contains $recordsFound data records but there are $totalProbes probes for this platform.\n"
            );
        }
    };

    if ( $totalProbes == 0 ) {

    #---------------------------------------------------------------------------
    #  2
    #---------------------------------------------------------------------------
        push @sth, <<"END_insertProbe";
INSERT INTO probe (pid, reporter)
SELECT ? as pid, reporter
FROM $temp_table
END_insertProbe
        push @param, [ $self->{_pid} ];
        push @check, undef;
    }

    #---------------------------------------------------------------------------
    #  2 || 3
    #---------------------------------------------------------------------------
    push @sth, sprintf(
        <<"END_insertResponse",
INSERT INTO microarray (%s)
SELECT %s FROM probe
INNER JOIN $temp_table AS temptable USING(reporter)
WHERE probe.pid=?
END_insertResponse
        join( ',',
            'rid',
            'eid',
            ( $upload_ratio      ? 'ratio'      : () ),
            ( $upload_fchange    ? 'foldchange' : () ),
            ( $upload_intensity1 ? 'intensity1' : () ),
            ( $upload_intensity2 ? 'intensity2' : () ),
            ( $upload_pvalue     ? 'pvalue'     : () ),
            ( $upload_pvalue2    ? 'pvalue2'    : () ),
            ( $upload_pvalue3    ? 'pvalue3'    : () ) ),
        join( ',',
            'probe.rid',
            '? as eid',
            ( $upload_ratio      ? 'temptable.ratio'      : () ),
            ( $upload_fchange    ? 'temptable.foldchange' : () ),
            ( $upload_intensity1 ? 'temptable.intensity1' : () ),
            ( $upload_intensity2 ? 'temptable.intensity2' : () ),
            ( $upload_pvalue     ? 'temptable.pvalue'     : () ),
            ( $upload_pvalue2    ? 'temptable.pvalue2'    : () ),
            ( $upload_pvalue3    ? 'temptable.pvalue3'    : () ) )
    );

    my $create_cmd1 = $delegate->_create_command();
    my $dbh = $delegate->{_dbh};
    my $create_cmd2 =
      defined( $self->{_stid} )
      ? $dbh->prepare('INSERT INTO StudyExperiment (stid, eid) VALUES (?, ?)')
      : undef;

    push @param, [
        sub {
            $create_cmd1->();
            my $eid = $dbh->last_insert_id( undef, undef, 'experiment', 'eid' );
            $self->{_eid} = $eid;
            if ( defined $create_cmd2 ) {
                $create_cmd2->execute( $self->{_stid}, $eid );
                $create_cmd2->finish();
            }
            return $eid;
        },
        $self->{_pid}
    ];

    push @check, sub {
        my $responses     = shift;
        my $recordsAdded  = $responses->[$#$responses];
        my $probeCount    = $totalProbes || $responses->[2];
        my $recordsLoaded = $responses->[1];
        if ( $recordsAdded != $recordsLoaded ) {
            my $msg =
"$recordsLoaded records found in input but only $recordsAdded could be added to database\n";
            SGX::Exception::User->throw( error => $msg );
        }
        elsif ( $recordsAdded > $probeCount ) {
            SGX::Exception::User->throw(
                error => "Uploaded file contains duplicate data.\n" );
        }
        elsif ( $recordsAdded < $probeCount ) {
            my $msg =
"WARNING: Added data to $recordsAdded probes (out of $probeCount probes under this platform)";
            $delegate->add_message( { -class => 'error' }, $msg );
        }
    };

    return SGX::CSV::delegate_fileUpload(
        delegate   => $delegate,
        statements => \@sth,
        parameters => \@param,
        validators => \@check,
        filename   => $outputFileName
    );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  UploadData
#       METHOD:  countProbes
#   PARAMETERS:  $pid - [optional] - platform id; if absent, will use
#                                    $self->{_pid}
#      RETURNS:  Count of probes
#  DESCRIPTION:  Returns number of probes that the current platform has
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub countProbes {
    my ( $self, $pid ) = @_;
    $pid = $self->{_pid} unless defined($pid);

    my $dbh = $self->{delegate}->{_dbh};

    my $sth     = $dbh->prepare('SELECT COUNT(*) FROM probe WHERE pid=?');
    my $rc      = $sth->execute($pid);
    my ($count) = $sth->fetchrow_array;
    $sth->finish;

    return $count;
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
        $sth->finish() if defined($sth) and ref $sth ne 'CODE';
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


