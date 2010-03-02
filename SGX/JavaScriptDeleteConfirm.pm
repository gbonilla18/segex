=head1 NAME

SGX::JavaScriptDeleteConfirm

=head1 SYNOPSIS

=head1 DESCRIPTION
Object to draw JavaScript function for warning the user about deletes.

=head1 AUTHORS
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::JavaScriptDeleteConfirm;

use strict;
use warnings;

sub new {
	# This is the constructor
	my $class = shift;

	my $self = {
		_JavaScriptCode	=> 
				'
				<script type = "text/javascript">
					function deleteConfirmation()
					{
						var confirmReturn;
						confirmReturn = confirm("Are you sure you want to delete this item?");
						
						if(confirmReturn==true)
						{
							return confirm("Deleting this item will also delete all its children. Are you absolutely sure you want to delete this item?");
						}
						else
						{
							return false;
						}
					}
				</script>
				' 
	};

	bless $self, $class;
	return $self;
}

sub drawJavaScriptCode
{
	my $self			= shift;
	
	print $self->{_JavaScriptCode};
}

1;
