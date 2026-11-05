pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Aster.Ui
import Aster.Grafika

// Płótno: strona z elementami, zaznaczenie z uchwytami (skalowanie, obrót), linie pomocnicze
// z przyciąganiem do środka i krawędzi strony oraz innych elementów, edycja tekstu w miejscu.
// Kilka elementów: Shift+klik albo ramka przeciągnięta po pustym miejscu. Dwuklik na zdjęciu — kadrowanie.
Item {
    id: stage
    required property Project project
    property string selected: ""               // jeden zaznaczony element (przy kilku — "")
    property var selection: []                  // wszystkie zaznaczone (id)
    property var group: ({})                    // prostokąt obejmujący kilka zaznaczonych (piksele strony)
    property string editing: ""
    property string cropping: ""                // zdjęcie w trybie kadrowania
    // Narzędzia AI na zaznaczonym zdjęciu: object (kliknięcie w rzecz) | brush | lasso
    readonly property bool magicOn: Magic.element !== "" && Magic.element === selected
    property string magicTool: "object"
    property real brushSize: 36                 // piksele ekranu
    property bool magicSubtract: false
    property rect marquee: Qt.rect(0, 0, 0, 0)  // ramka zaznaczania (piksele strony)
    property bool marqueeOn: false
    property var marqueeBase: []
    property bool syncing: false
    property var current: ({})                 // dane zaznaczonego elementu
    property bool fit: true                     // powiększenie „dopasuj do okna”
    property real userZoom: 1
    readonly property real fitZoom: Math.max(0.02, Math.min((width - ruler - 96) / project.pageWidth, (height - ruler - 96) / project.pageHeight))
    readonly property real zoom: fit ? fitZoom : userZoom
    property var guidesX: []
    property var guidesY: []
    property var snapX: []
    property var snapY: []
    property var snapRects: []                  // pozostałe elementy (prostokąty) — do równych odstępów
    property var gaps: []                       // znaczniki równych odstępów: { axis, s, e, c }
    property bool rulers: false                 // linijki i własne prowadnice (project.guides)
    readonly property real ruler: rulers ? 20 : 0
    property string hint: ""                    // np. wymiary albo kąt podczas zmiany
    signal menuRequested(real x, real y)
    signal quickAction(string action)           // pasek przy zaznaczeniu i pusta strona → EditorPage.runMenu
    property bool dragging: false               // przesuwanie elementów myszą (pasek szybkich działań znika)

    clip: true

    // Przesuwanie widoku: spacja + przeciąganie albo środkowy przycisk myszy
    property bool panning: false
    Keys.onPressed: (e) => { if (e.key === Qt.Key_Space && !e.isAutoRepeat && editing === "") { panning = true; e.accepted = true; } }
    Keys.onReleased: (e) => { if (e.key === Qt.Key_Space && !e.isAutoRepeat) { panning = false; e.accepted = true; } }

    function refresh() {
        current = selected !== "" ? project.get(selected) : ({});
        if (selected !== "" && current.id === undefined) selected = "";
        const alive = selection.filter(id => project.indexOf(id) >= 0);
        if (alive.length !== selection.length) { setSelection(alive); return; }
        if (cropping !== "" && cropping !== selected) cropping = "";
        group = selection.length > 1 ? bounds(selection) : ({});
    }
    onSelectedChanged: {
        if (Magic.element !== "" && selected !== Magic.element) Magic.end();
        if (!syncing) selection = selected !== "" ? [selected] : [];
        refresh();
    }
    function setSelection(list) {
        syncing = true;
        selection = list;
        selected = list.length === 1 ? list[0] : "";
        syncing = false;
        refresh();
    }
    function isSelected(id) { return selection.indexOf(id) >= 0; }
    // Kliknięcie w element grupy zaznacza całą grupę
    function groupOf(id) {
        const g = project.get(id).group;
        if (!g) return [id];
        return project.document().elements.filter(o => o.group === g && !o.hidden).map(o => o.id);
    }
    function selectWithGroup(id) {
        if (editing !== "" && editing !== id) stopEditing();
        if (cropping !== "" && cropping !== id) cropping = "";
        setSelection(groupOf(id));
    }
    function toggle(id) {
        const i = selection.indexOf(id);
        const list = selection.slice();
        if (i >= 0) list.splice(i, 1); else list.push(id);
        if (editing !== "") stopEditing();
        setSelection(list);
    }
    function selectAll() {
        stopEditing();
        setSelection(project.document().elements.filter(o => !o.hidden && !o.locked).map(o => o.id));
    }
    function clearSelection() {
        stopEditing();
        cropping = "";
        setSelection([]);
    }
    // Esc: najpierw kończy kadrowanie, potem zdejmuje zaznaczenie
    function cancel() {
        if (magicOn) Magic.end();
        else if (cropping !== "") cropping = "";
        else clearSelection();
    }
    // Prostokąt (bez obrotu) obejmujący elementy
    function bounds(ids) {
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        for (const id of ids) {
            const o = project.get(id);
            if (o.id === undefined) continue;
            const b = box(o, o.x, o.y);
            x0 = Math.min(x0, b.xs[0]); x1 = Math.max(x1, b.xs[2]);
            y0 = Math.min(y0, b.ys[0]); y1 = Math.max(y1, b.ys[2]);
        }
        return x0 === Infinity ? ({}) : { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
    }
    // Element pod punktem płótna (od wierzchu) — np. do upuszczenia zdjęcia w ramkę
    function elementAt(sx, sy) {
        const p = mapToItem(page, sx, sy);
        const px = p.x / zoom, py = p.y / zoom;
        const all = project.document().elements;
        for (let i = all.length - 1; i >= 0; --i) {
            const o = all[i];
            if (o.hidden) continue;
            const r = -(o.rotation || 0) * Math.PI / 180;
            const cx = o.x + o.w / 2, cy = o.y + o.h / 2;
            const lx = (px - cx) * Math.cos(r) - (py - cy) * Math.sin(r), ly = (px - cx) * Math.sin(r) + (py - cy) * Math.cos(r);
            if (Math.abs(lx) <= o.w / 2 && Math.abs(ly) <= o.h / 2) return o;
        }
        return null;
    }

    // ——— Ramka zaznaczania (p — punkt strony w pikselach ekranu) ———
    function marqueeBegin(p, additive) {
        stopEditing();
        cropping = "";
        marqueeBase = additive ? selection.slice() : [];
        if (!additive) setSelection([]);
        marquee = Qt.rect(p.x / zoom, p.y / zoom, 0, 0);
        marqueeStart = Qt.point(p.x / zoom, p.y / zoom);
        marqueeOn = true;
        forceActiveFocus();
    }
    property point marqueeStart
    function marqueeMove(p) {
        if (!marqueeOn) return;
        const x = p.x / zoom, y = p.y / zoom;
        marquee = Qt.rect(Math.min(x, marqueeStart.x), Math.min(y, marqueeStart.y), Math.abs(x - marqueeStart.x), Math.abs(y - marqueeStart.y));
        if (marquee.width * zoom < 4 && marquee.height * zoom < 4) return;
        const list = marqueeBase.slice();
        for (const o of project.document().elements) {
            if (o.hidden || o.locked || list.indexOf(o.id) >= 0) continue;
            const b = box(o, o.x, o.y);
            if (b.xs[2] >= marquee.x && b.xs[0] <= marquee.x + marquee.width && b.ys[2] >= marquee.y && b.ys[0] <= marquee.y + marquee.height)
                list.push(o.id);
        }
        setSelection(list);
    }
    function marqueeEnd() { marqueeOn = false; }
    Connections {
        target: stage.project
        function onDataChanged() { stage.refresh(); }
        function onReset() { stage.editing = ""; stage.refresh(); }
        function onRowsRemoved() { stage.refresh(); }
        function onCountChanged() { stage.refresh(); }
    }

    function select(id) {
        if (editing !== "" && editing !== id) stopEditing();
        if (cropping !== "" && cropping !== id) cropping = "";
        setSelection(id !== "" ? [id] : []);
    }
    function zoomBy(f) {
        userZoom = Math.max(0.05, Math.min(8, zoom * f));
        fit = false;
    }
    function zoomTo(v) { userZoom = v; fit = false; }

    // ——— Edycja tekstu w miejscu ———
    function startEditing(id) {
        const el = project.get(id);
        if (el.type !== "text") return;
        selected = id;
        editing = id;
        editor.text = el.text;
        editor.forceActiveFocus();
        editor.selectAll();
    }
    function stopEditing() {
        if (editing === "") return;
        const id = editing;
        editing = "";
        if (editor.text.trim() === "") project.remove(id);
        else project.commit();
        stage.forceActiveFocus();
    }

    // ——— Przyciąganie ———
    function box(el, x, y) {
        const r = (el.rotation || 0) * Math.PI / 180;
        const aw = Math.abs(el.w * Math.cos(r)) + Math.abs(el.h * Math.sin(r));
        const ah = Math.abs(el.w * Math.sin(r)) + Math.abs(el.h * Math.cos(r));
        const cx = x + el.w / 2, cy = y + el.h / 2;
        return { xs: [cx - aw / 2, cx, cx + aw / 2], ys: [cy - ah / 2, cy, cy + ah / 2] };
    }
    // ——— Prowadnice ———
    property var dragGuide: null                // przeciągana: { axis, index (−1 — nowa z linijki), v }
    readonly property real unitsPerPx: project.print.width ? project.print.width / project.pageWidth : 1   // mm albo px
    readonly property string unit: project.print.width ? "mm" : "px"
    function moveGuide(axis, index, v) {
        const t = nearest([v], axis === "x" ? snapX : snapY);
        if (t) v = t.t;
        v = Math.round(v * 10) / 10;
        dragGuide = { axis: axis, index: index, v: v };
        const size = axis === "x" ? project.pageWidth : project.pageHeight;
        hint = v < 0 || v > size ? "Puść, żeby usunąć prowadnicę"
             : (axis === "x" ? "X " : "Y ") + Math.round(v * unitsPerPx * 10) / 10 + " " + unit;
    }
    function dropGuide() {
        const g = dragGuide;
        dragGuide = null;
        hint = "";
        if (!g) return;
        const size = g.axis === "x" ? project.pageWidth : project.pageHeight;
        const all = { x: (project.guides.x || []).slice(), y: (project.guides.y || []).slice() };
        if (g.index >= 0) all[g.axis].splice(g.index, 1);
        if (g.v >= 0 && g.v <= size) all[g.axis].push(g.v);
        project.setGuides(all);
    }
    function addGuides(kind) {
        const W = project.pageWidth, H = project.pageHeight, m = Math.round(Math.min(W, H) * 0.05);
        const all = { x: (project.guides.x || []).slice(), y: (project.guides.y || []).slice() };
        const put = (axis, v) => { if (all[axis].every(o => Math.abs(o - v) > 0.5)) all[axis].push(v); };
        if (kind === "center") { put("x", W / 2); put("y", H / 2); }
        else if (kind === "margins") { put("x", m); put("x", W - m); put("y", m); put("y", H - m); }
        else if (kind === "thirds") { put("x", Math.round(W / 3)); put("x", Math.round(W * 2 / 3)); put("y", Math.round(H / 3)); put("y", Math.round(H * 2 / 3)); }
        rulers = true;
        project.setGuides(all);
    }

    function prepareSnap(ids, noGuides) {
        const W = project.pageWidth, H = project.pageHeight;
        const xs = [0, W / 2, W], ys = [0, H / 2, H];
        const rects = [];
        const all = project.document().elements;
        for (const o of all) {
            if (ids.indexOf(o.id) >= 0 || o.hidden) continue;
            const b = box(o, o.x, o.y);
            xs.push(...b.xs);
            ys.push(...b.ys);
            rects.push(rectOf(b));
        }
        if (rulers && !noGuides) {
            xs.push(...(project.guides.x || []));
            ys.push(...(project.guides.y || []));
        }
        snapX = xs;
        snapY = ys;
        snapRects = rects;
    }
    function nearest(edges, targets) {
        const thr = 7 / zoom;
        let best = null;
        for (const e of edges)
            for (const t of targets)
                if (Math.abs(t - e) < thr && (best === null || Math.abs(t - e) < Math.abs(best.d)))
                    best = { d: t - e, t: t };
        return best;
    }
    function rectOf(b) { return { x: b.xs[0], y: b.ys[0], w: b.xs[2] - b.xs[0], h: b.ys[2] - b.ys[0] }; }

    // Równe odstępy w osi "x" albo "y": przesuwany prostokąt m ustawia się tak, żeby odstępy od sąsiadów
    // były równe albo takie jak między dwoma innymi elementami w tym samym rzędzie. Zwraca { d, gaps } albo null.
    function spacing(m, axis) {
        const X = axis, Y = axis === "x" ? "y" : "x", W = axis === "x" ? "w" : "h", H = axis === "x" ? "h" : "w";
        const thr = 7 / zoom;
        const band = snapRects.filter(r => r[Y] < m[Y] + m[H] && r[Y] + r[H] > m[Y]);
        if (band.length === 0) return null;
        const end = r => r[X] + r[W];
        const L = band.filter(r => end(r) <= m[X] + thr && r[X] < m[X]).sort((a, b) => end(b) - end(a))[0];
        const R = band.filter(r => r[X] >= end(m) - thr && end(r) > end(m)).sort((a, b) => a[X] - b[X])[0];
        const gap = (a, b) => {
            const lo = Math.max(a[Y], b[Y]), hi = Math.min(a[Y] + a[H], b[Y] + b[H]);
            return { axis: axis, s: end(a), e: b[X], c: lo < hi ? (lo + hi) / 2 : b[Y] + b[H] / 2 };
        };
        const cands = [];
        if (L && R) {
            const g = (R[X] - end(L) - m[W]) / 2;
            if (g > 1) cands.push({ p: end(L) + g, l: true, r: true, pairs: [] });
        }
        // Odstępy między innymi elementami w tym rzędzie
        for (const a of band) {
            const b = band.filter(r => r[X] >= end(a) - 0.5).sort((p, q) => p[X] - q[X])[0];
            if (!b) continue;
            const g = b[X] - end(a);
            if (g < 1) continue;
            if (L && L !== a) cands.push({ p: end(L) + g, l: true, pairs: [[a, b]] });
            if (R && R !== b) cands.push({ p: R[X] - g - m[W], r: true, pairs: [[a, b]] });
        }
        let best = null;
        for (const c of cands)
            if (Math.abs(c.p - m[X]) < thr && (best === null || Math.abs(c.p - m[X]) < Math.abs(best.p - m[X]))) best = c;
        if (!best) return null;
        const at = Object.assign({}, m);
        at[X] = best.p;
        const gaps = [];
        if (best.l) gaps.push(gap(L, at));
        if (best.r) gaps.push(gap(at, R));
        for (const [a, b] of best.pairs) gaps.push(gap(a, b));
        return { d: best.p - m[X], gaps: gaps };
    }
    // Przyciąganie prostokątu m (krawędzie, środek, linie, równe odstępy); zwraca przesunięcie
    function snapRect(m) {
        let sx = nearest([m.x, m.x + m.w / 2, m.x + m.w], snapX), sy = nearest([m.y, m.y + m.h / 2, m.y + m.h], snapY);
        const px = spacing(m, "x");
        if (px && (!sx || Math.abs(px.d) <= Math.abs(sx.d))) sx = { d: px.d, t: null };
        const moved = Object.assign({}, m, { x: m.x + (sx ? sx.d : 0) });
        const py = spacing(moved, "y");
        if (py && (!sy || Math.abs(py.d) <= Math.abs(sy.d))) sy = { d: py.d, t: null };
        const done = Object.assign({}, moved, { y: m.y + (sy ? sy.d : 0) });
        guidesX = sx && sx.t !== null ? [sx.t] : [];
        guidesY = sy && sy.t !== null ? [sy.t] : [];
        const gx = sx && sx.t === null ? spacing(done, "x") : null, gy = sy && sy.t === null ? spacing(done, "y") : null;
        gaps = (gx ? gx.gaps : []).concat(gy ? gy.gaps : []);
        return { dx: sx ? sx.d : 0, dy: sy ? sy.d : 0 };
    }
    // Przesuwanie kilku elementów: przyciąga prostokąt całej grupy (g — prostokąt na początku)
    function snapGroup(g, dx, dy) {
        const s = snapRect({ x: g.x + dx, y: g.y + dy, w: g.w, h: g.h });
        return { dx: dx + s.dx, dy: dy + s.dy };
    }
    function endSnap() {
        guidesX = [];
        guidesY = [];
        gaps = [];
    }
    // Zmiana rozmiaru: przesuwana krawędź przyciąga się do linii (tylko bez obrotu)
    function snapResize(g, s, hx, hy, keep, text) {
        let sx = null, sy = null;
        if (hx === 1) { sx = nearest([g.x + g.w], snapX); if (sx) g.w += sx.d; }
        if (hx === -1) { sx = nearest([g.x], snapX); if (sx) { g.x += sx.d; g.w -= sx.d; } }
        if (!text && hy === 1 && !(keep && sx)) { sy = nearest([g.y + g.h], snapY); if (sy) g.h += sy.d; }
        if (!text && hy === -1 && !(keep && sx)) { sy = nearest([g.y], snapY); if (sy) { g.y += sy.d; g.h -= sy.d; } }
        if (keep && hx && hy && !text) {
            // Proporcje zostają: druga krawędź idzie za przyciągniętą
            if (sx) { g.h = g.w * s.h / s.w; if (hy === -1) g.y = s.y + s.h - g.h; }
            else if (sy) { g.w = g.h * s.w / s.h; if (hx === -1) g.x = s.x + s.w - g.w; }
        }
        guidesX = sx ? [sx.t] : [];
        guidesY = sy ? [sy.t] : [];
        return g;
    }
    function snapMove(el, x, y) {
        const s = snapRect(rectOf(box(el, x, y)));
        return { x: Math.round((x + s.dx) * 10) / 10, y: Math.round((y + s.dy) * 10) / 10 };
    }

    // Zmiana rozmiaru uchwytem (hx, hy ∈ −1, 0, 1) w układzie obróconego elementu; przeciwległy róg stoi w miejscu
    function resized(s, hx, hy, dx, dy, keep) {
        const r = (s.rotation || 0) * Math.PI / 180, cos = Math.cos(r), sin = Math.sin(r);
        const lx = dx * cos + dy * sin, ly = -dx * sin + dy * cos;
        let w = s.w + hx * lx, h = s.h + hy * ly;
        if (keep && hx && hy) {
            const k = Math.max(0.03, 1 + (hx * lx * s.w + hy * ly * s.h) / (s.w * s.w + s.h * s.h));
            w = s.w * k;
            h = s.h * k;
        }
        if (!hx) w = s.w;
        if (!hy) h = s.h;
        w = Math.max(8, w);
        h = Math.max(8, h);
        const shx = hx * (w - s.w) / 2, shy = hy * (h - s.h) / 2;
        const cx = s.x + s.w / 2 + shx * cos - shy * sin, cy = s.y + s.h / 2 + shx * sin + shy * cos;
        return { x: cx - w / 2, y: cy - h / 2, w: w, h: h };
    }

    // Kadrowanie: przeciąganie przesuwa zdjęcie w ramce (focusX/focusY — który fragment widać)
    function dragCrop(el, dx, dy) {
        const img = project.imageSize(el.src);
        if (img.width <= 0) return;
        const k = Math.max(el.w / img.width, el.h / img.height) * Math.max(1, el.zoom || 1);
        const ox = img.width * k - el.w, oy = img.height * k - el.h;
        const r = (el.rotation || 0) * Math.PI / 180;
        let lx = dx * Math.cos(r) + dy * Math.sin(r);
        const ly = -dx * Math.sin(r) + dy * Math.cos(r);
        if (el.flipX) lx = -lx;
        const fx0 = el.focusX === undefined ? 0.5 : el.focusX, fy0 = el.focusY === undefined ? 0.5 : el.focusY;
        const patch = {};
        if (ox > 0.5) patch.focusX = Math.round(Math.max(0, Math.min(1, fx0 - lx / ox)) * 1000) / 1000;
        if (oy > 0.5) patch.focusY = Math.round(Math.max(0, Math.min(1, fy0 - ly / oy)) * 1000) / 1000;
        project.change(el.id, patch, false);
    }

    WheelHandler {
        acceptedModifiers: Qt.ControlModifier
        onWheel: (e) => stage.zoomBy(e.angleDelta.y > 0 ? 1.1 : 1 / 1.1)
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.leftMargin: stage.ruler
        anchors.topMargin: stage.ruler
        contentWidth: Math.max(width, page.width + 96)
        contentHeight: Math.max(height, page.height + 96)
        boundsBehavior: Flickable.StopAtBounds
        interactive: false
        // Środek strony zostaje na miejscu przy powiększaniu
        onContentWidthChanged: contentX = Math.max(0, (contentWidth - width) / 2)
        onContentHeightChanged: contentY = Math.max(0, (contentHeight - height) / 2)

        WheelHandler {
            acceptedModifiers: Qt.NoModifier
            onWheel: (e) => {
                flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY - e.angleDelta.y));
                flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - e.angleDelta.x));
            }
        }

        // Kliknięcie obok strony zdejmuje zaznaczenie, przeciągnięcie — ramka zaznaczania
        MouseArea {
            width: flick.contentWidth; height: flick.contentHeight
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: (e) => stage.marqueeBegin(mapToItem(page, e.x, e.y), e.modifiers & Qt.ShiftModifier)
            onPositionChanged: (e) => stage.marqueeMove(mapToItem(page, e.x, e.y))
            onReleased: stage.marqueeEnd()
        }

        Item {
            id: page
            x: Math.round((flick.contentWidth - width) / 2)
            y: Math.round((flick.contentHeight - height) / 2)
            width: stage.project.pageWidth * stage.zoom
            height: stage.project.pageHeight * stage.zoom

            RectangularShadow {
                anchors.fill: parent
                visible: GraphicsInfo.api !== GraphicsInfo.Software
                blur: 24; offset.y: 6
                color: Qt.rgba(0, 0, 0, Theme.dark ? 0.5 : 0.18)
            }
            Rectangle {
                anchors.fill: parent; anchors.margins: -1
                color: "transparent"
                border.width: 1; border.color: Theme.line
            }

            ArtView {
                anchors.fill: parent
                project: stage.project
                element: Object.assign({ kind: "background", w: stage.project.pageWidth, h: stage.project.pageHeight }, stage.project.background)
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: (e) => {
                        if (e.button === Qt.RightButton) {
                            stage.clearSelection();
                            stage.forceActiveFocus();
                            const p = mapToItem(stage, e.x, e.y);
                            stage.menuRequested(p.x, p.y);
                            return;
                        }
                        stage.marqueeBegin(mapToItem(page, e.x, e.y), e.modifiers & Qt.ShiftModifier);
                    }
                    onPositionChanged: (e) => stage.marqueeMove(mapToItem(page, e.x, e.y))
                    onReleased: stage.marqueeEnd()
                }
            }

            Item {
                id: layer
                anchors.fill: parent
                clip: true
                Repeater {
                    model: stage.project
                    delegate: Item {
                        id: d
                        required property var element
                        readonly property string uid: element.id
                        readonly property bool cropping: stage.cropping === uid
                        visible: !element.hidden
                        x: element.x * stage.zoom
                        y: element.y * stage.zoom
                        width: element.w * stage.zoom
                        height: element.h * stage.zoom
                        rotation: element.rotation || 0
                        opacity: element.opacity === undefined ? 1 : element.opacity
                        z: cropping ? 1 : 0

                        // Kadrowanie: całe zdjęcie przygaszone pod ramką, żeby było widać, co zostaje poza nią
                        ArtView {
                            id: ghost
                            readonly property size img: d.cropping ? stage.project.imageSize(d.element.src) : Qt.size(0, 0)
                            readonly property real k: img.width > 0 ? Math.max(d.element.w / img.width, d.element.h / img.height) * Math.max(1, d.element.zoom || 1) : 1
                            readonly property real fx: d.element.focusX === undefined ? 0.5 : d.element.focusX
                            readonly property real fy: d.element.focusY === undefined ? 0.5 : d.element.focusY
                            visible: d.cropping && img.width > 0
                            opacity: 0.35
                            x: -(img.width * k - d.element.w) * (d.element.flipX ? 1 - fx : fx) * stage.zoom
                            y: -(img.height * k - d.element.h) * fy * stage.zoom
                            width: img.width * k * stage.zoom
                            height: img.height * k * stage.zoom
                            project: stage.project
                            element: visible ? Object.assign({}, d.element, { w: img.width * k, h: img.height * k, zoom: 1, mask: null, radius: 0, focusX: 0.5, focusY: 0.5 }) : ({})
                        }
                        ArtView {
                            anchors.fill: parent
                            anchors.margins: -bleed * stage.zoom       // miękki cień wystaje poza pole
                            project: stage.project
                            element: d.element
                            visible: stage.editing !== d.uid
                        }
                        // Obwódka każdego z kilku zaznaczonych
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -1
                            visible: stage.selection.length > 1 && stage.selection.indexOf(d.uid) >= 0
                            color: "transparent"
                            border.width: 1.5
                            border.color: Theme.accent
                        }
                        WheelHandler {
                            enabled: d.cropping
                            onWheel: (e) => {
                                const z = Math.max(1, Math.min(5, (d.element.zoom || 1) * (e.angleDelta.y > 0 ? 1.08 : 1 / 1.08)));
                                stage.project.change(d.uid, { zoom: Math.round(z * 100) / 100 }, false);
                                stage.hint = "Powiększenie " + Math.round(z * 100) + "%";
                                cropCommit.restart();
                            }
                        }
                        Timer { id: cropCommit; interval: 500; onTriggered: { stage.hint = ""; stage.project.commit(); } }
                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            anchors.margins: d.element.type === "shape" && (d.element.shape === "line" || d.element.shape === "arrow" || d.element.shape === "doubleArrow") ? -4 : 0
                            enabled: stage.editing !== d.uid
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: d.cropping ? Qt.OpenHandCursor : d.element.locked ? Qt.ArrowCursor
                                       : stage.selection.indexOf(d.uid) >= 0 ? Qt.SizeAllCursor : Qt.PointingHandCursor
                            property point start
                            property var starts: []         // przesuwane elementy: { id, x, y }
                            property var startGroup
                            property var startEl
                            property bool moved: false
                            property bool pickOne: false            // puszczenie bez ruchu — sam ten element z grupy
                            onPressed: (e) => {
                                pickOne = false;
                                stage.forceActiveFocus();
                                moved = false;
                                starts = [];
                                start = mapToItem(page, e.x, e.y);
                                startEl = d.element;
                                if (e.button === Qt.LeftButton && (e.modifiers & Qt.ShiftModifier)) {
                                    stage.toggle(d.uid);
                                    return;
                                }
                                const g = d.element.group;
                                if (!stage.isSelected(d.uid)) stage.selectWithGroup(d.uid);
                                else if (g && stage.selection.length > 1 && stage.selection.every(id => stage.project.get(id).group === g)) pickOne = true;
                                if (e.button === Qt.RightButton) {
                                    const p = mapToItem(stage, e.x, e.y);
                                    stage.menuRequested(p.x, p.y);
                                    return;
                                }
                                if (d.cropping) return;
                                const ids = stage.selection.length > 1 ? stage.selection : [d.uid];
                                for (const id of ids) {
                                    const o = stage.project.get(id);
                                    if (!o.locked) starts.push({ id: id, x: o.x, y: o.y });
                                }
                                startGroup = stage.bounds(starts.map(o => o.id));
                                stage.prepareSnap(ids);
                            }
                            onPositionChanged: (e) => {
                                if (!pressed || !(pressedButtons & Qt.LeftButton)) return;
                                const p = mapToItem(page, e.x, e.y);
                                const dx = (p.x - start.x) / stage.zoom, dy = (p.y - start.y) / stage.zoom;
                                if (!moved && Math.hypot(p.x - start.x, p.y - start.y) < 3) return;
                                if (d.cropping) {
                                    moved = true;
                                    stage.dragCrop(startEl, dx, dy);
                                    return;
                                }
                                if (starts.length === 0) return;
                                moved = true;
                                stage.dragging = true;
                                if (starts.length === 1) {
                                    const s = stage.snapMove(d.element, starts[0].x + dx, starts[0].y + dy);
                                    stage.project.change(starts[0].id, { x: s.x, y: s.y }, false);
                                } else {
                                    const g = stage.snapGroup(startGroup, dx, dy);
                                    for (const o of starts)
                                        stage.project.change(o.id, { x: Math.round((o.x + g.dx) * 10) / 10, y: Math.round((o.y + g.dy) * 10) / 10 }, false);
                                }
                            }
                            onReleased: {
                                stage.endSnap();
                                stage.dragging = false;
                                if (moved) stage.project.commit();
                                else if (pickOne) stage.select(d.uid);
                            }
                            onDoubleClicked: {
                                if (d.element.locked) return;
                                if (d.element.type === "text") stage.startEditing(d.uid);
                                else if (d.element.type === "image") stage.cropping = d.cropping ? "" : d.uid;
                            }
                        }
                    }
                }
            }

            // Własne prowadnice — przeciągnij, żeby przesunąć; poza stronę — usuwa
            Repeater {
                model: stage.rulers ? (stage.project.guides.x || []) : []
                delegate: Rectangle {
                    id: vg
                    required property real modelData
                    required property int index
                    readonly property bool dragged: stage.dragGuide !== null && stage.dragGuide.axis === "x" && stage.dragGuide.index === index
                    x: (dragged ? stage.dragGuide.v : modelData) * stage.zoom - 0.5
                    y: -page.y
                    width: 1; height: flick.contentHeight
                    color: "#00A3E0"
                    MouseArea {
                        anchors.fill: parent; anchors.leftMargin: -3; anchors.rightMargin: -3
                        cursorShape: Qt.SplitHCursor
                        onPressed: { stage.prepareSnap([], true); stage.moveGuide("x", vg.index, vg.modelData); }
                        onPositionChanged: (e) => { if (pressed) stage.moveGuide("x", vg.index, mapToItem(page, e.x, e.y).x / stage.zoom); }
                        onReleased: stage.dropGuide()
                    }
                }
            }
            Repeater {
                model: stage.rulers ? (stage.project.guides.y || []) : []
                delegate: Rectangle {
                    id: hg
                    required property real modelData
                    required property int index
                    readonly property bool dragged: stage.dragGuide !== null && stage.dragGuide.axis === "y" && stage.dragGuide.index === index
                    y: (dragged ? stage.dragGuide.v : modelData) * stage.zoom - 0.5
                    x: -page.x
                    height: 1; width: flick.contentWidth
                    color: "#00A3E0"
                    MouseArea {
                        anchors.fill: parent; anchors.topMargin: -3; anchors.bottomMargin: -3
                        cursorShape: Qt.SplitVCursor
                        onPressed: { stage.prepareSnap([], true); stage.moveGuide("y", hg.index, hg.modelData); }
                        onPositionChanged: (e) => { if (pressed) stage.moveGuide("y", hg.index, mapToItem(page, e.x, e.y).y / stage.zoom); }
                        onReleased: stage.dropGuide()
                    }
                }
            }
            // Nowa prowadnica wyciągana z linijki
            Rectangle {
                readonly property bool hor: stage.dragGuide !== null && stage.dragGuide.axis === "y"
                visible: stage.dragGuide !== null && stage.dragGuide.index < 0
                x: hor ? -page.x : (stage.dragGuide ? stage.dragGuide.v : 0) * stage.zoom - 0.5
                y: hor ? (stage.dragGuide ? stage.dragGuide.v : 0) * stage.zoom - 0.5 : -page.y
                width: hor ? flick.contentWidth : 1
                height: hor ? 1 : flick.contentHeight
                color: "#00A3E0"
            }

            // Ramka zaznaczania
            Rectangle {
                visible: stage.marqueeOn && (stage.marquee.width > 0 || stage.marquee.height > 0)
                x: stage.marquee.x * stage.zoom
                y: stage.marquee.y * stage.zoom
                width: stage.marquee.width * stage.zoom
                height: stage.marquee.height * stage.zoom
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                border.width: 1
                border.color: Theme.accent
            }
            // Prostokąt kilku zaznaczonych — narożniki zmieniają rozmiar wszystkich naraz (proporcjonalnie)
            Rectangle {
                id: groupBox
                visible: stage.selection.length > 1 && stage.group.w !== undefined
                x: (stage.group.x || 0) * stage.zoom - 4
                y: (stage.group.y || 0) * stage.zoom - 4
                width: (stage.group.w || 0) * stage.zoom + 8
                height: (stage.group.h || 0) * stage.zoom + 8
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
                radius: 3
                Repeater {
                    model: [{ hx: -1, hy: -1 }, { hx: 1, hy: -1 }, { hx: -1, hy: 1 }, { hx: 1, hy: 1 }]
                    delegate: Rectangle {
                        id: gh
                        required property var modelData
                        width: 12; height: 12; radius: 6
                        x: (modelData.hx + 1) / 2 * groupBox.width - 6
                        y: (modelData.hy + 1) / 2 * groupBox.height - 6
                        color: "white"
                        border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.25)
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            cursorShape: gh.modelData.hx === gh.modelData.hy ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                            property var starts: []
                            property point opp
                            property point corner
                            onPressed: (e) => {
                                const g = stage.group;
                                opp = Qt.point(gh.modelData.hx < 0 ? g.x + g.w : g.x, gh.modelData.hy < 0 ? g.y + g.h : g.y);
                                corner = Qt.point(gh.modelData.hx < 0 ? g.x : g.x + g.w, gh.modelData.hy < 0 ? g.y : g.y + g.h);
                                starts = stage.selection.map(id => stage.project.get(id)).filter(o => !o.locked);
                            }
                            onPositionChanged: (e) => {
                                if (!pressed) return;
                                const p = mapToItem(page, e.x, e.y);
                                const px = p.x / stage.zoom, py = p.y / stage.zoom;
                                const vx = corner.x - opp.x, vy = corner.y - opp.y;
                                const k = Math.max(0.05, ((px - opp.x) * vx + (py - opp.y) * vy) / (vx * vx + vy * vy));
                                for (const o of starts) stage.project.change(o.id, stage.project.scaled(o, k, opp.x, opp.y), false);
                                stage.hint = Math.round(k * 100) + "%";
                            }
                            onReleased: { stage.hint = ""; stage.project.commit(); }
                        }
                    }
                }
            }

            // Linie pomocnicze
            Repeater {
                model: stage.guidesX
                delegate: Rectangle {
                    required property real modelData
                    x: modelData * stage.zoom - 0.5; y: -12
                    width: 1; height: page.height + 24
                    color: "#FF3D9A"
                }
            }
            Repeater {
                model: stage.guidesY
                delegate: Rectangle {
                    required property real modelData
                    y: modelData * stage.zoom - 0.5; x: -12
                    height: 1; width: page.width + 24
                    color: "#FF3D9A"
                }
            }

            // Równe odstępy — odcinki z odległością
            Repeater {
                model: stage.gaps
                delegate: Item {
                    id: gp
                    required property var modelData
                    readonly property bool hor: modelData.axis === "x"
                    readonly property real len: (modelData.e - modelData.s) * stage.zoom
                    x: (hor ? modelData.s : modelData.c) * stage.zoom
                    y: (hor ? modelData.c : modelData.s) * stage.zoom
                    Rectangle { width: gp.hor ? gp.len : 1; height: gp.hor ? 1 : gp.len; color: "#FF3D9A" }
                    Rectangle { x: gp.hor ? 0 : -4; y: gp.hor ? -4 : 0; width: gp.hor ? 1 : 9; height: gp.hor ? 9 : 1; color: "#FF3D9A" }
                    Rectangle {
                        x: gp.hor ? gp.len - 1 : -4; y: gp.hor ? -4 : gp.len - 1
                        width: gp.hor ? 1 : 9; height: gp.hor ? 9 : 1; color: "#FF3D9A"
                    }
                    Rectangle {
                        x: gp.hor ? (gp.len - width) / 2 : 10
                        y: gp.hor ? 10 : (gp.len - height) / 2
                        width: gapText.implicitWidth + 8; height: 16; radius: 4
                        color: "#FF3D9A"
                        Text {
                            id: gapText
                            anchors.centerIn: parent
                            text: Math.round((gp.modelData.e - gp.modelData.s) * stage.unitsPerPx * 10) / 10
                            color: "white"
                            font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; font.features: { "tnum": 1 }
                        }
                    }
                }
            }

            // ——— Zaznaczenie ———
            Item {
                id: sel
                readonly property var el: stage.current
                readonly property bool line: el.type === "shape" && (el.shape === "line" || el.shape === "arrow" || el.shape === "doubleArrow")
                readonly property bool fixed: !!el.locked || stage.cropping !== "" || stage.magicOn     // bez uchwytów
                visible: stage.selected !== "" && el.id !== undefined && !el.hidden
                x: (el.x || 0) * stage.zoom
                y: (el.y || 0) * stage.zoom
                width: (el.w || 0) * stage.zoom
                height: (el.h || 0) * stage.zoom
                rotation: el.rotation || 0

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -1
                    color: "transparent"
                    border.width: 1.5
                    border.color: Theme.accent
                    visible: !sel.line || stage.editing !== ""
                }

                // Zablokowany — kłódka zamiast uchwytów
                Rectangle {
                    visible: !!sel.el.locked
                    x: sel.width - width / 2; y: -height / 2
                    width: 24; height: 24; radius: 12
                    color: "white"
                    border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.2)
                    Icon { anchors.centerIn: parent; d: Icons.lock; size: 13; stroke: 2; color: "#16181D" }
                }

                Repeater {
                    model: stage.editing !== "" || sel.fixed ? []
                         : sel.line ? [{ hx: -1, hy: 0 }, { hx: 1, hy: 0 }]
                         : sel.el.type === "text" ? [{ hx: -1, hy: 0 }, { hx: 1, hy: 0 }, { hx: -1, hy: -1 }, { hx: 1, hy: -1 }, { hx: -1, hy: 1 }, { hx: 1, hy: 1 }]
                         : [{ hx: -1, hy: -1 }, { hx: 0, hy: -1 }, { hx: 1, hy: -1 }, { hx: -1, hy: 0 }, { hx: 1, hy: 0 }, { hx: -1, hy: 1 }, { hx: 0, hy: 1 }, { hx: 1, hy: 1 }]
                    delegate: Rectangle {
                        id: handle
                        required property var modelData
                        readonly property bool side: modelData.hx === 0 || modelData.hy === 0
                        readonly property bool tooSmall: side && (modelData.hx === 0 ? sel.width < 40 : sel.height < 40) && !sel.line
                        visible: !tooSmall
                        width: side && !sel.line ? (modelData.hx === 0 ? 18 : 6) : 12
                        height: side && !sel.line ? (modelData.hy === 0 ? 18 : 6) : 12
                        radius: side ? 3 : 6
                        x: (modelData.hx + 1) / 2 * sel.width - width / 2
                        y: (modelData.hy + 1) / 2 * sel.height - height / 2
                        color: "white"
                        border.width: 1
                        border.color: Qt.rgba(0, 0, 0, 0.25)
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            cursorShape: handle.modelData.hx === 0 ? Qt.SizeVerCursor : handle.modelData.hy === 0 ? Qt.SizeHorCursor
                                       : handle.modelData.hx === handle.modelData.hy ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                            property point start
                            property var s
                            onPressed: (e) => { start = mapToItem(page, e.x, e.y); s = stage.current; stage.prepareSnap([s.id]); }
                            onPositionChanged: (e) => {
                                if (!pressed) return;
                                const p = mapToItem(page, e.x, e.y);
                                const t = s.type;
                                const keep = (t === "image" || t === "text" || t === "vector" || (t === "code" && s.kind === "qr")) !== !!(e.modifiers & Qt.ShiftModifier);
                                let g = stage.resized(s, handle.modelData.hx, handle.modelData.hy, (p.x - start.x) / stage.zoom, (p.y - start.y) / stage.zoom, keep);
                                if (!(s.rotation) && !sel.line) g = stage.snapResize(g, s, handle.modelData.hx, handle.modelData.hy, keep, t === "text" && handle.modelData.hy !== 0);
                                const patch = { x: Math.round(g.x * 10) / 10, y: Math.round(g.y * 10) / 10, w: Math.round(g.w * 10) / 10 };
                                if (t === "text") {
                                    if (handle.modelData.hy !== 0) patch.size = Math.max(4, Math.round(s.size * g.w / s.w));
                                } else {
                                    patch.h = Math.round(g.h * 10) / 10;
                                }
                                stage.hint = Math.round(g.w) + " × " + Math.round(t === "text" ? stage.current.h : g.h);
                                stage.project.change(s.id, patch, false);
                            }
                            onReleased: { stage.hint = ""; stage.guidesX = []; stage.guidesY = []; stage.project.commit(); }
                        }
                    }
                }

                // Uchwyt obrotu pod elementem
                Rectangle {
                    visible: stage.editing === "" && !sel.fixed
                    x: sel.width / 2 - width / 2
                    y: sel.height + 18
                    width: 26; height: 26; radius: 13
                    color: "white"
                    border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.2)
                    Icon { anchors.centerIn: parent; d: Icons.rotate; size: 14; stroke: 2; color: "#16181D" }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.CrossCursor
                        onPositionChanged: (e) => {
                            if (!pressed) return;
                            const c = sel.mapToItem(page, sel.width / 2, sel.height / 2);
                            const p = mapToItem(page, e.x, e.y);
                            let a = Math.atan2(p.y - c.y, p.x - c.x) * 180 / Math.PI - 90;
                            const stepped = Math.round(a / 15) * 15;
                            if (e.modifiers & Qt.ShiftModifier || Math.abs(stepped - a) < 3) a = stepped;
                            a = ((a % 360) + 540) % 360 - 180;
                            stage.hint = Math.round(a) + "°";
                            stage.project.change(stage.selected, { rotation: Math.round(a * 10) / 10 }, false);
                        }
                        onReleased: { stage.hint = ""; stage.project.commit(); }
                    }
                }
            }

            // ——— Edycja tekstu ———
            Item {
                id: editBox
                readonly property var el: stage.current
                visible: stage.editing !== ""
                x: (el.x || 0) * stage.zoom
                y: (el.y || 0) * stage.zoom
                width: (el.w || 0) * stage.zoom
                height: (el.h || 0) * stage.zoom
                rotation: el.rotation || 0
                opacity: el.opacity === undefined ? 1 : el.opacity
                TextEdit {
                    id: editor
                    width: editBox.el.w || 10
                    scale: stage.zoom
                    transformOrigin: Item.TopLeft
                    wrapMode: TextEdit.Wrap
                    color: editBox.el.color || "black"
                    selectionColor: Theme.accent
                    selectedTextColor: "white"
                    horizontalAlignment: editBox.el.align === "center" ? TextEdit.AlignHCenter : editBox.el.align === "right" ? TextEdit.AlignRight : TextEdit.AlignLeft
                    font.family: editBox.el.font || "Geist"
                    font.pixelSize: Math.max(1, Math.round(editBox.el.size || 48))
                    font.weight: editBox.el.weight || 400
                    font.variableAxes: ({ "wght": editBox.el.weight || 400 })
                    font.italic: !!editBox.el.italic
                    font.underline: !!editBox.el.underline
                    font.letterSpacing: (editBox.el.spacing || 0) * (editBox.el.size || 48)
                    font.capitalization: editBox.el.caps ? Font.AllUppercase : Font.MixedCase
                    font.hintingPreference: Font.PreferNoHinting
                    onTextChanged: if (stage.editing !== "" && activeFocus) stage.project.change(stage.editing, { text: text }, false)
                    Keys.onEscapePressed: stage.stopEditing()
                    onActiveFocusChanged: if (!activeFocus && stage.editing !== "") stage.stopEditing()
                }
            }

            // ——— Pasek szybkich działań nad zaznaczeniem ———
            Rectangle {
                id: quickBar
                readonly property var b: { stage.current; stage.group; return stage.selection.length > 0 ? stage.bounds(stage.selection) : ({}); }
                readonly property var el: stage.current
                readonly property bool single: stage.selection.length === 1
                visible: b.w !== undefined && stage.editing === "" && stage.cropping === "" && !stage.magicOn && !stage.dragging
                         && stage.hint === "" && !stage.marqueeOn && !(single && el.locked) && stage.dragGuide === null
                // Nad zaznaczeniem, a gdy brak miejsca (góra okna) — pod nim, za uchwytem obrotu
                readonly property real above: (b.y || 0) * stage.zoom - height - 14
                readonly property real roof: flick.contentY - page.y + 6
                x: Math.max(flick.contentX - page.x + 6, Math.min(flick.contentX - page.x + flick.width - width - 6,
                                                                   ((b.x || 0) + (b.w || 0) / 2) * stage.zoom - width / 2))
                y: above >= roof ? above : ((b.y || 0) + (b.h || 0)) * stage.zoom + 52
                width: quickRow.implicitWidth + 10; height: 40
                radius: 12
                color: Theme.surface
                border.width: 1; border.color: Theme.line
                z: 5
                Row {
                    id: quickRow
                    anchors.centerIn: parent
                    spacing: 2
                    ToolBtn { visible: quickBar.single && quickBar.el.type === "text"; icon: "pencil"; tip: "Edytuj tekst (Enter)"; onClicked: stage.quickAction("edit") }
                    ToolBtn {
                        visible: quickBar.single && quickBar.el.type === "image" && !!quickBar.el.src && Magic.available
                        icon: "sparkles"; tip: "Usuń tło (AI)"; enabled: !Magic.busy
                        onClicked: stage.quickAction("aiBackground")
                    }
                    ToolBtn {
                        visible: quickBar.single && quickBar.el.type === "image" && !!quickBar.el.src && Magic.available
                        icon: "brush"; tip: "Gumka i wyodrębnianie"; enabled: !Magic.busy
                        onClicked: stage.quickAction("aiMagic")
                    }
                    ToolBtn { visible: quickBar.single && quickBar.el.type === "image" && !!quickBar.el.src; icon: "crop"; tip: "Kadruj (dwuklik)"; onClicked: stage.quickAction("crop") }
                    Rectangle {
                        visible: quickBar.single && (quickBar.el.type === "text" || (quickBar.el.type === "image" && !!quickBar.el.src))
                        width: 1; height: 20; anchors.verticalCenter: parent.verticalCenter; color: Theme.line
                    }
                    ToolBtn { visible: !quickBar.single; icon: "layers"; tip: "Grupuj (Ctrl+G)"; onClicked: stage.quickAction("group") }
                    ToolBtn { icon: "copy"; tip: "Duplikuj (Ctrl+D)"; onClicked: stage.quickAction("duplicate") }
                    ToolBtn { icon: "lock"; tip: "Zablokuj"; onClicked: stage.quickAction("lock") }
                    ToolBtn { icon: "trash"; tip: "Usuń (Delete)"; onClicked: stage.quickAction("remove") }
                    ToolBtn {
                        icon: "more"; tip: "Więcej (prawy przycisk)"
                        onClicked: { const p = mapToItem(stage, width / 2, height); stage.menuRequested(p.x, p.y + 4); }
                    }
                }
            }

            // ——— Pusta strona: od czego zacząć ———
            Rectangle {
                visible: stage.project.count === 0 && stage.editing === ""
                anchors.centerIn: parent
                width: emptyCol.implicitWidth + 48; height: emptyCol.implicitHeight + 40
                radius: 20
                color: Theme.surface
                border.width: 1; border.color: Theme.line
                opacity: 0.97
                Column {
                    id: emptyCol
                    anchors.centerIn: parent
                    spacing: 14
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Od czego zaczniesz?"
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.Bold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: "Dodaj pierwszy element albo przeciągnij tu zdjęcie z Plików."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        Btn { primary: true; icon: "layout"; text: "Szablon"; onClicked: stage.quickAction("templates") }
                        Btn { icon: "textT"; text: "Tekst"; onClicked: stage.quickAction("addText") }
                        Btn { icon: "image"; text: "Zdjęcie"; onClicked: stage.quickAction("addPhoto") }
                        Btn { icon: "shapes"; text: "Kształt"; onClicked: stage.quickAction("shapesTab") }
                    }
                }
            }

            // ——— Narzędzia AI: zaznaczanie na zdjęciu ———
            Item {
                id: magicBox
                readonly property var el: stage.current
                visible: stage.magicOn
                x: (el.x || 0) * stage.zoom
                y: (el.y || 0) * stage.zoom
                width: (el.w || 0) * stage.zoom
                height: (el.h || 0) * stage.zoom
                rotation: el.rotation || 0
                Image {
                    anchors.fill: parent
                    visible: Magic.hasMask
                    source: Magic.maskUrl
                    cache: false
                    smooth: true
                }
                Rectangle {
                    anchors.fill: parent; anchors.margins: -1
                    color: "transparent"
                    border.width: 1.5; border.color: "#FF3D9A"
                }
                Canvas {
                    id: strokeCanvas
                    anchors.fill: parent
                    property var pts: []
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        if (pts.length === 0) return;
                        ctx.beginPath();
                        ctx.moveTo(pts[0][0], pts[0][1]);
                        for (const q of pts) ctx.lineTo(q[0], q[1]);
                        if (stage.magicTool === "lasso") {
                            ctx.closePath();
                            ctx.fillStyle = "rgba(255, 61, 154, 0.18)";
                            ctx.fill();
                            ctx.lineWidth = 1.5;
                            ctx.strokeStyle = "#FF3D9A";
                        } else {
                            ctx.lineCap = "round";
                            ctx.lineJoin = "round";
                            ctx.lineWidth = stage.brushSize;
                            ctx.strokeStyle = stage.magicSubtract ? "rgba(255, 255, 255, 0.5)" : "rgba(255, 61, 154, 0.5)";
                        }
                        ctx.stroke();
                    }
                }
                // Pędzel: kółko pod kursorem
                Rectangle {
                    id: brushRing
                    visible: stage.magicTool === "brush" && magicArea.containsMouse
                    width: stage.brushSize; height: width; radius: width / 2
                    color: "transparent"
                    border.width: 1.5; border.color: "white"
                    Rectangle { anchors.fill: parent; anchors.margins: -1.5; radius: width / 2; color: "transparent"; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.4) }
                }
                MouseArea {
                    id: magicArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !Magic.busy
                    cursorShape: stage.magicTool === "brush" ? Qt.BlankCursor : Qt.CrossCursor
                    onPositionChanged: (e) => {
                        brushRing.x = e.x - brushRing.width / 2;
                        brushRing.y = e.y - brushRing.height / 2;
                        if (!pressed || stage.magicTool === "object") return;
                        const last = strokeCanvas.pts[strokeCanvas.pts.length - 1];
                        if (last && Math.hypot(e.x - last[0], e.y - last[1]) < 2) return;
                        strokeCanvas.pts = strokeCanvas.pts.concat([[e.x, e.y]]);
                        strokeCanvas.requestPaint();
                    }
                    onPressed: (e) => {
                        stage.forceActiveFocus();
                        strokeCanvas.pts = stage.magicTool === "object" ? [] : [[e.x, e.y]];
                        strokeCanvas.requestPaint();
                    }
                    onReleased: (e) => {
                        const k = 1 / stage.zoom;
                        const sub = stage.magicSubtract || !!(e.modifiers & Qt.AltModifier);
                        const pts = strokeCanvas.pts.map(q => [q[0] * k, q[1] * k]);
                        if (stage.magicTool === "object") Magic.addObject(e.x * k, e.y * k, sub);
                        else if (stage.magicTool === "brush") Magic.addStroke(pts, stage.brushSize * k, false, sub);
                        else if (pts.length > 2) Magic.addStroke(pts, 0, true, sub);
                        strokeCanvas.pts = [];
                        strokeCanvas.requestPaint();
                    }
                }
            }
        }
    }

    // Linijki: w milimetrach przy projektach do druku, inaczej w pikselach.
    // Przeciągnięcie z linijki na stronę dodaje prowadnicę; prawy przycisk — menu prowadnic.
    Repeater {
        model: stage.rulers ? ["x", "y"] : []
        delegate: Rectangle {
            id: rl
            required property string modelData
            readonly property bool hor: modelData === "x"
            x: hor ? stage.ruler : 0
            y: hor ? 0 : stage.ruler
            width: hor ? stage.width - stage.ruler : stage.ruler
            height: hor ? stage.ruler : stage.height - stage.ruler
            color: Theme.dark ? "#1C1E25" : "#F4F5F8"
            Rectangle { x: rl.hor ? 0 : parent.width - 1; y: rl.hor ? parent.height - 1 : 0; width: rl.hor ? parent.width : 1; height: rl.hor ? 1 : parent.height; color: Theme.line }
            Canvas {
                id: ticks
                anchors.fill: parent
                readonly property var key: [stage.zoom, flick.contentX, flick.contentY, page.x, page.y, width, height, Theme.dark, stage.unitsPerPx,
                                            stage.selection.length > 0 ? JSON.stringify(stage.selection.length > 1 ? stage.group : stage.current) : ""]
                onKeyChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const len = rl.hor ? width : height;
                    const origin = (rl.hor ? page.x - flick.contentX : page.y - flick.contentY);      // początek strony w linijce
                    const ppu = stage.zoom / stage.unitsPerPx;                                         // piksele ekranu na jednostkę
                    const size = (rl.hor ? stage.project.pageWidth : stage.project.pageHeight) * stage.zoom;
                    ctx.fillStyle = Theme.dark ? "#262933" : "#FFFFFF";
                    if (rl.hor) ctx.fillRect(origin, 0, size, height - 1); else ctx.fillRect(0, origin, width - 1, size);
                    // Zaznaczony element na linijce
                    const g = stage.selection.length > 1 ? stage.group : stage.current;
                    if (stage.selection.length > 0 && g.w !== undefined) {
                        ctx.fillStyle = Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22);
                        if (rl.hor) ctx.fillRect(origin + g.x * stage.zoom, 0, g.w * stage.zoom, height - 1);
                        else ctx.fillRect(0, origin + g.y * stage.zoom, width - 1, g.h * stage.zoom);
                    }
                    let step = 1;
                    for (const s of [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000]) { step = s; if (s * ppu >= 46) break; }
                    const minor = step / (String(step)[0] === "2" ? 4 : 5);
                    ctx.strokeStyle = Theme.dark ? "#6B7280" : "#9AA0AC";
                    ctx.fillStyle = Theme.text2;
                    ctx.font = "9px sans-serif";
                    ctx.lineWidth = 1;
                    ctx.beginPath();
                    const first = Math.floor(-origin / ppu / minor) * minor;
                    for (let v = first; v * ppu + origin < len; v += minor) {
                        const p = Math.round(origin + v * ppu) + 0.5;
                        const major = Math.abs(v / step - Math.round(v / step)) < 1e-6;
                        const t = major ? 10 : 4;
                        if (rl.hor) { ctx.moveTo(p, height - t); ctx.lineTo(p, height); }
                        else { ctx.moveTo(width - t, p); ctx.lineTo(width, p); }
                        if (major) {
                            const label = String(Math.round(v));
                            if (rl.hor) ctx.fillText(label, p + 3, 9);
                            else { ctx.save(); ctx.translate(9, p + 3); ctx.rotate(-Math.PI / 2); ctx.fillText(label, -ctx.measureText(label).width - 3, 0); ctx.restore(); }
                        }
                    }
                    ctx.stroke();
                }
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: rl.hor ? Qt.SplitVCursor : Qt.SplitHCursor
                onPressed: (e) => {
                    if (e.button === Qt.RightButton) {
                        stage.clearSelection();
                        const p = mapToItem(stage, e.x, e.y);
                        stage.menuRequested(p.x, p.y);
                        return;
                    }
                    stage.prepareSnap([], true);
                }
                onPositionChanged: (e) => {
                    if (!(pressedButtons & Qt.LeftButton)) return;
                    const p = mapToItem(page, e.x, e.y);
                    // Z górnej linijki — prowadnica pozioma, z bocznej — pionowa
                    if (rl.hor) stage.moveGuide("y", -1, p.y / stage.zoom);
                    else stage.moveGuide("x", -1, p.x / stage.zoom);
                }
                onReleased: stage.dropGuide()
            }
        }
    }
    Rectangle {
        visible: stage.rulers
        width: stage.ruler; height: stage.ruler
        color: Theme.dark ? "#1C1E25" : "#F4F5F8"
        Text { anchors.centerIn: parent; text: stage.unit; color: Theme.text2; font.family: Theme.font; font.pixelSize: 8 }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: stage.panning ? Qt.LeftButton | Qt.MiddleButton : Qt.MiddleButton
        cursorShape: pressed ? Qt.ClosedHandCursor : stage.panning ? Qt.OpenHandCursor : Qt.ArrowCursor
        hoverEnabled: stage.panning
        property point start
        property point content
        onPressed: (e) => { start = Qt.point(e.x, e.y); content = Qt.point(flick.contentX, flick.contentY); }
        onPositionChanged: (e) => {
            if (!pressed) return;
            flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, content.x - (e.x - start.x)));
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, content.y - (e.y - start.y)));
        }
    }

    // ——— Pasek narzędzi AI ———
    Rectangle {
        id: magicBar
        visible: stage.magicOn
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 14
        width: Math.min(parent.width - 24, magicCol.implicitWidth + 28)
        height: magicCol.implicitHeight + 24
        radius: 18
        color: Theme.surface
        border.width: 1; border.color: Theme.line
        Column {
            id: magicCol
            anchors.centerIn: parent
            spacing: 10
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                Repeater {
                    model: [{ id: "object", label: "Kliknij rzecz", icon: "target" }, { id: "brush", label: "Pędzel", icon: "brush" }, { id: "lasso", label: "Lasso", icon: "lasso" }]
                    delegate: HoverButton {
                        id: tool
                        required property var modelData
                        readonly property bool on: stage.magicTool === modelData.id
                        width: toolRow.implicitWidth + 22; height: 32; radius: 16
                        baseColor: on ? Theme.accent : Theme.fill
                        color: on ? baseColor : hovered ? Theme.hover : baseColor
                        onClicked: stage.magicTool = modelData.id
                        Row {
                            id: toolRow
                            anchors.centerIn: parent
                            spacing: 6
                            Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons[tool.modelData.icon]; size: 15; stroke: 2; color: tool.on ? "white" : Theme.text }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: tool.modelData.label; color: tool.on ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: tool.on ? Font.DemiBold : Font.Normal }
                        }
                    }
                }
                Item { width: 6; height: 1 }
                Chip { text: "Odejmij"; on: stage.magicSubtract; onClicked: stage.magicSubtract = !stage.magicSubtract }
                ValueSlider {
                    visible: stage.magicTool === "brush"
                    width: 150; height: 44
                    label: "Rozmiar"
                    from: 6; to: 140; step: 1
                    value: stage.brushSize
                    suffix: " px"
                    onMoved: (v) => stage.brushSize = v
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: stage.magicTool === "object" ? "Kliknij rzecz na zdjęciu — zaznaczy się cała. Kliknij kolejne, żeby dodać."
                    : stage.magicTool === "brush" ? "Zamaluj to, co chcesz usunąć albo wyciąć."
                    : "Obrysuj fragment zdjęcia."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                Btn { primary: true; icon: "sparkles"; text: "Usuń"; height: 34; enabled: Magic.hasMask && !Magic.busy; onClicked: Magic.apply("erase") }
                Btn { text: "Wyodrębnij"; height: 34; enabled: Magic.hasMask && !Magic.busy; onClicked: Magic.apply("extract") }
                Btn { text: "Przenieś"; height: 34; enabled: Magic.hasMask && !Magic.busy; onClicked: Magic.apply("move") }
                ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "undo"; tip: "Cofnij zaznaczenie (Ctrl+Z)"; enabled: Magic.hasMask && !Magic.busy; onClicked: Magic.undoMask() }
                Btn { text: "Gotowe"; height: 34; onClicked: Magic.end() }
            }
        }
    }
    // Praca AI w toku (także „Usuń tło” z panelu)
    Rectangle {
        visible: Magic.busy
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top; anchors.topMargin: stage.ruler + 14
        width: busyCol.implicitWidth + 32; height: busyCol.implicitHeight + 18; radius: 16
        color: Qt.rgba(0, 0, 0, 0.78)
        Column {
            id: busyCol
            anchors.centerIn: parent
            spacing: 6
            Row {
                spacing: 8
                Icon {
                    d: Icons.sparkles; size: 15; stroke: 2; color: "white"
                    RotationAnimation on rotation { running: Magic.busy; from: 0; to: 360; duration: 1600; loops: Animation.Infinite }
                }
                Text { text: Magic.status; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
            }
            Rectangle {
                visible: Magic.progress >= 0
                width: parent.width; height: 4; radius: 2
                color: Qt.rgba(1, 1, 1, 0.25)
                Rectangle { width: parent.width * Math.max(0, Magic.progress); height: parent.height; radius: 2; color: "white" }
            }
        }
    }

    // Wymiary albo kąt podczas zmiany, podpowiedź kadrowania
    Rectangle {
        visible: stage.hint === "" && stage.cropping !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 16
        width: cropText.implicitWidth + 24; height: 30; radius: 15
        color: Qt.rgba(0, 0, 0, 0.72)
        Text {
            id: cropText
            anchors.centerIn: parent
            text: "Przeciągnij zdjęcie, żeby wybrać kadr · kółko myszy — powiększenie · Enter — gotowe"
            color: "white"
            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
        }
    }
    Rectangle {
        visible: stage.hint !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 16
        width: hintText.implicitWidth + 20; height: 26; radius: 13
        color: Qt.rgba(0, 0, 0, 0.72)
        Text {
            id: hintText
            anchors.centerIn: parent
            text: stage.hint
            color: "white"
            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; font.features: { "tnum": 1 }
        }
    }
}
