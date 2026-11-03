pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Aster.Ui
import Aster.Grafika

// Płótno: strona z elementami, zaznaczenie z uchwytami (skalowanie, obrót), linie pomocnicze
// z przyciąganiem do środka i krawędzi strony oraz innych elementów, edycja tekstu w miejscu.
Item {
    id: stage
    required property Project project
    property string selected: ""
    property string editing: ""
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
    }
    onSelectedChanged: refresh()
    Connections {
        target: stage.project
        function onDataChanged() { stage.refresh(); }
        function onReset() { stage.editing = ""; stage.refresh(); }
        function onRowsRemoved() { stage.refresh(); }
        function onCountChanged() { stage.refresh(); }
    }

    function select(id) {
        if (editing !== "" && editing !== id) stopEditing();
        selected = id;
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
    function prepareSnap(id) {
        const W = project.pageWidth, H = project.pageHeight;
        const xs = [0, W / 2, W], ys = [0, H / 2, H];
        const all = project.document().elements;
        for (const o of all) {
            if (o.id === id) continue;
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

        // Kliknięcie obok strony zdejmuje zaznaczenie
        MouseArea {
            width: flick.contentWidth; height: flick.contentHeight
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: { stage.stopEditing(); stage.selected = ""; stage.forceActiveFocus(); }
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
                        stage.stopEditing();
                        stage.selected = "";
                        stage.forceActiveFocus();
                        if (e.button === Qt.RightButton) {
                            const p = mapToItem(stage, e.x, e.y);
                            stage.menuRequested(p.x, p.y);
                        }
                    }
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
                        x: element.x * stage.zoom
                        y: element.y * stage.zoom
                        width: element.w * stage.zoom
                        height: element.h * stage.zoom
                        rotation: element.rotation || 0
                        opacity: element.opacity === undefined ? 1 : element.opacity

                        ArtView {
                            anchors.fill: parent
                            project: stage.project
                            element: d.element
                            visible: stage.editing !== d.uid
                        }
                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            anchors.margins: d.element.type === "shape" && (d.element.shape === "line" || d.element.shape === "arrow") ? -4 : 0
                            enabled: stage.editing !== d.uid
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: stage.selected === d.uid ? Qt.SizeAllCursor : Qt.PointingHandCursor
                            property point start
                            property real sx
                            property real sy
                            property bool moved: false
                            onPressed: (e) => {
                                stage.select(d.uid);
                                stage.forceActiveFocus();
                                start = mapToItem(page, e.x, e.y);
                                sx = d.element.x;
                                sy = d.element.y;
                                moved = false;
                                stage.prepareSnap(d.uid);
                                if (e.button === Qt.RightButton) {
                                    const p = mapToItem(stage, e.x, e.y);
                                    stage.menuRequested(p.x, p.y);
                                }
                            }
                            onPositionChanged: (e) => {
                                if (!pressed || !(pressedButtons & Qt.LeftButton)) return;
                                const p = mapToItem(page, e.x, e.y);
                                const dx = (p.x - start.x) / stage.zoom, dy = (p.y - start.y) / stage.zoom;
                                if (!moved && Math.hypot(p.x - start.x, p.y - start.y) < 3) return;
                                moved = true;
                                const s = stage.snapMove(d.element, sx + dx, sy + dy);
                                stage.project.change(d.uid, { x: s.x, y: s.y }, false);
                            }
                            onReleased: {
                                stage.guidesX = [];
                                stage.guidesY = [];
                                if (moved) stage.project.commit();
                            }
                            onDoubleClicked: if (d.element.type === "text") stage.startEditing(d.uid)
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
                visible: stage.selected !== "" && el.id !== undefined
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

                Repeater {
                    model: stage.editing !== "" ? []
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
                            onPressed: (e) => { start = mapToItem(page, e.x, e.y); s = stage.current; }
                            onPositionChanged: (e) => {
                                if (!pressed) return;
                                const p = mapToItem(page, e.x, e.y);
                                const t = s.type;
                                const keep = (t === "image" || t === "text") !== !!(e.modifiers & Qt.ShiftModifier);
                                const g = stage.resized(s, handle.modelData.hx, handle.modelData.hy, (p.x - start.x) / stage.zoom, (p.y - start.y) / stage.zoom, keep);
                                const patch = { x: Math.round(g.x * 10) / 10, y: Math.round(g.y * 10) / 10, w: Math.round(g.w * 10) / 10 };
                                if (t === "text") {
                                    if (handle.modelData.hy !== 0) patch.size = Math.max(4, Math.round(s.size * g.w / s.w));
                                } else {
                                    patch.h = Math.round(g.h * 10) / 10;
                                }
                                stage.hint = Math.round(g.w) + " × " + Math.round(t === "text" ? stage.current.h : g.h);
                                stage.project.change(s.id, patch, false);
                            }
                            onReleased: { stage.hint = ""; stage.project.commit(); }
                        }
                    }
                }

                // Uchwyt obrotu pod elementem
                Rectangle {
                    visible: stage.editing === ""
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

    // Wymiary albo kąt podczas zmiany
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
