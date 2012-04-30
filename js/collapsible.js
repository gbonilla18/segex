;(function (exports) {

"use strict";

exports.setupCheckboxes = function(obj) {
    var count_checked = 0;
    var state;
    var state_element = dom.get(obj.idPrefix + '_state');
    // try to recover state
    try {
        state = JSON.parse(state_element.value);
    } catch (e) {
        state = {};
    }
    var buttons = forEach(
        YAHOO.util.Dom.getElementsBy(
            function(obj) { return (obj.type === 'checkbox'); }, 
            'INPUT', 
            obj.idPrefix + '_container'
        ),
        function(el) {
            var button = new YAHOO.widget.Button(el);
            var btnId = button.get('name');
            if (state.hasOwnProperty(btnId)) {
                if (state[btnId]) {
                    button.set('checked', true);
                    count_checked++;
                } else {
                    button.set('checked', false);
                }
            } else {
                if (button.get('checked')) {
                    count_checked++;
                    state[btnId] = true;
                } else {
                    state[btnId] = false;
                }
            }
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
                var btnId = button.get('name');
                if (button.get('checked')) {
                    state[btnId] = true;
                    this.push("<li>" + button.get('title') + "</li>");
                } else {
                    state[btnId] = false;
                }
            }, []).join('') + 
            '</ol>';
        state_element.value = JSON.stringify(state);
    }
    updateBanner();
    return buttons;
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
