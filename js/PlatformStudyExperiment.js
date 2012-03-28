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
    var tuples = object_forEach(PlatfStudyExp, function(i, platformNode) {
        var species = platformNode.sname;
        var content = (typeof species !== 'undefined' && species !== null) ? platformNode.pname + ' \\ ' + species : platformNode.pname;
        this.push([i, content]);
    }, []).sort(ComparisonSortOnColumn(1));

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
    var tuples = object_forEach(study_data, function(key, val) {
        this.push([key, val.description]);
    }, []).sort(ComparisonSortOnColumn(1));

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
        var tuples = object_forKeys(experiment_ids, function(i) {
            var experimentNode = experiment_data[i];
            var content = i + '. ';
            if (typeof(experimentNode) !== 'undefined') {
                content += experimentNode.sample2 + ' / ' + experimentNode.sample1;
            }
            this.push([i, content]);
        }, []).sort(NumericSortOnColumn(0));

        // build dropdown box
        buildDropDown(experiments, tuples, experiment.selected, oldWidth);
    }
}

}(this));
