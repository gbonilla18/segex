package SGX::ManageProjects;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use SGX::Abstract::Exception ();
require SGX::Model::ProjectStudyExperiment;

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

    $self->set_attributes(

        _table_defs => {
            'ProjectStudy' => {
                key        => [qw/prid stid/],
                view       => [],
                base       => [qw/prid stid/],
                join_type  => 'INNER',
                constraint => [ prid => sub { shift->{_id} } ]
            },
            'project' => {
                item_name => 'project',
                resource  => 'projects',
                key       => [qw/prid/],
                view      => [qw/prname prdesc/],
                base      => [qw/prname prdesc manager/],

                # table key to the left, URI param to the right
                selectors => { manager => 'manager' },
                names     => [qw/prname/],
                meta      => {
                    prid => {
                        label  => 'No.',
                        parser => 'number'
                    },
                    manager => {
                        label    => 'Created By',
                        parser   => 'number',
                        __type__ => 'popup_menu',

                        __tie__      => [ users => 'uid' ],
                        __hidden__   => 1,
                        __optional__ => 1
                    },
                    prname => {
                        label      => 'Project Name',
                        -maxlength => 255,
                        -size      => 55
                    },
                    prdesc => {
                        label        => 'Description',
                        __optional__ => 1,
                        -maxlength   => 255,
                        -size        => 55
                    }
                },
                lookup => [ users => [ manager => 'uid' ] ]
            },
            'study' => {
                key => [qw/stid/],

                # table key to the left, URI param to the right
                selectors => { pid => 'pid' },
                view      => [qw/description pubmed/],
                base      => [qw/description pubmed/],
                resource  => 'studies',
                names     => [qw/description/],
                meta      => {
                    stid => { label => 'No.', parser => 'number' },
                    description => { label => 'Description' },
                    pubmed      => {
                        label     => 'PubMed ID',
                        formatter => sub {
                            'formatPubMed';
                          }
                    },
                    pid => {
                        label      => 'Platform',
                        parser     => 'number',
                        __hidden__ => 1
                    }
                },
                lookup => [ platform     => [ pid  => 'pid' ] ],
                join   => [ ProjectStudy => [ stid => 'stid' ] ]
            },
            'users' => {
                resource  => 'users',
                item_name => 'user',
                key       => [qw/uid/],
                view      => [qw/full_name/],
                names     => [qw/full_name/],
                meta      => {
                    uid       => { label => 'ID', parser => 'number' },
                    uname     => { label => 'Login ID' },
                    full_name => { label => 'Created By' }
                },
            },
            'platform' => {
                key   => [qw/pid/],
                view  => [qw/pname/],
                names => [qw/pname/],
                meta  => {
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
            }
        },
        _default_table  => 'project',
        _readrow_tables => [
            'study' => {
                heading    => 'Studies in Project',
                actions    => { form_assign => 'assign' },
                remove_row => { verb => 'unassign', table => 'ProjectStudy' }
            }
        ],

        _ProjectStudyExperiment =>
          SGX::Model::ProjectStudyExperiment->new( dbh => $self->{_dbh} ),
    );

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
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
#        CLASS:  ManageProjects
#       METHOD:  form_create_head
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD form_create_head
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub form_create_head {
    my $self = shift;
    my $s    = $self->{_UserSession};
    $self->{_id_data}->{manager} = $s->get_user_id();
    return $self->SUPER::form_create_head();
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
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
        { -src => 'ProjectStudyExperiment.js' },
        {
            -code => $self->get_pse_dropdown_js(
                extra_projects => {
                    'all' => { prname => '@All Projects' },
                    ''    => { prname => '@Unassigned Studies' }
                },
                projects         => 1,
                project_by_study => 1,
                studies          => 1
            )
        },
      );

    return 1;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
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
    #  Form: Assign Study to this Project
    #---------------------------------------------------------------------------

    return $q->h2( 'Editing Project: ' . $self->{_id_data}->{prname} ),

      $self->body_create_read_menu(
        'read'   => [ undef,         'Edit Project' ],
        'create' => [ 'form_assign', 'Assign Studies' ]
      ),
      $q->h3('Assign Studies:'),
      $q->dl(
        $q->dt( $q->label( { -for => 'prid' }, 'From project:' ) ),
        $q->dd(
            $q->popup_menu(
                -name   => 'prid',
                -id     => 'prid',
                -title  => qq/Choose a project/,
                -values => [],
                -labels => {}
            )
        )
      ),

      # Resource URI: /projects/id
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

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageProjects
#       METHOD:  get_pse_dropdown_js
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:
# # :TODO:10/08/2011 11:38:06:es: Isolate this method outside this class
#     SEE ALSO:  n/a
#===============================================================================
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
    $prid = $q->param('prid') unless defined $prid;

    return $js->let(
        [
            ProjStudyExp => $self->{_ProjectStudyExperiment}->get_ByProject(),
            currentSelection => [
                'project' => {
                    elementId => 'prid',
                    element   => undef,
                    selected => ( ( defined $prid ) ? { $prid => undef } : {} ),
                    updateViewOn => [ sub { 'window' }, 'load' ],
                    updateMethod => sub   { 'populateProject' }
                },
                (
                    ( $args{studies} )
                    ? (
                        'study' => {
                            elementId => 'stid',
                            element   => undef,
                            selected  => {},
                            updateViewOn =>
                              [ sub { 'window' }, 'load', 'prid', 'change' ],
                            updateMethod => sub { 'populateProjectStudy' }
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

SGX::ManageProjects

=head1 SYNOPSIS

=head1 DESCRIPTION
Module for managing project table.

=head1 AUTHORS
Eugene Scherba
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut


