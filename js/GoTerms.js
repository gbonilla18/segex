"use strict";

// BEGIN generic functions (to move to another module)
function zeroPad(num, places) {
    var zero = places - num.toString().length + 1;
    return Array(+(zero > 0 && zero)).join("0") + num;
}
function object_length(obj) {
    var size = 0, key;
    for (key in obj) {
        if (obj.hasOwnProperty(key)) size++;
    }
    return size;
}
function object_keys(obj) {
    var ret = [];
    for (var key in obj) {
        if (obj.hasOwnProperty(key)) {
            ret.push(key);
        }
    }
    return ret;
}
function object_clear(obj) {
    for (var key in obj) {
        if (obj.hasOwnProperty(key)) {
            delete obj[key];
        }
    }
    return obj;
}
// END generic functions


var dom = YAHOO.util.Dom;
YAHOO.util.Event.addListener("resulttable_astext", "click", export_table, data, true);

// MODEL
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
    var selectAll = dom.get("resulttable_selectall");

    dom.get("caption").innerHTML = data.caption;

    // checkbox formatter
    YAHOO.widget.DataTable.Formatter.formatGOCheck = function(elCell, oRecord, oColumn, oData) {
        // remove all children nodes if any exist
        if ( elCell.hasChildNodes() ) {
            while ( elCell.childNodes.length > 0 ) {
                elCell.removeChild( elCell.firstChild );
            } 
        }
        var label = document.createElement('label');
        dom.addClass(label, 'nowrap');
        var checkbox = document.createElement('input');
        checkbox.type = 'checkbox';
        checkbox.checked = (oData in buf);
        YAHOO.util.Event.addListener(checkbox, 'change', function() {
            if (this.checked) {
                // add to buffer object
                buf[oData] = null;
                if (object_length(buf) === data.records.length) {
                    selectAll.innerHTML = UNSELECT_ALL;
                }
            } else {
                // remove from buffer object
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

    // label formatter
    YAHOO.widget.DataTable.Formatter.formatGOName = function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = '<span class="TicketName">' + oData + 
                            '</span><br/><span class="fadeout">' 
                            + oRecord.getData('2') + '</span>';
    };

    // type formatter
    YAHOO.widget.DataTable.Formatter.formatGOType = function(elCell, oRecord, oColumn, oData) {

        // replace all underscores with spaces
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
