;(function (exports) {

"use strict";

exports.setupCheckboxes = function(obj) {
    var idPrefix = obj.idPrefix;
    var checkboxIds = YAHOO.util.Dom.getElementsBy(
        function(obj) { return ((obj.type === 'checkbox') ? true : false); }, 
        'INPUT', 
        idPrefix + '_container'
    );
    var minChecked = (typeof obj.minChecked !== 'undefined') ? obj.minChecked : 1;
    var count_checked = 0;

    var buttons = forEach(checkboxIds, function(el) {
        var button = new YAHOO.widget.Button(el.id);
        if (button.get('checked')) { count_checked++; }
        this[el.id] = button;
    }, {});

    // event handlers
    var beforeCheckedChange = function(ev) {
        return ((ev.prevValue && !ev.newValue && count_checked <= minChecked) ? false : true);
    };
    var checkedChange = function(ev) { 
        count_checked += (ev.newValue ? 1 : -1);
        updateBanner();
    };

    object_forValues(buttons, function(btn) {
        btn.addListener("beforeCheckedChange", beforeCheckedChange);
        btn.addListener("checkedChange", checkedChange);
    });
    var banner = document.getElementById(idPrefix + '_hint');
    function updateBanner() {
        var bannerText = "<p>The file should contain the following columns:</p><ol><li>" + obj.keyName + "</li>";
        object_forValues(buttons, function(button) {
            if (button.get('checked')) {
                bannerText += "<li>" + button.get('value') + "</li>";
            }
        });
        bannerText += "</ol>";
        banner.innerHTML = bannerText;
    }
    updateBanner();
}

YAHOO.util.Event.addListener(window, 'load', function() {
    var els = YAHOO.util.Dom.getElementsByClassName('pluscol', 'a', 'content');

    var fun1 = function(el) {
        return el.text.substr(0, 1);
    };
    var fun2 = function(el) { 
        if (el.text.substr(0, 1) === '+') {
            el.innerHTML = '-' + el.text.substr(1);
        } else {
            el.innerHTML = '+' + el.text.substr(1);
        }
    };
    forEach(els, function(el) {
        setupToggles(
            'click', 
            pairs2obj([el.id, {'-': [el.id + '_container']}]), 
            fun1, fun2
        );
    });
});

}(this));
