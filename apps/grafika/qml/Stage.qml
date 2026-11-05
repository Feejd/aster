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
    // Rysowanie odręczne: pen | marker | highlighter | neon | eraser ("" — wyłączone); grubość w pikselach strony
    property string drawTool: ""
    property color drawColor: "#16181D"
    property real drawWidth: 8
    readonly property bool drawOn: drawTool !== ""
    // Warstwy: tryby mieszania i korekcje wymagają składania całej strony
    property bool composite: false
    // Malowanie po masce warstwy
    property string maskEdit: ""
    property bool maskReveal: false             // false — pędzel ukrywa, true — przywraca
    property real maskSize: 60                  // piksele ekranu
    property real maskSoft: 0.5
    readonly property bool maskOn: maskEdit !== "" && maskEdit === selected
    // Zaznaczanie pikseli: rect | ellipse | lasso | wand | color | object ("" — inne narzędzie)
    property string selTool: ""
    property string selMode: "new"
    property real selFeather: 0
    property real selTolerance: 0.12
    property bool selLayerOnly: false
    readonly property bool selOn: selTool !== ""
    property string selHint: ""
    signal selAction(string action)
    signal generate(string prompt)
    // Malowanie i retusz po pikselach: brush | eraser | fill | pick | heal | clone | dodge | burn | smudge | blur
    property string paintTool: ""
    property color paintColor: "#16181D"
    property real paintSize: 40                 // piksele strony
    property real paintHardness: 0.7
    property real paintStrength: 1
    property real fillTolerance: 0.15
    readonly property bool paintOn: paintTool !== ""
    signal colorPicked(string color)
    signal paintMessage(string text)
    // Warstwa, po której malujemy: zaznaczone zdjęcie; bez niego pędzel i wypełnianie zakładają nową warstwę pikselową
    function paintTarget() {
        const o = current;
        if (selected !== "" && o.type === "image" && o.src && !o.locked && !o.hidden) return selected;
        if (paintTool === "brush" || paintTool === "fill") {
            const id = project.newPixelLayer();
            select(id);
            return id;
        }
        paintMessage("Zaznacz zdjęcie albo warstwę pikselową, na której chcesz pracować");
        return "";
    }
    onPaintOnChanged: if (paintOn && Magic.element !== "") Magic.end()
    // Swobodne przekształcenie: przeciąganie czterech rogów warstwy
    property string warpEdit: ""
    readonly property bool warpOn: warpEdit !== "" && warpEdit === selected
    function warpPoints() {
        const o = current;
        return o.warp && o.warp.length === 8 ? o.warp.slice() : [0, 0, o.w, 0, o.w, o.h, 0, o.h];
    }
    property var cellEdit: null                 // pisanie w komórce tabeli: { id, r, c }
    signal drawFinished()
    onDrawOnChanged: if (drawOn) { if (Magic.element !== "") Magic.end(); clearSelection(); }
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
        composite = project.usesCompositing();
        current = selected !== "" ? project.get(selected) : ({});
        if (selected !== "" && current.id === undefined) selected = "";
        const alive = selection.filter(id => project.indexOf(id) >= 0);
        if (alive.length !== selection.length) { setSelection(alive); return; }
        if (cropping !== "" && cropping !== selected) cropping = "";
        group = selection.length > 1 ? bounds(selection) : ({});
    }
    onSelectedChanged: {
        if (maskEdit !== "" && maskEdit !== selected) maskEdit = "";
        if (warpEdit !== "" && warpEdit !== selected) warpEdit = "";
        if (cellEdit && cellEdit.id !== selected) cellEdit = null;
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
        setSelection(project.document().elements.filter(o => !o.hidden && !o.locked && o.type !== "adjust").map(o => o.id));
    }
    function clearSelection() {
        stopEditing();
        cropping = "";
        setSelection([]);
    }
    // Esc: najpierw kończy kadrowanie, potem zdejmuje zaznaczenie
    function cancel() {
        if (warpEdit !== "") warpEdit = "";
        else if (maskEdit !== "") maskEdit = "";
        else if (cellEdit) cellEdit = null;
        else if (Selection.active) Selection.clear();
        else if (selOn) drawFinished();
        else if (drawOn || paintOn) drawFinished();
        else if (magicOn) Magic.end();
        else if (cropping !== "") cropping = "";
        else clearSelection();
    }
    // ——— Tabela: pisanie w komórce ———
    function editCell(id, r, c) {
        const o = project.get(id);
        const cells = o.cells || [];
        if (r < 0 || r >= cells.length) return;
        if (selected !== id) select(id);
        cellEdit = { id: id, r: r, c: c };
    }
    // Tab / Enter: następna komórka; za ostatnią — nowy wiersz
    function nextCell(down, back) {
        if (!cellEdit) return;
        const o = project.get(cellEdit.id);
        const g = (o.cells || []).map(r => r.slice());
        const C = Math.max(...g.map(r => r.length));
        let r = cellEdit.r, c = cellEdit.c;
        if (down) r += 1;
        else if (back) { c -= 1; if (c < 0) { c = C - 1; r -= 1; } }
        else { c += 1; if (c >= C) { c = 0; r += 1; } }
        if (r < 0) return;
        if (r >= g.length) {
            g.push(new Array(C).fill(""));
            project.change(o.id, { cells: g, h: Math.round(o.h / (g.length - 1) * g.length) });
        }
        cellEdit = { id: o.id, r: r, c: c };
    }
    // ——— Rysowanie ———
    // Kreska z punktów strony → element „draw” (punkty w częściach pola)
    function addDrawing(pts) {
        if (pts.length === 0) return;
        const sw = drawWidth;
        const pad = drawTool === "neon" ? sw * 2.2 : sw / 2 + 1;
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        for (const q of pts) { x0 = Math.min(x0, q[0]); x1 = Math.max(x1, q[0]); y0 = Math.min(y0, q[1]); y1 = Math.max(y1, q[1]); }
        x0 -= pad; y0 -= pad; x1 += pad; y1 += pad;
        const w = x1 - x0, h = y1 - y0;
        const flat = [];
        for (const q of pts) flat.push(Math.round((q[0] - x0) / w * 10000) / 10000, Math.round((q[1] - y0) / h * 10000) / 10000);
        project.add({ type: "draw", pen: drawTool, stroke: String(drawColor), strokeWidth: Math.round(sw * 10) / 10, points: flat,
                      x: Math.round(x0 * 10) / 10, y: Math.round(y0 * 10) / 10, w: Math.round(w * 10) / 10, h: Math.round(h * 10) / 10 });
    }
    // Gumka: usuwa rysunki, przez które przechodzi kursor (punkt strony, promień w pikselach strony)
    function eraseAt(px, py, radius) {
        const all = project.document().elements;
        for (let i = all.length - 1; i >= 0; --i) {
            const o = all[i];
            if (o.type !== "draw" || o.hidden || o.locked) continue;
            const r = -(o.rotation || 0) * Math.PI / 180;
            const cx = o.x + o.w / 2, cy = o.y + o.h / 2;
            const lx = (px - cx) * Math.cos(r) - (py - cy) * Math.sin(r) + o.w / 2;
            const ly = (px - cx) * Math.sin(r) + (py - cy) * Math.cos(r) + o.h / 2;
            const reach = radius + (o.strokeWidth || 8) / 2;
            if (lx < -reach || ly < -reach || lx > o.w + reach || ly > o.h + reach) continue;
            const p = o.points || [];
            let hit = false;
            for (let k = 0; k + 1 < p.length && !hit; k += 2) {
                const ax = p[k] * o.w, ay = p[k + 1] * o.h;
                const bx = k + 3 < p.length ? p[k + 2] * o.w : ax, by = k + 3 < p.length ? p[k + 3] * o.h : ay;
                const dx = bx - ax, dy = by - ay, len = dx * dx + dy * dy;
                const t = len > 0 ? Math.max(0, Math.min(1, ((lx - ax) * dx + (ly - ay) * dy) / len)) : 0;
                hit = Math.hypot(lx - ax - t * dx, ly - ay - t * dy) <= reach;
            }
            if (hit) project.remove(o.id);
        }
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
            if (o.hidden || o.type === "adjust") continue;
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
        function onPageChanged() { stage.refresh(); }
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
                // Strona złożona w całości, gdy są tryby mieszania albo korekcje; elementy niżej zostają do obsługi myszy
                PageView {
                    anchors.fill: parent
                    visible: stage.composite
                    project: stage.project
                    page: stage.project.currentPage
                    hidden: stage.editing
                }
                Repeater {
                    model: stage.project
                    delegate: Item {
                        id: d
                        required property var element
                        readonly property string uid: element.id
                        readonly property bool cropping: stage.cropping === uid
                        visible: !element.hidden && element.type !== "adjust"
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
                            visible: stage.editing !== d.uid && !stage.composite
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
                                // Pisanie w tabeli: kliknięcie w inną komórkę przenosi pisanie tam
                                if (stage.cellEdit && stage.cellEdit.id === d.uid && e.button === Qt.LeftButton) {
                                    const cells = d.element.cells || [];
                                    const C = Math.max(1, ...cells.map(r => r.length));
                                    stage.editCell(d.uid, Math.floor(e.y / height * cells.length), Math.min(C - 1, Math.floor(e.x / width * C)));
                                    return;
                                }
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
                            onDoubleClicked: (mouse) => {
                                if (d.element.locked) return;
                                if (d.element.type === "text") stage.startEditing(d.uid);
                                else if (d.element.type === "table") {
                                    const cells = d.element.cells || [];
                                    const C = Math.max(1, ...cells.map(r => r.length));
                                    stage.editCell(d.uid, Math.floor(mouse.y / height * cells.length), Math.min(C - 1, Math.floor(mouse.x / width * C)));
                                }
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
                readonly property bool fixed: !!el.locked || stage.cropping !== "" || stage.magicOn || stage.maskOn || stage.paintOn || stage.selOn     // bez uchwytów
                visible: stage.selected !== "" && el.id !== undefined && !el.hidden && el.type !== "adjust" && !el.warp && !stage.warpOn
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
                         && stage.hint === "" && !stage.marqueeOn && !(single && el.locked) && stage.dragGuide === null && !stage.drawOn && !stage.cellEdit && !stage.maskOn && !stage.paintOn && !stage.selOn && !stage.warpOn && !(single && el.type === "adjust")
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
                    ToolBtn { visible: quickBar.single && quickBar.el.type === "table"; icon: "pencil"; tip: "Pisz w komórkach (dwuklik w komórkę)"; onClicked: stage.editCell(stage.selected, 0, 0) }
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

            // ——— Pisanie w komórce tabeli ———
            Item {
                id: cellBox
                readonly property var el: stage.cellEdit ? stage.project.get(stage.cellEdit.id) : ({})
                readonly property var cells: el.cells || []
                readonly property int cols: { let n = 1; for (const r of cells) n = Math.max(n, r.length); return n; }
                visible: !!stage.cellEdit && el.id !== undefined
                x: (el.x || 0) * stage.zoom
                y: (el.y || 0) * stage.zoom
                width: (el.w || 0) * stage.zoom
                height: (el.h || 0) * stage.zoom
                rotation: el.rotation || 0
                z: 21
                Rectangle {
                    id: cellRect
                    readonly property real cw: cellBox.width / cellBox.cols
                    readonly property real rh: cellBox.height / Math.max(1, cellBox.cells.length)
                    readonly property bool head: cellBox.el.header !== false && stage.cellEdit && stage.cellEdit.r === 0
                    x: stage.cellEdit ? stage.cellEdit.c * cw : 0
                    y: stage.cellEdit ? stage.cellEdit.r * rh : 0
                    width: cw; height: rh
                    color: head ? (cellBox.el.headerFill || "#16181D") : (cellBox.el.fill || "white")
                    border.width: 2; border.color: Theme.accent
                    TextInput {
                        id: cellInput
                        readonly property real pad: Math.min((cellBox.el.size || 24) * 0.7, cellBox.el.w / cellBox.cols * 0.15) * stage.zoom
                        x: pad; width: parent.width - 2 * pad
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true
                        horizontalAlignment: cellBox.el.align === "center" ? TextInput.AlignHCenter : cellBox.el.align === "right" ? TextInput.AlignRight : TextInput.AlignLeft
                        color: cellRect.head ? (cellBox.el.headerColor || "white") : (cellBox.el.color || "#3D4048")
                        selectionColor: Theme.accent
                        selectByMouse: true
                        font.family: cellBox.el.font || "Geist"
                        font.pixelSize: Math.max(6, (cellBox.el.size || 24) * stage.zoom)
                        font.weight: cellRect.head ? Font.Bold : Font.Normal
                        property bool loading: false
                        function load() {
                            if (!stage.cellEdit) return;
                            loading = true;
                            text = (cellBox.cells[stage.cellEdit.r] || [])[stage.cellEdit.c] || "";
                            loading = false;
                            selectAll();
                            forceActiveFocus();
                        }
                        onTextEdited: {
                            const g = cellBox.cells.map(r => { const o = r.slice(); while (o.length < cellBox.cols) o.push(""); return o; });
                            g[stage.cellEdit.r][stage.cellEdit.c] = text;
                            stage.project.change(stage.cellEdit.id, { cells: g }, false);
                        }
                        Keys.onTabPressed: { stage.project.commit(); stage.nextCell(false, false); }
                        Keys.onBacktabPressed: { stage.project.commit(); stage.nextCell(false, true); }
                        Keys.onReturnPressed: { stage.project.commit(); stage.nextCell(true, false); }
                        Keys.onEnterPressed: { stage.project.commit(); stage.nextCell(true, false); }
                        Keys.onEscapePressed: { stage.project.commit(); stage.cellEdit = null; stage.forceActiveFocus(); }
                        onActiveFocusChanged: if (!activeFocus) stage.project.commit()
                    }
                }
                Connections {
                    target: stage
                    function onCellEditChanged() { if (stage.cellEdit) Qt.callLater(cellInput.load); else stage.project.commit(); }
                }
            }

            // ——— Swobodne przekształcenie ———
            Item {
                id: warpBox
                readonly property var el: stage.current
                visible: stage.warpOn
                x: (el.x || 0) * stage.zoom
                y: (el.y || 0) * stage.zoom
                width: (el.w || 0) * stage.zoom
                height: (el.h || 0) * stage.zoom
                rotation: el.rotation || 0
                z: 23
                readonly property var pts: stage.warpOn ? stage.warpPoints() : [0, 0, 0, 0, 0, 0, 0, 0]
                onPtsChanged: warpLines.requestPaint()
                Canvas {
                    id: warpLines
                    anchors.fill: parent
                    anchors.margins: -2000
                    onPaint: {
                        const c = getContext("2d"), p = warpBox.pts, z = stage.zoom, o = 2000;
                        c.reset();
                        c.beginPath();
                        for (let i = 0; i < 4; ++i) { if (i === 0) c.moveTo(p[0] * z + o, p[1] * z + o); else c.lineTo(p[2 * i] * z + o, p[2 * i + 1] * z + o); }
                        c.closePath();
                        c.lineWidth = 3; c.strokeStyle = "rgba(0, 0, 0, 0.35)"; c.stroke();
                        c.lineWidth = 1.5; c.strokeStyle = Theme.accent; c.stroke();
                    }
                }
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        id: wh
                        required property int index
                        x: warpBox.pts[2 * index] * stage.zoom - 7
                        y: warpBox.pts[2 * index + 1] * stage.zoom - 7
                        width: 14; height: 14; radius: 7
                        color: "white"
                        border.width: 2; border.color: Theme.accent
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -8
                            cursorShape: Qt.CrossCursor
                            onPositionChanged: (e) => {
                                if (!pressed) return;
                                const q = mapToItem(warpBox, e.x, e.y), list = warpBox.pts.slice();
                                list[2 * wh.index] = Math.round(q.x / stage.zoom * 10) / 10;
                                list[2 * wh.index + 1] = Math.round(q.y / stage.zoom * 10) / 10;
                                stage.project.change(stage.warpEdit, { warp: list }, false);
                            }
                            onReleased: stage.project.commit()
                        }
                    }
                }
            }

            // ——— Zaznaczanie pikseli ———
            Item {
                id: selBox
                anchors.fill: parent
                visible: stage.selOn
                z: 22
                Rectangle {
                    id: selRect
                    visible: false
                    color: "transparent"
                    radius: selArea.kind === "ellipse" ? Math.max(width, height) : 0
                    border.width: 1; border.color: "white"
                    Rectangle { anchors.fill: parent; anchors.margins: -1; radius: parent.radius; color: "transparent"; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.6) }
                }
                Canvas {
                    id: selCanvas
                    anchors.fill: parent
                    property var pts: []
                    onPaint: {
                        const c = getContext("2d");
                        c.reset();
                        if (pts.length < 2) return;
                        c.beginPath();
                        c.moveTo(pts[0][0], pts[0][1]);
                        for (const q of pts) c.lineTo(q[0], q[1]);
                        c.lineWidth = 3; c.strokeStyle = "rgba(0, 0, 0, 0.5)"; c.stroke();
                        c.lineWidth = 1; c.strokeStyle = "white"; c.stroke();
                    }
                }
                MouseArea {
                    id: selArea
                    anchors.fill: parent
                    anchors.margins: -60
                    enabled: !Magic.busy
                    cursorShape: Qt.CrossCursor
                    property string kind: ""
                    property string mode: "new"
                    property bool moving: false
                    property point start
                    function pos(e) { return Qt.point(e.x - 60, e.y - 60); }
                    onPressed: (e) => {
                        stage.forceActiveFocus();
                        const p = pos(e), k = 1 / stage.zoom;
                        const shift = !!(e.modifiers & Qt.ShiftModifier), alt = !!(e.modifiers & Qt.AltModifier);
                        mode = shift && alt ? "intersect" : shift ? "add" : alt ? "subtract" : stage.selMode;
                        kind = stage.selTool;
                        start = p;
                        moving = mode === "new" && (kind === "rect" || kind === "ellipse" || kind === "lasso") && Selection.contains(p.x * k, p.y * k);
                        if (kind === "lasso" && !moving) { selCanvas.pts = [[p.x, p.y]]; selCanvas.requestPaint(); }
                    }
                    onPositionChanged: (e) => {
                        if (!pressed) return;
                        const p = pos(e);
                        if (moving) { ants.x = p.x - start.x; ants.y = p.y - start.y; return; }
                        if (kind === "rect" || kind === "ellipse") {
                            selRect.x = Math.min(p.x, start.x); selRect.y = Math.min(p.y, start.y);
                            selRect.width = Math.abs(p.x - start.x); selRect.height = Math.abs(p.y - start.y);
                            selRect.visible = true;
                        } else if (kind === "lasso") {
                            const pts = selCanvas.pts, last = pts[pts.length - 1];
                            if (Math.hypot(p.x - last[0], p.y - last[1]) < 2) return;
                            selCanvas.pts = pts.concat([[p.x, p.y]]);
                            selCanvas.requestPaint();
                        }
                    }
                    onReleased: (e) => {
                        const k = 1 / stage.zoom, p = pos(e);
                        selRect.visible = false;
                        if (moving) {
                            ants.x = 0; ants.y = 0;
                            moving = false;
                            if (Math.hypot(p.x - start.x, p.y - start.y) >= 2) Selection.translate((p.x - start.x) * k, (p.y - start.y) * k);
                            else Selection.clear();
                            return;
                        }
                        if (kind === "rect" || kind === "ellipse") {
                            const w = Math.abs(p.x - start.x), h = Math.abs(p.y - start.y);
                            if (w >= 3 && h >= 3)
                                Selection.shape(stage.project, Math.min(p.x, start.x) * k, Math.min(p.y, start.y) * k, w * k, h * k, kind === "ellipse", mode, stage.selFeather);
                            else if (mode === "new") Selection.clear();
                        } else if (kind === "lasso") {
                            if (selCanvas.pts.length >= 3) Selection.lasso(stage.project, selCanvas.pts.map(q => [q[0] * k, q[1] * k]), mode, stage.selFeather);
                            else if (mode === "new") Selection.clear();
                            selCanvas.pts = [];
                            selCanvas.requestPaint();
                        } else if (kind === "wand" || kind === "color") {
                            Selection.wand(stage.project, p.x * k, p.y * k, stage.selTolerance, kind === "wand", stage.selLayerOnly ? stage.selected : "", mode, 0);
                        } else if (kind === "object") {
                            const q = mapToItem(stage, e.x, e.y), o = stage.elementAt(q.x, q.y);
                            if (o && o.type === "image" && o.src) Magic.selectObject(stage.project, o.id, p.x * k, p.y * k, mode);
                            else stage.paintMessage("Kliknij zdjęcie — AI zaznacza rzeczy na zdjęciach");
                        }
                    }
                }
            }
            // Maszerujące mrówki: widać je też przy malowaniu i korekcjach
            SelectionView {
                id: ants
                width: page.width; height: page.height
                visible: Selection.active
                z: 30
                Connections { target: Selection; function onChanged() { ants.rebuild(); } }
            }

            // ——— Malowanie i retusz ———
            Item {
                id: paintBox
                anchors.fill: parent
                visible: stage.paintOn
                z: 20
                Canvas {
                    id: healCanvas
                    anchors.fill: parent
                    property var pts: []
                    onPaint: {
                        const c = getContext("2d");
                        c.reset();
                        if (pts.length === 0) return;
                        c.beginPath();
                        c.moveTo(pts[0][0], pts[0][1]);
                        for (const q of pts) c.lineTo(q[0], q[1]);
                        if (pts.length === 1) c.lineTo(pts[0][0] + 0.01, pts[0][1]);
                        c.lineCap = "round"; c.lineJoin = "round";
                        c.lineWidth = stage.paintSize * stage.zoom;
                        c.strokeStyle = "rgba(255, 61, 154, 0.5)";
                        c.stroke();
                    }
                }
                // Źródło stempla
                Item {
                    visible: stage.paintTool === "clone" && Retouch.hasSource
                    x: Retouch.source.x * stage.zoom; y: Retouch.source.y * stage.zoom
                    Rectangle { x: -9; y: -0.75; width: 18; height: 1.5; color: "white"; border.width: 0.5; border.color: "black" }
                    Rectangle { x: -0.75; y: -9; width: 1.5; height: 18; color: "white"; border.width: 0.5; border.color: "black" }
                }
                Rectangle {
                    id: paintRing
                    readonly property real d: Math.max(6, stage.paintSize * stage.zoom)
                    visible: paintArea.containsMouse && stage.paintTool !== "pick" && stage.paintTool !== "fill"
                    width: d; height: d; radius: d / 2
                    color: "transparent"
                    border.width: 1.5; border.color: "white"
                    Rectangle { anchors.fill: parent; anchors.margins: -1.5; radius: width / 2; color: "transparent"; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.5) }
                }
                MouseArea {
                    id: paintArea
                    anchors.fill: parent
                    anchors.margins: -60
                    hoverEnabled: true
                    enabled: !Magic.busy
                    cursorShape: stage.paintTool === "pick" || stage.paintTool === "fill" ? Qt.CrossCursor : Qt.BlankCursor
                    property string target: ""
                    function pos(e) { return Qt.point((e.x - 60) / stage.zoom, (e.y - 60) / stage.zoom); }
                    function ring(e) {
                        paintRing.x = e.x - 60 - paintRing.width / 2;
                        paintRing.y = e.y - 60 - paintRing.height / 2;
                    }
                    onPressed: (e) => {
                        stage.forceActiveFocus();
                        ring(e);
                        target = "";
                        const p = pos(e), t = stage.paintTool;
                        if (t === "pick") { stage.colorPicked(stage.project.colorAt(p.x, p.y)); return; }
                        const id = stage.paintTarget();
                        if (id === "") return;
                        Retouch.color = String(stage.paintColor);
                        Retouch.size = stage.paintSize;
                        Retouch.hardness = stage.paintHardness;
                        Retouch.strength = stage.paintStrength;
                        if (t === "fill") { Retouch.fill(stage.project, id, p.x, p.y, stage.fillTolerance); return; }
                        if (t === "heal") {
                            target = id;
                            healCanvas.pts = [[e.x - 60, e.y - 60]];
                            healCanvas.requestPaint();
                            return;
                        }
                        Retouch.tool = t;
                        if (t === "clone" && (e.modifiers & Qt.AltModifier)) { Retouch.setSource(stage.project, id, p.x, p.y); return; }
                        if (Retouch.press(stage.project, id, p.x, p.y)) target = id;
                    }
                    onPositionChanged: (e) => {
                        ring(e);
                        if (!pressed || target === "") return;
                        const p = pos(e);
                        if (stage.paintTool === "heal") {
                            const pts = healCanvas.pts, last = pts[pts.length - 1];
                            if (Math.hypot(e.x - 60 - last[0], e.y - 60 - last[1]) < 2) return;
                            healCanvas.pts = pts.concat([[e.x - 60, e.y - 60]]);
                            healCanvas.requestPaint();
                        } else {
                            Retouch.move(p.x, p.y);
                        }
                    }
                    onReleased: {
                        if (target === "") return;
                        if (stage.paintTool === "heal") {
                            Magic.heal(stage.project, target, healCanvas.pts.map(q => [q[0] / stage.zoom, q[1] / stage.zoom]), stage.paintSize);
                            healCanvas.pts = [];
                            healCanvas.requestPaint();
                        } else {
                            Retouch.release();
                        }
                        target = "";
                    }
                }
            }

            // ——— Malowanie po masce warstwy ———
            Item {
                id: maskBox
                readonly property var el: stage.current
                readonly property bool whole: el.type === "adjust"
                visible: stage.maskOn
                x: whole ? 0 : (el.x || 0) * stage.zoom
                y: whole ? 0 : (el.y || 0) * stage.zoom
                width: whole ? page.width : (el.w || 0) * stage.zoom
                height: whole ? page.height : (el.h || 0) * stage.zoom
                rotation: whole ? 0 : el.rotation || 0
                z: 20
                Rectangle {
                    anchors.fill: parent; anchors.margins: -1
                    color: "transparent"
                    border.width: 1.5; border.color: Theme.accent
                }
                Canvas {
                    id: maskCanvas
                    anchors.fill: parent
                    property var pts: []
                    onPaint: {
                        const c = getContext("2d");
                        c.reset();
                        if (pts.length === 0) return;
                        c.beginPath();
                        c.moveTo(pts[0][0], pts[0][1]);
                        for (const q of pts) c.lineTo(q[0], q[1]);
                        if (pts.length === 1) c.lineTo(pts[0][0] + 0.01, pts[0][1]);
                        c.lineCap = "round"; c.lineJoin = "round";
                        c.lineWidth = stage.maskSize;
                        c.strokeStyle = stage.maskReveal ? "rgba(255, 255, 255, 0.5)" : "rgba(255, 40, 80, 0.5)";
                        c.stroke();
                    }
                }
                Rectangle {
                    id: maskRing
                    visible: maskArea.containsMouse
                    width: stage.maskSize; height: width; radius: width / 2
                    color: "transparent"
                    border.width: 1.5; border.color: "white"
                    Rectangle { anchors.fill: parent; anchors.margins: -1.5; radius: width / 2; color: "transparent"; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.45) }
                }
                MouseArea {
                    id: maskArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.BlankCursor
                    onPositionChanged: (e) => {
                        maskRing.x = e.x - maskRing.width / 2;
                        maskRing.y = e.y - maskRing.height / 2;
                        if (!pressed) return;
                        const pts = maskCanvas.pts, last = pts[pts.length - 1];
                        if (last && Math.hypot(e.x - last[0], e.y - last[1]) < 2) return;
                        maskCanvas.pts = pts.concat([[e.x, e.y]]);
                        maskCanvas.requestPaint();
                    }
                    onPressed: (e) => {
                        stage.forceActiveFocus();
                        maskCanvas.pts = [[e.x, e.y]];
                        maskCanvas.requestPaint();
                    }
                    onReleased: {
                        stage.project.maskStroke(stage.maskEdit, maskCanvas.pts.map(q => [q[0] / width, q[1] / height]),
                                                 stage.maskSize / width, stage.maskReveal, stage.maskSoft);
                        maskCanvas.pts = [];
                        maskCanvas.requestPaint();
                    }
                }
            }

            // ——— Rysowanie odręczne ———
            Item {
                id: drawBox
                anchors.fill: parent
                visible: stage.drawOn
                z: 20
                Canvas {
                    id: drawCanvas
                    anchors.fill: parent
                    anchors.margins: -400               // kreska może wyjść poza stronę
                    property var pts: []
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        if (pts.length === 0 || stage.drawTool === "eraser") return;
                        const o = 400, t = stage.drawTool;
                        const lw = stage.drawWidth * stage.zoom;
                        ctx.beginPath();
                        ctx.moveTo(pts[0][0] + o, pts[0][1] + o);
                        if (pts.length === 1) ctx.lineTo(pts[0][0] + o + 0.01, pts[0][1] + o);
                        for (let i = 1; i < pts.length - 1; ++i)
                            ctx.quadraticCurveTo(pts[i][0] + o, pts[i][1] + o, (pts[i][0] + pts[i + 1][0]) / 2 + o, (pts[i][1] + pts[i + 1][1]) / 2 + o);
                        if (pts.length > 1) ctx.lineTo(pts[pts.length - 1][0] + o, pts[pts.length - 1][1] + o);
                        ctx.lineCap = t === "highlighter" ? "butt" : "round";
                        ctx.lineJoin = t === "highlighter" ? "bevel" : "round";
                        ctx.lineWidth = lw;
                        ctx.strokeStyle = stage.drawColor;
                        ctx.globalAlpha = t === "highlighter" ? 0.42 : 1;
                        if (t === "neon") { ctx.shadowColor = stage.drawColor; ctx.shadowBlur = lw * 2.5; }
                        ctx.stroke();
                        if (t === "neon") {
                            ctx.shadowBlur = 0;
                            ctx.lineWidth = lw * 0.4;
                            ctx.strokeStyle = "rgba(255, 255, 255, 0.86)";
                            ctx.stroke();
                        }
                    }
                }
                Rectangle {
                    id: penRing
                    readonly property real d: Math.max(8, (stage.drawTool === "eraser" ? 24 : stage.drawWidth * stage.zoom))
                    visible: drawArea.containsMouse
                    width: d; height: d; radius: d / 2
                    color: stage.drawTool === "eraser" ? Qt.rgba(1, 1, 1, 0.35) : "transparent"
                    border.width: 1.5; border.color: stage.drawTool === "eraser" ? "#FF3D9A" : "white"
                    Rectangle { anchors.fill: parent; anchors.margins: -1.5; radius: width / 2; color: "transparent"; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.45) }
                }
                MouseArea {
                    id: drawArea
                    anchors.fill: parent
                    anchors.margins: -60
                    hoverEnabled: true
                    cursorShape: Qt.BlankCursor
                    function ring(e) {
                        penRing.x = e.x - 60 - penRing.width / 2;
                        penRing.y = e.y - 60 - penRing.height / 2;
                    }
                    onPressed: (e) => {
                        stage.forceActiveFocus();
                        ring(e);
                        if (stage.drawTool === "eraser") { stage.eraseAt((e.x - 60) / stage.zoom, (e.y - 60) / stage.zoom, 12 / stage.zoom); return; }
                        drawCanvas.pts = [[e.x - 60, e.y - 60]];
                        drawCanvas.requestPaint();
                    }
                    onPositionChanged: (e) => {
                        ring(e);
                        if (!pressed) return;
                        const x = e.x - 60, y = e.y - 60;
                        if (stage.drawTool === "eraser") { stage.eraseAt(x / stage.zoom, y / stage.zoom, 12 / stage.zoom); return; }
                        const pts = drawCanvas.pts;
                        const last = pts[pts.length - 1];
                        if (last && Math.hypot(x - last[0], y - last[1]) < 2.5) return;
                        drawCanvas.pts = pts.concat([[x, y]]);
                        drawCanvas.requestPaint();
                    }
                    onReleased: {
                        if (stage.drawTool !== "eraser") stage.addDrawing(drawCanvas.pts.map(q => [q[0] / stage.zoom, q[1] / stage.zoom]));
                        drawCanvas.pts = [];
                        drawCanvas.requestPaint();
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

    // Rysowanie: podpowiedź i wyjście
    Rectangle {
        visible: stage.drawOn
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 14
        width: drawPillRow.implicitWidth + 16; height: 44; radius: 22
        color: Theme.surface
        border.width: 1; border.color: Theme.line
        Row {
            id: drawPillRow
            anchors.centerIn: parent
            spacing: 10
            Item { width: 4; height: 1 }
            Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons[stage.drawTool === "eraser" ? "eraser" : "brush"] || Icons.brush; size: 16; stroke: 2; color: Theme.text }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: stage.drawTool === "eraser" ? "Przeciągnij po rysunku, żeby go zmazać" : "Rysuj po stronie · każda kreska to osobny element"
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13
            }
            Btn { anchors.verticalCenter: parent.verticalCenter; primary: true; text: "Gotowe"; height: 32; onClicked: stage.drawFinished() }
        }
    }

    // Pasek przy zaznaczeniu: opis tego, co ma się tu pojawić, i działania od razu pod ręką
    Rectangle {
        visible: Selection.active && !Magic.busy && !stage.paintOn && !stage.drawOn && !stage.maskOn && !stage.magicOn
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 14
        width: Math.min(parent.width - 24, ctxCol.implicitWidth + 20); height: ctxCol.implicitHeight + 16; radius: 22
        color: Theme.surface
        border.width: 1; border.color: Theme.line
        z: 7
        function fill() {
            const t = promptInput.text.trim();
            stage.generate(t);
        }
        Column {
          id: ctxCol
          anchors.centerIn: parent
          spacing: 6
          Rectangle {
            visible: Magic.available && Magic.canGenerate()
            width: ctxRow.implicitWidth; height: 38; radius: 19
            color: Theme.fill
            border.width: promptInput.activeFocus ? 1.5 : 0; border.color: Theme.accent
            Icon { x: 13; anchors.verticalCenter: parent.verticalCenter; d: Icons.sparkles; size: 16; stroke: 1.9; color: Theme.accentText }
            TextInput {
                id: promptInput
                x: 38; width: parent.width - 38 - genBtn.width - 10
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                color: Theme.text
                selectionColor: Theme.accent
                selectByMouse: true
                font.family: Theme.font; font.pixelSize: 13
                Keys.onReturnPressed: parent.parent.parent.fill()
                Keys.onEnterPressed: parent.parent.parent.fill()
                Keys.onEscapePressed: { focus = false; stage.forceActiveFocus(); }
                Text {
                    visible: !promptInput.text
                    text: "Opisz, co ma się tu pojawić, np. drewniana ławka"
                    color: Theme.text2; font: promptInput.font
                }
            }
            Btn {
                id: genBtn
                anchors.right: parent.right; anchors.rightMargin: 3
                anchors.verticalCenter: parent.verticalCenter
                height: 32; primary: true
                text: "Generuj"
                tip: Magic.downloadMB("generate") > 0 ? "Za pierwszym razem pobierze model AI (" + (Magic.downloadMB("generate") / 1000).toFixed(1).replace(".", ",") + " GB)" : "Wynik trafi na osobną warstwę"
                onClicked: parent.parent.parent.fill()
            }
          }
          Row {
            id: ctxRow
            spacing: 4
            Btn { anchors.verticalCenter: parent.verticalCenter; height: 34; primary: true; icon: "layers"; text: "Wyodrębnij"; tip: "Na nową warstwę, zdjęcie zostaje bez zmian (Ctrl+J)"; onClicked: stage.selAction("extract") }
            Btn { anchors.verticalCenter: parent.verticalCenter; height: 34; visible: Magic.available; icon: "sparkles"; text: "Usuń"; tip: "Znika z obrazu, a tło uzupełnia się samo"; onClicked: stage.selAction("aifill") }
            Btn { anchors.verticalCenter: parent.verticalCenter; height: 34; icon: "circleHalf"; text: "Maska"; tip: "Zostaje tylko zaznaczone; nic się nie kasuje"; onClicked: stage.selAction("mask") }
            Btn { anchors.verticalCenter: parent.verticalCenter; height: 34; icon: "sliders"; text: "Korekcja"; tip: "Kolory i tony tylko tutaj"; onClicked: stage.selAction("adjust") }
            ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "crop"; tip: "Przytnij stronę do zaznaczenia"; onClicked: stage.selAction("crop") }
            ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "swap"; tip: "Odwróć zaznaczenie (Ctrl+Shift+I)"; onClicked: stage.selAction("invert") }
            ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "close"; tip: "Odznacz (Esc)"; onClicked: stage.selAction("clear") }
          }
        }
    }

    // Zaznaczanie: podpowiedź i wyjście
    Rectangle {
        visible: stage.selOn && !Magic.busy && !Selection.active
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 14
        width: selPill.implicitWidth + 16; height: 44; radius: 22
        color: Theme.surface
        border.width: 1; border.color: Theme.line
        z: 6
        Row {
            id: selPill
            anchors.centerIn: parent
            spacing: 10
            Item { width: 4; height: 1 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: stage.selHint; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
            Btn { anchors.verticalCenter: parent.verticalCenter; primary: true; text: "Gotowe"; height: 32; onClicked: stage.drawFinished() }
        }
    }

    // Malowanie: wyjście i stan
    Rectangle {
        visible: stage.paintOn && !Magic.busy
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 14
        width: paintPill.implicitWidth + 16; height: 44; radius: 22
        color: Theme.surface
        border.width: 1; border.color: Theme.line
        z: 6
        Row {
            id: paintPill
            anchors.centerIn: parent
            spacing: 10
            Item { width: 4; height: 1 }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: stage.current.type === "image" && stage.current.src
                      ? "Pracujesz na: " + (stage.current.pixel ? "warstwa pikselowa" : "zdjęcie") + " · [ ] zmienia rozmiar"
                      : "Pędzel utworzy nową warstwę · [ ] zmienia rozmiar"
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13
            }
            Btn { anchors.verticalCenter: parent.verticalCenter; primary: true; text: "Gotowe"; height: 32; onClicked: stage.drawFinished() }
        }
    }

    // ——— Pasek przekształcenia ———
    Rectangle {
        visible: stage.warpOn
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 14
        width: warpRow.implicitWidth + 16; height: 44; radius: 22
        color: Theme.surface
        border.width: 1; border.color: Theme.line
        z: 6
        Row {
            id: warpRow
            anchors.centerIn: parent
            spacing: 10
            Item { width: 4; height: 1 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Przeciągnij rogi: perspektywa, zniekształcenie"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
            Btn { anchors.verticalCenter: parent.verticalCenter; height: 32; text: "Wyzeruj"; onClicked: stage.project.change(stage.warpEdit, { warp: null }) }
            Btn { anchors.verticalCenter: parent.verticalCenter; primary: true; text: "Gotowe"; height: 32; onClicked: stage.warpEdit = "" }
        }
    }

    // ——— Pasek maski warstwy ———
    Rectangle {
        visible: stage.maskOn
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 14
        width: Math.min(parent.width - 24, maskRow.implicitWidth + 24)
        height: maskRow.implicitHeight + 18
        radius: 16
        color: Theme.surface
        border.width: 1; border.color: Theme.line
        z: 6
        Row {
            id: maskRow
            anchors.centerIn: parent
            spacing: 6
            Chip { anchors.verticalCenter: parent.verticalCenter; text: "Ukryj"; on: !stage.maskReveal; tip: "Pędzel ukrywa warstwę (X zamienia)"; onClicked: stage.maskReveal = false }
            Chip { anchors.verticalCenter: parent.verticalCenter; text: "Przywróć"; on: stage.maskReveal; tip: "Pędzel przywraca warstwę (X zamienia)"; onClicked: stage.maskReveal = true }
            ValueSlider { width: 120; height: 44; label: "Rozmiar"; from: 4; to: 300; step: 1; value: stage.maskSize; suffix: " px"; onMoved: (v) => stage.maskSize = v }
            ValueSlider { width: 110; height: 44; label: "Miękkość"; from: 0; to: 1; step: 0.05; value: stage.maskSoft; shown: value * 100; suffix: "%"; onMoved: (v) => stage.maskSoft = v }
            ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "swap"; tip: "Odwróć maskę"; onClicked: stage.project.invertMask(stage.maskEdit) }
            ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "chevronDown"; tip: "Wygaszanie ku dołowi"; onClicked: stage.project.gradientMask(stage.maskEdit, 180) }
            ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "forward"; tip: "Wygaszanie w prawo"; onClicked: stage.project.gradientMask(stage.maskEdit, 90) }
            ToolBtn {
                anchors.verticalCenter: parent.verticalCenter
                icon: "trash"; tip: "Usuń maskę"
                onClicked: { const id = stage.maskEdit; stage.maskEdit = ""; stage.project.change(id, { layerMask: null, layerMaskOff: null }); }
            }
            Btn { anchors.verticalCenter: parent.verticalCenter; primary: true; text: "Gotowe"; height: 34; onClicked: stage.maskEdit = "" }
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
                Btn { text: "Maska"; height: 34; tip: "Zostaw tylko zaznaczone jako maskę warstwy — zdjęcie zostaje nietknięte"; enabled: Magic.hasMask && !Magic.busy; onClicked: Magic.apply("mask") }
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
            Text {
                visible: Magic.generating
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Anuluj"
                color: "white"; font.family: Theme.font; font.pixelSize: 12; font.underline: true
                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: Magic.cancelGenerate() }
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
