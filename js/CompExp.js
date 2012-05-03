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
var rowcount_titles = _xExpList.length;

YAHOO.util.Event.addListener(window, "load", function() {
    setupToggles('change',
        { 
            'getHTML': { 'checked' : ['display_format'] }, 
            'getCSV': { '' : ['display_format'] } 
        }, 
        function(el) { 
            return (el.checked ? 'checked' : ''); 
        }
    );

    Dom.get("includeAllProbes").value = includeAllProbes;
    Dom.get("searchFilter").value = searchFilter;

    var venn = getGoogleVenn();
    Dom.get("venn").innerHTML = (venn === null ? '' : '<h2>' + venn.title + '</h2><img title="Venn Diagram" alt="Venn Diagram" src="' + venn.uri + '" />');
    var selectedFS = Dom.get('selectedFS');
    var selectedExp = Dom.get('selectedExp');

    //==============================================================================
    function formatterFlagsum (elCell, oRecord, oColumn, oData) {
        var text = (oData === null) ? (includeAllProbes ? 'all probes' : 'all sign. probes') : 'Subset ' + oData;
        var btn = document.createElement('input');
        btn.setAttribute('type', 'submit');
        btn.setAttribute('class', 'plaintext');
        btn.setAttribute('value', text);
        btn.setAttribute('title', 'Display report including all probes from this set');
        YAHOO.util.Event.addListener(btn, 'click', function(ev) {
            selectedExp.value = JSON.stringify(fs2expected);
            selectedFS.value = this.getData('fs');
        }, oRecord, true);
        removeAllChildren(elCell);
        elCell.appendChild(btn);
    }
    function formatterSignIn (elCell, oRecord, oColumn, oData) {
        elCell.innerHTML = (oData === null) ? ((includeAllProbes ? '0-' : '1-') + rowcount_titles) : oData;
    }

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
        var text = document.createTextNode(getExperimentName(forEach(
            ['eid', 'study_desc', 'sample1', 'sample2', 'reverse'], 
            function(key) { this[key] = oRecord.getData(key); }, 
            {}
        )));
        var a = document.createElement('a');
        a.setAttribute('href', './?a=experiments&id=' + oData);
        a.appendChild(text);
        elCell.appendChild(a);
    };
    var formatterProbeCounts = function(elCell, oRecord, oColumn, oData) {
        var rowNumber = oRecord.getCount();
        elCell.innerHTML = hc[rowNumber];
    };

    // ====== comparison note =========
    var total_probes = probes_in_platform;
    var text = 'Total probes in the platform: ' + probes_in_platform + '. ';
    if (searchFilter !== null) {
        total_probes = Math.min(searchFilter.length, probes_in_platform);
        text += 'Filtering on ' + searchFilter.length + ' probes.';
    }
    dom.get('comparison_note').innerHTML = text;
    // ================================

    var totalExpected = 0.0;
    var fs2expected = iterateForward(function(theoretic_fs) {
            var expected = parseFloat(total_probes);
            for (var i = 0; i < rowcount_titles; i++) {
                if ((1 << i) & theoretic_fs) {
                    expected *= hc[i] / total_probes;
                } else {
                    expected *= (total_probes - hc[i]) / total_probes;
                }
            };
            totalExpected += expected;
            this[String(theoretic_fs)] = expected;
        }, {}, 0, 1 << rowcount_titles);
    var totalSignExpected = totalExpected - fs2expected['0'];
    fs2expected[null] = includeAllProbes ? totalExpected : totalSignExpected;

    //var expectedNonZero = object_forValues(h, function(row) {
    //    var row_fs = row.fs;
    //    if (fs2expected.hasOwnProperty(row_fs) && parseInt(row_fs) > 0) {
    //        this.total += fs2expected[row_fs];
    //    }
    //}, {total: 0.0}).total;
    //var correctionFactor = probe_count / expectedNonZero;

    // TFS: all
    var row_all = iterateForward(function(i) {
        this.push('n/a');
    }, [null, probe_count], 0, rowcount_titles).concat(null, Math.log(probe_count / fs2expected[null]).toPrecision(3));

    var tfs = {
        caption:'Probes grouped by significance in different experiment combinations',

        // data
        records: forEach(
            // transforming object into array
            object_forValues(h, function(row) { this.push(row); }, []).sort(NumericSortOnColumnDesc('fs')), 
            function(row) {
                var observed = parseInt(row.c);
                var expected = parseFloat(fs2expected[row.fs]);
                // calculate the log_odds ratio
                var fs = parseInt(row.fs);
                var significant_in = 0;
                this.push(iterateForward(function(i) {
                    // test for bit presence
                    if ((1 << i) & fs) {
                        significant_in++;
                        this.push('Y');
                    } else {
                        this.push('N');
                    }
                }, [fs, observed], 0, rowcount_titles).concat(
                    significant_in, 
                    //(100 * (observed - expected) / Math.max(observed, expected)).toPrecision(3)
                    Math.log(observed / expected).toPrecision(3)
                ));
            }, 
            [row_all]
        ),

        // source data fields
        data_fields: forEach(_xExpList, function(val) {
            this.push({ key: 'eid' + val.eid });
        }, [
            { key: 'fs', parser: 'number' },
            { key: 'probe_count', parser: 'number'}
        ]).concat(
            { key: 'significant_in', parser: 'number'},
            { key: 'log_odds', parser: 'number'}
        ),

        // tfs table definitions
        table_defs: forEach(_xExpList, function(val) {
            this.push({
                key: 'eid' + val.eid,
                sortable: true,
                resizeable: false,
                label: '#' + val.eid + ' (' + val.pValClass + ')',
                sortOptions: {
                    defaultDir: YAHOO.widget.DataTable.CLASS_DESC
                },
                formatter:formatMark
            });
        }, [
{ key: 'fs', sortable:true, resizeable:false, label: 'Probe Subset', sortOptions: { defaultDir: YAHOO.widget.DataTable.CLASS_DESC }, formatter:formatterFlagsum},
{ key: 'probe_count', sortable:true, resizeable: false, label:'Probes', sortOptions: { defaultDir: YAHOO.widget.DataTable.CLASS_DESC }}
        ]).concat(
{ key: 'significant_in', sortable:true, resizeable: false, label:'Signif. in', sortOptions: { defaultDir: YAHOO.widget.DataTable.CLASS_DESC }, formatter:formatterSignIn},
{ key: 'log_odds', sortable:true, resizeable: true, label:'Log Odds Ratio' }
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
        {key:"reverse", sortable:true, resizeable:false, label:'Switched Samples', formatter:formatterYesNo},
        {key:"pValClass", sortable:true, resizeable:false, label:'P-value'},
        {key:"pval", sortable:true, resizeable:false, label:'P <'},
        {key:"fchange", sortable:true, resizeable:false, label:'|Fold| >'},
        {key:"probe_count", sortable:true, resizeable:false, label:'Signif. Probes', formatter:formatterProbeCounts}
    ];
    var summary_table = new YAHOO.widget.DataTable("summary_table", summary_table_defs, summary_data, {});

    //============== TFS breakdown table ================
    var tfs_config = {
        paginator: new YAHOO.widget.Paginator({
            rowsPerPage: 18 
        })
    };
    var tfs_data = new YAHOO.util.DataSource(tfs.records);
    tfs_data.responseSchema = {
        fields: tfs.data_fields
    };
    var tfs_table = new YAHOO.widget.DataTable("tfs_table", tfs.table_defs, tfs_data, tfs_config);
});
})();
