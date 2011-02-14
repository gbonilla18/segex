<!--
// ========================================================================================================
// Experiment Comparison Page
// ========================================================================================================
function getSelectStudies(stid) {
        var option_string = '';
	var study_is_first = 1;
        for (var i in study) {
		if (study[i][3] == current_platform) {
			if (typeof first_study == 'undefined' && study_is_first) {
				first_study = i;
				study_is_first = 0;
			}
			var sel = (typeof stid != 'undefined' && stid == i) ? 'selected="selected"' : '' ;
			option_string += '<option ' + sel + ' value="' + i + '">' + study[i][0] + '</option>';
		}
        }
        return option_string;
}
function getSelectExperiments(stid, eid) {
        var option_string = '';   
        for (var i in study[stid][1]) {
		var sel = (typeof eid != 'undefined' && eid == stid + '|' + i) ? 'selected="selected"' : '' ;
                option_string += '<option ' + sel + ' value="' + stid + '|' + i + '">' + study[stid][1][i] + ' / ' + study[stid][2][i] + '</option>';
        }
        return option_string;
}
function populateSelectExperiments(obj, stid) {
        // first remove all existing option elements
        while(obj.options[0]) {
                obj.removeChild(obj.options[0]);
        }
        // now add new ones
        for (var i in study[stid][1]) {
                var new_opt = document.createElement("option");
                new_opt.setAttribute('value', i);
                //new_opt.text = study[stid][1][i] + ' / ' + study[stid][2][i]; // does not work in IE
                new_opt.innerHTML = study[stid][1][i] + ' / ' + study[stid][2][i];
                obj.appendChild(new_opt);
        }
}
function setDefaultCutoffs(exp_index, stid) {
        $("pval_" + exp_index).setAttribute("value", platform[study[stid][3]][1]);
        $("fc_" + exp_index).setAttribute("value", platform[study[stid][3]][2]);
}
function updateExperiments(obj){
// there is a different set of experiments for each study
// this functions updates the selection box below the current
        var exp_index = obj.getAttribute("id").replace(/^stid_/,'');
        var stid = obj.options[obj.selectedIndex].value;
	setDefaultCutoffs(exp_index, stid);
        populateSelectExperiments($("eid_" + exp_index), stid);
}
function removeExperiment(obj) {
        experiment_count--;
        var eid = obj.getAttribute("id").replace(/^remove_/,'');
        var fs = $("exp_" + eid);
        var fs2 = fs.nextSibling;
        fs.parentNode.removeChild(fs);
        while (fs2) {
                var eid2 = fs2.getAttribute("id").replace(/^exp_/,'');
                fs2.firstChild.innerHTML = "Experiment " + eid;        // legend
                $("remove_" + eid2).setAttribute("id", "remove_" + eid);
                $("stid_" + eid2).setAttribute("id", "stid_" + eid);
                $("reverse_" + eid2).setAttribute("name", "reverse_" + eid);
                $("reverse_" + eid2).setAttribute("id", "reverse_" + eid);
                $("eid_" + eid2).setAttribute("name", "eid_" + eid);
                $("eid_" + eid2).setAttribute("id", "eid_" + eid);
                $("pval_" + eid2).setAttribute("name", "pval_" + eid);
                $("pval_" + eid2).setAttribute("id", "pval_" + eid);
                $("fc_" + eid2).setAttribute("name", "fc_" + eid);
                $("fc_" + eid2).setAttribute("id", "fc_" + eid);
                fs2.setAttribute("id", "exp_" + eid);
                fs2 = fs2.nextSibling;
                eid++;
        }
}
function setSampleOrder(obj) {

        var exp_index = obj.getAttribute("id").replace(/^reverse_/,'');

        // get the currently selected study id
        opt = $("stid_" + exp_index).options;
        var stid;
        for (var i = 0, len = opt.length; i < len; ++i) {
                 if (opt[i].selected) { stid = opt[i].value; break; } 
        }

        // set sample order
        var num = (obj.checked) ? 2 : 1;
        var denom = (obj.checked) ? 1 : 2;

        // loop through all the experiment options and set sample order
        var opt = $("eid_" + exp_index).options;
        for (var i = 0, len = opt.length; i < len; ++i) {
                var eid = opt[i].value;
                opt[i].text = study[stid][num][eid] + ' / ' + study[stid][denom][eid];
        }
}
function addExperiment() {
	var eid;
	var stid;
	if (experiment_count) {
		var sel_stid = $("stid_" + experiment_count);
		var opts_stid = sel_stid.options;
		var selIndex_stid = sel_stid.selectedIndex;
		var sel_eid = $("eid_" + experiment_count);
		var opt_eid = sel_eid.options[sel_eid.selectedIndex + 1];
		if (typeof opt_eid == 'undefined') {
                        var opt_stid = opts_stid[selIndex_stid + 1];
                        if (typeof opt_stid == 'undefined') {
                                stid = opts_stid[0].value;
                        } else {
				stid = opt_stid.value;
			}
                } else {
			stid = opts_stid[selIndex_stid].value;
			eid = opt_eid.value;
		}
	}

	var opt_studies = getSelectStudies(stid);
	if (!experiment_count) { stid = first_study; }
	var opt_experiments = getSelectExperiments(stid, eid);
	//
        experiment_count++;
        var fieldset = document.createElement("fieldset");
        var fieldset_id = "exp_" + experiment_count;
        fieldset.setAttribute("id", fieldset_id);
        fieldset.innerHTML = '<legend>Experiment ' + experiment_count + '</legend><dl><dt>Study / Experiment:</dt><dd><select id="stid_' + experiment_count + '" onChange="updateExperiments(this);"> ' + opt_studies + '</select> <span class="separator">/</span> <select id="eid_' + experiment_count + '" name="eid_' + experiment_count + '" > ' + opt_experiments + ' </select></dd><dt><label for="reverse_' + experiment_count + '">Reverse sample order:</label></dt><dd><input id="reverse_' + experiment_count + '" type="checkbox" onclick="setSampleOrder(this);" name="reverse_' + experiment_count + '"/></dd><dt>Significance cutoff:</dt><dd><label>&#124;Fold Change&#124; &gt; <input type="text" id="fc_' + experiment_count + '" name="fc_' + experiment_count + '" value="" size="10" maxlength="10" /></label> <em>and</em> <label>P &lt; <input type="text" id="pval_' + experiment_count + '" name="pval_' + experiment_count + '" value="" size="10" maxlength="10" /></label></dd><dt>&nbsp;</dt><dd><input type="button" id="remove_' + experiment_count + '" value="Remove" onclick="removeExperiment(this);" /></dd></dl>';

        $(form).appendChild(fieldset);

	// updates default fold change and P cutoff values
	setDefaultCutoffs(experiment_count, stid);
}

function populatePlatforms(id) {
	obj = $(id);
	for (var i in platform) {
		var new_opt = document.createElement("option");
		new_opt.setAttribute('value',i);
		new_opt.innerHTML = platform[i][0];
		obj.appendChild(new_opt); 
	}
	current_platform = obj.options[obj.selectedIndex].value;
}
function updatePlatform(obj) {
	var form_obj = $(form);
	for (var i = 1; i <= experiment_count; i++) {
		form_obj.removeChild($("exp_" + i));
	}
	experiment_count = 0;
	current_platform = obj.options[obj.selectedIndex].value;
	addExperiment();
	updateExperiments($("stid_1"));	// DOM needs to be updated (addExperiment doesn't really do it)
}
var current_platform;
var first_study;
var experiment_count = 0; // how many experiments are displayed

function toggleSearchOptions(){
	if(document.getElementById("divSearchItemsDiv").style.display == '')
	{
		document.getElementById("divSearchItemsDiv").style.display = 'none';
	}
	else
	{
		document.getElementById("divSearchItemsDiv").style.display = '';
	}
}

function navigateToCSV()
{
	
	
}
