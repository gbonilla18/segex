function populateExisting(el, obj)
{
	for (var i in obj) {
		var new_opt = document.createElement("option");
		new_opt.setAttribute('value',i);
		new_opt.innerHTML = obj[i][0];
		el.appendChild(new_opt); 
	}
	if (el.length > 0)
	{
		current_platform = el.options[el.selectedIndex].value;
	}
}

function populateSelectExisting(el, id_el, obj) 
{
	if (id_el.length > 0)
	{
		var stid = id_el.options[id_el.selectedIndex].value;
		// first remove all existing option elements
		while (el.options[0]) {
		        el.removeChild(el.options[0]);
		}
		// now add new ones
		for (var i in obj[stid][1]) {
		        var new_opt = document.createElement('option');
		        new_opt.setAttribute('value', i);
			if (obj[stid][2] === undefined || obj[stid][2][i] === undefined) {
				// "study" for 
				// Projects -> Studies
				new_opt.innerHTML = obj[stid][1][i];
			} else {
				// "sample1 / sample2" for 
				// Projects -> Experiments
				new_opt.innerHTML = obj[stid][1][i] + ' / ' + obj[stid][2][i];
			}
		        el.appendChild(new_opt);
		}
	}
}
