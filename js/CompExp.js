(function() {

"use strict";

var Dom = YAHOO.util.Dom;
YAHOO.util.Event.addListener(window, "load", function() {
    var formatExperiment = function(elCell, oRecord, oColumn, oData) {
        var title = oRecord.getData('1');
        elCell.innerHTML = oData + '. ' + title;
    };
    Dom.get("eid").value = eid;
    Dom.get("rev").value = rev;
    Dom.get("fc").value = fc;
    Dom.get("pval").value = pval;
    Dom.get("allProbes").value = allProbes;
    Dom.get("searchFilter").value = searchFilter;
    Dom.get("venn").innerHTML = venn;
    Dom.get("summary_caption").innerHTML = summary.caption;

    var summary_data = new YAHOO.util.DataSource(summary.records);
    summary_data.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    summary_data.responseSchema = { fields: [
        {key:"0", parser:"number"},
        {key:"1"},
        {key:"2", parser:"number"},
        {key:"3", parser:"number"},
        {key:"4", parser:"number"}
    ]};
    var summary_table_defs = [
        {key:"0", sortable:true, resizeable:true, label:"Experiment", formatter:formatExperiment},
        {key:"2", sortable:true, resizeable:false, label:"P &lt;"},
        {key:"3", sortable:true, resizeable:false, label:"&#124;Fold&#124; &gt;"}, 
        {key:"4", sortable:true, resizeable:false, label:"Probe Count"}
    ];
    var summary_table = new YAHOO.widget.DataTable("summary_table", summary_table_defs, summary_data, {});

    YAHOO.widget.DataTable.Formatter.formatDownload = function(elCell, oRecord, oColumn, oData) {
        var fs = oRecord.getData("0");
        elCell.innerHTML = "<input class=\"plaintext\" type=\"submit\" name=\"get\" value=\"TFS " + fs + " (HTML)\" />&nbsp;&nbsp;&nbsp;<input class=\"plaintext\" type=\"submit\" name=\"get\" value=\"TFS " + fs + " (CSV)\" />";
    }
    Dom.get("tfs_caption").innerHTML = tfs.caption;
    Dom.get("tfs_all_dt").innerHTML = "View data for " + rep_count + " probes:";
    Dom.get("tfs_all_dd").innerHTML = "<input type=\"submit\" name=\"get\" class=\"plaintext\" value=\"TFS (HTML)\" /><span class=\"separator\"> / </span><input type=\"submit\" class=\"plaintext\" name=\"get\" value=\"TFS (CSV)\" />";
    var tfs_config = {
        paginator: new YAHOO.widget.Paginator({
            rowsPerPage: 50 
        })
    };
    var tfs_data = new YAHOO.util.DataSource(tfs.records);
    tfs_data.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    tfs_data.responseSchema = {
        fields: tfs_data_fields
    };
    var tfs_table = new YAHOO.widget.DataTable("tfs_table", tfs_table_defs, tfs_data, tfs_config);
});
})();
