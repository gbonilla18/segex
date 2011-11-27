package SGX::ManageExperiments;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use SGX::Debug;
use Scalar::Util qw/looks_like_number/;
use SGX::Abstract::Exception ();
require SGX::Model::PlatformStudyExperiment;

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Override parent constructor; add attributes to object instance
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    my ( $q, $s ) = @$self{qw/_cgi _UserSession/};
    my $curr_proj = $s->{session_cookie}->{curr_proj};

    my ( $pid, $stid ) = $self->get_id_data();

    $self->set_attributes(

# _table_defs: hash with keys corresponding to the names of tables handled by this module.
#
# key:        Fields that uniquely identify rows
# names:      Fields which identify rows in user-readable manner (row name will be
#             formed by concatenating values with a slash)
# fields:      Fields that are filled out on insert/creation of new records.
# view:       Fields to display.
# selectors:  Fields which, when present in CGI::param list, can narrow down
#             output. Format: { URI => SQL }.
# meta:       Additional field info.
        _table_defs => {
            'StudyExperiment' => {
                key       => [qw/eid stid/],
                base      => [qw/eid stid/],
                join_type => 'INNER'
            },
            'study' => {
                key      => [qw/stid/],
                base     => [qw/description pubmed/],
                view     => [qw/description pubmed/],
                resource => 'studies',

                # table key to the left, URI param to the right
                names => [qw/description/],
                meta  => {
                    stid => { label => 'No.', parser => 'number' },
                    description =>
                      { label => 'Description', __readonly__ => 1 },
                    pubmed => { label => 'PubMed', __readonly__ => 1 }
                },
                join => [
                    StudyExperiment => [
                        stid => 'stid',
                        { constraint => [ eid => sub { shift->{_id} } ] }
                    ]
                ]
            },
            'platform' => {
                key   => [qw/pid/],
                view  => [qw/pname species/],
                names => [qw/pname/],
                meta  => {
                    pname   => { label => 'Platform' },
                    species => { label => 'Species' }
                }
            },
            'experiment' => {
                key  => [qw/eid/],
                view => [
                    qw/eid sample1 sample2 ExperimentDescription AdditionalInformation study_desc/
                ],
                resource => 'experiments',
                base     => [
                    qw/sample1 sample2 ExperimentDescription
                      AdditionalInformation pid stid file/
                ],

                # table key to the left, URI param to the right
                selectors => { pid => 'pid' },
                names     => [qw/sample1 sample2/],
                meta      => {
                    file => {
                        __type__       => 'filefield',
                        __special__    => 1,
                        __createonly__ => 1,
                        __readonly__   => 1,
                        label          => 'Upload Data File'
                    },
                    eid => {
                        label        => 'No.',
                        parser       => 'number',
                        __readonly__ => 1
                    },
                    sample1 => {
                        label      => 'Sample 1',
                        -maxlength => 255,
                        -size      => 35
                    },
                    sample2 => {
                        label      => 'Sample 2',
                        -maxlength => 255,
                        -size      => 35
                    },
                    ExperimentDescription => {
                        label        => 'Description',
                        -maxlength   => 255,
                        -size        => 55,
                        __optional__ => 1,
                    },
                    AdditionalInformation => {
                        label        => 'Additional Info',
                        -maxlength   => 255,
                        -size        => 55,
                        __optional__ => 1
                    },
                    pid => {
                        label    => 'Platform',
                        parser   => 'number',
                        __type__ => 'popup_menu',

                        #__tie__  => [
                        #    (
                        #        looks_like_number( $pid )
                        #        ? ()
                        #        : ( platform => 'pid' )
                        #    )
                        #],
                        __readonly__ => 1,
                        __hidden__   => 1
                    },
                    stid => {
                        label          => 'Study',
                        parser         => 'number',
                        __type__       => 'popup_menu',
                        -multiple      => 'multiple',
                        -size          => 7,
                        __special__    => 1,
                        __optional__   => 1,
                        __createonly__ => 1
                    },
                    study_desc => {
                        __sql__      => 'study.description',
                        __readonly__ => 1,
                        label        => 'Study(-ies)'
                    }
                },
                lookup => [
                    (

                        # No need to display platform column if specific
                        # platform is requested.
                        (
                            looks_like_number($pid)
                              && !$self->get_dispatch_action() eq 'form_create'
                        ) ? ()
                        : ( 'platform' => [ 'pid' => 'pid' ] )
                    )
                ],
                join => [
                    StudyExperiment => [
                        eid => 'eid',
                        { selectors => { stid => 'stid' } }
                    ],
                    'study' => [
                        'StudyExperiment.stid' => 'stid',
                        { join_type => 'LEFT' }
                    ],
                    (
                        (
                                 defined($curr_proj)
                              && $curr_proj ne ''
                              && ( !defined($stid)
                                || $stid ne '' )
                        )
                        ? (
                            ProjectStudy => [
                                'StudyExperiment.stid' => 'stid',
                                {
                                    join_type  => 'INNER',
                                    constraint => [ prid => $curr_proj ]
                                }
                            ]
                          )
                        : ()
                    ),
                    data_count => [ eid => 'eid', { join_type => 'LEFT' } ],
                ],
            },
            data_count => {
                table => 'microarray',
                key   => [qw/eid rid/],
                view  => [qw/probe_count/],
                meta  => {
                    probe_count => {
                        __sql__ => 'COUNT(data_count.rid)',
                        label   => 'Probe Count',
                        parser  => 'number'
                    },
                },
                group_by => [qw/eid/]
            }
        },
        _default_table  => 'experiment',
        _readrow_tables => [
            'study' => {
                remove_row => { verb => 'unassign', table => 'StudyExperiment' }
            }
        ],

        _PlatformStudyExperiment =>
          SGX::Model::PlatformStudyExperiment->new( dbh => $self->{_dbh} ),
    );

    $self->{_id_data}->{pid}  = $pid;
    $self->{_id_data}->{stid} = $stid;

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Initialize parts that deal with responding to CGI queries
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my $self = shift;
    $self->SUPER::init();

    $self->register_actions(
        form_assign => {
            head => 'form_assign_head',
            body => 'form_assign_body'
        }
    );
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  get_id_data
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub get_id_data {
    my $self    = shift;
    my $q       = $self->{_cgi};
    my $id_data = $self->{_id_data} || {};

    my ( $pid, $stid ) = @$id_data{qw/pid stid/};
    $pid  = $q->param('pid')  if not defined $pid;
    $stid = $q->param('stid') if not defined $stid;

    if ( defined $stid ) {
        my $pse = $self->{_PlatformStudyExperiment};
        if ( not defined $pse ) {
            $pse =
              SGX::Model::PlatformStudyExperiment->new( dbh => $self->{_dbh} );
            $pse->init( platform_by_study => 1 );
        }
        my $pid_from_stid = $pse->getPlatformFromStudy($stid);
        $pid = $pid_from_stid if not defined $pid;
        if (    looks_like_number($pid_from_stid)
            and looks_like_number($pid)
            and $pid_from_stid != $pid )
        {
            $stid = undef;
        }
    }

    return ( $pid, $stid );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  form_create_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides SGX::CRUD::form_create_head
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_create_head {
    my $self = shift;
    my ( $js, $js_buffer ) = @$self{qw/_js_emitter _js_buffer/};

    my $code = $self->get_pse_dropdown_js(

        # default: show all studies or studies for a specific platform
        platforms         => undef,
        platform_by_study => 1,
        studies           => 1
    );
    $self->SUPER::form_create_head();

    # add platform dropdown
    push @{ $self->{_js_src_code} }, { -src => 'PlatformStudyExperiment.js' };

    push @$js_buffer, <<"END_SETUPTOGGLES";
setupToggles(
    { 'pid': { 'defined' : ['stid_dt', 'stid_dd'] } }, 
    function(el) { return ((getSelectedValue(el) !== '') ? 'defined' : ''); }
);
$code
END_SETUPTOGGLES

    my ($q, $id_data) = @$self{qw/_cgi _id_data/};
    if ( $self->{_upload_completed} ) {
        $self->add_message(
            'The uploaded data were placed in a new experiment under: '
              . $q->a(
                {
                    -href => $q->url( -absolute => 1 )
                      . sprintf(
                        '?a=experiments&b=Load&pid=%s&stid=%s',
                        $id_data->{pid}, $id_data->{stid}
                      )
                },
                $self->{_PlatformStudyExperiment}
                  ->getPlatformStudyName( $id_data->{pid}, $id_data->{stid} )
              )
        );
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  default_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD default_head
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_head {
    my $self = shift;

    # view all rows
    $self->SUPER::default_head();

    my $s         = $self->{_UserSession};
    my $curr_proj = $s->{session_cookie}->{curr_proj};
    my $stid      = $self->{_id_data}->{stid};

    # add platform dropdown
    push @{ $self->{_js_src_code} }, (
        { -src => 'PlatformStudyExperiment.js' },
        {
            -code => $self->get_pse_dropdown_js(

                # default: show all studies or studies for a specific platform
                platforms         => 1,
                studies           => 1,
                platform_by_study => 1,
                extra_platforms   => { 'all' => { name => '@All Platforms' } },
                extra_studies     => {
                    (
                        ( defined($curr_proj) && $curr_proj ne '' )
                        ? ( 'all' =>
                              { name => '@Assigned Experiments (All Studies)' }
                          )
                        : ( 'all' =>
                              { name => '@All Experiments (All Studies)' } )
                    ),
                    '' => { name => '@Unassigned Experiments' }
                }
            )
        }
    );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  default_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD default_body
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_body {

    # Form HTML for the study table.
    my $self = shift;
    my $q    = $self->{_cgi};

    #---------------------------------------------------------------------------
    #  Platform dropdown
    #---------------------------------------------------------------------------
    my $resource_uri = $self->get_resource_uri();
    return $q->h2( $self->{_title} ),
      $self->body_create_read_menu(
        'read'   => [ undef,         'View Existing' ],
        'create' => [ 'form_create', 'Create New' ]
      ),

      # Resource URI: /studies
      $self->view_start_get_form(),
      $q->dl(
        $q->dt( $q->label( { -for => 'pid' }, 'Platform:' ) ),
        $q->dd(
            $q->popup_menu(
                -name  => 'pid',
                -id    => 'pid',
                -title => 'Choose platform',
            )
        ),
        $q->dt( $q->label( { -for => 'stid' }, 'Study:' ) ),
        $q->dd(
            $q->popup_menu(
                -name  => 'stid',
                -id    => 'stid',
                -title => 'Choose study',
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $self->view_hidden_resource(),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Load',
                -title => 'Get studies for the selected platform'
            )
        )
      ),
      $q->end_form,

    #---------------------------------------------------------------------------
    #  Table showing all studies in all platforms
    #---------------------------------------------------------------------------
      $q->h3( { -id => 'caption' }, '' ),
      $q->div(
        $q->a( { -id => $self->{dom_export_link_id} }, 'View as plain text' ) ),
      $q->div( { -class => 'clearfix', -id => $self->{dom_table_id} }, '' );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  form_assign_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_assign_head {
    my $self = shift;
    return unless defined $self->{_id};    # _id must be present
    $self->_readrow_command()->();

    push @{ $self->{_js_src_code} },
      (
        { -src => 'PlatformStudyExperiment.js' },
        {
            -code => $self->get_pse_dropdown_js(
                platforms              => 1,
                platform_by_experiment => 1,
                studies                => 1
            )
        }
      );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  default_create
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  override CRUD::default_create
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_create {
    my $self    = shift;

    require SGX::UploadData;
    my $data = SGX::UploadData->new( delegate => $self );
    my $recordsLoaded = eval { $data->uploadData('file') } || 0;
    my $exception = $@;
    if ($recordsLoaded) {
        $self->{_upload_completed} = 1;
    } else {
        $self->add_message('No records loaded. ' . $exception);
    }
    $self->set_action('form_create');
    return;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  form_assign_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_assign_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    #---------------------------------------------------------------------------
    #  Form: Assign Studies to this Experiment
    #---------------------------------------------------------------------------

    return $q->h2( 'Editing Experiment: '
          . $self->{_id_data}->{sample2} . ' / '
          . $self->{_id_data}->{sample1} ),

      $self->body_create_read_menu(
        'read'   => [ undef,         'Edit Experiment' ],
        'create' => [ 'form_assign', 'Assign to Studies' ]
      ),
      $q->h3('Assign to Studies'),
      $q->dl(
        $q->dt( $q->label( { -for => 'pid' }, 'From platform:' ) ),
        $q->dd(
            $q->popup_menu(
                -id       => 'pid',
                -disabled => 'disabled'
            )
        ),
      ),

      # Resource URI: /studies/id
      $q->start_form(
        -method => 'POST',
        -action => $self->get_resource_uri()
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'stid' }, 'Study:' ) ),
        $q->dd(
            $q->popup_menu(
                -name => 'stid',
                -id   => 'stid',
                -title =>
qq/You can select multiple studies here by holding down Control or Command key before clicking./,
                -multiple => 'multiple',
                -size     => 7,
                -values   => [],
                -labels   => {}
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->hidden( -name => 'table', -value => 'StudyExperiment' ),
            $q->hidden( -name => 'b',     -value => 'assign' ),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Assign',
                -title => qq/Assign this experiment to selected studies/
            )
        )
      ),
      $q->end_form;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  readrow_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD readrow_body
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub readrow_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    #---------------------------------------------------------------------------
    #  Form: Set Experiment Attributes
    #---------------------------------------------------------------------------
    # :TODO:08/11/2011 16:35:27:es:  here breadcrumbs would be useful

    return $q->h2( 'Editing Experiment: '
          . $self->{_id_data}->{sample2} . ' / '
          . $self->{_id_data}->{sample1} ),

      $self->body_create_read_menu(
        'read'   => [ undef,         'Edit Experiment' ],
        'create' => [ 'form_assign', 'Assign to Study' ]
      ),
      $q->h3('Set Experiment Attributes'),

      $self->body_create_update_form( mode => 'update' ),

    #---------------------------------------------------------------------------
    #  Experiments table
    #---------------------------------------------------------------------------
      $q->h3('Studies this Experiment is Assigned to'),
      $q->div(
        $q->a( { -id => $self->{dom_export_link_id} }, 'View as plain text' ) ),
      $q->div( { -class => 'clearfix', -id => $self->{dom_table_id} } );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  get_pse_dropdown_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:   # :TODO:10/08/2011 11:42:09:es: Isolate this method into an
#     outside class
#     SEE ALSO:  n/a
#===============================================================================
sub get_pse_dropdown_js {
    my ( $self, %args ) = @_;

    my $pse = $self->{_PlatformStudyExperiment};
    $pse->init(
        platforms => 1,
        %args
    );

    # If a study is set, use the corresponding platform while ignoring the
    # platform parameter.
    my ( $pid, $stid ) = $self->get_id_data();
    $self->{_id_data}->{pid}  = $pid;
    $self->{_id_data}->{stid} = $stid;

    my ( $q, $js ) = @$self{qw/_cgi _js_emitter/};

    return $js->let(
        [
            PlatfStudyExp =>
              $self->{_PlatformStudyExperiment}->get_ByPlatform(),
            currentSelection => {
                'platform' => {
                    elementId => 'pid',
                    element   => undef,
                    selected  => ( ( defined $pid ) ? { $pid => undef } : {} )
                },
                (
                    ( $args{studies} )
                    ? (
                        'study' => {
                            elementId => 'stid',
                            element   => undef,
                            selected  => (
                                  ( defined $stid )
                                ? { $stid => undef }
                                : {}
                            )
                        }
                      )
                    : ()
                ),
                (
                    ( $args{experiments} )
                    ? (
                        'experiment' => {
                            elementId => 'eid',
                            element   => undef,
                            selected  => {}
                        }
                      )
                    : ()
                )
            }
        ],
        declare => 1
      )
      . $js->apply(
        'YAHOO.util.Event.addListener',
        [
            sub { 'window' },
            'load',
            $js->lambda(
                [],
                (
                    ( $args{platforms} )
                    ? $js->apply(
                        'populatePlatform.apply',
                        [ sub { 'currentSelection' } ],
                      )
                    : ()
                ),
                (
                    ( $args{studies} )
                    ? (
                        $js->apply(
                            'populatePlatformStudy.apply',
                            [ sub { 'currentSelection' } ],
                        )
                      )
                    : ()
                ),
                (
                    ( $args{studies} && $args{experiments} )
                    ? (
                        $js->apply(
                            'populateStudyExperiment.apply',
                            [ sub { 'currentSelection' } ],
                        )
                      )
                    : ()
                )
            )
        ],
      )
      . (
        ( $args{studies} || $args{experiments} )
        ? (
            $js->apply(
                'YAHOO.util.Event.addListener',
                [
                    'pid', 'change',
                    $js->lambda(
                        [],
                        (
                            ( $args{studies} )
                            ? (
                                $js->apply(
                                    'populatePlatformStudy.apply',
                                    [ sub { 'currentSelection' } ],
                                )
                              )
                            : ()
                        ),
                        (
                            ( $args{studies} && $args{experiments} )
                            ? (
                                $js->apply(
                                    'populateStudyExperiment.apply',
                                    [ sub { 'currentSelection' } ],
                                )
                              )
                            : ()
                        )
                    )
                ],
            )
          )
        : ''
      )
      . (
        ( $args{studies} && $args{experiments} )
        ? (
            $js->apply(
                'YAHOO.util.Event.addListener',
                [
                    'stid', 'change',
                    $js->lambda(
                        [],
                        $js->apply(
                            'populateStudyExperiment.apply',
                            [ sub { 'currentSelection' } ],
                        )
                    )
                ],
            )
          )
        : ''
      );
}

1;

__END__

=head1 NAME

SGX::ManageStudies

=head1 SYNOPSIS

=head1 DESCRIPTION
Grouping of functions for managing studies.

=head1 AUTHORS
Michael McDuffie
Eugene Scherba

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut


