"use strict";

/*
* Note: the following NCBI search shows only genes specific to a given species:
* http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=gene&term=Cyp2a12+AND+mouse[ORGN]
*/

YAHOO.util.Event.addListener("probetable_astext", "click", export_table, probelist, true);
YAHOO.util.Event.addListener(window, "load", function() {
    var graph_ul;
    var graph_content = '';

    var matchesQuery = (function() {
        // first see if we have an array
        if (YAHOO.lang.isArray(queriedItems)) {
            var regexes = [];
            for (var i = 0, len = queriedItems.length; i < len; i++) {
                regexes.push(new RegExp(queriedItems[i], 'i'));
            }
            // for each item in the list, check if the given argument matches
            // formed regulat expression.
            return function(x) {
                for (var j = 0, len = regexes.length; j < len; j++) {
                    if (x.match(regexes[j])) {
                        return true;
                    }
                }
                return false;
            };
        }
        // then check if we are dealing with an object
        else if (YAHOO.lang.isObject(queriedItems)) {
            return function(x) { return (x.toLowerCase() in queriedItems); };
        }
        // fail otherwise
        else {
            throw new TypeError("Type of queriedItems must be an Object");
        }
    })();


    function buildSVGElement(obj) {
        function uriFromKeyVal(obj) {
            var uri_part = [];
            for (var key in obj) {
                var val = obj[key];
                uri_part.push(key + '=' + val);
            }
            return uri_part.join('&');
        }
        var resourceURI = "./?a=graph&" + uriFromKeyVal(obj);
        var width = 1200;
        var height = 600;
        return "<object type=\"image/svg+xml\" width=\"" + width + "\" height=\"" + height + "\" data=\"" + resourceURI + "\"><embed src=\"" + resourceURI + "\" width=\"" + width + "\" height=\"" + height + "\" /></object>";
    }

    if (show_graphs !== 'No Graphs') {
        graph_ul = YAHOO.util.Dom.get("graphs");
    }

    YAHOO.util.Dom.get("caption").innerHTML = probelist.caption;

    YAHOO.widget.DataTable.Formatter.formatProbe = function(elCell, oRecord, oColumn, oData) {
        var hClass = (searchColumn === oColumn.key && matchesQuery(oData))
            ? 'class="highlight"' 
            : '';
        var i = oRecord.getCount();
        if (show_graphs !== 'No Graphs') {
            var this_rid = oRecord.getData("0");
            graph_content += "<li id=\"reporter_" + i + "\">" + buildSVGElement({proj: project_id, rid: this_rid, reporter: oData, trans: show_graphs}) + "</li>";
            elCell.innerHTML = "<div id=\"container" + i + "\"><a " + hClass + " title=\"Show differental expression graph\" href=\"#reporter_" + i + "\">" + oData + "</a></div>";
        } else {
            elCell.innerHTML = "<div id=\"container" + i + "\"><a " + hClass + " title=\"Show differental expression graph\" id=\"show" + i + "\">" + oData + "</a></div>";
        }
    };

    YAHOO.widget.DataTable.Formatter.formatAccNum = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            var a = oData.split(/\s+/);
            var out = [];
            for (var i=0, al=a.length; i < al; i++) {
                var b = a[i];
                var hClass = (searchColumn === oColumn.key && matchesQuery(b))
                    ? 'class="highlight"' 
                    : '';
                if (b.match(/^ENS[A-Z]{0,4}\d{11}/i)) {
                    out.push("<a " + hClass + " title=\"Search Ensembl for " + b + "\" target=\"_blank\" href=\"http://www.ensembl.org/Search/Summary?species=all;q=" + b + "\">" + b + "</a>");
                } else {
                    out.push("<a " + hClass + " title=\"Search NCBI Nucleotide for " + b + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=Nucleotide&term=" + oRecord.getData("5") + "[ORGN]+AND+" + b + "[ACCN]\">" + b + "</a>");
                }
            }
            elCell.innerHTML = out.join(', ');
        }
    };
    YAHOO.widget.DataTable.Formatter.formatGene = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            var a = oData.split(/\s+/);
            var out = [];
            for (var i=0, al=a.length; i < al; i++) {
                var b = a[i];
                var hClass = (searchColumn === oColumn.key && matchesQuery(b))
                    ? 'class="highlight"' 
                    : '';
                if (b.match(/^ENS[A-Z]{0,4}\d{11}/i)) {
                    out.push("<a " + hClass + " title=\"Search Ensembl for " + b + "\" target=\"_blank\" href=\"http://www.ensembl.org/Search/Summary?species=all;q=" + b + "\">" + b + "</a>");
                } else if (b.match(/^\d+$/)) {
                    out.push("<a " + hClass + " title=\"Search NCBI Gene for " + b + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/gene?term=" + b + "[uid]\">" + b + "</a>");
                } else if (b.match(/-similar_to/)) {
                    out.push(b);
                } else {
                    out.push("<a " + hClass + " title=\"Search NCBI Gene for " + b + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=gene&term=" + oRecord.getData("5") + "[ORGN]+AND+" + b + "[GENE]\">" + b + "</a>");
                }
            }
            elCell.innerHTML = out.join(', ');
        }
    };
    YAHOO.widget.DataTable.Formatter.formatExperiment = function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = "<a title=\"View Experiment Data\" target=\"_blank\" href=\"?a=getTFS&eid=" + oRecord.getData("7") + "&rev=0&fc=" + oRecord.getData("10") + "&pval=" + oRecord.getData("9") + "&opts=2\">" + oData + "</a>";
    };
    YAHOO.widget.DataTable.Formatter.formatSequence = function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = "<a href=\"http://genome.ucsc.edu/cgi-bin/hgBlat?userSeq=" + oData + "&type=DNA&org=" + oRecord.getData("5") + "\" title=\"Search for this sequence using BLAT in " + oRecord.getData("5") + " genome (genome.ucsc.edu)\" target=\"_blank\">" + oData + "</a>";
    };

    var myDataSource = new YAHOO.util.DataSource(probelist.records);
    myDataSource.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;

    var myColumnList = ["0","1","2","3","4","5"];
    var myColumnDefs = [
        {key:"1", sortable:true, resizeable:true, 
            label:probelist.headers[0], formatter:"formatProbe"},
        {key:"2", sortable:true, resizeable:true, 
            label:probelist.headers[1]},
        {key:"3", sortable:true, resizeable:true, 
            label:probelist.headers[2], formatter:"formatAccNum"}, 
        {key:"4", sortable:true, resizeable:true, 
            label:probelist.headers[3], formatter:"formatGene"},
        {key:"5", sortable:true, resizeable:true, 
            label:probelist.headers[4]}
    ];
    if (extra_fields !== 'Basic') {
        myColumnList.push("6","7","8");
        myColumnDefs.push(
            {key:"6", sortable:true, resizeable:true, 
                label:probelist.headers[5], formatter:"formatSequence"},
            {key:"7", sortable:true, resizeable:true, 
                label:probelist.headers[6]},
            {key:"8", sortable:true, resizeable:true, 
                label:probelist.headers[7]}
        );
    }
    myDataSource.responseSchema = {
        fields: myColumnList
    };
    var myData_config = {
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

    // TODO: fix this -- no need to know anything about actual data
    // representation
    var nodes = YAHOO.util.Selector.query("#probetable tr td.yui-dt-col-1 a");
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
        (show_graphs !== 'No Graphs') 
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
                        var panel = new YAHOO.widget.Panel("panel" + index, { 
                            close:true, visible:true, draggable:true, 
                            constraintoviewport:false, 
                            context:["container" + index, "tl", "br"] 
                        });
                        var this_reporter = this.innerHTML;
                        panel.setHeader(this_reporter);

                        var this_rid = myDataTable.getRecord(this).getData("0");
                        panel.setBody(buildSVGElement({
                            proj: project_id, rid: this_rid, reporter: this_reporter, trans: show_graphs
                        }));
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
