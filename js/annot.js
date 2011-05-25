(function() {

var util = YAHOO.util; 
var Dom = util.Dom;
var Event = util.Event;
var DDM = util.DragDropMgr;
 
//////////////////////////////////////////////////////////////////////////////
// example app
//////////////////////////////////////////////////////////////////////////////
var DDApp = {
    init: function() {
 
        var cols=2,i,j,len;
        for (i=1; i<=cols; i++) {
            new util.DDTarget("ul"+i);
        }
 
	var children = Dom.getChildren("ul1");
 	for (i = 0, len = children.length; i < len; i++) {
		new DDList(children[i].getAttribute("id"));
	}
        children = Dom.getChildren("ul2");
        for (i = 0, len = children.length; i < len; i++) {
                new DDList(children[i].getAttribute("id"));
        }
    }
};
 
//////////////////////////////////////////////////////////////////////////////
// custom drag and drop implementation
//////////////////////////////////////////////////////////////////////////////
 
var DDList = function(id, sGroup, config) {
 
    DDList.superclass.constructor.call(this, id, sGroup, config);
 
    this.logger = this.logger || YAHOO;
    var el = this.getDragEl();
    Dom.setStyle(el, "opacity", 0.67); // The proxy is slightly transparent
 
    this.goingUp = false;
    this.lastY = 0;
};
 
YAHOO.extend(DDList, util.DDProxy, {
 
    startDrag: function(x, y) {
        this.logger.log(this.id + " startDrag");
 
        // make the proxy look like the source element
        var dragEl = this.getDragEl();
        var clickEl = this.getEl();
        Dom.setStyle(clickEl, "visibility", "hidden");
 
        dragEl.innerHTML = clickEl.innerHTML;
 
        Dom.setStyle(dragEl, "color", Dom.getStyle(clickEl, "color"));
        Dom.setStyle(dragEl, "backgroundColor", Dom.getStyle(clickEl, "backgroundColor"));
        Dom.setStyle(dragEl, "border", "2px solid gray");
    },
 
    endDrag: function(e) {
 
        var srcEl = this.getEl();
        var proxy = this.getDragEl();
 
        // Show the proxy element and animate it to the src element's location
        Dom.setStyle(proxy, "visibility", "");
        var a = new util.Motion( 
            proxy, { 
                points: { 
                    to: Dom.getXY(srcEl)
                }
            }, 
            0.2, 
            util.Easing.easeOut 
        )
        var proxyid = proxy.id;
        var thisid = this.id;
 
        // Hide the proxy and show the source element when finished with the animation
        a.onComplete.subscribe(function() {
                Dom.setStyle(proxyid, "visibility", "hidden");
                Dom.setStyle(thisid, "visibility", "");
            });
        a.animate();
    },
 
    onDragDrop: function(e, id) {
 
        // If there is one drop interaction, the li was dropped either on the list,
        // or it was dropped on the current location of the source element.
        if (DDM.interactionInfo.drop.length === 1) {
 
            // The position of the cursor at the time of the drop (util.Point)
            var pt = DDM.interactionInfo.point; 
 
            // The region occupied by the source element at the time of the drop
            var region = DDM.interactionInfo.sourceRegion; 

            // Check to see if we are over the source element's location.  We will
            // append to the bottom of the list once we are sure it was a drop in
            // the negative space (the area of the list without any list items)
            if (!region.intersect(pt)) {
		var srcEl = this.getEl();
		var destEl = Dom.get(id);
		p = destEl.parentNode;
		// disallow moving elements with class "list2" into element with id "ul1"
		// also disallow moving elements within "ul1"
		if (!(Dom.hasClass(srcEl, "list2") && destEl.getAttribute("id") == "ul1") &&
		    !(srcEl.parentNode.getAttribute("id") == "ul1" && destEl.getAttribute("id") == "ul1")) {
			var destDD = DDM.getDDById(id);
			destEl.appendChild(srcEl);
			destDD.isEmpty = false;
			DDM.refreshCache();
		}
            }
 
        }
	setOrder();
    },
 
    onDrag: function(e) {
 
        // Keep track of the direction of the drag for use during onDragOver
        var y = Event.getPageY(e);
 
        if (y < this.lastY) {
            this.goingUp = true;
        } else if (y > this.lastY) {
            this.goingUp = false;
        }
 
        this.lastY = y;
    },
 
    onDragOver: function(e, id) {
    
        var srcEl = this.getEl();
        var destEl = Dom.get(id);

        // We are only concerned with list items, we ignore the dragover
        // notifications for the list.
        if (destEl.nodeName.toLowerCase() == "li") {
            var orig_p = srcEl.parentNode;
            var p = destEl.parentNode;

		// disallow moving elements with class "list2" into parent element with id "ul1"
		// also disallow moving elements within "ul1"
		if (!(Dom.hasClass(srcEl, "list2") && p.getAttribute("id") == "ul1") &&
		    !(srcEl.parentNode.getAttribute("id") == "ul1" && p.getAttribute("id") == "ul1")) {

		    if (this.goingUp) {
			p.insertBefore(srcEl, destEl); // insert above
		    } else {
			p.insertBefore(srcEl, destEl.nextSibling); // insert below
		    }
		}
            DDM.refreshCache();
        }
    }
});

function setOrder() {
        function parseList(ul) {
                var items = ul.getElementsByTagName("li");
                var out = "";
                for (i = 0, len = items.length; i < len; i++) {
                        out += items[i].id + ",";
                }
                return out.replace(/,$/, "");
        };
	Dom.get("fields").value = parseList(Dom.get("ul2"));
	//alert(Dom.get("fields").value);
}
 
Event.onDOMReady(DDApp.init, DDApp, true);

 
})();
