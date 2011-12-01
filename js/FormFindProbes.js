"use strict";
// dropdown list
setupToggles('change', {
    'pattern': {
        'part' : ['pattern_part_hint']
    }, 
    'opts'   : {
        'basic': ['graph_names', 'graph_values'],
        'full' : ['graph_names', 'graph_values']
    }
}, function(el) { return getSelectedValue(el); });

// checkbox
setupToggles('change', {
    'graph'  : {
        'checked': ['graph_option_values']
    }
}, function(el) { return (el.checked) ? 'checked' : null; });

setupToggles('click', {
    'locusFilter' : {
        '-': ['filterLoci', 'extraText']
    }
}, 
function(el) { return el.text.substr(0, 1); },
function(el) { 
    if (el.text.substr(0, 1) == '+') {
        el.text = '-' + el.text.substr(1);
    } else {
        el.text = '+' + el.text.substr(1);
        clearLocation();
    }
});

YAHOO.util.Event.addListener('main_form', 'submit', function() {
    // remove white space from the left and from the right, then replace each
    // internal group of spaces with a comma
    var terms = document.getElementById("q");
    terms.value = terms.value.replace(/^\s+/, "").replace(/\s+$/, "").replace(/[,\s]+/g, ",");
    return true;
});

function clearLocation()
{
    var filterLoci = document.getElementById("filterLoci");
    document.getElementById("sid").value = '';
    document.getElementById("chr").value = '';
    document.getElementById("start").value = '';
    document.getElementById("end").value = '';
}

