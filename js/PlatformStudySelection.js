function populateSelectFilterStudy(obj, stid_object) {

	var stid;

	stid = stid_object.options[stid_object.selectedIndex].value;
	
        // first remove all existing option elements
        while(obj.options[0]) {
                obj.removeChild(obj.options[0]);
        }
		
		//Add 'ALL' Element.
		var new_opt = document.createElement("option");
		new_opt.setAttribute('value', '0');
		new_opt.innerHTML = 'ALL';
		obj.appendChild(new_opt);		
		
        // now add new ones
        for (var i in studies[stid]) {
                var new_opt = document.createElement("option");
                new_opt.setAttribute('value', i[1]);
                new_opt.innerHTML = i[0];
                obj.appendChild(new_opt);
        }
}
