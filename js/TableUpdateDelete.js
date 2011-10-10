/* depends on the following YUI files:
*
* build/yahoo-dom-event/yahoo-dom-event.js
* build/connection/connection_core-min.js
* build/element/element-min.js
* build/datasource/datasource-min.js
* build/datatable/datatable-min.js
*
*/

function highlightEditableCell(oArgs) { 
    var elCell = oArgs.target; 
    if (YAHOO.util.Dom.hasClass(elCell, "yui-dt-editable")) { 
        this.highlightCell(elCell); 
    } 
};
function createCellDropdown(transformed_data, field, resourceURIBuilder, updateDataBuilder, rowNameBuilder) {
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
                // update other joined fields:
                // http://developer.yahoo.com/yui/docs/YAHOO.widget.DataTable.html#method_updateCell

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
    return new YAHOO.widget.DropdownCellEditor({
        dropdownOptions:transformed_data,
        disableBtns: false,
        asyncSubmitter: submitter
    });
}
function cellDropdown(resourceURIBuilder, rowNameBuilder) {
    return function(table_info, field, subName) {
        var updateDataBuilder = function(field, newValue) {
            return "b=ajax_update&" + field + "=" + encodeURIComponent(newValue);
        };
        var transformed_data = [];
        var this_data = table_info.data;
        var sub_col = table_info.symbol2index[subName] - 1;
        for (var key in table_info.data) {
            var val = this_data[key][sub_col];
            transformed_data.push({ label: val, value: key});
        }
        return createCellDropdown(transformed_data, field, resourceURIBuilder, updateDataBuilder, rowNameBuilder);
    };
}
function cellDropdownDirect(resourceURIBuilder, rowNameBuilder) {
    return function(field, rename_array) {
        var updateDataBuilder = function(field, newValue) {
            return "b=ajax_update&" + field + "=" + encodeURIComponent(newValue);
        };
        return createCellDropdown(rename_array, field, resourceURIBuilder, updateDataBuilder, rowNameBuilder);
    };
}
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
function createJoinFormatter(table_info, field) {
    var sub_col = table_info.symbol2index[field] - 1;
    return function(elCell, oRecord, oColumn, oData) {

        // this also gets executed after we update a cell via AJAX
        var sub_record = table_info.data[oData];
        elCell.innerHTML = (typeof sub_record !== "undefined") ? sub_record[sub_col] : '';
    };
}
function createRenameFormatter(rename_array) {
    var rename_hash = {};
    for (var i = 0, len = rename_array.length; i < len; i++) {
        var obj = rename_array[i];
        rename_hash[obj.value] = obj.label;
    }
    return function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = rename_hash[oData];
    };
}
function newDataSourceFromArrays(struct) {
    var ds = new YAHOO.util.DataSource(struct.records);
    ds.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    ds.responseSchema = {fields:struct.fields};
    return ds;
}
function expandJoinedFields(mainTable, lookupTables) {
    var tmp = {};
    for (var lookupTable in lookupTables) {
        var obj = lookupTables[lookupTable];
        var lookup_by = obj.lookup_by;
        if (lookup_by in tmp) {
            tmp[lookup_by].push([lookupTable, obj]);
        } else {
            tmp[lookup_by] = [ [lookupTable, obj] ];
        }
    }
    var mainTable_fields = mainTable.fields,
    mainTable_records = mainTable.records,
    num_records = mainTable_records.length,
    mainTable_meta = mainTable.meta;
    for (var k = 0, num_fields = mainTable_fields.length; k < num_fields; k++) {
        var field = mainTable_fields[k];
        if (field in mainTable_meta) {
            // replace with object containing parser
            mainTable_fields[k] = { key: field, parser: mainTable_meta[field].parser };
        }
        if (field in tmp) {
            var objArray = tmp[field];
            var extra_col_count = 0;
            for (var l = 0, obj_len = objArray.length; l < obj_len; l++) {
                var tuple = objArray[l];
                var lookupTable = tuple[0],
                obj = tuple[1];
                var extra_fields = obj.index2symbol.slice(1);
                var extra_meta = obj.meta;
                for (var m = 0, extra_len = extra_fields.length; m < extra_len; m++) {
                    extra_fields[m] = lookupTable + '.' + extra_fields[m];
                }
                var extra_fields_len = extra_fields.length;
                extra_col_count += extra_fields_len;
                for (var f = 0; f < extra_fields_len; f++) {
                    var join_field = extra_fields[f];
                    // either plain field name or object containing parser
                    mainTable_fields.push(
                        (join_field in extra_meta) 
                        ? { key: join_field, parser: extra_meta[join_field].parser } 
                        : join_field
                    );
                }
            }
            // For each record in data array, add field value for the
            // corresponding join field.  TODO: if joined field not editable (no
            // dropdown formatter), make it sortable (fully subsitute key
            // values). Problem: how to tell that the joined field has no
            // dropdown formatter?
            for (var i = 0; i < num_records; i++) {
                var record = mainTable_records[i];
                var field_value = record[k];
                for (var j = 0; j < extra_col_count; j++) {
                    record.push(field_value);
                }
            }
        }
    }
    return mainTable;
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

//function createUpdateHandler() {
//    return function (ev) {
//        console.log(ev);
//    };
//}

function subscribeEnMasse(el, obj) {
    for (var event in obj) {
        var handler = obj[event];
        el.subscribe(event, handler);
    }
}

// helper functions
function formatEmail(elLiner, oRecord, oColumn, oData) {
    elLiner.innerHTML = "<a href=\"mailto:" + oData + "\">" + oData + "</a>";
};

