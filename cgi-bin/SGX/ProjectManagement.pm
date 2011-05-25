=head1 NAME

SGX::ProjectManagement

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

package SGX::ProjectManagement;

use strict;
use warnings;
use Switch;

use Data::Dumper;
use SGX::DropDownData;

sub new {
	# This is the constructor
	my $class = shift;

	my $self = {
		_dbh			=> shift,
		_FormObject		=> shift,
		_ProjectDropdownQuery	=> "SELECT ProjectID,ProjectName FROM Projects",
		_ProjectList		=> {},
		_ProjectValue 		=> ()
		};

	bless $self, $class;
	return $self;
}

sub loadProjectData
{
	my $self		= shift;
print $self->{_ProjectDropdownQuery};
	my $projectDropDown	= new SGX::DropDownData($self->{_dbh},$self->{_ProjectDropdownQuery},0);

	$projectDropDown->loadDropDownValues();

	$self->{_ProjectList} 	= $projectDropDown->{_dropDownList};
	$self->{_ProjectQuery} 	= $projectDropDown->{_dropDownValue};
}

#######################################################################################
#This is the area that gets included on each page that shows which project we have selected.
#######################################################################################
sub drawProjectInfoHeader
{
	my $self = shift;

	$self->{_FormObject}->div({-id=>'projectInfo'},
		$self->{_FormObject}->ul(
			$self->{_FormObject}->li("<font size='5'>Current Project : SEGEX</font>"),
			$self->{_FormObject}->li($self->{_FormObject}->a({-href=>$self->{_FormObject}->url(-absolute=>1).'?a=changeProject',-title=>'Change Project'},'Click here to change current project.'))
		)
	);

}
#######################################################################################

#######################################################################################
#.
#######################################################################################
sub drawChangeProjectScreen
{
	my $self = shift;

	#Load the study dropdown to choose which experiments to load into table.
	print $self->{_FormObject}->start_form(
		-method=>'POST',
		-action=>$self->{_FormObject}->url(-absolute=>1).'?a=changeProject&projectAction=change'
	) .
	$self->{_FormObject}->dl
		(
		$self->{_FormObject}->dt('Project:'),
		$self->{_FormObject}->dd($self->{_FormObject}->popup_menu(-name=>'project_load',-id=>'project_load',-values=>\@{$self->{_projectValue}},-labels=>\%{$self->{_projectList}})
		)	
	) .
	$self->{_FormObject}->end_form;

}
#######################################################################################

1;

