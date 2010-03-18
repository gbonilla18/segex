function populateExistingStudy(id) {
	obj = $(id);
	for (var i in study) {
		var new_opt = document.createElement("option");
		new_opt.setAttribute('value',i);
		new_opt.innerHTML = study[i][0];
		obj.appendChild(new_opt); 
	}
	current_platform = obj.options[obj.selectedIndex].value;
}
function populateSelectExistingExperiments(obj, stid_object) {

	var stid;

	stid = stid_object.options[stid_object.selectedIndex].value;

        // first remove all existing option elements
        while(obj.options[0]) {
                obj.removeChild(obj.options[0]);
        }
        // now add new ones
        for (var i in study[stid][1]) {
                var new_opt = document.createElement("option");
                new_opt.setAttribute('value', i);
                new_opt.innerHTML = study[stid][1][i] + ' / ' + study[stid][2][i];
                obj.appendChild(new_opt);
        }
}
