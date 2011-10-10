
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
# mutable:    Fields that can be modified independently of each other (or other elements).
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
                key       => [qw/eid stid/],
                mutable   => [],
                proto     => [qw/eid stid/],
                selectors => [qw/stid/],
            },
            'study' => {
                key       => [qw/stid/],
                proto     => [qw/description pubmed pid/],
                view      => [qw/description pubmed/],
                mutable   => [qw/description pubmed pid/],    # note: pid !!!
                resource  => 'studies',
                selectors => [qw/pid/],
                names     => [qw/description/],
                labels    => {
                    stid        => 'No.',
                    description => 'Description',
                    pubmed      => 'PubMed',
                    pid         => 'Platform'
                },
                lookup     => { platform => [ pid => 'pid' ] },
                inner_join => {
                    StudyExperiment => [
                        stid => 'stid',
                        { constraint => [ eid => sub { shift->{_id} } ] }
                    ]
                }
            },
            'platform' => {
                key    => [qw/pid/],
                view   => [qw/pname species/],
                names  => [qw/pname/],
                labels => { pname => 'Platform', species => 'Species' }
            },
            'experiment' => {
                key  => [qw/eid/],
                view => [
                    qw/eid sample1 sample2 ExperimentDescription AdditionalInformation/
                ],
                mutable => [
                    qw/sample1 sample2 ExperimentDescription AdditionalInformation/
                ],
                resource => 'experiments',
                proto    => [
                    qw/sample1 sample2 ExperimentDescription AdditionalInformation pid/
                ],
                selectors => [qw/pid/],
                names     => [qw/sample1 sample2/],
                labels    => {
                    eid                   => 'No.',
                    sample1               => 'Sample 1',
                    sample2               => 'Sample 2',
                    ExperimentDescription => 'Description',
                    AdditionalInformation => 'Additional Info'
                },
                lookup     => { microarray      => [ eid => 'eid' ] },
                inner_join => { StudyExperiment => [ eid => 'eid' ] }
            },
            'microarray' => {
                key     => [qw/eid rid/],
                view    => [qw/COUNT(1)/],
                proto   => [],
                mutable => [],
                labels  => {
                    eid        => 'No.',
                    'COUNT(1)' => 'Probe Count'
                },
                inner_join => { StudyExperiment => [ eid => 'eid' ] }
            }
        },
        _default_table => 'experiment',
        _title         => 'Manage Experiments',

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
                extra_platforms   => { 'all' => { name => '@All Platforms' } }
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
        $q->dt( $q->label( { -for => 'pid' }, 'Platform:' ) ),
        $q->dd(
            $q->popup_menu(
                -name  => 'pid',
                -id    => 'pid',
                -title => 'Choose platform'
            )
        ),
        $q->dt( $q->label( { -for => 'description' }, 'Description:' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'description',
                -id        => 'description',
                -maxlength => 100,
                -title     => 'Enter brief study escription (up to 100 letters)'
            )
        ),
        $q->dt( $q->label( { -for => 'pubmed' }, 'PubMed ID:' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'pubmed',
                -id        => 'pubmed',
                -maxlength => 20,
                -title     => 'Enter PubMed ID'
            )
        ),

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

      $self->_body_create_read_menu(
        'read'   => [ undef,         'Edit Experiment' ],
        'create' => [ 'form_assign', 'Assign Studies' ]
      ),
      $q->h3('Assign Studies'), $q->dl(
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

      $self->_body_create_read_menu(
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
        $q->dt( $q->label( { -for => 'pid' }, 'Platform:' ) ),
        $q->dd(
            $q->popup_menu(
                -id       => 'pid',
                -disabled => 'disabled'
            )
        ),
        $q->dt( $q->label( { -for => 'sample1' }, 'sample1' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'sample1',
                -id        => 'sample1',
                -title     => 'Sample 1 Name',
                -maxlength => 100,
                -value     => $self->{_id_data}->{sample1}
            )
        ),
        $q->dt( $q->label( { -for => 'sample2' }, 'sample2' ) ),
        $q->dd(
            $q->textfield(
                -name      => 'sample2',
                -id        => 'sample2',
                -title     => 'Sample 2 Name',
                -maxlength => 100,
                -value     => $self->{_id_data}->{sample2}
            )
        ),
        $q->dt(
            $q->label( { -for => 'ExperimentDescription' }, 'Description' )
        ),
        $q->dd(
            $q->textarea(
                -name  => 'ExperimentDescription',
                -id    => 'ExperimentDescription',
                -title => 'Description',
                -value => $self->{_id_data}->{ExperimentDescription}
            )
        ),
        $q->dt(
            $q->label( { -for => 'AdditionalInformation' }, 'Additional Info' )
        ),
        $q->dd(
            $q->textarea(
                -name  => 'AdditionalInformation',
                -id    => 'AdditionalInformation',
                -title => 'Additional Info',
                -value => $self->{_id_data}->{AdditionalInformation}
            )
        ),
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
