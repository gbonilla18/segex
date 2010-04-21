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

sub new {
	# This is the constructor
	my $class = shift;

	my $self = {
		_dbh		=> shift,
		_LoadQuery	=> shift,
		_includeBlank	=> shift,
		_dropDownList	=> {},
		_dropDownValue	=> ()
	};

	bless $self, $class;
	return $self;
}

sub loadDropDownValues
{
	my $self		= shift;
	my $dataQuery		= shift;

	#Temp variables used to create the hash and array for the dropdown.
	my %tempLabel;
	my @tempValue;

	#Variables used to temporarily hold the database information.
	my $tempRecords		= '';
	my $tempRecordCount	= '';
	my @tempRecordsArray	= '';

	$tempRecords 		= $self->{_dbh}->prepare($self->{_LoadQuery}) or die $self->{_dbh}->errstr;
	$tempRecordCount	= $tempRecords->execute or die $self->{_dbh}->errstr;

	#Grab all platforms and build the hash and array for drop down.
	@tempRecordsArray	= @{$tempRecords->fetchall_arrayref};

	#If the dropdown is to have blank values, add them.
	if($self->{_includeBlank})
	{
		$tempLabel{"0"}="Please select a value.";
		push(@tempValue,"0");
	}

	foreach (sort {$a->[0] cmp $b->[0]} @tempRecordsArray)
	{
		$tempLabel{$_->[0]} = $_->[1];
		push(@tempValue,$_->[0]);
	}

	#Assign members variables reference to the hash and array.
	$self->{_dropDownList} 		= \%tempLabel;
	$self->{_dropDownValue}		= \@tempValue;
	
	#Finish with database.
	$tempRecords->finish;	
}

1;
