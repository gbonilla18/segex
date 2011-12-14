"use strict";

YAHOO.util.Event.addListener('main_form', 'submit', function() {
    // remove white space from the left and from the right, then replace each
    // internal group of spaces with a comma
    var terms = document.getElementById("q");
    terms.value = terms.value.replace(/^\s+/, "").replace(/\s+$/, "").replace(/[,\s]+/g, ",");
    return true;
});
YAHOO.util.Event.addListener(window, 'load', function() {
    setupToggles('change',
        { 'spid': { 'defined' : ['chr_div' ] } }, 
        isDefinedSelection
    );

    // scope
    var scope_state = document.getElementById("scope_state");
    var pattern_div = document.getElementById('pattern_div');
    var scope = new YAHOO.widget.ButtonGroup("scope_container");
    scope.addListener("checkedButtonChange", function(ev) {
        var selectedIndex = ev.newValue.index;
        scope_state.value = selectedIndex;
        if (selectedIndex === 0 ) {
            pattern_div.style.display = 'block';
        } else {
            pattern_div.style.display = 'none';
        }
    });
    if (scope_state.value !== '') {
        scope.check(scope_state.value);
    }

    // pattern/match
    var pattern_state = document.getElementById("pattern_state");
    var patterns = new YAHOO.widget.ButtonGroup("pattern_container");
    var pattern_part_hint = document.getElementById('pattern_part_hint');
    patterns.addListener("checkedButtonChange", function(ev) {
        var selectedIndex = ev.newValue.index;
        pattern_state.value = selectedIndex;
        if (selectedIndex === 2) {
            pattern_part_hint.style.display = 'block';
        } else {
            pattern_part_hint.style.display = 'none';
        }
    });
    if (pattern_state.value !== '') {
        patterns.check(pattern_state.value);
    }

    // graphs
    var graph_container = document.getElementById("graph_everything_container");
    var graph_hint = document.getElementById('graph_hint');
    var graphs = new YAHOO.widget.ButtonGroup('graph_container');
    var graphs_state = document.getElementById('graph_state');
    graphs.addListener("checkedButtonChange", function(ev) {
        var selectedIndex = ev.newValue.index;
        graphs_state.value = selectedIndex;
        if (selectedIndex !== 0) {
            graph_hint.style.display = 'block';
        } else {
            graph_hint.style.display = 'none';
        }
    });
    if (graphs_state.value !== '') {
        graphs.check(graphs_state.value);
    }

    // Output options
    var opts = new YAHOO.widget.ButtonGroup("opts_container");
    var opts_state = document.getElementById('opts_state');
    opts.addListener("checkedButtonChange", function(ev) {
        var selectedIndex = ev.newValue.index;
        opts_state.value = selectedIndex;
        if (selectedIndex !== 2) {
            graph_container.style.display = 'block';
        } else {
            graph_container.style.display = 'none';
        }
    });
    if (opts_state.value !== '') {
        opts.check(opts_state.value);
    }

});
