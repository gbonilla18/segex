
function createExperimentCellUpdater(field) {
    /*
     * this functions makes a hammer after it first builds a factory in the
     * neighborhood that makes hammers using the hammer construction factory
     * spec sheet in CellUpdater.js 
     */
    return createCellUpdater(field, url_prefix + "?a=manageExperiments", "3");
}

if (typeof(JSStudyList) !== 'undefined') {
    YAHOO.util.Event.addListener("StudyTable_astext", "click", export_table, JSStudyList, true);
}

YAHOO.util.Event.addListener(window, "load", function() {
    /**** Everything below applies only when tables are shown ****/

    if (typeof(JSStudyList) !== 'undefined') {
        YAHOO.widget.DataTable.Formatter.formatExperimentDeleteLink = 
        function(elCell, oRecord, oColumn, oData) {
            if(oRecord.getData("9") == '') {
                elCell.innerHTML = '<a title="Delete this experiment and \
its associated data from the database" onclick="return deleteConfirmation();" \
target="_self" href="' + deleteURL + oData + '">Delete</a>';
            } else {
                elCell.innerHTML = '<a title="Unassign this experiment \
from all studies" onclick="return deleteConfirmation(\
{ itemName: \\"experiment\\" });" target="_self" href="' + deleteURL + oData + 
"&deleteFrom=" + encodeURI(oRecord.getData("9")) + '\">Unassign</a>';
            }
        };

        var caption = JSStudyList.caption + ' from: ';
        if (typeof(curr_study) !== 'undefined') {
            if (curr_study === 'all') {
                caption += 'All Studies';
            } else if (curr_study === '') {
                caption += 'Unassigned';
            } else {
                caption += studies[curr_study][0];
            }
        }

        YAHOO.util.Dom.get("caption").innerHTML = caption;
        var myColumnDefs = [
            {key:"3", sortable:true, resizeable:true, label:"#"},
            {key:"0", sortable:true, resizeable:true, label:"Sample 1", editor:createExperimentCellUpdater("sample1")},
            {key:"1", sortable:true, resizeable:true, label:"Sample 2", editor:createExperimentCellUpdater("sample2")},
            {key:"2", sortable:true, resizeable:true, label:"Probe Count"},
            {key:"5", sortable:true, resizeable:true, label:"Experiment", editor:createExperimentCellUpdater("ExperimentDescription")},
            {key:"6", sortable:true, resizeable:true, label:"Experiment: Additional Info", editor:createExperimentCellUpdater("AdditionalInformation")},
            {key:"3", sortable:false, resizeable:true, label:"Unassign\/Delete", formatter:"formatExperimentDeleteLink"},
            {key:"7", sortable:true, resizeable:true, label:"Study"},
            {key:"8", sortable:true, resizeable:true, label:"Platform"}
        ];

        var myDataSource = new YAHOO.util.DataSource(JSStudyList.records);
        myDataSource.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
        myDataSource.responseSchema = 
        {fields: ["0","1","2","3","4","5","6","7","8","9"]};
        var myData_config = {
            paginator: new YAHOO.widget.Paginator({rowsPerPage: 50})
        };
        var myDataTable = new YAHOO.widget.DataTable(
        "StudyTable", myColumnDefs, myDataSource, myData_config);

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
    }
});
