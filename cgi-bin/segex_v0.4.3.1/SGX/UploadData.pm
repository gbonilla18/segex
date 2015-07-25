package SGX::UploadData;

use strict;
use warnings;

use SGX::Abstract::Exception ();
use Scalar::Util qw/looks_like_number/;
use SGX::Util qw/writeFlags/;
require Data::UUID;

my %parse_types = (
    probe_id => sub {

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
    ratio => sub {

       # Note: expression 'my ($x) = shift =~ /(.*)/' untaints input value and
       # assigns it to $x (untainting is important when perl -T option is used).
        my ($x) = shift =~ /(.*)/;
        if ( looks_like_number($x) && $x >= 0 ) {
            return $x + 0.0;
        }
        else {
            SGX::Exception::User->throw(
                error => 'Ratio not a decimal r >= 0.0 on line ' . shift );
        }
    },
    fchange => sub {
        my ($x) = shift =~ /(.*)/;
        if ( looks_like_number($x) && abs($x) >= 1.0 ) {
            return $x + 0.0;
        }
        else {
            SGX::Exception::User->throw(
                error => 'Fold change not a decimal |fc| >= 1.0 ' . shift );
        }
    },
    intensity => sub {
        my ($x) = shift =~ /(.*)/;
        if ( looks_like_number($x) && $x >= 0.0 ) {
            return $x + 0.0;
        }
        else {
            SGX::Exception::User->throw(
                error => 'Intensity not a decimal >= 0 on line ' . shift );
        }
    },
    pvalue => sub {
        my ($x) = shift =~ /(.*)/;
        if ( looks_like_number($x) && $x >= 0.0 && $x <= 1.0 ) {
            return $x + 0.0;
        }
        else {
            SGX::Exception::User->throw(
                error => 'P-value not a decimal 0.0 <= p <= 1.0 on line '
                  . shift );
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
    my ( $self, %args ) = @_;
    my $delegate = $self->{delegate};
    my $update   = $args{update};

    my $q                 = $delegate->{_cgi};
    my $upload_ratio      = defined( $q->param('ratio') );
    my $upload_fchange    = defined( $q->param('fold_change') );
    my $upload_intensity1 = defined( $q->param('intensity1') );
    my $upload_intensity2 = defined( $q->param('intensity2') );
    my $upload_pvalue1    = defined( $q->param('pvalue1') );
    my $upload_pvalue2    = defined( $q->param('pvalue2') );
    my $upload_pvalue3    = defined( $q->param('pvalue3') );
    my $upload_pvalue4    = defined( $q->param('pvalue4') );

    require SGX::CSV;

    my @parser = (
        $parse_types{probe_id},
        ( $upload_ratio      ? $parse_types{ratio}     : () ),
        ( $upload_fchange    ? $parse_types{fchange}   : () ),
        ( $upload_intensity1 ? $parse_types{intensity} : () ),
        ( $upload_intensity2 ? $parse_types{intensity} : () ),
        ( $upload_pvalue1    ? $parse_types{pvalue}    : () ),
        ( $upload_pvalue2    ? $parse_types{pvalue}    : () ),
        ( $upload_pvalue3    ? $parse_types{pvalue}    : () ),
        ( $upload_pvalue4    ? $parse_types{pvalue}    : () )
    );

    my ( $outputFileNames, $recordsValid ) =
      SGX::CSV::sanitizeUploadWithMessages( $delegate, $args{filefield},
        parser => \@parser );

    my ($outputFileName) = @$outputFileNames;
    return if not defined $outputFileName;

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
            ( $upload_pvalue1    ? 'pvalue1 DOUBLE'    : () ),
            ( $upload_pvalue2    ? 'pvalue2 DOUBLE'    : () ),
            ( $upload_pvalue3    ? 'pvalue3 DOUBLE'    : () ),
            ( $upload_pvalue4    ? 'pvalue4 DOUBLE'    : () ),
            'UNIQUE KEY reporter (reporter)' )
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
            ( $upload_pvalue1    ? 'pvalue1'    : () ),
            ( $upload_pvalue2    ? 'pvalue2'    : () ),
            ( $upload_pvalue3    ? 'pvalue3'    : () ),
            ( $upload_pvalue4    ? 'pvalue4'    : () ) )
    );
    push @param, [$outputFileName];
    push @check, sub {
        my $responses    = shift;
        my $recordsFound = $responses->[-1];
        if ( $recordsFound == 0 ) {
            SGX::Exception::User->throw( error => "No records in file.\n" );
        }
        elsif ( $totalProbes > 0 && $recordsFound > $totalProbes ) {
            SGX::Exception::User->throw( error =>
"File contains $recordsFound data records but there are $totalProbes probes for this platform.\n"
            );
        }
    };

    #---------------------------------------------------------------------------
    #  2 || 3
    #---------------------------------------------------------------------------
    my $dbh = $delegate->{_dbh};
    if ($update) {
        push @sth, sprintf(
            <<"END_insertResponse",
UPDATE response
INNER JOIN probe ON response.rid=probe.rid AND response.eid=?
INNER JOIN $temp_table AS temptable USING(reporter)
SET %s
END_insertResponse
            join(
                ',',
                ( $upload_ratio ? 'response.ratio=temptable.ratio' : () ),
                (
                    $upload_fchange
                    ? 'response.foldchange=temptable.foldchange'
                    : ()
                ),
                (
                    $upload_intensity1
                    ? 'response.intensity1=temptable.intensity1'
                    : ()
                ),
                (
                    $upload_intensity2
                    ? 'response.intensity2=temptable.intensity2'
                    : ()
                ),
                (
                    $upload_pvalue1 ? 'response.pvalue1=temptable.pvalue1'
                    : ()
                ),
                (
                    $upload_pvalue2 ? 'response.pvalue2=temptable.pvalue2'
                    : ()
                ),
                (
                    $upload_pvalue3 ? 'response.pvalue3=temptable.pvalue3'
                    : ()
                ),
                (
                    $upload_pvalue4 ? 'response.pvalue4=temptable.pvalue4'
                    : ()
                )
            ),
        );
        $self->{_eid} = $delegate->{_id};
        push @param, [ $delegate->{_id} ];
    }
    else {

    #---------------------------------------------------------------------------
    #  INSERT/CREATE mode
    #---------------------------------------------------------------------------
        if ( $totalProbes == 0 ) {
            push @sth, <<"END_insertProbe";
INSERT INTO probe (pid, reporter)
SELECT ? as pid, reporter
FROM $temp_table
END_insertProbe
            push @param, [ $self->{_pid} ];
            push @check, undef;
        }
        push @sth, sprintf(
            <<"END_insertResponse",
INSERT INTO response (%s)
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
                ( $upload_pvalue1    ? 'pvalue1'    : () ),
                ( $upload_pvalue2    ? 'pvalue2'    : () ),
                ( $upload_pvalue3    ? 'pvalue3'    : () ),
                ( $upload_pvalue4    ? 'pvalue4'    : () ) ),
            join( ',',
                'probe.rid',
                '? as eid',
                ( $upload_ratio      ? 'temptable.ratio'      : () ),
                ( $upload_fchange    ? 'temptable.foldchange' : () ),
                ( $upload_intensity1 ? 'temptable.intensity1' : () ),
                ( $upload_intensity2 ? 'temptable.intensity2' : () ),
                ( $upload_pvalue1    ? 'temptable.pvalue1'    : () ),
                ( $upload_pvalue2    ? 'temptable.pvalue2'    : () ),
                ( $upload_pvalue3    ? 'temptable.pvalue3'    : () ),
                ( $upload_pvalue4    ? 'temptable.pvalue4'    : () ) )
        );

        # study id must be defined and numeric for a study link to be created
        my $create_cmd1 = $delegate->_create_command();
        my $create_cmd2 =
          ( defined( $self->{_stid} ) && $self->{_stid} =~ m/^\d+$/ )
          ? $dbh->prepare(
            'INSERT INTO StudyExperiment (stid, eid) VALUES (?, ?)')
          : undef;
        push @param, [
            sub {
                $create_cmd1->();
                my $eid =
                  $dbh->last_insert_id( undef, undef, 'experiment', 'eid' );
                $self->{_eid} = $eid;
                if ( defined $create_cmd2 ) {
                    $create_cmd2->execute( $self->{_stid}, $eid );
                    $create_cmd2->finish();
                }
                return $eid;
            },
            $self->{_pid}
        ];

        # updating records (instead of inserting) will cause recordsAdded to be
        # zero, and changes will be rolled back. Therefore we allow these checks
        # only in INSERT/CREATE mode.
        push @check, sub {
            my $responses     = shift;
            my $recordsAdded  = $responses->[-1];
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
    }

    #---------------------------------------------------------------------------
    #   write PValFlag
    #---------------------------------------------------------------------------
    push @sth, 'UPDATE experiment SET PValFlag = (PValFlag | ?) WHERE eid=?';
    push @param,
      [
        writeFlags(
            $upload_pvalue1, $upload_pvalue2,
            $upload_pvalue3, $upload_pvalue4
        ),
        sub { return $self->{_eid}; }
      ];

    # reporting penultimate error code (index -2) because the last one is
    # statement updating experiment record itself.
    return SGX::CSV::delegate_fileUpload(
        delegate              => $delegate,
        return_code_to_report => -2,
        statements            => \@sth,
        parameters            => \@param,
        validators            => \@check,
        filename              => $outputFileName
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


