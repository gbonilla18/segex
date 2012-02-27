"use strict";

function zeroPad(num, places) {
    var zero = places - num.toString().length + 1;
    return Array(+(zero > 0 && zero)).join("0") + num;
}

var dom = YAHOO.util.Dom;
YAHOO.util.Event.addListener(window, "load", function() {
    YAHOO.widget.DataTable.Formatter.formatGOCheck = function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = '<label><input type="checkbox" name="q" value="' + oData + '"/>' 
                            + 'GO:' + zeroPad(oData, 7) + '</label>';
    };
    YAHOO.widget.DataTable.Formatter.formatGOType = function(elCell, oRecord, oColumn, oData) {

        // replace all underscores with spaces
        elCell.innerHTML = oData.replace(/_/, ' ');
    };
    YAHOO.widget.DataTable.Formatter.formatGOName = function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = '<strong>' + oData + '</strong><br/><span class="fadeout">' 
                            + oRecord.getData('2') + '</span>';
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

    var myDataTable = new YAHOO.widget.DataTable(
    "resulttable", myColumnDefs, myDataSource, myData_config);

});
