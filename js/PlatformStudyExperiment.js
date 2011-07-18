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
function buildDropDown(obj, tuples, selected) {
    for (var i = 0, len = tuples.length; i < len; i++) {
        var key = tuples[i][0];
        var value = tuples[i][1];
        var option = document.createElement('option');
        option.setAttribute('value', key);
        if (typeof(selected) !== 'undefined' && (key in selected)) {
            option.selected = 'selected';
        }
        //console.log(key + ' ' + value);
        option.innerHTML = value;
        obj.appendChild(option);
    }
}
/******************************************************************/
function clearDropDown(obj) {
    while (obj.options[0]) {
        obj.removeChild(obj.options[0]);
    }
}
/******************************************************************
* populatePlatform()
* This function is typically run only once, on page load
******************************************************************/
function populatePlatform()
{
    var platform = this.platform;
    var platforms = (platform.element === null)
        ? (platform.element = document.getElementById(platform.elementId))
        : platform.element;

    // First remove all existing option elements -- need to do this even though
    // platform drop-down list is never repopulated after page loads. This is
    // because it seems that some browsers (Firefox, Safari) automatically add
    // an option to the dropdown that was present in the same control before
    // page load.
    clearDropDown(platforms);

    // sort by platform name
    var tuples = [];
    for (var i in PlatfStudyExp) {
        var platformNode = PlatfStudyExp[i];
        var content = (platformNode.species !== null)
        ? platformNode.name + ' \\ ' + platformNode.species
        : platformNode.name;
        tuples.push([i, content]);
    }
    // generic tuple sort (sort hash by value)
    tuples.sort(function(a, b) {
        a = a[1];
        b = b[1];
        return a < b ? -1 : (a > b ? 1 : 0);
    });

    // build dropdown box
    buildDropDown(platforms, tuples, platform.selected);
}

/******************************************************************/
function populatePlatformStudy()
{
    var platform = this.platform;
    var platforms = (platform.element === null)
        ? (platform.element = document.getElementById(platform.elementId))
        : platform.element;

    var study = this.study;
    var studies = (study.element === null)
        ? (study.element = document.getElementById(study.elementId))
        : study.element;

    // first remove all existing option elements
    clearDropDown(studies);

    // now add new ones
    var pid = getSelectedValue(platforms);
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
            //return a[0] - b[0];
            a = a[1];
            b = b[1];
            return a < b ? -1 : (a > b ? 1 : 0);
        });

        buildDropDown(studies, tuples, study.selected);
    }
}
/******************************************************************/
function populateStudyExperiment()
{
    var platform = this.platform;
    var platforms = (platform.element === null)
        ? (platform.element = document.getElementById(platform.elementId))
        : platform.element;
    var pid = getSelectedValue(platforms);

    var study = this.study;
    var studies = (study.element === null)
        ? (study.element = document.getElementById(study.elementId))
        : study.element;
    var stid = getSelectedValue(studies);

    var experiment = this.experiment;
    var experiments = (experiment.element === null)
        ? (experiment.element = document.getElementById(experiment.elementId))
        : experiment.element;

    // first remove all existing option elements
    clearDropDown(experiments);

    // now add new ones
    if (typeof pid !== 'undefined' && typeof stid !== 'undefined') {
        var platformNode = PlatfStudyExp[pid];
        var experiment_ids = platformNode.studies[stid].experiments;
        var experiment_data = platformNode.experiments;

        // sort by experiment id
        var tuples = [];
        for (var i in experiment_ids) {
            var experimentNode = experiment_data[i];
            var content;
            if (typeof(experimentNode) === 'undefined') {
                // no experiment info for given eid among platform data
                content = '@' + i;
            } else {
                content = experimentNode[0] + ' / ' + experimentNode[1];
            }
            tuples.push([i, content]);
        }
        // generic tuple sort (sort hash by numeric key)
        tuples.sort(function(a, b) {
            return a[0] - b[0];
        });

        // build dropdown box
        buildDropDown(experiments, tuples, experiment.selected);
    }
}
