
=head1 NAME

SGX::DropDownData

=head1 SYNOPSIS

=head1 DESCRIPTION
Object to populate drop down boxes.

=head1 AUTHORS
Michael McDuffie
Eugene Scherba

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::DropDownData;

use strict;
use warnings;

#use Data::Dumper;
use CGI::Carp qw/croak/;
use Tie::IxHash;

#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  new
#   PARAMETERS:  0) $self  - object instance
#                1) $dbh   - database handle
#                2) $query - SQL query string (with or without placeholders)
#      RETURNS:  $self
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  :NOTE:06/01/2011 03:32:37:es: preparing query once during
#                  construction
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my ($class, $dbh, $query) = @_;

    my $sth = $dbh->prepare($query)
      or croak $dbh->errstr;

    my $self = {
        _dbh => $dbh,
        _sth => $sth,
        _tied => undef,
        _hash => {},
    };

    # Tying the hash using Tie::IxHash module allows us to keep hash
    # keys ordered 
    $self->{_tied} = tie(%{$self->{_hash}}, 'Tie::IxHash');

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  clone
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  This is a copy constructor
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub clone {
    my $self = shift;

    my $clone = {
        _dbh => $self->{_dbh},
        _sth => $self->{_sth},
        _tied => undef,
        _hash => {},
    };

    # Tying the hash using Tie::IxHash module allows us to keep hash
    # keys ordered 
    $clone->{_tied} = tie(%{$clone->{_hash}}, 'Tie::IxHash');

    # now fill the new hash
    $clone->{_tied}->Push(%{$self->{_hash}});

    bless $clone, ref $self;
    return $clone;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  loadDropDownValues
#   PARAMETERS:  $self
#                @params - array of parameters to be used to fill placeholders
#                in the query statement
#      RETURNS:  reference to drop down data stored in key-value format (hash)
#  DESCRIPTION:  loads values by executing query
#       THROWS:  no exceptions
#     COMMENTS:  :NOTE:06/01/2011 03:31:28:es: allowing this method to be
#                 executed more than once
#     SEE ALSO:  http://search.cpan.org/~chorny/Tie-IxHash-1.22/lib/Tie/IxHash.pm
#===============================================================================
sub loadDropDownValues {
    my ( $self, @params ) = @_;

    my $rc = $self->{_sth}->execute(@params)
      or croak $self->{_dbh}->errstr;

    my @sthArray = @{ $self->{_sth}->fetchall_arrayref };

    $self->{_sth}->finish;

    my $hash_ref = $self->{_hash};
    foreach (@sthArray) {
        my $k = $_->[0];
        croak "Conflicting key '$k' in output hash"
          if exists $hash_ref->{$k};
        $hash_ref->{$k} = $_->[1];
    }

    return $hash_ref;
}


#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  Push
#   PARAMETERS:  0) $self
#                1) list of key-value pairs, e.g. Push('0' => 'All Values', ...)
#      RETURNS:  Same as Tie::IxHash::Push
#  DESCRIPTION:  Add key-value array to hash using Tie::IxHash object
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub Push
{
    my ($self, @rest) = @_;
    return $self->{_tied}->Push(@rest);
}

#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  Unshift
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  Wraps the Unshift method in Tie::IxHash
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub Unshift
{
    my ($self, @rest) = @_;
    return $self->{_tied}->Unshift(@rest);
}

1;
