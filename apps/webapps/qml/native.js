// Aster: „natywizacja” strony w oknie aplikacji webowej.
// Wstrzykiwane do każdej strony aplikacji. Szuka jej nawigacji i oddaje ją oknu:
//  • boczne menu (wysoka kolumna z lewej z ≥3 krótkimi pozycjami) → natywny pasek boczny Aster,
//  • poziome zakładki u góry (3–8 pozycji w jednym rzędzie)      → przyciski w pasku tytułu,
//  • górny pasek strony                                            → pasek tytułu okna (przeciąganie, dwuklik),
//  • sekcje i liczniki menu, główny przycisk („Napisz”), pole wyszukiwania, kolory tła → natywne elementy okna.
// Do tego wygląd treści jak w systemie: czcionka Inter, kolor akcentu, zaznaczenie, obwódka fokusu.
// Oryginalne elementy są ukrywane klasą na <html>, więc wyłączenie przywraca stronę bez przeładowania.
// Rozmowa z oknem: console.debug("aster:{json}") → okno; okno → window.__aster.click(id) itd.
(function () {
    if (window.__aster) return;

    var A = {
        enabled: true,
        font: true,
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
        "html.aster-search [data-aster-search]{visibility:hidden!important}" +
        // Czcionka systemu w tekście strony — bez ikon (czcionki z ikonami, SVG) i kodu
        "html.aster-font body,html.aster-font body *:not(i):not(code):not(pre):not(kbd):not(samp):not(tt):not(var):not(svg):not(svg *)" +
        ":not([class*=icon]):not([class*=Icon]):not([class*=material]):not([class*=symbol]):not([class*=fa-]):not([class^=fa])" +
        ":not([class*=mono]):not([class*=code]):not([class*=Code]):not([class*=editor]):not([class*=cm-]):not([aria-hidden=true])" +
        "{font-family:Inter,'Inter Variable',system-ui,sans-serif!important}" +
        "html.aster-font{-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility}" +
        "html{accent-color:#3456E8}" +
        "*:focus-visible{outline-color:rgba(52,86,232,.75)!important}" +
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

    // Podpis i licznik pozycji: widoczny tekst („Odebrane” + „12”), a dla samych ikon aria-label/title
    function parseItem(el) {
        var lines = (el.innerText || "").split("\n").map(function (x) { return x.trim().replace(/\s+/g, " "); })
                                           .filter(function (x) { return x.length; });
        var label = "", count = "";
        for (var i = 0; i < lines.length; ++i) {
            if (/^\d{1,5}\+?$/.test(lines[i]) || /^\d+(,\d+)?\s?(tys\.|K|k|M)$/.test(lines[i])) { if (!count) count = lines[i]; }
            else if (!label) label = lines[i];
        }
        if (!label) {
            label = (el.getAttribute("aria-label") || el.getAttribute("title") || "").trim().replace(/\s+/g, " ");
            var m = /^(.*?)[,:]?\s+(\d{1,5})(\s.*)?$/.exec(label);
            if (m && !count) { label = m[1]; count = m[2]; }
        }
        return { label: label.length >= 1 && label.length <= 32 ? label : "", count: count };
    }
    function labelOf(el) { return parseItem(el).label; }

    function bgOf(el) {
        for (; el && el.nodeType === 1; el = el.parentElement) {
            var c = getComputedStyle(el).backgroundColor;
            if (c && c !== "transparent" && !/rgba\(.*,\s*0\)$/.test(c)) return c;
        }
        return "";
    }

    function isActive(el) {
        var cur = el.getAttribute("aria-current");
        if (cur && cur !== "false") return true;
        if (el.getAttribute("aria-selected") === "true" || el.getAttribute("aria-pressed") === "true") return true;
        var cls = typeof el.className === "string" ? el.className : "";
        if (/(^|[\s_-])(active|selected|current|is-active|is-selected)([\s_-]|$)/i.test(cls)) return true;
        if (el.parentElement && typeof el.parentElement.className === "string"
                && /(^|[\s_-])(active|selected|current)([\s_-]|$)/i.test(el.parentElement.className)) return true;
        // Link prowadzący dokładnie tu, gdzie jesteśmy (z kotwicą #… włącznie)
        try { return !!el.href && el.href === location.href && el.getAttribute("href") !== "/"; } catch (e) { return false; }
    }

    // Pozycje nawigacji w kontenerze: [{id, label, count, active, icon (svg), img}];
    // z withSections także nagłówki grup: {section: true, label}
    function itemsIn(box, max, maxHeight, withSections, skip) {
        var out = [], seen = {}, pendingSection = "";
        var sel = "a[href],[role=link],[role=tab],[role=menuitem],[role=treeitem],[role=option],button";
        if (withSections) sel += ",h1,h2,h3,h4,h5,[role=heading]";
        var list = box.querySelectorAll(sel);
        for (var i = 0; i < list.length && out.length <= max; ++i) {
            var el = list[i];
            if (skip && (el === skip || skip.contains(el))) continue;
            if (withSections && el.matches("h1,h2,h3,h4,h5,[role=heading]")) {
                if (visible(el) && !el.closest("a,button")) {
                    var h = (el.innerText || "").trim().split("\n")[0].trim();
                    if (h && h.length <= 28) pendingSection = h;
                }
                continue;
            }
            var r = el.getBoundingClientRect();
            if (r.height < 20 || r.height > maxHeight || r.width < 20) continue;
            if (!visible(el)) continue;
            var pi = parseItem(el), t = pi.label;
            if (!t || seen[t]) continue;
            seen[t] = true;
            if (pendingSection) { out.push({ section: true, label: pendingSection }); pendingSection = ""; }
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
            out.push({ id: el.dataset.asterId, label: t, count: pi.count, active: isActive(el), icon: icon, img: img, top: Math.round(r.top) });
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
        if (!best) return null;
        var primary = findPrimary(best);
        var items = itemsIn(best, 60, best.getBoundingClientRect().width < 110 ? 88 : 56, true, primary ? primary.el : null);
        return { el: best, items: items, width: best.getBoundingClientRect().width, primary: primary ? primary.info : null,
                 bg: bgOf(best) };
    }

    // Wyróżniony przycisk na górze menu („Napisz”, „Nowy czat”): wypełnione tło, większy, krótki podpis
    function findPrimary(box) {
        var boxBg = bgOf(box);
        var list = box.querySelectorAll("button,a[href],[role=button]");
        for (var i = 0, seen = 0; i < list.length && seen < 5; ++i) {
            var el = list[i];
            if (!visible(el)) continue;
            ++seen;
            var r = el.getBoundingClientRect();
            if (r.height < 36 || r.height > 64 || r.width < 72) continue;
            var bg = getComputedStyle(el).backgroundColor;
            if (!bg || bg === "transparent" || /rgba\(.*,\s*0\)$/.test(bg) || bg === boxBg) continue;
            var t = labelOf(el);
            if (!t || t.length > 24) continue;
            if (!el.dataset.asterId) el.dataset.asterId = String(A.nextId++);
            var svg = el.querySelector("svg");
            return { el: el, info: { id: el.dataset.asterId, label: t, icon: svg && svg.outerHTML.length < 7000 ? svg.outerHTML : "" } };
        }
        return null;
    }

    // Główne pole wyszukiwania strony (u góry albo w menu)
    function findSearch() {
        var list = document.querySelectorAll("input[type=search],[role=search] input,input[role=combobox],input[aria-label*=zukaj i]," +
                                              "input[aria-label*=earch i],input[placeholder*=zukaj i],input[placeholder*=earch i],input[name=q],input[name=search_query]");
        for (var i = 0; i < list.length; ++i) {
            var el = list[i];
            if (!visible(el) || el.disabled) continue;
            var r = el.getBoundingClientRect();
            if (r.top > 170 || r.width < 100) continue;
            if (!el.dataset.asterId) el.dataset.asterId = String(A.nextId++);
            // Chowamy formularz wyszukiwania (z ikoną i tłem), a gdy go nie ma — samo pole, nie cały nagłówek
            var wrap = el.closest("form,[role=search]") || el;
            if (wrap.getBoundingClientRect().width > 900) wrap = el;
            return { el: el, wrap: wrap, info: { id: el.dataset.asterId, placeholder: el.getAttribute("placeholder") || el.getAttribute("aria-label") || "Szukaj", value: el.value || "" } };
        }
        return null;
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
        // Sprawdzamy kilka punktów treści i główny kontener — wystarczy trafić w przesunięty element
        var starts = [];
        var main = document.querySelector("main,[role=main]");
        if (main) starts.push(main);
        [0.15, 0.3, 0.5, 0.7].forEach(function (fy) {
            var el = document.elementFromPoint(Math.min(innerWidth - 10, width + 40), Math.round(innerHeight * fy));
            if (el) starts.push(el);
        });
        starts.forEach(function (el) {
            for (var depth = 0; el && el !== document.body && el !== document.documentElement && depth < 14; ++depth, el = el.parentElement) {
                var s = getComputedStyle(el);
                var ml = parseFloat(s.marginLeft) || 0, pl = parseFloat(s.paddingLeft) || 0, l = parseFloat(s.left) || 0;
                if (Math.abs(ml - width) < 18 || Math.abs(pl - width) < 18 || (s.position !== "static" && Math.abs(l - width) < 18))
                    el.dataset.asterZero = "1";
            }
        });
    }

    function clearMarks(attr) {
        var old = document.querySelectorAll("[" + attr + "]");
        for (var i = 0; i < old.length; ++i) old[i].removeAttribute(attr);
    }

    var observer = null;
    function update() {
        if (!document.body) return;
        // Aplikacja z natywną nakładką (Adapters.js): nic nie wykrywamy, tylko czcionka systemu
        if (window.__asterAdapter) {
            document.documentElement.classList.toggle("aster-font", A.font);
            return;
        }
        if (observer) observer.disconnect();
        var root = document.documentElement;
        root.classList.remove("aster-sidebar", "aster-topnav", "aster-controls", "aster-search", "aster-font");

        var side = A.enabled ? findSidebar() : null;
        var nav = A.enabled && !side ? findTopnav() : null;
        var bar = findTopbar();
        var search = A.enabled ? findSearch() : null;

        clearMarks("data-aster-sidebar");
        clearMarks("data-aster-topnav");
        clearMarks("data-aster-topbar");
        clearMarks("data-aster-search");
        if (search) {
            search.wrap.setAttribute("data-aster-search", "");
            root.classList.add("aster-search");
        }
        if (A.font) root.classList.add("aster-font");
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
            primary: side ? side.primary : null,
            topnav: nav ? nav.items : [],
            topbar: A.topbarBottom,
            search: search ? search.info : null,
            pageBg: bgOf(document.body) || "rgb(255, 255, 255)",
            sideBg: side ? side.bg : "",
            topbarBg: bar ? bgOf(bar) : ""
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
    // Wyszukiwarka okna steruje polem strony (wartość jak przy pisaniu — działa też w React/Vue)
    A.search = function (id, text) {
        var el = document.querySelector("[data-aster-id='" + id + "']");
        if (!el) return;
        var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
        setter.call(el, text);
        el.dispatchEvent(new Event("input", { bubbles: true }));
        el.dispatchEvent(new Event("change", { bubbles: true }));
    };
    A.submit = function (id) {
        var el = document.querySelector("[data-aster-id='" + id + "']");
        if (!el) return;
        el.focus();
        var opts = { key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true, cancelable: true };
        var ev = new KeyboardEvent("keydown", opts);
        var handled = !el.dispatchEvent(ev);
        el.dispatchEvent(new KeyboardEvent("keyup", opts));
        if (!handled && el.form) { try { el.form.requestSubmit(); } catch (e) { el.form.submit(); } }
        schedule();
    };
    // Przejście do adresu w serwisie bez przeładowania (aplikacje jednostronicowe słuchają popstate);
    // gdy strona nie zareaguje, zwykłe przejście
    A.go = function (url) {
        var target = new URL(url, location.href);
        if (target.origin !== location.origin) { location.assign(target.href); return; }
        history.pushState({}, "", target.href);
        dispatchEvent(new PopStateEvent("popstate", { state: {} }));
        setTimeout(function () {
            if (location.href !== target.href) location.assign(target.href);
        }, 1500);
    };
    A.setFont = function (on) { A.font = on; A.last = ""; update(); };
    A.setEnabled = function (on) { A.enabled = on; A.last = ""; update(); };
    A.refresh = function () { A.last = ""; update(); };

    // Przeciąganie okna za puste miejsca górnego paska strony; dwuklik maksymalizuje
    function inDragZone(e) {
        if (e.button !== 0) return false;
        if (e.target.closest && e.target.closest(INTERACTIVE)) return false;
        if (window.__asterAdapter || !A.topbarBottom) return false;
        return e.clientY <= A.topbarBottom;
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
