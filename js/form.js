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
function validate_fields(of,reqfields) {

    // test if DOM is available
    if(!document.getElementById || !document.createTextNode || !document.appendChild){return;}

    // define error messages
    var errorID="errormsg";
    var errorClass="error"
    var errorMsg="There is a problem with your input. Please fill out or correct the highlighted field(s).";

    // cleanup: if there is an old errormessage field, delete it
    var em = document.getElementById(errorID);
    if(em){em.parentNode.removeChild(em);}

    // split the required fields and loop throught them
    for (var i=0, reqfields_length = reqfields.length; i < reqfields_length; i++) {
        // get a required field
        var f=document.getElementById(reqfields[i]);
        // cleanup: remove old classes from the required fields
        f.parentNode.className="";
        // completely strip whitespace and place field value into value 
        // test if the required field has an error, according to its type
        switch(f.type.toLowerCase()) {
            case "text":
                var value =f.value.replace(/ /g,"");
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
    return (document.getElementById(errorID) === null);

    /* tool methods */
    function cf_adderr(o) {
        // colourise the error fields
        o.parentNode.className=errorClass;
        // check if there is no error message
        if(document.getElementById(errorID) === null) {
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
    }
}
