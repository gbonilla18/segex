=head1 NAME

SGX::DropDownData

=head1 SYNOPSIS

=head1 DESCRIPTION
Object to populate drop down boxes.

=head1 AUTHORS
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::DropDownData;

use strict;
use warnings;

#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  new
#   PARAMETERS:  $dbh - database handle
#   			 $query - query statement text (with or without placeholders)
#   			 $includeBlank - boolean (allow blank value?)
#      RETURNS:  $self
#  DESCRIPTION:  This is the constructor
#       THROWS:  no exceptions
#     COMMENTS:  :NOTE:06/01/2011 03:32:37:es: preparing query once during
#     			 construction
#     SEE ALSO:  n/a
#===============================================================================
sub new {
	my $class = shift;
	my ($dbh, $query, $includeBlank) = @_;

	my $sth = $dbh->prepare($query) or die $dbh->errstr;
	my $self = {
		_dbh			=> $dbh,
		_sth			=> $sth,
		_includeBlank	=> $includeBlank,
		#_dropDownList	=> {}
	};

	bless $self, $class;
	return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  DropDownData
#       METHOD:  loadDropDownValues
#   PARAMETERS:  $self
#   			 @params - array of parameters to be used to fill placeholders
#   			 in the query statement
#      RETURNS:  reference to drop down data stored in key-value format (hash)
#  DESCRIPTION:  loads values by executing query
#       THROWS:  no exceptions
#     COMMENTS:  :NOTE:06/01/2011 03:31:28:es: allowing this method to be
#     			 executed more than once
#     SEE ALSO:  n/a
#===============================================================================
sub loadDropDownValues
{
	my ($self, @params) = @_;

	my $rc = $self->{_sth}->execute(@params)
		or die $self->{_dbh}->errstr;

	my @sthArray = sort {$a->[0] cmp $b->[0]} @{$self->{_sth}->fetchall_arrayref};

	my %tempLabel;

	#If the dropdown is to have blank values, add them.
	if($self->{_includeBlank})
	{
		$tempLabel{"0"} = "Please select a value.";
	}

	foreach (@sthArray)
	{
		$tempLabel{$_->[0]} = $_->[1];
	}

	$self->{_sth}->finish;

	return \%tempLabel;
}

1;
