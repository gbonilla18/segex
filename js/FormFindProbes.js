YAHOO.util.Event.addListener(window, 'load', function() {

    // dropdown list
    setupToggles({
        'pattern': {
            'part' : ['pattern_part_hint']
        }, 
        'opts'   : {
            'basic': ['graph_names', 'graph_values'],
            'full' : ['graph_names', 'graph_values']
        }
    }, function(el) { return el.options[el.selectedIndex].value; });

    // checkbox
    setupToggles({
        'graph'  : {
            'checked': ['graph_option_values']
        }
    }, function(el) { return (el.checked) ? 'checked' : null; });
});

YAHOO.util.Event.addListener('main_form', 'submit', function() {
    // remove white space from the left and from the right, then replace each
    // internal group of spaces with a comma
    var terms = document.getElementById("terms");
    terms.value = terms.value.replace(/^\s+/, "").replace(/\s+$/, "").replace(/[,\s]+/g, ",");
    return true;
});
