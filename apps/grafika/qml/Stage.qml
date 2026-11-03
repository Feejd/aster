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
    property rect marquee: Qt.rect(0, 0, 0, 0)  // ramka zaznaczania (piksele strony)
    property bool marqueeOn: false
    property var marqueeBase: []
    property bool syncing: false
    property var current: ({})                 // dane zaznaczonego elementu
    property bool fit: true                     // powiększenie „dopasuj do okna”
    property real userZoom: 1
    readonly property real fitZoom: Math.max(0.02, Math.min((width - 96) / project.pageWidth, (height - 96) / project.pageHeight))
    readonly property real zoom: fit ? fitZoom : userZoom
    property var guidesX: []
    property var guidesY: []
    property var snapX: []
    property var snapY: []
    property string hint: ""                    // np. wymiary albo kąt podczas zmiany
    signal menuRequested(real x, real y)

    clip: true

    function refresh() {
        current = selected !== "" ? project.get(selected) : ({});
        if (selected !== "" && current.id === undefined) selected = "";
        const alive = selection.filter(id => project.indexOf(id) >= 0);
        if (alive.length !== selection.length) { setSelection(alive); return; }
        if (cropping !== "" && cropping !== selected) cropping = "";
        group = selection.length > 1 ? bounds(selection) : ({});
    }
    onSelectedChanged: {
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
        if (cropping !== "") cropping = "";
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
    function prepareSnap(ids) {
        const W = project.pageWidth, H = project.pageHeight;
        const xs = [0, W / 2, W], ys = [0, H / 2, H];
        const all = project.document().elements;
        for (const o of all) {
            if (ids.indexOf(o.id) >= 0 || o.hidden) continue;
            const b = box(o, o.x, o.y);
            xs.push(...b.xs);
            ys.push(...b.ys);
        }
        snapX = xs;
        snapY = ys;
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
    // Przesuwanie kilku elementów: przyciąga prostokąt całej grupy (g — prostokąt na początku)
    function snapGroup(g, dx, dy) {
        const xs = [g.x + dx, g.x + dx + g.w / 2, g.x + dx + g.w], ys = [g.y + dy, g.y + dy + g.h / 2, g.y + dy + g.h];
        const sx = nearest(xs, snapX), sy = nearest(ys, snapY);
        guidesX = sx ? [sx.t] : [];
        guidesY = sy ? [sy.t] : [];
        return { dx: dx + (sx ? sx.d : 0), dy: dy + (sy ? sy.d : 0) };
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
        const b = box(el, x, y);
        const sx = nearest(b.xs, snapX), sy = nearest(b.ys, snapY);
        if (sx) x += sx.d;
        if (sy) y += sy.d;
        guidesX = sx ? [sx.t] : [];
        guidesY = sy ? [sy.t] : [];
        return { x: Math.round(x * 10) / 10, y: Math.round(y * 10) / 10 };
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
                            anchors.margins: d.element.type === "shape" && (d.element.shape === "line" || d.element.shape === "arrow") ? -4 : 0
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
                                stage.guidesX = [];
                                stage.guidesY = [];
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

            // ——— Zaznaczenie ———
            Item {
                id: sel
                readonly property var el: stage.current
                readonly property bool line: el.type === "shape" && (el.shape === "line" || el.shape === "arrow")
                readonly property bool fixed: !!el.locked || stage.cropping !== ""     // bez uchwytów
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
