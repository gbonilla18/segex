;(function (exports) {

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
exports.createCellDropdown = function(resourceURIBuilder, rowNameBuilder) {
    return function(lookup_table, update_field, name_field) {
        var getUpdateQuery = function(update_field, newValue) {
            return "b=ajax_update&" + update_field + "=" + encodeURIComponent(newValue);
        };
        // TODO: instead of sending name_field as a parameter, rely on 'names'
        // property?
        var name_column = lookup_table.symbol2index[name_field];
        var index_column = lookup_table.symbol2index[lookup_table.key[0]];
        var transformed_data = object_forValues(lookup_table.records, function(value) {
            this.push({ label: value[name_column], value: value[index_column] });
        }, []);
        return createCellDropdownCreator(transformed_data, update_field, resourceURIBuilder, getUpdateQuery, rowNameBuilder);
    };
}
exports.createCellDropdownDirect = function(resourceURIBuilder, rowNameBuilder) {
    return function(field, rename_array) {
        var getUpdateQuery = function(field, newValue) {
            return "b=ajax_update&" + field + "=" + encodeURIComponent(newValue);
        };
        return createCellDropdownCreator(rename_array, field, resourceURIBuilder, getUpdateQuery, rowNameBuilder);
    };
}
exports.createCellUpdater = function(resourceURIBuilder, rowNameBuilder) {
    return function(field) {
        /* uses createCellUpdater in TableUpdateDelete.js */
        var getUpdateQuery = function(field, newValue) {
            return "b=ajax_update&" + field + "=" + encodeURIComponent(newValue);
        };
        return createCellUpdaterCreator(field, resourceURIBuilder, getUpdateQuery, rowNameBuilder);
    };
}
exports.createEditFormatter = function(verb, noun, resourceURIBuilder) {
    var cellContent_part1 = '<a title="' + verb + ' this ' + noun + '" href="';
    var cellContent_part2 = '">' + verb + '</a>';
    return function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = cellContent_part1 + resourceURIBuilder(oRecord) + cellContent_part2;
    };
}
exports.createWaitIndicator = function(wait_indicator, waitIndicatorImageURL) {
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
exports.createRowDeleter = function(buttonValue, resourceURIBuilder, deleteDataBuilder, rowNameBuilder, waitIndicatorImageURL) {
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
exports.createDeleteDataBuilder = function(oArg) {
    if (typeof(oArg) === 'undefined' || oArg === null) {
        oArg = {};
    }
    var keys = (typeof oArg.key !== "undefined") ? oArg.key : {};
    var tableData = (typeof oArg.table !== "undefined") ? ["table=" + encodeURIComponent(oArg.table)] : [];
    return function(oRecord) {
        return object_forEach(keys, function(key, val) {
            this.push(key + '=' + encodeURIComponent(oRecord.getData(val)));
        }, ['b=ajax_delete'].concat(tableData)).join('&');
    };
}
exports.createDeleteFormatter = function(verb, noun) {
    var cellContent = '<button title="' + verb + ' this ' + noun + '" class="plaintext">' + verb + '</button>';
    return function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = cellContent;
    };
}
exports.createJoinFormatter = function(join_tuple, lookup_table, name_field) {
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
exports.createRenameFormatter = function (rename_array) {
    var rename_hash = forEach(rename_array, function(obj) {
        this[obj.value] = obj.label;
    }, {});
    return function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = rename_hash[oData];
    };
}
exports.newDataSourceFromArrays = function(struct) {
    var ds = new YAHOO.util.DataSource(struct.records);
    ds.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    ds.responseSchema = {fields:struct.fields};
    return ds;
}
exports.expandJoinedFields = function(mainTable, lookupTables) {
    var tmp = forPairInList(mainTable.lookup, function(other_table, tuple) {
        var obj = lookupTables[other_table];
        if (typeof obj !== 'undefined' && obj !== null) {
            obj.lookup_by = {};
            var this_field = tuple[0];
            var other_field = tuple[1];
            if (this.hasOwnProperty(this_field)) {
                this[this_field].push([other_table, other_field, obj]);
            } else {
                this[this_field] = [ [other_table, other_field, obj] ];
            }
        }
    }, {});
    var mainTable_fields  = mainTable.fields;
    var mainTable_records = mainTable.records;
    var mainTable_meta    = mainTable.meta;
    for (var k = 0, num_fields = mainTable_fields.length; k < num_fields; k++) {
        var field = mainTable_fields[k];
        if (mainTable_meta.hasOwnProperty(field)) {
            // replace with object containing parser
            mainTable_fields[k] = { key: field, parser: mainTable_meta[field].parser };
        }
        if (tmp.hasOwnProperty(field)) {
            var extra_col_count = 0;
            forEach(tmp[field], function(triple) {
                var lookupTable = triple[0];
                var lookupField = triple[1];
                var obj         = triple[2];

                // prepend table name to every field from view
                var extra_meta = obj.meta;
                extra_col_count += obj.view.length;
                var extra_fields = forEach(obj.view, function(extra_field) {
                    var join_field = lookupTable + '.' + extra_field;
                    // either plain field name or object containing parser
                    mainTable_fields.push(
                        extra_meta.hasOwnProperty(join_field) ? { key: join_field, parser: extra_meta[join_field].parser } : join_field
                    );
                }, []);

                // setup 'data' property in lookupTable
                var lookupIndex = obj.symbol2index[lookupField];
                var extra_key_len = obj.key.length;
                obj.lookup_by[lookupField] = forEach(obj.records, function(record) {
                    var data_slice = record.slice(extra_key_len);
                    var key_val = record[lookupIndex];
                    if (this.hasOwnProperty(key_val)) {
                        var this_array = this[key_val];
                        for (var c = 0, clen = this_array.length; c < clen; c++) {
                            // zip on commas
                            this_array[c] = this_array[c] + ', ' + data_slice[c];
                        }
                    } else {
                        this[key_val] = data_slice;
                    }
                }, {});
            });
            // For each record in data array, add field value for the
            // corresponding join field.  TODO: if joined field not editable (no
            // dropdown formatter), make it sortable (fully subsitute key
            // values). Problem: how to tell that the joined field has no
            // dropdown formatter?
            forEach(mainTable_records, function(this_record) {
                var field_value = this_record[k];
                for (var j = 0; j < extra_col_count; j++) {
                    this_record.push(field_value);
                }
            });
        }
    }
    return mainTable;
}
exports.createResourceURIBuilder = function(uriPrefix, columnMapping) {
    return function (oRecord) {
        var myColMap = (typeof columnMapping !== "undefined") ? columnMapping : [];
        return object_forEach(myColMap, function(key, val) {
            this.push(key + "=" + encodeURIComponent(oRecord.getData(val)));
        }, [uriPrefix]).join('&');
    };
}
exports.createRowNameBuilder = function(nameColumns, item_class) {
    function getCleanFieldValue(oRecord, field) {
        /* getData() takes name of column that contains record names */
        return String(oRecord.getData(field)).replace('"', "").replace("'","");
    }
    return function (oRecord) {
        return item_class + ' `' + forEach(nameColumns, function(el) {
            this.push(getCleanFieldValue(oRecord, el));
        }, []).join(' / ') + '`';
    };
}
exports.formatEmail = function(elLiner, oRecord, oColumn, oData) {
    elLiner.innerHTML = (typeof oData !== 'undefined' && oData !== null) ? "<a href=\"mailto:" + oData + "\">" + oData + "</a>" : '';
}
exports.formatPubMed = function(elLiner, oRecord, oColumn, oData) {
    elLiner.innerHTML = (typeof oData !== 'undefined' && oData !== null) ? oData.replace(/\bPMID *: *([0-9]+)\b/gi, '<a class="external" target="_blank" title="View this study on PubMed" href="http://www.ncbi.nlm.nih.gov/pubmed?term=$1[uid]">PMID:$1</a>') : '';
}
exports.populateDropdowns = function(lookupTables, lookup, data) {
    var inverseLookup = forPairInList(lookup, function(table, fieldmap) {
        var this_field = fieldmap[0];

        // only use first lookup
        if (!this.hasOwnProperty(this_field)) {
            var table_info = lookupTables[table];
            if (typeof table_info !== 'undefined') {
                var other_field = fieldmap[1];
                var names = table_info.names;
                if (names === null) {
                    names = [other_field]; // default to key field
                }

                var symbol2index = table_info.symbol2index;
                var name_indexes = forEach(names, function(name) {
                    this.push(symbol2index[name]);
                }, []).sort();

                // now create a key-value structure mapping lookud up values of
                // this_field to names in lookup table
                var other_index = symbol2index[other_field];
                var id_name = forEach(table_info.records, function(record) {
                    this.push([record[other_index], selectFromArray(record, name_indexes).join(' / ')]);
                }, [['', '@Choose ' + table_info.symbol2name[names[0]] + ':']]).sort(ComparisonSortOnColumn(1));

                // generic tuple sort (sort hash by value)
                this[this_field] = {options: id_name, selected:data[this_field]};
            }
        }
    }, {});

    return function() {
        object_forEach(inverseLookup, function(key, val) {
            var obj = document.getElementById(key);
            if (obj !== null) {
                var selected = val.selected;
                var haveSelected = typeof(selected) !== 'undefined';
                if (val.options.length === 0) {
                    obj.style.width = '200px'; // default width
                }
                removeAllChildren(obj);
                forEach(val.options, function(tuple) {
                    var this_key = tuple[0];
                    var option = document.createElement('option');
                    option.setAttribute('value', this_key);
                    if (haveSelected && this_key === selected) {
                        option.selected = 'selected';
                    }
                    option.appendChild(document.createTextNode(tuple[1]));
                    obj.appendChild(option);
                });
                triggerEvent(obj, 'change');
            }
        });
    };
}

}(this));
