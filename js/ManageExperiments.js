function populateSelectFilterStudy() {

    var studyDropdown = document.getElementById("study");
    var platformDropdown = document.getElementById("platform");

    // Currently getting current platform from selected option in the Platforms
    // dropdown box. This is bad practice. Need to send current platform as JSON
    // value.
    var pid = platformDropdown.options[platformDropdown.selectedIndex].value;

    // first remove all existing option elements
    //
    while (studyDropdown.options[0]) {
        studyDropdown.removeChild(studyDropdown.options[0]);
    }

    //Add 'Unassigned Studies' option
    var optionUnassigned = document.createElement("option");
    optionUnassigned.setAttribute('value', '');
    optionUnassigned.innerHTML = 'Unassigned';
    studyDropdown.appendChild(optionUnassigned);			

    //Add 'All Studies' option
    var optionAll = document.createElement("option");
    optionAll.setAttribute('value', 'all');
    optionAll.innerHTML = 'All Studies';
    studyDropdown.appendChild(optionAll);

    //Add other options
    for (var i in studies) {
        // Only add the ones that are in the platform we selected.
        if (pid === 'all' || studies[i][1] === pid )
        {
            var option = document.createElement("option");
            option.setAttribute('value', i);
            if (typeof(curr_study) !== 'undefined' && curr_study == i) {
                option.selected = "selected";
            }
            option.innerHTML = studies[i][0];
            studyDropdown.appendChild(option);
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

        var caption = JSStudyList.caption;
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
            {key:"3", sortable:true, resizeable:true, 
                label:"No."},
            {key:"0", sortable:true, resizeable:true, 
                label:"Sample 1", editor:createCellEditor(
                        url_prefix + "?a=manageExperiments",
                        function(newValue, record) {
                            return "b=update&field=sample1"
                                 + "&value=" + escape(newValue) 
                                 + "&id=" + encodeURI(record.getData("3"));
                        }
                    )
                },
            {key:"1", sortable:true, resizeable:true, 
                label:"Sample 2",editor:createCellEditor(
                        url_prefix + "?a=manageExperiments",
                        function(newValue, record) {
                            return "b=update&field=sample2"
                                 + "&value=" + escape(newValue) 
                                 + "&id=" + encodeURI(record.getData("3"));
                        }
                    )
                },
            {key:"2", sortable:true, resizeable:true, 
                label:"Probe Count"},
            {key:"5", sortable:false, resizeable:true, 
                label:"Experiment",editor:createCellEditor(
                        url_prefix + "?a=manageExperiments",
                        function(newValue, record) {
                            return "b=update&field=ExperimentDescription"
                                 + "&value=" + escape(newValue) 
                                 + "&id=" + encodeURI(record.getData("3"));
                        }
                    )
                },
            {key:"6", sortable:false, resizeable:true, 
                label:"Experiment: Additional Info",editor:createCellEditor(
                        url_prefix + "?a=manageExperiments",
                        function(newValue, record) {
                            return "b=update&field=AdditionalInformation"
                                 + "&value=" + escape(newValue) 
                                 + "&id=" + encodeURI(record.getData("3"));
                        }
                    )
                },
            {key:"3", sortable:false, resizeable:true, 
                label:"Unassign\/Delete",formatter:"formatExperimentDeleteLink"},
            {key:"7", sortable:true, resizeable:true, 
                label:"Study"},
            {key:"8", sortable:true, resizeable:true, 
                label:"Platform"}
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
