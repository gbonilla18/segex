=head1 NAME

SGX::ManageExperiments

=head1 SYNOPSIS

=head1 DESCRIPTION
Grouping of functions for managing experiments.

=head1 AUTHORS
Michael McDuffie

=head1 SEE ALSO


=head1 COPYRIGHT


=head1 LICENSE

Artistic License 2.0
http://www.opensource.org/licenses/artistic-license-2.0.php

=cut

package SGX::ManageExperiments;

use strict;
use warnings;

use SGX::DropDownData;
use SGX::DrawingJavaScript;
use SGX::JavaScriptDeleteConfirm;
use Data::Dumper;
use Switch;

sub new {
    # This is the constructor
    my $class = shift;

    my @deleteStatementList;

    push @deleteStatementList,'DELETE FROM microarray WHERE eid = {0};';
    push @deleteStatementList,'DELETE FROM StudyExperiment WHERE eid = {0};';
    push @deleteStatementList,'DELETE FROM experiment WHERE eid = {0};';

    my $self = {
        _dbh        => shift,
        _cgi    => shift,
        _js_dir        => shift,
        _LoadQuery    => "    SELECT     experiment.eid,
                        study.pid,
                        experiment.sample1,
                        experiment.sample2,
                        COUNT(1),
                        ExperimentDescription,
                        AdditionalInformation,
                        IFNULL(study.description,'Unassigned Study'),
                        platform.pname,
                        IFNULL(study.stid,0)
                    FROM    experiment 
                    LEFT JOIN StudyExperiment ON experiment.eid = StudyExperiment.eid
                    LEFT JOIN study ON study.stid = StudyExperiment.stid
                    LEFT JOIN platform ON platform.pid = study.pid
                    LEFT JOIN microarray ON microarray.eid = experiment.eid
                    WHERE study.stid = {0}
                    GROUP BY experiment.eid,
                        study.pid,
                        experiment.sample1,
                        experiment.sample2,
                        ExperimentDescription,
                        AdditionalInformation,
                        IFNULL(study.stid,0)
                    ORDER BY experiment.eid ASC;
                   ",
        _LoadUnassignedQuery        => "    SELECT     experiment.eid,
                        study.pid,
                        experiment.sample1,
                        experiment.sample2,
                        COUNT(1),
                        ExperimentDescription,
                        AdditionalInformation,
                        IFNULL(study.description,'Unassigned Study'),
                        IFNULL(platform.pname,IFNULL(probe_platform.pname,'Unable to find platform.')),
                        IFNULL(study.stid,0)
                    FROM    experiment 
                    LEFT JOIN StudyExperiment ON experiment.eid = StudyExperiment.eid
                    LEFT JOIN study ON study.stid = StudyExperiment.stid
                    LEFT JOIN platform     ON platform.pid = study.pid                    
                    LEFT JOIN microarray     ON microarray.eid = experiment.eid
                    LEFT JOIN probe     ON probe.rid = microarray.rid
                    LEFT JOIN platform probe_platform ON probe_platform.pid = probe.pid
                    WHERE (probe.pid = {1} OR {1} = 0)
                    AND StudyExperiment.stid IS NULL
                    GROUP BY experiment.eid,
                        study.pid,
                        experiment.sample1,
                        experiment.sample2,
                        ExperimentDescription,
                        AdditionalInformation,
                        IFNULL(study.stid,0)
                    ORDER BY experiment.eid ASC;
                   ",
        _LoadAllExperimentsQuery    => "    SELECT     experiment.eid,
                        study.pid,
                        experiment.sample1,
                        experiment.sample2,
                        COUNT(1),
                        ExperimentDescription,
                        AdditionalInformation,
                        IFNULL(study.description,'Unassigned Study'),
                        IFNULL(platform.pname,IFNULL(probe_platform.pname,'Unable to find platform.')),
                        IFNULL(study.stid,0)
                    FROM    experiment 
                    LEFT JOIN StudyExperiment ON experiment.eid = StudyExperiment.eid
                    LEFT JOIN study ON study.stid = StudyExperiment.stid
                    LEFT JOIN platform     ON platform.pid = study.pid                    
                    LEFT JOIN microarray     ON microarray.eid = experiment.eid
                    LEFT JOIN probe     ON probe.rid = microarray.rid
                    LEFT JOIN platform probe_platform ON probe_platform.pid = probe.pid
                    WHERE (probe.pid = {1} OR {1} = 0)
                    GROUP BY experiment.eid,
                        study.pid,
                        experiment.sample1,
                        experiment.sample2,
                        ExperimentDescription,
                        AdditionalInformation,
                        IFNULL(study.stid,0)
                    ORDER BY experiment.eid ASC;
                   ",
        _LoadSingleQuery=> "SELECT    eid,
                        sample1,
                        sample2,
                        ExperimentDescription,
                        AdditionalInformation
                    FROM    experiment 
                    NATURAL JOIN StudyExperiment
                    NATURAL JOIN study
                    WHERE    experiment.eid = {0}
                    GROUP BY experiment.eid,
                        experiment.sample1,
                        experiment.sample2,
                        ExperimentDescription,
                        AdditionalInformation
                    ORDER BY experiment.eid ASC;
                ",                   
        
        _UpdateQuery    => 'UPDATE experiment SET ExperimentDescription = \'{0}\', AdditionalInformation = \'{1}\', sample1 = \'{2}\', sample2 = \'{3}\' WHERE eid = {4};',
        _DeleteQuery    => \@deleteStatementList,
        _RemoveQuery    => 'DELETE FROM StudyExperiment WHERE stid = {0} AND eid = {1};',
        _StudyQuery    => 'SELECT 0,\'All Studies\' UNION SELECT -1,\'Unassigned Study\' UNION SELECT stid,description FROM study ORDER BY 1;',
        _StudyPlatformQuery    => 'SELECT pid,stid,description FROM study ORDER BY 1,2;',
        _PlatformQuery            => "SELECT 0,\'All Platforms\' UNION SELECT pid,CONCAT(pname ,\' \\\\ \',species) FROM platform ORDER BY 1;",
        _PlatformList        => '',
        _PlatformValues        => '',
        _RecordCount    => 0,
        _Records    => '',
        _FieldNames    => '',
        _Data        => undef,
        _stid        => '',
        _description    => '',
        _pubmed        => '',
        _pid        => '',
        _eid        => '',
        _studyList    => {},
        #_studyValue    => (),
        _ExistingExperimentList    => {},
        #_ExistingExperimentValue => (),
        _sample1    => '',
        _sample2    => '',
        _ExperimentDescription => '',
        _AdditionalInformation => '',
        _SelectedStudy    => 0,
        _SelectExperiment => 0
    };

    bless $self, $class;
    return $self;
}

#===  CLASS METHOD  ============================================================
#        CLASS:  ManageExperiments
#       METHOD:  dispatch
#   PARAMETERS:  ????
#      RETURNS:  ????
#  DESCRIPTION:  executes code appropriate for the given action
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub dispatch
{
    my ( $self, $action ) = @_;

    $action = '' if not defined($action);
    switch($action)
    {
        case 'addNew' {
            $self->loadFromForm();
            $self->addNewExperiment();
            print "<br />Record updated - Redirecting...<br />";
        }
        case 'delete' {
            $self->loadFromForm();
            $self->deleteExperiment();
            print "<br />Record removed - Redirecting...<br />";
        }
        case 'load' {
            my $javaScriptDeleteConfirm = SGX::JavaScriptDeleteConfirm->new();
            $javaScriptDeleteConfirm->drawJavaScriptCode();

            $self->loadFromForm();
            $self->loadAllExperimentsFromStudy();
            $self->loadStudyData();
            $self->loadPlatformData();
            $self->showExperiments();
        }
        else {
            # default action: show experiments form
            my $javaScriptDeleteConfirm = SGX::JavaScriptDeleteConfirm->new();
            $javaScriptDeleteConfirm->drawJavaScriptCode();

            $self->loadStudyData();
            $self->loadPlatformData();
            $self->showExperiments();
        }
    }
    if($action eq 'delete' || $action eq 'addNew')
    {
        my $redirectSite   = $self->{_cgi}->url(-absolute=>1)."?a=manageExperiments&ManageAction=load&stid=$self->{_stid}&pid=$self->{_pid}";
        my $redirectString = "<script type=\"text/javascript\">window.location = \"$redirectSite\"</script>";
        print "$redirectString";
    }
    return;
}
#Loacs all expriments from a specific study.
sub loadAllExperimentsFromStudy
{
    my $self     = shift;
    my $loadQuery     = "";

    if($self->{_stid} == 0)
    {
        $loadQuery = $self->{_LoadAllExperimentsQuery};
    }
    elsif($self->{_stid} == -1)
    {
        $loadQuery = $self->{_LoadUnassignedQuery};
    }
    else
    {
        $loadQuery = $self->{_LoadQuery};
    }
            
    $loadQuery     =~ s/\{0\}/\Q$self->{_stid}\E/g;
    $loadQuery     =~ s/\{1\}/\Q$self->{_pid}\E/g;
    
    $self->{_Records}         = $self->{_dbh}->prepare($loadQuery) or die $self->{_dbh}->errstr;
    $self->{_RecordCount}    = $self->{_Records}->execute or die $self->{_dbh}->errstr;
    $self->{_FieldNames}     = $self->{_Records}->{NAME};
    $self->{_Data}             = $self->{_Records}->fetchall_arrayref;
    $self->{_Records}->finish;
}

#Loads a single platform from the database based on the URL parameter.
sub loadSingleExperiment
{
    #Grab object and id from URL.
    my $self     = shift;
    $self->{_eid}     = $self->{_cgi}->url_param('id');
    $self->{_stid}    = ($self->{_cgi}->url_param('stid')) if defined($self->{_cgi}->url_param('stid'));
    
    #Use a regex to replace the ID in the query to load a single platform.
    my $singleItemQuery     = $self->{_LoadSingleQuery};
    $singleItemQuery     =~ s/\{0\}/\Q$self->{_eid}\E/g;

    #Run the SPROC and get the data into the object.
    $self->{_Records}     = $self->{_dbh}->prepare($singleItemQuery) or die $self->{_dbh}->errstr;
    $self->{_RecordCount}    = $self->{_Records}->execute or die $self->{_dbh}->errstr;
    $self->{_Data}         = $self->{_Records}->fetchall_arrayref;

    foreach (@{$self->{_Data}})
    {
        $self->{_sample1}        = $_->[1];
        $self->{_sample2}        = $_->[2];
        $self->{_ExperimentDescription}    = $_->[3];
        $self->{_AdditionalInformation}    = $_->[4];
    }

    $self->{_Records}->finish;
}

#Loads information into the object that is used to create the study dropdown.
sub loadStudyData
{
    my $self = shift;

    my $studyDropDown = SGX::DropDownData->new(
        $self->{_dbh},
        $self->{_StudyQuery}
    );

    $self->{_studyList} = $studyDropDown->loadDropDownValues();
}

#Loads information into the object that is used to create the study dropdown.
sub loadPlatformData
{
    my $self = shift;

    my $platformDropDown = SGX::DropDownData->new(
        $self->{_dbh},
        $self->{_PlatformQuery}
    );

    $self->{_platformList}  = $platformDropDown->loadDropDownValues();
}

#Load the data from the submitted form.
sub loadFromForm
{
    my $self = shift;

    $self->{_pid}            = ($self->{_cgi}->param('platform_addNew'))            if defined($self->{_cgi}->param('platform_addNew'));    
    $self->{_pid}            = ($self->{_cgi}->url_param('pid'))                     if defined($self->{_cgi}->url_param('pid'));
    $self->{_pid}            = ($self->{_cgi}->param('platform_load'))            if defined($self->{_cgi}->param('platform_load'));
    $self->{_eid}            = ($self->{_cgi}->param('eid'))                         if defined($self->{_cgi}->param('eid'));
    $self->{_stid}            = ($self->{_cgi}->param('stid'))                        if defined($self->{_cgi}->param('stid'));
    $self->{_stid}            = ($self->{_cgi}->url_param('stid'))                    if defined($self->{_cgi}->url_param('stid'));    
    $self->{_eid}            = ($self->{_cgi}->url_param('id'))                     if defined($self->{_cgi}->url_param('id'));
    $self->{_selectedstid}    = ($self->{_cgi}->url_param('selectedstid'))         if defined($self->{_cgi}->url_param('selectedstid'));
    $self->{_selectedpid}    = ($self->{_cgi}->url_param('selectedpid'))             if defined($self->{_cgi}->url_param('selectedpid'));
}

#######################################################################################
#PRINTING HTML AND JAVASCRIPT STUFF
#######################################################################################
#Draw the javascript and HTML for the experiment table.
sub showExperiments
{
    my $self = shift;
    my $error_string = "";

    #This block of logic controls our double dropdowns for platform/study.
    print    '<script src="' . $self->{_js_dir} . '/PlatformStudySelection.js" type="text/javascript"></script>';
    print    '<script src="' . $self->{_js_dir} . '/AJAX.js" type="text/javascript"></script>';
    print    "<script type=\"text/javascript\">\n";
    printJavaScriptRecordsForFilterDropDowns($self);    
    print     "</script>\n";        
    
    print    '<font size="5">Manage Experiments</font><br /><br />' . "\n";

    #Load the study dropdown to choose which experiments to load into table.
    print $self->{_cgi}->start_form(
        -method=>'POST',
        -action=>$self->{_cgi}->url(-absolute=>1).'?a=manageExperiments&ManageAction=load',
        -onsubmit=>'return validate_fields(this, [\'study\']);'
    ) .
    $self->{_cgi}->dl(
        $self->{_cgi}->dt('Platform:'),
        $self->{_cgi}->dd($self->{_cgi}->popup_menu(
                -name=>'platform_load',
                -id=>'platform_load',
                -values=>[keys %{$self->{_platformList}}],
                -labels=>$self->{_platformList},
                -default=>$self->{_pid},
                onChange=>"populateSelectFilterStudy(document.getElementById(\"stid\"),document.getElementById(\"platform_load\"));"
        )),
        $self->{_cgi}->dt('Study:'),
        $self->{_cgi}->dd($self->{_cgi}->popup_menu(
                -name=>'stid',
                -id=>'stid',
                -values=>[keys %{$self->{_studyList}}],
                -labels=>$self->{_studyList},
                -default=>$self->{_stid}
        )),
        $self->{_cgi}->dt('&nbsp;'),
        $self->{_cgi}->dd( $self->{_cgi}->submit(
                -name=>'SelectStudy',
                -id=>'SelectStudy',
                -value=>'Load'),
            $self->{_cgi}->span({-class=>'separator'}
        ))
    ) .
    $self->{_cgi}->end_form;
    
    #If we have selected and loaded an experiment, load the table.
    if(defined ($self->{_Data}))
    {
        my $JSStudyList = "var JSStudyList = 
        {
            caption: \"Showing all Experiments\",
            records: [". printJSRecords($self) ."],
            headers: [". printJSHeaders($self) . "]
        };" . "\n";

        print    '<h2 name = "caption" id="caption"></h2>' . "\n";
        print    '<div><a id="StudyTable_astext" onClick = "export_table(JSStudyList)">View as plain text</a></div>' . "\n";
        print    '<div id="StudyTable"></div>' . "\n";

        print    "<script type=\"text/javascript\">\n";
        print $JSStudyList;

        printTableInformation($self->{_FieldNames},$self->{_cgi});
        printExportTable();    
        printDrawResultsTableJS();
        
        #Run this once when we first load to make sure dropdown is loaded correctly.
        print "populateSelectFilterStudy(document.getElementById(\"stid\"),document.getElementById(\"platform_load\"));";
        
        #Now we need to re-select the current StudyID, if we have one.
        if(defined($self->{_stid}))
        {
            print "selectStudy(document.getElementById(\"stid\")," . $self->{_stid} . ");";
        }
        
        print     "</script>\n";

        my $addExperimentInfo = new SGX::AddExperiment($self->{_dbh},$self->{_cgi},'manageExperiments');
        $addExperimentInfo->loadFromForm();
        $addExperimentInfo->loadPlatformData();
        $addExperimentInfo->drawAddExperimentMenu();
    }
}

#This prints the results table to a printable text screen.
sub printExportTable
{

print '
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
            d.write(r[i][j] + "\t");
        }
        d.write("\n");
    }
    d.write("</pre>");
    d.close();
    w.focus();
}

';

}

sub printDrawResultsTableJS
{
    print    '
    var myDataSource         = new YAHOO.util.DataSource(JSStudyList.records);
    myDataSource.responseType     = YAHOO.util.DataSource.TYPE_JSARRAY;
    myDataSource.responseSchema     = {fields: ["0","1","2","3","4","5","6","7","8","9"]};
    var myData_config         = {paginator: new YAHOO.widget.Paginator({rowsPerPage: 50})};
    var myDataTable         = new YAHOO.widget.DataTable("StudyTable", myColumnDefs, myDataSource, myData_config);' . "\n" . '
    
    // Set up editing flow 
    var highlightEditableCell = function(oArgs) { 
        var elCell = oArgs.target; 
        if(YAHOO.util.Dom.hasClass(elCell, "yui-dt-editable")) { 
        this.highlightCell(elCell); 
        } 
    }; 
    
    myDataTable.subscribe("cellMouseoverEvent", highlightEditableCell); 
    myDataTable.subscribe("cellMouseoutEvent", myDataTable.onEventUnhighlightCell); 
    myDataTable.subscribe("cellClickEvent", myDataTable.onEventShowCellEditor);
    ';    
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
        #eid,pid,sample1,sample2,count(1),ExperimentDescription,AdditionalInfo,Study Description,platform name,stid
        $tempRecordList .= '{0:"'.$_->[2].'",1:"'.$_->[3].'",2:"'.$_->[4].'",3:"'.$_->[0].'",4:"' . $_->[0] . '",5:"' . $_->[5] . '",6:"' . $_->[6] . '",7:"' . $_->[7] . '",8:"' . $_->[8] . '",9:"' . $_->[9] . '",10:"' . $_->[1] . '"},';
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
    my $arrayRef     = shift;
    my @names     = @$arrayRef;
    my $CGIRef     = shift;
    my $deleteURL     = $CGIRef->url(absolute=>1).'?a=manageExperiments&ManageAction=delete&id=';
    my $editURL    = $CGIRef->url(absolute=>1).'?a=manageExperiments&ManageAction=edit&stid=&id=';
    
    #This is the code to use the AJAXy update box for description..
    my $postBackURLDescr            = '"'.$CGIRef->url(-absolute=>1).'?a=updateCell"';
    my $postBackQueryParametersDesc = '"type=experiment&desc=" + escape(newValue) + "&add=" + encodeURI(record.getData("6")) + "&eid=" + encodeURI(record.getData("3"))';
    my $textCellEditorObjectDescr    = new SGX::DrawingJavaScript($postBackURLDescr,$postBackQueryParametersDesc);

    #This is the code to use the AJAXy update box for Additional Info..
    my $postBackURLAdd                 = '"'.$CGIRef->url(-absolute=>1).'?a=updateCell"';
    my $postBackQueryParametersAdd     = '"type=experiment&desc=" + encodeURI(record.getData("5")) + "&add=" + escape(newValue) + "&eid=" + encodeURI(record.getData("3"))';
    my $textCellEditorObjectAdd        = new SGX::DrawingJavaScript($postBackURLAdd,$postBackQueryParametersAdd);

    #This is the code to use the AJAXy update box for Sample1..
    my $postBackURLSample1                = '"'.$CGIRef->url(-absolute=>1).'?a=updateCell"';
    my $postBackQueryParametersSample1     = '"type=experimentSamples&S1=" + escape(newValue) + "&S2=" + encodeURI(record.getData("1")) + "&eid=" + encodeURI(record.getData("3"))';
    my $textCellEditorObjectSample1        = new SGX::DrawingJavaScript($postBackURLSample1,$postBackQueryParametersSample1);

    #This is the code to use the AJAXy update box for Sample2..
    my $postBackURLSample2                = '"'.$CGIRef->url(-absolute=>1).'?a=updateCell"';
    my $postBackQueryParametersSample2     = '"type=experimentSamples&S1=" + encodeURI(record.getData("0")) + "&S2=" + escape(newValue) + "&eid=" + encodeURI(record.getData("3"))';
    my $textCellEditorObjectSample2        = new SGX::DrawingJavaScript($postBackURLSample2,$postBackQueryParametersSample2);
    
    print    '
    
        YAHOO.widget.DataTable.Formatter.formatExperimentDeleteLink = function(elCell, oRecord, oColumn, oData) 
        {
            if(oRecord.getData("9") == 0)
            {
                elCell.innerHTML = "<a title=\"Delete\" onClick = \"return deleteConfirmation();\" target=\"_self\" href=\"' . $deleteURL . '" + oData + "&stid=" + encodeURI(oRecord.getData("9")) + "&selectedpid=" + document.forms[0].platform_load[document.forms[0].platform_load.selectedIndex].value + "&selectedstid=" + document.forms[0].stid[document.forms[0].stid.selectedIndex].value + "\">Delete</a>";
            }
            else
            {
                elCell.innerHTML = "<a title=\"Remove\" onClick = \"return removeExperimentConfirmation();\" target=\"_self\" href=\"' . $deleteURL . '" + oData + "&stid=" + encodeURI(oRecord.getData("9")) + "&selectedpid=" + document.forms[0].platform_load[document.forms[0].platform_load.selectedIndex].value + "&selectedstid=" + document.forms[0].stid[document.forms[0].stid.selectedIndex].value + "\">Remove</a>";
            }
        }

        YAHOO.util.Dom.get("caption").innerHTML = JSStudyList.caption;
        var myColumnDefs = [
        {key:"3", sortable:true, resizeable:true, label:"Experiment Number"},
        {key:"0", sortable:true, resizeable:true, label:"Sample 1",editor:' . $textCellEditorObjectSample1->printTextCellEditorCode() . '},
        {key:"1", sortable:true, resizeable:true, label:"Sample 2",editor:' . $textCellEditorObjectSample2->printTextCellEditorCode() . '},
        {key:"2", sortable:true, resizeable:true, label:"Probe Count"},
        {key:"5", sortable:false, resizeable:true, label:"Experiment Description",editor:' . $textCellEditorObjectDescr->printTextCellEditorCode() . '},
        {key:"6", sortable:false, resizeable:true, label:"Additional Information",editor:' . $textCellEditorObjectAdd->printTextCellEditorCode() . '},
        {key:"3", sortable:false, resizeable:true, label:"Delete\/Remove Experiment",formatter:"formatExperimentDeleteLink"},
        {key:"7", sortable:true, resizeable:true, label:"Study Description"},
        {key:"8", sortable:true, resizeable:true, label:"Platform Name"}
        ];' . "\n";
}


sub printJavaScriptRecordsForFilterDropDowns
{
    my $self         = shift;

    my $studyQuery         = $self->{_StudyPlatformQuery};

    my $tempRecords     = $self->{_dbh}->prepare($studyQuery) or die $self->{_dbh}->errstr;
    my $tempRecordCount    = $tempRecords->execute or die $self->{_dbh}->errstr;

    print     "var studies = {};";

    my $out = "";

    while (my @row = $tempRecords->fetchrow_array) {
        $out .= 'studies['.$row[1]."] = {};\n"; # Study ID
        $out .= 'studies['.$row[1].'][0] = \''.$row[2]."';\n"; #Study Description
        $out .= 'studies['.$row[1].'][1] = \''.$row[0]."';\n"; #PID
    }
    $tempRecords->finish;
    
    print $out;
    
}



#######################################################################################


#######################################################################################
#ADD/DELETE/EDIT METHODS
#######################################################################################
sub deleteExperiment
{
    my $self = shift;

    #If our study = 0, we delete, otherwise we just remove it from the study.
    if($self->{_stid} ne "0")
    {
        my $deleteStatement     = $self->{_RemoveQuery};
        $deleteStatement     =~ s/\{0\}/\Q$self->{_stid}\E/;
        $deleteStatement     =~ s/\{1\}/\Q$self->{_eid}\E/;
        
        $self->{_dbh}->do($deleteStatement) or die $self->{_dbh}->errstr;        
    }
    else
    {
        foreach (@{$self->{_DeleteQuery}})
        {
            my $deleteStatement     = $_;
            $deleteStatement     =~ s/\{0\}/\Q$self->{_eid}\E/;
            
            $self->{_dbh}->do($deleteStatement) or die $self->{_dbh}->errstr;
        }
    }
    
    #After deleting the experiments we change the current STID to whatever was selected in the dropdown before we deleted.
    $self->{_stid} = $self->{_selectedstid};
    $self->{_pid} = $self->{_selectedpid};
}

sub addNewExperiment
{
    my $self = shift;
    
    my $addExperimentInfo = new SGX::AddExperiment($self->{_dbh},$self->{_cgi},'manageExperiments');
    $addExperimentInfo->loadFromForm();
    $addExperimentInfo->addNewExperiment();
    
    $self->{_stid} = "0";
}

#######################################################################################

1;
