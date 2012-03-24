"use strict";

/* depends on the following YUI files:
*
* build/yahoo-dom-event/yahoo-dom-event.js
* build/connection/connection_core-min.js
* build/element/element-min.js
* build/datasource/datasource-min.js
* build/datatable/datatable-min.js
*/

function ajaxError(o, verb, name, resourceURI) {
    return (o.responseText !== undefined) ? "Error encountered when attempting to " + verb + " " + name + " under " + resourceURI +".\nServer responded with code " + o.status + " (" + o.statusText + "):\n\n" + o.responseText : "Timeout on updating record (" + name + ") under " + resourceURI;
}

function highlightEditableCell(oArgs) { 
    var elCell = oArgs.target; 
    if (YAHOO.util.Dom.hasClass(elCell, "yui-dt-editable")) { 
        this.highlightCell(elCell); 
    } 
}

function createCellDropdownCreator(transformed_data, field, resourceURIBuilder, getUpdateQuery, rowNameBuilder) {
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
                alert(ajaxError(o, 'update', rowNameBuilder(record), resourceURI));
            },
            scope:this
        };
        YAHOO.util.Connect.asyncRequest(
            "POST", 
            resourceURI,
            callbackObject, 
            getUpdateQuery(field, newValue)
        );
    };
    return new YAHOO.widget.DropdownCellEditor({
        dropdownOptions:transformed_data,
        disableBtns: false,
        asyncSubmitter: submitter
    });
}

function createCellDropdown(resourceURIBuilder, rowNameBuilder) {
    return function(lookup_table, update_field, name_field) {
        var getUpdateQuery = function(update_field, newValue) {
            return "b=ajax_update&" + update_field + "=" + encodeURIComponent(newValue);
        };
        // TODO: instead of sending name_field as a parameter, rely on 'names'
        // property?
        var transformed_data = [];
        var lookup_records = lookup_table.records;
        var name_column = lookup_table.symbol2index[name_field];
        var index_column = lookup_table.symbol2index[lookup_table.key[0]];
        for (var key in lookup_records) {
            if (lookup_records.hasOwnProperty(key)) {
                var value = lookup_records[key];
                transformed_data.push({ label: value[name_column], value: value[index_column]});
            }
        }

        return createCellDropdownCreator(transformed_data, update_field, resourceURIBuilder, getUpdateQuery, rowNameBuilder);
    };
}

function createCellDropdownDirect(resourceURIBuilder, rowNameBuilder) {
    return function(field, rename_array) {
        var getUpdateQuery = function(field, newValue) {
            return "b=ajax_update&" + field + "=" + encodeURIComponent(newValue);
        };
        return createCellDropdownCreator(rename_array, field, resourceURIBuilder, getUpdateQuery, rowNameBuilder);
    };
}

function createCellUpdaterCreator(field, resourceURIBuilder, getUpdateQuery, rowNameBuilder) {
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
                alert(ajaxError(o, 'update', rowNameBuilder(record), resourceURI));
            },
            scope:this
        };
        YAHOO.util.Connect.asyncRequest(
            "POST", 
            resourceURI,
            callbackObject, 
            getUpdateQuery(field, newValue)
        );
    };
    return new YAHOO.widget.TextareaCellEditor({
        disableBtns: false,
        asyncSubmitter: submitter
    });
}

function createCellUpdater(resourceURIBuilder, rowNameBuilder) {
    return function(field) {
        /* uses createCellUpdater in TableUpdateDelete.js */
        var getUpdateQuery = function(field, newValue) {
            return "b=ajax_update&" + field + "=" + encodeURIComponent(newValue);
        };
        return createCellUpdaterCreator(field, resourceURIBuilder, getUpdateQuery, rowNameBuilder);
    };
}

function createEditFormatter(verb, noun, resourceURIBuilder) {
    var cellContent_part1 = '<a title="' + verb + ' this ' + noun + '" href="';
    var cellContent_part2 = '">' + verb + '</a>';
    return function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = cellContent_part1 + resourceURIBuilder(oRecord) + cellContent_part2;
    };
}

function createWaitIndicator(wait_indicator, waitIndicatorImageURL) {
    if (!wait_indicator) {
        // Initialize the temporary Panel to display while waiting for external content to load
        wait_indicator = new YAHOO.widget.Panel("wait", { 
            width: "200px", 
            fixedcenter: true, 
            close: false, 
            draggable: false, 
            zindex:4, 
            modal: true, 
            visible: false 
        });
        wait_indicator.setHeader("Deleting, please wait...");
        wait_indicator.setBody("<img src=\"" + waitIndicatorImageURL + "\"/>");
        wait_indicator.render(document.body);
    }
    return wait_indicator;
}

function createRowDeleter(buttonValue, resourceURIBuilder, deleteDataBuilder, rowNameBuilder, waitIndicatorImageURL) {
    var verb = buttonValue.toLowerCase();

    var handleSuccess = function(o, scope) {
        // simply delete row, then do nothing
        var record = o.argument[0];
        scope.deleteRow(record);
    };

    var handleFailure = function(o, scope) {
        var record = o.argument[0];
        var name = rowNameBuilder(record);
        alert(ajaxError(o, verb, rowNameBuilder(record), resourceURIBuilder(record)));
    };

    var wait_indicator;
    return function(ev) {
        var target = YAHOO.util.Event.getTarget(ev);
        if (target.innerHTML !== buttonValue) { return false; }
        var record = this.getRecord(target);

        // strip double and single quotes from row name
        var name = rowNameBuilder(record);
        var resourceURI = resourceURIBuilder(record);
        if (!confirm("Are you sure you want to " + verb + " " + name + "?")) { return false; }

        // show wait indicator
        wait_indicator = createWaitIndicator(wait_indicator, waitIndicatorImageURL);

        var callbackObject = {
            success:function(o) { 
                wait_indicator.hide();
                handleSuccess(o, this);
            },
            failure:function(o) {
                wait_indicator.hide();
                handleFailure(o, this);
            },
            argument:[record],
            scope:this
        };
        // show waiting indicator
        wait_indicator.show();

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
    var keys = (typeof oArg !== "undefined" && typeof oArg.key !== "undefined") ? oArg.key : {};
    var tableData = (typeof oArg !== "undefined" && typeof oArg.table !== "undefined") ? "&table=" + oArg.table : "";
    return function(oRecord) {
        var data = "b=ajax_delete" + tableData;
        for (var key in keys) {
            if (keys.hasOwnProperty(key)) {
                data += "&" + key + "=" + encodeURIComponent(oRecord.getData(keys[key]));
            }
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
function createJoinFormatter(join_tuple, lookup_table, name_field) {
    if (typeof join_tuple === 'undefined') {
        return function(elCell, oRecord, oColumn, oData) {};
    }
    var this_field = join_tuple[0], other_field = join_tuple[1];
    var name_column, root;
    if (typeof lookup_table !== 'undefined') {
        name_column = lookup_table.symbol2index[name_field] - lookup_table.key.length;
        root = lookup_table.lookup_by[other_field];
    }

    return function(elCell, oRecord, oColumn, oData) {
        // this also gets executed after we update a cell via AJAX
        var sub_record;
        if (typeof oData !== 'undefined') {
            sub_record = root[oData];
        }
        elCell.innerHTML = (typeof sub_record !== 'undefined') ? sub_record[name_column] : '';
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

function forPairInList (list, fun) {
    if (list !== null) {
        for (var i = 0, len = list.length; i < len; i += 2) {
            fun(list[i], list[i + 1]);
        }
    }
}

function expandJoinedFields(mainTable, lookupTables) {
    var tmp = {};
    forPairInList(mainTable.lookup, function(other_table, tuple) {
        var obj = lookupTables[other_table];
        if (typeof obj !== 'undefined' && obj !== null) {
            obj.lookup_by = {};
            var this_field = tuple[0];
            var other_field = tuple[1];
            if (tmp.hasOwnProperty(this_field)) {
                tmp[this_field].push([other_table, other_field, obj]);
            } else {
                tmp[this_field] = [ [other_table, other_field, obj] ];
            }
        }
    });
    var mainTable_fields = mainTable.fields,
    mainTable_records = mainTable.records,
    num_records = mainTable_records.length,
    mainTable_meta = mainTable.meta;
    for (var k = 0, num_fields = mainTable_fields.length; k < num_fields; k++) {
        var field = mainTable_fields[k];
        if (mainTable_meta.hasOwnProperty(field)) {
            // replace with object containing parser
            mainTable_fields[k] = { key: field, parser: mainTable_meta[field].parser };
        }
        if (tmp.hasOwnProperty(field)) {
            var objArray = tmp[field];
            var extra_col_count = 0;
            for (var l = 0, obj_len = objArray.length; l < obj_len; l++) {
                var triple = objArray[l];
                var lookupTable = triple[0];
                var lookupField = triple[1];
                var obj = triple[2];


                var extra_key_len = obj.key.length;
                var extra_fields = obj.view;
                var extra_meta = obj.meta;

                // prepend table name to every field from view
                for (var m = 0, extra_len = extra_fields.length; m < extra_len; m++) {
                    extra_fields[m] = lookupTable + '.' + extra_fields[m];
                }

                var extra_fields_len = extra_fields.length;
                extra_col_count += extra_fields_len;
                for (var f = 0; f < extra_fields_len; f++) {
                    var join_field = extra_fields[f];
                    // either plain field name or object containing parser
                    mainTable_fields.push(
                        extra_meta.hasOwnProperty(join_field) ? { key: join_field, parser: extra_meta[join_field].parser } : join_field
                    );
                }

                // setup 'data' property in lookupTable
                var data = {};
                var lookupTable_records = obj.records;
                var lookupIndex = obj.symbol2index[lookupField];
                for (var r = 0, len = lookupTable_records.length; r < len; r++) {
                    var record = lookupTable_records[r];
                    var data_slice = record.slice(extra_key_len);
                    var key_val = record[lookupIndex];
                    if (data.hasOwnProperty(key_val)) {
                        var this_array = data[key_val];
                        for (var c = 0, clen = this_array.length; c < clen; c++) {
                            // zip on commas
                            this_array[c] = this_array[c] + ', ' + data_slice[c];
                        }
                    } else {
                        data[key_val] = data_slice;
                    }
                }
                obj.lookup_by[lookupField] = data;
            }
            // For each record in data array, add field value for the
            // corresponding join field.  TODO: if joined field not editable (no
            // dropdown formatter), make it sortable (fully subsitute key
            // values). Problem: how to tell that the joined field has no
            // dropdown formatter?
            for (var i = 0; i < num_records; i++) {
                var this_record = mainTable_records[i];
                var field_value = this_record[k];
                for (var j = 0; j < extra_col_count; j++) {
                    this_record.push(field_value);
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
                if (columnMapping.hasOwnProperty(key)) {
                    resourceURI += "&" + key + "=" + encodeURIComponent(oRecord.getData(columnMapping[key]));
                }
            }
        }
        return resourceURI;
    };
}

function createRowNameBuilder(nameColumns, item_class) {
    function getCleanFieldValue(oRecord, field) {
        /* getData() takes name of column that contains record names */
        return oRecord.getData(field).replace('"', "").replace("'","");
    }
    return function (oRecord) {
        var names = [];
        for (var i = 0, len = nameColumns.length; i < len; i++) {
            names.push(getCleanFieldValue(oRecord, nameColumns[i]));
        }
        return item_class + " `" + names.join(" / ") + "`";
    };
}

function subscribeEnMasse(el, obj) {
    for (var event in obj) {
        if (obj.hasOwnProperty(event)) {
            var handler = obj[event];
            el.subscribe(event, handler);
        }
    }
}

// helper functions
function formatEmail(elLiner, oRecord, oColumn, oData) {
    elLiner.innerHTML = (oData !== null) ? "<a href=\"mailto:" + oData + "\">" + oData + "</a>" : '';
}

function formatPubMed(elLiner, oRecord, oColumn, oData) {
    elLiner.innerHTML = (typeof oData !== 'undefined' && oData !== null) ? oData.replace(/\bPMID *: *([0-9]+)\b/gi, '<a target="_blank" title="View this study on PubMed" href="http://www.ncbi.nlm.nih.gov/pubmed?term=$1[uid]">PMID:$1</a>') : '';
}

// returns a new array containing a specified subset of the old one
function selectFromArray(array, subset) {
    var subset_length = subset.length;
    var result = new Array(subset_length);
    for (var i = 0; i < subset_length; i++) {
        result[i] = array[subset[i]];
    }
    return result;
}

function sortNestedByColumn (tuples, column) {
    tuples.sort(function (a, b) {
        a = a[column];
        b = b[column];
        return a < b ? -1 : (a > b ? 1 : 0);
    });
}

function populateDropdowns(lookupTables, lookup, data) {
    var inverseLookup = {};
    forPairInList(lookup, function(table, fieldmap) {
        var this_field = fieldmap[0];

        // only use first lookup
        if (!inverseLookup.hasOwnProperty(this_field)) {
            var table_info = lookupTables[table];
            if (typeof table_info !== 'undefined') {
                var other_field = fieldmap[1];
                var symbol2index = table_info.symbol2index;
                var other_index = symbol2index[other_field];
                var names = table_info.names;
                if (names === null) {
                    // default to key field 
                    names = [other_field];
                }
                var name_indexes = [];
                for (var i = 0, name_count = names.length; i < name_count; i++) {
                    name_indexes.push(symbol2index[names[i]]);
                }
                name_indexes.sort();

                // now create a key-value structure mapping lookud up values of
                // this_field to names in lookup table
                var records = table_info.records;
                var records_length = records.length;
                var id_name = [['', '@Choose ' + table_info.symbol2name[names[0]] + ':']];
                for (var j = 0; j < records_length; j++) {
                    var record = records[j];
                    id_name.push([record[other_index], selectFromArray(record, name_indexes).join(' / ')]);
                }
                // generic tuple sort (sort hash by value)
                sortNestedByColumn(id_name, 1);
                inverseLookup[this_field] = {options: id_name, selected:data[this_field]};
            }
        }
    });
    return function() {
        for (var key in inverseLookup) {
            if (inverseLookup.hasOwnProperty(key)) {
                var obj = document.getElementById(key);
                if (obj !== null) {
                    var val = inverseLookup[key];
                    var selected = val.selected;
                    var tuples = val.options;
                    var tuples_length = tuples.length;
                    // default width
                    if (tuples_length === 0) {
                        obj.style.width = '200px';
                    }
                    for (var i = 0; i < tuples_length; i++) {
                        var this_key = tuples[i][0];
                        var value = tuples[i][1];
                        var option = document.createElement('option');
                        option.setAttribute('value', this_key);
                        if (typeof(selected) !== 'undefined' && this_key === selected) {
                            option.selected = 'selected';
                        }
                        option.innerHTML = value;
                        obj.appendChild(option);
                    }
                }
            }
        }
    };
}
