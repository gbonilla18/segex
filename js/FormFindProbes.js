"use strict";

var dom = YAHOO.util.Dom;

YAHOO.util.Event.addListener('main_form', 'submit', function() {
    // remove white space from the left and from the right, then replace each
    // internal group of spaces with a comma
    var terms = dom.get("q");
    terms.value = terms.value.replace(/^\s+/, "").replace(/\s+$/, "");
    return true;
});

YAHOO.util.Event.addListener(window, 'load', function() {
    setupToggles('change',
        { 'spid': { 'defined' : ['chr_div' ] } }, 
        function(el) {
            var result = isDefinedSelection(el);
            EnableDisable('location_block', (result ? '' : 'disabled'));
            return result;
        }
    );
    setupToggles('change',
        { 'show_graphs': { 'checked' : [ 'graph_hint_container', 'graph_hint' ] }},
        function(el) { return (el !== null && el.checked) ? 'checked' : ''; }
    );

    // handle changes in both pattern and scope
    var pattern_part_hint = dom.get('pattern_part_hint');
    var pattern_fullword_hint = dom.get('pattern_fullword_hint');
    var scope = new YAHOO.widget.ButtonGroup("scope_container");
    var match_buttons = dom.get(['full_word', 'prefix', 'partial']);
    var pattern_div = dom.get('pattern_div');

    function displayHintPanels() {
        var currentScope = scope.get('checkedButton').get('value');
        var currentMatch = getSelectedFromRadioGroup(match_buttons);
        switch (currentScope) {
            case 'Probe IDs':
            case 'GO IDs':
                pattern_div.style.display = 'none';
                pattern_fullword_hint.style.display = 'block';
            break;
            default:
                pattern_div.style.display = 'block';
                pattern_fullword_hint.style.display = 'none';
            break;
        }
        switch (currentMatch) {
            case 'Full-Word':
                pattern_part_hint.style.display = 'none';
                switch (currentScope) {
                    case 'Gene Names/Desc.':
                    case 'GO Names':
                    case 'GO Names/Desc.':
                        pattern_fullword_hint.style.display = 'block';
                    break;
                    default:
                        pattern_fullword_hint.style.display = 'none';
                    break;
                }
                break;
            case 'Partial':
                pattern_part_hint.style.display = 'block';
                pattern_fullword_hint.style.display = 'none';
                break;
            default:
                pattern_part_hint.style.display = 'none';
                pattern_fullword_hint.style.display = 'none';
                break;
        }
    }
    displayHintPanels();
    for (var i = 0, len = match_buttons.length; i < len; i++) {
        YAHOO.util.Event.addListener(match_buttons[i], 'change', function() {
            displayHintPanels();
        });
    }

    // scope
    var scope_state = dom.get("scope_state");
    scope.addListener("checkedButtonChange", function(ev) {
        var selectedIndex = ev.newValue.index;
        scope_state.value = selectedIndex;
        displayHintPanels();
    });
    if (scope_state.value !== '') {
        scope.check(scope_state.value);
    }

    var scope_file = new YAHOO.widget.ButtonGroup("scope_file_container");
    var scope_file_state = dom.get("scope_file_state");
    scope_file.addListener("checkedButtonChange", function(ev) {
        var selectedIndex = ev.newValue.index;
        scope_file_state.value = selectedIndex;
    });
    if (scope_file_state.value !== '') {
        scope_file.check(scope_file_state.value);
    }
});
