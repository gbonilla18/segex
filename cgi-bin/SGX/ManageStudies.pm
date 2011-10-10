
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

package SGX::ManageStudies;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use SGX::Abstract::JSEmitter qw/true false/;
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

    $self->_set_attributes(

# _table_defs: hash with keys corresponding to the names of tables handled by this module.
#
# key:        Fields that uniquely identify rows
# names:      Fields which identify rows in user-readable manner (row name will be
#             formed by concatenating values with a slash)
# proto:      Fields that are filled out on insert/creation of new records.
# view:       Fields to display.
# selectors:  Fields which, when present in CGI::param list, can narrow down
#             output.
#
# labels:     What to call each field
# left_join:  Whether to query additional tables emulating SQL join. If present, joins
#             will be performed on the corresponding fields.
# inner_join: Whether to add INNER JOIN clause to generated SQL.
        _table_defs => {
            'StudyExperiment' => {
                key        => [qw/stid eid/],
                proto      => [qw/stid eid/],
                join_type  => 'INNER',
                constraint => [ stid => sub { shift->{_id} } ]
            },
            'study' => {
                key      => [qw/stid/],
                proto    => [qw/description pubmed pid/],
                view     => [qw/description pubmed/],
                resource => 'studies',

                # table key to the left, URI param to the right
                selectors => { pid => 'pid' },
                names     => [qw/description/],
                meta      => {
                    stid => {
                        label  => 'No.',
                        parser => 'number',
                        -disabled => 'disabled'
                    },
                    description => {
                        label      => 'Description',
                        -maxlength => 100
                    },
                    pubmed => {
                        label      => 'PubMed',
                        -maxlength => 20
                    },
                    pid => {
                        label     => 'Platform',
                        __type__  => 'popup_menu',
                        parser    => 'number',
                        -disabled => 'disabled'
                    }
                },
                lookup => { platform => [ pid => 'pid' ] },
            },
            'platform' => {
                key   => [qw/pid/],
                view  => [qw/pname species/],
                names => [qw/pname/],
                meta  => {
                    pid     => { label => 'Platform', parser => 'number' },
                    pname   => { label => 'Platform' },
                    species => { label => 'Species' }
                }
            },
            'experiment' => {
                key  => [qw/eid/],
                view => [
                    qw/eid sample1 sample2 ExperimentDescription AdditionalInformation data_count/
                ],
                resource => 'experiments',
                proto    => [
                    qw/sample1 sample2 ExperimentDescription AdditionalInformation/
                ],

                # table key to the left, URI param to the right
                selectors => {},
                names     => [qw/sample1 sample2/],
                meta      => {
                    eid     => { label => 'No.', parser => 'number' },
                    sample1 => { label => 'Sample 1' },
                    sample2 => { label => 'Sample 2' },
                    ExperimentDescription => { label => 'Description' },
                    AdditionalInformation => { label => 'Additional Info' },
                    data_count            => {
                        __sql__ => 'COUNT(microarray.eid)',
                        label   => 'Probe Count',
                        parser  => 'number'
                    },
                },
                join => [
                    StudyExperiment => [ eid => 'eid' ],
                    microarray      => [ eid => 'eid', { join_type => 'LEFT' } ]
                ]
            }
        },
        _default_table => 'study',
        _title         => 'Manage Studies',

        _PlatformStudyExperiment =>
          SGX::Model::PlatformStudyExperiment->new( dbh => $self->{_dbh} ),

        _id      => undef,
        _id_data => {},
    );

    $self->_register_actions(
        'head' => {
            form_create => 'form_create_head',
            form_assign => 'form_assign_head'
        },
        'body' => {
            form_create => 'form_create_body',
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

    # get data for given study
    $self->SUPER::readrow_head();

    # add extra table showing experiments
    $self->generate_datatable( 'experiment',
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
    push @{ $self->{_js_src_code} },
      (
        { -src => 'PlatformStudyExperiment.js' },
        {
            -code => $self->get_pse_dropdown_js(
                platforms       => 1,
                extra_platforms => {
                    'all' => { name => '@All Platforms' },
                    ''    => { name => '@Unassigned Studies' }
                }
            )
        }
      );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageStudies
#       METHOD:  form_create
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_create_head {
    my $self = shift;
    return if defined $self->{_id};    # no _id

    push @{ $self->{_js_src_code} },
      (
        { -src  => 'PlatformStudyExperiment.js' },
        { -code => $self->get_pse_dropdown_js( platforms => 1 ) }
      );
    return 1;
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
      $self->_body_create_read_menu(
        'read'   => [ undef,         'View Existing' ],
        'create' => [ 'form_create', 'Create New' ]
      ),

      # Resource URI: /studies
      $self->_view_start_get_form(),
      $q->dl(
        $q->dt( $q->label( { -for => 'pid' }, 'Platform:' ) ),
        $q->dd(
            $q->popup_menu(
                -name  => 'pid',
                -id    => 'pid',
                -title => 'Choose platform',
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $self->_view_hidden_resource(),
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
sub form_create_body {

    my $self = shift;
    my $q    = $self->{_cgi};

    return $q->h2( $self->{_title} ),
      $self->_body_create_read_menu(
        'read'   => [ undef,         'View Existing' ],
        'create' => [ 'form_create', 'Create New' ]
      ),
      $q->h3('Create New Study'),

      # Resource URI: /studies
      $q->start_form(
        -method   => 'POST',
        -action   => $self->get_resource_uri(),
        -onsubmit => 'return validate_fields(this, [\'description\']);'
      ),
      $q->dl(
        $self->_body_edit_fields(mode => 'create'),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->hidden( -name => 'b', -value => 'create' ),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Create Study',
                -title => 'Create a new study'
            )
        )
      ),
      $q->end_form;
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
                studies           => 1,
                experiments       => 1,
                extra_studies => { '' => { name => '@Unassigned Experiments' } }
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
    #  Form: Assign Experiment to this Study
    #---------------------------------------------------------------------------

    return $q->h2('Editing Study'),

      $self->_body_create_read_menu(
        'read'   => [ undef,         'Edit Study' ],
        'create' => [ 'form_assign', 'Assign Experiments' ]
      ),
      $q->h3('Assign Experiments:'),
      $q->dl(
        $q->dt( $q->label( { -for => 'pid' }, 'From platform:' ) ),
        $q->dd(
            $q->popup_menu(
                -id       => 'pid',
                -disabled => 'disabled'
            )
        ),
        $q->dt( $q->label( { -for => 'stid' }, 'From study:' ) ),
        $q->dd(
            $q->popup_menu(
                -name   => 'stid',
                -id     => 'stid',
                -title  => qq/Choose a study/,
                -values => [],
                -labels => {}
            )
        )
      ),

      # Resource URI: /studies/id
      $q->start_form(
        -method => 'POST',
        -action => $self->get_resource_uri()
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'eid' }, 'Experiment:' ) ),
        $q->dd(
            $q->popup_menu(
                -name     => 'eid',
                -id       => 'eid',
                -multiple => 'multiple',
                -title =>
qq/You can select multiple experiments here by holding down Control or Command key before clicking./,
                -size   => 7,
                -values => [],
                -labels => {}
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->hidden( -name => 'table', -value => 'StudyExperiment' ),
            $q->hidden( -name => 'b',     -value => 'assign' ),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Assign',
                -title => qq/Assign selected experiments to this study/
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
    #  Form: Set Study Attributes
    #---------------------------------------------------------------------------
    # :TODO:08/11/2011 16:35:27:es:  here breadcrumbs would be useful
    return $q->h2('Editing Study'),

      $self->_body_create_read_menu(
        'read'   => [ undef,         'Edit Study' ],
        'create' => [ 'form_assign', 'Assign Experiments' ]
      ),
      $q->h3('Set Study Attributes'),

      # Resource URI: /studies/id
      $q->start_form(
        -method   => 'POST',
        -action   => $self->get_resource_uri(),
        -onsubmit => 'return validate_fields(this, [\'description\']);'
      ),
      $q->dl(
        $self->_body_edit_fields(mode => 'update'),
        $q->dt('&nbsp;'),
        $q->dd(
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
      $q->h3('All Experiments in the Study'),
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

    my $js = SGX::Abstract::JSEmitter->new( pretty => 0 );

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
