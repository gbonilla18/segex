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
    setupToggles('change',
        { 'show_graphs': { 'checked' : [ 'graph_hint_container', 'graph_hint' ] }},
        function(el) { return (el.checked) ? 'checked' : ''; }
    );
    var pattern_part_hint = document.getElementById('pattern_part_hint');
    YAHOO.util.Event.addListener('full_word', 'change', function() {
        pattern_part_hint.style.display = (this.checked) ? 'none' : 'block';
    });
    YAHOO.util.Event.addListener('prefix', 'change', function() {
        pattern_part_hint.style.display = (this.checked) ? 'none' : 'block';
    });
    YAHOO.util.Event.addListener('partial', 'change', function() {
        pattern_part_hint.style.display = (this.checked) ? 'block' : 'none';
    });

    // scope
    var pattern_div = document.getElementById('pattern_div');
    var scope_list_state = document.getElementById("scope_list_state");
    var scope_file_state = document.getElementById("scope_file_state");
    var scope_list = new YAHOO.widget.ButtonGroup("scope_list_container");
    var scope_file = new YAHOO.widget.ButtonGroup("scope_file_container");
    scope_list.addListener("checkedButtonChange", function(ev) {
        var selectedIndex = ev.newValue.index;
        scope_list_state.value = selectedIndex;
        switch (selectedIndex) {
        case 0:
            pattern_div.style.display = 'none';
            break;
        case 1:
            pattern_div.style.display = 'block';
            break;
        case 2:
        case 3:
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
});
