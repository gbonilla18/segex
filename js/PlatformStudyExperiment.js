;(function (exports) {

"use strict";

/******************************************************************
* populatePlatform()
* This function is typically run only once, on page load
******************************************************************/
exports.populatePlatform = function()
{
    var platform = this.platform;
    var platforms = (platform.element === null) ? (platform.element = document.getElementById(platform.elementId)) : platform.element;

    // First remove all existing option elements -- need to do this even though
    // platform drop-down list is never repopulated after page loads. This is
    // because it seems that some browsers (Firefox, Safari) automatically add
    // an option to the dropdown that was present in the same control before
    // page load.
    var oldWidth = clearDropDown(platforms);

    // sort by platform name
    var tuples = [];
    for (var i in PlatfStudyExp) {
        if (PlatfStudyExp.hasOwnProperty(i)) {
            var platformNode = PlatfStudyExp[i];
            var species = platformNode.species;
            var content = (typeof species !== 'undefined' && species !== null) ? platformNode.name + ' \\ ' + species : platformNode.name;
            tuples.push([i, content]);
        }
    }
    sortNestedByColumn(tuples, 1);

    // build dropdown box
    buildDropDown(platforms, tuples, platform.selected, oldWidth);
}

/******************************************************************/
exports.populatePlatformStudy = function()
{
    var platform = this.platform;
    var platforms = (platform.element === null) ? (platform.element = document.getElementById(platform.elementId)) : platform.element;

    var study = this.study;
    var studies = (study.element === null) ? (study.element = document.getElementById(study.elementId)) : study.element;

    // first remove all existing option elements
    var oldWidth = clearDropDown(studies);

    // now add new ones
    var pid = getSelectedValue(platforms);
    var study_data = (typeof pid !== 'undefined' && typeof PlatfStudyExp[pid] !== 'undefined') ? PlatfStudyExp[pid].studies : {};

    // sort by study id
    var tuples = [];
    for (var i in study_data) {
        if (study_data.hasOwnProperty(i)) {
            var content = study_data[i].name;
            tuples.push([i, content]);
        }
    }
    sortNestedByColumn(tuples, 1);

    buildDropDown(studies, tuples, study.selected, oldWidth);
}
/******************************************************************/
exports.populateStudyExperiment = function()
{
    var platform = this.platform;
    var platforms = (platform.element === null) ? (platform.element = document.getElementById(platform.elementId)) : platform.element;
    var pid = getSelectedValue(platforms);

    var study = this.study;
    var studies = (study.element === null) ? (study.element = document.getElementById(study.elementId)) : study.element;
    var stid = getSelectedValue(studies);

    var experiment = this.experiment;
    var experiments = (experiment.element === null) ? (experiment.element = document.getElementById(experiment.elementId)) : experiment.element;

    // first remove all existing option elements
    var oldWidth = clearDropDown(experiments);

    // now add new ones
    if (typeof pid !== 'undefined' && typeof stid !== 'undefined') {
        var platformNode = PlatfStudyExp[pid];

        // When we need to use experiments from all studies in given platform, 
        // we simply point to 'experiments' property of parent platform.
        var experiment_ids = (stid === 'all') ? platformNode.experiments : platformNode.studies[stid].experiments;
        var experiment_data = platformNode.experiments;

        // sort by experiment id
        var tuples = [];
        for (var i in experiment_ids) {
            if (experiment_ids.hasOwnProperty(i)) {
                var experimentNode = experiment_data[i];
                var content = i + '. ';
                if (typeof(experimentNode) !== 'undefined') {
                    // no experiment info for given eid among platform data -- this
                    // typically would mean that the experiment in question has been
                    // assigned to the study but not the platform -- this is not
                    // supposed to happen but we consider the possibility anyway.
                    content += experimentNode.sample2 + ' / ' + experimentNode.sample1;
                }
                tuples.push([i, content]);
            }
        }
        sortNestedByColumnNumeric(tuples, 0);

        // build dropdown box
        buildDropDown(experiments, tuples, experiment.selected, oldWidth);
    }
}

}(this));
