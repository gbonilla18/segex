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
		_includeBlank	=> $includeBlank,
		_sth			=> $sth,
		_dropDownList	=> {},
		_dropDownValue	=> ()
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
#      RETURNS:  ????
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

	#Grab all platforms and build the hash and array for drop down.
	my @sthArray	= @{$self->{_sth}->fetchall_arrayref};

	#Temp variables used to create the hash and array for the dropdown.
	my %tempLabel;
	my @tempValue;

	#If the dropdown is to have blank values, add them.
	if($self->{_includeBlank})
	{
		$tempLabel{"0"}="Please select a value.";
		push(@tempValue,"0");
	}

	foreach (sort {$a->[0] cmp $b->[0]} @sthArray)
	{
		$tempLabel{$_->[0]} = $_->[1];
		push(@tempValue,$_->[0]);
	}

	#Assign members variables reference to the hash and array.
	$self->{_dropDownList} 		= \%tempLabel;
	$self->{_dropDownValue}		= \@tempValue;
	
	#Finish with database.
	$self->{_sth}->finish;
}

1;
