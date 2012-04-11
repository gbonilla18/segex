;(function() {

"use strict";

var dom = YAHOO.util.Dom;
var lang   = YAHOO.lang;

YAHOO.util.Event.addListener(window, "load", function () {

    // Drop progressively enhanced content class, just before creating the
    // module
    var user_selection = dom.get('user_selection');
    var specialFilterForm_el = dom.get("specialFilterForm");
    dom.removeClass(specialFilterForm_el, "yui-pe-content");

    // Instantiate the Dialog
    var specialFilterForm = new YAHOO.widget.Dialog(
        specialFilterForm_el, 
        {
            fixedcenter: true,
            visible : false, 
            constraintoviewport : false,
            draggable: true,
            modal: true,
        }
    );

    // Overrides YAHOO.widget.Overlay center() method:
    //http://developer.yahoo.com/yui/docs/YAHOO.widget.Overlay.html#method_center
    specialFilterForm.center = function() {
        var nViewportOffset = YAHOO.widget.Overlay.VIEWPORT_OFFSET,
        elementWidth = this.element.offsetWidth,
        elementHeight = this.element.offsetHeight,
        viewPortWidth = dom.getViewportWidth(),
        viewPortHeight = dom.getViewportHeight();

        var x = dom.getDocumentScrollLeft() + (
            (viewPortWidth > elementWidth) ?
            ((viewPortWidth - elementWidth) / 2) :
            nViewportOffset
        );

        // position such that distance between panel top and top viewport
        // edge is a fifth of the distance between panel bottom and bottom 
        // viewport edge.
        var y = dom.getDocumentScrollTop() + (
            (viewPortHeight > elementHeight) ?
            ((viewPortHeight - elementHeight) / 5) :
            nViewportOffset
        );

        this.cfg.setProperty("xy", [parseInt(x, 10), parseInt(y, 10)]);
        this.cfg.refireEvent("iframe");

        if (YAHOO.env.ua.webkit) {
            this.forceContainerRedraw();
        }
    };
    dom.addClass(specialFilterForm.element, 'filter-dialog');
    specialFilterForm.render();

    YAHOO.util.Event.addListener("specialFilter", "change", 
        function(e) { 
            if (this.checked) {
                specialFilterForm.show();
            } else {
                specialFilterForm.hide();
            }
        }
    );

    var myDataSource = new YAHOO.util.DataSource();
    myDataSource.responseType = YAHOO.util.DataSource.TYPE_JSARRAY;
    myDataSource.responseSchema = { fields: [
        {key:"eid", parser:"number"},
        {key:"study_desc"},
        {key:"sample1"},
        {key:"sample2"},
        {key:"reverse"},
        {key:"pValFlag", parser:"number"},
        {key:"pValClass", parser:"number"},
        {key:"pval", parser:"number"},
        {key:"fchange", parser: "number"},
        {key:"drop"}
    ] };

    var checkboxFormatter = function(elCell, oRecord, oColumn, oData) {
        removeAllChildren(elCell);
        var checkbox = document.createElement('input');
        checkbox.setAttribute('type', 'checkbox');
        if (oData) {
            checkbox.setAttribute('checked', oData);
        }
        YAHOO.util.Event.addListener(checkbox, 'click', function(ev) {
            oRecord.setData(oColumn.key, ev.target.checked);
            this.updateRow(oRecord, oRecord.getData());
        }, this, true);
        elCell.appendChild(checkbox);
    };
    var createTextboxFormatter = function(isValid, cssClass) {
        function textboxOnChange(ev) {
            var oRecord = this[1];
            var oColumn = this[2];
            var col = oColumn.key;
            var newVal = ev.target.value;
            if (isValid(newVal)) {
                // update model
                oRecord.setData(col, newVal);
            } else {
                // restore old value from model
                ev.target.value = oRecord.getData(col);
            }
        }
        return function(elCell, oRecord, oColumn, oData) {
            removeAllChildren(elCell);
            var textbox = document.createElement('input');
            textbox.setAttribute('type', 'text');
            if (cssClass) {
                textbox.setAttribute('class', cssClass);
            }
            textbox.setAttribute('value', oData);
            YAHOO.util.Event.addListener(textbox, 'change', textboxOnChange, arguments, true);
            elCell.appendChild(textbox);
        };
    };
    var removeFormatter = function(elCell, oRecord, oColumn, oData) {
        removeAllChildren(elCell);
        var btn = document.createElement('button');
        btn.setAttribute('class', 'plaintext');
        btn.setAttribute('title', 'Drop experiment from comparison');
        btn.appendChild(document.createTextNode('drop'));

        // in formatter context, `this' referes to DataTable instance
        YAHOO.util.Event.addListener(btn, 'click', function(ev) {
            this.deleteRow(oRecord);
        }, this, true);
        elCell.appendChild(btn);
    };
    var experimentFormatter = function(elCell, oRecord, oColumn, oData) {
        removeAllChildren(elCell);
        var eid = oRecord.getData('eid');
        var study_desc = oRecord.getData('study_desc');
        var sample1 = oRecord.getData('sample1');
        var sample2 = oRecord.getData('sample2');
        var reverseCell = oRecord.getData('reverse');
        var newVal = eid + '. ' + study_desc + ': ' + (reverseCell ? (sample1 + ' / ' + sample2) : (sample2 + ' / ' + sample1));
        elCell.appendChild(document.createTextNode(newVal));
    };
    var pValClassFormatter = function(elCell, oRecord, oColumn, oData) {
        removeAllChildren(elCell);
        var select = document.createElement('select');
        select.setAttribute('title', 'Select P-value to use');
        var flag = oRecord.getData('pValFlag');
        var chosenPVal = parseInt(oData);
        for (var i = 0; i < 4; i++) {
            // test for bit presence
            if (flag & (1 << i)) {
                var opt = document.createElement('option');
                var pvalIndex = i + 1;
                opt.setAttribute('value', pvalIndex);
                if (pvalIndex === chosenPVal) {
                    opt.setAttribute('selected', 'selected');
                }
                opt.appendChild(document.createTextNode(pvalIndex));
                select.appendChild(opt);
            }
        }
        YAHOO.util.Event.addListener(select, 'change', function(ev) {
            var el = ev.target;
            var val = getSelectedValue(el);
            oRecord.setData(oColumn.key, val);
        });
        oRecord.setData(oColumn.key, getSelectedValue(select));
        elCell.appendChild(select);
    };
    var pvalFormatter = createTextboxFormatter(function(val) {
        var float = parseFloat(val);
        if (float !== parseFloat(val) || float <= 0.0 || float > 1.0) {
            alert("P-value cutoff must be a number > 0 and <= 1");
            return false;
        }
        return true;
    }, 'shortnum');
    var fchangeFormatter = createTextboxFormatter(function(val) {
        var float = parseFloat(val);
        if (float !== parseFloat(val) || float < 1.0) {
            alert("Fold change cutoff must be a number >= 1");
            return false;
        }
        return true;
    }, 'shortnum');

    var myColumnDefs = [
        {key:"eid", sortable:true, resizeable:true, label:'Experiment', formatter:experimentFormatter},
        {key:"reverse", sortable:true, resizeable:false, label:'Reverse Samples', formatter:checkboxFormatter},
        {key:"pValClass", sortable:true, resizeable:false, label:'P-value', formatter:pValClassFormatter},
        {key:"pval", sortable:true, resizeable:false, label:'P <', formatter:pvalFormatter},
        {key:"fchange", sortable:true, resizeable:false, label:'|Fold| >', formatter:fchangeFormatter},
        {key:"drop", sortable:false, resizeable:false, label:'', formatter:removeFormatter}
    ];
    var myDataTable = new YAHOO.widget.DataTable(
        "exp_table", myColumnDefs, myDataSource, {}
    );

    var selPlatforms = dom.get('pid');
    var selStudies = dom.get('stid');
    var selExperiments = dom.get('eid');

    function pickExperiment() {
        function incrementParentIfEmpty(parent, child) {
            // increment study if experiment is empty
            while (child.selectedIndex < 0 && parent.selectedIndex >= 0) {
                incrementDropdown(parent);
                triggerEvent(parent, 'change');
            }
        }
        incrementParentIfEmpty(selStudies, selExperiments);
        if (selExperiments.selectedIndex < 0) {
            return;
        }
        var result = getSelectedValue(selExperiments);
        selExperiments.selectedIndex++;
        incrementParentIfEmpty(selStudies, selExperiments);
        triggerEvent(selExperiments, 'change');
        return result;
    }

    // revive stored model
    var records = [];
    if (user_selection.value) {
        records = JSON.parse(user_selection.value);
    }
    forEach(records, function(record) {
        myDataTable.addRow(YAHOO.widget.DataTable._cloneObject(record));
    });

    YAHOO.util.Event.addListener('add', 'click', function() {
        var pid = getSelectedValue(selPlatforms);
        var stid = getSelectedValue(selStudies);
        var eid = pickExperiment();
        if (typeof pid === 'undefined' || typeof eid === 'undefined') {
            return false;
        }
        var platfRoot = PlatfStudyExp[pid];
        var expRoot = platfRoot.experiments[eid];
        var studyRoot = platfRoot.studies[stid];
        var record = YAHOO.widget.DataTable._cloneObject({
            sample1  : expRoot.sample1,
            sample2  : expRoot.sample2,
            pValFlag : expRoot.PValFlag,
            study_desc: studyRoot.description,

            stid     : stid,
            eid      : eid,
            pval     : platfRoot.def_p_cutoff,
            fchange  : platfRoot.def_f_cutoff,
            reverse  : false
        });
        myDataTable.addRow(record);
    });

    YAHOO.util.Event.addListener('form_compareExperiments', 'submit', function(ev) {
        var data = forEach(
            myDataTable.getRecordSet().getRecords(), 
            function(record) {
                this.push(record.getData());
            }, []
        );
        user_selection.value = JSON.stringify(data);
    });
});
})();
