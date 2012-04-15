package SGX::ManageExperiments;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use SGX::Debug;
use Scalar::Util qw/looks_like_number/;
use SGX::Util qw/file_opts_html file_opts_columns/;
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
                    pubmed => {
                        label        => 'PubMed',
                        __readonly__ => 1,
                        formatter    => sub { 'formatPubMed' }
                    }
                },
                join => [
                    StudyExperiment => [
                        stid => 'stid',
                        { constraint => [ eid => sub { shift->{_id} } ] }
                    ]
                ]
            },
            'platform' => {
                resource  => 'platforms',
                item_name => 'platform',
                key       => [qw/pid/],
                view      => [qw/pname/],
                names     => [qw/pname/],
                meta      => { pname => { label => 'Platform' }, },

               #join => [ species => [ sid => 'sid', { join_type => 'LEFT' } ] ]
            },

            #species => {
            #    key   => [qw/sid/],
            #    view  => [qw/sname/],
            #    names => [qw/sname/],
            #    meta  => { sname => { label => 'Species' } }
            #},
            'experiment' => {
                item_name => 'experiment',
                key       => [qw/eid/],
                view      => [
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
                        label          => 'Upload Data File',
                        __type__       => 'filefield',
                        __special__    => 1,
                        __createonly__ => 1,
                        __readonly__   => 1,
                        __extra_html__ => $q->div(
                            file_opts_html( $q, 'fileOpts' ),
                            file_opts_columns(
                                $q,
                                id    => 'datafile',
                                items => [
                                    probe => {
                                        -checked  => 'checked',
                                        -disabled => 'disabled',
                                        -value    => 'Probe ID'
                                    },
                                    ratio => {
                                        -checked => 'checked',
                                        -value   => 'Ratio'
                                    },
                                    fold_change => {
                                        -checked => 'checked',
                                        -value   => 'Fold Change'
                                    },
                                    intensity1 => {
                                        -checked => 'checked',
                                        -value   => 'Intensity-1'
                                    },
                                    intensity2 => {
                                        -checked => 'checked',
                                        -value   => 'Intensity-2'
                                    },
                                    pvalue1 => {
                                        -checked => 'checked',
                                        -value   => 'P-Value 1'
                                    },
                                    pvalue2 => { -value => 'P-Value 2' },
                                    pvalue3 => { -value => 'P-Value 3' },
                                    pvalue4 => { -value => 'P-Value 4' }
                                ]
                            )
                        )
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
                        (
                            looks_like_number($pid)
                            ? ()
                            : ( __tie__ => [ ( platform => 'pid' ) ] )
                        ),

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
                        label   => 'Probes',
                        parser  => 'number'
                    },
                },
                group_by => [qw/eid/]
            }
        },
        _default_table  => 'experiment',
        _readrow_tables => [
            'study' => {
                heading    => 'Studies Experiment is Assigned to',
                actions    => { form_assign => 'assign' },
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

    # add platform dropdown
    push @{ $self->{_css_src_yui} }, 'button/assets/skins/sam/button.css';
    push @{ $self->{_js_src_yui} },  'button/button-min.js';

    # add platform dropdown
    push @{ $self->{_js_src_code} }, { -src => 'collapsible.js' };

    push @{ $self->{_js_buffer} }, <<"END_SETUPTOGGLES";
YAHOO.util.Event.addListener(window,'load',function(){
    setupToggles('change',
        { 'pid': { 'defined' : ['stid_dt', 'stid_dd'] } }, 
        isDefinedSelection
    );
    setupCheckboxes({
        idPrefix: 'datafile',
        minChecked: 1
    });
});
END_SETUPTOGGLES
    push @{ $self->{_js_src_code} }, { -src => 'PlatformStudyExperiment.js' };
    push @{ $self->{_js_src_code} }, {
        -code => $self->get_pse_dropdown_js(

            # default: show all studies or studies for a specific platform
            platforms         => undef,
            platform_by_study => 1,
            studies           => 1,
            extra_studies => { '' => { description => '@Unassigned Experiments' } }
        )
    };

    $self->SUPER::form_create_head();

    my ( $q, $id_data ) = @$self{qw/_cgi _id_data/};
    my $stid = $id_data->{stid} || '';
    if ( $self->{_upload_completed} ) {
        $self->add_message(
            'The uploaded data were placed in a new experiment under: '
              . $q->a(
                {
                    -href => $q->url( -absolute => 1 )
                      . sprintf(
                        '?a=experiments&b=Load&pid=%s&stid=%s',
                        $id_data->{pid}, $stid
                      )
                },
                $self->{_PlatformStudyExperiment}
                  ->getPlatformStudyName( $id_data->{pid}, $stid )
              )
        );
    }
    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  SGX::Strategy::CRUD
#       METHOD:  form_create_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  Overrides Strategy::CRUD::form_create_body
#     SEE ALSO:  n/a
#===============================================================================
sub form_create_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    return

      # container stuff
      $q->h2(
        $self->format_title(
            'manage ' . $self->pluralize_noun( $self->get_item_name() )
        )
      ),
      $self->body_create_read_menu(
        'read'   => [ undef,         'View Existing' ],
        'create' => [ 'form_create', 'Create New' ]
      ),
      $q->h3(
        $self->format_title( 'Upload data to a new ' . $self->get_item_name() )
      ),

      # form
      $self->body_create_update_form(
        mode       => 'create',
        cgi_extras => { -enctype => 'multipart/form-data' }
      );
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
                extra_platforms   => { all => { pname => '@All Platforms' } },
                extra_studies     => {
                    all => {
                        description => (
                            ( defined($curr_proj) && $curr_proj ne '' )
                            ? '@Assigned Experiments (All Studies)'
                            : '@All Experiments (All Studies)'
                        )
                    },
                    '' => { description => '@Unassigned Experiments' }
                }
            )
        },
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
    my $self = shift;
    return if defined $self->{_id};

    require SGX::UploadData;
    my $data = SGX::UploadData->new( delegate => $self );

    eval {
        $self->{_upload_completed} = $data->uploadData( filefield => 'file' );
    } or do {
        my $exception = $@;
        my $msg = ( defined $exception ) ? "$exception" : '';
        $self->add_message( { -class => 'error' }, "No records loaded. $msg" );
    };

    # show body for form_create again
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
            currentSelection => [
                'platform' => {
                    elementId => 'pid',
                    element   => undef,
                    selected  => ( ( defined $pid ) ? { $pid => undef } : {} ),
                    updateViewOn => [ sub { 'window' }, 'load' ],
                    updateMethod => sub   { 'populatePlatform' }
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
                            ),
                            updateViewOn =>
                              [ sub { 'window' }, 'load', 'pid', 'change' ],
                            updateMethod => sub { 'populatePlatformStudy' }
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
                            selected  => {},
                            updateViewOn =>
                              [ sub { 'window' }, 'load', 'stid', 'change' ],
                            updateMethod => sub { 'populateStudyExperiment' }
                        }
                      )
                    : ()
                )
            ]
        ],
        declare => 1
    ) . $js->apply( 'setupPPDropdowns', [ sub { 'currentSelection' } ] );
}

1;

__END__

=head1 NAME

SGX::ManageStudies

=head1 SYNOPSIS

=head1 DESCRIPTION
Module for managing experiment table.

=head1 AUTHORS
Michael McDuffie
Eugene Scherba

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut


