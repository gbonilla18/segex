
=head1 NAME

SGX::ManageProjects

=head1 SYNOPSIS

=head1 DESCRIPTION
Grouping of functions for managing projects.

=head1 AUTHORS
Eugene Scherba
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::ManagePlatforms;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use Scalar::Util qw/looks_like_number/;
use SGX::Abstract::Exception;
use SGX::Model::ProjectStudyExperiment;

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
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
# fields:      Fields that are filled out on insert/creation of new records.
# view:       Fields to display.
# selectors:  Fields which, when present in CGI::param list, can narrow down
#             output. Format: { URI => SQL }.
# meta:       Additional field info.
        _table_defs => {
            'platform' => {
                key      => [qw/pid/],
                resource => 'platforms',
                base     => [qw/pname def_p_cutoff def_f_cutoff species/],
                view     => [qw/pname def_p_cutoff def_f_cutoff species/],
                selectors => {}, # table key to the left, URI param to the right
                names => [qw/pname species/],
                meta  => {
                    pid => { label => 'No.', parser => 'number' },
                    pname   => { label => 'Platform Name', -maxlength => 100 },
                    species => { label => 'Species',       -maxlength => 100 },

                    # def_p_cutoff
                    def_p_cutoff => {
                        label      => 'P-value Cutoff',
                        parser     => 'number',
                        -maxlength => 20,

                        # validate def_p_cutoff
                        __valid__ => sub {
                            my $val = shift;
                            (        looks_like_number($val)
                                  && $val >= 0
                                  && $val <= 1 )
                              or SGX::Exception::User->throw( error =>
                                  'P-value must be a number from 0.0 to 1.0' );
                        },
                    },

                    # def_f_cutoff
                    def_f_cutoff => {
                        label      => 'Fold-change Cutoff',
                        parser     => 'number',
                        -maxlength => 20,

                        # validate def_f_cutoff
                        __valid__ => sub {
                            my $val = shift;
                            ( looks_like_number($val) && abs($val) >= 1 )
                              or SGX::Exception::User->throw( error =>
'Fold change must be a number <= -1.0 or >= 1.0'
                              );
                        },
                    },
                },
                join => [ probe => [ pid => 'pid', { join_type => 'LEFT' } ] ]
            },
            probe => {
                key  => [qw/pid/],
                view => [qw/probes_total probe_sequences probe_locations/],
                meta => {
                    probes_total => {
                        __sql__ => 'COUNT(probe.rid)',
                        label   => 'Probe Count',
                        parser  => 'number'
                    },
                    probe_sequences => {
                        __sql__ => 'COUNT(probe.probe_sequence)',
                        label   => 'Probe Sequences',
                        parser  => 'number'
                    },
                    probe_locations => {
                        __sql__ => 'COUNT(probe.location)',
                        label   => 'Locations',
                        parser  => 'number'
                    }
                },
                group_by => [qw/pid/]
            },
            'study' => {
                key      => [qw/stid/],
                view     => [qw/description pubmed/],
                base     => [qw/description pubmed/],
                resource => 'studies',
                selectors => {}, # table key to the left, URI param to the right
                names => [qw/description/],
                meta  => {
                    stid => {
                        label      => 'No.',
                        parser     => 'number',
                        __hidden__ => 1
                    },
                    description => { label => 'Description' },
                    pubmed      => { label => 'PubMed ID' }
                },
                lookup     => [ proj_brief => [ stid => 'stid' ] ],
                constraint => [ pid        => sub    { shift->{_id} } ]
            },
            proj_brief => {
                table => 'ProjectStudy',
                key   => [qw/stid prid/],
                view  => [qw/prname/],
                meta  => {
                    prname => {
                        __sql__ => 'project.prname',
                        label   => 'Project(s)'
                    }
                },
                join =>
                  [ project => [ prid => 'prid', { join_type => 'INNER' } ] ]
            },
            'experiment' => {
                key  => [qw/eid/],
                view => [qw/sample1 sample2/],
                base => [],
                selectors => {}, # table key to the left, URI param to the right
                names => [qw/sample1 sample2/]
            },
        },
        _default_table => 'platform',
        _title         => 'Manage Platforms',

        _id      => undef,
        _id_data => {},

        _ProjectStudyExperiment =>
          SGX::Model::ProjectStudyExperiment->new( dbh => $self->{_dbh} ),

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
#        CLASS:  ManageProjects
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

    # get data for given platform
    $self->SUPER::readrow_head();

    my $table = 'study';

    # add extra table showing studies
    $self->generate_datatable( 'study', remove_row => ['unassign'] );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
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
    return if defined $self->{_id};    # {_id} must not be set

    return 1;
}

#######################################################################################
#PRINTING HTML AND JAVASCRIPT STUFF
#######################################################################################
sub readall_body {

    # Form HTML for the project table.
    my $self = shift;
    my $q    = $self->{_cgi};

    #---------------------------------------------------------------------------
    #  Project dropdown
    #---------------------------------------------------------------------------
    my $resource_uri = $self->get_resource_uri();
    return $q->h2( $self->{_title} ),
      $self->body_create_read_menu(
        'read'   => [ undef,         'View Existing' ],
        'create' => [ 'form_create', 'Create New' ]
      ),

    #---------------------------------------------------------------------------
    #  Table showing all projects in all projects
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
      $self->body_create_read_menu(
        'read'   => [ undef,         'View Existing' ],
        'create' => [ 'form_create', 'Create New' ]
      ),
      $q->h3('Create New Platform'),

      # Resource URI: /projects
      $q->start_form(
        -method   => 'POST',
        -action   => $self->get_resource_uri(),
        -onsubmit => 'return validate_fields(this, [\'pname\']);'
      ),
      $q->dl(
        $self->body_edit_fields( mode => 'create' ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->hidden( -name => 'b', -value => 'create' ),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Create Platform',
                -title => 'Create a new platform'
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
        { -src => 'ProjectStudyExperiment.js' },
        {
            -code => $self->get_pse_dropdown_js(
                extra_projects => {
                    'all' => { name => '@All Projects' },
                    ''    => { name => '@Unassigned Studies' }
                },
                projects         => 1,
                project_by_study => 1,
                studies          => 1
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
    #  Form: Assign Study to this Platform
    #---------------------------------------------------------------------------

    return $q->h2('Editing Platform'),

      $self->body_create_read_menu(
        'read'   => [ undef,         'Edit Platform' ],
        'create' => [ 'form_assign', 'Assign Studies' ]
      ),
      $q->h3('Assign Studies:'),
      $q->dl(
        $q->dt( $q->label( { -for => 'prid' }, 'From platform:' ) ),
        $q->dd(
            $q->popup_menu(
                -name   => 'prid',
                -id     => 'prid',
                -title  => qq/Choose a platform/,
                -values => [],
                -labels => {}
            )
        )
      ),

      # Resource URI: /platforms/id
      $q->start_form(
        -method => 'POST',
        -action => $self->get_resource_uri()
      ),
      $q->dl(
        $q->dt( $q->label( { -for => 'stid' }, 'Study:' ) ),
        $q->dd(
            $q->popup_menu(
                -name     => 'stid',
                -id       => 'stid',
                -multiple => 'multiple',
                -title =>
qq/You can select multiple studies here by holding down Control or Command key before clicking./,
                -size   => 7,
                -values => [],
                -labels => {}
            )
        ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->hidden( -name => 'table', -value => 'ProjectStudy' ),
            $q->hidden( -name => 'b',     -value => 'assign' ),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Assign',
                -title => qq/Assign selected study to this project/
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
    #  Form: Set Project Attributes
    #---------------------------------------------------------------------------
    # :TODO:08/11/2011 16:35:27:es:  here breadcrumbs would be useful
    return $q->h2('Editing Platform'),

      $self->body_create_read_menu(
        'read'   => [ undef,         'Edit Platform' ],
        'create' => [ 'form_assign', 'Assign Studies' ]
      ),
      $q->h3('Set Platform Attributes'),

      # Resource URI: /platforms/id
      $q->start_form(
        -method   => 'POST',
        -action   => $self->get_resource_uri(),
        -onsubmit => 'return validate_fields(this, [\'pname\']);'
      ),
      $q->dl(
        $self->body_edit_fields( mode => 'update' ),
        $q->dt('&nbsp;'),
        $q->dd(
            $q->hidden( -name => 'b', -value => 'update' ),
            $q->submit(
                -class => 'button black bigrounded',
                -value => 'Set Attributes',
                -title => 'Change project attributes'
            )
        )
      ),
      $q->end_form,

    #---------------------------------------------------------------------------
    #  Studies table
    #---------------------------------------------------------------------------
      $q->h3('All Studies Assigned to this Platform'),
      $q->div(
        $q->a( { -id => $self->{dom_export_link_id} }, 'View as plain text' ) ),
      $q->div( { -style => 'clear:both;', -id => $self->{dom_table_id} } );
}

#######################################################################################
sub get_pse_dropdown_js {
    my ( $self, %args ) = @_;

    my $pse = $self->{_ProjectStudyExperiment};
    $pse->init(
        projects => 1,
        %args
    );

    my $js = $self->{_js_emitter};

    my $q    = $self->{_cgi};
    my $prid = $self->{_id};
    $prid = $q->param('prid') if not defined $prid;

    return $js->bind(
        [
            ProjStudyExp => $self->{_ProjectStudyExperiment}->get_ByProject(),
            currentSelection => {
                'project' => {
                    elementId => 'prid',
                    element   => undef,
                    selected  => ( defined $prid ) ? { $prid => undef } : {}
                },
                (
                    ( $args{projects} )
                    ? (
                        'project' => {
                            elementId => 'prid',
                            element   => undef,
                            selected  => {}
                        }
                      )
                    : ()
                ),
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
                    'populateProject.apply', [ sub { 'currentSelection' } ],
                ),
                (
                    ( $args{projects} && $args{studies} )
                    ? (
                        $js->apply(
                            'populateProjectStudy.apply',
                            [ sub { 'currentSelection' } ],
                        )
                      )
                    : ()
                )
            )
        ]
      )
      . (
        ( $args{projects} || $args{studies} )
        ? (
            $js->apply(
                'YAHOO.util.Event.addListener',
                [
                    'prid', 'change',
                    $js->lambda(
                        [],
                        (
                            ( $args{projects} && $args{studies} )
                            ? (
                                $js->apply(
                                    'populateProjectStudy.apply',
                                    [ sub { 'currentSelection' } ],
                                )
                              )
                            : ()
                        )
                    )
                ]
            )
          )
        : ''
      )
      . (
        ( $args{projects} && $args{studies} )
        ? (
            $js->apply(
                'YAHOO.util.Event.addListener',
                [
                    'prid', 'change',
                    $js->lambda(
                        [],
                        $js->apply(
                            'populateProjectStudy.apply',
                            [ sub { 'currentSelection' } ],
                        )
                    )
                ]
            )
          )
        : ''
      );
}

1;
