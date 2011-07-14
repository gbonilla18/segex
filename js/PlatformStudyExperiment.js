/******************************************************************/
function getSelectedValue(obj)
{
    try {
        return obj.options[obj.selectedIndex].value;
    } catch(e) {
        if (e instanceof TypeError) {
            // cannot be set because no option was selected
        } else {
            // other error types: rethrow exception
            throw e;
        }
    }
}
/******************************************************************/
function populatePlatform()
{
    // This function is only run once, on page load
    var platforms = document.getElementById('pid');
    for (var i in PlatfStudyExp) {
        var this_platform = PlatfStudyExp[i];
        var new_opt = document.createElement('option');
        new_opt.setAttribute('value', i);
        new_opt.innerHTML = this_platform.name + ' \\ ' + this_platform.species;
        platforms.appendChild(new_opt); 
    }
    //current_platform = obj.options[obj.selectedIndex].value;
}
/******************************************************************/
function populatePlatformStudy()
{
    var platforms = document.getElementById('pid');
    var pid = getSelectedValue(platforms);
    var studies = document.getElementById('stid');

    // first remove all existing option elements
    while (studies.options[0]) {
        studies.removeChild(studies.options[0]);
    }

    // now add new ones
    if (typeof pid !== 'undefined') {
        var study_data = PlatfStudyExp[pid].studies;
        for (var i in study_data) {
            var this_study = study_data[i];
            var new_opt = document.createElement('option');
            new_opt.setAttribute('value', i);
            new_opt.innerHTML = this_study.name;
            studies.appendChild(new_opt);
        }
    }
}
/******************************************************************/
function populateStudyExperiment()
{
    var platforms = document.getElementById('pid');
    var pid = getSelectedValue(platforms);

    var studies = document.getElementById('stid');
    var stid = getSelectedValue(studies);

    var experiments = document.getElementById('eid');

    // first remove all existing option elements
    while(experiments.options[0]) {
        experiments.removeChild(experiments.options[0]);
    }

    // now add new ones
    if (typeof pid !== 'undefined' && typeof stid !== 'undefined') {
        var this_platform = PlatfStudyExp[pid];
        var experiment_ids = this_platform.studies[stid].experiments;
        var experiment_data = this_platform.experiments;
        for (var i in experiment_ids) {
            var this_experiment = experiment_data[i]
            var new_opt = document.createElement('option');
            new_opt.setAttribute('value', i);
            new_opt.innerHTML = this_experiment[0] + ' / ' + this_experiment[1];
            experiments.appendChild(new_opt);
        }
    }
}
