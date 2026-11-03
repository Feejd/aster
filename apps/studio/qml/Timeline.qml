pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Aster.Ui
import Aster.Studio

// Oś czasu: z lewej nagłówki ścieżek (nagrywanie, wycisz, solo), z prawej linijka taktów i pasy z klipami.
// Klipy przesuwa się (także między ścieżkami), przycina za brzegi, a zapętlony klip — wydłuża prawym brzegiem.
// Górny pasek linijki ustawia region pętli odtwarzania (przeciągnij; brzegi da się przesuwać).
// Kółko: przewijanie w pionie, Shift+kółko — w poziomie, Ctrl+kółko — powiększenie. Pliki dźwiękowe można upuścić na pas.
Item {
    id: tl
    property var colors: []
    property real pxPerBeat: 36
    property real scrollX: 0
    property int snapDiv: 1                  // -1 bez przyciągania, 0 takt, 1 miara, 2 ósemka, 4 szesnastka
    readonly property real pps: pxPerBeat * Studio.bpm / 60
    readonly property real beatSec: 60 / Studio.bpm
    readonly property real barSec: beatSec * Studio.beatsPerBar
    readonly property int headerW: 236
    readonly property int rulerH: 30
    readonly property int trackH: 88
    readonly property real viewW: Math.max(1, width - headerW)
    readonly property real contentW: Math.max(viewW, (Math.max(Studio.duration, Studio.position) + barSec * 16) * pps)
    readonly property real maxScroll: Math.max(0, contentW - viewW)
    readonly property int count: Studio.tracks.length
    property int dropTrack: -2               // podświetlenie przy przeciąganiu plików

    signal clipMenu(var clip, int track, Item item, real x, real y, real at)
    signal trackMenu(int track, Item item, real x, real y)
    signal addTrackRequested(Item item, real x, real y)
    signal editPattern(int track)

    onScrollXChanged: if (scrollX > maxScroll || scrollX < 0) scrollX = Math.max(0, Math.min(maxScroll, scrollX))

    function color(i) { return colors.length ? colors[i % colors.length] : Theme.accent; }
    function snapUnit() { return snapDiv === 0 ? barSec : beatSec / Math.max(1, snapDiv); }
    function snapDelta(d, mods) { return (mods & Qt.ShiftModifier) || snapDiv < 0 ? d : Math.round(d / snapUnit()) * snapUnit(); }
    function snapAbs(t, mods) { return Math.max(0, (mods & Qt.ShiftModifier) || snapDiv < 0 ? t : Math.round(t / snapUnit()) * snapUnit()); }
    function zoom(factor, anchorX) {
        const t = (scrollX + anchorX) / pps;
        pxPerBeat = Math.max(4, Math.min(240, pxPerBeat * factor));
        scrollX = Math.max(0, t * pps - anchorX);
    }
    function reveal(t) {
        const px = t * pps;
        if (px < scrollX || px > scrollX + viewW - 40) scrollX = Math.max(0, px - 80);
    }

    // Głowica podąża za odtwarzaniem
    Connections {
        target: Studio
        function onPositionChanged() {
            if (!Studio.playing) return;
            const px = Studio.position * tl.pps;
            if (px > tl.scrollX + tl.viewW - 40 || px < tl.scrollX - 1) tl.scrollX = Math.max(0, px - 80);
        }
    }

    // ——— Róg: tytuł i nowa ścieżka ———
    Item {
        width: tl.headerW; height: tl.rulerH
        Text {
            x: 16; anchors.verticalCenter: parent.verticalCenter
            text: "ŚCIEŻKI"
            color: Theme.text2
            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.6
        }
        HoverButton {
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; radius: 7
            onClicked: tl.addTrackRequested(this, 0, height + 4)
            Icon { anchors.centerIn: parent; d: Icons.plus; size: 14; stroke: 2; color: Theme.text2 }
            Tip { shown: parent.hovered; text: "Nowa ścieżka (Ctrl+T)"; below: true }
        }
    }

    // ——— Linijka taktów ———
    Item {
        id: ruler
        x: tl.headerW
        width: tl.viewW; height: tl.rulerH
        clip: true
        readonly property real barPx: tl.barSec * tl.pps
        readonly property int step: barPx >= 56 ? 1 : barPx >= 28 ? 2 : barPx >= 14 ? 4 : 8
        readonly property int first: Math.floor(tl.scrollX / barPx / step) * step
        readonly property int shown: Math.ceil(width / barPx / step) + 2
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        Repeater {
            model: ruler.shown
            delegate: Item {
                id: mark
                required property int index
                readonly property int bar: ruler.first + index * ruler.step
                x: bar * ruler.barPx - tl.scrollX
                height: ruler.height
                Rectangle { anchors.bottom: parent.bottom; width: 1; height: 10; color: Theme.text2; opacity: 0.6 }
                Text {
                    x: 5; anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                    text: mark.bar + 1
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium; font.features: { "tnum": 1 }
                }
            }
        }
        // Region pętli odtwarzania
        Rectangle {
            readonly property real x0: Studio.cycleStart * tl.pps - tl.scrollX
            visible: Studio.cycleEnd > Studio.cycleStart
            x: x0; y: 2
            width: (Studio.cycleEnd - Studio.cycleStart) * tl.pps; height: 10; radius: 4
            color: Studio.cycle ? "#F5B83D" : Theme.fill
            border.width: 1; border.color: Studio.cycle ? "#D9961A" : Theme.edge
        }
        MouseArea {
            id: rulerArea
            anchors.fill: parent
            hoverEnabled: true
            readonly property bool inCycleBar: mouseY < 13
            cursorShape: inCycleBar ? (nearEdge(mouseX) !== "" ? Qt.SizeHorCursor : Qt.CrossCursor) : Qt.PointingHandCursor
            property string mode: ""            // seek | new | start | end
            property real anchorT: 0
            function at(x) { return Math.max(0, (x + tl.scrollX) / tl.pps); }
            function nearEdge(x) {
                if (Studio.cycleEnd <= Studio.cycleStart) return "";
                if (Math.abs(x - (Studio.cycleStart * tl.pps - tl.scrollX)) < 6) return "start";
                if (Math.abs(x - (Studio.cycleEnd * tl.pps - tl.scrollX)) < 6) return "end";
                return "";
            }
            onPressed: (e) => {
                if (e.y < 13) {
                    mode = nearEdge(e.x) || "new";
                    anchorT = mode === "start" ? Studio.cycleEnd : mode === "end" ? Studio.cycleStart : tl.snapAbs(at(e.x), e.modifiers);
                } else {
                    mode = "seek";
                    Studio.seek(at(e.x));
                }
            }
            onPositionChanged: (e) => {
                if (!pressed) return;
                if (mode === "seek") { Studio.seek(at(e.x)); return; }
                const t = tl.snapAbs(at(e.x), e.modifiers);
                if (Math.abs(t - anchorT) > 0.05) Studio.setCycle(Math.min(t, anchorT), Math.max(t, anchorT));
            }
            onReleased: mode = ""
        }
        Tip { shown: rulerArea.containsMouse && rulerArea.inCycleBar && !rulerArea.pressed; text: "Przeciągnij, żeby zaznaczyć fragment do ćwiczenia w pętli (C)"; below: true }
    }

    // ——— Ścieżki ———
    Flickable {
        id: vflick
        y: tl.rulerH
        width: parent.width; height: parent.height - y
        contentHeight: tl.count * tl.trackH + 56
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: false

        WheelHandler {
            acceptedModifiers: Qt.NoModifier
            orientation: Qt.Vertical
            onWheel: (e) => vflick.contentY = Math.max(0, Math.min(vflick.contentHeight - vflick.height, vflick.contentY - e.angleDelta.y / 2))
        }
        WheelHandler {
            acceptedModifiers: Qt.ShiftModifier
            onWheel: (e) => tl.scrollX -= (e.angleDelta.y || e.angleDelta.x) / 2
        }
        WheelHandler {
            orientation: Qt.Horizontal
            onWheel: (e) => tl.scrollX -= e.angleDelta.x / 2
        }
        WheelHandler {
            acceptedModifiers: Qt.ControlModifier
            onWheel: (e) => tl.zoom(e.angleDelta.y > 0 ? 1.15 : 1 / 1.15, Math.max(0, e.x - tl.headerW))
        }

        // Pasy z klipami
        Item {
            id: lanesClip
            x: tl.headerW
            width: tl.viewW; height: vflick.contentHeight
            clip: true

            Item {
                id: lanes
                x: -tl.scrollX
                width: tl.contentW; height: parent.height

                // Tło pasów (zaznaczona ścieżka jaśniejsza)
                Repeater {
                    model: tl.count
                    delegate: Rectangle {
                        required property int index
                        x: tl.scrollX; y: index * tl.trackH
                        width: tl.viewW; height: tl.trackH
                        color: index === tl.dropTrack ? Theme.accentSoft
                             : index === Studio.selectedTrack ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.03)) : "transparent"
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                    }
                }

                // Siatka: takty mocniej, miary słabiej
                Item {
                    id: grid
                    readonly property real beatPx: tl.beatSec * tl.pps
                    readonly property bool beats: beatPx >= 10
                    readonly property real unit: beats ? beatPx : beatPx * Studio.beatsPerBar
                    readonly property int first: Math.floor(tl.scrollX / unit)
                    height: tl.count * tl.trackH
                    Repeater {
                        model: Math.ceil(tl.viewW / grid.unit) + 2
                        delegate: Rectangle {
                            required property int index
                            readonly property int n: grid.first + index
                            readonly property bool bar: !grid.beats || n % Studio.beatsPerBar === 0
                            x: n * grid.unit
                            width: 1; height: grid.height
                            color: Theme.text
                            opacity: bar ? (Theme.dark ? 0.11 : 0.10) : (Theme.dark ? 0.045 : 0.04)
                        }
                    }
                }

                // Kliknięcie w puste miejsce: zaznacz ścieżkę i przestaw głowicę
                MouseArea {
                    width: parent.width; height: tl.count * tl.trackH
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: (e) => {
                        const ti = Math.floor(e.y / tl.trackH);
                        if (ti >= 0 && ti < tl.count) Studio.selectedTrack = ti;
                        Studio.selectedClip = 0;
                        if (e.button === Qt.LeftButton) Studio.seek(tl.snapAbs(e.x / tl.pps, e.modifiers));
                    }
                }

                Repeater {
                    model: Studio.tracks
                    delegate: Item {
                        id: lane
                        required property var modelData
                        required property int index
                        y: index * tl.trackH
                        width: lanes.width; height: tl.trackH
                        z: 2
                        Repeater {
                            model: lane.modelData.clips
                            delegate: ClipItem {
                                required property var modelData
                                cl: modelData
                                trackIndex: lane.index
                                tint: tl.color(lane.modelData.color)
                            }
                        }
                        // Nagrywany właśnie dźwięk
                        Rectangle {
                            id: liveClip
                            z: 20
                            visible: Studio.recording && lane.modelData.armed && Studio.position > Studio.recordStart
                            x: Studio.recordStart * tl.pps
                            y: 4
                            width: Math.max(2, (Studio.position - Studio.recordStart) * tl.pps)
                            height: tl.trackH - 8
                            radius: 8
                            color: Qt.rgba(0.9, 0.28, 0.3, 0.28)
                            border.width: 1; border.color: "#E5484D"
                            Text {
                                x: 8; y: 3
                                text: Studio.recordTake > 0 ? "● Nagrywanie — podejście " + Studio.recordTake : "● Nagrywanie"
                                color: "#E5484D"
                                font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                            }
                            Waveform {
                                readonly property real leftPx: Math.max(0, tl.scrollX - liveClip.x)
                                x: leftPx; y: 18
                                width: Math.max(0, Math.min(liveClip.width, tl.scrollX + tl.viewW - liveClip.x) - leftPx)
                                height: parent.height - 22
                                live: true
                                from: Studio.recordTakeOffset + leftPx / tl.pps
                                pxPerSec: tl.pps
                                color: "#E5484D"
                                version: Math.floor(Studio.position * 15)
                            }
                        }
                    }
                }

                // Odliczanie przed nagraniem
                Text {
                    visible: Studio.countingIn
                    x: tl.scrollX + (tl.viewW - width) / 2
                    y: Math.max(10, (Math.min(vflick.height, tl.count * tl.trackH) - height) / 2) + vflick.contentY
                    text: Math.max(1, Math.ceil((Studio.recordStart - Studio.position) / tl.beatSec - 0.001))
                    color: "#E5484D"
                    font.family: Theme.font; font.pixelSize: 96; font.weight: Font.Bold
                    z: 20
                }
            }

            // Podpowiedź w pustym projekcie
            Column {
                visible: Studio.duration === 0 && !Studio.recording && !Studio.busy
                x: (parent.width - width) / 2
                y: Math.min(tl.count * tl.trackH + 20, Math.max(20, vflick.height / 2 - 60))
                width: Math.min(420, parent.width - 40)
                spacing: 10
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Zacznij od nagrania albo pętli"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Zaznacz ścieżkę i naciśnij czerwony przycisk (R) — po odliczeniu taktu metronomu zacznie się nagrywanie. Pliki WAV, FLAC, MP3 i OGG przeciągnij prosto na ścieżkę."
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.25
                }
            }

            DropArea {
                anchors.fill: parent
                onEntered: (drag) => { drag.accepted = drag.hasUrls; }
                onPositionChanged: (drag) => { const ti = Math.floor(drag.y / tl.trackH); tl.dropTrack = ti < tl.count ? ti : -1; }
                onExited: tl.dropTrack = -2
                onDropped: (drop) => {
                    const ti = Math.floor(drop.y / tl.trackH);
                    tl.dropTrack = -2;
                    Studio.importFiles(drop.urls, ti < tl.count ? ti : -1, tl.snapAbs((drop.x + tl.scrollX) / tl.pps, 0));
                    drop.accept();
                }
            }
        }

        // Nagłówki ścieżek
        Column {
            width: tl.headerW
            Repeater {
                model: Studio.tracks
                delegate: TrackHeader {
                    required property var modelData
                    required property int index
                    track: modelData
                    trackIndex: index
                }
            }
            HoverButton {
                id: addRow
                x: 10; width: tl.headerW - 20; height: 40; radius: 10
                onClicked: tl.addTrackRequested(addRow, 0, height)
                Row {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.plus; size: 15; stroke: 2; color: Theme.text2 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Dodaj ścieżkę"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                }
            }
        }
    }

    // Linia między nagłówkami a pasami
    Rectangle { x: tl.headerW; width: 1; height: parent.height; color: Theme.line }

    // ——— Głowica ———
    Item {
        readonly property real px: Studio.position * tl.pps - tl.scrollX
        visible: px >= -1 && px <= tl.viewW + 1
        x: tl.headerW + px
        height: parent.height
        z: 30
        readonly property color c: Studio.recording ? "#E5484D" : Theme.accent
        Rectangle { x: -1; width: 2; height: parent.height; color: parent.c }
        Rectangle {
            x: -6; y: tl.rulerH - 12
            width: 12; height: 12; radius: 3
            rotation: 45
            color: parent.c
        }
    }

    // Poziomy pasek przewijania
    Rectangle {
        visible: tl.maxScroll > 0
        x: tl.headerW + 6 + (tl.viewW - 12 - width) * (tl.scrollX / Math.max(1, tl.maxScroll))
        anchors.bottom: parent.bottom; anchors.bottomMargin: 4
        width: Math.max(40, (tl.viewW - 12) * tl.viewW / tl.contentW)
        height: hbar.pressed || hbar.containsMouse ? 8 : 5; radius: height / 2
        color: Theme.text2
        opacity: hbar.pressed || hbar.containsMouse ? 0.6 : 0.3
        z: 31
        MouseArea {
            id: hbar
            anchors.fill: parent; anchors.margins: -4
            hoverEnabled: true
            property real startX: 0
            property real startScroll: 0
            onPressed: (e) => { startX = mapToItem(tl, e.x, 0).x; startScroll = tl.scrollX; }
            onPositionChanged: (e) => {
                if (!pressed) return;
                const dx = mapToItem(tl, e.x, 0).x - startX;
                tl.scrollX = startScroll + dx * tl.contentW / tl.viewW;
            }
        }
    }

    // ——— Nagłówek ścieżki ———
    component TrackHeader: Rectangle {
        id: th
        property var track
        property int trackIndex
        readonly property bool selected: Studio.selectedTrack === trackIndex
        readonly property color tint: tl.color(track.color)
        readonly property var mix: Studio.mix[trackIndex] || {}
        width: tl.headerW; height: tl.trackH
        color: selected ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.05)) : "transparent"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        Rectangle { x: 0; y: 6; width: 4; height: parent.height - 12; radius: 2; color: th.tint }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: Studio.selectedTrack = th.trackIndex
            onClicked: (e) => { if (e.button === Qt.RightButton) tl.trackMenu(th.trackIndex, th, e.x, e.y); }
            onDoubleClicked: nameEdit.start()
        }

        readonly property var kindInfo: ({
            audio: { icon: "mic", label: "Nagranie" },
            beat: { icon: "audioTrack", label: "Bit z pliku" },
            drums: { icon: "grid", label: "Bit" },
            bass: { icon: "audioTrack", label: "Bas 808" },
            keys: { icon: "music", label: "Akordy" },
            melody: { icon: "keyboard", label: "Melodia" }
        })[th.track.beat ? "beat" : th.track.kind] || { icon: "music", label: "" }
        readonly property string presetLabel: th.mix.preset ? (Studio.presets.find(p => p.id === th.mix.preset) || { label: "" }).label : ""

        // Ikona rodzaju ścieżki w kolorze ścieżki
        Rectangle {
            x: 14; y: 10
            width: 30; height: 30; radius: 9
            color: Qt.rgba(th.tint.r, th.tint.g, th.tint.b, Theme.dark ? 0.28 : 0.2)
            Icon { anchors.centerIn: parent; d: Icons[th.kindInfo.icon] || ""; size: 16; stroke: 2; color: Theme.text }
        }
        Text {
            id: nameText
            visible: !nameEdit.visible
            x: 52; y: 9
            width: parent.width - 90
            text: th.track.name
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
        }
        TextInput {
            id: nameEdit
            visible: false
            x: 52; y: 9
            width: parent.width - 90
            color: Theme.text
            selectionColor: Theme.accentSoft
            font: nameText.font
            function start() { text = th.track.name; visible = true; forceActiveFocus(); selectAll(); }
            onAccepted: { Studio.renameTrack(th.trackIndex, text); visible = false; }
            onActiveFocusChanged: if (!activeFocus && visible) { Studio.renameTrack(th.trackIndex, text); visible = false; }
            Keys.onEscapePressed: visible = false
        }
        Text {
            x: 52; y: 27
            width: parent.width - 90
            text: th.track.armed ? th.kindInfo.label + " · " + ["wejście L+P", "wejście L", "wejście P"][th.track.input]
                                 : th.kindInfo.label + (th.presetLabel && !th.kindInfo.label.includes(th.presetLabel) ? " · " + th.presetLabel : "")
            elide: Text.ElideRight
            color: Theme.text2
            font.family: Theme.font; font.pixelSize: 11
        }
        HoverButton {
            anchors.right: parent.right; anchors.rightMargin: 8
            y: 10
            width: 26; height: 26; radius: 7
            onClicked: { const p = mapToItem(th, 0, height); tl.trackMenu(th.trackIndex, th, p.x, p.y + 2); }
            Icon { anchors.centerIn: parent; d: Icons.more; size: 15; color: Theme.text2 }
            Tip { shown: parent.hovered; text: "Więcej" }
        }

        // M i S zawsze w tym samym miejscu; z prawej nagrywanie albo edycja wzoru
        Row {
            x: 14; y: 48
            spacing: 6
            MiniBtn {
                tip: "Wycisz (M)"
                on: !!th.mix.mute
                onColor: "#E8A317"
                label: "M"
                onClicked: Studio.setTrackMute(th.trackIndex, !th.mix.mute)
            }
            MiniBtn {
                tip: "Solo — słychać tylko tę ścieżkę"
                on: !!th.mix.solo
                onColor: "#2F80ED"
                label: "S"
                onClicked: Studio.setTrackSolo(th.trackIndex, !th.mix.solo)
            }
        }
        // Odsłuch w słuchawkach (z efektami ścieżki) — przy ścieżce gotowej do nagrania
        MiniBtn {
            id: monBtn
            visible: th.track.armed
            anchors.right: armBtn.left; anchors.rightMargin: 6
            y: 48
            tip: Studio.monitor ? "Słyszysz siebie w słuchawkach z efektami ścieżki — kliknij, żeby wyłączyć"
                                : "Słysz siebie w słuchawkach z efektami (np. autotune). Tylko w słuchawkach — w głośnikach zapiszczy"
            on: Studio.monitor
            onColor: Theme.accent
            onClicked: Studio.monitor = !Studio.monitor
            Icon { anchors.centerIn: parent; d: Icons.headphones; size: 14; stroke: 2; color: Studio.monitor ? "white" : Theme.text }
        }
        MiniBtn {
            id: armBtn
            visible: th.track.kind === "audio" && !th.track.beat
            anchors.right: parent.right; anchors.rightMargin: 14
            y: 48
            width: armRow.implicitWidth + 16
            tip: th.track.armed ? "Gotowa do nagrania — kliknij, żeby wyłączyć" : "Nagrywaj na tę ścieżkę"
            on: th.track.armed
            onColor: "#E5484D"
            onClicked: Studio.setTrackArmed(th.trackIndex, !th.track.armed)
            Row {
                id: armRow
                anchors.centerIn: parent
                spacing: 5
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 9; height: 9; radius: 4.5; color: th.track.armed ? "white" : "#E5484D" }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Nagrywaj"; color: th.track.armed ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }
            }
        }
        HoverButton {
            visible: th.track.kind !== "audio"
            anchors.right: parent.right; anchors.rightMargin: 14
            y: 48
            width: editRow.implicitWidth + 16; height: 24; radius: 7
            baseColor: Qt.rgba(th.tint.r, th.tint.g, th.tint.b, 0.3)
            color: hovered ? Qt.rgba(th.tint.r, th.tint.g, th.tint.b, 0.45) : baseColor
            onClicked: tl.editPattern(th.trackIndex)
            Row {
                id: editRow
                anchors.centerIn: parent
                spacing: 5
                Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.pencil; size: 12; stroke: 2; color: Theme.text }
                Text { anchors.verticalCenter: parent.verticalCenter; text: th.track.kind === "bass" ? "Nuty 808" : th.track.kind === "keys" ? "Akordy" : th.track.kind === "melody" ? "Piano roll" : "Beat Maker"; color: Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }
            }
            Tip { shown: parent.hovered; text: "Otwórz edytor (albo dwuklik na klipie)" }
        }

        // Poziom: wejście, gdy ścieżka czeka na nagranie, inaczej to, co gra
        Rectangle {
            x: 14; y: tl.trackH - 12
            width: parent.width - 28; height: 3; radius: 1.5
            color: Theme.fill
            readonly property real level: th.track.armed ? Studio.inputLevel : (Studio.levels[th.trackIndex] || 0)
            readonly property real pos: level <= 0 ? 0 : Math.max(0, Math.min(1, (20 * Math.log(level) / Math.LN10 + 60) / 60))
            Rectangle {
                width: parent.width * parent.pos; height: parent.height; radius: 2
                color: parent.level >= 0.99 ? "#E5484D" : parent.level > 0.5 ? "#E8A317" : "#30C26B"
            }
        }
    }

    component MiniBtn: HoverButton {
        id: mb
        property bool on: false
        property color onColor: Theme.accent
        property string label
        property string tip
        width: 28; height: 24; radius: 7
        baseColor: on ? onColor : Theme.fill
        color: on ? (hovered ? Qt.lighter(onColor, 1.1) : onColor) : (hovered ? Theme.hover : baseColor)
        Text {
            visible: mb.label !== ""
            anchors.centerIn: parent
            text: mb.label
            color: mb.on ? "white" : Theme.text
            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Bold
        }
        Tip { shown: mb.hovered; text: mb.tip }
    }

    // ——— Klip ———
    component ClipItem: Rectangle {
        id: ci
        property var cl
        property int trackIndex
        property color tint
        property real dx: 0                  // podgląd w trakcie przeciągania (s)
        property int dTrack: 0
        property real trimL: 0
        property real trimR: 0
        property bool dragging: false
        readonly property bool selected: Studio.selectedClip === cl.id
        readonly property real len: cl.length - trimL + trimR

        x: (cl.start + dx + trimL) * tl.pps
        y: 4 + dTrack * tl.trackH
        width: Math.max(6, len * tl.pps)
        height: tl.trackH - 8
        z: dragging ? 10 : (selected ? 2 : 1)
        radius: 8
        color: Qt.rgba(tint.r, tint.g, tint.b, selected ? (Theme.dark ? 0.45 : 0.40) : (Theme.dark ? 0.30 : 0.26))
        border.width: selected ? 2 : 1
        border.color: selected ? (Theme.dark ? "white" : Qt.darker(tint, 1.5)) : Qt.rgba(tint.r, tint.g, tint.b, 0.9)
        clip: true
        opacity: dragging ? 0.85 : (cl.missing ? 0.5 : 1)

        // Pasek z nazwą
        Rectangle {
            width: parent.width; height: 18
            color: Qt.rgba(ci.tint.r, ci.tint.g, ci.tint.b, 0.55)
            Row {
                x: 7; anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Icon { visible: ci.cl.loop; anchors.verticalCenter: parent.verticalCenter; d: Icons.repeat; size: 11; stroke: 2; color: Theme.dark ? "white" : "#16181D" }
                Text {
                    width: Math.max(0, ci.width - 30 - (takeBadge.visible ? takeBadge.width + 4 : 0))
                    text: ci.cl.missing ? ci.cl.name + " (brak pliku)" : ci.cl.name
                    elide: Text.ElideRight
                    color: Theme.dark ? "white" : "#16181D"
                    font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                }
            }
        }
        // Podejścia z nagrywania w pętli: klik — następne, które obejmuje ten kawałek
        Rectangle {
            id: takeBadge
            visible: (ci.cl.takes || 0) > 1 && ci.width > 70
            anchors.right: parent.right; anchors.rightMargin: 3
            y: 2
            width: takeText.implicitWidth + 12; height: 14; radius: 7
            color: takeArea.containsMouse ? "white" : Qt.rgba(1, 1, 1, Theme.dark ? 0.25 : 0.7)
            Text {
                id: takeText
                anchors.centerIn: parent
                text: "podejście " + ((ci.cl.take || 0) + 1) + "/" + (ci.cl.takes || 0)
                color: "#16181D"
                font.family: Theme.font; font.pixelSize: 9; font.weight: Font.Bold
            }
            MouseArea {
                id: takeArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    const n = ci.cl.takes, ok = ci.cl.takeOk || [];
                    for (let i = 1; i < n; ++i) {
                        const k = (ci.cl.take + i) % n;
                        if (ok[k]) { Studio.setClipTake(ci.cl.id, k); break; }
                    }
                }
            }
            Tip { shown: takeArea.containsMouse; text: "Następne podejście (prawy przycisk — lista)" }
        }
        Waveform {
            readonly property real leftPx: Math.max(0, tl.scrollX - ci.x)
            x: leftPx; y: 20
            width: Math.max(0, Math.min(ci.width, tl.scrollX + tl.viewW - ci.x) - leftPx)
            height: parent.height - 22
            file: ci.cl.file
            srcStart: ci.cl.srcStart
            srcLength: ci.cl.srcLength
            loopOffset: ci.cl.loopOffset
            loop: ci.cl.loop
            from: ci.trimL + leftPx / tl.pps
            pxPerSec: tl.pps
            gain: Math.pow(10, (ci.cl.gain || 0) / 20)
            color: Theme.dark ? Qt.lighter(ci.tint, 1.25) : Qt.darker(ci.tint, 1.35)
            version: Studio.sourcesVersion
        }
        // Narastanie i wyciszanie: przyciemniony trójkąt nad krzywą
        property real fadeInPreview: -1
        property real fadeOutPreview: -1
        readonly property real fadeInPx: (fadeInPreview >= 0 ? fadeInPreview : cl.fadeIn) * tl.pps
        readonly property real fadeOutPx: (fadeOutPreview >= 0 ? fadeOutPreview : cl.fadeOut) * tl.pps
        Shape {
            visible: ci.fadeInPx > 1
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Theme.dark ? "white" : "#16181D"; strokeWidth: 1
                fillColor: Qt.rgba(0, 0, 0, Theme.dark ? 0.35 : 0.12)
                startX: 0; startY: ci.height
                PathQuad { x: ci.fadeInPx; y: 18; controlX: ci.fadeInPx * 0.15; controlY: 18 }
                PathLine { x: 0; y: 18 }
                PathLine { x: 0; y: ci.height }
            }
        }
        Shape {
            visible: ci.fadeOutPx > 1
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Theme.dark ? "white" : "#16181D"; strokeWidth: 1
                fillColor: Qt.rgba(0, 0, 0, Theme.dark ? 0.35 : 0.12)
                startX: ci.width; startY: ci.height
                PathQuad { x: ci.width - ci.fadeOutPx; y: 18; controlX: ci.width - ci.fadeOutPx * 0.15; controlY: 18 }
                PathLine { x: ci.width; y: 18 }
                PathLine { x: ci.width; y: ci.height }
            }
        }

        // Granice powtórzeń pętli
        Repeater {
            model: ci.cl.loop && ci.cl.srcLength * tl.pps > 6 ? Math.min(128, Math.floor((ci.len + ci.cl.loopOffset) / ci.cl.srcLength)) : 0
            delegate: Rectangle {
                required property int index
                x: ((index + 1) * ci.cl.srcLength - ci.cl.loopOffset - ci.trimL) * tl.pps
                y: 18; width: 1; height: ci.height - 18
                color: Theme.dark ? "white" : "#16181D"
                opacity: 0.35
            }
        }

        // Przesuwanie
        MouseArea {
            anchors.fill: parent
            anchors.leftMargin: 8; anchors.rightMargin: 8
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: ci.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property point start
            onPressed: (e) => {
                Studio.selectedClip = ci.cl.id;
                Studio.selectedTrack = ci.trackIndex;
                start = mapToItem(lanes, e.x, e.y);
            }
            onPositionChanged: (e) => {
                if (!pressed || !(pressedButtons & Qt.LeftButton)) return;
                const p = mapToItem(lanes, e.x, e.y);
                if (!ci.dragging && Math.abs(p.x - start.x) < 4 && Math.abs(p.y - start.y) < 4) return;
                ci.dragging = true;
                ci.dx = Math.max(-ci.cl.start, tl.snapDelta((p.x - start.x) / tl.pps, e.modifiers));
                ci.dTrack = Math.max(-ci.trackIndex, Math.min(tl.count - 1 - ci.trackIndex, Math.round((p.y - start.y) / tl.trackH)));
            }
            onReleased: {
                if (ci.dragging) Studio.moveClip(ci.cl.id, ci.trackIndex + ci.dTrack, ci.cl.start + ci.dx);
                ci.dragging = false; ci.dx = 0; ci.dTrack = 0;
            }
            onDoubleClicked: { if (Studio.tracks[ci.trackIndex] && Studio.tracks[ci.trackIndex].kind !== "audio") tl.editPattern(ci.trackIndex); }
            onClicked: (e) => {
                if (e.button === Qt.RightButton)
                    tl.clipMenu(ci.cl, ci.trackIndex, ci, e.x + 8, e.y, ci.cl.start + (e.x + 8) / tl.pps);
            }
        }
        // Przycinanie z lewej
        MouseArea {
            width: 8; height: parent.height
            cursorShape: Qt.SizeHorCursor
            property real startX
            onPressed: (e) => { Studio.selectedClip = ci.cl.id; startX = mapToItem(lanes, e.x, 0).x; }
            onPositionChanged: (e) => {
                if (!pressed) return;
                const t = tl.snapAbs(ci.cl.start + (mapToItem(lanes, e.x, 0).x - startX) / tl.pps, e.modifiers);
                const minT = ci.cl.loop ? 0 : ci.cl.start - ci.cl.srcStart;
                ci.trimL = Math.max(minT, Math.min(ci.cl.start + ci.cl.length - 0.05, t)) - ci.cl.start;
            }
            onReleased: { if (ci.trimL !== 0) Studio.trimClipStart(ci.cl.id, ci.cl.start + ci.trimL); ci.trimL = 0; }
        }
        // Przycinanie (albo wydłużanie pętli) z prawej
        MouseArea {
            anchors.right: parent.right
            width: 8; height: parent.height
            cursorShape: Qt.SizeHorCursor
            property real startX
            onPressed: (e) => { Studio.selectedClip = ci.cl.id; startX = mapToItem(lanes, e.x, 0).x; }
            onPositionChanged: (e) => {
                if (!pressed) return;
                const end0 = ci.cl.start + ci.cl.length;
                let end = tl.snapAbs(end0 + (mapToItem(lanes, e.x, 0).x - startX) / tl.pps, e.modifiers);
                end = Math.max(ci.cl.start + 0.05, end);
                if (!ci.cl.loop) end = Math.min(end, ci.cl.start + ci.cl.srcDuration - ci.cl.srcStart);
                ci.trimR = end - end0;
            }
            onReleased: { if (ci.trimR !== 0) Studio.trimClipEnd(ci.cl.id, ci.cl.start + ci.cl.length + ci.trimR); ci.trimR = 0; }
        }

        // Uchwyty narastania (lewy górny róg) i wyciszania (prawy) — widoczne pod kursorem i na zaznaczonym klipie
        HoverHandler { id: clipHover }
        readonly property bool hoveredNow: clipHover.hovered
        FadeHandle { out: false }
        FadeHandle { out: true }
    }

    component FadeHandle: Rectangle {
        id: fh
        property bool out
        readonly property var c: parent
        visible: (c.selected || c.hoveredNow || fhArea.pressed) && c.width > 40 && !c.dragging
        x: (out ? c.width - c.fadeOutPx : c.fadeInPx) - width / 2
        y: 18 - height / 2
        z: 5
        width: 12; height: 12; radius: 6
        color: "white"
        border.width: 1.5; border.color: Qt.darker(c.tint, 1.4)
        MouseArea {
            id: fhArea
            anchors.fill: parent; anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.SizeHorCursor
            onPressed: Studio.selectedClip = fh.c.cl.id
            onPositionChanged: (e) => {
                if (!pressed) return;
                const x = mapToItem(fh.c, e.x, 0).x;
                const max = fh.c.cl.length - (fh.out ? fh.c.cl.fadeIn : fh.c.cl.fadeOut);
                const v = Math.max(0, Math.min(max, (fh.out ? fh.c.width - x : x) / tl.pps));
                if (fh.out) fh.c.fadeOutPreview = v; else fh.c.fadeInPreview = v;
            }
            onReleased: {
                const fi = fh.c.fadeInPreview >= 0 ? fh.c.fadeInPreview : fh.c.cl.fadeIn;
                const fo = fh.c.fadeOutPreview >= 0 ? fh.c.fadeOutPreview : fh.c.cl.fadeOut;
                fh.c.fadeInPreview = -1; fh.c.fadeOutPreview = -1;
                Studio.remember();
                Studio.setClipFades(fh.c.cl.id, fi, fo);
            }
        }
        Tip { shown: fhArea.containsMouse && !fhArea.pressed; text: fh.out ? "Wyciszanie — przeciągnij w lewo" : "Narastanie — przeciągnij w prawo"; below: true }
    }
}
