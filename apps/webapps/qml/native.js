// Aster: „natywizacja” strony w oknie aplikacji webowej.
// Wstrzykiwane do każdej strony aplikacji. Szuka jej nawigacji i oddaje ją oknu:
//  • boczne menu (wysoka kolumna z lewej z ≥3 krótkimi pozycjami) → natywny pasek boczny Aster,
//  • poziome zakładki u góry (3–8 pozycji w jednym rzędzie)      → przyciski w pasku tytułu,
//  • górny pasek strony                                            → pasek tytułu okna (przeciąganie, dwuklik).
// Oryginalne elementy są ukrywane klasą na <html>, więc wyłączenie przywraca stronę bez przeładowania.
// Rozmowa z oknem: console.debug("aster:{json}") → okno; okno → window.__aster.click(id) itd.
(function () {
    if (window.__aster) return;

    var A = {
        enabled: true,
        nextId: 1,
        sidebarEl: null,
        topnavEl: null,
        topbarEl: null,
        topbarBottom: 0,
        last: "",
        timer: 0
    };
    window.__aster = A;

    function post(o) { console.debug("aster:" + JSON.stringify(o)); }

    var css = document.createElement("style");
    css.id = "aster-native";
    css.textContent =
        "html.aster-sidebar [data-aster-sidebar]{display:none!important}" +
        "html.aster-topnav [data-aster-topnav=hide]{visibility:hidden!important}" +
        "html.aster-topnav [data-aster-topnav=collapse]{display:none!important}" +
        "html.aster-controls [data-aster-topbar=flow]{padding-right:150px!important;box-sizing:border-box!important}" +
        "html.aster-controls [data-aster-topbar=fixed]{width:calc(100% - 150px)!important;right:auto!important}" +
        "html.aster-sidebar [data-aster-zero]{margin-left:0!important;padding-left:0!important;left:0!important}" +
        "::selection{background:rgba(52,86,232,.28)}";

    var INTERACTIVE = "a,button,input,textarea,select,label,summary,video,audio,iframe,[role=button],[role=link],[role=tab]," +
                      "[role=menuitem],[role=textbox],[role=searchbox],[role=combobox],[role=slider],[contenteditable=''],[contenteditable=true]," +
                      "[draggable=true],[tabindex]:not([tabindex='-1'])";

    function visible(el) {
        var r = el.getBoundingClientRect();
        if (r.width <= 0 || r.height <= 0) return false;
        var s = getComputedStyle(el);
        return s.visibility !== "hidden" && s.display !== "none" && parseFloat(s.opacity || "1") > 0.05;
    }

    function labelOf(el) {
        // Najpierw to, co widać na ekranie; opisy (aria-label, title) tylko dla samych ikon
        var shown = (el.innerText || "").trim().split("\n")[0].trim().replace(/\s+/g, " ");
        var t = shown || (el.getAttribute("aria-label") || el.getAttribute("title") || "").trim().replace(/\s+/g, " ");
        return t.length >= 1 && t.length <= 32 ? t : "";
    }

    function isActive(el) {
        var cur = el.getAttribute("aria-current");
        if (cur && cur !== "false") return true;
        if (el.getAttribute("aria-selected") === "true" || el.getAttribute("aria-pressed") === "true") return true;
        var cls = typeof el.className === "string" ? el.className : "";
        if (/(^|[\s_-])(active|selected|current|is-active|is-selected)([\s_-]|$)/i.test(cls)) return true;
        if (el.parentElement && typeof el.parentElement.className === "string"
                && /(^|[\s_-])(active|selected|current)([\s_-]|$)/i.test(el.parentElement.className)) return true;
        try { return !!el.href && el.href.split("#")[0] === location.href.split("#")[0] && el.getAttribute("href") !== "/"; } catch (e) { return false; }
    }

    // Pozycje nawigacji w kontenerze: [{id, label, active, icon (svg), img}]
    function itemsIn(box, max, maxHeight) {
        var out = [], seen = {};
        var list = box.querySelectorAll("a[href],[role=link],[role=tab],[role=menuitem],[role=treeitem],[role=option],button");
        for (var i = 0; i < list.length && out.length <= max; ++i) {
            var el = list[i];
            var r = el.getBoundingClientRect();
            if (r.height < 20 || r.height > maxHeight || r.width < 20) continue;
            if (!visible(el)) continue;
            var t = labelOf(el);
            if (!t || seen[t]) continue;
            seen[t] = true;
            if (!el.dataset.asterId) el.dataset.asterId = String(A.nextId++);
            var icon = "", img = "";
            var svg = el.querySelector("svg");
            if (svg) {
                var s = svg.outerHTML;
                if (s.length < 7000) icon = s;
            } else {
                var im = el.querySelector("img");
                if (im && im.src && im.getBoundingClientRect().width <= 48) img = im.src;
            }
            out.push({ id: el.dataset.asterId, label: t, active: isActive(el), icon: icon, img: img, top: Math.round(r.top) });
        }
        return out;
    }

    function findSidebar() {
        var vh = innerHeight, best = null, bestScore = 0, bestItems = [];
        var cands = document.querySelectorAll("nav,aside,[role=navigation],[role=complementary],div,section,tp-yt-app-drawer");
        for (var i = 0; i < cands.length; ++i) {
            var el = cands[i];
            if (el === document.body || el === document.documentElement) continue;
            var r = el.getBoundingClientRect();
            if (r.left > 6 || r.width < 52 || r.width > 360 || r.height < vh * 0.55 || r.top > vh * 0.3) continue;
            if (innerWidth - r.width < 320) continue;                         // to nie kolumna, tylko cała strona
            var items = itemsIn(el, 60, r.width < 110 ? 88 : 56);
            if (items.length < 3 || items.length > 50) continue;
            var score = items.length + (el.matches("nav,aside,[role=navigation]") ? 8 : 0) + (r.width >= 150 ? 4 : 0);
            if (score > bestScore) { best = el; bestScore = score; bestItems = items; }
        }
        return best ? { el: best, items: bestItems, width: best.getBoundingClientRect().width } : null;
    }

    function findTopnav() {
        var cands = document.querySelectorAll("nav,[role=navigation],[role=tablist],header ul,ul");
        var best = null, bestScore = 0, bestItems = [];
        for (var i = 0; i < cands.length; ++i) {
            var el = cands[i];
            var r = el.getBoundingClientRect();
            if (r.top > 160 || r.top < -2 || r.height > 90 || r.width < 200) continue;
            var items = itemsIn(el, 10, 60);
            if (items.length < 3 || items.length > 8) continue;
            var top0 = items[0].top, row = true;
            for (var k = 1; k < items.length; ++k) if (Math.abs(items[k].top - top0) > 14) { row = false; break; }
            if (!row || items.some(function (it) { return it.label.length > 22; })) continue;
            var score = items.length + (el.matches("nav,[role=navigation],[role=tablist]") ? 6 : 0);
            if (score > bestScore) { best = el; bestScore = score; bestItems = items; }
        }
        return best ? { el: best, items: bestItems } : null;
    }

    function findTopbar() {
        var cands = document.querySelectorAll("header,[role=banner],#masthead-container,#masthead,nav,div");
        for (var i = 0; i < cands.length; ++i) {
            var el = cands[i];
            var r = el.getBoundingClientRect();
            if (r.top > 4 || r.top < -4 || r.height < 36 || r.height > 110 || r.width < innerWidth * 0.6) continue;
            var pos = getComputedStyle(el).position;
            if (el.matches("header,[role=banner],#masthead-container") || pos === "fixed" || pos === "sticky") return el;
        }
        return null;
    }

    // Po schowaniu menu treść bywa nadal przesunięta o jego szerokość — zerujemy to przesunięcie
    function fixGap(width) {
        var el = document.elementFromPoint(Math.min(innerWidth - 10, width + 40), Math.round(innerHeight * 0.6));
        for (var depth = 0; el && el !== document.body && depth < 14; ++depth, el = el.parentElement) {
            var s = getComputedStyle(el);
            var ml = parseFloat(s.marginLeft) || 0, pl = parseFloat(s.paddingLeft) || 0, l = parseFloat(s.left) || 0;
            if (Math.abs(ml - width) < 14 || Math.abs(pl - width) < 14 || (s.position !== "static" && Math.abs(l - width) < 14))
                el.dataset.asterZero = "1";
        }
    }

    function clearMarks(attr) {
        var old = document.querySelectorAll("[" + attr + "]");
        for (var i = 0; i < old.length; ++i) old[i].removeAttribute(attr);
    }

    var observer = null;
    function update() {
        if (!document.body) return;
        if (observer) observer.disconnect();
        var root = document.documentElement;
        root.classList.remove("aster-sidebar", "aster-topnav", "aster-controls");

        var side = A.enabled ? findSidebar() : null;
        var nav = A.enabled && !side ? findTopnav() : null;
        var bar = findTopbar();

        clearMarks("data-aster-sidebar");
        clearMarks("data-aster-topnav");
        clearMarks("data-aster-topbar");
        if (side) {
            side.el.setAttribute("data-aster-sidebar", "");
            root.classList.add("aster-sidebar");
            fixGap(side.width);
        }
        if (nav) {
            // Cały pas z samymi zakładkami (np. ciemny pasek nad stroną) można zwinąć; inaczej tylko je ukryć
            var strip = nav.el, nr = nav.el.getBoundingClientRect();
            for (var up = 0, p = nav.el.parentElement; p && p !== document.body && up < 4; ++up, p = p.parentElement) {
                var pr = p.getBoundingClientRect();
                if (pr.height > nr.height + 20 || pr.width < innerWidth * 0.9) break;
                var others = Array.prototype.some.call(p.querySelectorAll(INTERACTIVE), function (x) { return !nav.el.contains(x) && visible(x); });
                if (others) break;
                strip = p;
            }
            nav.el.setAttribute("data-aster-topnav", strip === nav.el ? "hide" : "");
            if (strip !== nav.el) strip.setAttribute("data-aster-topnav", "collapse");
            root.classList.add("aster-topnav");
        }
        A.topbarBottom = 0;
        if (bar && !nav) {
            var bp = getComputedStyle(bar).position;
            bar.setAttribute("data-aster-topbar", bp === "fixed" || bp === "absolute" ? "fixed" : "flow");
            root.classList.add("aster-controls");
            A.topbarBottom = Math.round(bar.getBoundingClientRect().bottom);
        }
        var state = JSON.stringify({
            type: "layout",
            sidebar: side ? side.items : [],
            topnav: nav ? nav.items : [],
            topbar: A.topbarBottom
        });
        if (state !== A.last) {
            A.last = state;
            console.debug("aster:" + state);
        }
        if (observer) { observer.takeRecords(); observe(); }
    }
    function schedule() {
        clearTimeout(A.timer);
        A.timer = setTimeout(update, 350);
    }
    function observe() {
        observer.observe(document.body, { childList: true, subtree: true, attributes: true,
                                          attributeFilter: ["class", "aria-current", "aria-selected", "hidden", "style"] });
    }

    A.click = function (id) {
        var el = document.querySelector("[data-aster-id='" + id + "']");
        if (!el) return;
        ["pointerdown", "mousedown", "pointerup", "mouseup"].forEach(function (t) {
            el.dispatchEvent(new MouseEvent(t, { bubbles: true, cancelable: true, view: window, button: 0 }));
        });
        el.click();
        schedule();
    };
    // Diagnostyka (aster-webapps --run … --debug): kandydaci na nawigację
    A.explain = function () {
        var out = [];
        var c = document.querySelectorAll("nav,[role=navigation],[role=tablist],ul");
        for (var i = 0; i < c.length && out.length < 12; ++i) {
            var r = c[i].getBoundingClientRect();
            if (r.top > 200 || r.width < 100) continue;
            var it = itemsIn(c[i], 10, 60);
            out.push((c[i].tagName + "." + (typeof c[i].className === "string" ? c[i].className.slice(0, 30) : "")) + " top=" + Math.round(r.top)
                     + " h=" + Math.round(r.height) + " w=" + Math.round(r.width) + " items=" + it.length + " [" + it.map(function (x) { return x.label + "@" + x.top; }).join(",") + "]");
        }
        return out.join("\n");
    };
    A.setEnabled = function (on) { A.enabled = on; A.last = ""; update(); };
    A.refresh = function () { A.last = ""; update(); };

    // Przeciąganie okna za puste miejsca górnego paska strony; dwuklik maksymalizuje
    function inDragZone(e) {
        if (e.button !== 0) return false;
        if (e.target.closest && e.target.closest(INTERACTIVE)) return false;
        var limit = A.topbarBottom || 40;
        return e.clientY <= limit;
    }
    document.addEventListener("mousedown", function (e) { if (inDragZone(e)) post({ type: "drag" }); }, true);
    document.addEventListener("dblclick", function (e) { if (inDragZone(e)) post({ type: "maximize" }); }, true);

    function start() {
        (document.head || document.documentElement).appendChild(css);
        observer = new MutationObserver(schedule);
        observe();
        addEventListener("resize", schedule);
        addEventListener("popstate", schedule);
        ["pushState", "replaceState"].forEach(function (m) {
            var orig = history[m];
            history[m] = function () { var r = orig.apply(this, arguments); schedule(); return r; };
        });
        update();
        setTimeout(update, 1200);
        setTimeout(update, 3500);
    }
    if (document.body) start(); else document.addEventListener("DOMContentLoaded", start);
})();
