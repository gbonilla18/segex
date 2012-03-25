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
    var buttons = {};
    var count_checked = 0;
    for (var i = 0, len = checkboxIds.length; i < len; i++) {
        var checkboxId = checkboxIds[i].id;
        var button = new YAHOO.widget.Button(checkboxId);
        if (button.get('checked')) {
            count_checked++;
        }
        buttons[checkboxId] = button;
    }

    // event handlers
    var beforeCheckedChange = function(ev) {
        return ((ev.prevValue && !ev.newValue && count_checked <= minChecked) ? false : true);
    };
    var checkedChange = function(ev) { 
        count_checked += (ev.newValue ? 1 : -1);
        updateBanner();
    };
    for (var cId in buttons) {
        if (buttons.hasOwnProperty(cId)) {
            var btn = buttons[cId];
            btn.addListener("beforeCheckedChange", beforeCheckedChange);
            btn.addListener("checkedChange", checkedChange);
        }
    }
    var banner = document.getElementById(idPrefix + '_hint');
    function updateBanner() {
        var bannerText = "<p>The file should contain the following columns:</p><ol><li>" + obj.keyName + "</li>";
        for (var checkboxId in buttons) {
            if (buttons.hasOwnProperty(checkboxId)) {
                var button = buttons[checkboxId];
                if (button.get('checked')) {
                    bannerText += "<li>" + button.get('value') + "</li>";
                }
            }
        }
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
    for (var i = 0, len = els.length; i < len; i++) {
        var el_id = els[i].id;
        var struct = {};
        struct[el_id] = {'-': [el_id + '_container']};
        setupToggles('click', struct, fun1, fun2);
    }
});

}(this));
