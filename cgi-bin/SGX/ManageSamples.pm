package SGX::ManageSamples;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use Scalar::Util qw/looks_like_number/;
use SGX::Util qw/car file_opts_html file_opts_columns coord2int/;
use SGX::Abstract::Exception ();
require Data::UUID;
use List::Util qw/sum/;
use SGX::Config qw/$YUI_BUILD_ROOT/;
#===  CLASS METHOD  ============================================================
#        CLASS:  ManageSamples
#       METHOD:  init
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Overrides CRUD::init
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub init {
    my ( $class, @param ) = @_;
    my $self = $class->SUPER::init(@param);

    $self->set_attributes(
        _permission_level => 'admin',
        _table_defs       => {
            'sample' => {
                item_name => 'sample',
                key       => [qw/smid/],

                # table key to the left, URI param to the right
                selectors => { smid => 'smid' },
                base => [qw/ smdesc lpid rsid tid/],
                view => [
                    qw/smdesc/
                ],
                resource => 'samples',
                names    => [qw/smdesc/],
                meta     => {

                    smdesc => {
                        label => 'Sample description',
                        -size => 30
                    },
					lpid => {
                        label  => 'Library Preparation',
						__type__     => 'popup_menu',
                        __optional__ => 1,
                        __tie__      => [ library_prep => 'lpid' ],
                        __extra_html__ =>
						'<p class="visible hint">...</p>'
                      
                    },
					rsid => {
                        label  => 'RNA category',
						__type__     => 'popup_menu',
                        __optional__ => 1,
                        __tie__      => [ source => 'rsid' ],
                        __extra_html__ =>
						'<p class="visible hint">...</p>'
                      
                    },
					tid => {
                        label  => 'Tissue',
						__type__     => 'popup_menu',
                        __optional__ => 1,
                        __tie__      => [ tissue => 'tid' ],
                        __extra_html__ =>
						'<p class="visible hint">...</p>'
                      
                    }

					
                },
				lookup => [
                    library_prep      => [ lpid => 'lpid', { join_type => 'LEFT' } ],
					source      => [ rsid => 'rsid', { join_type => 'LEFT' } ],
					tissue      => [ tid => 'tid', { join_type => 'LEFT' } ],                   
                ]
            },
			library_prep => {
                key       => [qw/lpid/],
                view      => [qw/lpname/],
                names     => [qw/lpname/],
                resource  => 'lprep',
                item_name => 'library_prep',
                meta      => {
                    lpname => {
                        __createonly__ => 1,
                        label          => 'Library Preparation',
                        -size          => 35,
                        -maxlength     => 255,
                    }
                }
            },
			source => {
                key       => [qw/rsid/],
                view      => [qw/rsname/],
                names     => [qw/rsname/],
                resource  => 'source',
                item_name => 'source',
                meta      => {
                    rsname => {
                        __createonly__ => 1,
                        label          => 'RNA category',
                        -size          => 35,
                        -maxlength     => 255,
                    }
                }
            },
			tissue => {
                key       => [qw/tid/],
                view      => [qw/tname/],
                names     => [qw/tname/],
                resource  => 'tissues',
                item_name => 'tissue',
                meta      => {
                    tname => {
                        __createonly__ => 1,
                        label          => 'Tissue',
                        -size          => 35,
                        -maxlength     => 255,
                    }
                }
            },
        },
        _default_table => 'sample',
    );

    return $self;
}


1;

__END__


=head1 NAME

SGX::ManageUsers

=head1 SYNOPSIS

=head1 DESCRIPTION
Module for managing user table.

=head1 AUTHORS
Eugene Scherba
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut



