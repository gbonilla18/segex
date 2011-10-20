package SGX::Model::ProjectStudyExperiment;

use strict;
use warnings;

#use SGX::Debug qw/assert/;
use Data::Dumper;
use Hash::Merge qw/merge/;
use SGX::Abstract::Exception;

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
        _ByProject => {},
        _ByStudy    => {}
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
sub get_ByProject {
    my $self = shift;
    return $self->{_ByProject};
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
#      RETURNS:  prid
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getProjectFromStudy {
    my ( $self, $stid ) = @_;
    return $self->{_ByStudy}->{$stid}->{prid};
}

#===  CLASS METHOD  ============================================================


#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getProjectNameFromPID {
    my ( $self, $prid ) = @_;
    return $self->{_ByProject}->{$prid}->{name};
}

#===  CLASS METHOD  ============================================================


#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getProjectStudyName {
    my ( $self, $prid, $stid ) = @_;
    return $self->{_ByProject}->{$prid}->{studies}->{$stid}->{name} . ' \ '
      . $self->{_ByProject}->{$prid}->{name};
}

#===  CLASS METHOD  ============================================================


#   PARAMETERS:
#       projects          => T/F - whether to add project info such as
#                                   prdesc and project name
#       studies            => T/F - whether to add study info such as study description
#       experiments        => T/F - whether to add experiment info
#                                   (names of sample 1 and sample 2)
#       empty_study        => str/F - name of an empty study (If true, a special study
#                                   under given name will always show up in
#                                   the list. If false, "@Unassigned" study
#                                   will show up only in special cases.
#       empty_project     => str/F - if true, a special project will show
#                                   up in the list.
#       project_by_study  => T/F - whether to store info about
#                                   which project a study belongs to on a
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
    my $project_info = $args{projects};

    # defaulting to "no"
    my $study_info = $args{studies};

    # defaulting to "no"
    my $experiment_info = $args{experiments};

    # defaulting to "no"
    my $extra_studies = $args{extra_studies};

    # defaulting to "no"
    my $extra_projects = $args{extra_projects};

    # defaulting to "no"
    my $project_by_study = $args{project_by_study};

    # when project_by_study is set, both projects and studies will be set to
    # one
    if ($project_by_study) {
        $project_info = 1;
        $study_info    = 1;
    }

    my $default_study_name =
      ( exists $args{default_study_name} )
      ? $args{default_study_name}
      : '@Unassigned Experiments';

    my $default_project_name =
      ( exists $args{default_project_name} )
      ? $args{default_project_name}
      : '@Unassigned Experiments';

    #---------------------------------------------------------------------------
    #  build model
    #---------------------------------------------------------------------------
    my $all_projects = ( exists $extra_projects->{all} ) ? 1 : 0;

    #my $all_studies   = ( exists $extra_studies->{all} )   ? 1 : 0;

    $self->getProjects( extra => $extra_projects ) if $project_info;

    # we didn't define getStudy() because getProjectStudy() accomplishes the
    # same goal (there is a one-to-many relationship between projects and
    # studies).
    $self->getProjectStudy(
        reverse_lookup => $project_by_study,
        extra          => $extra_studies,
        all_projects  => $all_projects
    ) if $study_info;

    $self->getExperiments( all_projects => $all_projects )
      if $experiment_info;

    if ( $study_info && $experiment_info ) {
        $self->getStudyExperiment();
    }

    #---------------------------------------------------------------------------
    #  Assign experiments from under studies and place them under studies that
    #  are under projects. This code will be executed only when we initialize
    #  the object with the following parameters:
    #
    #  projects => 1, studies => 1, experiments => 1
    #---------------------------------------------------------------------------
    if ( $project_info && $study_info && $experiment_info ) {
        my $model   = $self->{_ByProject};
        my $studies = $self->{_ByStudy};

        # Also determine which experiment ids do not belong to any study. Do
        # this by obtaining a list of all experiments in the project (keys
        # %{$project->{experiments}}) and subtracting from it experiments
        # belonging to each study as we iterate over the list of all studies in
        # the project.
        #
        my $this_empty_study =
          ( defined($extra_studies) && defined( $extra_studies->{''} ) )
          ? $extra_studies->{''}->{name}
          : $default_study_name;

        my $this_empty_project =
          ( defined($extra_projects) && defined( $extra_projects->{''} ) )
          ? $extra_projects->{''}->{name}
          : $default_project_name;

        foreach my $project ( values %$model ) {

            # populate %unassigned hash initially with all experiments for the
            # project
            my %unassigned =
              map { $_ => {} } keys %{ $project->{experiments} };

            # initialize $project->{studies} (must always be present)
            $project->{studies} ||= {};
            $project->{name}    ||= $this_empty_project;
            $project->{prdesc} ||= undef;

            # cache "studies" field
            my $projectStudies = $project->{studies};
            foreach my $study ( keys %$projectStudies ) {
                my $studyExperiments =
                  ( $studies->{$study}->{experiments} || {} );
                $projectStudies->{$study}->{experiments} = $studyExperiments;

                # delete assigned experiments from unassigned
                delete @unassigned{ keys %$studyExperiments };
            }

            # if %unassigned hash is not empty, add "Unassigned" study to
            # studies
            if (%unassigned) {
                if ( exists $projectStudies->{''} ) {
                    $projectStudies->{''}->{experiments} = \%unassigned;
                }
                else {
                    $projectStudies->{''} = {
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


#   PARAMETERS:  extra => {
#                   'all' => { name => '@All Projects', prdesc => undef },
#                   ''    => { name => '@Unassigned', prdesc => undef }
#                }
#      RETURNS:  HASHREF to model
#
#  DESCRIPTION:  Builds a nested data structure that describes which studies
#                belong to which project. The list of studies for each project
#                contains a null member meant to represent Unassigned studies.
#                The data structure is meant to be encoded as JSON.
#
#                var projectStudy = {
#                  '13': {
#                     'name': 'Mouse Agilent 123',
#                     'prdesc': 'Mouse',
#                     'studies': {
#                       '108': { 'name': 'Study XX' },
#                       '120': { 'name': 'Study YY' },
#                       ''   : { 'name': 'Unassigned' }
#                     }
#                   },
#                  '14': {
#                     'name': 'Project 456',
#                     'prdesc': 'Human',
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
sub getProjects {
    my ( $self, %args ) = @_;

    my $extra_projects =
      ( defined $args{extra} )
      ? $args{extra}
      : {};

    #my $unassigned_name = $args{empty};
    #my %extra_projects =
    #    ( defined $unassigned_name )
    #  ? ( '' => { name => "\@$unassigned_name", prdesc => undef } )
    #  : ();

    # cache the database handle
    my $dbh = $self->{_dbh};

    # query to get project info
    my $sth_project = $dbh->prepare(<<"END_PLATFORMQUERY");
SELECT
    prid,
    prname,
    prdesc
FROM project
END_PLATFORMQUERY
    my $rc_project = $sth_project->execute;

    my ( $prid, $prname, $prdesc );
    $sth_project->bind_columns( undef, \$prid, \$prname, \$prdesc );

    # what is returned
    my %model = (%$extra_projects);

    # first setup the model using project info
    while ( $sth_project->fetch ) {

        # "Unassigned" study should exist only
        # (a) on request,
        # (b) if there are actually unassigned studies (determined later)
        $model{$prid} = {
            name    => $prname,
            prdesc => $prdesc
        };
    }

    $sth_project->finish;

    # Merge in the hash we just built. If $self->{_ByProject} is undefined,
    # this simply sets it to \%model
    $self->{_ByProject} = merge( \%model, $self->{_ByProject} );

    return 1;
}

#===  CLASS METHOD  ============================================================


#   PARAMETERS:  extra => {
#                    '' => { name => '@Unassigned' }
#                }
#                               whose id is a zero-length string.
#                reverse_lookup => true/false  - whether to store info about
#                               which project a study belongs to on a per-study
#                               basis (_ByStudy hash).
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  Exception::Class::DBI
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getProjectStudy {
    my ( $self, %args ) = @_;

    my $extra_studies = $args{extra} || {};

    # default: false
    my $all_projects = $args{all_projects};

    # default: false
    #my $all_studies = $args{all_studies};

    #my $unassigned_name = $args{empty};
    #my %unassigned =
    #    ( defined $unassigned_name )
    #  ? ( '' => { name => "\@$unassigned_name" } )
    #  : ();

    # defaulting to "no"
    my $reverse_lookup = $args{reverse_lookup};

    # cache the database handle
    my $dbh = $self->{_dbh};

    # what is returned
    my %model;

    # query to get study info
    my $sth_study = $dbh->prepare(<<"END_STUDYQUERY");
SELECT
    prid,
    stid,
    description
FROM study
LEFT JOIN ProjectStudy USING(stid)
END_STUDYQUERY
    my $rc_study = $sth_study->execute;
    my ( $prid, $stid, $study_desc );
    $sth_study->bind_columns( undef, \$prid, \$stid, \$study_desc );

    my %reverse_model;

    # complete the model using study info
    while ( $sth_study->fetch ) {
        $prid = '' if not defined $prid;
        if ( exists $model{$prid} ) {
            $model{$prid}->{studies}->{$stid}->{name} = $study_desc;
        }
        else {
            $model{$prid} =
              { studies =>
                  merge( { $stid => { name => $study_desc } }, $extra_studies )
              };
        }

        # if there is an 'all' project, add every study to it
        if ($all_projects) {
            if ( exists $model{all} ) {
                $model{all}->{studies}->{$stid}->{name} = $study_desc;
            }
            else {
                $model{all} = {
                    studies => merge(
                        { $stid => { name => $study_desc } },
                        $extra_studies
                    )
                };
            }
        }
        if ($reverse_lookup) {
            if ( exists $reverse_model{$stid} ) {
                $reverse_model{$stid}->{prid} = $prid;
            }
            else {
                $reverse_model{$stid} = { prid => $prid };
            }
        }
    }
    $sth_study->finish;

    # Merge in the hash we just built. If $self->{_ByProject} is undefined,
    # this simply sets it to \%model
    $self->{_ByProject} = merge( \%model, $self->{_ByProject} );
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

    # default: false
    my $all_projects = $args{all_projects};

    # cache the database handle
    my $dbh = $self->{_dbh};

    # what is returned
    my %model;

    # query to get project info (know nothing about studies at this point)
    my $sth_experiment = $dbh->prepare(<<"END_EXPERIMENTQUERY");
SELECT
    eid,
    sample1,
    sample2
FROM experiment
END_EXPERIMENTQUERY
    my $rc_experiment = $sth_experiment->execute;
    my ( $eid, $sample1, $sample2 );
    $sth_experiment->bind_columns( undef, \$eid, \$sample1, \$sample2 );

    # add experiments to projects
    while ( $sth_experiment->fetch ) {

        # an experiment may not have any pid, in which case we add it to empty
        # project
        if ( exists $model{all} ) {
            $model{all}->{experiments}->{$eid} = {
                sample1 => $sample1,
                sample2 => $sample2
            };
        }
        else {
            $model{all} =
              { experiments =>
                  { $eid => { sample1 => $sample1, sample2 => $sample2 } } };
        }

        # if there is an 'all' project, add every experiment to it
        if ($all_projects) {
            if ( exists $model{all} ) {
                $model{all}->{experiments}->{$eid} = {
                    sample1 => $sample1,
                    sample2 => $sample2
                };
            }
            else {
                $model{all} =
                  { experiments =>
                      { $eid => { sample1 => $sample1, sample2 => $sample2 } }
                  };
            }
        }
    }

    $sth_experiment->finish;

    # Merge in the hash we just built. If $self->{_ByProject} is undefined,
    # this simply sets it to \%model
    $self->{_ByProject} = merge( \%model, $self->{_ByProject} );
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
            $model{$se_stid}->{experiments}->{$se_eid} = {};
        }
        else {
            $model{$se_stid} = { experiments => { $se_eid => {} } };
        }
    }

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
#         FILE:  ProjectStudyExperiment.pm
#
#  DESCRIPTION:  This is a model class for setting up the data in the project,
#                study, and experiment tables in easy-to-use Perl data
#                structures.
#
#                /* Result of composition of var StudyExperiment and
#                * var ProjectExperiment */
#
#                var projectStudyExperiment = {
#
#                   /*** Projects enumerated by their ids ***/
#                   '13': {
#
#                       /* Study section. Only experiment ids are listed for
#                        * each study. Note that the 'experiments' field of each
#                        * study has the same structure as the project-wide
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


