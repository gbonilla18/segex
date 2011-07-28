/* depends on the following YUI files:
 *
 * build/yahoo-dom-event/yahoo-dom-event.js
 * build/connection/connection_core-min.js
 * build/element/element-min.js
 * build/datasource/datasource-min.js
 * build/datatable/datatable-min.js
 *
 */

/* BEGIN generic stuff -- help implement the U in CRUD */
function createTextareaCellEditor(PostBackURL, buildPostBackQuery) {
    return new YAHOO.widget.TextareaCellEditor({
        disableBtns: false,
        asyncSubmitter: function(callback, newValue) {
            var record = this.getRecord();
            //var column = this.getColumn();
            //var datatable = this.getDataTable();
            if (this.value === newValue) { callback(); }
            YAHOO.util.Connect.asyncRequest("POST", PostBackURL, {
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
            }, buildPostBackQuery(newValue, record));
        }
    });
}

/* curry createTextareaCellEditor on PostBackURL: this is a generic factory spec
 * sheet for making hammers */
function createCellUpdater(field, PostBackURL, indexColumnName) {
    // field: name of the field in the database table to update.
    // PostBackURL: the URL to send the data to.
    // indexColumnName: column in the data array which contains the lookup
    // index.
    return createTextareaCellEditor(
        PostBackURL,
        function(newValue, record) {
            return "b=update&field=" + field
            + "&value=" + escape(newValue) 
            + "&id=" + encodeURI(record.getData(indexColumnName));
        }
    );
}
/* END generic stuff */
