"use strict";

YAHOO.util.Event.addListener('main_form', 'submit', function() {
    // remove white space from the left and from the right, then replace each
    // internal group of spaces with a comma
    var terms = document.getElementById("q");
    terms.value = terms.value.replace(/^\s+/, "").replace(/\s+$/, "");
    return true;
});

YAHOO.util.Event.addListener(window, 'load', function() {
    setupToggles('change',
        { 'spid': { 'defined' : ['chr_div' ] } }, 
        isDefinedSelection
    );

    // scope
    var pattern_div = document.getElementById('pattern_div');
    var scope_list_state = document.getElementById("scope_list_state");
    var scope_file_state = document.getElementById("scope_file_state");
    var scope_list = new YAHOO.widget.ButtonGroup("scope_list_container");
    var scope_file = new YAHOO.widget.ButtonGroup("scope_file_container");
    var patterns = new YAHOO.widget.ButtonGroup("pattern_container");
    scope_list.addListener("checkedButtonChange", function(ev) {
        var selectedIndex = ev.newValue.index;
        scope_list_state.value = selectedIndex;
        switch (selectedIndex) {
        case 0:
            patterns.check(0);
            pattern_div.style.display = 'none';
            break;
        case 1:
            patterns.check(0);
            pattern_div.style.display = 'block';
            break;
        case 2:
        case 3:
            patterns.check(1);
            pattern_div.style.display = 'block';
            break;
        }
    });
    if (scope_list_state.value !== '') {
        scope_list.check(scope_list_state.value);
    }
    scope_file.addListener("checkedButtonChange", function(ev) {
        var selectedIndex = ev.newValue.index;
        scope_file_state.value = selectedIndex;
    });
    if (scope_file_state.value !== '') {
        scope_file.check(scope_file_state.value);
    }

    // pattern/match
    var pattern_state = document.getElementById("pattern_state");
    var pattern_part_hint = document.getElementById('pattern_part_hint');
    patterns.addListener("checkedButtonChange", function(ev) {
        var selectedIndex = ev.newValue.index;
        pattern_state.value = selectedIndex;
        if (selectedIndex === 1) {
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
