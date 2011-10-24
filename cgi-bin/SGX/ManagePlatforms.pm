package SGX::ManagePlatforms;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use Scalar::Util qw/looks_like_number/;
use SGX::Abstract::Exception ();
require SGX::Model::ProjectStudyExperiment;

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
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
                    pid   => { label => 'No.', parser => 'number' },
                    pname => {
                        label      => 'Platform Name',
                        -maxlength => 255,
                        -size      => 55
                    },
                    species => {
                        label        => 'Species',
                        -maxlength   => 255,
                        __optional__ => 1,
                        -size        => 35
                    },

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
        _default_table  => 'platform',
        _readrow_tables => [ 'study' => {} ],

        _ProjectStudyExperiment =>
          SGX::Model::ProjectStudyExperiment->new( dbh => $self->{_dbh} ),

    );

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
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
#        CLASS:  ManagePlatforms
#       METHOD:  default_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD default_body
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub default_body {

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
      $q->div( { -class => 'clearfix', -id => $self->{dom_table_id} }, '' );
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
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
    #  Form: Set Project Attributes
    #---------------------------------------------------------------------------
    # :TODO:08/11/2011 16:35:27:es:  here breadcrumbs would be useful
    return $q->h2( 'Editing Platform: ' . $self->{_id_data}->{pname} ),

      $self->body_create_read_menu(
        'read'   => [ undef,         'Edit Platform' ],
        'create' => [ 'form_assign', '' ]
      ),
      $q->h3('Set Platform Attributes'),

      # Resource URI: /platforms/id
      $self->body_create_update_form( mode => 'update' ),

    #---------------------------------------------------------------------------
    #  Studies table
    #---------------------------------------------------------------------------
      $q->h3('All Studies Assigned to this Platform'),
      $q->div(
        $q->a( { -id => $self->{dom_export_link_id} }, 'View as plain text' ) ),
      $q->div( { -class => 'clearfix', -id => $self->{dom_table_id} } );
}

1;

__END__

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


