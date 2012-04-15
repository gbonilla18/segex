;(function (exports) {

"use strict";

exports.setupCheckboxes = function(obj) {
    var count_checked = 0;
    var buttons = forEach(
        YAHOO.util.Dom.getElementsBy(
            function(obj) { return (obj.type === 'checkbox'); }, 
            'INPUT', 
            obj.idPrefix + '_container'
        ),
        function(el) {
            var button = new YAHOO.widget.Button(el);
            if (button.get('checked')) { count_checked++; }
            this.push(button);
        },
        []
    );

    // event handlers
    var minChecked = (typeof obj.minChecked !== 'undefined') ? obj.minChecked : 0;
    var beforeCheckedChange = function(ev) {
        return ((ev.prevValue && !ev.newValue && count_checked <= minChecked) ? false : true);
    };
    var checkedChange = function(ev) { 
        count_checked += (ev.newValue ? 1 : -1);
        updateBanner();
    };

    forEach(buttons, function(btn) {
        btn.addListener("beforeCheckedChange", beforeCheckedChange);
        btn.addListener("checkedChange", checkedChange);
    });
    var banner = document.getElementById(obj.idPrefix + '_hint');
    function updateBanner() {
        banner.innerHTML = 
            '<p>The file should contain the following columns:</p><ol>' + 
            forEach(buttons, function(button) {
                if (button.get('checked')) {
                    this.push("<li>" + button.get('value') + "</li>");
                }
            }, []).join('') + 
            '</ol>';
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
