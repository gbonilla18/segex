;(function (exports) {

"use strict";

/******************************************************************
* populateProject()
* This function is typically run only once, on page load
******************************************************************/
exports.populateProject = function()
{
    var project = this.project;
    var projects = (project.element === null) ? (project.element = document.getElementById(project.elementId)) : project.element;

    // First remove all existing option elements -- need to do this even though
    // project drop-down list is never repopulated after page loads. This is
    // because it seems that some browsers (Firefox, Safari) automatically add
    // an option to the dropdown that was present in the same control before
    // page load.
    var oldWidth = clearDropDown(projects);

    // sort by project name
    var tuples = [];
    for (var i in ProjStudyExp) {
        if (ProjStudyExp.hasOwnProperty(i)) {
            var projectNode = ProjStudyExp[i];
            var content = projectNode.name;
            tuples.push([i, content]);
        }
    }
    sortNestedByColumn(tuples, 1);

    // build dropdown box
    buildDropDown(projects, tuples, project.selected, oldWidth);
}

/******************************************************************/
exports.populateProjectStudy = function()
{
    var project = this.project;
    var projects = (project.element === null) ? (project.element = document.getElementById(project.elementId)) : project.element;

    var study = this.study;
    var studies = (study.element === null) ? (study.element = document.getElementById(study.elementId)) : study.element;

    // first remove all existing option elements
    var oldWidth = clearDropDown(studies);

    // now add new ones
    var pid = getSelectedValue(projects);
    if (typeof pid !== 'undefined') {
        var study_data = ProjStudyExp[pid].studies;

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
}
/******************************************************************/
exports.populateStudyExperiment = function()
{
    var project = this.project;
    var projects = (project.element === null) ? (project.element = document.getElementById(project.elementId)) : project.element;
    var pid = getSelectedValue(projects);

    var study = this.study;
    var studies = (study.element === null) ? (study.element = document.getElementById(study.elementId)) : study.element;
    var stid = getSelectedValue(studies);

    var experiment = this.experiment;
    var experiments = (experiment.element === null) ? (experiment.element = document.getElementById(experiment.elementId)) : experiment.element;

    // first remove all existing option elements
    var oldWidth = clearDropDown(experiments);

    // now add new ones
    if (typeof pid !== 'undefined' && typeof stid !== 'undefined') {
        var projectNode = ProjStudyExp[pid];

        // When we need to use experiments from all studies in given project, 
        // we simply point to 'experiments' property of parent project.
        var experiment_ids = (stid === 'all') ? projectNode.experiments : projectNode.studies[stid].experiments;
        var experiment_data = projectNode.experiments;

        // sort by experiment id
        var tuples = [];
        for (var i in experiment_ids) {
            if (experiment_ids.hasOwnProperty(i)) {
                var experimentNode = experiment_data[i];
                var content = i + '. ';
                if (typeof(experimentNode) !== 'undefined') {
                    // no experiment info for given eid among project data -- this
                    // typically would mean that the experiment in question has been
                    // assigned to the study but not the project -- this is not
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
