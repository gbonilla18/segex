"use strict";
// dropdown list
setupToggles({
    'pattern': {
        'part' : ['pattern_part_hint']
    }, 
    'opts'   : {
        'basic': ['graph_names', 'graph_values'],
        'full' : ['graph_names', 'graph_values']
    }
}, function(el) { return getSelectedValue(el); });

// checkbox
setupToggles({
    'graph'  : {
        'checked': ['graph_option_values']
    }
}, function(el) { return (el.checked) ? 'checked' : null; });

YAHOO.util.Event.addListener('main_form', 'submit', function() {
    // remove white space from the left and from the right, then replace each
    // internal group of spaces with a comma
    var terms = document.getElementById("q");
    terms.value = terms.value.replace(/^\s+/, "").replace(/\s+$/, "").replace(/[,\s]+/g, ",");
    return true;
});
///////////////////////////////////////////////////////////
var oButtonGroupFilter = new YAHOO.widget.ButtonGroup({
    id: 'buttongroupFilter', 
    name: 'radiofieldFilter', 
    container:  'locusFilter', 
    usearia: true
});
oButtonGroupFilter.addButtons([
    { id: 'none', value: 'none', label: 'No Filter', checked: true },
    { id: 'range', value: 'range', label: 'Chr. Range' }
]);
oButtonGroupFilter.on('checkedButtonChange', function (p_oEvent) {
    // drop "-button" suffix from button id
    var btnValue = p_oEvent.newValue._button.id.replace(/-button$/i, '');
    toggleFilterOptions(btnValue);
});
function toggleFilterOptions(selectedRadio)
{
    var filterLoci = document.getElementById("filterLoci");
    if(selectedRadio === 'none')
    {
        filterLoci.style.display = 'none';
    }
    else if(selectedRadio === 'range')
    {
        filterLoci.style.display = 'block';
    }    
    else
    {
        throw "Invalid button selected: " + selectedRadio;
    }
}

