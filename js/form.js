"use strict"; 

//==============================================================================
// tab views
//==============================================================================
function selectTabFromHash(tabView) {
    var url = window.location.href.split('#');
    if (url[1]) {
        // We have a hash
        var tabHash = url[1];
        var tabs = tabView.get('tabs');
        for (var i = 0, tl = tabs.length; i < tl; i++) {
            if (tabs[i].get('href') == '#' + tabHash) {
                tabView.set('activeIndex', i);
                break;
            }
        }
    }
}
//==============================================================================
// export_table
//==============================================================================
function export_table(e) {
    var records = this.records;
    var row_count = records.length;

    var win = window.open("");
    var doc = win.document.open("text/html");
    doc.title = "Tab-Delimited Text";
    doc.write("<pre>\n");

    // table head
    var col_count;
    if (this.headers) {
        col_count = this.headers.length;
        doc.write(this.headers.join("\t"));
        doc.write("\n");
    }

    // table body
    for (var i = 0; i < row_count; i++) {
        var row_hash = records[i];
        var row_array = [];
        if (col_count) {
            // fill up until col_count
            for (var j = 0; j < col_count; j++) {
                row_array.push(row_hash[j]);
            }
        } else {
            // fill up until the first empty element
            for (var j = 0; row_hash[j]; j++) {
                row_array.push(row_hash[j]);
            }
        }
        doc.write(row_array.join("\t"));
        doc.write("\n");
    }

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
        var dependents = {};
        for (var inv_id in inv_prop) {
            dependents[inv_id] = document.getElementById(inv_id);
        }

        return function() {
            var sel = getValue(obj);
            // need to hide all objects not referenced by sel
            // and show all objects that are.
            for (var dep_id in dependents) {
                var dep_obj = dependents[dep_id];
                if (dep_obj !== null) {
                    dep_obj.style.display = 
                    (sel in inv_prop[dep_id]) ? 'block' : 'none';
                }
            }
            return true;
        }
    }

    // inverse the inside hash
    var inverse_attr = {};
    for (var id in attr) {
        var hash = attr[id];
        var tmp = {};
        for (var key in hash) {
            var idList = hash[key];
            for (var i = 0, len = idList.length; i < len; i++) {
                var id2 = idList[i];
                if (id2 in tmp) {
                    tmp[id2][key] = null;
                } else {
                    var tmp2 = {};
                    tmp2[key] = null;
                    tmp[id2] = tmp2;
                }
            }
        }
        inverse_attr[id] = tmp;
    }

    // code below must be performed when DOM is loaded
    for (var id in attr) {
        var toggle = createToggle(id);
        toggle();
        var el = document.getElementById(id);
        YAHOO.util.Event.addListener(
            id, 
            event, 
            (typeof callBack !== 'undefined') 
            ? function() { callBack(el); toggle(); } 
            : function() { toggle();  }
        );
    }
}
//==============================================================================
// deleteConfirmation
//==============================================================================
function deleteConfirmation(oArg)
{
    var itemName = (oArg && oArg.itemName) ? oArg.itemName : "item";
    var msg = "Are you sure you want to delete this " + itemName  + "?";
    if (oArg && oArg.childName) {
        msg += " Deleting it will also remove any " + childName + "(s) it contains."; 
    }
    return confirm(msg);
}
//==============================================================================
// getSelectedValue
//==============================================================================
function getSelectedValue(obj)
{
    try {
        return obj.options[obj.selectedIndex].value;
    } catch(e) {
        if (e instanceof TypeError || e instanceof DOMException) {
            // cannot be set because no option was selected
        } else {
            // other error types: rethrow exception
            throw e;
        }
    }
}
//==============================================================================
// getSelectedFromRadioGroup
//==============================================================================
function getSelectedFromRadioGroup(obj) {
    for (var i = 0, len = obj.length; i < len; i++) {
        var button = obj[i];
        if (button.checked) {
            return button.value;
        }
    }
    return null;
}
//==============================================================================
// EnableDisable
//==============================================================================
function EnableDisable(el, disabled) {
    var children = dom.getChildren(el);
    var len = children.length;
    for (var i = 0; i < len; i++) {
        var child = children[i];
        if (child.tagName === 'INPUT') {
            child.disabled = disabled;
        } else if (disabled !== '') {
            dom.addClass(child, 'disabled');
        } else {
            dom.removeClass(child, 'disabled');
        }
        EnableDisable(child, disabled);
    }
}
//==============================================================================
// isDefinedSelection
// returns 'defined' if yes, '' otherwise
//==============================================================================
function isDefinedSelection(el) { 
    var val = getSelectedValue(el); 
    return (typeof val !== 'undefined' && val !== '') ? 'defined' : '';
}
//==============================================================================
// validate_fields
//==============================================================================
function validate_fields(of,reqfields) {

    var dom = YAHOO.util.Dom;

    // clear error messages
    var content_div = document.getElementById('content');
    var error_container = document.getElementById('message');
    if (error_container !== null ) {
        error_container.parentNode.removeChild(error_container);
    }
    var errorMsg = "There is a problem with your input. Please fill out or correct the highlighted field(s).";

    // split the required fields and loop throught them
    for (var i = 0, len = reqfields.length; i < len; i++) {
        // get a required field
        var f=document.getElementById(reqfields[i]);
        if (f === null ) {
            // cannot find the required field in the DOM body
            return false;
        }
        // cleanup: remove old classes from the required fields
        dom.removeClass(f.parentNode, 'error');
        // completely strip whitespace and place field value into value 
        // test if the required field has an error, according to its type
        switch(f.type.toLowerCase()) {
            case "text":
                var value = f.value.replace(/ /g,"");
                switch(f.id.toLowerCase()) {
                    case "email":
                    case "email1":
                    case "email2":
                        if(!cf_isEmailAddr(value )) {cf_adderr(f)}
                        break;
                    default:
                        if(value  === "") {cf_adderr(f)}
                }
                break;
            case "select-one":
                var value = getSelectedValue(f);
                if (value ===""){cf_adderr(f)}
                break;
            case "file":
            case "textarea":
            case "password":
                var value = f.value.replace(/ /g,"");
                if(value ===""){cf_adderr(f)}
                break;
        }
    }
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
            newp.appendChild(document.createTextNode(errorMsg))
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
