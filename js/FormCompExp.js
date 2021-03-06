;(function() {

"use strict";

var dom = YAHOO.util.Dom;

YAHOO.util.Event.addListener(window, "load", function () {

    // Drop progressively enhanced content class, just before creating the
    // module
    var user_pse = dom.get('user_pse');
    var user_selection = dom.get('user_selection');
    var specialFilterForm_el = dom.get("specialFilterForm");
    dom.removeClass(specialFilterForm_el, "yui-pe-content");

    // Instantiate the Dialog
    var checkboxSpecialFilter = dom.get('specialFilter');
    var specialFilterForm = new YAHOO.widget.Dialog(
        specialFilterForm_el, 
        {
            fixedcenter: true,
            visible : false, 
            constraintoviewport : false,
            draggable: true,
            modal: true,
            buttons : [ 
                { text:"Apply", handler:function() { this.hide(); }, isDefault:true },
                { text:"Cancel", handler:function() { checkboxSpecialFilter.checked = false; this.cancel(); } } 
            ]
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

    YAHOO.util.Event.addListener(checkboxSpecialFilter, "change", 
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
<<<<<<< HEAD
        {key:"FCFlag", parser:"number"},
        {key:"FCClass", parser: "number"},
	    {key:"fchange", parser: "number"},

=======
        {key:"fchange", parser: "number"},
>>>>>>> fff9d8d7950b20b683423368896ff5be2cc170a4
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
    var experimentS2S1Formatter = function(elCell, oRecord, oColumn, oData) {
        removeAllChildren(elCell);
        var sample1 = oRecord.getData('sample1');
        var sample2 = oRecord.getData('sample2');
        var reverseCell = oRecord.getData('reverse');
        var newVal = reverseCell ? (sample1 + ' / ' + sample2) : (sample2 + ' / ' + sample1);
        var eid = oRecord.getData('eid');
        var a = document.createElement('a');
        a.setAttribute('href', './?a=experiments&id=' + encodeURIComponent(eid));
        a.appendChild(document.createTextNode(newVal));
        elCell.appendChild(a);
    };
    var studyFormatter = function(elCell, oRecord, oColumn, oData) {
        removeAllChildren(elCell);
        var stid = oRecord.getData('stid');
        var a = document.createElement('a');
        a.setAttribute('href', './?a=studies&id=' + encodeURIComponent(stid));
        a.appendChild(document.createTextNode(oData));
        elCell.appendChild(a);
    };
<<<<<<< HEAD
    var FCClassFormatter = function(elCell, oRecord, oColumn, oData) {
        removeAllChildren(elCell);
        var select = document.createElement('select');
        select.setAttribute('title', 'Select FC to use');
        var flag = oRecord.getData('FCFlag');
        var chosenFC = parseInt(oData);
        for (var i = 0; i < 4; i++) {
            // test for bit presence
            if (flag & (1 << i)) {
                var opt = document.createElement('option');
                var FCIndex = i + 1;
                opt.setAttribute('value', FCIndex);
                if (FCIndex === chosenFC) {
                    opt.setAttribute('selected', 'selected');
                }
                opt.appendChild(document.createTextNode(FCIndex));
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
=======
>>>>>>> fff9d8d7950b20b683423368896ff5be2cc170a4
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
        {key:"eid", sortable:true, resizeable:true, label:'Exp. no.'},
<<<<<<< HEAD
        {key:"fCClass", sortable:true, resizeable:false, label:'Fold-change', formatter:FCClassFormatter},
=======
>>>>>>> fff9d8d7950b20b683423368896ff5be2cc170a4
        {key:"fchange", sortable:true, resizeable:false, label:'|Fold| >', formatter:fchangeFormatter},
        {key:"pValClass", sortable:true, resizeable:false, label:'P-value', formatter:pValClassFormatter},
        {key:"pval", sortable:true, resizeable:false, label:'P <', formatter:pvalFormatter},
        {key:"study_desc", sortable:true, resizeable:true, label:'Study', formatter:studyFormatter},
        {key:"samples", resizeable:true, label:'Experiment samples', formatter:experimentS2S1Formatter},
        {key:"reverse", sortable:true, resizeable:false, label:'Switch samples', formatter:checkboxFormatter},
        {key:"drop", sortable:false, resizeable:false, label:'', formatter:removeFormatter}
    ];
    var myDataTable = new YAHOO.widget.DataTable(
        "exp_table", myColumnDefs, myDataSource, {}
    );

    var selPlatform = dom.get('pid');
    var selStudy = dom.get('stid');
    var selExperiment = dom.get('eid');

    function pickExperiment() {
        function incrementParentIfEmptyChild(parent, child) {
            // increment study if experiment is empty
            while (child.selectedIndex < 0 && parent.selectedIndex >= 0) {
                incrementDropdown(parent);
                triggerEvent(parent, 'change');
            }
        }
        incrementParentIfEmptyChild(selStudy, selExperiment);
        if (selExperiment.selectedIndex < 0) {
            return;
        }
        var result = {
            eid: getSelectedValue(selExperiment),
            stid: getSelectedValue(selStudy),
            pid: getSelectedValue(selPlatform)
        };

        // increment experiment to the next one
        selExperiment.selectedIndex++;
        incrementParentIfEmptyChild(selStudy, selExperiment);
        triggerEvent(selExperiment, 'change');
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

    var updateSpeciesSel = function(pid) {
        // updates hidden value with name 'pid' and id 'search_pid'
        var searchPlatform = dom.get('search_pid');
        searchPlatform.value = pid;
        triggerEvent(searchPlatform, 'change');
    }
    // restore model from old_json
    var old_json = JSON.parse(user_pse.value || '{}');
    var platfCurrSel = currentSelection[1].selected = tuplesToObj([old_json.pid]);
    var studyCurrSel = currentSelection[3].selected = tuplesToObj([old_json.stid]);
    var experCurrSel = currentSelection[5].selected = tuplesToObj([old_json.eid]);
    YAHOO.util.Event.addListener(selPlatform, 'change', function() {

        // two things: (1) every time a platform changes, update 'user_pse'
        // (2) if old value of 'user_pse' does not match new value, delete all
        // experiments from the comparison
        //
        var old_json = JSON.parse(user_pse.value || '{}');
        var new_pid = getSelectedValue(selPlatform);
        if (new_pid !== old_json.pid) {
            
            // remove all experiments selected for comparison because they 
            // belong to a different platform.
            myDataTable.deleteRows(0, myDataTable.getRecordSet().getLength());

            // change species dropdown in filter dialog to the species of the
            // newly selected platform.
            updateSpeciesSel(new_pid);
        }
        user_pse.value = JSON.stringify({
            pid: new_pid,
            stid: getSelectedValue(selStudy),
            eid: getSelectedValue(selExperiment)
        });
    });

    YAHOO.util.Event.addListener('add', 'click', function() {
        var pse_obj = pickExperiment();
        var eid = pse_obj.eid;
        var stid = pse_obj.stid;
        var pid = pse_obj.pid;

        if (typeof pid === 'undefined' || typeof eid === 'undefined') {
            return false;
        }
        var platfRoot = PlatfStudyExp[pid];
        var expRoot = platfRoot.experiments[eid];
        var studyRoot = platfRoot.studies[stid];
        var record = YAHOO.widget.DataTable._cloneObject({
            sample1  : expRoot.sample1,
            sample2  : expRoot.sample2,
            exp_info: expRoot.AdditionalInformation,
            pValFlag : expRoot.PValFlag,
<<<<<<< HEAD
            FCFlag : expRoot.FCFlag,

=======
>>>>>>> fff9d8d7950b20b683423368896ff5be2cc170a4
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
        user_pse.value = JSON.stringify({
            pid: getSelectedValue(selPlatform),
            stid: getSelectedValue(selStudy),
            eid: getSelectedValue(selExperiment)
        });
        user_selection.value = JSON.stringify(data);
    });
});
})();
