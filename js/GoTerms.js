"use strict";

var dom = YAHOO.util.Dom;
YAHOO.util.Event.addListener("resulttable_astext", "click", export_table, data, true);

// MODEL -- has to be restored from "q" element when page loads
var buf = {};

// VIEW
var myDataTable;

var SELECT_ALL = 'Select all';
var UNSELECT_ALL = 'Unselect all';

YAHOO.util.Event.addListener("resulttable_selectall", "click", function(o) {
    var rec = data.records;
    var len = rec.length;
    var text = this.innerHTML;
    if (text === SELECT_ALL) {

        // select all rows
        for (var i = 0; i < len; i++) {
            buf[rec[i][0]] = null;
        }
        this.innerHTML = UNSELECT_ALL;
    } else {

        // unselect all rows
        object_clear(buf);
        this.innerHTML = SELECT_ALL;
    }
    myDataTable.render();
}, null, false);

YAHOO.util.Event.addListener("main_form", "submit", function(o) {
    dom.get("q").value = object_keys(buf).join(',');
    return true;
}, null, false);

YAHOO.util.Event.addListener(window, "load", function() {
    // split on words (but do not split on colons)
    object_add(buf, 
        dom.get("q").value.
        replace(/^\W*/, '').
        replace(/\W*$/, '').
        split(/[^\w^:]+/), null);
    var selectAll = dom.get("resulttable_selectall");
    dom.get("caption").innerHTML = data.caption;

    var queriedPhrases = splitIntoPhrases(queryText);
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

    // checkbox formatter
    YAHOO.widget.DataTable.Formatter.formatGOCheck = function(elCell, oRecord, oColumn, oData) {
        // remove all children nodes if any exist
        if ( elCell.hasChildNodes() ) {
            while ( elCell.childNodes.length > 0 ) {
                elCell.removeChild( elCell.firstChild );
            } 
        }
        var parentTR = getFirstParentOfName(elCell, 'TR');

        var label = document.createElement('label');
        dom.addClass(label, 'nowrap');
        var checkbox = document.createElement('input');
        checkbox.type = 'checkbox';
        if (oData in buf) {
            checkbox.checked = true;
            dom.addClass(parentTR, 'selected_row');
        } else {
            checkbox.checked = false;
        }
        YAHOO.util.Event.addListener(checkbox, 'change', function() {
            var thisParentTR = getFirstParentOfName(this, 'TR');
            if (this.checked) {
                // add to buffer object
                dom.addClass(parentTR, 'selected_row');
                buf[oData] = null;
                if (object_length(buf) === data.records.length) {
                    selectAll.innerHTML = UNSELECT_ALL;
                }
            } else {
                // remove from buffer object
                dom.removeClass(parentTR, 'selected_row');
                delete buf[oData];
                if (object_length(buf) === 0) {
                    selectAll.innerHTML = SELECT_ALL;
                }
            }
        });
        label.appendChild(checkbox);
        label.appendChild(document.createTextNode('GO:' + zeroPad(oData, 7)));
        elCell.appendChild(label);
    };

    // label formatter: if searching for names only, only highlight names, not
    // descriptions.
    var wrapGONameDesc = (scope === 'GO Names')
        ? function(oData, oRecord) { 
            var goID = 'GO:' + zeroPad(oRecord.getData('0'), 7);
            return '<a target="_blank" title="Search EBI QuickGO database for ' + goID + '" href="http://www.ebi.ac.uk/QuickGO/GTerm?id=' + goID + '" class="TicketName">' + highlightWords(oData) + 
                        '</a><br/><span >' 
                        + oRecord.getData('2') + '</span>' 
            }
        : function(oData, oRecord) { 
            var goID = 'GO:' + zeroPad(oRecord.getData('0'), 7);
            return '<a target="_blank" title="Search EBI QuickGO database for ' + goID + '" href="http://www.ebi.ac.uk/QuickGO/GTerm?id=' + goID + '" class="TicketName">' + highlightWords(oData) + 
                        '</a><br/><span >' 
                        + highlightWords(oRecord.getData('2')) + '</span>' 
            };

    YAHOO.widget.DataTable.Formatter.formatGOName = function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = wrapGONameDesc(oData, oRecord);
    };

    // type formatter: replace all underscores with spaces
    YAHOO.widget.DataTable.Formatter.formatGOType = function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = oData.replace(/_/, ' ');
    };

    var myDataSource = new YAHOO.util.DataSource(data.records);
    myDataSource.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    myDataSource.responseSchema = {
        fields: [
            {key:"0", parser:"number"},
            {key:"1"},
            {key:"2"},
            {key:"3"},
            {key:"4", parser:"number"}
        ]
    };

    var myColumnDefs = [
        {key:"0", sortable:true, resizeable:true,
            parser:'number', label:data.headers[0], formatter:"formatGOCheck"},
        {key:"1", sortable:true, resizeable:true, 
            label:data.headers[1], formatter:"formatGOName"} ,
        {key:"3", sortable:true, resizeable:true, 
            label:data.headers[3], formatter:"formatGOType"},
        {key:"4", sortable:true, resizeable:true,
            parser:'number', label:data.headers[4]},
    ];

    var myData_config = {
        paginator: new YAHOO.widget.Paginator({
            rowsPerPage: 15 
        })
    };

    myDataTable = new YAHOO.widget.DataTable(
    "resulttable", myColumnDefs, myDataSource, myData_config);

});
