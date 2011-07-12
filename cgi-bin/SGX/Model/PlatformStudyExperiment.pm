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
use List::Util qw/reduce/;

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::PlatformStudyExperiment
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
        _ByPlatform => {
            platform           => undef,
            platformStudy      => undef,
            platformExperiment => undef
        },
        _ByStudy => undef
    };

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::PlatformStudyExperiment
#       METHOD:  overlayByPlatform
#   PARAMETERS:  none
#      RETURNS:  HASHREF to merged data
#  DESCRIPTION:  Merges (or overlays) all data in $self->{_ByPlatform}
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub overlayByPlatform {
    my ($self) = @_;

    my $model = 
      reduce { merge( $a, $b ) }
      grep { defined }
      values %{ $self->{_ByPlatform} };

    # For testing:
      #@{ $self->{_ByPlatform} }{qw{platform platformStudy platformExperiment}};
      #@{ $self->{_ByPlatform} }{qw{platformStudy platform platformExperiment}};
      #@{ $self->{_ByPlatform} }{qw{platformStudy platformExperiment platform}};
      #@{ $self->{_ByPlatform} }{qw{platform platformExperiment platformStudy}};
      #@{ $self->{_ByPlatform} }{qw{platformExperiment platformStudy platform}};
      #@{ $self->{_ByPlatform} }{qw{platformExperiment platform platformStudy}};

    return $model;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::PlatformStudyExperiment
#       METHOD:  getByPlatformStudyExperiment
#   PARAMETERS:  
#       platform_info => [1|0]     - whether to add platform info such as
#                                    species and platform name
#       experiment_info => [1|0]   - whether to add experiment info
#                                    (names of sample 1 and sample 2)
#       require_unassigned =>[1|0] - whether to always list
#                                    "Unassigned Experiments" among studies,
#                                    even when no such experiments exist.
#      RETURNS:  HASHREF of merged data structure
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getByPlatformStudyExperiment {
    my ( $self, %param ) = @_;

    # require_unassigned parameter
    my $require_unassigned = $param{require_unassigned};

    # platform_info parameter
    if ($param{platform_info}) {
        $self->getPlatformInfo();
    }
    # experiment_info parameter
    if ($param{experiment_info}) {
        $self->getExperiments();
    }

    $self->getPlatformStudy()
      if not defined $self->{_ByPlatform}->{platformStudy};

    my $model = $self->overlayByPlatform();

    $self->getStudyExperiment()
      if not defined $self->{_ByStudy};
    my $studies = $self->{_ByStudy};

    # Also determine which experiment ids do not belong to any study. Do this by
    # obtaining a list of all experiments in the platform (keys
    # %{$platform->{experiments}}) and subtracting from it experiments belonging
    # to each study as we iterate over the list of all studies in the platform.
    #
    foreach my $platform ( values %$model ) {
        # populate %unassigned hash initially with all experiments for the
        # platform
        my %unassigned = map { $_ => undef } keys %{$platform->{experiments}};

        my $platformStudies = $platform->{studies};
        foreach my $study ( keys %$platformStudies ) {
            my $studyExperiments = $studies->{$study};
            $platformStudies->{$study}->{experiments} = $studyExperiments;

            # delete assigned experiments from unassigned
            delete @unassigned{ keys %$studyExperiments };
        }

        # if %unassigned hash is not empty, add "Unassigned" study to studies
        if ($require_unassigned or %unassigned) {
            $platformStudies->{''} = {
                experiments => \%unassigned,
                name => '@Unassigned'
            };
        }
    }

    return $model;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::PlatformStudyExperiment
#       METHOD:  getPlatformInfo
#   PARAMETERS:  ????
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
sub getPlatformInfo {
    my $self = shift;

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
    my %model;

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

    $self->{_ByPlatform}->{platform} = \%model;
    return \%model;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::PlatformStudyExperiment
#       METHOD:  getPlatformStudy
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  Exception::Class::DBI
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getPlatformStudy {
    my ( $self, %param ) = @_;

    my $unassigned_name = $param{unassigned};
    my %unassigned =
        ( defined $unassigned_name )
      ? ( '' => { name => $unassigned_name } )
      : ();

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

    # complete the model using study info
    while ( $sth_study->fetch ) {
        if ( exists $model{$pid} ) {
            $model{$pid}->{studies}->{$stid}->{name} = $study_desc;
        }
        else {
            $model{$pid} =
              { studies => { %unassigned, $stid => { name => $study_desc } } };
        }
    }
    $sth_study->finish;

    $self->{_ByPlatform}->{platformStudy} = \%model;
    return \%model;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::PlatformStudyExperiment
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

    $self->{_ByPlatform}->{platformExperiment} = \%model;
    return \%model;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::PlatformStudyExperiment
#       METHOD:  getStudyExperiment
#   PARAMETERS:  ????
#      RETURNS:  HASHREF to model
#  DESCRIPTION:  create a structure describing which study has which experiments
#
#                /* var StudyExperiment -- note that this structure is missing
#                 * experiments not assigned to studies */
#                var StudyExperiment = {
#                    '108': { '1120':null, '2311':null },
#                    '120': { '1120':null }
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
            $model{$se_stid}->{$se_eid} = undef;
        }
        else {
            $model{$se_stid} = { $se_eid => undef };
        }
    }

    $self->{_ByStudy} = \%model;
    return \%model;
}

1;
