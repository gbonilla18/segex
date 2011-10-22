YAHOO.util.Event.addListener(window, 'load', function() {

    // dropdown list
    setupToggles({
        'pattern': {'part': ['pattern_part_hint']}, 
        'opts'   : {'1'   : ['graph_names', 'graph_values'],
            '2'   : ['graph_names', 'graph_values']}
      }, 
      function(el) { return el.options[el.selectedIndex].value; }
    );

    // checkbox
    setupToggles({
        'graph'  : {'checked': ['graph_option_values']}
      }, 
      function(el) { return (el.checked) ? 'checked' : null; }
    );
});

YAHOO.util.Event.addListener('main_form', 'submit', function() {
    var terms = document.getElementById("terms");
    // remove white space from the left and from the right, then replace each
    // internal group of spaces with a comma
    terms.value = terms.value.replace(/^\s+/, "").replace(/\s+$/, "").replace(/[,\s]+/g, ",");
    return true;
});
