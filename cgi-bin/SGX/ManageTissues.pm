package SGX::ManageTissues;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use SGX::Util qw/car/;
use SGX::Abstract::Exception ();

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageTissues
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
            'tissue' => {
                item_name => 'tissue',
                key       => [qw/tid/],

                # table key to the left, URI param to the right
                selectors => { uname => 'tname' },
                base => [qw/tname/],
                view => [
                    qw/tname/
                ],
                resource => 'tissues',
                names    => [qw/tname/],
                meta     => {

                    tid => {
                        label  => 'ID',
                        parser => 'number'
                    },
                    tname => {
                        label => 'Tissue name',
                        -size => 30
                    }
                },
            }
        },
        _default_table => 'tissue',
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



