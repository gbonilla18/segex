package SGX::ManageStudies;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use Scalar::Util qw/looks_like_number/;
use SGX::Abstract::Exception ();
require SGX::Model::PlatformStudyExperiment;

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
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    my ( $q, $s ) = @$self{qw/_cgi _UserSession/};
    my $curr_proj = $s->{session_cookie}->{curr_proj};

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
                key        => [qw/stid eid/],
                base       => [qw/stid eid/],
                join_type  => 'INNER',
                constraint => [ stid => sub { shift->{_id} } ]
            },
            'study' => {
                item_name => 'study',
                key       => [qw/stid/],
                base      => [qw/description pubmed pid/],
                view      => [qw/description pubmed/],
                resource  => 'studies',

                # table key to the left, URI param to the right
                selectors => { pid => 'pid' },
                names     => [qw/description/],
                meta      => {
                    stid => {
                        label        => 'No.',
                        parser       => 'number',
                        __readonly__ => 1
                    },
                    description => {
                        label      => 'Study Description',
                        -maxlength => 255,
                        -size      => 55
                    },
                    pubmed => {
                        label        => 'PubMed',
                        formatter    => sub { 'formatPubMed' },
                        -maxlength   => 255,
                        __optional__ => 1
                    },
                    pid => {
                        label        => 'Platform',
                        __type__     => 'popup_menu',
                        parser       => 'number',
                        __readonly__ => 1,
                        (
                            looks_like_number( $q->param('pid') )
                            ? ()
                            : __tie__ => [ ( platform => 'pid' ) ]
                        ),

                        #__tie__      => [
                        #    (
                        #        looks_like_number( $q->param('pid') ) ? ()
                        #        : ( platform => 'pid' )
                        #    )
                        #],
                        __hidden__ => 1
                    },
                },
                lookup => [
                    (
                        looks_like_number( $q->param('pid') ) ? ()
                        : ( platform => [ pid => 'pid' ] )
                    )
                ],
                join => [
                    (
                        ( defined $curr_proj && $curr_proj ne '' )
                        ? (
                            ProjectStudy => [
                                stid => 'stid',
                                {
                                    join_type  => 'INNER',
                                    constraint => [ prid => $curr_proj ]
                                }
                            ]
                          )
                        : ()
                    )
                ]
            },
            'platform' => {
                resource  => 'platforms',
                item_name => 'platform',
                key       => [qw/pid/],
                view      => [qw/pname/],
                names     => [qw/pname/],
                meta      => {
                    pid   => { label => 'Platform', parser => 'number' },
                    pname => { label => 'Platform' },
                },
                join => [ species => [ sid => 'sid', { join_type => 'LEFT' } ] ]
            },
            species => {
                key   => [qw/sid/],
                view  => [qw/sname/],
                names => [qw/sname/],
                meta  => { sname => { label => 'Species' } }
            },
            'experiment' => {
                key  => [qw/eid/],
                view => [
                    qw/eid sample1 sample2 ExperimentDescription AdditionalInformation/
                ],
                resource => 'experiments',
                base     => [
                    qw/sample1 sample2 ExperimentDescription AdditionalInformation/
                ],

                # table key to the left, URI param to the right
                selectors => {},
                names     => [qw/sample1 sample2/],
                meta      => {
                    eid => {
                        label        => 'No.',
                        parser       => 'number',
                        __readonly__ => 1
                    },
                    sample1               => { label => 'Sample 1' },
                    sample2               => { label => 'Sample 2' },
                    ExperimentDescription => { label => 'Description' },
                    AdditionalInformation => { label => 'Additional Info' },
                },
                join => [
                    StudyExperiment => [ eid => 'eid' ],
                    data_count      => [ eid => 'eid', { join_type => 'LEFT' } ]
                ]
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
        _default_table  => 'study',
        _readrow_tables => [
            'experiment' => {
                heading    => 'Experiments in Study',
                actions    => { form_assign => 'assign' },
                remove_row => { verb => 'unassign', table => 'StudyExperiment' }
            },
        ],

        _PlatformStudyExperiment =>
          SGX::Model::PlatformStudyExperiment->new( dbh => $self->{_dbh} ),
    );

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageStudies
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my $self = shift;
    $self->SUPER::init();

    $self->register_actions( form_assign =>
          { head => 'form_assign_head', body => 'form_assign_body' } );

    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageStudies
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

    # add platform dropdown
    push @{ $self->{_js_src_code} },
      (
        { -src => 'PlatformStudyExperiment.js' },
        {
            -code => $self->get_pse_dropdown_js(
                platforms       => 1,
                extra_platforms => { all => { pname => '@All Platforms' } }
            )
        },
      );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageStudies
#       METHOD:  default_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD default_body
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_body {
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
#        CLASS:  ManageStudies
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
                platforms         => 1,
                platform_by_study => 1,
                studies           => 1,
                experiments       => 1,
                extra_studies => { '' => { description => '@Unassigned Experiments' } }
            )
        },
      );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageStudies
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
    #  Form: Assign Experiment to this Study
    #---------------------------------------------------------------------------

    return $q->h2( 'Editing Study: ' . $self->{_id_data}->{description} ),

      $self->body_create_read_menu(
        'read'   => [ undef,         'Edit Study' ],
        'create' => [ 'form_assign', 'Assign Experiments' ]
      ),
      $q->h3('Create New Experiment:'),
      $q->dl(
        $q->dt('&nbsp;'),
        $q->dd(
            $q->a(
                {
                        -href => $self->url( -absolute => 1 )
                      . '?a=experiments&b=form_create&stid='
                      . $self->{_id}
                },
                'Upload Data'
            )
        )
      ),
      $q->h3('- or -'), $q->h3('Assign Existing Experiments:'),
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

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageStudies
#       METHOD:  get_pse_dropdown_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:
# # :TODO:10/08/2011 11:36:24:es: Isolate this method outside this class
#     SEE ALSO:  n/a
#===============================================================================
sub get_pse_dropdown_js {
    my ( $self, %args ) = @_;

    my $pse = $self->{_PlatformStudyExperiment};
    $pse->init(
        platforms => 1,
        %args
    );

    my ( $q, $js ) = @$self{qw/_cgi _js_emitter/};

    # If a study is set, use the corresponding platform while ignoring the
    # platform parameter.
    my $stid = $self->{_id};
    my $pid =
      ( defined $stid )
      ? $pse->getPlatformFromStudy($stid)
      : $q->param('pid');

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
Module for managing study table.

=head1 AUTHORS
Michael McDuffie
Eugene Scherba

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut


