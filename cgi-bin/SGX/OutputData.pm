=head1 NAME

SGX::OutputData

=head1 SYNOPSIS

=head1 DESCRIPTION
Grouping of functions for dumping data.

=head1 AUTHORS
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::OutputData;

use strict;
use warnings;
use CGI::Carp qw/croak/;
use Data::Dumper;
use Switch;

sub new {
    # This is the constructor
    my $class = shift;

    my $ReportQuery = <<"END_ReportQuery";
SELECT CONCAT(study.description, ' - ', experiment.sample2, ' / ', experiment.sample1) AS Identity,
    probe.reporter,
    gene.accnum AS Transcript,
    gene.seqname AS Gene,
    microarray.ratio,
    microarray.foldchange,
    microarray.pvalue,
    microarray.intensity2,
    microarray.intensity1
FROM    experiment
INNER JOIN StudyExperiment USING(eid)
INNER JOIN Study USING(stid)
INNER JOIN microarray USING(eid)
INNER JOIN probe ON probe.rid = microarray.rid
INNER JOIN annotates ON annotates.rid = probe.rid
INNER JOIN gene ON gene.gid = annotates.gid
WHERE    experiment.eid IN (?)
ORDER BY experiment.eid

END_ReportQuery

    my $self = {
        _dbh        => shift,
        _FormObject    => shift,
        _js_dir        => shift,
        _ExistingStudyQuery         => 'SELECT stid,description,pid FROM study',
        _ExistingExperimentQuery     => 'SELECT stid,eid,sample2,sample1 FROM experiment RIGHT JOIN StudyExperiment USING(eid);',
        _ReportQuery            => $ReportQuery,
        _ExistingExperimentList        => {},
        _Data                => '',
        _FieldNames            => '',
        _SelectedExperiment        => ''
    };

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  OutputData
#       METHOD:  dispatch
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  executes appropriate method for the given action
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub dispatch
{
    my ( $self, $action ) = @_;

    $action = '' if not defined($action);
    switch ($action) {
        case 'runReport' {
            $self->loadFromForm();
            $self->loadReportData();
            $self->runReport();
            #print "<br />Record updated - Redirecting...<br />";
        }
        else {
            # default action: show form
            $self->showExperiments();
        }
    }
    return;
}

#Load the data from the submitted form.
sub loadFromForm
{
    my $self = shift;
    $self->{_eidList} = ($self->{_FormObject}->param('experiment_exist')) if defined($self->{_FormObject}->param('experiment_exist'));
    return;
}

sub loadReportData
{
    my $self = shift;
    
    $self->{_Records} = $self->{_dbh}->prepare($self->{_ReportQuery}) 
        or croak $self->{_dbh}->errstr;
    my $tempRecordCount = $self->{_Records}->execute($self->{_eidList})
        or croak $self->{_dbh}->errstr;

    $self->{_FieldNames}     = $self->{_Records}->{NAME};
    $self->{_Data}         = $self->{_Records}->fetchall_arrayref;
    return;
}

#######################################################################################
#PRINTING HTML AND JAVASCRIPT STUFF
#######################################################################################
#Draw the javascript and HTML for the experiment table.
sub showExperiments
{
    my $self = shift;
    my $error_string = "";

    print    '<font size="5">Output Data</font><br /><br />' . "\n";
    print    '<script src="' . $self->{_js_dir} . '/OutputData.js" type="text/javascript"></script>';
    print    "<script type=\"text/javascript\">\n";

    printJavaScriptRecordsForExistingDropDowns($self);

    print     "</script>\n";

    print    '<br /><h2 name = "Output_Caption" id = "Output_Caption">Select Items to output</h2>' . "\n";

    print $self->{_FormObject}->start_form(
        -method=>'POST',
        -name=>'AddExistingForm',
        -action=>$self->{_FormObject}->url(-absolute=>1).'?a=outputData&outputAction=runReport',
        -onsubmit=>'return validate_fields(this,"");'
    ) .
    $self->{_FormObject}->dl(
        $self->{_FormObject}->dt('Study : '),
        $self->{_FormObject}->dd($self->{_FormObject}->popup_menu(-name=>'study_exist', -id=>'study_exist',-onChange=>"populateSelectExistingExperiments(document.getElementById(\"experiment_exist\"),document.getElementById(\"study_exist\"));")),
        $self->{_FormObject}->dt('Experiment : '),
        $self->{_FormObject}->dd($self->{_FormObject}->popup_menu(-name=>'experiment_exist',-multiple=>'true', -id=>'experiment_exist')),
        $self->{_FormObject}->dt('&nbsp;'),
        $self->{_FormObject}->dd($self->{_FormObject}->submit(-name=>'RunReport',-id=>'RunReport',-value=>'Run Report'),$self->{_FormObject}->span({-class=>'separator'},' / ')
        )
    ) .
    $self->{_FormObject}->end_form;
    return;
}

##########################################################
#This prints the results table to a printable text screen.
sub printExportTable
{
    print <<"END_ExportTable";
function export_table(e) {
    var r = e.records;
    var bl = e.headers.length;
    var w = window.open("");
    var d = w.document.open("text/html");
    d.title = "Tab-Delimited Text";
    d.write("<pre>");
    for (var i=0, al = r.length; i < al; i++) 
    {
        for (var j=0; j < bl; j++) 
        {
            d.write(r[i][j] + "\\t");
        }
        d.write("\\n");
    }
    d.write("</pre>");
    d.close();
    w.focus();
}

END_ExportTable
    return;
}

sub printDrawResultsTableJS
{
    print <<"END_DrawResultsTableJS";
    var myDataSource         = new YAHOO.util.DataSource(OutputReport.records);
    myDataSource.responseType     = YAHOO.util.DataSource.TYPE_JSARRAY;
    myDataSource.responseSchema     = {fields: ["0","1","2","3","4","5","6","7","8"]};
    var myData_config         = {paginator: new YAHOO.widget.Paginator({rowsPerPage: 50})};
    var myDataTable         = new YAHOO.widget.DataTable("OutputTable", myColumnDefs, myDataSource, myData_config);

END_DrawResultsTableJS
    return;
}

sub printJSRecords
{
    my $self = shift;
    my $tempRecordList = '';

    #Loop through data and load into JavaScript array.
    foreach (@{$self->{_Data}}) 
    {
        foreach (@$_)
        {
            $_ = '' if !defined $_;
            $_ =~ s/"//g;    # strip all double quotes (JSON data are bracketed with double quotes)
        }
        #stid,description,pubmed,platform.pid,platform.pname,platform.species
        $tempRecordList .= '{0:"'.$_->[0].'",1:"'.$_->[1].'",2:"'.$_->[2].'",3:"'.$_->[3].'",4:"' . $_->[4] . '",5:"' . $_->[5] . '",6:"' . $_->[6] . '",7:"' . $_->[7] . '",8:"' . $_->[8] . '"},'. "\n";
    }
    $tempRecordList =~ s/,\s*$//;    # strip trailing comma

    return $tempRecordList;
}

sub printJSHeaders
{
    my $self = shift;
    my $tempHeaderList = '';

    #Loop through data and load into JavaScript array.
    foreach (@{$self->{_FieldNames}})
    {
        $tempHeaderList .= '"' . $_ . '",';
    }
    $tempHeaderList =~ s/,\s*$//;    # strip trailing comma

    return $tempHeaderList;


}

sub printTableInformation
{
    print <<"END_TableInformation";
        var myColumnDefs = [
        {key:"0", sortable:true, resizeable:true, label:"Study"},
        {key:"1", sortable:true, resizeable:true, label:"Reporter"},
        {key:"2", sortable:true, resizeable:true, label:"Transcript"},
        {key:"3", sortable:false, resizeable:true, label:"Gene"},
        {key:"4", sortable:false, resizeable:true, label:"Ratio"},
        {key:"5", sortable:false, resizeable:true, label:"Fold Change"},
        {key:"6", sortable:false, resizeable:true, label:"P value"},
        {key:"7", sortable:false, resizeable:true, label:"Intensity 2"},
        {key:"8", sortable:false, resizeable:true, label:"Intensity 1"}
        ];
END_TableInformation
    return;
}
##########################################################

sub printJavaScriptRecordsForExistingDropDowns
{
    my $self         = shift;

    my $studyQuery         = $self->{_ExistingStudyQuery};
    my $experimentQuery    = $self->{_ExistingExperimentQuery};

    my $tempRecords     = $self->{_dbh}->prepare($studyQuery) or croak $self->{_dbh}->errstr;
    my $tempRecordCount    = $tempRecords->execute or croak $self->{_dbh}->errstr;

    print    'Event.observe(window, "load", init);';
    print     "var study = {};";

    my $out = "";

    while (my @row = $tempRecords->fetchrow_array) {
        $out .= 'study['.$row[0]."] = {};\n";
        $out .= 'study['.$row[0].'][0] = \''.$row[1]."';\n"; # study description
        $out .= 'study['.$row[0]."][1] = {};\n";     # sample 1 name
        $out .= 'study['.$row[0]."][2] = {};\n";     # sample 2 name
        $out .= 'study['.$row[0].'][3] = \''.$row[2]."';\n"; # platform id
    }
    $tempRecords->finish;

    $tempRecords         = $self->{_dbh}->prepare($experimentQuery) or croak $self->{_dbh}->errstr;
    $tempRecordCount    = $tempRecords->execute or croak $self->{_dbh}->errstr;

    ### populate the Javascript hash with the content of the experiment recordset
    while (my @row = $tempRecords->fetchrow_array) {
        $out .= 'study['.$row[0].'][1]['.$row[1].'] = \''.$row[2]."';\n";
        $out .= 'study['.$row[0].'][2]['.$row[1].'] = \''.$row[3]."';\n";
    }
    $tempRecords->finish;

    print $out;
    print 'function init() {';
    print 'populateExistingStudy("study_exist");';
    print 'populateSelectExistingExperiments(document.getElementById("experiment_exist"),document.getElementById("study_exist"));';
    print '}';
    return;
}

#######################################################################################
sub runReport
{
    my $self = shift;

    my $records = printJSRecords($self);
    my $headers = printJSHeaders($self);

    my $JSOuputList = <<"END_JSOuputList";
var OutputReport = 
    {
        caption: "Showing all Experiments",
        records: [$records],
        headers: [$headers]
    };
END_JSOuputList

    print    '<h2 name = "caption" id="caption"></h2>' . "\n";
    print    '<div><a id="OutPut_astext" onClick = "export_table(OutputReport)">View as plain text</a></div>' . "\n";
    print    '<div id="OutputTable"></div>' . "\n";
    print    "<script type=\"text/javascript\">\n";
    print $JSOuputList;

    printTableInformation();
    printExportTable();    
    printDrawResultsTableJS();

    print     "</script>\n";
    return;
}

#######################################################################################

1;
