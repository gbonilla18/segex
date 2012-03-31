;(function () {

"use strict";

/*
* Note: the following NCBI search shows only genes specific to a given species:
* http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=gene&term=Cyp2a12+AND+mouse[ORGN]
*/

var dom = YAHOO.util.Dom;
var formatter = YAHOO.widget.DataTable.Formatter;

function buildSVGElement(obj) {
    var resourceURI = object_forEach(obj, function(key, val) {
        this.push(key + '=' + encodeURIComponent(val));
    }, ['./?a=graph']).join('&');

    // another alternative to the code below
    //var object = document.createElement('img');
    //object.setAttribute('src', resourceURI);
    //return object;

    var object = document.createElement('object');
    object.setAttribute('type', 'image/svg+xml');
    object.setAttribute('data', resourceURI);
    var embed = document.createElement('embed');
    embed.setAttribute('type', 'image/svg+xml');
    embed.setAttribute('src', resourceURI);
    object.appendChild(embed);

    // resize object after loading to work around Safari resizing bug
    YAHOO.util.Event.addListener(object, 'load', function() {
        var svgAttr = dom.getFirstChildBy(
            this.contentDocument,
            function(el) { return (el.nodeName === 'svg'); }
        ).attributes;
        var newHeight = parseInt(svgAttr.height.value, 10);
        if (this.offsetHeight !== newHeight) {
            this.setAttribute('height', newHeight);
        }
        var newWidth = parseInt(svgAttr.width.value, 10);
        if (this.offsetWidth !== newWidth) {
            this.setAttribute('width', newWidth);
        }
    });
    return object;
}

// graph manager class
function Graphs(id) {
    this.graph_ul = dom.get(id);
    this.graph_content = [];
    this.addToModel = function(li_id, svgObjAttr) {
        var li = document.createElement('li');
        li.setAttribute('id', li_id);
        li.appendChild(buildSVGElement(svgObjAttr));
        this.graph_content.push(li);
        return true;
    };
    this.purgeModel = function() {
        forEach(this.graph_content, function(el) {
            YAHOO.util.Event.purgeElement(el, false);
        });
        this.graph_content.length = 0;
        return true;
    };
    this.render = function() {
        // remove all existing DOM nodes
        removeAllChildren(this.graph_ul);

        // add new ones from the model
        var graph_ul = this.graph_ul;
        forEach(this.graph_content, function(el) {
            graph_ul.appendChild(el);
        });
    };
}

YAHOO.util.Event.addListener("resulttable_astext", "click", export_table, data, true);
YAHOO.util.Event.addListener("get_csv", "submit", function(o) {

    // get first elements of data.records tuples -- those are Probe IDs
    dom.get("q").value = forEach(data.records, function(row) {
        this.push(row[0]);
    }, []).join(',');

    dom.get("q_old").value = queryText;
    dom.get("scope_old").value = scope;
    dom.get("match_old").value = match;
    return true;
}, null, false);

YAHOO.util.Event.addListener(window, "load", function() {

    var queriedPhrases = 
        (match === 'Full-Word') ?  splitIntoPhrases(queryText) : queryText.split(/[,\s]+/);
    var regex_obj = (function() {
        if (queriedPhrases.length === 0) {
            return null;
        }
        var joined = 
            (queriedPhrases.length > 1) ? '(?:' + queriedPhrases.join('|') + ')' : queriedPhrases.join('|');
        var bounds = {
            'Prefix':    ['\\b',  '\\w*'],
            'Full-Word': ['\\b',  '\\b' ],
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

    var highlightWords = (regex_obj !== null) ? function(x) {
            return x.replace(regex_obj, function(v) { 
                return '<span class="highlight">' + v + '</span>';
            });
        } : function(x) {
            return x;
        };

    dom.get("caption").innerHTML = data.caption;

    // extra_fields >= 0
    var dataFields = { rid: "0" };
    var myColumnList = [{key:"0", parser:"number"}];
    var myColumnDefs = [];

    var columns2highlight = {
        'GO IDs'               : { },
        'Probe IDs'            : { '2' : 1 },
        'Genes/Accession Nos.' : { '5' : 1, '6' : 1 },
        'Gene Names/Desc.'     : { '6' : 1, '9' : 1 }
    };
    var currScope = columns2highlight[scope];

    // extra_fields > 0
    if (extra_fields > 0) {
        dataFields.species = '3';
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
    function wrapAccNum(b, highlight, args) {
        var species = args[0];
        if (b.match(/^ENS[A-Z]{0,4}\d{11}$/i)) {
            return "<a " + highlight + " title=\"Search Ensembl for " + b + "\" target=\"_blank\" href=\"http://www.ensembl.org/Search/Summary?species=all;q=" + b + "\">" + b + "</a>";
        } else {
            return "<a " + highlight + " title=\"Search NCBI Nucleotide for " + b + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=Nucleotide&term=" + species + "[ORGN]+AND+" + b + "[ACCN]\">" + b + "</a>";
        }
    }
    function wrapGeneSymbol(b, highlight, args) {
        var species = args[0];
        var gsymbol = b;
        if (b.match(/^ENS[A-Z]{0,4}\d{11}$/i)) {
            return "<a " + highlight + " title=\"Search Ensembl for " + b + "\" target=\"_blank\" href=\"http://www.ensembl.org/Search/Summary?species=all;q=" + b + "\">" + b + "</a>";
        } else if (b.match(/^\d+$/)) {
            return "<a " + highlight + " title=\"Search NCBI Gene for " + b + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/gene?term=" + b + "[uid]\">" + b + "</a>";
        } else if (b.match(/^\w+_similar_to/)) {
            gsymbol = /^(\w+)_similar_to/.exec(b)[1];
        }
        return "<a " + highlight + " title=\"Search NCBI Gene for " + gsymbol + "\" target=\"_blank\" href=\"http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=gene&term=" + species + "[ORGN]+AND+" + gsymbol + "[GENE]\">" + b + "</a>";
    }

    function formatSymbols(symbol, colKey, wrapperFun, args) {
        var doMatch = currScope.hasOwnProperty(colKey) && regex_obj !== null;

        // split by commas while removing spaces, process, then join on commas
        return forEach(symbol.split(/[,\s]+/), function(val) {
            var higlightString = (doMatch && val.match(regex_obj)) ? 'class="highlight"' : '';
            this.push(wrapperFun(val, higlightString, args));
        }, []).join(', ');
    }

    var graphs = null;
    var manager = null;
    if (show_graphs === '') {
        // do not show graphs below the table (only show them within panels)
        manager = new YAHOO.widget.OverlayManager();
    } else {
        // show graphs below the table
        graphs = new Graphs('graphs');
    }

    formatter.formatProbe = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            var i = oRecord.getCount();
            var this_rid = oRecord.getData(dataFields.rid);

            var a = document.createElement("a");
            if (currScope.hasOwnProperty(oColumn.key) && regex_obj !== null && oData.match(regex_obj)) {
                a.setAttribute('class', 'highlight');
            }
            a.setAttribute('title', 'Show differental expression graph');
            a.appendChild(document.createTextNode(oData));

            if (graphs !== null) {
                var graphId = 'reporter_' + i;
                graphs.addToModel(
                    graphId,
                    { proj: project_id, rid: this_rid, reporter: oData, trans: show_graphs }
                );
                a.setAttribute('href', '#' + graphId);
            } else if (manager !== null) {

                // Set up SVG pop-up panel
                var panelID = "panel" + i;
                manager.remove(panelID);
                YAHOO.util.Event.addListener(a, 'click', function() {

                    // first see if the panel already exists
                    var panel = manager.find(panelID);
                    if (panel !== null) {
                        // toggle panel visibility
                        if (panel.cfg.getProperty('visible')) {
                            panel.hide();
                        } else {
                            panel.show();
                        }
                        return;
                    }

                    // if not, create a new panel
                    panel = new YAHOO.widget.Panel(panelID, {
                        close:true, visible:true, draggable:true, fixedcenter: false,
                        constraintoviewport:false, context:[elCell, "tl", "tr"]
                    });
                    dom.addClass(panel.element, 'graph-panel');
                    panel.setHeader(oData);
                    panel.setBody(buildSVGElement({
                        proj: project_id, rid: this_rid, reporter: oData,
                        trans: show_graphs
                    }));

                    // Call register() and render() only. Calling show() is
                    // unnecessary here because visible:true has already
                    // been set during initialization.
                    manager.register(panel);
                    panel.render(elCell);
                });
            }
            elCell.appendChild(a);
        }
    };
    formatter.formatAccNum = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            var species = oRecord.getData(dataFields.species);
            elCell.innerHTML = formatSymbols(oData, oColumn.key, wrapAccNum, [species]);
        }
    };
    formatter.formatGene = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            var species = oRecord.getData(dataFields.species);
            elCell.innerHTML = formatSymbols(oData, oColumn.key, wrapGeneSymbol, [species]);
        }
    };
    formatter.formatGeneName = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            elCell.innerHTML = currScope.hasOwnProperty(oColumn.key) ? highlightWords(oData) : oData;
        }
    };
    formatter.formatPlatform = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            var species = oRecord.getData(dataFields.species);
            elCell.innerHTML = (oData.match(new RegExp('^' + species))) ? oData : species + ' / ' + oData;
        }
    };
    formatter.formatSequence = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            dom.addClass(elCell, 'sgx-dt-sequence');
            var species = oRecord.getData(dataFields.species);
            elCell.innerHTML = "<a href=\"http://genome.ucsc.edu/cgi-bin/hgBlat?userSeq=" + oData + "&type=DNA&org=" + species + "\" title=\"Search for this sequence using BLAT in " + species + " genome (genome.ucsc.edu)\" target=\"_blank\">" + oData + "</a>";
        }
    };

    var myDataSource = new YAHOO.util.DataSource(data.records);
    myDataSource.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    myDataSource.responseSchema = { fields: myColumnList };

    var myData_config = {
        paginator: new YAHOO.widget.Paginator({
            rowsPerPage: 15 
        })
    };

    var myDataTable = new YAHOO.widget.DataTable(
        "resulttable", myColumnDefs, myDataSource, myData_config
    );

    if (graphs !== null) {
        // TODO: Ideally, use a "pre-formatter" event to clear graph_content
        myDataTable.doBeforeSortColumn = function(oColumn, sSortDir) {
            graphs.purgeModel();
            return true;
        };
        myDataTable.doBeforePaginatorChange = function(oPaginatorState) {
            graphs.purgeModel();
            return true;
        };
        myDataTable.subscribe("renderEvent", function () { graphs.render(); });
    }

});

}());
