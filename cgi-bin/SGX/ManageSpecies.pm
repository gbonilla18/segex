package SGX::ManageSpecies;

use strict;
use warnings;

use base qw/SGX::Strategy::CRUD/;

use SGX::Abstract::Exception ();
use Digest::SHA1 qw/sha1_hex/;

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageUsers
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
            'species' => {
                item_name => 'species',
                key       => [qw/sid/],
                base      => [qw/sname/],
                view      => [qw/sname/],
                resource  => 'species',
                names     => [qw/sname/],
                meta      => {
                    sname => {
                        label => 'Species',
                        -size => 30
                    }
                }
            }
        },
        _default_table => 'species',
    );

    bless $self, $class;
    return $self;
}

1;

__END__


=head1 NAME

SGX::ManageSpecies

=head1 SYNOPSIS

=head1 DESCRIPTION
Moduel for managing species table.

=head1 AUTHORS
Eugene Scherba

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut


