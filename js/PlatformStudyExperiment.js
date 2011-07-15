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
function buildDropDown(obj, tuples) {
    for (var i = 0, len = tuples.length; i < len; i++) {
        var key = tuples[i][0];
        var value = tuples[i][1];
        var new_opt = document.createElement('option');
        new_opt.setAttribute('value', key);
        new_opt.innerHTML = value;
        obj.appendChild(new_opt);
    }
}
/******************************************************************/
function clearDropDown(obj) {
    while (obj.options[0]) {
        obj.removeChild(obj.options[0]);
    }
}
/******************************************************************/
function populatePlatform()
{
    // This function is only run once, on page load
    var platforms = document.getElementById('pid');

    // sort by platform name
    var tuples = [];
    for (var i in PlatfStudyExp) {
        var this_platform = PlatfStudyExp[i];
        var content = (this_platform.species !== null)
                    ? this_platform.name + ' \\ ' + this_platform.species
                    : this_platform.name;
        tuples.push([i, content]);
    }
    // generic tuple sort (sort hash by value)
    tuples.sort(function(a, b) {
        a = a[1];
        b = b[1];
        return a < b ? -1 : (a > b ? 1 : 0); 
    });

    // build dropdown box
    buildDropDown(platforms, tuples);

    //current_platform = obj.options[obj.selectedIndex].value;
}

/******************************************************************/
function populatePlatformStudy()
{
    var platforms = document.getElementById('pid');
    var pid = getSelectedValue(platforms);
    var studies = document.getElementById('stid');

    // first remove all existing option elements
    clearDropDown(studies);

    // now add new ones
    if (typeof pid !== 'undefined') {
        var study_data = PlatfStudyExp[pid].studies;

        // sort by study id
        var tuples = [];
        for (var i in study_data) {
            var content = study_data[i].name;
            tuples.push([i, content]);
        }
        // generic tuple sort (sort hash by numeric key)
        tuples.sort(function(a, b) {
            return a[0] - b[0];
        });
        
        buildDropDown(studies, tuples);
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
    clearDropDown(experiments);

    // now add new ones
    if (typeof pid !== 'undefined' && typeof stid !== 'undefined') {
        var this_platform = PlatfStudyExp[pid];
        var experiment_ids = this_platform.studies[stid].experiments;
        var experiment_data = this_platform.experiments;

        // sort by experiment id
        var tuples = [];
        for (var i in experiment_ids) {
            var this_experiment = experiment_data[i]
            var content = this_experiment[0] + ' / ' + this_experiment[1];
            tuples.push([i, content]);
        }
        // generic tuple sort (sort hash by numeric key)
        tuples.sort(function(a, b) {
            return a[0] - b[0];
        });

        // build dropdown box
        buildDropDown(experiments, tuples);
    }
}
