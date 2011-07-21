#
#===============================================================================
#
#         FILE:  PlatformStudyExperiment.pm
#
#  DESCRIPTION:  This is a model class for setting up the data in the platform,
#                study, and experiment tables in easy-to-use Perl data
#                structures.
#
#                /* Result of composition of var StudyExperiment and
#                * var PlatformExperiment */
#
#                var platformStudyExperiment = {
#
#                   /*** Platforms enumerated by their ids ***/
#                   '13': {
#
#                       /* Study section. Only experiment ids are listed for
#                        * each study. Note that the 'experiments' field of each
#                        * study has the same structure as the platform-wide
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

package SGX::Model::PlatformStudyExperiment;

use strict;
use warnings;

#use SGX::Debug qw/assert/;
use Data::Dumper;
use Hash::Merge qw/merge/;
use SGX::Exceptions;

#===  CLASS METHOD  ============================================================
#        CLASS:  PlatformStudyExperiment
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

    my ($dbh) = @param{qw{dbh}};

    my $self = {
        _dbh        => $dbh,
        _ByPlatform => {},
        _ByStudy    => {}
    };

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  PlatformStudyExperiment
#       METHOD:  get_ByPlatform
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  getter method for _ByPlatform
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_ByPlatform {
    my $self = shift;
    return $self->{_ByPlatform};
}

#===  CLASS METHOD  ============================================================
#        CLASS:  PlatformStudyExperiment
#       METHOD:  get_ByStudy
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
#        CLASS:  PlatformStudyExperiment
#       METHOD:  getPlatformFromStudy
#   PARAMETERS:  stid
#      RETURNS:  pid
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getPlatformFromStudy {
    my ( $self, $stid ) = @_;
    return $self->{_ByStudy}->{$stid}->{pid};
}


#===  CLASS METHOD  ============================================================
#        CLASS:  PlatformStudyExperiment
#       METHOD:  getPlatformNameFromPID
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getPlatformNameFromPID {
    my ( $self, $pid ) = @_;
    return $self->{_ByPlatform}->{$pid}->{name};
}

#===  CLASS METHOD  ============================================================
#        CLASS:  PlatformStudyExperiment
#       METHOD:  getPlatformStudyName
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getPlatformStudyName {
    my ( $self, $pid, $stid ) = @_;
    return $self->{_ByPlatform}->{$pid}->{studies}->{$stid}->{name} . ' \ '
      . $self->{_ByPlatform}->{$pid}->{name};
}

#===  CLASS METHOD  ============================================================
#        CLASS:  PlatformStudyExperiment
#       METHOD:  init
#   PARAMETERS:
#       platforms          => T/F - whether to add platform info such as
#                                   species and platform name
#       studies            => T/F - whether to add study info such as study description
#       experiments        => T/F - whether to add experiment info
#                                   (names of sample 1 and sample 2)
#       empty_study        => str/F - name of an empty study (If true, a special study
#                                   under given name will always show up in
#                                   the list. If false, "@Unassigned" study
#                                   will show up only in special cases.
#       empty_platform     => str/F - if true, a special platform will show
#                                   up in the list.
#       platform_by_study  => T/F - whether to store info about
#                                   which platform a study belongs to on a
#                                   per-study basis (_ByStudy hash).
#      RETURNS:  HASHREF of merged data structure
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my ( $self, %param ) = @_;

    #---------------------------------------------------------------------------
    #  process argument hash
    #---------------------------------------------------------------------------
    # defaulting to "no"
    my $platform_info = $param{platforms};

    # defaulting to "no"
    my $study_info = $param{studies};

    # defaulting to "no"
    my $experiment_info = $param{experiments};

    # defaulting to "no"
    my $extra_studies = $param{extra_studies};

    # defaulting to "no"
    my $extra_platforms = $param{extra_platforms};

    # defaulting to "no"
    my $platform_by_study = $param{platform_by_study};

    my $default_study_name = (exists $param{default_study_name})
                           ? $param{default_study_name}
                           : '@Unassigned Experiments';

    my $default_platform_name = (exists $param{default_platform_name})
                           ? $param{default_platform_name}
                           : '@Unassigned Experiments';

    #---------------------------------------------------------------------------
    #  build model
    #---------------------------------------------------------------------------
    $self->getPlatforms( extra => $extra_platforms ) if $platform_info;

    # we didn't define getStudy() because getPlatformStudy() accomplishes the
    # same goal (there is a one-to-many relationship between platforms and
    # studies).
    $self->getPlatformStudy(
        reverse_lookup => $platform_by_study,
        extra          => $extra_studies
    ) if $study_info;
    $self->getExperiments() if $experiment_info;

    if ( $study_info && $experiment_info ) {
        $self->getStudyExperiment();
    }

    #---------------------------------------------------------------------------
    #  platforms => 1, studies => 1, experiments => 1
    #---------------------------------------------------------------------------
    if ( $platform_info && $study_info && $experiment_info ) {
        my $model   = $self->{_ByPlatform};
        my $studies = $self->{_ByStudy};

        # Also determine which experiment ids do not belong to any study. Do
        # this by obtaining a list of all experiments in the platform (keys
        # %{$platform->{experiments}}) and subtracting from it experiments
        # belonging to each study as we iterate over the list of all studies in
        # the platform.
        #
        my $this_empty_study =
          ( defined($extra_studies) && defined( $extra_studies->{''} ) )
          ? $extra_studies->{''}->{name}
          : $default_study_name;

        my $this_empty_platform =
          ( defined($extra_platforms) && defined( $extra_platforms->{''} ) )
          ? $extra_platforms->{''}->{name}
          : $default_platform_name;

        foreach my $platform ( values %$model ) {

            # populate %unassigned hash initially with all experiments for the
            # platform
            my %unassigned =
              map { $_ => undef } keys %{ $platform->{experiments} };

            # initialize $platform->{studies} (must always be present)
            $platform->{studies} ||= {};
            $platform->{name}    ||= $this_empty_platform;
            $platform->{species} ||= undef;

            # cache "studies" field
            my $platformStudies = $platform->{studies};
            foreach my $study ( keys %$platformStudies ) {
                my $studyExperiments = $studies->{$study}->{experiments};
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
                        name        => $this_empty_study
                    };
                }
            }
        }
    }

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  PlatformStudyExperiment
#       METHOD:  getPlatforms
#   PARAMETERS:  extra => {
#                   'all' => { name => '@All Platforms', species => undef },
#                   ''    => { name => '@Unassigned', species => undef }
#                }
#      RETURNS:  HASHREF to model
#
#  DESCRIPTION:  Builds a nested data structure that describes which studies
#                belong to which platform. The list of studies for each platform
#                contains a null member meant to represent Unassigned studies.
#                The data structure is meant to be encoded as JSON.
#
#                var platformStudy = {
#                  '13': {
#                     'name': 'Mouse Agilent 123',
#                     'species': 'Mouse',
#                     'studies': {
#                       '108': { 'name': 'Study XX' },
#                       '120': { 'name': 'Study YY' },
#                       ''   : { 'name': 'Unassigned' }
#                     }
#                   },
#                  '14': {
#                     'name': 'Platform 456',
#                     'species': 'Human',
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
    my ( $self, %param ) = @_;

    my $extra_platforms = (defined $param{extra} )
                        ? $param{extra}
                        : {};

    #my $unassigned_name = $param{empty};
    #my %extra_platforms =
    #    ( defined $unassigned_name )
    #  ? ( '' => { name => "\@$unassigned_name", species => undef } )
    #  : ();

    # cache the database handle
    my $dbh = $self->{_dbh};

    # query to get platform info
    my $sth_platform = $dbh->prepare(<<"END_PLATFORMQUERY");
SELECT
    pid,
    pname,
    species
FROM platform
END_PLATFORMQUERY
    my $rc_platform = $sth_platform->execute;

    my ( $pid, $pname, $species );
    $sth_platform->bind_columns( undef, \$pid, \$pname, \$species );

    # what is returned
    my %model = (%$extra_platforms);

    # first setup the model using platform info
    while ( $sth_platform->fetch ) {

        # "Unassigned" study should exist ony
        # (a) on request,
        # (b) if there are actually unassigned studies (determined later)
        $model{$pid} = {
            name    => $pname,
            species => $species
        };
    }

    $sth_platform->finish;

    # Merge in the hash we just built. If $self->{_ByPlatform} is undefined,
    # this simply sets it to \%model
    $self->{_ByPlatform} = merge( \%model, $self->{_ByPlatform} );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  PlatformStudyExperiment
#       METHOD:  getPlatformStudy
#   PARAMETERS:  extra => {
#                    '' => { name => '@Unassigned' }
#                }
#                               whose id is a zero-length string.
#                reverse_lookup => true/false  - whether to store info about
#                               which platform a study belongs to on a per-study
#                               basis (_ByStudy hash).
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  Exception::Class::DBI
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getPlatformStudy {
    my ( $self, %param ) = @_;

    my $extra_studies = (defined $param{extra})
                      ? $param{extra}
                      : {};
    #my $unassigned_name = $param{empty};
    #my %unassigned =
    #    ( defined $unassigned_name )
    #  ? ( '' => { name => "\@$unassigned_name" } )
    #  : ();

    # defaulting to "no"
    my $reverse_lookup = $param{reverse_lookup};

    # cache the database handle
    my $dbh = $self->{_dbh};

    # what is returned
    my %model;

    # query to get study info
    my $sth_study = $dbh->prepare(<<"END_STUDYQUERY");
SELECT
    pid,
    stid,
    description
FROM study
END_STUDYQUERY
    my $rc_study = $sth_study->execute;
    my ( $pid, $stid, $study_desc );
    $sth_study->bind_columns( undef, \$pid, \$stid, \$study_desc );

    my %reverse_model;

    # complete the model using study info
    while ( $sth_study->fetch ) {
        if ( exists $model{$pid} ) {
            $model{$pid}->{studies}->{$stid}->{name} = $study_desc;
        }
        else {
            $model{$pid} =
              { studies => { %$extra_studies, $stid => { name => $study_desc } } };
        }
        if ($reverse_lookup) {
            if ( exists $reverse_model{$stid} ) {
                $reverse_model{$stid}->{pid} = $pid;
            }
            else {
                $reverse_model{$stid} = { pid => $pid };
            }
        }
    }
    $sth_study->finish;

    # Merge in the hash we just built. If $self->{_ByPlatform} is undefined,
    # this simply sets it to \%model
    $self->{_ByPlatform} = merge( \%model, $self->{_ByPlatform} );
    if ($reverse_lookup) {
        $self->{_ByStudy} = merge( \%reverse_model, $self->{_ByStudy} );
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  PlatformStudyExperiment
#       METHOD:  getExperiments
#   PARAMETERS:  ????
#      RETURNS:  HASHREF to model
#  DESCRIPTION:
#

#       THROWS:  Exception::Class::DBI
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getExperiments {
    my $self = shift;

    # cache the database handle
    my $dbh = $self->{_dbh};

    # what is returned
    my %model;

    # query to get platform info (know nothing about studies at this point)
    my $sth_experiment = $dbh->prepare(<<"END_EXPERIMENTQUERY");
SELECT
    pid,
    eid,
    sample1,
    sample2
FROM experiment
END_EXPERIMENTQUERY
    my $rc_experiment = $sth_experiment->execute;
    my ( $pid, $eid, $sample1, $sample2 );
    $sth_experiment->bind_columns( undef, \$pid, \$eid, \$sample1, \$sample2 );
    while ( $sth_experiment->fetch ) {

        # an experiment may not have any pid, in which case we add it to empty
        # platform
        my $this_pid = ( defined($pid) ) ? $pid : '';
        if ( exists $model{$this_pid} ) {
            $model{$this_pid}->{experiments}->{$eid} = [ $sample1, $sample2 ];
        }
        else {
            $model{$this_pid} =
              { experiments => { $eid => [ $sample1, $sample2 ] } };
        }
    }

    $sth_experiment->finish;

    # Merge in the hash we just built. If $self->{_ByPlatform} is undefined,
    # this simply sets it to \%model
    $self->{_ByPlatform} = merge( \%model, $self->{_ByPlatform} );
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  PlatformStudyExperiment
#       METHOD:  getStudyExperiment
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

    # cache the database handle
    my $dbh = $self->{_dbh};

    # what is returned
    my %model;
    my $sth_StudyExperiment = $dbh->prepare(<<"END_STUDYEXPERIMENTQUERY");
SELECT
   stid,
   eid 
FROM StudyExperiment
END_STUDYEXPERIMENTQUERY
    my $rc_StudyExperiment = $sth_StudyExperiment->execute;
    my ( $se_stid, $se_eid );
    $sth_StudyExperiment->bind_columns( undef, \$se_stid, \$se_eid );
    while ( $sth_StudyExperiment->fetch ) {

        if ( exists $model{$se_stid} ) {
            $model{$se_stid}->{experiments}->{$se_eid} = undef;
        }
        else {
            $model{$se_stid} = { experiments => { $se_eid => undef } };
        }
    }

    # Merge in the hash we just built. If $self->{_ByStudy} is undefined,
    # this simply sets it to \%model
    $self->{_ByStudy} = merge( \%model, $self->{_ByStudy} );
    return \%model;
}

1;