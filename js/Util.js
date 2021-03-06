"use strict"; 

var dom = YAHOO.util.Dom;

function ajaxError(o, verb, name, resourceURI) {
    return (o.responseText !== undefined) ? "Error encountered when attempting to " + verb + " " + name + " under " + resourceURI +".\nServer responded with code " + o.status + " (" + o.statusText + "):\n\n" + o.responseText : "Timeout on updating record (" + name + ") under " + resourceURI;
}


//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
// Scalar utilities
//==============================================================================
// zeroPad
// pad number `num' with zeros to `places' places
//==============================================================================
function zeroPad(num, places) {

    // pad number `num' with zeros to `places' places
    var zero = places - num.toString().length + 1;
    var arr = new Array(+(zero > 0 && zero));
    return arr.join("0") + num;
}
//==============================================================================
// formatCommas
// will add commas every three decimals to an integer representation of string
//==============================================================================
function formatCommas(numString) {
    var re = /(-?\d+)(\d{3})/;
    while (re.test(numString)) {
        numString = numString.replace(re, "$1,$2");
    }
    return numString;
}

//==============================================================================
// abbreviate
//==============================================================================
function abbreviate(str, len) {
    var abbrLen = len - 3;
    return str.length > abbrLen ? str.substr(0, abbrLen) + '...' : str;
}
//==============================================================================
// splitIntoPhrases
// Splits by words or by double-quoted phrases. Meant to emulate MySQL full-
// text searching.
// parameters: (1) string
// returns   : array
//==============================================================================
function splitIntoPhrases(str) {
    var extractQuoted = /^"([^"]*)"/;
    var extractWord = /^\W*(\w*)/;
    var phrases = [];
    var matched;
    while (str.length > 0) {
        // remove non-word non-quote characters from beginning
        str = str.replace(/^[^\w"]*/, '');
        
        var matchQuoted = extractQuoted.exec(str);
        if (matchQuoted !== null) {
            // extract quoted substring
            str = str.substring(matchQuoted[0].length);
            matched = matchQuoted[1];
            if (matched.length > 0) {
                phrases.push(matched);
            }
        } else {
            // extract first word ignoring quotes
            var matchWord = extractWord.exec(str);
            if (matchWord !== null) {
                str = str.substring(matchWord[0].length);
                matched = matchWord[1];
                if (matched.length > 0) {
                    phrases.push(matched);
                }
            } else {
                // terminate
                str = '';
            }
        }
    }
    return phrases;
}
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
// Loops
function LoopExit() {} // exception to exit a loop
//==============================================================================
// Iterate from a to b, step +1
// (replaces for loop)
//==============================================================================
function iterateForward(fun, out, from, to) {
    try {
        for (var i = from; i < to; i++) {
            fun.call(out, i);
        }
    }
    catch(e) {
        if (!(e instanceof LoopExit)) {
            throw e;
        }
    }
    return out;
}

//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
// Array utilities
//==============================================================================
// execute function fun() for all elements
//==============================================================================
function forEach(list, fun, out) {
    if (list !== null) {
        try {
            for (var i = 0, len = list.length; i < len; i++) {
                fun.call(out, list[i]);
            }
        }
        catch(e) {
            if (!(e instanceof LoopExit)) {
                throw e;
            }
        }
    }
    return out;
}
//==============================================================================
// execute function fun() for all pairs in the array
//==============================================================================
function forPairInList(list, fun, out) {
    if (list !== null) {
        try {
            for (var i = 0, len = list.length; i < len; i += 2) {
                fun.call(out, list[i], list[i + 1]);
            }
        }
        catch(e) {
            if (!(e instanceof LoopExit)) {
                throw e;
            }
        }
    }
    return out;
}
//==============================================================================
// convert a list to an object mapping
//==============================================================================
function pairs2obj(list, obj) {
    if (typeof(obj) === 'undefined' || obj === null) {
        obj = {};
    }
    return forPairInList(list, function(head, tail) {
        this[head] = tail;
    }, obj);
}
//==============================================================================
// returns a new array containing a specified subset of the old one
//==============================================================================
function selectFromArray(array, subset) {
    var subset_length = subset.length;
    var result = new Array(subset_length);
    for (var i = 0; i < subset_length; i++) {
        result[i] = array[subset[i]];
    }
    return result;
}

//==============================================================================
// sort tuples by column
//==============================================================================
function ComparisonSortOnColumn(column) {
    return function (a, b) {
        a = a[column];
        b = b[column];
        return a < b ? -1 : (a > b ? 1 : 0);
    };
}
function sortNestedByColumn(tuples, column) {
    return tuples.sort(ComparisonSortOnColumn(column)); 
}

//==============================================================================
// sort tuples by column (numeric)
//==============================================================================
function NumericSortOnColumn(column) {
    return function (a, b) {
        return a[column] - b[column];
    };
}
function sortNestedByColumnNumeric(tuples, column) {
    return tuples.sort(NumericSortOnColumn(column)); 
}
function NumericSortOnColumnDesc(column) {
    return function (a, b) {
        return b[column] - a[column];
    };
}
function sortNestedByColumnNumericDesc(tuples, column) {
    return tuples.sort(NumericSortOnColumnDesc(column)); 
}
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
// Object utilities
//==============================================================================
// iterate over key-value pairs -- three function imitating Perl's each, keys,
// and values.
//==============================================================================
function tuplesToObj() {
    // takes a list of tuples and converts them to an object
    var obj = {};
    for (var i = 0, len = arguments.length; i < len; i++) {
        var tuple = arguments[i];
        obj[tuple[0]] = tuple[1];
    }
    return obj;
}
function countOwnProperties(obj) {
    var i = 0;
    for (var key in obj) {
        if (obj.hasOwnProperty(key)) {
            i++;
        }
    }
    return i;
}
function object_forEach(obj, fun, out) {
    try {
        for (var key in obj) {
            if (obj.hasOwnProperty(key)) {
                var val = obj[key];
                fun.call(out, key, val);
            }
        }
    } catch(e) {
        if (!(e instanceof LoopExit)) {
            throw e;
        }
    }
    return out;
}
function object_forKeys(obj, fun, out) {
    try {
        for (var key in obj) {
            if (obj.hasOwnProperty(key)) {
                fun.call(out, key);
            }
        }
    } catch(e) {
        if (!(e instanceof LoopExit)) {
            throw e;
        }
    }
    return out;
}
function object_forValues(obj, fun, out) {
    try {
        for (var key in obj) {
            if (obj.hasOwnProperty(key)) {
                fun.call(out, obj[key]);
            }
        }
    } catch(e) {
        if (!(e instanceof LoopExit)) {
            throw e;
        }
    }
    return out;
}
//==============================================================================
// count number of own properties in object
//==============================================================================
function object_length(obj) {
    var size = 0, key;
    for (key in obj) {
        if (obj.hasOwnProperty(key)) {
            size++;
        }
    }
    return size;
}
//==============================================================================
// return array of keys in the object
//==============================================================================
function object_keys(obj) {
    var ret = [];
    for (var key in obj) {
        if (obj.hasOwnProperty(key)) {
            ret.push(key);
        }
    }
    return ret;
}
//==============================================================================
// delete all own properties in the object
//==============================================================================
function object_clear(obj) {
    for (var key in obj) {
        if (obj.hasOwnProperty(key)) {
            delete obj[key];
        }
    }
    return obj;
}
//==============================================================================
// add a single value to all keys
//==============================================================================
function object_add(obj, keys, val) {
    for (var i = 0, len = keys.length; i < len; i++) {
        obj[keys[i]] = val;
    }
}

//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
// DOM utilities
//==============================================================================
// remove all children from element
//==============================================================================
function removeAllChildren(el) {
    while (el.firstChild) {
        el.removeChild(el.firstChild);
    }
    return el;
}

//==============================================================================
// getSelectedValue
//==============================================================================
function getSelectedValue(obj)
{
    try {
        return obj.options[obj.selectedIndex].value;
    } catch(e) {
        // avoid rethrow: cannot be set because no option was selected
        if (!(e instanceof TypeError || e instanceof DOMException)) {
            throw e;
        }
    }
}
//==============================================================================
// getSelectedFromRadioGroup
//==============================================================================
function getSelectedFromRadioGroup(obj) {
    return forEach(obj, function(button) {
        if (button.checked) {
            this.firstChecked = button.value;
            throw new LoopExit;
        }
    }, {}).firstChecked;
}
//==============================================================================
// isDefinedSelection
// Will work both on INPUT elements (uses el.value) and on SELECT elements 
// (checks if any OPTION elements are selected).
// returns 'defined' if yes, '' otherwise
//==============================================================================
function isDefinedSelection(el) { 
    if (el === null) { return ''; }
    var val = (el.nodeName === 'SELECT' ? getSelectedValue(el) : el.value); 
    return (typeof val !== 'undefined' && val !== '') ? 'defined' : '';
}

//==============================================================================
// EnableDisable
//==============================================================================
function EnableDisable(el, disabled) {
    forEach(dom.getChildren(el), function(child) {
        if (child.tagName === 'INPUT') {
            child.disabled = disabled;
        } else if (disabled !== '') {
            dom.addClass(child, 'disabled');
        } else {
            dom.removeClass(child, 'disabled');
        }
        EnableDisable(child, disabled);
    });
}

//==============================================================================
// Recurse upward in the DOM hierarchy and return the first node that matches
// the requested node name
//==============================================================================
function getFirstParentOfName(id, parentName) {
    var el = dom.get(id);
    if (el === null) {
        return null;
    }
    var elParent = el.parentNode;
    if (elParent === null) {
        return null;
    }
    return (elParent.nodeName.toUpperCase() === parentName.toUpperCase()) ? elParent : getFirstParentOfName(elParent, parentName);
}
//==============================================================================
// build dropdown
//==============================================================================
function buildDropDown(obj, tuples, selected, old) {
    if (obj === null) {
        return;
    }
    function setMinWidth(el, width, old) {
        // sets minimum width for an element with content

        // first see if scrollWidth is greater than zero. If yes, reuse offsetWidth
        // instead of setting minimum. Only when scrollWidth is zero do we set
        // style.width.
        el.style.width = (old.scrollWidth > 0) ? old.offsetWidth + 'px' : width;
    }
    if (tuples.length > 0) {
        // reset width for automatic width control
        obj.style.width = '';
    } else {
        // set width to either old (if present) or minimum
        setMinWidth(obj, '200px', old);
    }
    var haveSelected = typeof(selected) !== 'undefined';
    forEach(tuples, function(tuple) {
        var key = tuple[0];
        var option = document.createElement('option');
        option.setAttribute('value', key);
        if (haveSelected && selected.hasOwnProperty(key)) {
            option.selected = 'selected';
        }
        option.innerHTML = tuple[1];
        obj.appendChild(option);
    });
}

//==============================================================================
// clear dropdown
//==============================================================================
function clearDropDown(obj) {
    // capture old width
    if (obj === null) {
        return { clientWidth: 0, offsetWidth: 0, scrollWidth: 0 };
    }
    var oldWidth = { 
        clientWidth: obj.clientWidth, 
        offsetWidth: obj.offsetWidth, 
        scrollWidth: obj.scrollWidth 
    };
    // remove option elements
    while (obj.options[0]) {
        obj.removeChild(obj.options[0]);
    }
    return oldWidth;
}

//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
// YUI helpers
//==============================================================================
// YUI helper: call 'subscribe' method on element 'el' with obj as special 
// argument; obj is structured like the following: 
// {
//      'click': function() { ... },
//      'mousedown': onMousedown,
//  }
//==============================================================================
function subscribeEnMasse(el, obj) {
    object_forEach(obj, function(event, handler) {
        el.subscribe(event, handler);
    });
}
//==============================================================================
// highlight editable cell in DataTable control
//==============================================================================
function highlightEditableCell(oArgs) { 
    var elCell = oArgs.target; 
    if (YAHOO.util.Dom.hasClass(elCell, "yui-dt-editable")) {
        // in the call context, `this' is a reference to YUI DataTable object
        this.highlightCell(elCell); 
    } 
}

//==============================================================================
// YUI helper: tab views
//==============================================================================
function selectTabFromHash(tabView) {
    var url = window.location.href.split('#')[1];
    if (!url) { return; };

    // We have a hash
    var tabHash = '#' + url;
    forEach(tabView.get('tabs'), function(tab) {
        if (tab.get('href') === tabHash) {
            tabView.set('activeIndex', this.index);
            throw new LoopExit;
        }
        this.index++;
    }, {index: 0});
}

//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
// Misc
//==============================================================================
// incrementDropdown
//==============================================================================
function lastIsSelected(obj) {
    var len = obj.options.length;
    var ind = obj.selectedIndex;
    return ind === len - 1;
}
function incrementDropdown(obj) {
    if (!lastIsSelected(obj)) {
        obj.selectedIndex++;
    }
}

//==============================================================================
// export_table
//==============================================================================
function export_table(e) {
    var this_records = this.records;
    var this_headers = this.headers;

    var win = window.open("");
    var doc = win.document.open("text/html");
    doc.title = "Tab-Delimited Text";
    doc.write("<pre>\n");

    // table head
    var col_count;
    if (typeof(this_headers) !== 'undefined' && this_headers !== null) {
        col_count = this_headers.length;
        doc.write(this_headers.join("\t"));
        doc.write("\n");
    }

    // table body
    forEach(this_records, function(row) {
        doc.write(row.join("\t"));
        doc.write("\n");
    });

    doc.write("</pre>\n");
    doc.close();
    win.focus();
}
//==============================================================================
// setupToggles
// See FormFindProbes.js for example usage of this function
//==============================================================================
function setupToggles(event, attr, getValue, callBack) {

    function createToggle(id) {
        var obj = document.getElementById(id);
        var inv_prop = inverse_attr[id];

        // fill out 'dependents' helper hash
        var dependents = object_forKeys(inv_prop, function(inv_id) {
            this[inv_id] = document.getElementById(inv_id);
        }, {});

        return function() {
            // need to hide all objects not referenced by sel and show all
            // objects that are.
            var sel = getValue(obj);
            object_forEach(dependents, function(dep_id, dep_obj) {
               if (dep_obj !== null) {
                    var inv_obj = inv_prop[dep_id];
                    var style = inv_obj.hasOwnProperty(sel) ? 'block' : 'none';
                    dep_obj.style.display = style;
                }
            });
            return true;
        };
    }

    // inverse the inside hash
    // converts {x: {a: [1, 2, ...]}} into
    // {x: {1: {a: null}, 2: {a: null}, ...}}
    var inverse_attr = object_forEach(attr, function(id, hash) {
        this[id] = object_forEach(hash, function(key, idList) {
            var tmp = this;
            forEach(idList, function(el) {
                tmp[el] = pairs2obj([key, null], tmp[el]);
            });
        }, {});
    }, {});

    // code below must be performed when DOM is loaded
    object_forKeys(attr, function(id) {
        var toggle = createToggle(id);
        toggle();
        var toggleCallBack = ((typeof callBack !== 'undefined') ? function () { callBack(this); return toggle(); } : toggle);
        YAHOO.util.Event.addListener(
            id, event, toggleCallBack, document.getElementById(id)
        );
    });
}

//====
//
//====
function setupPPDropdowns(arr) {
    var obj = forPairInList(arr, function(key, val) { this[key] = val; }, {});
    forPairInList(arr, function(key, val) {
        forPairInList(val.updateViewOn, function(id, event) {
            YAHOO.util.Event.addListener(
                id, event, val.updateMethod, obj, true
            );
        });
    });
}

//==============================================================================
// triggerEvent
//==============================================================================
function triggerEvent(obj, event) {
    var listeners = YAHOO.util.Event.getListeners(obj, event);
    forEach(listeners, function(listener) {
        listener.fn.apply(listener.scope);
    });
}

//==============================================================================
// validate_fields
//==============================================================================
function validate_fields(of,reqfields) {

    // clear error messages
    var content_div = document.getElementById('content');
    var error_container = document.getElementById('message');
    if (error_container !== null ) {
        error_container.parentNode.removeChild(error_container);
    }
    var errorMsg = "There is a problem with your input. Please fill out or correct the highlighted field(s).";

    // split the required fields and loop throught them
    forEach(reqfields, function(el) {
        // get a required field
        var f=document.getElementById(el);
        if (f === null ) {
            // cannot find the required field in the DOM body
            return false;
        }
        // cleanup: remove old classes from the required fields
        dom.removeClass(f.parentNode, 'error');
        // completely strip whitespace and place field value into value 
        // test if the required field has an error, according to its type
        var value;
        switch(f.type.toLowerCase()) {
            case "text":
                value = f.value.replace(/ /g,"");
                switch(f.id.toLowerCase()) {
                    case "email":
                    case "email1":
                    case "email2":
                        if(!cf_isEmailAddr(value )) { cf_adderr(f); }
                        break;
                    default:
                        if(value  === "") {cf_adderr(f); }
                }
                break;
            case "select-one":
                value = getSelectedValue(f);
                if (value ===""){ cf_adderr(f); }
                break;
            case "file":
            case "textarea":
            case "password":
                value = f.value.replace(/ /g,"");
                if(value ===""){ cf_adderr(f); }
                break;
        }
    });
    return (document.getElementById('message') === null);

    /* tool methods */
    function cf_adderr(o) {
        // colourise the error fields
        dom.addClass(o.parentNode, 'error');
        // check if there is no error message
        if(document.getElementById('message') === null) {
            // create errormessage and insert before submit button
            error_container = document.createElement('div');
            error_container.id = 'message';
            var newp=document.createElement("p");
            dom.addClass(newp, 'error');
            newp.appendChild(document.createTextNode(errorMsg));
            error_container.appendChild(newp);
            content_div.insertBefore(error_container, content_div.firstChild);
            window.location.hash = 'message';
        }
    }
    function cf_isEmailAddr(str) {
        // RFC 2822 regex from
        // http://www.regular-expressions.info/email.html
        return str.match(/(?:[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*|"(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21\x23-\x5b\x5d-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])*")@(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?|\[(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?|[a-z0-9-]*[a-z0-9]:(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21-\x5a\x53-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])+)\])/);
    }
}
