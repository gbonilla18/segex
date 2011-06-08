
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

use CGI::Carp qw/croak/;
use Data::Dumper;

#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  new
#   PARAMETERS:  0) $self  - object instance
#                1) $dbh   - database handle
#                2) $query - SQL query string (with or without placeholders)
#                3) %args  - variable number of optional named arguments, e.g.
#                   extras => {-1 => 'Unassigned', 0 => 'All'}
#
#                   Description of these optional arguments:
#                   * extras   - key-value pair for the "blank" row. If
#                                     present, a "blank" row will be added.
#      RETURNS:  $self
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  :NOTE:06/01/2011 03:32:37:es: preparing query once during
#                  construction
#     SEE ALSO:  n/a
#===============================================================================
sub new {
    my $class = shift;
    my $dbh   = shift;
    my $query = shift;

    my $sth = $dbh->prepare($query)
      or croak $dbh->errstr;

    my $self = {
        _dbh => $dbh,
        _sth => $sth,
        @_    # not unpacking @_: constructor doesn't know about arguments to
              # loadDropDownValues()
    };

    bless $self, $class;
    return $self;
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
#     SEE ALSO:  n/a
#===============================================================================
sub loadDropDownValues {
    my ( $self, @params ) = @_;

    my $rc = $self->{_sth}->execute(@params)
      or croak $self->{_dbh}->errstr;

    my @sthArray = @{ $self->{_sth}->fetchall_arrayref };

    my %tempLabel;

    foreach (@sthArray) {
        my $k = $_->[0];
        croak "Conflicting key '$k' in output hash"
          if exists $tempLabel{$k};
        $tempLabel{$k} = $_->[1];
    }

    # If the dropdown is to have extra values, merge the hash referenced by 
    # {extras} with the output hash. If the {extras} has not been assigned, the
    # loop will be skipped, so no additional # check for definedness is needed.
    #
    while ( my ( $k, $v ) = each( %{ $self->{extras} } ) ) {
        croak "Conflicting key '$k' in output hash"
          if exists $tempLabel{$k};
        $tempLabel{$k} = $v;
    }

    $self->{_sth}->finish;

    return \%tempLabel;
}

1;
