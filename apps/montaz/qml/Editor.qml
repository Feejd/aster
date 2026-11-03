pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Aster.Ui
import Aster.Montaz

// Edytor: u góry pasek z nazwą projektu, po lewej multimedia, pośrodku podgląd,
// po prawej ustawienia zaznaczonego elementu, a na dole oś czasu.
GlassPane {
    id: ed
    required property Window window
    property real radius: 0
    signal toast(string text)
    signal importRequested()
    signal overlayRequested()
    signal menuRequested(var items, real x, real y)

    leftLine: false
    topLeftRadius: radius; topRightRadius: radius; bottomLeftRadius: radius; bottomRightRadius: radius

    property string selected: ""
    readonly property string selectedKind: Project.revision >= 0 ? Project.kindOf(selected) : ""
    property alias player: player
    property alias timeline: timeline

    Player {
        id: player
        active: ed.visible && !exportSheet.running
    }

    // Zaznaczony napis ma być widać na podglądzie — głowica wskakuje do jego środka
    onSelectedChanged: {
        if (selectedKind !== "text" && selectedKind !== "overlay") return;
        const t = Project.item(selected);
        if (player.position < t.start || player.position >= t.start + t.length) {
            player.pause();
            player.seek(t.start + Math.min(t.length - 1, Math.round(t.length / 2)));
        }
    }

    Connections {
        target: Project
        function onOpenChanged() { ed.selected = ""; timeline.fit(); }
        function onChanged() { if (ed.selected && !Project.kindOf(ed.selected)) ed.selected = ""; }
    }

    // Gdzie wstawić nowe klipy: w miejscu głowicy, a gdy stoi na końcu — na końcu
    function insertFrame() { return player.position > 0 && player.position < Project.duration - 1 ? player.position : -1 }
    // Upuszczenie na ścieżkę nakładek dodaje nakładkę zamiast klipu
    function dropTrack(x, y) {
        const p = mapToItem(timeline, x, y);
        return timeline.contains(Qt.point(p.x, p.y)) ? timeline.trackAtY(p.y) : "";
    }
    function dropFrame(x, y) {
        const p = mapToItem(timeline, x, y);
        return timeline.contains(Qt.point(p.x, p.y)) ? timeline.frameAtX(p.x) : insertFrame();
    }

    // ——— Działania (skróty, przyciski, menu) ———
    function splitAtPlayhead() {
        let id = selected && Project.itemAt(selectedKind === "clip" ? "video" : selectedKind, player.position) === selected ? selected : "";
        if (!id) id = Project.clipAt(player.position);
        if (!id) { toast("Ustaw głowicę na klipie, który chcesz podzielić"); return; }
        const second = Project.split(id, player.position);
        if (!second) toast("Za blisko krawędzi klipu");
    }
    function removeSelected() {
        if (!selected) return;
        Project.remove(selected);
        selected = "";
    }
    function addText() {
        selected = Project.addText(player.position);
        inspector.focusText();
    }
    function addTextFocus() { inspector.focusText() }
    readonly property string clipTab: inspector.clipTab
    function showTransition(id) { selected = id; inspector.clipTab = "trans"; }
    function runMenu(a) {
        if (a === "split") splitAtPlayhead();
        else if (a === "delete") removeSelected();
        else if (a === "import") importRequested();
        else if (a === "mlt") mltDialog.open();
        else if (a === "home") Project.closeProject();
    }
    function itemMenu(id, item, x, y) {
        selected = id;
        const p = item.mapToItem(null, x, y);
        menuRequested([{ label: "Podziel w miejscu głowicy", icon: "scissors", shortcut: "S", action: "split" },
                       { separator: true },
                       { label: "Usuń", icon: "trash", shortcut: "Delete", action: "delete", danger: true }], p.x, p.y);
    }

    FileDialog {
        id: mltDialog
        title: "Zapisz projekt MLT (Kdenlive, Shotcut)"
        fileMode: FileDialog.SaveFile
        currentFolder: "file://" + Project.videosDir()
        selectedFile: "file://" + Project.videosDir() + "/" + Project.name + ".mlt"
        nameFilters: ["Projekt MLT (*.mlt)"]
        onAccepted: ed.toast(Project.saveMlt(String(selectedFile)) ? "Zapisano projekt MLT" : "Nie udało się zapisać pliku")
    }

    // Do testów (ASTER_OPEN)
    function test(what, arg) {
        if (what.startsWith("text:")) { selected = Project.addText(player.position, arg); }
        else if (what.startsWith("select:")) { const c = Project.clips[Number(arg)]; if (c) selected = c.id; }
        else if (what.startsWith("selecttext:")) { const t = Project.texts[Number(arg)]; if (t) selected = t.id; }
        else if (what.startsWith("selectmusic:")) { const t = Project.music[Number(arg)]; if (t) selected = t.id; }
        else if (what.startsWith("seek:")) player.seek(Number(arg));
        else if (what === "split") splitAtPlayhead();
        else if (what === "play") player.play();
        else if (what === "pause") player.pause();
        else if (what === "zoom:+") timeline.zoom(1.5);
        else if (what === "zoom:-") timeline.zoom(1 / 1.5);
        else if (what.startsWith("style:")) Project.setValue(selected, "style", arg);
        else if (what.startsWith("fade:")) Project.setValue(selected, "fade", Number(arg));
        else if (what.startsWith("speed:")) Project.setValue(selected, "speed", Number(arg));
        else if (what.startsWith("volume:")) Project.setValue(selected, "volume", Number(arg));
        else if (what.startsWith("look:")) { Project.setValue(selected, "look", arg); inspector.clipTab = "look"; }
        else if (what.startsWith("anim:")) Project.setValue(selected, "anim", arg);
        else if (what.startsWith("option:")) Project.setOption(arg, true);
        else if (what.startsWith("tab:")) inspector.clipTab = arg;
        else if (what.startsWith("trans:")) { Project.setValue(selected, "trans", arg); inspector.clipTab = "trans"; }
        else if (what.startsWith("motion:")) { Project.setValue(selected, "motion", arg); inspector.clipTab = "frame"; }
        else if (what.startsWith("fit:")) { Project.setValue(selected, "fit", arg); inspector.clipTab = "frame"; }
        else if (what.startsWith("format:")) Project.setOption("format", arg);
        else if (what.startsWith("textpos:")) { const v = arg.split(","); Project.setValue(selected, "pos", { x: Number(v[0]), y: Number(v[1]) }); }
        else if (what.startsWith("textscale:")) Project.setValue(selected, "scale", Number(arg));
        else if (what.startsWith("textcolor:")) Project.setValue(selected, "color", arg);
        else if (what.startsWith("overlay:")) selected = Project.addOverlay(arg, player.position);
        else if (what.startsWith("ov:")) { const kv = arg.split("="); Project.setValue(selected, kv[0], isNaN(Number(kv[1])) ? (kv[1] === "true" ? true : kv[1]) : Number(kv[1])); }
        else if (what.startsWith("ovpos:")) { const v = arg.split(","); Project.setValue(selected, "pos", { x: Number(v[0]), y: Number(v[1]) }); }
        else if (what === "deselect") selected = "";
        else if (what === "captions") openCaptions();
        else if (what.startsWith("captionsstart:")) { const a = (arg + ",zolty,brak").split(","); openCaptions(); Captions.start(a[0], "pl", a[1], a[2]); }
        else if (what === "export") exportSheet.open();
        else if (what.startsWith("exportstart:")) { exportSheet.open(); exportSheet.startWhenReady(arg); }
        else if (what === "menu") itemMenu(selected, timeline, 300, 120);
    }

    // ——— Skróty ———
    readonly property bool keys: visible && !exportSheet.shown && !captionsSheet.shown
    function openCaptions() { player.pause(); captionsSheet.open(); }
    Shortcut { sequence: "Space"; enabled: ed.keys; onActivated: player.toggle() }
    Shortcut { sequence: "S"; enabled: ed.keys; onActivated: ed.splitAtPlayhead() }
    Shortcut { sequences: [StandardKey.Delete, "Backspace"]; enabled: ed.keys; onActivated: ed.removeSelected() }
    Shortcut { sequence: "Left"; enabled: ed.keys; onActivated: player.step(-1) }
    Shortcut { sequence: "Right"; enabled: ed.keys; onActivated: player.step(1) }
    Shortcut { sequence: "Shift+Left"; enabled: ed.keys; onActivated: player.step(-Project.fps) }
    Shortcut { sequence: "Shift+Right"; enabled: ed.keys; onActivated: player.step(Project.fps) }
    Shortcut { sequence: "Home"; enabled: ed.keys; onActivated: { player.pause(); player.seek(0); } }
    Shortcut { sequence: "End"; enabled: ed.keys; onActivated: { player.pause(); player.seek(Project.duration - 1); } }
    Shortcut { sequences: [StandardKey.Undo]; enabled: ed.keys; onActivated: Project.undo() }
    Shortcut { sequences: [StandardKey.Redo, "Ctrl+Y"]; enabled: ed.keys; onActivated: Project.redo() }
    Shortcut { sequence: "T"; enabled: ed.keys; onActivated: ed.addText() }
    Shortcut { sequences: ["+", "="]; enabled: ed.keys; onActivated: timeline.zoom(1.4) }
    Shortcut { sequence: "-"; enabled: ed.keys; onActivated: timeline.zoom(1 / 1.4) }
    Shortcut { sequence: "Ctrl+I"; enabled: ed.keys; onActivated: ed.importRequested() }
    Shortcut { sequence: "Ctrl+E"; enabled: ed.keys; onActivated: exportSheet.open() }
    Shortcut { sequence: "Escape"; enabled: ed.keys; onActivated: ed.selected = "" }

    // ——— Pasek u góry ———
    Item {
        id: topBar
        width: parent.width; height: 58
        z: 5
        DragHandler { target: null; onActiveChanged: if (active) ed.window.startSystemMove() }
        TapHandler { onDoubleTapped: if (ed.window.visibility === Window.Maximized) ed.window.showNormal(); else ed.window.showMaximized() }

        Row {
            x: 14; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            ToolBtn { icon: "back"; onClicked: Project.closeProject() }
            Item {
                width: Math.min(nameInput.contentWidth + 16, 320); height: 32
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    anchors.fill: parent; radius: 8
                    color: nameInput.activeFocus ? Theme.fill : nameHover.hovered ? Theme.hover : "transparent"
                    border.width: nameInput.activeFocus ? 1 : 0
                    border.color: Theme.accentAlpha(0.6)
                }
                HoverHandler { id: nameHover; cursorShape: Qt.IBeamCursor }
                TextInput {
                    id: nameInput
                    x: 8; width: 304
                    anchors.verticalCenter: parent.verticalCenter
                    text: Project.name
                    color: Theme.text
                    selectionColor: Theme.accentSoft
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                    clip: true
                    onEditingFinished: { Project.name = text; focus = false; }
                    Keys.onEscapePressed: { text = Project.name; focus = false; }
                }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: fmtText.implicitWidth + 14; height: 22; radius: 7
                color: Theme.fill
                Text { id: fmtText; anchors.centerIn: parent; text: Project.format; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: 2
            ToolBtn { icon: "undo"; enabled: Project.canUndo; onClicked: Project.undo() }
            ToolBtn { icon: "undo"; enabled: Project.canRedo; onClicked: Project.redo(); transform: Scale { xScale: -1; origin.x: 17 } }
        }

        Row {
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            ToolBtn {
                anchors.verticalCenter: parent.verticalCenter
                icon: "more"
                onClicked: {
                    const p = mapToItem(null, -200, height + 6);
                    ed.menuRequested([{ label: "Dodaj multimedia…", icon: "plus", shortcut: "Ctrl+I", action: "import" },
                                      { label: "Zapisz jako projekt MLT…", icon: "doc", action: "mlt" },
                                      { separator: true },
                                      { label: "Wszystkie projekty", icon: "grid", action: "home" }], p.x, p.y);
                }
            }
            HoverButton {
                anchors.verticalCenter: parent.verticalCenter
                width: exportRow.implicitWidth + 28; height: 34; radius: 17
                baseColor: Theme.accent
                color: hovered ? Qt.lighter(Theme.accent, 1.12) : baseColor
                enabled: Project.duration > 0
                opacity: enabled ? 1 : 0.5
                onClicked: exportSheet.open()
                Row {
                    id: exportRow
                    anchors.centerIn: parent
                    spacing: 7
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.upload; size: 15; stroke: 2; color: "white" }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Eksportuj"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                }
            }
            WindowButtons { window: ed.window; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    // ——— Środek: multimedia, podgląd, ustawienia ———
    Item {
        id: body
        y: topBar.height
        width: parent.width
        height: parent.height - topBar.height - timeline.height

        // Multimedia projektu
        Item {
            id: mediaPanel
            width: 232; height: parent.height
            Text {
                x: 18; y: 6
                text: "Multimedia"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            }
            ToolBtn { x: parent.width - width - 10; y: 0; icon: "plus"; onClicked: ed.importRequested() }

            GridView {
                id: mediaGrid
                x: 12; y: 40
                width: parent.width - 18; height: parent.height - 48
                cellWidth: Math.floor(width / 2); cellHeight: 96
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: Project.media
                delegate: MediaTile {
                    required property var modelData
                    width: mediaGrid.cellWidth - 8
                    info: modelData
                }
            }
            Column {
                visible: Project.media.length === 0
                anchors.centerIn: mediaGrid
                width: parent.width - 40
                spacing: 10
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 54; height: 54; radius: 16
                    color: Theme.fill
                    Icon { anchors.centerIn: parent; d: Icons.plus; size: 24; color: Theme.text2 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ed.importRequested() }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Przeciągnij tu filmy, zdjęcia i muzykę albo kliknij „+”"
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
                }
            }
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }
        }

        // Podgląd
        Item {
            id: stage
            x: mediaPanel.width
            width: parent.width - mediaPanel.width - inspector.width
            height: parent.height
            readonly property real ratio: Project.width / Project.height
            readonly property real availW: width - 40
            readonly property real availH: height - 66

            Rectangle {
                id: screen
                anchors.horizontalCenter: parent.horizontalCenter
                y: 6
                width: Math.max(10, Math.min(stage.availW, stage.availH * stage.ratio))
                height: width / stage.ratio
                radius: 10
                color: "black"
                clip: true
                PreviewView {
                    anchors.fill: parent
                    player: player
                    visible: Project.duration > 0
                }
                TextHandle {
                    anchors.fill: parent
                    visible: ed.selectedKind === "text" || ed.selectedKind === "overlay"
                }
                Column {
                    visible: Project.duration === 0
                    anchors.centerIn: parent
                    width: parent.width - 32
                    spacing: 10
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; d: Icons.clapper; size: 34; stroke: 1.5; color: "#8A90A0" }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: "Dodaj filmy i zdjęcia — przeciągnij je na okno"
                        color: "#C9CED8"; font.family: Theme.font; font.pixelSize: 13
                    }
                    HoverButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: addLabel.implicitWidth + 26; height: 32; radius: 16
                        baseColor: Qt.rgba(1, 1, 1, 0.14)
                        onClicked: ed.importRequested()
                        Text { id: addLabel; anchors.centerIn: parent; text: "Dodaj multimedia…"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                    }
                }
            }

            // Sterowanie odtwarzaniem
            Item {
                anchors.top: screen.bottom; anchors.topMargin: 8
                width: parent.width; height: 44
                Text {
                    anchors.right: controls.left; anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: Project.time(player.position)
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium; font.features: { "tnum": 1 }
                }
                Row {
                    id: controls
                    anchors.centerIn: parent
                    spacing: 4
                    ToolBtn { icon: "prev"; onClicked: { player.pause(); player.seek(0); } }
                    ToolBtn { icon: "back"; onClicked: player.step(-1) }
                    HoverButton {
                        width: 40; height: 40; radius: 20
                        baseColor: Theme.fill
                        onClicked: player.toggle()
                        Icon {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: player.playing ? 0 : 1
                            d: player.playing ? Icons.pause : Icons.play
                            size: 18; color: Theme.text; fill: Theme.text
                        }
                    }
                    ToolBtn { icon: "chevronRight"; onClicked: player.step(1) }
                    ToolBtn { icon: "next"; onClicked: { player.pause(); player.seek(Project.duration - 1); } }
                }
                Text {
                    anchors.left: controls.right; anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: Project.time(Project.duration)
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: 13; font.features: { "tnum": 1 }
                }
            }
        }

        Inspector {
            id: inspector
            anchors.right: parent.right
            width: 272; height: parent.height
            selected: ed.selected
            kind: ed.selectedKind
            editor: ed
        }
    }

    Timeline {
        id: timeline
        anchors.bottom: parent.bottom
        width: parent.width; height: 276 + timeline.overlayH - 36
        player: player
        editor: ed
    }

    CaptionsSheet {
        id: captionsSheet
        anchors.fill: parent
        z: 50
        onToast: (text) => ed.toast(text)
    }

    ExportSheet {
        id: exportSheet
        anchors.fill: parent
        z: 50
        onToast: (text) => ed.toast(text)
    }

    // Ramka zaznaczonego napisu na podglądzie: przeciągnij, żeby przesunąć (przyciąga do środka kadru),
    // uchwyt w rogu zmienia wielkość
    component TextHandle: Item {
        id: th
        readonly property bool isOverlay: ed.selectedKind === "overlay"
        readonly property var info: isOverlay && Project.revision >= 0 ? Project.item(ed.selected) : ({})
        // Prostokąt w ułamkach kadru: napis — z C++, nakładka — z położenia, wielkości i proporcji
        readonly property var box: ed.selectedKind === "text" && Project.revision >= 0 ? Project.textBox(ed.selected)
                                   : isOverlay ? ({ x: info.x / 100, y: info.y / 100, w: info.scale, h: info.scale * Project.width / info.aspect / Project.height })
                                   : ({ x: 0.5, y: 0.5, w: 0, h: 0 })
        property real dx: 0
        property real dy: 0
        property real dscale: 1
        property bool snapX: false
        property bool snapY: false
        readonly property real cx: box.x * width + dx
        readonly property real cy: box.y * height + dy
        Rectangle {      // linie środka kadru przy przyciąganiu
            visible: th.snapX
            x: th.width / 2 - 0.5; width: 1; height: th.height
            color: "#FFD84D"
        }
        Rectangle {
            visible: th.snapY
            y: th.height / 2 - 0.5; height: 1; width: th.width
            color: "#FFD84D"
        }
        Rectangle {
            id: frameRect
            width: Math.max(30, th.box.w * th.width * th.dscale + 12)
            height: Math.max(20, th.box.h * th.height * th.dscale + 8)
            x: th.cx - width / 2
            y: th.cy - height / 2
            rotation: th.isOverlay ? (th.info.rotation || 0) : 0
            color: moveArea.pressed ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            radius: 6
            border.width: 1.5
            border.color: "white"
            MouseArea {
                id: moveArea
                anchors.fill: parent
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.SizeAllCursor
                preventStealing: true
                property point start
                onPressed: (e) => { start = mapToItem(th, e.x, e.y); }
                onPositionChanged: (e) => {
                    const p = mapToItem(th, e.x, e.y);
                    let nx = th.box.x * th.width + p.x - start.x, ny = th.box.y * th.height + p.y - start.y;
                    th.snapX = Math.abs(nx - th.width / 2) < 6;
                    th.snapY = Math.abs(ny - th.height / 2) < 6;
                    if (th.snapX) nx = th.width / 2;
                    if (th.snapY) ny = th.height / 2;
                    th.dx = nx - th.box.x * th.width;
                    th.dy = ny - th.box.y * th.height;
                }
                onReleased: {
                    if (Math.abs(th.dx) > 1 || Math.abs(th.dy) > 1)
                        Project.setValue(ed.selected, "pos", { x: th.cx / th.width * 100, y: th.cy / th.height * 100 });
                    th.dx = 0; th.dy = 0; th.snapX = false; th.snapY = false;
                }
            }
            Rectangle {      // uchwyt wielkości
                x: parent.width - width / 2; y: parent.height - height / 2
                width: 14; height: 14; radius: 7
                color: "white"
                border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.3)
                MouseArea {
                    anchors.fill: parent; anchors.margins: -4
                    cursorShape: Qt.SizeFDiagCursor
                    preventStealing: true
                    property real startX
                    onPressed: (e) => { startX = mapToItem(th, e.x, 0).x; }
                    onPositionChanged: (e) => {
                        const d = mapToItem(th, e.x, 0).x - startX;
                        th.dscale = Math.max(0.3, 1 + 2 * d / Math.max(40, frameRect.width));
                    }
                    onReleased: {
                        const info = Project.item(ed.selected);
                        if (Math.abs(th.dscale - 1) > 0.02) Project.setValue(ed.selected, "scale", (info.scale || 1) * th.dscale);
                        th.dscale = 1;
                    }
                }
            }
        }
    }

    // Kafelek w multimediach: klik — zaznacz, dwuklik albo przeciągnięcie na oś — dodaj
    component MediaTile: Item {
        id: tile
        property var info
        height: 90
        Rectangle {
            id: thumbBox
            width: parent.width; height: 62
            radius: 8
            color: tile.info.kind === "audio" ? "#2FB38A" : (Theme.dark ? "#1B1D24" : "#E4E7EE")
            clip: true
            Image {
                anchors.fill: parent
                visible: tile.info.kind !== "audio"
                source: tile.info.thumb
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.height: 90
            }
            Icon { visible: tile.info.kind === "audio"; anchors.centerIn: parent; d: Icons.music; size: 22; color: "white" }
            Rectangle {
                visible: tile.info.kind !== "image"
                anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 4
                width: durText.implicitWidth + 8; height: 16; radius: 5
                color: Qt.rgba(0, 0, 0, 0.6)
                Text { id: durText; anchors.centerIn: parent; text: Project.time(tile.info.frames, false); color: "white"; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold }
            }
            Rectangle {
                anchors.fill: parent; radius: 8
                color: "transparent"
                border.width: tileArea.containsMouse ? 2 : 0
                border.color: Theme.accent
            }
            Rectangle {
                visible: tileArea.containsMouse
                anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 4
                width: 22; height: 22; radius: 11
                color: Theme.accent
                Icon { anchors.centerIn: parent; d: Icons.plus; size: 14; stroke: 2.2; color: "white" }
            }
        }
        Text {
            y: 66
            width: parent.width
            text: tile.info.name
            elide: Text.ElideMiddle
            color: Theme.text2
            font.family: Theme.font; font.pixelSize: 11
        }
        MouseArea {
            id: tileArea
            anchors.fill: thumbBox
            hoverEnabled: true
            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            drag.target: ghost
            drag.threshold: 6
            onPressed: (e) => {
                const p = mapToItem(ed, e.x, e.y);
                ghost.x = p.x - ghost.width / 2; ghost.y = p.y - ghost.height / 2;
                ghost.info = tile.info;
            }
            onClicked: Project.addFromMedia(tile.info.path, ed.insertFrame())
            onReleased: {
                if (!drag.active) return;
                const p = ghost.mapToItem(timeline, ghost.width / 2, ghost.height / 2);
                if (timeline.contains(Qt.point(p.x, p.y))) {
                    if (timeline.trackAtY(p.y) === "overlay" && tile.info.kind !== "audio")
                        ed.selected = Project.addOverlay(tile.info.path, timeline.frameAtX(p.x));
                    else
                        Project.addFromMedia(tile.info.path, timeline.frameAtX(p.x));
                }
                ghost.info = null;
            }
            onCanceled: ghost.info = null
        }
    }

    // Miniatura przeciąganego kafelka
    Rectangle {
        id: ghost
        property var info: null
        visible: info !== null && (ghost.x !== 0 || ghost.y !== 0)
        width: 96; height: 56; radius: 8
        z: 100
        opacity: 0.85
        color: info && info.kind === "audio" ? "#2FB38A" : "#1B1D24"
        border.width: 2; border.color: Theme.accent
        clip: true
        Image { anchors.fill: parent; anchors.margins: 2; source: ghost.info && ghost.info.kind !== "audio" ? ghost.info.thumb : ""; fillMode: Image.PreserveAspectCrop; sourceSize.height: 90 }
    }
}
