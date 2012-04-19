;(function() {

"use strict";

var dom = YAHOO.util.Dom;
var lang = YAHOO.lang;

function getExperimentName(oArgs) {
    var sample1 = oArgs.sample1;
    var sample2 = oArgs.sample2;
    return oArgs.eid + '. ' + oArgs.study_desc + ': ' + (oArgs.reverse ? (sample1 + ' / ' + sample2) : (sample2 + ' / ' + sample1));
}
function isSignif(oRecord) {
    if (_fs === null) {
        return null;
    } else {
        var recordIndex = parseInt(oRecord.getCount(), 10);
        var flags = parseInt(_fs, 10);
        return (1 << recordIndex & flags);
    }
}

YAHOO.util.Event.addListener("tfs_astext", "click", export_table, tfs, true);
YAHOO.util.Event.addListener(window, "load", function() {
    // ======= Summary table ==============
    var formatterYesNo = function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = (oData) ? 'Yes' : 'No';
    };
    var experimentFormatter = function(elCell, oRecord, oColumn, oData) {
        removeAllChildren(elCell);
        var text = document.createTextNode(getExperimentName(forEach(
            ['eid', 'study_desc', 'sample1', 'sample2', 'reverse'], 
            function(key) { this[key] = oRecord.getData(key); }, 
            {}
        )));
        var a = document.createElement('a');
        a.setAttribute('href', './?a=experiments&id=' + oData);
        if (!isSignif(oRecord)) {
            a.setAttribute('class', 'disabled');
        } 
        a.appendChild(text);
        elCell.appendChild(a);
    };
    var formatterReqSignif = function(elCell, oRecord, oColumn, oData) {
        var answer = isSignif(oRecord);
        if (answer === null) {
            dom.addClass(elCell, 'disabled');
            elCell.innerHTML = 'n/a';
        } else if (isSignif(oRecord)) {
            dom.removeClass(elCell, 'disabled');
            elCell.innerHTML = '<strong>Y</strong>';
        } else {
            dom.addClass(elCell, 'disabled');
            elCell.innerHTML = 'N';
        }
    };
    var summary_data = new YAHOO.util.DataSource(_xExpList);
    summary_data.responseSchema = { fields: [
        {key:"eid", parser:"number"},
        {key:"study_desc"},
        {key:"sample1"},
        {key:"sample2"},
        {key:"reverse"},
        {key:"pValFlag", parser:"number"},
        {key:"pValClass", parser:"number"},
        {key:"pval", parser:"number"},
        {key:"fchange", parser: "number"}
    ]};
    var summary_table_defs = [
        {key:"eid", sortable:false, resizeable:true, label:'Experiment', formatter:experimentFormatter},
        {key:"reverse", sortable:false, resizeable:false, label:'Switched Samples', formatter:formatterYesNo},
        {key:"pValClass", sortable:false, resizeable:false, label:'P-value'},
        {key:"pval", sortable:false, resizeable:false, label:'P <'},
        {key:"fchange", sortable:false, resizeable:false, label:'|Fold| >'},
        {key:"reqSignif", sortable:false, resizeable:true, label:'Signif. In', formatter:formatterReqSignif}
    ];
    var summary_table = new YAHOO.widget.DataTable("summary_table", summary_table_defs, summary_data, {});


    var Formatter = YAHOO.widget.DataTable.Formatter;
    Formatter.formatProbe = function (elCell, oRecord, oColumn, oData) {
        var clean = (oData === null) ? '' : oData;
        elCell.innerHTML = lang.substitute(tfs.frm_tpl.probe, {"0":clean});
    };
    Formatter.formatAccNum = function (elCell, oRecord, oColumn, oData) {
        var clean = (oData === null) ? '' : oData;
        elCell.innerHTML = lang.substitute(tfs.frm_tpl.accnum, {"0":clean});
    };
    Formatter.formatGene = function (elCell, oRecord, oColumn, oData) {
        var clean = (oData === null) ? '' : oData;
        elCell.innerHTML = lang.substitute(tfs.frm_tpl.gene, {"0":clean});
    };
    Formatter.formatProbeSequence = function (elCell, oRecord, oColumn, oData) {
        var clean = (oData === null) ? '' : oData;
        elCell.innerHTML = lang.substitute(lang.substitute(tfs.frm_tpl.probeseq, {"0":clean}),{"1":oRecord.getData("6")});

    };
    Formatter.formatNumber = function(elCell, oRecord, oColumn, oData) {
        // Overrides the built-in formatter
        if (oData !== null) {
            elCell.innerHTML = oData.toPrecision(3);
        }
    };
    dom.get("tfs_caption").innerHTML = tfs.caption;
    var tfs_table_defs = [];
    var tfs_schema_fields = [];
    for (var i=0, th = tfs.headers, tp = tfs.parsers, tf=tfs.formats, al=th.length; i<al; i++) {
        tfs_table_defs.push({key:String(i), sortable:true, label:th[i], formatter:tf[i]});
        tfs_schema_fields.push({key:String(i), parser:tp[i]});
    }
    var tfs_config = {
        paginator: new YAHOO.widget.Paginator({
            rowsPerPage: 15 
        })
    };
    var tfs_data = new YAHOO.util.DataSource(tfs.records);
    tfs_data.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    tfs_data.responseSchema = { fields: tfs_schema_fields };
    var tfs_table = new YAHOO.widget.DataTable("tfs_table", tfs_table_defs, tfs_data, tfs_config);
});

})();
