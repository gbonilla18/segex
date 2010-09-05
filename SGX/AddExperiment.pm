=head1 NAME

SGX::AddExperiment

=head1 SYNOPSIS

=head1 DESCRIPTION
Grouping of functions for adding experiments.

=head1 AUTHORS
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::AddExperiment;

use strict;
use warnings;

sub new {
	# This is the constructor
	my $class = shift;

	my $self = {
		_dbh		=> shift,
		_FormObject	=> shift,
		_LoadQuery	=> 'SELECT stid,description,pubmed,platform.pid,platform.pname,platform.species FROM study INNER JOIN platform ON platform.pid = study.pid AND platform.isAnnotated;',
		_ExperimentsQuery=>"	SELECT 	experiment.eid,
						study.pid,
						experiment.sample1,
						experiment.sample2,
						COUNT(1),
						ExperimentDescription,
						AdditionalInformation,
						study.description,
						platform.pname
					FROM	experiment 
					INNER JOIN study ON study.stid = experiment.stid
					INNER JOIN platform ON platform.pid = study.pid
					LEFT JOIN microarray ON microarray.eid = experiment.eid
					WHERE experiment.stid = {0}
					GROUP BY experiment.eid,
						study.pid,
						experiment.sample1,
						experiment.sample2,
						ExperimentDescription,
						AdditionalInformation
					ORDER BY experiment.eid ASC;
				   ",
		_ExpRecordCount	=> 0,
		_ExpRecords	=> '',
		_ExpFieldNames	=> '',
		_ExpData	=> '',
		_ExistingStudyQuery 		=> 'SELECT stid,description FROM study WHERE pid IN (SELECT pid FROM study WHERE stid = {0}) AND stid <> {0};',
		_ExistingExperimentQuery 	=> "SELECT	stid,eid,sample2,sample1 FROM experiment WHERE stid IN (SELECT stid FROM study WHERE pid IN (SELECT pid FROM study WHERE stid = {0})) AND stid <> {0} ORDER BY experiment.eid ASC;",	
		_RecordCount	=> 0,
		_Records	=> '',
		_FieldNames	=> '',
		_Data		=> '',
		_stid		=> '',
		_description	=> '',
		_pubmed		=> '',
		_pid		=> '',
		_platformList	=> {},
		_platformValue	=> ()
	};

	bless $self, $class;
	return $self;
}

sub drawAddExperimentMenu
{
	my $self = shift;

	print	'<br /><h2 name = "Add_Caption" id = "Add_Caption">Add New Experiment</h2>' . "\n";

	print $self->{_FormObject}->start_form(
		-method=>'POST',
		-action=>$self->{_FormObject}->url(-absolute=>1).'?a=manageExperiments&ManageAction=addNew&stid=' . $self->{_stid},
		-onsubmit=>'return validate_fields(this, [\'Sample1\',\'Sample2\',\'uploaded_data_file\']);'
	) .
	$self->{_FormObject}->p('In order to upload experiment data the file must be in a tab separated format and the columns be as follows.')
	.
	$self->{_FormObject}->p('<b>Reporter Name, Ratio, Fold Change, P-value, Intensity 1, Intensity 2</b>')
	.
	$self->{_FormObject}->p('Make sure the first row is the column headings and the second row starts the data.')
	.
	$self->{_FormObject}->dl(
		$self->{_FormObject}->dt('Sample 1:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'Sample1',-id=>'Sample1',-maxlength=>120)),
		$self->{_FormObject}->dt('Sample 2:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'Sample2',-id=>'Sample2',-maxlength=>120)),
		$self->{_FormObject}->dt('Experiment Description:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'ExperimentDescription',-id=>'ExperimentDescription',-maxlength=>1000)),
		$self->{_FormObject}->dt('Additional Information:'),
		$self->{_FormObject}->dd($self->{_FormObject}->textfield(-name=>'AdditionalInformation',-id=>'AdditionalInformation',-maxlength=>1000)),
		$self->{_FormObject}->dt("Data File to upload:"),
		$self->{_FormObject}->dd($self->{_FormObject}->filefield(-name=>'uploaded_data_file',-id=>'uploaded_data_file')),
		$self->{_FormObject}->dt('&nbsp;'),
		$self->{_FormObject}->dd($self->{_FormObject}->submit(-name=>'AddExperiment',-id=>'AddExperiment',-value=>'Add Experiment'),$self->{_FormObject}->span({-class=>'separator'},' / '))
	) .
	$self->{_FormObject}->end_form;

}

1;
