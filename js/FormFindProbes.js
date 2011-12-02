"use strict";
setupToggles('change',
    { 'spid': { 'defined' : ['chr_div' ] } }, 
    function(el) { return ((getSelectedValue(el) !== '') ? 'defined' : ''); }
);
setupToggles('click', {
        'locusFilter' : {
            '-': ['locus_container']
        },
    }, 
    function(el) { return el.text.substr(0, 1); },
    function(el) { 
        if (el.text.substr(0, 1) == '+') {
            el.text = '-' + el.text.substr(1);
        } else {
            el.text = '+' + el.text.substr(1);
        }
});
setupToggles('click', {
        'patternMatcher': {
            '-': ['pattern_hint_container']
        }
    }, 
    function(el) { return el.text.substr(0, 1); },
    function(el) { 
        if (el.text.substr(0, 1) == '+') {
            el.text = '-' + el.text.substr(1);
        } else {
            el.text = '+' + el.text.substr(1);
        }
});
setupToggles('click', {
        'outputOpts': {
            '-': ['opts_hint_container']
        }
    }, 
    function(el) { return el.text.substr(0, 1); },
    function(el) { 
        if (el.text.substr(0, 1) == '+') {
            el.text = '-' + el.text.substr(1);
        } else {
            el.text = '+' + el.text.substr(1);
        }
});


YAHOO.util.Event.addListener('main_form', 'submit', function() {
    // remove white space from the left and from the right, then replace each
    // internal group of spaces with a comma
    var terms = document.getElementById("q");
    terms.value = terms.value.replace(/^\s+/, "").replace(/\s+$/, "").replace(/[,\s]+/g, ",");
    return true;
});
YAHOO.util.Event.addListener(window, 'load', function() {
    new YAHOO.widget.ButtonGroup("scope_container");
    var patterns = new YAHOO.widget.ButtonGroup("pattern_container");
    var pattern_part_hint = document.getElementById('pattern_part_hint');
    patterns.addListener("checkedButtonChange", function(ev) {
        if (ev.newValue.index === 2) {
            pattern_part_hint.style.display = 'block';
        } else {
            pattern_part_hint.style.display = 'none';
        }
    });
    var graph_container = document.getElementById("graph_container");
    var graph_hint = document.getElementById('graph_hint');
    var graphs = new YAHOO.widget.ButtonGroup(graph_container);
    graphs.addListener("checkedButtonChange", function(ev) {
        if (ev.newValue.index !== 0) {
            graph_hint.style.display = 'block';
        } else {
            graph_hint.style.display = 'none';
        }
    });
    var opts = new YAHOO.widget.ButtonGroup("opts_container");
    opts.addListener("checkedButtonChange", function(ev) {
        if (ev.newValue.index !== 2) {
            graph_container.style.display = 'block';
        } else {
            graph_container.style.display = 'none';
            graphs.check(0); // turn off graphs
        }
    });
});
