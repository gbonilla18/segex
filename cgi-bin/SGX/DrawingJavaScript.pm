=head1 NAME

SGX::DrawingJavaScript

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 AUTHORS
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::DrawingJavaScript;

use strict;
use warnings;

sub new {
	# This is the constructor
	my $class = shift;

	my $self = {
		_postBackString	=> shift,
		_queryParameters=> shift
	};

	bless $self, $class;
	return $self;
}

sub printTextCellEditorCode
{
	my $self		= shift;

	my $textCellEditorTemplate = <<"END_textCellEditorTemplate";
	new YAHOO.widget.TextareaCellEditor
	(
		{
			disableBtns: false,
			asyncSubmitter: function(callback, newValue) 
			{ 
				var record = this.getRecord();
				if (this.value == newValue) 
				{ 
					callback(); 
				} 

				YAHOO.util.Connect.asyncRequest('POST',%s,
															{ 
																success:function(o) 
																{ 
																	if(o.status === 200) 
																	{
																		// HTTP 200 OK
																		callback(true, newValue); 
																	} 
																	else 
																	{ 
																		alert(o.statusText);
																		//callback();
																	} 
																}, 
																failure:function(o) 
																{ 
																	alert(o.statusText); 
																	callback(); 
																},
																scope:this 
															}, %s);
			}
		}
	)
END_textCellEditorTemplate

    $textCellEditorTemplate = sprintf(
        $textCellEditorTemplate,
        $self->{_postBackString},
        $self->{_queryParameters}
    );

	return $textCellEditorTemplate;
}

1;
