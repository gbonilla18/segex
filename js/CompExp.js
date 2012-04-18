(function() {

"use strict";

var Dom = YAHOO.util.Dom;

//==============================================================================
function getExperimentName(oArgs) {
    var sample1 = oArgs.sample1;
    var sample2 = oArgs.sample2;
    return oArgs.eid + '. ' + oArgs.study_desc + ': ' + (oArgs.reverse ? (sample1 + ' / ' + sample2) : (sample2 + ' / ' + sample1));
}

//==============================================================================
function getGoogleVennURI2() {
    var c = iterateForward(function(fs) {
        this.push(h.hasOwnProperty(fs) ? parseInt(h[fs].c) : 0);
    }, [], 1, 4);

    var A = parseInt(hc[0]),
        B = parseInt(hc[1]),
        AB = c[2];

    return {
        title: 'Significant Probes Diagram',
        uri: 'http://chart.apis.google.com/chart?' + object_forEach({
            //chtt - titlle
            cht  : 'v',
            chs  : '800x300',
            chd  : 't:' + [A, B, 0, AB ].join(','),
            chds : [0, Math.max(A, B)].join(','),
            chco : ['ff0000', '00ff00'].join(','),
            chdl : forEach( _xExpList, 
                    function(row) { this.push(encodeURIComponent(abbreviate(getExperimentName(row), 70))); }, 
                []).join('|')
            }, function(key, val) {
                this.push(key + '=' + val);
            }, []).join('&')
    };
}

//==============================================================================
function getGoogleVennURI3() {
    var c = iterateForward(function(fs) {
        this.push(h.hasOwnProperty(fs) ? parseInt(h[fs].c) : 0);
    }, [], 1, 8);

    var A = parseInt(hc[0]),
        B = parseInt(hc[1]),
        C = parseInt(hc[2]),
        AB = c[2] + c[6],
        AC = c[4] + c[6],
        BC = c[5] + c[6],
        ABC = c[6];

    //number of elements greater than zero
    var num_circles = forEach([A, B, C], function(val) {
        if (val !== null && val > 0) {
            this.push(val);
        }
    }, []).length;

    return {
        title: (num_circles > 2 ? 'Significant Probes Diagram (Approx.)' : 'Significant Probes Diagram'),
        uri: 'http://chart.apis.google.com/chart?' + object_forEach({
            //chtt - titlle
            cht  : 'v',
            chs  : '800x300',
            chd  : 't:' + [ A, B, C, AB, AC, BC, ABC ].join(','),
            chds : [0, Math.max(A, B, C)].join(','),
            chco : ['ff0000', '00ff00', '0000ff'].join(','),
            chdl : forEach( _xExpList, 
                    function(row) { this.push(encodeURIComponent(abbreviate(getExperimentName(row), 70))); }, 
                []).join('|')
            }, function(key, val) {
                this.push(key + '=' + val);
            }, []).join('&') 
    };
}

//==============================================================================
function getGoogleVenn() {
    // http://code.google.com/apis/chart/types.html#venn
    // http://code.google.com/apis/chart/formats.html#data_scalin
    if (!probe_count) {
        return null;
    }
    switch (_xExpList.length) {
        case 2:
            return getGoogleVennURI2();
            break;
        case 3:
            return getGoogleVennURI3();
            break;
        default:
            return null;
            break;
    }
}

//==============================================================================
function formatterFlagsum (elCell, oRecord, oColumn, oData) {
    var text = oData === null ? (includeAllProbes ? 'all probes' : 'all sign. probes') : 'FS ' + oData;
    elCell.innerHTML = text;
};

//==============================================================================
var rowcount_titles = _xExpList.length;

// TFS: all
var row_all = iterateForward(function(i) {
    this.push('n/a');
}, [null], 0, rowcount_titles).concat(null, probe_count);


YAHOO.util.Event.addListener(window, "load", function() {
    Dom.get("includeAllProbes").value = includeAllProbes;
    Dom.get("searchFilter").value = searchFilter;

    var venn = getGoogleVenn();
    Dom.get("venn").innerHTML = (venn === null ? '' : '<h2>' + venn.title + '</h2><img title="Venn Diagram" alt="Venn Diagram" src="' + venn.uri + '" />');

    var selectedFS = Dom.get('selectedFS');

    //==============================================================================
    var formatDownload = function(elCell, oRecord, oColumn, oData) {
        removeAllChildren(elCell);
        var fs = oRecord.getData("fs");
        var btn_html = document.createElement('input');
        btn_html.setAttribute('type', 'submit');
        btn_html.setAttribute('class', 'plaintext');
        btn_html.setAttribute('name', 'get');
        btn_html.setAttribute('value', 'HTML');
        var btn_csv = document.createElement('input');
        btn_csv.setAttribute('type', 'submit');
        btn_csv.setAttribute('class', 'plaintext');
        btn_csv.setAttribute('name', 'get');
        btn_csv.setAttribute('value', 'CSV');
        var sep = document.createElement('span');
        sep.setAttribute('class', 'separator');
        sep.appendChild(document.createTextNode(' / '));

        YAHOO.util.Event.addListener([btn_html, btn_csv], 'click', function(ev) {
            selectedFS.value = fs;
        });

        elCell.appendChild(btn_html);
        elCell.appendChild(sep);
        elCell.appendChild(btn_csv);
    };
    var formatMark = function(elCell, oRecord, oColumn, oData) {
        if (oData === 'Y') {
            dom.removeClass(elCell, 'disabled');
            elCell.innerHTML = '<strong>' + oData + '</strong>';
        } else {
            dom.addClass(elCell, 'disabled');
            elCell.innerHTML = oData;
        }
    };
    var formatterYesNo = function(elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = (oData) ? 'Yes' : 'No';
    };
    var experimentFormatter = function(elCell, oRecord, oColumn, oData) {
        removeAllChildren(elCell);
        elCell.appendChild(document.createTextNode(getExperimentName(forEach(
            ['eid', 'study_desc', 'sample1', 'sample2', 'reverse'], 
            function(key) { this[key] = oRecord.getData(key); }, 
            {}
        ))));
    };
    var formatterProbeCounts = function(elCell, oRecord, oColumn, oData) {
        var rowNumber = oRecord.getCount();
        elCell.innerHTML = hc[rowNumber];
    };

    // ====== comparison note =========
    var total_probes = probes_in_platform;
    var text = 'Total probes in the platform: ' + probes_in_platform + '. ';
    if (searchFilter !== null) {
        total_probes = searchFilter.length;
        text += 'Filtering on ' + total_probes + ' probes.';
    }
    dom.get('comparison_note').innerHTML = text;
    // ================================

    var tfs = {
        caption:'Probes grouped by significance in different experiment combinations',

        // data
        records: forEach(
            object_forValues(h, function(val) { this.push(val); }, []).sort(NumericSortOnColumnDesc('fs')), 
            function(val) {
                var fs = val.fs;
                var significant_in = 0;
                //var expected = parseFloat(total_probes);
                this.push(iterateForward(function(i) {
                    // test for bit presence
                    if ((1 << i) & fs) {
                        significant_in++;
                        //expected *= hc[i] / total_probes;
                        this.push('Y');
                    } else {
                        //expected *= (total_probes - hc[i]) / total_probes;
                        this.push('N');
                    }
                }, [fs], 0, rowcount_titles).concat(
                    significant_in, 
                    val.c
                    //Math.log(val.c / expected).toPrecision(3)
                ));
            }, 
            [row_all]
        ),

        // source data fields
        data_fields: forEach(_xExpList, function(val) {
            this.push({ key: 'eid' + val.eid });
        }, [
            { key: 'fs', parser: 'number' }
        ]).concat(
            { key: 'significant_in', parser: 'number'},
            { key: 'probe_count', parser: 'number'},
            //{ key: 'log_odds', parser: 'number'},
            { key: 'view_probes' }
        ),

        // tfs table definitions
        table_defs: forEach(_xExpList, function(val) {
            this.push({
                key: 'eid' + val.eid,
                sortable: true,
                resizeable: false,
                label: '#' + val.eid,
                sortOptions: {
                    defaultDir: YAHOO.widget.DataTable.CLASS_DESC
                },
                formatter:formatMark
            });
        }, [
    { key: 'fs', sortable:true, resizeable:false, label: 'Set Index', sortOptions: { defaultDir: YAHOO.widget.DataTable.CLASS_DESC }, formatter:formatterFlagsum}
        ]).concat(
            { key: 'significant_in', sortable:true, resizeable: false, label:'Sign. in', sortOptions: { defaultDir: YAHOO.widget.DataTable.CLASS_DESC }},
            { key: 'probe_count', sortable:true, resizeable: false, label:'Probes', sortOptions: { defaultDir: YAHOO.widget.DataTable.CLASS_DESC }},
            //{ key: 'log_odds', sortable:true, resizeable: true, label:'Log Odds Over Expected' },
            { key: 'view_probes', sortable:false, resizeable: true, label:'View report', formatter:formatDownload}
        )
    };
    YAHOO.util.Event.addListener("tfs_astext", "click", export_table, tfs, true);

    // ======= Summary table ==============
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
        {key:"fchange", parser: "number"},
    ]};
    var summary_table_defs = [
        {key:"eid", sortable:true, resizeable:true, label:'Experiment', formatter:experimentFormatter},
        {key:"reverse", sortable:true, resizeable:false, label:'Reverse Samples', formatter:formatterYesNo},
        {key:"pValClass", sortable:true, resizeable:false, label:'P-value'},
        {key:"pval", sortable:true, resizeable:false, label:'P <'},
        {key:"fchange", sortable:true, resizeable:false, label:'|Fold| >'},
        {key:"probe_count", sortable:true, resizeable:false, label:'Sign. Probes', formatter:formatterProbeCounts}
    ];
    var summary_table = new YAHOO.widget.DataTable("summary_table", summary_table_defs, summary_data, {});

    //============== TFS breakdown table ================
    var tfs_config = {
        paginator: new YAHOO.widget.Paginator({
            rowsPerPage: 50 
        })
    };
    var tfs_data = new YAHOO.util.DataSource(tfs.records);
    tfs_data.responseSchema = {
        fields: tfs.data_fields
    };
    var tfs_table = new YAHOO.widget.DataTable("tfs_table", tfs.table_defs, tfs_data, tfs_config);
});
})();
