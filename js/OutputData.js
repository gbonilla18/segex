/******************************************************************/
function populatePlatform()
{
    // This function is only run once, on page load
    var platform = document.getElementById('platform');
    for (var i in PlatfStudyExp) {
        var this_platform = PlatfStudyExp[i];
        var new_opt = document.createElement('option');
        new_opt.setAttribute('value', i);
        new_opt.innerHTML = this_platform.name + ' \\ ' + this_platform.species;
        platform.appendChild(new_opt); 
    }
    //current_platform = obj.options[obj.selectedIndex].value;
}
/******************************************************************/
function populatePlatformStudy()
{
    var platform = document.getElementById('platform');
    var pid;
    try {
        pid = platform.options[platform.selectedIndex].value;
    } catch(e) {
        if (e instanceof TypeError) {
            // cannot be set because no option was selected
        } else {
            // other error types: rethrow exception
            throw e;
        }
    }

    var study = document.getElementById('study');

    // first remove all existing option elements
    while (study.options[0]) {
        study.removeChild(study.options[0]);
    }

    // now add new ones
    if (typeof pid !== 'undefined') {
        var studies = PlatfStudyExp[pid].studies;
        for (var i in studies) {
            var this_study = studies[i];
            var new_opt = document.createElement('option');
            new_opt.setAttribute('value', i);
            new_opt.innerHTML = this_study.name;
            study.appendChild(new_opt);
        }
    }
}
/******************************************************************/
function populateStudyExperiment()
{
    var platform = document.getElementById('platform');
    var pid;
    try {
        pid = platform.options[platform.selectedIndex].value;
    } catch(e) {
        if (e instanceof TypeError) {
            // cannot be set because no option was selected
        } else {
            // other error types: rethrow exception
            throw e;
        }
    }

    var study = document.getElementById('study');
    var stid;
    try {
        stid = study.options[study.selectedIndex].value;
    } catch(e) {
         if (e instanceof TypeError) {
            // cannot be set because no option was selected
        } else {
            // other error types: rethrow exception
            throw e;
        }
    }

    var eids = document.getElementById('eids');

    // first remove all existing option elements
    while(eids.options[0]) {
        eids.removeChild(eids.options[0]);
    }

    // now add new ones
    if (typeof pid !== 'undefined' && typeof stid !== 'undefined') {
        var this_platform = PlatfStudyExp[pid];
        var experiment_ids = this_platform.studies[stid].experiments;
        var experiments = this_platform.experiments;
        for (var i in experiment_ids) {
            var this_experiment = experiments[i]
            var new_opt = document.createElement('option');
            new_opt.setAttribute('value', i);
            new_opt.innerHTML = this_experiment[0] + ' / ' + this_experiment[1];
            eids.appendChild(new_opt);
        }
    }
}
