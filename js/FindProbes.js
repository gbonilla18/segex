/*
* Note: the following NCBI search shows only genes specific to a given species:
* http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=gene&term=Cyp2a12+AND+mouse[ORGN]
*/

YAHOO.util.Event.addListener("probetable_astext", "click", export_table, probelist, true);
YAHOO.util.Event.addListener(window, "load", function() {
    var graph_ul;
    var graph_content;

    function buildSVGElement(project_id, reporter, transform) {
        var resourceURI = "./graph.cgi?proj=" + project_id + "&reporter=" + reporter + "&trans=" + transform;
        var width = 1200;
        var height = 600;
        return "<object type=\"image/svg+xml\" width=\"" + width + "\" height=\"" + height + "\" data=\"" + resourceURI + "\"><embed src=\"" + resourceURI + "\" width=\"" + width + "\" height=\"" + height + "\" /></object>";
    }

    // Define a custom row formatter function
    var myRowFormatter = function(elTr, oRecord) {
        if (oRecord.getData(searchColumn).toLowerCase() in queriedItems ) {
            YAHOO.util.Dom.addClass(elTr, 'mark');
        }
        return true;
    };

    if (show_graphs) {
        graph_ul = YAHOO.util.Dom.get("graphs");
    }

    YAHOO.util.Dom.get("caption").innerHTML = probelist.caption;

    YAHOO.widget.DataTable.Formatter.formatProbe = function(elCell, oRecord, oColumn, oData) {
        var i = oRecord.getCount();
        if (show_graphs) {
            graph_content += "<li id=\"reporter_" + i + "\">" + buildSVGElement(project_id, oData, response_transform) + "</li>";
            elCell.innerHTML = "<div id=\"container" + i + "\"><a title=\"Show differental expression graph\" href=\"#reporter_" + i + "\">" + oData + "</a></div>";
        } else {
            elCell.innerHTML = "<div id=\"container" + i + "\"><a title=\"Show differental expression graph\" id=\"show" + i + "\">" + oData + "</a></div>";
        }
    };

    YAHOO.widget.DataTable.Formatter.formatAccNum = function(elCell, oRecord, oColumn, oData) {
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
    };
    YAHOO.widget.DataTable.Formatter.formatGene = function(elCell, oRecord, oColumn, oData) {
        if (oData.match(/^ENS[A-Z]{4}\d{11}/i)) {
            elCell.innerHTML = "<a title=\"Search Ensembl for " + oData + "\" target=\"_blank\" href=\"http://www.ensembl.org/Search/Summary?species=all;q=" + oData + "\">" + oData + "</a>";
        } else {
            elCell.innerHTML = "<a title=\"Search NCBI Gene for " + oData + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=gene&term=" + oRecord.getData("4") + "[ORGN]+AND+" + oData + "\">" + oData + "</a>";
        }
    };
    YAHOO.widget.DataTable.Formatter.formatExperiment = function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = "<a title=\"View Experiment Data\" target=\"_blank\" href=\"?a=getTFS&eid=" + oRecord.getData("6") + "&rev=0&fc=" + oRecord.getData("9") + "&pval=" + oRecord.getData("8") + "&opts=2\">" + oData + "</a>";
    };
    YAHOO.widget.DataTable.Formatter.formatSequence = function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = "<a href=\"http://genome.ucsc.edu/cgi-bin/hgBlat?userSeq=" + oData + "&type=DNA&org=" + oRecord.getData("4") + "\" title=\"Search for this sequence using BLAT in " + oRecord.getData("4") + " genome (genome.ucsc.edu)\" target=\"_blank\">" + oData + "</a>";
    };

    var myDataSource = new YAHOO.util.DataSource(probelist.records);
    myDataSource.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;

    var myColumnList = ["0","1","2","3","4"];
    var myColumnDefs = [
        {key:"0", sortable:true, resizeable:true, 
            label:probelist.headers[0], formatter:"formatProbe"},
        {key:"1", sortable:true, resizeable:true, 
            label:probelist.headers[1]},
        {key:"2", sortable:true, resizeable:true, 
            label:probelist.headers[2], formatter:"formatAccNum"}, 
        {key:"3", sortable:true, resizeable:true, 
            label:probelist.headers[3], formatter:"formatGene"},
        {key:"4", sortable:true, resizeable:true, 
            label:probelist.headers[4]}
    ];
    if (extra_fields) {
        myColumnList.push("5","6","7");
        myColumnDefs.push(
            {key:"5", sortable:true, resizeable:true, 
                label:probelist.headers[5], formatter:"formatSequence"},
            {key:"6", sortable:true, resizeable:true, 
                label:probelist.headers[6]},
            {key:"7", sortable:true, resizeable:true, 
                label:probelist.headers[7]}
        );
    }
    myDataSource.responseSchema = {
        fields: myColumnList
    };
    var myData_config = {
        formatRow: myRowFormatter,
        paginator: new YAHOO.widget.Paginator({
            rowsPerPage: 15 
        })
    };

    var myDataTable = new YAHOO.widget.DataTable(
    "probetable", myColumnDefs, myDataSource, myData_config);

    // Set up editing flow 
    var highlightEditableCell = function(oArgs) { 
        var elCell = oArgs.target; 
        if(YAHOO.util.Dom.hasClass(elCell, "yui-dt-editable")) { 
            this.highlightCell(elCell); 
        } 
    }; 
    myDataTable.subscribe("cellMouseoverEvent", highlightEditableCell); 
    myDataTable.subscribe("cellMouseoutEvent", 
    myDataTable.onEventUnhighlightCell); 
    myDataTable.subscribe("cellClickEvent", myDataTable.onEventShowCellEditor);

    var nodes = YAHOO.util.Selector.query("#probetable tr td.yui-dt-col-0 a");
    var nl = nodes.length;

    // Ideally, would want to use a "pre-formatter" event to clear graph_content
    // TODO: fix the fact that when cells are updated via cell editor, the
    // graphs are rebuilt unnecessarily.
    //
    myDataTable.doBeforeSortColumn = function(oColumn, sSortDir) {
        graph_content = "";
        return true;
    };
    myDataTable.doBeforePaginatorChange = function(oPaginatorState) {
        graph_content = "";
        return true;
    };

    // TODO: why are we adding a new listener every time the table is rendered?
    myDataTable.subscribe("renderEvent", 
        (show_graphs) 
        ? function () { graph_ul.innerHTML = graph_content; }
        : function () {
            // if the line below is moved to window.load closure,
            // panels will no longer show up after sorting
            var manager = new YAHOO.widget.OverlayManager();
            var myEvent = YAHOO.util.Event;
            for (var i = 0; i < nl; i++) {
                myEvent.addListener("show" + i, "click", function () {
                    var index = this.getAttribute("id").substring(4);
                    var panel_old = manager.find("panel" + index);

                    if (panel_old === null) {
                        // replaced ".text" with ".innerHTML" because of IE
                        // problem
                        var imgFile = this.innerHTML;    
                        var panel = new YAHOO.widget.Panel("panel" + index, { 
                            close:true, visible:true, draggable:true, 
                            constraintoviewport:false, 
                            context:["container" + index, "tl", "br"] 
                        });
                        panel.setHeader(imgFile);
                        panel.setBody(buildSVGElement(project_id,
                            imgFile, 
                            response_transform
                        ));
                        manager.register(panel);
                        panel.render("container" + index);
                        // panel.show is unnecessary here because visible:true
                        // is set
                    } else {
                        panel_old.show();
                    }
                }, nodes[i], true);
            }
        }
    );

    return {
        oDS: myDataSource,
        oDT: myDataTable
    };
});
