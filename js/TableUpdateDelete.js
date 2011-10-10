/* depends on the following YUI files:
*
* build/yahoo-dom-event/yahoo-dom-event.js
* build/connection/connection_core-min.js
* build/element/element-min.js
* build/datasource/datasource-min.js
* build/datatable/datatable-min.js
*
*/

var highlightEditableCell = function(oArgs) { 
    var elCell = oArgs.target; 
    if (YAHOO.util.Dom.hasClass(elCell, "yui-dt-editable")) { 
        this.highlightCell(elCell); 
    } 
};

function createCellUpdater(field, resourceURIBuilder, updateDataBuilder, rowNameBuilder) {
    var submitter = function(callback, newValue) {
        if (this.value === newValue) { 
            // existing value is the same as the new one -- no need to send 
            // POST request
            callback(true, newValue); 
            return; 
        }
        var record = this.getRecord();
        var resourceURI = resourceURIBuilder(record);
        var callbackObject = {
            success:function(o) { 
                // simply update cell, then do nothing
                callback(true, newValue); 
            },
            failure:function(o) { 
                callback(); 
                var name = rowNameBuilder(record);
                if(o.responseText !== undefined) {
                    alert("Error encountered on updating record (" + name + ") under " + resourceURI +".\nServer responded with code " + o.status + " (" + o.statusText + ").");
                } else {
                    alert("Timeout on updating record (" + name + ") under " + resourceURI);
                }
            },
            scope:this
        };
        YAHOO.util.Connect.asyncRequest(
            "POST", 
            resourceURI,
            callbackObject, 
            updateDataBuilder(field, newValue)
        );
    };
    return new YAHOO.widget.TextareaCellEditor({
        disableBtns: false,
        asyncSubmitter: submitter
    });
}
function cellUpdater(resourceURIBuilder, rowNameBuilder) {
    return function(field) {
        /* uses createCellUpdater in TableUpdateDelete.js */
        var updateDataBuilder = function(field, newValue) {
            return "b=ajax_update&" + field + "=" + encodeURIComponent(newValue);
        };
        return createCellUpdater(field, resourceURIBuilder, updateDataBuilder, rowNameBuilder);
    };
}

function createEditFormatter(verb, noun, resourceURIBuilder) {
    var cellContent_part1 = '<a title="' + verb + ' this ' + noun + '" href="';
    var cellContent_part2 = '">' + verb + '</a>';
    return function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = cellContent_part1 + resourceURIBuilder(oRecord) + cellContent_part2;
    };
}

function createRowDeleter(buttonValue, resourceURIBuilder, deleteDataBuilder, rowNameBuilder) {
    var verb = buttonValue.toLowerCase();

    var handleSuccess = function(o) {
        // simply delete row, then do nothing
        var record = o.argument[0];
        this.deleteRow(record);
    };

    var handleFailure = function(o) {
        var record = o.argument[0];
        var name = rowNameBuilder(record);
        if(o.responseText !== undefined) {
            alert("Error encountered when attempting to " + verb + " record (" + name + ") from " + resourceURIBuilder(record) +".\nServer responded with code " + o.status + " (" + o.statusText + ").");
        } else {
            alert("Timeout when attempting to " + verb + " record (" + name + ") from " + resourceURIBuilder(record));
        }
    };

    return function(ev) {
        var target = YAHOO.util.Event.getTarget(ev);
        if (target.innerHTML !== buttonValue) { return false; }
        var record = this.getRecord(target);

        // strip double and single quotes from row name
        var name = rowNameBuilder(record);
        var resourceURI = resourceURIBuilder(record);
        if (!confirm("Are you sure you want to " + verb + " '" + name + "' from " + resourceURI + "?")) { return false; }

        var callbackObject = {
            success:handleSuccess,
            failure:handleFailure,
            argument:[record],
            scope:this
        };
        YAHOO.util.Connect.asyncRequest(
            'POST', 
            resourceURI, 
            callbackObject,
            deleteDataBuilder(record)
        );
        return true;
    };
}

function createDeleteDataBuilder(oArg) {
    var keys = (typeof oArg !== "undefined" && typeof oArg.key !== "undefined") 
    ? oArg.key
    : {};
    var tableData = (typeof oArg !== "undefined" && typeof oArg.table !== "undefined") 
    ? "&table=" + oArg.table
    : "";
    return function(oRecord) {
        var data = "b=ajax_delete" + tableData;
        for (var key in keys) {
            data += "&" + key + "=" + encodeURIComponent(oRecord.getData(keys[key]));
        }
        return data;
    };
}

function createDeleteFormatter(verb, noun) {
    var cellContent = '<button title="' + verb + ' this ' + noun + '" class="plaintext">' + verb + '</button>';
    return function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = cellContent;
    };
}
function createJoinFormatter(table_info, field, joinColumn) {
    var sub_col = table_info.symbol2index[field] - 1;
    return function(elCell, oRecord, oColumn, oData) {
        var sub_record = table_info.data[oRecord.getData(joinColumn)];
        elCell.innerHTML = sub_record[sub_col];
    };
}

function createResourceURIBuilder(uriPrefix, columnMapping) {
    return function (oRecord) {
        var resourceURI = uriPrefix;
        if (typeof columnMapping !== "undefined") {
            for (var key in columnMapping) {
                resourceURI += "&" + key + "=" + encodeURIComponent(oRecord.getData(columnMapping[key]));
            }
        }
        return resourceURI;
    };
}

function createRowNameBuilder(nameColumns) {
    function getCleanFieldValue(oRecord, field) {
        /* getData() takes name of column that contains record names */
        return oRecord.getData(field).replace('"', "").replace("'","");
    }
    return function (oRecord) {
        var names = [];
        for (var i = 0, len = nameColumns.length; i < len; i++) {
            names.push(getCleanFieldValue(oRecord, nameColumns[i]));
        }
        return names.join(" / ");
    };
}

function subscribeEnMasse(el, obj) {
    for (var event in obj) {
        var handler = obj[event];
        el.subscribe(event, handler);
    }
}
