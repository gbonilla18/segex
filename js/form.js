<!--
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
		return str.match(/^[\w-]+(\.[\w-]+)*@([\w-]+\.)+[a-zA-Z]{2,7}$/);
		// arpad3 email regex validator (passes all tests at http://www.pgregg.com/projects/php/code/showvalidemail.php):
		//alert( preg_match('/^(?:"(?:\\\\.|[^"])*"|[^@]+)@(?=[^()]*(?:\([^)]*\)[^()]*)*\z)(?![^ ]* (?=[^)]+(?:\(|\z)))(?:(?:[a-z\d() ]+(?:[a-z\d() -]*[()a-z\d])?\.)+[a-z\d]{2,6}|\[(?:(?:1?\d\d?|2[0-4]\d|25[0-4])\.){3}(?:1?\d\d?|2[0-4]\d|25[0-4])\]) *\z/si'));
		//return false;
	}
}
function sgx_toggle(of,targets) {
        // test if DOM is available
        if(!document.getElementById || !document.createTextNode || !document.appendChild){return;}

	var style_display = (of) ? 'block' : 'none';

	 for (var i=0; i<targets.length; i++) {
	          var f=$(targets[i]);
	          if (f) {
	          	f.style.display = style_display;
		}
         }
}

function validate_Number(of,checkFields)
{
	


}