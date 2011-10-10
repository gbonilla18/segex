
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

package SGX::ManageExperiments;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use Scalar::Util qw/looks_like_number/;
use SGX::Abstract::Exception;
use SGX::Model::PlatformStudyExperiment;

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageStudies
#       METHOD:  new
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Override parent constructor; add attributes to object instance
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ( $class, @param ) = @_;

    my $self = $class->SUPER::new(@param);
    my $q    = $self->{_cgi};

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
                base     => [qw/description pubmed pid/],
                view     => [qw/description pubmed/],
                resource => 'studies',

                # table key to the left, URI param to the right
                names => [qw/description/],
                meta  => {
                    stid => { label => 'No.', parser => 'number' },
                    description => { label => 'Description' },
                    pubmed      => { label => 'PubMed' },
                    pid         => {
                        label        => 'Platform',
                        parser       => 'number',
                        __readonly__ => 1,
                        __tie__      => [ platform => 'pid' ],
                        __hidden__   => 1
                    },
                },
                lookup => [ platform => [ pid => 'pid' ] ],
                join   => [
                    StudyExperiment => [
                        stid => 'stid',
                        { constraint => [ eid => sub { shift->{_id} } ] }
                    ]
                ]
            },
            study_brief => {
                table     => 'StudyExperiment',
                key       => [qw/eid stid/],
                view      => [qw/description/],
                selectors => { stid => 'stid' },
                meta      => {
                    description => {
                        __sql__ => 'study.description',
                        label   => 'Study(-ies)'
                    }
                },
                join =>
                  [ 'study' => [ stid => 'stid', { join_type => 'INNER' } ] ]
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
                    qw/eid sample1 sample2 ExperimentDescription AdditionalInformation/
                ],
                resource => 'experiments',
                base     => [
                    qw/sample1 sample2 ExperimentDescription AdditionalInformation pid/
                ],

                # table key to the left, URI param to the right
                selectors => { pid => 'pid' },
                names     => [qw/sample1 sample2/],
                meta      => {
                    eid => {
                        label  => 'No.',
                        parser => 'number',
                    },
                    sample1 => {
                        label      => 'Sample 1',
                        -maxlength => 100,
                        -size      => 35
                    },
                    sample2 => {
                        label      => 'Sample 2',
                        -maxlength => 100,
                        -size      => 35
                    },
                    ExperimentDescription => {
                        label => 'Description',
                        -size => 55
                    },
                    AdditionalInformation => {
                        label        => 'Additional Info',
                        -size        => 55,
                        __optional__ => 1
                    },
                    pid => {
                        label    => 'Platform',
                        parser   => 'number',
                        __type__ => 'popup_menu',
                        __tie__  => (
                            looks_like_number( $q->param('pid') )
                            ? undef
                            : [ platform => 'pid' ]
                        ),
                        __readonly__ => 1,
                        __hidden__   => 1
                    }
                },
                lookup => [
                    (

                        # No need to display study column if specific study is
                        # requested.
                        looks_like_number( $q->param('stid') )
                        ? ()
                        : ( 'study_brief' => [ 'eid' => 'eid' ] )
                    ),
                    (

                        # No need to display platform column if specific
                        # platform is requested.
                        looks_like_number( $q->param('pid') )
                        ? ()
                        : ( 'platform' => [ 'pid' => 'pid' ] )
                    )
                ],
                join => [
                    StudyExperiment => [
                        eid => 'eid',
                        { selectors => { stid => 'stid' } }
                    ],
                    data_count => [ eid => 'eid' ]
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
                join_type => 'LEFT',
                group_by  => [qw/eid/]
            }
        },
        _default_table => 'experiment',

        # :TODO:10/05/2011 16:35:27:es: can generate _title automatically from
        # _item_name
        _title     => 'Manage Experiments',
        _item_name => 'Experiment',

        _PlatformStudyExperiment =>
          SGX::Model::PlatformStudyExperiment->new( dbh => $self->{_dbh} ),

        _id      => undef,
        _id_data => {},
    );

    $self->register_actions(
        'head' => {
            form_assign => 'form_assign_head'
        },
        'body' => {
            form_assign => 'form_assign_body'
        }
    );

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageStudies
#       METHOD:  readrow
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub readrow_head {
    my $self = shift;

    # get data for given experiment
    $self->SUPER::readrow_head();

    # add extra table showing studies
    $self->generate_datatable( 'study',
        remove_row => [ 'unassign' => 'StudyExperiment' ] );

    # add platform dropdown
    push @{ $self->{_js_src_code} },
      (
        { -src  => 'PlatformStudyExperiment.js' },
        { -code => $self->get_pse_dropdown_js( platform_by_study => 1 ) }
      );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageStudies
#       METHOD:  readall
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub readall_head {
    my $self = shift;

    # view all rows
    $self->SUPER::readall_head();

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
                    'all' => { name => '@All Studies' },
                    ''    => { name => '@Unassigned Experiments' }
                }
            )
        }
    );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageStudies
#       METHOD:  form_create_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_create_head {
    my $self = shift;

    push @{ $self->{_js_src_code} },
      (
        { -src  => 'PlatformStudyExperiment.js' },
        { -code => $self->get_pse_dropdown_js( platforms => 1 ) }
      );
    return $self->SUPER::form_create_head();
}

#######################################################################################
#PRINTING HTML AND JAVASCRIPT STUFF
#######################################################################################
sub readall_body {

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
        $q->dt( $q->label( { -for => 'stid' }, 'Study' ) ),
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
      $q->div( { -id => $self->{dom_table_id} }, '' );
}
#######################################################################################
sub form_assign_head {
    my $self = shift;
    return if not defined $self->{_id};    # _id must be present
    $self->_readrow_command()->();

    push @{ $self->{_js_src_code} },
      (
        { -src => 'PlatformStudyExperiment.js' },
        {
            -code => $self->get_pse_dropdown_js(
                platforms         => 1,
                platform_by_study => 1,
                studies           => 1
            )
        }
      );

    return 1;
}
#######################################################################################
sub form_assign_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    #---------------------------------------------------------------------------
    #  Form: Assign Studies to this Experiment
    #---------------------------------------------------------------------------

    return $q->h2('Editing Experiment'),

      $self->body_create_read_menu(
        'read'   => [ undef,         'Edit Experiment' ],
        'create' => [ 'form_assign', 'Assign Studies' ]
      ),
      $q->h3('Assign Studies'),
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
                -title => qq/Assign selected studies to this experiment/
            )
        )
      ),
      $q->end_form;
}
#######################################################################################
sub readrow_body {
    my $self = shift;
    my $q    = $self->{_cgi};

    #---------------------------------------------------------------------------
    #  Form: Set Experiment Attributes
    #---------------------------------------------------------------------------
    # :TODO:08/11/2011 16:35:27:es:  here breadcrumbs would be useful

    return $q->h2('Editing Experiment'),

      $self->body_create_read_menu(
        'read'   => [ undef,         'Edit Experiment' ],
        'create' => [ 'form_assign', 'Assign Studies' ]
      ),
      $q->h3('Set Experiment Attributes'),

      $q->start_form(
        -method   => 'POST',
        -action   => $self->get_resource_uri(),
        -onsubmit => 'return validate_fields(this, [\'description\']);'
      ),
      $q->dl(
        $self->body_edit_fields( mode => 'update' ),
        $q->dt('&nbsp;') => $q->dd(
            $q->hidden( -name => 'b', -value => 'update' ),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Set Attributes',
                -title => 'Change study attributes'
            )
        )
      ),
      $q->end_form,

    #---------------------------------------------------------------------------
    #  Experiments table
    #---------------------------------------------------------------------------
      $q->h3('All Studies assigned to the Experiment'),
      $q->div(
        $q->a( { -id => $self->{dom_export_link_id} }, 'View as plain text' ) ),
      $q->div( { -style => 'clear:both;', -id => $self->{dom_table_id} } );
}

#######################################################################################
sub get_pse_dropdown_js {
    my ( $self, %args ) = @_;

    my $pse = $self->{_PlatformStudyExperiment};
    $pse->init(
        platforms => 1,
        %args
    );

    my $js = $self->{_js_emitter};

    my $q = $self->{_cgi};
    my $pid;
    if ( defined $self->{_id} ) {

        # If a study is set, use the corresponding platform while ignoring the
        # platform parameter.
        $pid = $pse->getPlatformFromStudy( $self->{_id} );
    }
    $pid = $q->param('pid') if not defined $pid;

    return $js->bind(
        [
            PlatfStudyExp =>
              $self->{_PlatformStudyExperiment}->get_ByPlatform(),
            currentSelection => {
                'platform' => {
                    elementId => 'pid',
                    element   => undef,
                    selected  => ( defined $pid ) ? { $pid => undef } : {}
                },
                (
                    ( $args{studies} )
                    ? (
                        'study' => {
                            elementId => 'stid',
                            element   => undef,
                            selected  => {}
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
                $js->apply(
                    'populatePlatform.apply', [ sub { 'currentSelection' } ],
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
