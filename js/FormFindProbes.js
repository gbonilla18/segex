YAHOO.util.Event.addListener(window, "load", init);
YAHOO.util.Event.addListener(["opts", "graph"], "change", updateForm);
function updateForm() {
    //
    var opts = document.getElementById("opts");
    var graph_names = document.getElementById("graph_names");
    var graph_values = document.getElementById("graph_values");
    //
    var graph = document.getElementById("graph");
    var graph_option_names = document.getElementById("graph_option_names");
    var graph_option_values = document.getElementById("graph_option_values");
    //
    if (parseInt(opts.options[opts.selectedIndex].value) == 3) {
        graph_names.style.display = "none";
        graph_values.style.display = "none";
        graph_option_names.style.display = "none";
        graph_option_values.style.display = "none";
    } else {
        graph_names.style.display = "block";
        graph_values.style.display = "block";
        graph_option_names.style.display = "block";
        graph_option_values.style.display = "block";
        if (graph.checked) {
            graph_option_names.style.display = "block";
            graph_option_values.style.display = "block";
        } else {
            graph_option_names.style.display = "none";
            graph_option_values.style.display = "none";
        }
    }
}
function init() {
    updateForm();
}
