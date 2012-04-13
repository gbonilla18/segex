;(function () {

"use strict";

/*
* Note: the following NCBI search shows only genes specific to a given species:
* http://www.ncbi.nlm.nih.gov/sites/entrez?cmd=search&db=gene&term=Cyp2a12+AND+mouse[ORGN]
*/

var dom = YAHOO.util.Dom;
var formatter = YAHOO.widget.DataTable.Formatter;

function buildSVGElement(obj) {
    var resourceURI = './?' +
    object_forEach(obj, function(key, val) {
        this.push(key + '=' + encodeURIComponent(val));
    }, [ 'a=graph' ]).join('&');

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
        var svg = dom.getFirstChildBy(
            this.contentDocument,
            function(el) { return (el.nodeName === 'svg'); }
        );
        if (svg) { 
            // Found SVG inside
            var svgAttr = svg.attributes;
            var newHeight = parseInt(svgAttr.height.value, 10);
            if (this.offsetHeight !== newHeight) {
                this.setAttribute('height', newHeight);
            }
            var newWidth = parseInt(svgAttr.width.value, 10);
            if (this.offsetWidth !== newWidth) {
                this.setAttribute('width', newWidth);
            }
            return true;
        } else {
            // no SVG -- probably error page returned
            removeAllChildren(this.contentDocument);
            this.setAttribute('height', 0);
            this.setAttribute('width', 0);
            return false;
        }
    });
    return object;
}

// graph manager class
function Graphs(id) {
    this.graph_container = dom.get(id);
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
        removeAllChildren(this.graph_container);

        // add new ones from the model
        this.graph_container.appendChild(
            forEach(
                this.graph_content, 
                function(el) { this.appendChild(el); }, 
                document.createElement("ul")
            )
        );
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
    var formatProbe = function(elCell, oRecord, oColumn, oData) {
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
            removeAllChildren(elCell);
            elCell.appendChild(a);
        } else {
            elCell.innerHTML = ''
        }
    };
    var formatAccNum = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            var species = oRecord.getData(dataFields.species);
            var slatin = oRecord.getData(dataFields.slatin);
            elCell.innerHTML = formatSymbols(oData, oColumn.key, wrapAccNum, [species, slatin]);
        } else {
            elCell.innerHTML = ''
        }
    };
    var formatGene = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            var species = oRecord.getData(dataFields.species);
            var slatin = oRecord.getData(dataFields.slatin);
            elCell.innerHTML = formatSymbols(oData, oColumn.key, wrapGeneSymbol, [species, slatin]);
        } else {
            elCell.innerHTML = ''
        }
    };
    var formatGeneName = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            elCell.innerHTML = currScope.hasOwnProperty(oColumn.key) ? highlightWords(oData) : oData;
        } else {
            elCell.innerHTML = ''
        }
    };
    var formatPlatform = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            var species = oRecord.getData(dataFields.species);
            elCell.innerHTML = (oData.match(new RegExp('^' + species))) ? oData : species + ' / ' + oData;
        } else {
            elCell.innerHTML = ''
        }
    };
    var formatSequence = function(elCell, oRecord, oColumn, oData) {
        if (oData !== null) {
            dom.addClass(elCell, 'sgx-dt-sequence');
            var organism = oRecord.getData(dataFields.species);
            var uri = 'http://genome.ucsc.edu/cgi-bin/hgBlat?' +
            object_forEach({
                userSeq : oData,
                type    : 'DNA',
                org     : organism
            }, function(key, val) {
                this.push(key + '=' + encodeURIComponent(val));
            }, []).join('&');

            elCell.innerHTML = '<a class="external" href="' + uri + '" title="Map this sequence to ' + organism + ' genome with BLAT (genome.ucsc.edu)" target="_blank">' + oData + '</a>';
        } else {
            elCell.innerHTML = '';
        }
    };

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
    var dataFields = forEach(
        ['rid'],
        function(val) { this.self[val] = String(this.index++) },
        { self: {}, index: countOwnProperties({}) }
    ).self;
    var myColumnList = [{key:dataFields.rid, parser:"number"}];
    var myColumnDefs = [];

    // extra_fields > 0
    if (extra_fields > 0) {
        forEach(
            ['pid', 'reporter', 'species', 'slatin', 'platform_name', 'accnum', 'gsymbol'],
            function(val) { this.self[val] = String(this.index++) },
            { self: dataFields, index: countOwnProperties(dataFields) }
        );
        myColumnList.push(
            {key:dataFields.pid, parser:"number"},
            {key:dataFields.reporter},
            {key:dataFields.species},
            {key:dataFields.slatin},
            {key:dataFields.platform_name},
            {key:dataFields.accnum},
            {key:dataFields.gsymbol}
        );
        myColumnDefs.push(
            {key:dataFields.platform_name, sortable:true, resizeable:true, 
                label:data.headers[parseInt(dataFields.platform_name)], formatter:formatPlatform},
            {key:dataFields.reporter, sortable:true, resizeable:true, 
                label:data.headers[parseInt(dataFields.reporter)], formatter:formatProbe}
        );
        if (extra_fields > 1) {
            forEach(
                ['probe_sequence', 'locus', 'gene_name'],
                function(val) { this.self[val] = String(this.index++) },
                { self: dataFields, index: countOwnProperties(dataFields) }
            );
            myColumnList.push(
                {key:dataFields.probe_sequence},
                {key:dataFields.locus}
            );
            myColumnDefs.push(
                {key:dataFields.probe_sequence, sortable:true, resizeable:true,
                    label:data.headers[parseInt(dataFields.probe_sequence)], formatter:formatSequence},
                {key:dataFields.locus, sortable:true, resizeable:true,
                    label:data.headers[parseInt(dataFields.locus)]}
            );
        }
        myColumnDefs.push(
            {key:dataFields.accnum, sortable:true, resizeable:true, 
                label:data.headers[parseInt(dataFields.accnum)], formatter:formatAccNum}, 
            {key:dataFields.gsymbol, sortable:true, resizeable:true, 
                label:data.headers[parseInt(dataFields.gsymbol)], formatter:formatGene}
        );
        if (extra_fields > 1) {
            myColumnList.push(
                {key:dataFields.gene_name}
            );
            myColumnDefs.push(
                {key:dataFields.gene_name, sortable:true, resizeable:true, 
                    label:data.headers[parseInt(dataFields.gene_name)], formatter:formatGeneName}
            );
        }
    }
    var columns2highlight = {
      'GO IDs'               : { },
      'Probe IDs'            : tuplesToObj([dataFields.reporter, null]),
      'Genes/Accession Nos.' : tuplesToObj([dataFields.accnum, null], [dataFields.gsymbol, null]),
      'Gene Names/Desc.'     : tuplesToObj([dataFields.gsymbol, null], [dataFields.gene_name, null])
    };
    var currScope = columns2highlight[scope];

    // =======================================================================
    function wrapAccNum(b, classString, args) {
        var uri, database;
        var organism = args[0];
        var organism_latin = args[1];
        if (organism_latin !== null) {
            organism_latin = organism_latin.split(/\s+/).join('_');
        }

        if (b.match(/^ENS[A-Z]{0,4}\d{11}$/i)) {
            // Ensembl IDs have a very specific format
            database = 'Ensembl';
            uri = 'http://www.ensembl.org/Search/Details?' + 
            object_forEach({
                idx     : 'Gene',
                q       : b,
                species : (organism_latin === null ? 'all' : organism_latin)
            }, function(key, val) {
                this.push(key + '=' + encodeURIComponent(val));
            }, []).join('&');
        } else {
            // Search for everything else in NCBI/Entrez Nucleotide
            database = 'NCBI Nucleotide';
            uri = 'http://www.ncbi.nlm.nih.gov/sites/entrez?' + 
            object_forEach({
                cmd  : 'search',
                db   : 'Nucleotide',
                term : b + '[ACCN] AND ' + organism + '[ORGN]'
            }, function(key, val) {
                this.push(key + '=' + encodeURIComponent(val));
            }, []).join('&');
        }
        var classTuple = 'class="external"';
        if (classString !== null && classString !== '') {
            var classTuple = 'class="external ' + classString + '"';
        }
        return '<a ' + classTuple + ' title="Search ' + database + ' for ' + b + '" target="_blank" href="' + uri + '">' + b + '</a>';
    }

    // =======================================================================
    function wrapGeneSymbol(b, classString, args) {
        var uri, database;
        var organism = args[0];
        var organism_latin = args[1];
        if (organism_latin !== null) {
            organism_latin = organism_latin.split(/\s+/).join('_');
        }

        if (b.match(/^\w+_similar_to/)) {
            // Extract gene symbol from '_similar_to' match
            b = /^(\w+)_similar_to/.exec(b)[1];
        }

        if (b.match(/^ENS[A-Z]{0,4}\d{11}$/i)) {
            // Ensembl IDs have a very specific format
            database = 'Ensembl';
            uri = 'http://www.ensembl.org/Search/Details?' + 
            object_forEach({
                idx     : 'Gene',
                q       : b,
                species : (organism_latin === null ? 'all' : organism_latin)
            }, function(key, val) {
                this.push(key + '=' + encodeURIComponent(val));
            }, []).join('&');
        } else if (b.match(/^\d+$/)) {
            // Search for integer ids in NCBI Gene [uid]
            database = 'NCBI Gene';
            uri = 'http://www.ncbi.nlm.nih.gov/gene?' +
            object_forEach({
                term : b + '[uid]',
            }, function(key, val) {
                this.push(key + '=' + encodeURIComponent(val));
            }, []).join('&');
        } else {
            // Search for everything else in NCBI/Entrez Gene
            database = 'NCBI Gene';
            uri = 'http://www.ncbi.nlm.nih.gov/sites/entrez?' +
            object_forEach({
                cmd  : 'search',
                db   : 'Gene',
                term : b + '[GENE] AND ' + organism + '[ORGN]',
            }, function(key, val) {
                this.push(key + '=' + encodeURIComponent(val));
            }, []).join('&');
        }
        var classTuple = 'class="external"';
        if (classString !== null && classString !== '') {
            var classTuple = 'class="external ' + classString + '"';
        }
        return '<a ' + classTuple + ' title="Search ' + database + ' for ' + b + '" target="_blank" href="' + uri + '">' + b + '</a>';
    }

    // =======================================================================
    function formatSymbols(symbol, colKey, wrapperFun, args) {
        var doMatch = currScope.hasOwnProperty(colKey) && regex_obj !== null;

        // split by commas while removing spaces, process, then join on commas
        return forEach(symbol.split(/[,\s]+/), function(val) {
            var classes = (doMatch && val.match(regex_obj)) ? 'highlight' : '';
            this.push(wrapperFun(val, classes, args));
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
