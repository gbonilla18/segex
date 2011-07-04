function populateSelectFilterStudy() {

    var obj = document.getElementById("study");
    var pid_object = document.getElementById("platform");

    var pid = pid_object.options[pid_object.selectedIndex].value;

    // first remove all existing option elements
    //
    while (obj.options[0]) {
        obj.removeChild(obj.options[0]);
    }

    //Add 'Unassigned Studies' option
    var opt_unassigned = document.createElement("option");
    opt_unassigned.setAttribute('value', '');
    opt_unassigned.innerHTML = 'Unassigned Studies';
    obj.appendChild(opt_unassigned);			

    //Add 'All Studies' option
    var opt_all = document.createElement("option");
    opt_all.setAttribute('value', 'all');
    opt_all.innerHTML = 'All Studies';
    obj.appendChild(opt_all);

    //Add other options
    for (var i in studies) {
        // Only add the ones that are in the platform we selected.
        if (pid === '' || studies[i][1] === pid )
        {
            var opt_new = document.createElement("option");
            opt_new.setAttribute('value', i);
            opt_new.innerHTML = studies[i][0];
            obj.appendChild(opt_new);
        }
    }
}

if (show_table) {
    YAHOO.util.Event.addListener("StudyTable_astext", "click", export_table, JSStudyList, true);
}

YAHOO.util.Event.addListener("platform", "change", populateSelectFilterStudy);
YAHOO.util.Event.addListener(window, "load", function() {
    populateSelectFilterStudy();

    /**** Everything below applies only when tables are shown ****/

    if (show_table) {
        function createCellEditor(postBackURL, postBackQueryParameters) {
            return new YAHOO.widget.TextareaCellEditor({
                disableBtns: false,
                asyncSubmitter: function(callback, newValue) {
                    var record = this.getRecord();
                    //var column = this.getColumn();
                    //var datatable = this.getDataTable();
                    if (this.value === newValue) { callback(); }
                    YAHOO.util.Connect.asyncRequest("POST", postBackURL, {
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
                    }, postBackQueryParameters(newValue, record));
                }
            });
        }

        YAHOO.widget.DataTable.Formatter.formatExperimentDeleteLink = 
            function(elCell, oRecord, oColumn, oData) {
                if(oRecord.getData("9") == '') {
                    elCell.innerHTML = '<a title="Delete this experiment and its associated data from the database" onclick="return deleteConfirmation();" target="_self" href="' + deleteURL + oData + '">Delete</a>';
                } else {
                    elCell.innerHTML = '<a title="Unassign this experiment from all studies" onclick="return deleteConfirmation({ itemName: \\"experiment\\" });" target="_self" href="' + deleteURL + oData + "&deleteFrom=" + encodeURI(oRecord.getData("9")) + '\">Unassign</a>';
                }
        };

        YAHOO.util.Dom.get("caption").innerHTML = JSStudyList.caption;
        var myColumnDefs = [
            {key:"3", sortable:true, resizeable:true, 
                label:"No."},
            {key:"0", sortable:true, resizeable:true, 
                label:"Sample 1", editor:createCellEditor(
                        url_prefix + "?a=updateCell",
                        function(newValue, record) {
                            return "type=experimentSamples" 
                                 + "&S1=" + escape(newValue) 
                                 + "&S2=" + encodeURI(record.getData("1")) 
                                 + "&eid=" + encodeURI(record.getData("3"));
                        }
                    )
                },
            {key:"1", sortable:true, resizeable:true, 
                label:"Sample 2",editor:createCellEditor(
                        url_prefix + "?a=updateCell",
                        function(newValue, record) {
                            return "type=experimentSamples"
                                 + "&S1=" + encodeURI(record.getData("0")) 
                                 + "&S2=" + escape(newValue) 
                                 + "&eid=" + encodeURI(record.getData("3"));
                        }
                    )
                },
            {key:"2", sortable:true, resizeable:true, 
                label:"Probe Count"},
            {key:"5", sortable:false, resizeable:true, 
                label:"Experiment Description",editor:createCellEditor(
                        url_prefix + "?a=updateCell",
                        function(newValue, record) {
                            return "type=experiment"
                                 + "&desc=" + escape(newValue) 
                                 + "&add=" + encodeURI(record.getData("6")) 
                                 + "&eid=" + encodeURI(record.getData("3"));
                        }
                    )
                },
            {key:"6", sortable:false, resizeable:true, 
                label:"Additional Information",editor:createCellEditor(
                        url_prefix + "?a=updateCell",
                        function(newValue, record) {
                            return "type=experiment"
                                 + "&desc=" + encodeURI(record.getData("5")) + 
                                 + "&add=" + escape(newValue) 
                                 + "&eid=" + encodeURI(record.getData("3"));
                        }
                    )
                },
            {key:"3", sortable:false, resizeable:true, 
                label:"Unassign\/Delete",formatter:"formatExperimentDeleteLink"},
            {key:"7", sortable:true, resizeable:true, 
                label:"Study Description"},
            {key:"8", sortable:true, resizeable:true, 
                label:"Platform Name"}
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
