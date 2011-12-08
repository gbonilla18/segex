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
                item_name => 'platform',
                key       => [qw/pid/],
                resource  => 'platforms',
                base      => [qw/pname def_p_cutoff def_f_cutoff sid file/],
                view      => [qw/pname def_p_cutoff def_f_cutoff/],

                # table key to the left, URI param to the right
                selectors => { sid => 'sid' },
                names     => [qw/pname/],
                meta      => {
                    sid => {
                        label        => 'Species',
                        __type__     => 'popup_menu',
                        __readonly__ => 1,
                        __tie__      => [ species => 'sid' ]
                    },
                    file => {
                        __type__     => 'filefield',
                        __special__  => 1,
                        __optional__ => 1,
                        label        => 'Upload Probes/Annotations'
                    },
                    pid   => { label => 'No.', parser => 'number' },
                    pname => {
                        label      => 'Platform Name',
                        -maxlength => 255,
                        -size      => 55
                    },

                    # def_p_cutoff
                    def_p_cutoff => {
                        label      => 'P-value Cutoff',
                        parser     => 'number',
                        -maxlength => 20,

                        # validate def_p_cutoff
                        __encode__ => sub {
                            my $val = shift;
                            (        looks_like_number($val)
                                  && $val >= 0
                                  && $val <= 1 )
                              or SGX::Exception::User->throw( error =>
                                  'P-value must be a number from 0.0 to 1.0' );
                            return $val;
                        },
                    },

                    # def_f_cutoff
                    def_f_cutoff => {
                        label      => 'Fold-change Cutoff',
                        parser     => 'number',
                        -maxlength => 20,

                        # validate def_f_cutoff
                        __encode__ => sub {
                            my $val = shift;
                            ( looks_like_number($val) && abs($val) >= 1 )
                              or SGX::Exception::User->throw( error =>
'Fold change must be a number <= -1.0 or >= 1.0'
                              );
                            return $val;
                        },
                    },
                },
                lookup => [
                    species      => [ sid => 'sid', { join_type => 'LEFT' } ],
                    probe_counts => [ pid => 'pid', { join_type => 'LEFT' } ],
                    locus_counts => [ pid => 'pid', { join_type => 'LEFT' } ]
                ]
            },
            species => {
                key       => [qw/sid/],
                view      => [qw/sname/],
                names     => [qw/sname/],
                resource  => 'species',
                item_name => 'species',
                meta      => {
                    sname => {
                        __createonly__ => 1,
                        label          => 'Species',
                        -size          => 35,
                        -maxlength     => 255,
                    }
                }
            },
            probe_counts => {
                table => 'probe',
                key   => [qw/pid/],
                view  => [qw/id_count sequence_count/],
                meta  => {
                    id_count => {
                        __sql__ => 'COUNT(rid)',
                        label   => 'Probe Count',
                        parser  => 'number'
                    },
                    sequence_count => {
                        __sql__ => 'COUNT(probe_sequence)',
                        label   => 'Probe Sequences',
                        parser  => 'number'
                    },
                },
                group_by => [qw/pid/]
            },
            locus_counts => {
                table => 'probe',
                key   => [qw/pid/],
                view  => [qw/locus_count/],
                meta  => {
                    locus_count => {
                        __sql__ => 'COUNT(location.rid)',
                        label   => 'Chr. Locations',
                        parser  => 'number'
                    },
                },
                group_by => [qw/pid/],
                join =>
                  [ location => [ rid => 'rid', { join_type => 'LEFT' } ] ]
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
        _readrow_tables =>
          [ 'study' => { heading => 'All Studies Assigned to this Platform' } ],

        _ProjectStudyExperiment =>
          SGX::Model::ProjectStudyExperiment->new( dbh => $self->{_dbh} ),

    );

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManagePlatforms
#       METHOD:  form_create_body
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:
#       THROWS:  no exceptions
#     COMMENTS:  overrides CRUD::form_create_body
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
      $q->h3( $self->format_title( 'create new ' . $self->get_item_name() ) ),

      # form
      $self->body_create_update_form(
        mode       => 'create',
        cgi_extras => { -enctype => 'multipart/form-data' }
      );
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

1;

__END__

=head1 NAME

SGX::ManageProjects

=head1 SYNOPSIS

=head1 DESCRIPTION
Module for managing platform table.

=head1 AUTHORS
Eugene Scherba
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut


