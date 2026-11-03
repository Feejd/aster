pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Montaz

// Oś czasu: linijka, ścieżka wideo (klipy jeden za drugim), tekst i muzyka.
// Krawędzie klipów przeciąga się, żeby je przyciąć, a środek — żeby przesunąć.
Item {
    id: tl
    property Player player
    property var editor            // Editor (typ rekurencyjny — qmllint go nie przyjmuje)

    property real ppf: 3                     // pikseli na klatkę
    property bool autoFit: true              // dopasowuj skalę do długości filmu, dopóki ktoś nie przybliży sam
    readonly property int head: 46           // kolumna z ikonami ścieżek
    readonly property int pad: 10
    readonly property int rulerH: 26
    readonly property int videoY: rulerH + 8
    readonly property int videoH: 64
    readonly property int overlayY: videoY + videoH + 6
    // Nakładki nachodzące na siebie w czasie dostają osobne wiersze (najwyżej 4)
    function lanesFor(items) {
        const lanes = [], ends = [];
        const list = items.slice().sort((a, b) => a.start - b.start);
        for (const o of list) {
            let l = 0;
            while (l < ends.length && ends[l] > o.start) l++;
            l = Math.min(l, 3);
            ends[l] = Math.max(ends[l] || 0, o.start + o.length);
            lanes[o.id] = l;
        }
        return { map: lanes, count: Math.max(1, ends.length) };
    }
    readonly property var overlayLanes: lanesFor(Project.overlays)
    // Muzyka i lektor nachodzące na siebie też dostają osobne wiersze
    readonly property var musicLanes: lanesFor(Project.music)
    readonly property int musicLaneH: musicLanes.count > 1 ? 30 : 42
    readonly property int laneH: overlayLanes.count > 1 ? 28 : 36
    readonly property int overlayH: laneH * overlayLanes.count
    readonly property int textY: overlayY + overlayH + 6
    readonly property int textH: 32
    readonly property int musicY: textY + textH + 6
    readonly property int musicH: musicLaneH * musicLanes.count
    readonly property color videoColor: Theme.dark ? "#2A2E39" : "#C9CFDB"
    readonly property color textColor: "#8B6CF6"
    readonly property color musicColor: "#24A57E"
    readonly property color overlayColor: "#D9792B"
    readonly property color voiceColor: "#D9467A"
    // Ścieżka pod punktem (y we współrzędnych osi czasu): "video", "overlay", "text", "music"
    function trackAtY(y) {
        const cy = y - bar.height;
        if (cy >= overlayY - 3 && cy < overlayY + overlayH + 3) return "overlay";
        if (cy >= textY - 3 && cy < textY + textH + 3) return "text";
        if (cy >= musicY - 3) return "music";
        return "video";
    }

    function xOf(frame) { return pad + frame * ppf }
    function frameAtX(x) {          // x we współrzędnych osi czasu
        return Math.max(0, Math.round((x - head - pad + flick.contentX) / ppf));
    }
    function fit() {
        ppf = Math.max(0.05, Math.min(12, (flick.width - 2 * pad - 60) / Math.max(Project.duration * 1.08, 6 * Project.fps)));
        flick.contentX = 0;
    }
    function zoom(k) {
        autoFit = false;
        const at = xOf(player.position) - flick.contentX;
        ppf = Math.max(0.05, Math.min(30, ppf * k));
        flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, xOf(player.position) - at));
    }
    // Przyciąganie do głowicy i krawędzi innych elementów (8 px)
    function snap(frame, exceptId) {
        let best = frame, dist = 8 / ppf;
        const targets = [0, player.position];
        for (const c of Project.clips) if (c.id !== exceptId) targets.push(c.start, c.start + c.length);
        for (const t of Project.texts) if (t.id !== exceptId) targets.push(t.start, t.start + t.length);
        for (const m of Project.music) if (m.id !== exceptId) targets.push(m.start, m.start + m.length);
        for (const o of Project.overlays) if (o.id !== exceptId) targets.push(o.start, o.start + o.length);
        for (const t of targets) if (Math.abs(t - frame) < dist) { dist = Math.abs(t - frame); best = t; }
        return best;
    }
    // Ścieżka wideo: gdzie trafi przesuwany klip
    function dropIndex(id, centerFrame) {
        let i = 0;
        for (const c of Project.clips) if (c.id !== id && c.start + c.length / 2 < centerFrame) i++;
        return i;
    }
    function dropX(id, index) {
        const others = Project.clips.filter(c => c.id !== id);
        if (others.length === 0) return xOf(0);
        if (index >= others.length) { const l = others[others.length - 1]; return xOf(l.start + l.length); }
        return xOf(others[index].start);
    }

    Connections {
        target: Project
        function onOpenChanged() { tl.autoFit = true; }
        function onChanged() { if (tl.autoFit && Project.duration > 0) tl.fit(); }
    }
    Connections {
        target: tl.player
        function onPositionChanged() {
            if (!tl.player.playing) return;
            const x = tl.xOf(tl.player.position);
            if (x > flick.contentX + flick.width - 40 || x < flick.contentX)
                flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, x - 60));
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.dark ? Qt.rgba(0, 0, 0, 0.28) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.035) }
    Rectangle { width: parent.width; height: 1; color: Theme.line }

    // ——— Pasek narzędzi osi ———
    Item {
        id: bar
        width: parent.width; height: 42
        Row {
            x: 12; anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            BarButton { icon: "scissors"; label: "Podziel"; hint: "S"; enabled: Project.duration > 0; onClicked: tl.editor.splitAtPlayhead() }
            BarButton { icon: "trash"; label: "Usuń"; enabled: tl.editor.selected !== ""; onClicked: tl.editor.removeSelected() }
            Rectangle { width: 1; height: 20; color: Theme.line; anchors.verticalCenter: parent.verticalCenter }
            BarButton { icon: "textSize"; label: "Tekst"; hint: "T"; onClicked: tl.editor.addText() }
            BarButton { icon: "image"; label: "Nakładka"; enabled: Project.duration > 0; onClicked: tl.editor.overlayRequested() }
            BarButton { icon: "music"; label: "Muzyka"; onClicked: tl.editor.importRequested() }
            BarButton { icon: "mic"; label: "Lektor"; enabled: Project.duration > 0; onClicked: tl.editor.openVoice() }
            BarButton { icon: "captions"; label: "Napisy z mowy"; visible: Captions.available; enabled: Project.clips.length > 0; onClicked: tl.editor.openCaptions() }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            ToolBtn { icon: "minus"; onClicked: tl.zoom(1 / 1.5) }
            HoverButton {
                width: fitText.implicitWidth + 18; height: 32
                onClicked: { tl.fit(); tl.autoFit = true; }
                Text { id: fitText; anchors.centerIn: parent; text: "Dopasuj"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
            }
            ToolBtn { icon: "plus"; onClicked: tl.zoom(1.5) }
        }
    }

    // ——— Ikony ścieżek ———
    Item {
        y: bar.height
        width: tl.head; height: parent.height - y
        TrackIcon { y: tl.videoY + (tl.videoH - height) / 2; icon: "film" }
        TrackIcon { y: tl.overlayY + (tl.overlayH - height) / 2; icon: "image" }
        TrackIcon { y: tl.textY + (tl.textH - height) / 2; icon: "textSize" }
        TrackIcon { y: tl.musicY + (tl.musicH - height) / 2; icon: "music" }
    }

    Flickable {
        id: flick
        x: tl.head; y: bar.height
        width: parent.width - tl.head; height: parent.height - y
        contentWidth: Math.max(width, tl.xOf(Project.duration + 10 * Project.fps))
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        interactive: false

        WheelHandler {
            acceptedModifiers: Qt.ControlModifier
            onWheel: (e) => tl.zoom(e.angleDelta.y > 0 ? 1.15 : 1 / 1.15)
        }
        WheelHandler {
            acceptedModifiers: Qt.NoModifier
            onWheel: (e) => {
                const d = Math.abs(e.angleDelta.x) > Math.abs(e.angleDelta.y) ? e.angleDelta.x : e.angleDelta.y;
                flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - d));
            }
        }

        Item {
            id: content
            width: flick.contentWidth; height: flick.height

            // Klik w puste miejsce: przesuń głowicę i odznacz
            MouseArea {
                anchors.fill: parent
                onPressed: (e) => { tl.editor.selected = ""; tl.player.pause(); tl.player.seek(Math.round((e.x - tl.pad) / tl.ppf)); }
                onPositionChanged: (e) => tl.player.seek(Math.round((e.x - tl.pad) / tl.ppf))
            }

            // Linijka
            Item {
                id: ruler
                width: parent.width; height: tl.rulerH
                readonly property int step: {
                    for (const s of [1, 2, 5, 10, 15, 30, 60, 120, 300, 600])
                        if (s * Project.fps * tl.ppf >= 70) return s * Project.fps;
                    return 1200 * Project.fps;
                }
                Repeater {
                    model: Math.ceil(content.width / (ruler.step * tl.ppf)) + 1
                    delegate: Item {
                        required property int index
                        x: tl.xOf(index * ruler.step)
                        height: ruler.height
                        Rectangle { y: ruler.height - 8; width: 1; height: 8; color: Theme.text2; opacity: 0.6 }
                        Repeater {
                            model: 4
                            delegate: Rectangle {
                                required property int index
                                x: (index + 1) * ruler.step * tl.ppf / 5
                                y: ruler.height - 4; width: 1; height: 4; color: Theme.text2; opacity: 0.35
                            }
                        }
                        Text {
                            x: 4; y: 3
                            text: Project.time(parent.index * ruler.step, false)
                            color: Theme.text2
                            font.family: Theme.font; font.pixelSize: 10; font.features: { "tnum": 1 }
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeHorCursor
                    onPressed: (e) => { tl.player.pause(); tl.player.seek(Math.round((e.x - tl.pad) / tl.ppf)); }
                    onPositionChanged: (e) => tl.player.seek(Math.round((e.x - tl.pad) / tl.ppf))
                }
            }

            // Tła ścieżek
            Rectangle { x: tl.pad; y: tl.videoY; width: parent.width - tl.pad; height: tl.videoH; radius: 8; color: Theme.fill }
            Rectangle { x: tl.pad; y: tl.overlayY; width: parent.width - tl.pad; height: tl.overlayH; radius: 8; color: Theme.fill; opacity: 0.6 }
            Rectangle { x: tl.pad; y: tl.textY; width: parent.width - tl.pad; height: tl.textH; radius: 8; color: Theme.fill; opacity: 0.6 }
            Rectangle { x: tl.pad; y: tl.musicY; width: parent.width - tl.pad; height: tl.musicH; radius: 8; color: Theme.fill; opacity: 0.6 }
            Text {
                visible: Project.clips.length === 0
                x: tl.pad + 14; y: tl.videoY + (tl.videoH - height) / 2
                text: "Przeciągnij tu filmy i zdjęcia"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
            Text {
                visible: Project.overlays.length === 0
                x: tl.pad + 14; y: tl.overlayY + (tl.overlayH - height) / 2
                text: "Nakładki — obraz w obrazie, naklejki, zielone tło: przeciągnij tu plik z multimediów"
                color: Theme.text2; opacity: 0.8; font.family: Theme.font; font.pixelSize: 11
            }
            Text {
                visible: Project.texts.length === 0
                x: tl.pad + 14; y: tl.textY + (tl.textH - height) / 2
                text: "Napisy — przycisk „Tekst” albo klawisz T"
                color: Theme.text2; opacity: 0.8; font.family: Theme.font; font.pixelSize: 11
            }
            Text {
                visible: Project.music.length === 0
                x: tl.pad + 14; y: tl.musicY + (tl.musicH - height) / 2
                text: "Muzyka — upuść plik MP3 albo kliknij „Muzyka”"
                color: Theme.text2; opacity: 0.8; font.family: Theme.font; font.pixelSize: 11
            }

            Repeater {
                model: Project.clips
                delegate: Block { required property var modelData; info: modelData; kind: "clip"; y: tl.videoY; height: tl.videoH }
            }
            Repeater {
                model: Project.overlays
                delegate: Block {
                    required property var modelData
                    info: modelData; kind: "overlay"
                    y: tl.overlayY + (tl.overlayLanes.map[modelData.id] || 0) * tl.laneH
                    height: tl.laneH - (tl.overlayLanes.count > 1 ? 2 : 0)
                }
            }
            Repeater {
                model: Project.texts
                delegate: Block { required property var modelData; info: modelData; kind: "text"; y: tl.textY; height: tl.textH }
            }
            Repeater {
                model: Project.music
                delegate: Block {
                    required property var modelData
                    info: modelData; kind: "music"
                    y: tl.musicY + (tl.musicLanes.map[modelData.id] || 0) * tl.musicLaneH
                    height: tl.musicLaneH - (tl.musicLanes.count > 1 ? 2 : 0)
                }
            }

            // Przyciski przejść na styku klipów
            Repeater {
                model: Project.clips.slice(1)
                delegate: Rectangle {
                    id: junction
                    required property var modelData
                    readonly property bool on: modelData.fade > 0
                    readonly property bool sel: tl.editor.selected === modelData.id && tl.editor.clipTab === "trans"
                    x: tl.xOf(modelData.start + modelData.fade / 2) - width / 2
                    y: tl.videoY + (tl.videoH - height) / 2
                    width: 22; height: 22; radius: 7
                    z: 15
                    rotation: 45
                    color: on ? (sel ? "#FFD84D" : "white") : (jArea.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.75))
                    border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.3)
                    Icon {
                        anchors.centerIn: parent
                        rotation: -45
                        d: junction.on ? Icons.contrast : Icons.plus
                        size: 12; stroke: 2
                        color: "#1E2230"
                    }
                    MouseArea {
                        id: jArea
                        anchors.fill: parent; anchors.margins: -3
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tl.editor.showTransition(junction.modelData.id)
                    }
                }
            }

            // Miejsce wstawienia przesuwanego klipu
            Rectangle {
                id: insertMark
                property bool shown: false
                visible: shown
                y: tl.videoY - 4; width: 3; height: tl.videoH + 8; radius: 1.5
                color: Theme.accent
                z: 20
            }

            // Głowica
            Item {
                x: tl.xOf(tl.player.position)
                width: 1; height: parent.height
                z: 30
                Rectangle { x: -1; y: 4; width: 2; height: parent.height - 4; color: "#FF4D5E" }
                Rectangle {
                    x: -7; y: 2; width: 14; height: 14; radius: 4
                    color: "#FF4D5E"
                }
            }
        }
    }

    // ——— Element na ścieżce ———
    component Block: Item {
        id: b
        property var info
        property string kind
        property int dl: 0                     // przycięcie lewej krawędzi (klatki osi)
        property int dr: 0                     // prawej krawędzi
        property real dx: 0                    // przesunięcie (piksele)
        property bool moving: false
        readonly property bool sel: tl.editor.selected === info.id
        readonly property int len: info.length
        readonly property int minLen: 6

        x: tl.xOf(info.start + dl) + dx
        width: Math.max(4, (len - dl + dr) * tl.ppf)
        z: moving ? 10 : (sel ? 2 : 1)
        opacity: moving ? 0.85 : 1

        // Granice przycinania
        function minDl() {
            if (kind === "clip") return info.kind === "image" ? -10 * Project.fps : -Math.floor(info.in / info.speed);
            if (kind === "text" || (kind === "overlay" && info.kind === "image")) return -info.start;
            return -Math.min(info.in, info.start);
        }
        function maxDr() {
            if (kind === "clip" && info.kind !== "image") return Math.floor((info.srcFrames - 1 - info.out) / info.speed);
            if (kind === "music" || (kind === "overlay" && info.kind !== "image")) return info.srcFrames - 1 - info.out;
            return 60 * 60 * Project.fps;
        }

        Rectangle {
            id: body
            anchors.fill: parent
            radius: 7
            color: b.kind === "clip" ? tl.videoColor : b.kind === "text" ? tl.textColor : b.kind === "overlay" ? tl.overlayColor
                   : b.info.voice ? tl.voiceColor : tl.musicColor
            clip: true

            // Taśma klatek
            Row {
                id: strip
                visible: b.kind === "clip"
                height: parent.height
                readonly property real thumbW: Math.max(40, Math.min(128, tl.videoH * Project.width / Project.height))
                Repeater {
                    model: b.kind === "clip" ? Math.min(200, Math.ceil(b.width / strip.thumbW)) : 0
                    delegate: Image {
                        required property int index
                        width: strip.thumbW; height: strip.height
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.height: 96
                        source: b.info.kind === "image" ? Project.thumb(b.info.path, 0)
                                : Project.thumb(b.info.path, Math.round((b.info.in + (index + 0.5) * width / tl.ppf * b.info.speed) / 10) * 10)
                    }
                }
            }
            Rectangle {
                visible: b.kind === "clip"
                width: parent.width; height: 22
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.55) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            // Miniatura nakładki
            Image {
                visible: b.kind === "overlay"
                x: 2; y: 2
                width: Math.min(parent.height * 1.4, parent.width - 4); height: parent.height - 4
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.height: 64
                source: b.kind === "overlay" ? Project.thumb(b.info.path, b.info.in + 5) : ""
            }
            // Kształt fali muzyki (cały utwór, przesunięty o przycięty początek)
            Image {
                visible: b.kind === "music"
                x: -(b.info.in + b.dl) * tl.ppf
                width: (b.info.srcFrames || 0) * tl.ppf; height: parent.height
                fillMode: Image.Stretch
                asynchronous: true
                sourceSize: Qt.size(1600, 64)
                source: b.kind === "music" ? Project.wave(b.info.path) : ""
                opacity: 0.9
            }
            // Przenikanie z poprzedniego klipu
            Rectangle {
                visible: b.kind === "clip" && b.info.fade > 0
                width: (b.info.fade || 0) * tl.ppf; height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.45) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                }
            }
            Row {
                x: b.kind === "overlay" ? Math.min(b.height * 1.4, b.width - 4) + 8 : 8
                y: b.kind === "clip" ? 4 : (parent.height - height) / 2
                width: parent.width - 16
                spacing: 5
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: b.kind === "text" || b.kind === "music"
                    d: b.kind === "text" ? Icons.textSize : b.info.voice ? Icons.mic : Icons.music
                    size: 13; stroke: 2; color: "white"
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, Math.min(implicitWidth, parent.width - (speedBadge.visible ? speedBadge.width + 5 : 0) - (b.kind === "text" || b.kind === "music" ? 18 : 0)))
                    text: b.kind === "text" ? b.info.text.replace(/\n/g, " ") : b.info.name
                    elide: Text.ElideRight
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                }
                Rectangle {
                    id: speedBadge
                    anchors.verticalCenter: parent.verticalCenter
                    visible: b.kind === "clip" && b.info.speed !== 1
                    width: speedText.implicitWidth + 8; height: 15; radius: 4
                    color: Qt.rgba(0, 0, 0, 0.45)
                    Text { id: speedText; anchors.centerIn: parent; text: String(b.info.speed).replace(".", ",") + "×"; color: "white"; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Bold }
                }
            }
            Text {
                visible: b.kind === "clip" && b.width > 70
                anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 5
                text: Project.time(b.len - b.dl + b.dr, false)
                color: "white"
                style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.5)
                font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: 7
            color: "transparent"
            border.width: b.sel ? 2 : 1
            border.color: b.sel ? (b.kind === "clip" ? "#FFD84D" : "white") : Qt.rgba(0, 0, 0, 0.25)
        }

        // Przesuwanie (i zaznaczanie)
        MouseArea {
            id: moveArea
            anchors.fill: parent
            anchors.leftMargin: 9; anchors.rightMargin: 9
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
            cursorShape: b.moving ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property real startX
            onPressed: (e) => {
                tl.editor.selected = b.info.id;
                if (e.button === Qt.RightButton) { tl.editor.itemMenu(b.info.id, moveArea, e.x, e.y); return; }
                startX = mapToItem(content, e.x, 0).x;
            }
            onPositionChanged: (e) => {
                if (!(e.buttons & Qt.LeftButton)) return;
                const d = mapToItem(content, e.x, 0).x - startX;
                if (!b.moving && Math.abs(d) < 4) return;
                b.moving = true;
                if (b.kind === "clip") {
                    b.dx = d;
                    const idx = tl.dropIndex(b.info.id, b.info.start + b.len / 2 + d / tl.ppf);
                    insertMark.x = tl.dropX(b.info.id, idx) - 1;
                    insertMark.shown = true;
                } else {
                    let s = Math.max(0, b.info.start + Math.round(d / tl.ppf));
                    const snapped = tl.snap(s, b.info.id);
                    if (snapped !== s) s = snapped;
                    else s = tl.snap(s + b.len, b.info.id) - b.len;
                    b.dx = (Math.max(0, s) - b.info.start) * tl.ppf;
                }
            }
            onReleased: {
                if (!b.moving) return;
                b.moving = false;
                insertMark.shown = false;
                if (b.kind === "clip") {
                    const idx = tl.dropIndex(b.info.id, b.info.start + b.len / 2 + b.dx / tl.ppf);
                    b.dx = 0;
                    Project.moveClip(b.info.id, idx);
                } else {
                    const s = b.info.start + Math.round(b.dx / tl.ppf);
                    b.dx = 0;
                    Project.moveItem(b.info.id, s);
                }
            }
            onDoubleClicked: if (b.kind === "text") tl.editor.addTextFocus()
        }

        // Przycinanie krawędzi
        Repeater {
            model: ["left", "right"]
            delegate: MouseArea {
                id: edge
                required property string modelData
                readonly property bool isLeft: modelData === "left"
                x: isLeft ? 0 : b.width - width
                width: Math.min(10, b.width / 3); height: b.height
                cursorShape: Qt.SizeHorCursor
                hoverEnabled: true
                preventStealing: true
                property real startX
                Rectangle {
                    anchors.centerIn: parent
                    width: 3; height: Math.min(22, parent.height - 10); radius: 1.5
                    color: "white"
                    opacity: edge.containsMouse || edge.pressed || b.sel ? 0.95 : 0
                }
                onPressed: (e) => { tl.editor.selected = b.info.id; startX = mapToItem(content, e.x, 0).x; }
                onPositionChanged: (e) => {
                    if (!pressed) return;
                    let d = Math.round((mapToItem(content, e.x, 0).x - startX) / tl.ppf);
                    if (isLeft) {
                        let edgeF = b.kind === "clip" ? b.info.start + d : tl.snap(b.info.start + d, b.info.id);
                        d = edgeF - b.info.start;
                        b.dl = Math.max(b.minDl(), Math.min(d, b.len + b.dr - b.minLen));
                    } else {
                        const edgeF = tl.snap(b.info.start + b.len + d, b.info.id);
                        d = edgeF - b.info.start - b.len;
                        b.dr = Math.min(b.maxDr(), Math.max(d, b.dl - b.len + b.minLen));
                    }
                }
                onReleased: {
                    const l = b.dl, r = b.dr;
                    b.dl = 0; b.dr = 0;
                    Project.trim(b.info.id, l, r);
                }
            }
        }
    }

    component TrackIcon: Rectangle {
        property string icon
        x: 10; width: 28; height: 28; radius: 8
        color: Theme.fill
        Icon { anchors.centerIn: parent; d: Icons[parent.icon]; size: 15; color: Theme.text2 }
    }

    component BarButton: HoverButton {
        id: bb
        property string icon
        property string label
        property string hint
        width: bbRow.implicitWidth + 18; height: 32
        opacity: enabled ? 1 : 0.4
        Row {
            id: bbRow
            anchors.centerIn: parent
            spacing: 6
            Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons[bb.icon]; size: 15; color: Theme.text }
            Text { anchors.verticalCenter: parent.verticalCenter; text: bb.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
        }
    }
}
