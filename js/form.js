function $() {
    var elements = new Array();
    for (var i = 0; i < arguments.length; i++) {
        var element = arguments[i];
        if (typeof element == 'string')
            element = document.getElementById(element);
        if (arguments.length == 1)
            return element;
        elements.push(element);
    }
    return elements;
}

/*
* Recursively merge properties of two objects 
* http://stackoverflow.com/questions/171251/how-can-i-merge-properties-of-two-javascript-objects-dynamically/383245#383245
*
*/
function MergeRecursive(obj1, obj2) {
    for (var p in obj2) {
        try {
            // Property in destination object set; update its value.
            if ( obj2[p].constructor==Object ) {
                obj1[p] = MergeRecursive(obj1[p], obj2[p]);
            } else {
                obj1[p] = obj2[p];
            }
        } catch(e) {
            // Property in destination object not set; create it and set its
            // value.
            obj1[p] = obj2[p];
        }
    }
    return obj1;
}

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

function deleteConfirmation(oArg)
{
    var itemName = (oArg && oArg.itemName) ? oArg.itemName : "item";
    var msg = "Are you sure you want to delete this " + itemName  + "?";
    if (oArg && oArg.childName) {
        msg += " Deleting it will also remove any " + childName + "(s) it contains."; 
    }
    return confirm(msg);
}
function validate_fields(of,reqfields) {
    /* 04/18/2009 - changed from using a hidden field to store ids
    of required fields to passing an array of ids directly
    /* 06/20/2007 -	added "document.appendChild" check for Opera 6
    /* 06/14/2007 -	removed code related to IMG elements,
    added "password" input type
    Based on:
    http://www.onlinetools.org/articles/unobtrusivejavascript/chapter5.html

    Modified by Eugene Scherba 2007-2009 
    Requires Prototype JavaScript framework
    */

    // test if DOM is available
    if(!document.getElementById || !document.createTextNode || !document.appendChild){return;}

    // define error messages
    var errorID="errormsg";
    var errorClass="error"
    var errorMsg="There is a problem with your input. Please fill out or correct the highlighted field(s).";
    // other definitions
    var captchaLength = 5;

    // cleanup: if there is an old errormessage field, delete it
    var em=$(errorID);
    if(em){em.parentNode.removeChild(em);}

    // split the required fields and loop throught them
    for (var i=0; i<reqfields.length; i++) {
        // get a required field
        var f=$(reqfields[i]);
        if(!f){continue;}
        // cleanup: remove old classes from the required fields
        f.parentNode.className="";
        // completely strip whitespace and place field value into v
        var v=f.value.replace(/ /g,"");
        // test if the required field has an error, according to its type
        switch(f.type.toLowerCase()) {
            case "text":
                // email is a special field and needs checking
                // AN UGLY TECHNIQUE USED HERE: we only check email
                // field when it is NOT empty. This is ugly because
                // I did not implement a way to tell this function
                // that email is a required field in case we want
                // it to be required.
                switch(f.id.toLowerCase()) {
                    case "email":
                    case "email1":
                    case "email2":
                        if(v != "" && !cf_isEmailAddr(v)) {cf_adderr(f);}
                        break;
                    case "security_code":
                        if(v.length != captchaLength) {cf_adderr(f);}
                        break;
                    default:
                        if(v == "") {cf_adderr(f);}
                }
                break;
            case "textarea":
            case "password":
                if(v==""){cf_adderr(f);}
                break;
            /* case "checkbox":
                if(!f.checked){cf_adderr(f);}
                break;
            case "select-one":
                if(!f.selectedIndex && f.selectedIndex==0){cf_adderr(f);}
                break; */
        }
    }
    return !$(errorID);

    /* tool methods */
    function cf_adderr(o) {
        // colourise the error fields
        o.parentNode.className=errorClass;
        // check if there is no error message
        if(!$(errorID)) {
            // create errormessage and insert before submit button
            var em=document.createElement("div");
            em.id=errorID;
            var newp=document.createElement("p");
            newp.appendChild(document.createTextNode(errorMsg))
            em.appendChild(newp);
            // find the submit button
            for(var i=0;i<of.getElementsByTagName("input").length;i++) {
                if(/submit/i.test(of.getElementsByTagName("input")[i].type)) {
                    var sb=of.getElementsByTagName("input")[i];
                    break;
                }
            }
            if(sb) {
                sb.parentNode.insertBefore(em,sb);
            }
        }
    }
    function cf_isEmailAddr(str) {
        // RFC 2822 regex from
        // http://www.regular-expressions.info/email.html
        return str.match(/(?:[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*|"(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21\x23-\x5b\x5d-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])*")@(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?|\[(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?|[a-z0-9-]*[a-z0-9]:(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21-\x5a\x53-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])+)\])/);
        //return str.match(/^[\w-]+(\.[\w-]+)*@([\w-]+\.)+[a-zA-Z]{2,7}$/);
        // arpad3 email regex validator (passes all tests at http://www.pgregg.com/projects/php/code/showvalidemail.php):
        //alert( preg_match('/^(?:"(?:\\\\.|[^"])*"|[^@]+)@(?=[^()]*(?:\([^)]*\)[^()]*)*\z)(?![^ ]* (?=[^)]+(?:\(|\z)))(?:(?:[a-z\d() ]+(?:[a-z\d() -]*[()a-z\d])?\.)+[a-z\d]{2,6}|\[(?:(?:1?\d\d?|2[0-4]\d|25[0-4])\.){3}(?:1?\d\d?|2[0-4]\d|25[0-4])\]) *\z/si'));
        //return false;
    }
}
