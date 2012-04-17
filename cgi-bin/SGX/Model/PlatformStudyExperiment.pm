package SGX::Model::PlatformStudyExperiment;

use strict;
use warnings;

use Storable qw/dclone/;
use SGX::Debug;
use Hash::Merge qw/merge/;
use SGX::Abstract::Exception ();

#===  CLASS METHOD  ============================================================

#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ( $class, %args ) = @_;

    my ($dbh) = @args{qw{dbh}};

    my $self = {
        _dbh        => $dbh,
        _ByPlatform => {},
        _ByStudy    => {},

        # abstract defs
        _Platform => {
            table => 'platform LEFT JOIN species USING(sid)',
            base  => ['pid'],
            attr  => [ 'pname', 'sname', 'sid' ]
        },
        _PlatformStudy => {
            table => 'study',
            base  => [ 'pid', 'stid' ],
            attr  => ['description']
        },
        _StudyExperiment => {
            table => 'StudyExperiment',
            base  => [ 'stid', 'eid' ],
            attr  => []
        },
        _Experiment => {
            table => 'experiment',
            base  => [ 'pid', 'eid' ],
            attr  => [ 'sample1', 'sample2' ]
        },
    };

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================

#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  getter method
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_ByPlatform {
    my $self = shift;
    return $self->{_ByPlatform};
}

#===  CLASS METHOD  ============================================================

#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  getter method for _ByStudy
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_ByStudy {
    my $self = shift;
    return $self->{_ByStudy};
}

#===  CLASS METHOD  ============================================================

#   PARAMETERS:  stid
#      RETURNS:  p*
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getPlatformFromStudy {
    my ( $self, $stid ) = @_;
    my $stid_info = defined($stid) ? $self->{_ByStudy}->{$stid} : undef;
    return defined($stid_info) ? $stid_info->{pid} : undef;
}

#===  CLASS METHOD  ============================================================

#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getPlatformNameFromPID {
    my ( $self, $pid ) = @_;
    return $self->{_ByPlatform}->{$pid}->{pname};
}

#===  CLASS METHOD  ============================================================

#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getPlatformStudyName {
    my ( $self, $pid, $stid ) = @_;

    my $platform      = $self->{_ByPlatform}->{$pid};
    my $platform_name = $platform->{pname};
    my $study_name    = $platform->{studies}->{$stid}->{description};
    return "$study_name \\ $platform_name";
}

#===  CLASS METHOD  ============================================================

#   PARAMETERS:
#       p*s          => T/F - whether to add p* info such as
#                                   * and p* name
#       studies            => T/F - whether to add study info such as study description
#       experiments        => T/F - whether to add experiment info
#                                   (names of sample 1 and sample 2)
#       empty_study        => str/F - name of an empty study (If true, a special study
#                                   under given name will always show up in
#                                   the list. If false, "@Unassigned" study
#                                   will show up only in special cases.
#       empty_p*     => str/F - if true, a special p* will show
#                                   up in the list.
#       p*_by_study  => T/F - whether to store info about
#                                   which p* a study belongs to on a
#                                   per-study basis (_ByStudy hash).
#      RETURNS:  HASHREF of merged data structure
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my ( $self, %args ) = @_;

    #---------------------------------------------------------------------------
    #  process argument hash
    #---------------------------------------------------------------------------
    # defaulting to "no"
    my $platform_info = $args{platforms};

    # defaulting to "no"
    my $study_info = $args{studies};

    # defaulting to "no"
    my $experiment_info = $args{experiments};

    # defaulting to "no"
    my $extra_studies = $args{extra_studies};

    # defaulting to "no"
    my $extra_platforms = $args{extra_platforms};

    # defaulting to "no"
    my $platform_by_study = $args{platform_by_study};

    # when p* is set, both p* and studies will be set to "yes"
    if ($platform_by_study) {
        $platform_info = 1;
        $study_info    = 1;
    }

    my $default_study_name =
      ( exists $args{default_study_name} )
      ? $args{default_study_name}
      : '@Unassigned Experiments';

    #---------------------------------------------------------------------------
    #  build model
    #---------------------------------------------------------------------------
    my $all_platforms = ( exists $extra_platforms->{all} ) ? 1 : 0;

    $self->getPlatforms(
        extra         => $extra_platforms,
        extra_studies => $extra_studies
    ) if $platform_info;

    # we didn't define getStudy() because getP*Study() accomplishes the
    # same goal (there is a one-to-many relationship between p* and
    # studies).
    $self->getPlatformStudy(
        reverse_lookup => $platform_by_study,
        extra          => $extra_studies,
        all_platforms  => $all_platforms
    ) if $study_info;

    $self->getExperiments( all_platforms => $all_platforms )
      if $experiment_info;

    if ( $study_info && $experiment_info ) {
        $self->getStudyExperiment();
    }

    #---------------------------------------------------------------------------
    #  Assign experiments from under studies and place them under studies that
    #  are under p*. This code will be executed only when we initialize
    #  the object with the following parameters:
    #
    #  p* => 1, studies => 1, experiments => 1
    #---------------------------------------------------------------------------
    if ( $platform_info && $study_info && $experiment_info ) {
        my $model   = $self->{_ByPlatform};
        my $studies = $self->{_ByStudy};

        # Also determine which experiment ids do not belong to any study. Do
        # this by obtaining a list of all experiments in the p* (keys
        # %{$p*->{experiments}}) and subtracting from it experiments
        # belonging to each study as we iterate over the list of all studies in
        # the p*.
        #
        my $this_empty_study =
          ( defined($extra_studies) && defined( $extra_studies->{''} ) )
          ? $extra_studies->{''}->{description}
          : $default_study_name;

        foreach my $platform ( values %$model ) {

           # populate %unassigned hash initially with all experiments for the p*
            my %unassigned =
              map { $_ => {} } keys %{ $platform->{experiments} };

            # initialize $p*->{studies} (must always be present)
            $platform->{studies} ||= {};

            # cache "studies" field
            my $platformStudies = $platform->{studies};
            foreach my $study ( keys %$platformStudies ) {
                my $studyExperiments =
                  ( $studies->{$study}->{experiments} || {} );
                $platformStudies->{$study}->{experiments} = $studyExperiments;

                # delete assigned experiments from unassigned
                delete @unassigned{ keys %$studyExperiments };
            }

            # if %unassigned hash is not empty, add "Unassigned" study to
            # studies
            if (%unassigned) {
                if ( exists $platformStudies->{''} ) {
                    $platformStudies->{''}->{experiments} = \%unassigned;
                }
                else {
                    $platformStudies->{''} = {
                        experiments => \%unassigned,
                        description => $this_empty_study
                    };
                }
            }
        }
    }
    return 1;
}

#===  FUNCTION  ================================================================
#         NAME:  iterateOverTable
#      PURPOSE:
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub iterateOverTable {
    my $self = shift;
    my $dbh  = $self->{_dbh};

    my %args = @_;

    my $table_info = $args{table_info};
    my $iterator   = $args{iterator};

    my @base = @{ $table_info->{base} };
    my $sql  = sprintf(
        'SELECT %s FROM %s',
        join( ',', ( @base, @{ $table_info->{attr} } ) ),
        $table_info->{table}
    );
    my $sth = $dbh->prepare($sql);
    my $rc  = $sth->execute;

    while ( my $row = $sth->fetchrow_hashref ) {
        my @base_vals = @$row{@base};
        delete @$row{@base};

        $iterator->( \@base_vals, $row );
    }
    $sth->finish;
    return 1;
}

#===  CLASS METHOD  ============================================================

#   PARAMETERS:  extra => {
#                   'all' => { name => '@All P*', * => undef },
#                   ''    => { name => '@Unassigned', * => undef }
#                }
#      RETURNS:  HASHREF to model
#
#  DESCRIPTION:  Builds a nested data structure that describes which studies
#                belong to which p*. The list of studies for each p*
#                contains a null member meant to represent Unassigned studies.
#                The data structure is meant to be encoded as JSON.
#
#                var p*Study = {
#                  '13': {
#                     'name': 'Mouse Agilent 123',
#                     '*': 'Mouse',
#                     'studies': {
#                       '108': { 'name': 'Study XX' },
#                       '120': { 'name': 'Study YY' },
#                       ''   : { 'name': 'Unassigned' }
#                     }
#                   },
#                  '14': {
#                     'name': 'P* 456',
#                     '*': 'Human',
#                     'studies': {
#                        '12': { 'name': 'Study abc' },
#                        ''  : { 'name': 'Unassigned' }
#                     }
#                   }
#                };
#
#       THROWS:  Exception::Class::DBI
#
#     COMMENTS:  This method builds a model and should be moved to an
#                appropriate model-only class together with the associated
#                queries and data.
#
#                Alternatively, we could return a simpler structure (one level
#                of nesting instead of two) and then remap it in Javascript.
#
#     SEE ALSO:  SGX::CompareExperiments, SGX::ManageExperiments,
#                SGX::OutputData, and SGX::AddExperiment all rely on a similar
#                data structure. Except for SGX::AddExperiment, all of these
#                modules also need a data structure representing the
#                relationships between studies and experiments and a list of
#                experiments, which can be composited in afterwards.
#===============================================================================
sub getPlatforms {
    my ( $self, %args ) = @_;

    my $model = dclone( $args{extra} || {} );
    my $extra_studies = $args{extra_studies} || {};

    $self->iterateOverTable(
        table_info => $self->{_Platform},
        iterator   => sub {
            my ( $base_vals, $row ) = @_;
            my ($pid) = @$base_vals;
            $row->{studies} = dclone($extra_studies);
            $model->{$pid} = $row;
        }
    );

    # Merge in the hash we just built. If $self->{_ByP*} is undefined,
    # this simply sets it to \%model
    $self->{_ByPlatform} = merge( $model, $self->{_ByPlatform} );
    return 1;
}

#===  CLASS METHOD  ============================================================

#   PARAMETERS:  extra => {
#                    '' => { name => '@Unassigned' }
#                }
#                               whose id is a zero-length string.
#                reverse_lookup => true/false  - whether to store info about
#                               which p* a study belongs to on a per-study
#                               basis (_ByStudy hash).
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  Exception::Class::DBI
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getPlatformStudy {
    my ( $self, %args ) = @_;

    my %model =
      $args{all_platforms}
      ? ( all => { studies => dclone( $args{extra} || {} ) } )
      : ();
    my %reverse_model;
    my $reverse_lookup = $args{reverse_lookup};

    $self->iterateOverTable(
        table_info => $self->{_PlatformStudy},
        iterator   => sub {
            my ( $base_vals, $row )  = @_;
            my ( $pid,       $stid ) = @$base_vals;

            $pid = '' if not defined $pid;
            $model{$pid}->{studies}->{$stid} = $row;

            # if there is an 'all' p*, add every study to it
            if ( exists $model{all} ) {
                $model{all}->{studies}->{$stid} = dclone($row);
            }
            if ($reverse_lookup) {
                $reverse_model{$stid}->{pid} = $pid;
            }
        }
    );

    # Merge in the hash we just built. If $self->{_ByP*} is undefined,
    # this simply sets it to \%model
    $self->{_ByPlatform} = merge( \%model, $self->{_ByPlatform} );
    if ($reverse_lookup) {
        $self->{_ByStudy} = merge( \%reverse_model, $self->{_ByStudy} );
    }
    return 1;
}

#===  CLASS METHOD  ============================================================

#   PARAMETERS:  ????
#      RETURNS:  HASHREF to model
#  DESCRIPTION:
#

#       THROWS:  Exception::Class::DBI
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getExperiments {
    my ( $self, %args ) = @_;

    my %model = $args{all_platforms} ? ( all => { experiments => {} } ) : ();

    $self->iterateOverTable(
        table_info => $self->{_Experiment},
        iterator   => sub {
            my ( $base_vals, $row ) = @_;
            my ( $pid,       $eid ) = @$base_vals;
            my $this_pid = defined($pid) ? $pid : '';
            $model{$this_pid}->{experiments}->{$eid} = $row;

            # if there is an 'all' p*, add every experiment to it
            if ( exists $model{all} ) {
                $model{all}->{experiments}->{$eid} = dclone($row);
            }
        }
    );

    # Merge in the hash we just built. If $self->{_ByP*} is undefined,
    # this simply sets it to \%model
    $self->{_ByPlatform} = merge( \%model, $self->{_ByPlatform} );
    return 1;
}

#===  CLASS METHOD  ============================================================

#   PARAMETERS:  ????
#      RETURNS:  HASHREF to model
#  DESCRIPTION:  create a structure describing which study has which experiments
#
#                /* var StudyExperiment -- note that this structure is missing
#                 * experiments not assigned to studies */
#                var StudyExperiment = {
#                    '108': { 'experiments' : { '1120':null, '2311':null }},
#                    '120': { 'experiments' : { '1120':null }}
#                };
#
#       THROWS:  Exception::Class::DBI
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getStudyExperiment {
    my $self = shift;

    my %model;
    $self->iterateOverTable(
        table_info => $self->{_StudyExperiment},
        iterator   => sub {
            my ( $base_vals, $row ) = @_;
            my ( $stid,      $eid ) = @$base_vals;
            $model{$stid}->{experiments}->{$eid} = $row;
        }
    );

    # Merge in the hash we just built. If $self->{_ByStudy} is undefined,
    # this simply sets it to \%model
    $self->{_ByStudy} = merge( \%model, $self->{_ByStudy} );
    return \%model;
}

1;

__END__

#
#===============================================================================
#
#         FILE:  P*StudyExperiment.pm
#
#  DESCRIPTION:  This is a model class for setting up the data in the p*,
#                study, and experiment tables in easy-to-use Perl data
#                structures.
#
#                /* Result of composition of var StudyExperiment and
#                * var P*Experiment */
#
#                var p*StudyExperiment = {
#
#                   /*** P*s enumerated by their ids ***/
#                   '13': {
#
#                       /* Study section. Only experiment ids are listed for
#                        * each study. Note that the 'experiments' field of each
#                        * study has the same structure as the p*-wide
#                        * 'experiments' field. This allows us to write code
#                        * that is ignorant of where the experiment object came
#                        * from. */
#                       'studies': {
#                           '':    { 'experiments': { '2315':null } },
#                           '108': { 'experiments': { '1120':null, '2311':null } },
#                           '120': { 'experiments': { '1120':null } }
#                       },
#
#                       /* Experiment info is separated from study info in its
#                        * own section for compactness because one experiment
#                        * can belong to several studies
#                        */
#                       'experiments': {
#                           '2311': [
#                              'Male Tasmanian Devil wild type',
#                              'Female Tasmanian Devil knockout'
#                           ],
#                           '1120': [
#                              'Female Three-Toed Sloth Type A',
#                              'Male Three-Toed Sloth Type B'
#                           ],
#                           '2315': [
#                               'Male Anteater wild type',
#                               'Male Anteater knockout'
#                           ]
#                       }
#                   },
#                   '14': {
#                       'studies': {
#                           '':    { 'experiments': { '1297':null } }
#                       }
#                       'experiments': {
#                           '1297': [
#                               'Male Aardvark Knockout',
#                               'Male Aardvark Wild Type'
#                           ]
#                       }
#                   }
#                };
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Eugene Scherba (es), escherba@gmail.com
#      COMPANY:  Boston University
#      VERSION:  1.0
#      CREATED:  07/11/2011 03:32:43
#     REVISION:  ---
#===============================================================================


