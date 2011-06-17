=head1 NAME

SGX::FindProbes

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

package SGX::FindProbes;

use strict;
use warnings;

use base qw/Exporter/;

use Switch;
use CGI::Carp;
use Tie::IxHash;
use Data::Dumper;
use File::Basename;
use JSON::XS;
use File::Temp qw/tempfile/;

use SGX::Util qw/trim/;
use SGX::Debug qw/assert/;

our @EXPORT_OK =
  qw/getform_findProbes/;

sub new {
    # This is the constructor
    my $class = shift;

    my $self = {
        _dbh            => shift,
        _cgi        => shift,
        _SearchType        => shift,
        _SearchText        => shift,
        _ProbeRecords        => '',
        _ProbeCount        => 0,
        _ProbeColNames        => '',        
        _ProbeData        => '',
        _RecordsPlatform    => '',
        _ProbeHash        => '',
        _RowCountAll        => 0,
        _ProbeExperimentHash=> '',
        _Data            => '',        
        _eids            => '',
        _ExperimentRec        => '',
        _ExperimentCount    => 0,
        _ExperimentData        => '',
        _FullExperimentRec        => '',
        _FullExperimentCount    => 0,
        _FullExperimentData        => '',        
        _InsideTableQuery     => '',
        _SearchItems        => '',
        _PlatformInfoQuery    => "SELECT pid, pname FROM platform",
        _PlatformInfoHash    => '',
        _ProbeQuery         => '',
        _ProbeReporterQuery        => "
                SELECT DISTINCT rid
                FROM (
                    SELECT gid
                    FROM ({0}) AS g1
                    INNER JOIN gene ON (g1.accnum=gene.accnum OR g1.seqname=gene.seqname)
                    GROUP BY gid
                ) as g0
                INNER JOIN annotates USING(gid)
                INNER JOIN probe USING(rid)",

        _ExperimentListHash     => '',
        _ExperimentStudyListHash    => '',        
        _TempTableID            => '',
        _ExperimentNameListHash     => '',
        _ExperimentDataQuery     => "
                    select     experiment.eid, 
                        microarray.ratio,
                        microarray.foldchange,
                        microarray.pvalue,
                        IFNULL(microarray.intensity1,0),
                        IFNULL(microarray.intensity2,0),
                        CONCAT(
                            study.description, ': ', 
                            experiment.sample2, '/', experiment.sample1
                        ) AS 'Name',
                        study.stid,
                        study.pid
                    FROM microarray 
                    INNER JOIN experiment USING(eid)
                    INNER JOIN StudyExperiment USING(eid)
                    INNER JOIN study USING(stid)
                    WHERE rid={0}
                    ORDER BY experiment.eid ASC
                    ",
        _ReporterList        => undef
    };

    #Reporter,Accession Number, Gene Name, Probe Sequence, {Ratio,FC,P-Val,Intensity1,Intensity2}    
    
    bless $self, $class;
    return $self;
}
#######################################################################################

sub set_SearchItems
{
    my ($self, $mode) = @_;

    # 'text' must always be set
    my $text = $self->{_cgi}->param('text') 
        or croak 'You did not specify what to search for';

    #This will be the array that holds all the splitted items.
    my @textSplit;    
    #If we find a comma, split on that, otherwise we split on new lines.
    if ($text =~ m/,/) {
        #Split the input on commas.    
        @textSplit = split(/\,/,trim($text));
    } else {
        #Split the input on the new line.    
        @textSplit = split(/\r\n/,$text);
    }
    
    #Get the count of how many search terms were found.
    my $searchesFound = @textSplit;
    my $qtext;
    if($searchesFound < 2) {
        my $match = (defined($self->{_cgi}->param('match'))) 
                    ? $self->{_cgi}->param('match') 
                    : 'full';
        switch ($match) {
            case 'full'        { $qtext = '^'.$textSplit[0].'$' }
            case 'prefix'    { $qtext = '^'.$textSplit[0] }
            case 'part'        { $qtext = $textSplit[0] } 
            else            { croak "Invalid match value $match" }
        }
    } else {
        if ($mode == 0) {
            $qtext = join('|',
                map { '^' . trim($_) . '$' } @textSplit);
        } else {
            $qtext = '^' . join('|',
                map { trim($_) } @textSplit) . '$';
        }
    }
    $self->{_SearchItems} = $qtext;
}
#######################################################################################
#This is the code that generates part of the SQL statement.
#######################################################################################
sub createInsideTableQuery
{
    my $self = shift;
    $self->set_SearchItems(0);

    # 'type' must always be set
    my $type = $self->{_cgi}->param('type') 
        or croak "You did not specify where to search";

    $self->build_InsideTableQuery($type);
}
#######################################################################################

#######################################################################################
#This is the code that generates part of the SQL statement (From a file instead of a list of genes).
#######################################################################################
sub createInsideTableQueryFromFile
{
    #Get the probe object.
    my $self = shift;

    #This is the type of search.
    # 'type' must always be set
    my $type = $self->{_cgi}->param('type') 
        or croak "You did not specify where to search";
    
    #This is the file that was uploaded.
    my $uploadedFile = $self->{_cgi}->upload('gene_file')
        or croak "No file specified";

    #We need to get the list from the user into SQL, We need to do some temp table/file trickery for this.
    #Get time to make our unique ID.
    my $time          = time();
    #Make idea with the time and ID of the running application.
    my $processID     = $time. '_' . getppid();
    #Regex to strip quotes.
    my $regex_strip_quotes = qr/^("?)(.*)\1$/;
    
    #Store the temp Table id so we can drop the table later.
    $self->{_TempTableID} = $processID;
    
    #We need to create this output directory.
    my $tmp = File::Temp->new();
    #This is where we put the temp file we will import.
    my $outputFileName = $tmp->filename();
    #Open file we are writing to server.
    open(OUTPUTTOSERVER,">$outputFileName");
    #Each line is an item to search on.
    while ( <$uploadedFile> )
    {
        #Grab the current line (Or Whole file if file is using Mac line endings).
        #Replace all carriage returns, or carriage returns and line feed with just a line feed.
        $_ =~ s/(\r\n|\r)/\n/g;
        print OUTPUTTOSERVER $_;
    }
    close(OUTPUTTOSERVER);

    #--------------------------------------------
    #Now get the temp file into a temp MYSQL table.

    #Command to create temp table.
    my $createTableStatement = "CREATE TABLE $processID (searchField VARCHAR(200))";

    #This is the mysql command to suck in the file.
    my $inputStatement = <<"END_inputStatement";
LOAD DATA LOCAL INFILE ?
INTO TABLE $processID
LINES TERMINATED BY '\n'
(searchField);
END_inputStatement
    #--------------------------------------------

    #When using the file from the user we join on the temp table we create.
    #---------------------------------------------
    #Run the command to create the temp table.
    $self->{_dbh}->do($createTableStatement)
        or croak $self->{_dbh}->errstr;

    #Run the command to suck in the data.
    $self->{_dbh}->do($inputStatement, undef, $outputFileName)
        or croak $self->{_dbh}->errstr;
    #--------------------------------------------

    $self->build_InsideTableQuery($type, tmp_table => $processID);
    $self->{_SearchItems} = undef;
}
#######################################################################################

#######################################################################################
#This gets set in the index.cgi page based on input parameters.
#######################################################################################
#sub setInsideTableQuery
#{
#    my $self        = shift;
#    my $tableQuery     = shift;
#    
#    $self->{_InsideTableQuery} = $tableQuery;
#}
#######################################################################################

#######################################################################################
#Return the inside table query.
#######################################################################################
sub getInsideTableQuery
{
    my $self        = shift;
        
    return $self->{_InsideTableQuery};
}
#######################################################################################

#######################################################################################
#Return the search terms used in the query.
#######################################################################################
sub getQueryTerms
{
    my $self        = shift;

    return $self->{_SearchItems};
}
#######################################################################################

#######################################################################################
#Fill a hash with platform name and ID so we print it for the seperators.
#######################################################################################
sub fillPlatformHash
{
    my $self        = shift;

    my $tempPlatformQuery     = $self->{_PlatformInfoQuery};
    my $platformRecords    = $self->{_dbh}->prepare($tempPlatformQuery)     or croak $self->{_dbh}->errstr;
    my $platformCount     = $platformRecords->execute()                     or croak $self->{_dbh}->errstr;    
    my $platformData    = $platformRecords->fetchall_arrayref;

    $platformRecords->finish;

    #Initialize our hash.
    $self->{_PlatformInfoHash} = {};

    #For each probe we get add an item to the hash. 
    foreach(@{$platformData})
    {
        ${$self->{_PlatformInfoHash}{$_->[0]}} = $_->[1];
    }
}
#######################################################################################

#######################################################################################
#Get a list of the probes (Only the reporter field).
#######################################################################################
sub loadProbeReporterData
{
    my ($self, $qtext) = @_;
    
    my $probeQuery                = $self->{_ProbeReporterQuery};
    
    $probeQuery                 =~ s/\{0\}/\Q$self->{_InsideTableQuery}\E/;
    $probeQuery                 =~ s/\\//g;

    $self->{_ProbeRecords}    = $self->{_dbh}->prepare($probeQuery)
        or croak $self->{_dbh}->errstr;
    $self->{_ProbeCount}    = $self->{_ProbeRecords}->execute()
        or croak $self->{_dbh}->errstr;    
    $self->{_ProbeColNames} = @{$self->{_ProbeRecords}->{NAME}};
    $self->{_Data}            = $self->{_ProbeRecords}->fetchall_arrayref;
    
    $self->{_ProbeRecords}->finish;
    
    $self->{_ProbeHash}     = {};
    
    my $DataCount            = @{$self->{_Data}};
    
    # For the situation where we created a temp table for the user input, 
    # we need to drop that temp table. This is the command to drop the temp table.
    my $dropStatement = "DROP TABLE " . $self->{_TempTableID} . ";";    
    
    #Run the command to drop the temp table.
    $self->{_dbh}->do($dropStatement) or croak $self->{_dbh}->errstr;
    
    if($DataCount < 1)
    {
        print $self->{_cgi}->header(-type=>'text/html', -cookie=>\@SGX::Cookie::cookies);
        print "No records found! Please click back on your browser and search again!";
        exit;
    }
    
    #foreach (@{$self->{_Data}}) {
    #    foreach (@$_) {
    #        $_ = '' if !defined $_;
    #        $_ =~ s/"//g;
    #    }
    #    $self->{_ReporterList} .= "'$_->[0]',";
    #}    
    ##Trim trailing comma off.
    #$self->{_ReporterList} =~ s/\,$//;    

    my $dbh = $self->{_dbh};
    $self->{_ReporterList} = join(',',
        map { $_->[0] } @{$self->{_Data}});
}
#######################################################################################


#######################################################################################
#Get a list of the probes here so that we can get all experiment data for each probe in another query.
#######################################################################################
sub loadProbeData
{
    my $self                = shift;
    my $qtext                = shift;
    
    my $probeQuery                = $self->{_ProbeQuery};
    
    $self->{_ProbeRecords}    = $self->{_dbh}->prepare($probeQuery)
        or croak $self->{_dbh}->errstr;
    $self->{_ProbeCount}    = $self->{_ProbeRecords}->execute($qtext)
        or croak $self->{_dbh}->errstr;    
    $self->{_ProbeColNames} = @{$self->{_ProbeRecords}->{NAME}};
    $self->{_Data}            = $self->{_ProbeRecords}->fetchall_arrayref;
    
    $self->{_ProbeRecords}->finish;
    
    $self->{_ProbeHash}     = {};
    
    my $DataCount            = @{$self->{_Data}};
    
    if($DataCount < 1)
    {
        print $self->{_cgi}->header(-type=>'text/html', -cookie=>\@SGX::Cookie::cookies);
        print "No records found! Please click back on your browser and search again!";
        exit;
    }
    
    foreach (@{$self->{_Data}}) 
    {
        foreach (@$_)
        {
            $_ = '' if !defined $_;
            $_ =~ s/"//g;
        }

        $self->{_ProbeHash}->{$_->[0]} = [@$_[1..7]];

        #[$_->[1], $_->[2], $_->[3], $_->[4], $_->[5], $_->[6]];
        #"$_->[1]|$_->[2]|$_->[3]|$_->[4]|$_->[5]|$GOField|";
    }    
}
#######################################################################################

#######################################################################################
#For each probe in the list get all the experiment data.
#######################################################################################
sub loadExperimentData
{
    my $self                         = shift;
    my $experimentDataString        = '';
    my $transform                    = '';
    my $sql_trans                    = '';
    
    $self->{_ProbeExperimentHash}        = {};
    $self->{_ExperimentListHash}        = {};
    $self->{_ExperimentStudyListHash}    = {};
    $self->{_ExperimentNameListHash}    = {};
    
    #Grab the format for the output from the form.
    $transform     = ($self->{_cgi}->param('trans'))     if defined($self->{_cgi}->param('trans'));
    
    #Build SQL statement based on desired output type.
    switch ($transform) 
    {
        case 'fold'
        {
            $sql_trans = 'if(foldchange>0,foldchange-1,foldchange+1)';
        }
        case 'ln'
        {
            $sql_trans = 'if(foldchange>0, log2(foldchange), log2(-1/foldchange))';
        }
    }    

    #while (my ($key, $splitPlatformID) = each %{$self->{_ProbeHash}})
    foreach my $key (keys %{$self->{_ProbeHash}})
    {
        my $tempReportQuery = $self->{_ExperimentDataQuery};

        $tempReportQuery                 =~ s/\{0\}/\Q$key\E/;
        $tempReportQuery                 =~ s/\{1\}/\Q$sql_trans\E/;
        $tempReportQuery                 =~ s/\\//g;

        $self->{_ExperimentRec}         = $self->{_dbh}->prepare($tempReportQuery)     or croak $self->{_dbh}->errstr;
        $self->{_ExperimentCount}         = $self->{_ExperimentRec}->execute()         or croak $self->{_dbh}->errstr;    
        $self->{_ExperimentData}        = $self->{_ExperimentRec}->fetchall_arrayref;
        $self->{_ExperimentRec}->finish;
        
        #We use a temp hash that gets added to the _ProbeExperimentHash.
        my %tempHash;
        
        #Extract the PID from the string in the hash.
        #We need this platform ID to use later on.
        #my $currentPID = $splitPlatformID->[0];
        
        #For each experiment we get, stash the results in a string 
        foreach(@{$self->{_ExperimentData}})
        {
            #This is a | seperated string with all the experiment info.
            $experimentDataString = $_->[1] . '|' . $_->[2] . '|' . $_->[3] . '|' . $_->[4] . '|' . $_->[5];

            #Add this experiment to the hash which will have all the experiments and their data for a given reporter.
            $tempHash{$_->[0]} = $experimentDataString;

            #Keep a hash of EID and PID.
            ${$self->{_ExperimentListHash}{$_->[0]}} = $_->[8];

            #Keep a hash of EID and STID.
            ${$self->{_ExperimentStudyListHash}{$_->[0] . '|' . $_->[7]}} = 1;
            
            #Keep a hash of experiment names and EID.            
            ${$self->{_ExperimentNameListHash}{$_->[0]}} = $_->[6];
            
        }

        #Add the hash of experiment data to the hash of reporters.
        ${$self->{_ProbeExperimentHash}}{$_} = \%tempHash;

    }
    
}
#######################################################################################

#######################################################################################
sub printFindProbeToScreen
{
        my $self        = shift;
        my $caption         = sprintf("Found %d probe", $self->{_ProbeCount}) .(($self->{_ProbeCount} != 1) ? 's' : '')." annotated with $self->{_SearchType} groups matching '$self->{_SearchText}' ($self->{_SearchType}s grouped by gene symbol or transcript accession number)";
        my $trans         = (defined($self->{_cgi}->param('trans'))) ? $self->{_cgi}->param('trans') : 'fold';
        my $speciesColumn    = 4;
        
        my $out .= "
        var probelist = {
        caption: \"$caption\",
        records: [
        ";

        my @names = $self->{_ProbeColNames};    # cache the field name array

        my $data = $self->{_Data};

        # data are sent as a JSON object plus Javascript code (at the moment)
        foreach (sort {$a->[3] cmp $b->[3]} @$data) 
        {
            foreach (@$_) 
            {
                $_ = '' if !defined $_;
                $_ =~ s/"//g;
            }

            my $currentPID = $_->[1];
            
            $out .= '{0:"'.${$self->{_PlatformInfoHash}{$currentPID}}.'",1:"'.$_->[0].'",2:"'.$_->[2].'",3:"'.$_->[3].'",4:"'.$_->[4].'",5:"'.$_->[5].'",6:"'.$_->[6].'",7:"'.$_->[7].'",8:"'.$_->[8].'",9:"'.$_->[9].'"';
            $out .= "},\n";
        }
        $out =~ s/,\s*$//;    # strip trailing comma

        my $tableOut = '';

        $out .= '
    ]}

    function export_table(e) {
        var r = this.records;
        var bl = this.headers.length;
        var w = window.open("");
        var d = w.document.open("text/html");
        d.title = "Tab-Delimited Text";
        d.write("<pre>");
        for (var i=0, al = r.length; i < al; i++) {
            for (var j=0; j < bl; j++) {
                d.write(r[i][j] + "\t");
            }
            d.write("\n");
        }
        d.write("</pre>");
        d.close();
        w.focus();
    }

    YAHOO.util.Event.addListener("probetable_astext", "click", export_table, probelist, true);
    YAHOO.util.Event.addListener(window, "load", function() {
        ';
        if (defined($self->{_cgi}->param('graph'))) {
            $out .= 'var graph_content = "";
        var graph_ul = YAHOO.util.Dom.get("graphs");';
        }
        $out .= '
        YAHOO.util.Dom.get("caption").innerHTML = probelist.caption;

        YAHOO.widget.DataTable.Formatter.formatProbe = function(elCell, oRecord, oColumn, oData) {
            var i = oRecord.getCount();
            ';
            if (defined($self->{_cgi}->param('graph'))) {
                $out .= 'graph_content += "<li id=\"reporter_" + i + "\"><object type=\"image/svg+xml\" width=\"555\" height=\"880\" data=\"./graph.cgi?reporter=" + oData + "&trans='.$trans.'\"><embed src=\"./graph.cgi?reporter=" + oData + "&trans='.$trans.'\" width=\"555\" height=\"880\" /></object></li>";
            elCell.innerHTML = "<div id=\"container" + i + "\"><a title=\"Show differental expression graph\" href=\"#reporter_" + i + "\">" + oData + "</a></div>";';
            } else {
                $out .= 'elCell.innerHTML = "<div id=\"container" + i + "\"><a title=\"Show differental expression graph\" id=\"show" + i + "\">" + oData + "</a></div>";';
            }
        $out .= '
        }
        YAHOO.widget.DataTable.Formatter.formatTranscript = function(elCell, oRecord, oColumn, oData) {
            var a = oData.split(/ *, */);
            var out = "";
            for (var i=0, al=a.length; i < al; i++) {
                var b = a[i];
                if (b.match(/^ENS[A-Z]{4}\d{11}/i)) {
                    out += "<a title=\"Search Ensembl for " + b + "\" target=\"_blank\" href=\"http://www.ensembl.org/Search/Summary?species=all;q=" + b + "\">" + b + "</a>, ";
                } else {
                    out += "<a title=\"Search NCBI Nucleotide for " + b + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=Nucleotide&term=" + oRecord.getData("' . $speciesColumn . '") + "[ORGN]+AND+" + b + "[NACC]\">" + b + "</a>, ";
                }
            }
            elCell.innerHTML = out.replace(/,\s*$/, "");
        }
        YAHOO.widget.DataTable.Formatter.formatGene = function(elCell, oRecord, oColumn, oData) {
            if (oData.match(/^ENS[A-Z]{4}\d{11}/i)) {
                elCell.innerHTML = "<a title=\"Search Ensembl for " + oData + "\" target=\"_blank\" href=\"http://www.ensembl.org/Search/Summary?species=all;q=" + oData + "\">" + oData + "</a>";
            } else {
                elCell.innerHTML = "<a title=\"Search NCBI Gene for " + oData + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=gene&term=" + oRecord.getData("' . $speciesColumn . '") + "[ORGN]+AND+" + oData + "\">" + oData + "</a>";
            }
        }
        YAHOO.widget.DataTable.Formatter.formatExperiment = function(elCell, oRecord, oColumn, oData) {
            elCell.innerHTML = "<a title=\"View Experiment Data\" target=\"_blank\" href=\"?a=getTFS&eid=" + oRecord.getData("6") + "&rev=0&fc=" + oRecord.getData("9") + "&pval=" + oRecord.getData("8") + "&opts=2\">" + oData + "</a>";
        }
        YAHOO.widget.DataTable.Formatter.formatSequence = function(elCell, oRecord, oColumn, oData) {
            elCell.innerHTML = "<a href=\"http://genome.ucsc.edu/cgi-bin/hgBlat?userSeq=" + oData + "&type=DNA&org=" + oRecord.getData("' . $speciesColumn . '") + "\" title=\"UCSC BLAT on " + oRecord.getData("' . $speciesColumn . '") + " DNA\" target=\"_blank\">" + oData + "</a>";
        }
        var myColumnDefs = [
            {key:"0", sortable:true, resizeable:true, label:"Platform"},
            {key:"1", sortable:true, resizeable:true, label:"Reporter ID", formatter:"formatProbe"},
            {key:"2", sortable:true, resizeable:true, label:"Accession Number", formatter:"formatTranscript"}, 
            {key:"3", sortable:true, resizeable:true, label:"Gene Name", formatter:"formatGene"},
            {key:"4", sortable:true, resizeable:true, label:"Probe Sequence"},
            {key:"5", sortable:true, resizeable:true, label:"Experiment Number",formatter:"formatExperiment"}];

        var myDataSource = new YAHOO.util.DataSource(probelist.records);
        myDataSource.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
        myDataSource.responseSchema = {
            fields: ["0","1","2","3","4","5","6","7","8","9"]
        };
        var myData_config = {
            paginator: new YAHOO.widget.Paginator({
                rowsPerPage: 50 
            })
        };

        var myDataTable = new YAHOO.widget.DataTable("probetable", myColumnDefs, myDataSource, myData_config);

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

        var nodes = YAHOO.util.Selector.query("#probetable tr td.yui-dt-col-0 a");
        var nl = nodes.length;

        // Ideally, would want to use a "pre-formatter" event to clear graph_content
        // TODO: fix the fact that when cells are updated via cell editor, the graphs are rebuilt unnecessarily.
        myDataTable.doBeforeSortColumn = function(oColumn, sSortDir) {
            graph_content = "";
            return true;
        };
        myDataTable.doBeforePaginatorChange = function(oPaginatorState) {
            graph_content = "";
            return true;
        };
        myDataTable.subscribe("renderEvent", function () {
        ';

        if (defined($self->{_cgi}->param('graph'))) 
        {
            $out .= '
            graph_ul.innerHTML = graph_content;
            ';

        } else {
            $out .=
        '
            // if the line below is moved to window.load closure,
            // panels will no longer show up after sorting
            var manager = new YAHOO.widget.OverlayManager();
            var myEvent = YAHOO.util.Event;
            var i;
            var imgFile;
            for (i = 0; i < nl; i++) {
                myEvent.addListener("show" + i, "click", function () {
                    var index = this.getAttribute("id").substring(4);
                    var panel_old = manager.find("panel" + index);

                    if (panel_old === null) {
                        imgFile = this.innerHTML;    // replaced ".text" with ".innerHTML" because of IE problem
                        var panel =  new YAHOO.widget.Panel("panel" + index, { close:true, visible:true, draggable:true, constraintoviewport:false, context:["container" + index, "tl", "br"] } );
                        panel.setHeader(imgFile);
                        panel.setBody("<object type=\"image/svg+xml\" width=\"555\" height=\"880\" data=\"./graph.cgi?reporter=" + imgFile + "&trans='.$trans.'\"><embed src=\"./graph.cgi?reporter=" + imgFile + "&trans='.$trans.'\" width=\"555\" height=\"880\" /></object>");
                        manager.register(panel);
                        panel.render("container" + index);
                        // panel.show is unnecessary here because visible:true is set
                    } else {
                        panel_old.show();
                    }
                }, nodes[i], true);
            }
        '};
        $out .= '
        });

        return {
            oDS: myDataSource,
            oDT: myDataTable
        };
    });
    ';
    $out;

}
#######################################################################################

#######################################################################################
#Print the data from the hashes into a CSV file.
#######################################################################################
sub printFindProbeCSV
{
    my $self                     = shift;
    my $currentPID                = 0;

    #Clear our headers so all we get back is the CSV file.
    print $self->{_cgi}->header(-type=>'text/csv',-attachment => 'results.csv', -cookie=>\@SGX::Cookie::cookies);

    #Print a line to tell us what report this is.
    print "Find Probes Report," . localtime() . "\n\n";    
    
    #Sort the hash so the PID's are together.
    foreach my $key (sort {$self->{_ProbeHash}{$a} cmp $self->{_ProbeHash}{$b} } keys %{$self->{_ProbeHash}})
    {

        #This lets us know if we should print the headers.
        my $printHeaders            = 0;    
    
        #Extract the PID from the string in the hash.
        my $splitPlatformID = $self->{_ProbeHash}->{$key};
    
        #If this is the first PID then grab it from the hash. If the hash is different from the current one put in a seperator.
        if($currentPID == 0)
        {
            $currentPID = $splitPlatformID->[1];
            $printHeaders = 1;
        }
        elsif($splitPlatformID->[1] != $currentPID)
        {
            print "\n";

            $currentPID = $splitPlatformID->[1];
            $printHeaders = 1;
        }
        
        if($printHeaders==1)
        {
            #Print the name of the current platform.
            print "\"${$self->{_PlatformInfoHash}{$currentPID}}\"";
            print "\n";
            print "Experiment Number,Study Description, Experiment Heading,Experiment Description\n";
            
            #String representing the list of experiment names.
            my $experimentList = ",,,,,,,";
            
            #Temporarily hold the string we are to output so we can trim the trailing ",".
            my $outLine = "";

            #Loop through the list of experiments and print out the ones for this platform.
            foreach my $value (sort{$a <=> $b} keys %{$self->{_ExperimentListHash}})
            {
                if(${$self->{_ExperimentListHash}{$value}} == $currentPID)
                {
                    my $currentLine = "";
                
                    $currentLine .= $value . ",";
                    $currentLine .= $self->{_FullExperimentData}->{$value}->{description} . ",";
                    $currentLine .= $self->{_FullExperimentData}->{$value}->{experimentHeading} . ",";
                    $currentLine .= $self->{_FullExperimentData}->{$value}->{ExperimentDescription};
                    
                    #Current experiment name.
                    my $currentExperimentName = ${$self->{_ExperimentNameListHash}{$value}};
                    $currentExperimentName =~ s/\,//g;
                    
                    #Experiment Number,Study Description, Experiment Heading,Experiment Description
                    print "$currentLine\n";
                    
                    #The list of experiments goes with the Ratio line for each block of 5 columns.
                    $experimentList .= "$value : $currentExperimentName,,,,,,";                    
                    
                    #Form the line that goes above the data. Each experiment gets a set of 5 columns.
                    $outLine .= ",$value:Ratio,$value:FC,$value:P-Val,$value:Intensity1,$value:Intensity2,";                    
                }
            }
            
            #Trim trailing comma off experiment list.
            $experimentList =~ s/\,$//;
            
            #Trim trailing comma off data row header.
            $outLine =~ s/\,$//;
            
            #Print list of experiments.
            print $experimentList;
            print "\n";

            #Print header line for probe rows.
            print "Reporter ID,Accession Number, Gene Name,Probe Sequence,Gene Description,Gene Ontology,";
            
            print "$outLine\n";
                    
        }
        
        #This is the line of data we will output. We need to trim the trailing comma.
        my $outRow = '';        
        
        #Print the probe ID.
        #$outRow .= "$key,";
        $outRow .= $splitPlatformID->[1] . ',';

        #Trim any commas out of the Gene Name.
        my $geneName     = $splitPlatformID->[3];
        $geneName         =~ s/\,//g;
        
        my $geneDescription = $splitPlatformID->[5];
        $geneDescription    =~ s/\,//g;

        my $geneOntology = $splitPlatformID->[6];
        $geneOntology    =~ s/\,//g;
        
        #Print the probe info. (Accession,Gene Name, Probe Sequence, Gene description, Gene Ontology).
        $outRow .= "$splitPlatformID->[2],$geneName,$splitPlatformID->[4],$geneDescription,$geneOntology,,";
                
        #For this reporter we print out a column for all the experiments that we have data for.
        foreach my $EIDvalue (sort{$a <=> $b} keys %{$self->{_ExperimentListHash}})
        {
            #Only try to see the EID's for platform $currentPID.
            if(${$self->{_ExperimentListHash}{$EIDvalue}} == $currentPID)
            {
                my %currentProbeExperimentHash;
                %currentProbeExperimentHash = %{$self->{_ProbeExperimentHash}->{$key}};
                            
                #Split the output string.
                my @outputColumns = split(/\|/,$currentProbeExperimentHash{$EIDvalue});
                
                #Add all the experiment data to the output string.
                foreach(@outputColumns)
                {
                    $outRow .= "$_,";
                }
                
                $outRow .= ",";
            }
        }
        
        print "$outRow\n";
    }
}
#######################################################################################

#######################################################################################
#Loop through the list of Reporters we are filtering on and create a list.
#######################################################################################
sub setProbeList
{
    my $self                     = shift;
    #$self->{_ReporterList}        = '';
    #foreach(keys %{$self->{_ProbeHash}}) {
    #    $self->{_ReporterList} .= "'$_',";
    #}
    ##Trim trailing comma off.
    #$self->{_ReporterList} =~ s/\,$//;    

    my $dbh = $self->{_dbh};    
    $self->{_ReporterList} = join(',', keys %{$self->{_ProbeHash}});
}
#######################################################################################

#######################################################################################
#Loop through the list of Reporters we are filtering on and create a list.
#######################################################################################
sub getProbeList
{
    my $self = shift;
    return $self->{_ReporterList};
}
#######################################################################################
#Loop through the list of experiments we are displaying and get the information on each. We need eid and stid for each.
#######################################################################################
sub getFullExperimentData
{
    my $self                     = shift;
    my $query_titles            = "";
    
    foreach my $currentRecord (keys %{$self->{_ExperimentStudyListHash}})
    {    
    
        my @IDSplit = split(/\|/,$currentRecord);
        
        my $currentEID = $IDSplit[0];    
        my $currentSTID = $IDSplit[1];
    
        $query_titles .= " SELECT     experiment.eid, 
                                    CONCAT(study.description, ': ', experiment.sample1, ' / ', experiment.sample2) AS title, 
                                    CONCAT(experiment.sample1, ' / ', experiment.sample2) AS experimentHeading,
                                    study.description,
                                    experiment.ExperimentDescription 
                            FROM experiment 
                            NATURAL JOIN StudyExperiment 
                            NATURAL JOIN study 
                            WHERE eid=$currentEID AND study.stid = $currentSTID UNION ALL ";
    }
    
    # strip trailing 'UNION ALL' plus any trailing white space
    $query_titles =~ s/UNION ALL\s*$//i;
    
    $self->{_FullExperimentRec}        = $self->{_dbh}->prepare($query_titles) or croak $self->{_dbh}->errstr;
    $self->{_FullExperimentCount}    = $self->{_FullExperimentRec}->execute()     or croak $self->{_dbh}->errstr;    
    $self->{_FullExperimentData}    = $self->{_FullExperimentRec}->fetchall_hashref('eid');
    
    $self->{_FullExperimentRec}->finish;

}

#######################################################################################
sub list_yui_deps
{
    my ($self, $list) = @_;
    push @$list, (
        'yahoo-dom-event/yahoo-dom-event.js',
        'connection/connection-min.js',
        'dragdrop/dragdrop-min.js',
        'container/container-min.js',
        'element/element-min.js',
        'datasource/datasource-min.js',
        'paginator/paginator-min.js',
        'datatable/datatable-min.js',
        'selector/selector-min.js'
    );
}
#######################################################################################

#===  FUNCTION  ================================================================
#         NAME:  getform_findProbes
#      PURPOSE:  display Find Probes form
#   PARAMETERS:  $q - CGI object
#                $a - name of the top-level action
#      RETURNS:  ????
#  DESCRIPTION:  ????
#       THROWS:  no exceptions
#     COMMENTS:  none
#     SEE ALSO:  n/a
#===============================================================================
sub getform_findProbes {
    my ($q, $a) = @_;

    my %type_dropdown;
    my $type_dropdown_t = tie(%type_dropdown, 'Tie::IxHash',
        'gene'=>'Gene Symbols',
        'transcript'=>'Transcripts',
        'probe'=>'Probes'
    );
    my %match_dropdown;
    my $match_dropdown_t = tie(%match_dropdown, 'Tie::IxHash',
        'full'=>'Full Word',
        'prefix'=>'Prefix',
        'part'=>'Part of the Word / Regular Expression*'
    );
    my %opts_dropdown;
    my $opts_dropdown_t = tie(%opts_dropdown, 'Tie::IxHash',
        '1'=>'Basic (names and ids only)',
        '2'=>'Full annotation',
        '3'=>'Full annotation with experiment data (CSV)'
    );
    my %trans_dropdown;
    my $trans_dropdown_t = tie(%trans_dropdown, 'Tie::IxHash',
        'fold' => 'Fold Change +/- 1', 
        'ln'=>'Log2 Ratio'
    );

    return $q->start_form(-method=>'GET',
        -action=>$q->url(absolute=>1),
        -enctype=>'application/x-www-form-urlencoded') .
    $q->h2('Find Probes') .
    $q->p('Enter search text below to find the data for that probe. The textbox will allow a comma separated list of values, or one value per line, to obtain information on multiple probes.') .
    $q->p('Regular Expression Example: "^cyp.b" would retrieve all genes starting with cyp.b where the period represents any one character. More examples can be found at <a href="http://en.wikipedia.org/wiki/Regular_expression_examples">Wikipedia Examples</a>.') .
    $q->dl(
        $q->dt('Search string(s):'),
        $q->dd($q->textarea(-name=>'address',-id=>'address',-rows=>10,-columns=>50,-tabindex=>1, -name=>'text')),
        $q->dt('Search type :'),
        $q->dd($q->popup_menu(
                -name=>'type',
                -default=>'gene',
                -values=>[keys %type_dropdown],
                -labels=>\%type_dropdown
        )),
        $q->dt('Pattern to match :'),
        $q->dd($q->radio_group(
                -tabindex=>2, 
                -name=>'match', 
                -linebreak=>'true', 
                -default=>'full', 
                -values=>[keys %match_dropdown], 
                -labels=>\%match_dropdown
        )),
        $q->dt('Display options :'),
        $q->dd($q->popup_menu(
                -tabindex=>3, 
                -name=>'opts',
                -values=>[keys %opts_dropdown], 
                -default=>'1',
                -labels=>\%opts_dropdown
        )),
        $q->dt('Graph(s) :'),
        $q->dd($q->checkbox(-tabindex=>4, id=>'graph', -onclick=>'sgx_toggle(this.checked, [\'graph_option_names\', \'graph_option_values\']);', -checked=>0, -name=>'graph',-label=>'Show Differential Expression Graph')),
        $q->dt({id=>'graph_option_names'}, "Response variable:"),
        $q->dd({id=>'graph_option_values'}, $q->radio_group(
                -tabindex=>5, 
                -name=>'trans', 
                -linebreak=>'true', 
                -default=>'fold', 
                -values=>[keys %trans_dropdown], 
                -labels=>\%trans_dropdown
        )),
        $q->dt('&nbsp;'),
        $q->dd($q->submit(-tabindex=>6, -name=>'a', -value=>$a, -override=>1)),
    ) 
    .
    $q->endform;
}
#######################################################################################
sub build_InsideTableQuery
{
    my ($self, $type, %optarg) = @_;

    my $tmpTable = $optarg{tmp_table};
    switch ($type) 
    {
        case 'probe' {
            my $clause = (defined $tmpTable)
                ? "INNER JOIN $tmpTable tmpTable ON tmpTable.searchField=reporter"
                : 'WHERE reporter REGEXP ?';
            $self->{_InsideTableQuery} = <<"END_InsideTableQuery_probe";
SELECT DISTINCT accnum, seqname
        FROM gene 
        RIGHT JOIN annotates USING(gid)
        RIGHT JOIN probe USING(rid)
        $clause
END_InsideTableQuery_probe
        }
        case 'gene' {
            my $clause = (defined $tmpTable)
                ? "INNER JOIN $tmpTable tmpTable ON tmpTable.searchField=seqname"
                : 'WHERE seqname REGEXP ?';
            $self->{_InsideTableQuery} = <<"END_InsideTableQuery_gene"
SELECT DISTINCT accnum, seqname
        FROM gene 
        $clause
END_InsideTableQuery_gene
        }
        case 'transcript' {
            my $clause = (defined $tmpTable)
                ? "INNER JOIN $tmpTable tmpTable ON tmpTable.searchField=accnum"
                : 'WHERE accnum REGEXP ?';
            $self->{_InsideTableQuery} = <<"END_InsideTableQuery_transcript";
SELECT DISTINCT accnum, seqname
        FROM gene 
        $clause
END_InsideTableQuery_transcript
        } 
        else {
            croak "Unknown request parameter value type=$type";
        }
    }
}
#######################################################################################
sub build_ProbeQuery
{
    my ($self, %p) = @_;
    my $sql_select_fields = '';
    my $sql_subset_by_project = '';
    my $curr_proj = $p{curr_proj};

    assert(defined($p{extra_fields}));

    switch ($p{extra_fields}) {
        case 0 {
            # only probe ids (rid)
            $sql_select_fields = <<"END_select_fields_rid";
probe.rid,
probe.reporter,
platform.pid,
GROUP_CONCAT(DISTINCT IF(ISNULL(g0.accnum),'NONE',g0.accnum) ORDER BY g0.seqname ASC separator ' # ') AS 'Accession',
IF(ISNULL(g0.seqname),'NONE',g0.seqname) AS 'Gene',
probe.probe_sequence AS 'Probe Sequence',
GROUP_CONCAT(DISTINCT g0.description ORDER BY g0.seqname ASC SEPARATOR '; ') AS 'Gene Description',
GROUP_CONCAT(DISTINCT gene_note ORDER BY g0.seqname ASC SEPARATOR '; ') AS 'Gene Ontology - Comment'
END_select_fields_rid
        }
        case 1 {
            # basic
            $sql_select_fields = <<"END_select_fields_basic";
probe.reporter AS Probe, 
pname AS Platform,
GROUP_CONCAT(
    DISTINCT IF(ISNULL(g0.accnum), '', g0.accnum) 
    ORDER BY g0.seqname ASC SEPARATOR ','
) AS 'Transcript', 
IF(ISNULL(g0.seqname), '', g0.seqname) AS 'Gene',
platform.species AS 'Species' 
END_select_fields_basic
        }
        else {
            # with extras
            $sql_select_fields = <<"END_select_fields_extras";
probe.reporter AS Probe, 
pname AS Platform,
GROUP_CONCAT(
    DISTINCT IF(ISNULL(g0.accnum), '', g0.accnum) 
    ORDER BY g0.seqname ASC SEPARATOR ','
) AS 'Transcript', 
IF(ISNULL(g0.seqname), '', g0.seqname) AS 'Gene',
platform.species AS 'Species', 
probe.note AS 'Probe Specificity - Comment',
probe.probe_sequence AS 'Probe Sequence',
GROUP_CONCAT(
    DISTINCT g0.description ORDER BY g0.seqname ASC SEPARATOR '; '
) AS 'Gene Description',
GROUP_CONCAT(
    DISTINCT gene_note ORDER BY g0.seqname ASC SEPARATOR '; '
) AS 'Gene Ontology - Comment'
END_select_fields_extras
        }
    }

    if (defined($curr_proj) && $curr_proj ne '') {
        $curr_proj = $self->{_dbh}->quote($curr_proj);
        $sql_subset_by_project = <<"END_sql_subset_by_project"
INNER JOIN study USING(pid) 
INNER JOIN ProjectStudy USING(stid) 
WHERE prid=$curr_proj 
END_sql_subset_by_project
    }
    my $InsideTableQuery = $self->{_InsideTableQuery};
    $self->{_ProbeQuery} = <<"END_ProbeQuery";
SELECT
$sql_select_fields
FROM (
    SELECT 
        gid, 
        COALESCE(g1.accnum, gene.accnum) AS accnum, 
        COALESCE(g1.seqname, gene.seqname) AS seqname, 
        description, 
        gene_note
    FROM (
        $InsideTableQuery
    ) AS g1
    INNER JOIN gene ON (g1.accnum=gene.accnum OR g1.seqname=gene.seqname)
    GROUP BY gid
) AS g0
INNER JOIN annotates USING(gid)
INNER JOIN probe USING(rid)
INNER JOIN platform USING(pid)
$sql_subset_by_project
GROUP BY probe.rid
END_ProbeQuery
}
#######################################################################################
sub findProbes_js 
{
    my ($self, $s) = @_;

    $self->set_SearchItems(1);
    my $qtext = $self->{_SearchItems};

    # 'type' must always be set
    my $type = $self->{_cgi}->param('type') 
        or croak "You did not specify where to search";

    $self->build_InsideTableQuery($type);

    # find out what the current project is set to
    $s->read_perm_cookie();
    my $curr_proj = $s->{perm_cookie_value}->{curr_proj};

    my $opts = (defined($self->{_cgi}->param('opts'))) ? $self->{_cgi}->param('opts') : 1;
    $self->build_ProbeQuery(extra_fields => $opts, curr_proj => $curr_proj);

    my $trans = (defined($self->{_cgi}->param('trans'))) ? $self->{_cgi}->param('trans') : 'fold';

    if ($opts == 3) {
        # Full annotation with experiment data (CSV)
        $s->commit();
        #print $self->{_cgi}->header(-type=>'text/html', -cookie=>\@SGX::Cookie::cookies);
        #$self = SGX::FindProbes->new($self->{_dbh},$q,$type,$qtext);
        $self->{_SearchType} = $type;
        $self->{_SearchText} = $qtext;
        #$self->setInsideTableQuery($g0_sql);
        $self->loadProbeData($qtext);
        $self->loadExperimentData();
        $self->fillPlatformHash();
        $self->getFullExperimentData();        
        $self->printFindProbeCSV();
        exit;
    }
    else {
        # HTML output
        my $sth = $self->{_dbh}->prepare($self->{_ProbeQuery})
            or croak $self->{_dbh}->errstr;
        my $rowcount = $sth->execute($qtext) 
            or croak $self->{_dbh}->errstr;

        my $caption = sprintf("Found %d probe", $rowcount) .(($rowcount != 1) ? 's' : '')." annotated with $type groups matching '$qtext' (${type}s grouped by gene symbol or transcript accession number)";

        my @json_records;
        my %json_probelist = (
            caption => $caption,
            records => \@json_records
        );

        # cache the field name array
        my @names = @{$sth->{NAME}};

        my $data = $sth->fetchall_arrayref;
        $sth->finish;

        # data are sent as a JSON object plus Javascript code (at the moment)
        #foreach (sort {$a->[3] cmp $b->[3]} @$data) {
        foreach my $array_ref (@$data) {
            # the below "trick" converts an array into a hash such that array elements
            # become hash values and array indexes become hash keys
            my $i = 0;
            my %row = map { $i++ => $_ } @$array_ref;
            push @json_records, \%row;
        }

        my $out = 'var probelist = ' . encode_json(\%json_probelist) . ";\n";
        my $tableOut = '';
        my $columnList = '';

        # Note: the following NCBI search shows only genes specific to a given species:
        # http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=gene&term=Cyp2a12+AND+mouse[ORGN]
        switch ($opts) 
            {
                case 1 
                {
                    $tableOut = '';
                }

                case 2 
                { 
                    $columnList = ',"4","5","6","7","8"';
                    $tableOut = ',
                            {key:"4", sortable:true, resizeable:true, label:"'.$names[4].'",
                    editor:new YAHOO.widget.TextareaCellEditor({
                    disableBtns: false,
                    asyncSubmitter: function(callback, newValue) { 
                        var record = this.getRecord();
                        //var column = this.getColumn();
                        //var datatable = this.getDataTable(); 
                        if (this.value == newValue) { callback(); } 

                        YAHOO.util.Connect.asyncRequest("POST", "'.$self->{_cgi}->url(-absolute=>1).'?a=updateCell", { 
                            success:function(o) { 
                                if(o.status === 200) {
                                    // HTTP 200 OK
                                    callback(true, newValue); 
                                } else { 
                                    alert(o.statusText);
                                    //callback();
                                } 
                            }, 
                            failure:function(o) { 
                                alert(o.statusText); 
                                callback(); 
                            },
                            scope:this 
                        }, "type=probe&note=" + escape(newValue) + "&pname=" + encodeURI(record.getData("1")) + "&reporter=" + encodeURI(record.getData("0"))
                        );
                    }})},
                            {key:"5", sortable:true, resizeable:true, label:"'.$names[5].'", formatter:"formatSequence"},
                            {key:"6", sortable:true, resizeable:true, label:"'.$names[6].'"},
                            {key:"7", sortable:true, resizeable:true, label:"'.$names[7].'",

                    editor:new YAHOO.widget.TextareaCellEditor({
                    disableBtns: false,
                    asyncSubmitter: function(callback, newValue) {
                        var record = this.getRecord();
                        //var column = this.getColumn();
                        //var datatable = this.getDataTable();
                        if (this.value == newValue) { callback(); }
                        YAHOO.util.Connect.asyncRequest("POST", "'.$self->{_cgi}->url(-absolute=>1).'?a=updateCell", {
                            success:function(o) {
                                if(o.status === 200) {
                                    // HTTP 200 OK
                                    callback(true, newValue);
                                } else {
                                    alert(o.statusText);
                                    //callback();
                                }
                            },
                            failure:function(o) {
                                alert(o.statusText);
                                callback();
                            },
                            scope:this
                        }, "type=gene&note=" + escape(newValue) + "&pname=" + encodeURI(record.getData("1")) + "&seqname=" + encodeURI(record.getData("3")) + "&accnum=" + encodeURI(record.getData("2"))
                        );
                    }})}';
                }

                case 3 
                {
                    $columnList = ',"4","5","6","7","8","9"';
                    $tableOut = ",\n" . '{key:"5", sortable:true, resizeable:true, label:"Experiment",formatter:"formatExperiment"}';
                    $tableOut .= ",\n" . '{key:"7", sortable:true, resizeable:true, label:"Probe Sequence"}';
                }
            }


        $out .= '
    function export_table(e) {
        var r = this.records;
        var bl = this.headers.length;
        var w = window.open("");
        var d = w.document.open("text/html");
        d.title = "Tab-Delimited Text";
        d.write("<pre>");
        for (var i=0, al = r.length; i < al; i++) {
            for (var j=0; j < bl; j++) {
                d.write(r[i][j] + "\t");
            }
            d.write("\n");
        }
        d.write("</pre>");
        d.close();
        w.focus();
    }

    YAHOO.util.Event.addListener("probetable_astext", "click", export_table, probelist, true);
    YAHOO.util.Event.addListener(window, "load", function() {
        ';
        if (defined($self->{_cgi}->param('graph'))) {
            $out .= 'var graph_content = "";
        var graph_ul = YAHOO.util.Dom.get("graphs");';
        }
        $out .= '
        YAHOO.util.Dom.get("caption").innerHTML = probelist.caption;

        YAHOO.widget.DataTable.Formatter.formatProbe = function(elCell, oRecord, oColumn, oData) {
            var i = oRecord.getCount();
            ';
            if (defined($self->{_cgi}->param('graph'))) {
                $out .= 'graph_content += "<li id=\"reporter_" + i + "\"><object type=\"image/svg+xml\" width=\"555\" height=\"880\" data=\"./graph.cgi?reporter=" + oData + "&trans='.$trans.'\"><embed src=\"./graph.cgi?reporter=" + oData + "&trans='.$trans.'\" width=\"555\" height=\"880\" /></object></li>";
            elCell.innerHTML = "<div id=\"container" + i + "\"><a title=\"Show differental expression graph\" href=\"#reporter_" + i + "\">" + oData + "</a></div>";';
            } else {
                $out .= 'elCell.innerHTML = "<div id=\"container" + i + "\"><a title=\"Show differental expression graph\" id=\"show" + i + "\">" + oData + "</a></div>";';
            }
        $out .= '
        }
        YAHOO.widget.DataTable.Formatter.formatTranscript = function(elCell, oRecord, oColumn, oData) {
            var a = oData.split(/ *, */);
            var out = "";
            for (var i=0, al=a.length; i < al; i++) {
                var b = a[i];
                if (b.match(/^ENS[A-Z]{4}\d{11}/i)) {
                    out += "<a title=\"Search Ensembl for " + b + "\" target=\"_blank\" href=\"http://www.ensembl.org/Search/Summary?species=all;q=" + b + "\">" + b + "</a>, ";
                } else {
                    out += "<a title=\"Search NCBI Nucleotide for " + b + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=Nucleotide&term=" + oRecord.getData("4") + "[ORGN]+AND+" + b + "[NACC]\">" + b + "</a>, ";
                }
            }
            elCell.innerHTML = out.replace(/,\s*$/, "");
        }
        YAHOO.widget.DataTable.Formatter.formatGene = function(elCell, oRecord, oColumn, oData) {
            if (oData.match(/^ENS[A-Z]{4}\d{11}/i)) {
                elCell.innerHTML = "<a title=\"Search Ensembl for " + oData + "\" target=\"_blank\" href=\"http://www.ensembl.org/Search/Summary?species=all;q=" + oData + "\">" + oData + "</a>";
            } else {
                elCell.innerHTML = "<a title=\"Search NCBI Gene for " + oData + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=gene&term=" + oRecord.getData("4") + "[ORGN]+AND+" + oData + "\">" + oData + "</a>";
            }
        }
        YAHOO.widget.DataTable.Formatter.formatExperiment = function(elCell, oRecord, oColumn, oData) {
            elCell.innerHTML = "<a title=\"View Experiment Data\" target=\"_blank\" href=\"?a=getTFS&eid=" + oRecord.getData("6") + "&rev=0&fc=" + oRecord.getData("9") + "&pval=" + oRecord.getData("8") + "&opts=2\">" + oData + "</a>";
        }
        YAHOO.widget.DataTable.Formatter.formatSequence = function(elCell, oRecord, oColumn, oData) {
            elCell.innerHTML = "<a href=\"http://genome.ucsc.edu/cgi-bin/hgBlat?userSeq=" + oData + "&type=DNA&org=" + oRecord.getData("4") + "\" title=\"UCSC BLAT on " + oRecord.getData("4") + " DNA\" target=\"_blank\">" + oData + "</a>";
        }
        var myColumnDefs = [
            {key:"0", sortable:true, resizeable:true, label:"'.$names[0].'", formatter:"formatProbe"},
            {key:"1", sortable:true, resizeable:true, label:"'.$names[1].'"},
            {key:"2", sortable:true, resizeable:true, label:"'.$names[2].'", formatter:"formatTranscript"}, 
            {key:"3", sortable:true, resizeable:true, label:"'.$names[3].'", formatter:"formatGene"}'. $tableOut.'];

        var myDataSource = new YAHOO.util.DataSource(probelist.records);
        myDataSource.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
        myDataSource.responseSchema = {
            fields: ["0","1","2","3"'. $columnList . ']
        };
        var myData_config = {
            paginator: new YAHOO.widget.Paginator({
                rowsPerPage: 50 
            })
        };

        var myDataTable = new YAHOO.widget.DataTable("probetable", myColumnDefs, myDataSource, myData_config);

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

        var nodes = YAHOO.util.Selector.query("#probetable tr td.yui-dt-col-0 a");
        var nl = nodes.length;

        // Ideally, would want to use a "pre-formatter" event to clear graph_content
        // TODO: fix the fact that when cells are updated via cell editor, the graphs are rebuilt unnecessarily.
        myDataTable.doBeforeSortColumn = function(oColumn, sSortDir) {
            graph_content = "";
            return true;
        };
        myDataTable.doBeforePaginatorChange = function(oPaginatorState) {
            graph_content = "";
            return true;
        };
        myDataTable.subscribe("renderEvent", function () {
        ';

        if (defined($self->{_cgi}->param('graph'))) 
        {
            $out .= '
            graph_ul.innerHTML = graph_content;
            ';

        } else {
            $out .=
        '
            // if the line below is moved to window.load closure,
            // panels will no longer show up after sorting
            var manager = new YAHOO.widget.OverlayManager();
            var myEvent = YAHOO.util.Event;
            var i;
            var imgFile;
            for (i = 0; i < nl; i++) {
                myEvent.addListener("show" + i, "click", function () {
                    var index = this.getAttribute("id").substring(4);
                    var panel_old = manager.find("panel" + index);

                    if (panel_old === null) {
                        imgFile = this.innerHTML;    // replaced ".text" with ".innerHTML" because of IE problem
                        var panel =  new YAHOO.widget.Panel("panel" + index, { close:true, visible:true, draggable:true, constraintoviewport:false, context:["container" + index, "tl", "br"] } );
                        panel.setHeader(imgFile);
                        panel.setBody("<object type=\"image/svg+xml\" width=\"555\" height=\"880\" data=\"./graph.cgi?reporter=" + imgFile + "&trans='.$trans.'\"><embed src=\"./graph.cgi?reporter=" + imgFile + "&trans='.$trans.'\" width=\"555\" height=\"880\" /></object>");
                        manager.register(panel);
                        panel.render("container" + index);
                        // panel.show is unnecessary here because visible:true is set
                    } else {
                        panel_old.show();
                    }
                }, nodes[i], true);
            }
        '};
        $out .= '
        });

        return {
            oDS: myDataSource,
            oDT: myDataTable
        };
    });
    ';
        $out;
    }
}

1;
