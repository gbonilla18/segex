function populateSelectFilterStudy(obj, pid_object) {

	var pid;

	pid = pid_object.options[pid_object.selectedIndex].value;
	
        // first remove all existing option elements
        while(obj.options[0]) {
                obj.removeChild(obj.options[0]);
        }
	
	//Add 'Unassigned Studies'
	new_opt = document.createElement("option");
	new_opt.setAttribute('value', '-1');
	new_opt.innerHTML = 'Unassigned Studies';
	obj.appendChild(new_opt);			
		
	//Add 'ALL' Element.
	var new_opt = document.createElement("option");
	new_opt.setAttribute('value', '0');
	new_opt.innerHTML = 'All Studies';
	obj.appendChild(new_opt);
		
        // now add new ones
        for (var i in studies) {
		//Only add the ones that are in the platform we selected.
		if(studies[i][1] == pid || pid=='0')
		{
                	var new_opt = document.createElement("option");
	                new_opt.setAttribute('value', i);
	                new_opt.innerHTML = studies[i][0];
	                obj.appendChild(new_opt);
		}
        }
}

function selectStudy(obj,stid)
{
	for(var i in obj.options)
	{
		if(obj.options[i].value == stid)
		{
			obj.options[i].selected = true;
		}
	}
}