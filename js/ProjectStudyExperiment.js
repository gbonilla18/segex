"use strict";
function sortNestedByColumn (tuples, column) {
    tuples.sort(function (a, b) {
        a = a[column];
        b = b[column];
        return a < b ? -1 : (a > b ? 1 : 0);
    }); 
}
function sortNestedByColumnNumeric (tuples, column) {
    tuples.sort(function (a, b) {
        return a[column] - b[column];
    }); 
}
/******************************************************************/
function getSelectedValue(obj)
{
    try {
        return obj.options[obj.selectedIndex].value;
    } catch(e) {
        if (e instanceof TypeError || e instanceof DOMException) {
            // cannot be set because no option was selected
        } else {
            // other error types: rethrow exception
            throw e;
        }
    }
}
/******************************************************************/
function setMinWidth(el, width, old) {
    // sets minimum width for an element with content

    // first see if scrollWidth is greater than zero. If yes, reuse offsetWidth
    // instead of setting minimum. Only when scrollWidth is zero do we set
    // style.width.
    el.style.width = (old.scrollWidth > 0) 
    ? old.offsetWidth + 'px' 
    : width;
}
/******************************************************************/
function buildDropDown(obj, tuples, selected, old) {
    var len = tuples.length;
    if (len > 0) {
        // reset width for automatic width control
        obj.style.width = '';
    } else {
        // set width to either old (if present) or minimum
        setMinWidth(obj, '200px', old);
    }
    for (var i = 0; i < len; i++) {
        var key = tuples[i][0];
        var value = tuples[i][1];
        var option = document.createElement('option');
        option.setAttribute('value', key);
        if (typeof(selected) !== 'undefined' && (key in selected)) {
            option.selected = 'selected';
        }
        option.innerHTML = value;
        obj.appendChild(option);
    }
}
/******************************************************************/
function clearDropDown(obj) {
    // capture old width
    var oldWidth = { 
        clientWidth: obj.clientWidth, 
        offsetWidth: obj.offsetWidth, 
        scrollWidth: obj.scrollWidth 
    };
    // remove option elements
    while (obj.options[0]) {
        obj.removeChild(obj.options[0]);
    }
    return oldWidth;
}
/******************************************************************
* populateProject()
* This function is typically run only once, on page load
******************************************************************/
function populateProject()
{
    var project = this.project;
    var projects = (project.element === null)
    ? (project.element = document.getElementById(project.elementId))
    : project.element;

    // First remove all existing option elements -- need to do this even though
    // project drop-down list is never repopulated after page loads. This is
    // because it seems that some browsers (Firefox, Safari) automatically add
    // an option to the dropdown that was present in the same control before
    // page load.
    var oldWidth = clearDropDown(projects);

    // sort by project name
    var tuples = [];
    for (var i in ProjStudyExp) {
        var projectNode = ProjStudyExp[i];
        var content = projectNode.name;
        tuples.push([i, content]);
    }
    sortNestedByColumn(tuples, 1);

    // build dropdown box
    buildDropDown(projects, tuples, project.selected, oldWidth);
}

/******************************************************************/
function populateProjectStudy()
{
    var project = this.project;
    var projects = (project.element === null)
    ? (project.element = document.getElementById(project.elementId))
    : project.element;

    var study = this.study;
    var studies = (study.element === null)
    ? (study.element = document.getElementById(study.elementId))
    : study.element;

    // first remove all existing option elements
    var oldWidth = clearDropDown(studies);

    // now add new ones
    var pid = getSelectedValue(projects);
    if (typeof pid !== 'undefined') {
        var study_data = ProjStudyExp[pid].studies;

        // sort by study id
        var tuples = [];
        for (var i in study_data) {
            var content = study_data[i].name;
            tuples.push([i, content]);
        }
        sortNestedByColumn(tuples, 1);

        buildDropDown(studies, tuples, study.selected, oldWidth);
    }
}
/******************************************************************/
function populateStudyExperiment()
{
    var project = this.project;
    var projects = (project.element === null)
    ? (project.element = document.getElementById(project.elementId))
    : project.element;
    var pid = getSelectedValue(projects);

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
    var oldWidth = clearDropDown(experiments);

    // now add new ones
    if (typeof pid !== 'undefined' && typeof stid !== 'undefined') {
        var projectNode = ProjStudyExp[pid];

        // When we need to use experiments from all studies in given project, 
        // we simply point to 'experiments' property of parent project.
        var experiment_ids = (stid === 'all') 
        ? projectNode.experiments 
        : projectNode.studies[stid].experiments;
        var experiment_data = projectNode.experiments;

        // sort by experiment id
        var tuples = [];
        for (var i in experiment_ids) {
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
        sortNestedByColumnNumeric(tuples, 0);

        // build dropdown box
        buildDropDown(experiments, tuples, experiment.selected, oldWidth);
    }
}
