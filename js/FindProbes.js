"use strict";

/*
* Note: the following NCBI search shows only genes specific to a given species:
* http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=gene&term=Cyp2a12+AND+mouse[ORGN]
*/

var dom = YAHOO.util.Dom;
YAHOO.util.Event.addListener("resulttable_astext", "click", export_table, data, true);
YAHOO.util.Event.addListener("get_csv", "submit", function(o) {
    var inputEl = dom.get("q");
    var rec = data.records;
    var len = rec.length;
    var array = new Array(len);
    for (var i = 0; i < len; i++) {
        array[i] = rec[i][0];
    }
    inputEl.value = array.join(',');
    return true;
}, null, false);

YAHOO.util.Event.addListener(window, "load", function() {

    var graph_ul;
    var graph_content = '';
    var queriedPhrases = (match === 'Full Word') 
        ? splitIntoPhrases(queryText)
        : queryText.split(/[,\s]+/);
    var regex_obj = (function() {
        if (queriedPhrases.length === 0) {
            return null;
        }
        var joined = (queriedPhrases.length > 1) 
            ? '(?:' + queriedPhrases.join('|') + ')' 
            : queriedPhrases.join('|');
        var bounds = {
            'Prefix':    ['\\b',  '\\w*'],
            'Full Word': ['\\b',  '\\b' ],
            'Partial':   ['\\w*', '\\w*']
        };
        var regex = bounds[match][0] + joined + bounds[match][1];
        try {
            var regex_obj = new RegExp(regex, 'gi');
            return regex_obj;
        } catch(e) {
            return null;
        }
    }());

    var highlightWords = (regex_obj !== null) 
        ? function(x) {
            return x.replace(regex_obj, function(v) { 
                return '<span class="highlight">' + v + '</span>';
            });
        } 
        : function(x) {
            return x;
        };

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
        return "<object type=\"image/svg+xml\" width=\"" 
        + width + "\" height=\"" + height + "\" data=\"" 
        + resourceURI + "\"><embed src=\"" + resourceURI 
        + "\" width=\"" + width + "\" height=\"" + height 
        + "\" /></object>";
    }

    if (show_graphs !== 'No Graphs') {
        graph_ul = dom.get("graphs");
    }

    dom.get("caption").innerHTML = data.caption;

    // extra_fields >= 0
    var dataFields = { rid: "0" };
    var myColumnList = [{key:"0", parser:"number"}];
    var myColumnDefs = [];

    var columns2highlight = {
        'GO IDs'               : { },
        'Probe IDs'            : { '2' : 1 },
        'Genes/Accession Nos.' : { '6'  : 1 },
        'Gene Names/Desc.'     : { '6'  : 1, '9' : 1 },
    };
    var currScope = columns2highlight[scope];

    // extra_fields > 0
    if (extra_fields > 0) {
        dataFields['species']  = '3';
        myColumnList.push(
            {key:"1", parser:"number"},
            {key:"2"},
            {key:"3"},
            {key:"4"},
            {key:"5"},
            {key:"6"}
        );
        myColumnDefs.push(
            {key:"4", sortable:true, resizeable:true, 
                label:data.headers[3] + '/' + data.headers[4], formatter:"formatPlatform"},
            {key:"2", sortable:true, resizeable:true, 
                label:data.headers[2], formatter:"formatProbe"}
        );
        if (extra_fields > 1) {
            myColumnList.push(
                {key:"7"},
                {key:"8"}
            );
            myColumnDefs.push(
                {key:"7", sortable:true, resizeable:true,
                    label:data.headers[7], formatter:"formatSequence"},
                {key:"8", sortable:true, resizeable:true,
                    label:data.headers[8]}
            );
        }
        myColumnDefs.push(
            {key:"5", sortable:true, resizeable:true, 
                label:data.headers[5], formatter:"formatAccNum"}, 
            {key:"6", sortable:true, resizeable:true, 
                label:data.headers[6], formatter:"formatGene"}
        );
        if (extra_fields > 1) {
            myColumnList.push(
                {key:"9"}
            );
            myColumnDefs.push(
                {key:"9", sortable:true, resizeable:true, 
                    label:data.headers[9], formatter:"formatGeneName"}
            );
        }
    }
    function wrapProbeGraphs(oData, highlight, args) {
        var i = args[0];
        var this_rid = args[1];
        graph_content += "<li id=\"reporter_" + i + "\">" 
        + buildSVGElement({proj: project_id, rid: this_rid, reporter: oData, trans: show_graphs}) 
        + "</li>";
        return "<div id=\"container" + i + "\"><a " 
        + highlight + " title=\"Show differental expression graph\" href=\"#reporter_" 
        + i + "\">" + oData + "</a></div>";       
    }
    function wrapProbe(oData, highlight, args) {
        var i = args[0];
        return "<div id=\"container" + i + "\"><a " 
                + highlight + " title=\"Show differental expression graph\" id=\"show" 
                + i + "\">" + oData + "</a></div>";
    }
    function wrapAccNum(b, highlight, args) {
        var species = args[0];
        if (b.match(/^ENS[A-Z]{0,4}\d{11}$/i)) {
            return "<a " + highlight + " title=\"Search Ensembl for " + b 
                + "\" target=\"_blank\" href=\"http://www.ensembl.org/Search/Summary?species=all;q=" 
            + b + "\">" + b + "</a>";
        } else {
            return "<a " + highlight + " title=\"Search NCBI Nucleotide for " + b 
                + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=Nucleotide&term=" 
            + species + "[ORGN]+AND+" + b + "[ACCN]\">" + b + "</a>";
        }
    }
    function wrapGeneSymbol(b, highlight, args) {
        var species = args[0];
        var gsymbol = b;
        if (b.match(/^ENS[A-Z]{0,4}\d{11}$/i)) {
            return "<a " + highlight + " title=\"Search Ensembl for " + b 
                + "\" target=\"_blank\" href=\"http://www.ensembl.org/Search/Summary?species=all;q=" 
            + b + "\">" + b + "</a>";
        } else if (b.match(/^\d+$/)) {
            return "<a " + highlight + " title=\"Search NCBI Gene for " + b 
                + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/gene?term=" 
            + b + "[uid]\">" + b + "</a>";
        } else if (b.match(/^\w+_similar_to/)) {
            var match = /^(\w+)_similar_to/.exec(b);
            var gsymbol = match[1];
        }
        return "<a " + highlight + " title=\"Search NCBI Gene for " + gsymbol 
                + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=gene&term=" 
            + species + "[ORGN]+AND+" + gsymbol + "[GENE]\">" + b + "</a>";
    }

    function formatSymbols(symbol, colKey, wrapperFun, args) {
            // split by commas while removing spaces
            var array = symbol.split(/[,\s]+/);
            var len = array.length;
            var formatted = new Array(len);
            for (var i = 0; i < len; i++) {
                var val = array[i];
                formatted[i] = wrapperFun(val,
                    ((colKey in currScope && regex_obj !== null && val.match(regex_obj)) 
                    ? 'class="highlight"' 
                    : ''), args
                );
            }
            return formatted.join(', ');
    }
    YAHOO.widget.DataTable.Formatter.formatProbe = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            var i = oRecord.getCount();
            if (show_graphs !== '') {
                 var this_rid = oRecord.getData(dataFields.rid);
                 elCell.innerHTML = formatSymbols(oData, oColumn.key, wrapProbeGraphs, [i, this_rid]);
            } else {
                 elCell.innerHTML = formatSymbols(oData, oColumn.key, wrapProbe, [i]);
            }
        }
    };
    YAHOO.widget.DataTable.Formatter.formatAccNum = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            var species = oRecord.getData(dataFields.species);
            elCell.innerHTML = formatSymbols(oData, oColumn.key, wrapAccNum, [species]);
        }
    };
    YAHOO.widget.DataTable.Formatter.formatGene = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            var species = oRecord.getData(dataFields.species);
            elCell.innerHTML = formatSymbols(oData, oColumn.key, wrapGeneSymbol, [species]);
        }
    };
    YAHOO.widget.DataTable.Formatter.formatGeneName = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            elCell.innerHTML = (oColumn.key in currScope) ? highlightWords(oData) : oData;
        }
    }
    YAHOO.widget.DataTable.Formatter.formatPlatform = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            var species = oRecord.getData(dataFields.species);
            elCell.innerHTML = (oData.match(new RegExp('^' + species))) 
            ? oData
            : species + ' / ' + oData;
        }
    };
    YAHOO.widget.DataTable.Formatter.formatSequence = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            dom.addClass(elCell, 'sgx-dt-sequence');
            var species = oRecord.getData(dataFields.species);
            elCell.innerHTML = "<a href=\"http://genome.ucsc.edu/cgi-bin/hgBlat?userSeq=" + oData 
            + "&type=DNA&org=" + species + "\" title=\"Search for this sequence using BLAT in " 
            + species + " genome (genome.ucsc.edu)\" target=\"_blank\">" + oData + "</a>";
        }
    };

    var myDataSource = new YAHOO.util.DataSource(data.records);
    myDataSource.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;


    myDataSource.responseSchema = {
        fields: myColumnList
    };
    var myData_config = {
        paginator: new YAHOO.widget.Paginator({
            rowsPerPage: 15 
        })
    };

    var myDataTable = new YAHOO.widget.DataTable(
    "resulttable", myColumnDefs, myDataSource, myData_config);

    // Set up editing flow 
    var highlightEditableCell = function(oArgs) { 
        var elCell = oArgs.target; 
        if(dom.hasClass(elCell, "yui-dt-editable")) { 
            this.highlightCell(elCell); 
        } 
    }; 
    myDataTable.subscribe("cellMouseoverEvent", highlightEditableCell); 
    myDataTable.subscribe("cellMouseoutEvent", 
    myDataTable.onEventUnhighlightCell); 
    myDataTable.subscribe("cellClickEvent", myDataTable.onEventShowCellEditor);

    // TODO: fix this -- no need to know anything about actual data
    // representation
    var nodes = YAHOO.util.Selector.query("#resulttable tr td.yui-dt-col-1 a");
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
