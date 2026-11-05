pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Studio

// Piano roll kanału w bieżącym wzorze: z lewej klawiatura, w siatce nuty (wiersz = wysokość, kolumna = szesnastka).
// Klik w puste miejsce — nowa nuta, przeciągnięcie nuty — przesuwa, prawy brzeg — długość, prawy klik — usuwa.
// Wiersze tonacji piosenki są jaśniejsze; „Tylko nuty skali” nie pozwala trafić w fałszywą nutę.
// Klawiatura komputera gra jak pianino (A S D F G H J K — białe, W E T Y U O — czarne, Z/X — oktawa);
// przy odtwarzaniu z „Nagrywaj nuty” zagrane dźwięki trafiają do siatki (wyrównane do szesnastek).
Item {
    id: pr
    property int channel: 0
    property var colors: []
    signal closeRequested()

    readonly property var tr: Studio.channels.find((c) => c.id === channel) || null
    readonly property var patInfo: Studio.patterns.find((p) => p.id === Studio.currentPattern) || null
    property var pat: null
    property int noteLen: 2                       // długość nowej nuty (kroki)
    property bool scaleOnly: true
    property bool keysActive: true               // klawiatura komputera gra nuty
    property bool recNotes: false
    property int octave: 4                       // oktawa dla A = C
    property var held: ({})                      // klawisz → { pitch, start }
    readonly property var keyMap: ({ "A": 0, "W": 1, "S": 2, "E": 3, "D": 4, "F": 5, "T": 6, "G": 7, "Y": 8, "H": 9, "U": 10, "J": 11, "K": 12, "O": 13, "L": 14, "P": 15 })
    readonly property var heldPitches: Object.keys(held).map(k => held[k].pitch)
    focus: visible && keysActive
    onVisibleChanged: if (visible) { reload(); forceActiveFocus(); }

    function absStep() { return Math.round(Math.max(0, Studio.position) / stepSec); }
    Keys.onPressed: (e) => { if (!e.isAutoRepeat && keyDown(e.text.toUpperCase())) e.accepted = true; }
    Keys.onReleased: (e) => { if (!e.isAutoRepeat && keyUp(e.text.toUpperCase())) e.accepted = true; }
    function keyDown(ch) {
        if (!keysActive || !pat) return false;
        if (ch === "Z") { octave = Math.max(1, octave - 1); return true; }
        if (ch === "X") { octave = Math.min(7, octave + 1); return true; }
        if (!(ch in keyMap) || ch in held) return false;
        return noteDown(ch, 12 * (octave + 1) + keyMap[ch], 0.85);
    }
    // Klawiatura MIDI: te same ścieżki co klawiatura komputera, z siłą uderzenia
    function midiDown(pitch, velocity) { if (pat) noteDown("m" + pitch, pitch, velocity / 127); }
    function midiUp(pitch) { keyUp("m" + pitch); }
    function noteDown(id, pitch, vel) {
        Studio.channelNoteOn(channel, pitch, vel);
        const h = Object.assign({}, held);
        h[id] = { pitch: pitch, start: absStep(), vel: vel };
        held = h;
        return true;
    }
    function keyUp(ch) {
        if (!(ch in held)) return false;
        const n = held[ch];
        const h = Object.assign({}, held);
        delete h[ch];
        held = h;
        Studio.channelNoteOff(channel, n.pitch);
        if (!recNotes || !Studio.playing) return true;
        // Nagranie: początek i długość wyrównane do szesnastek, w pętli wzoru
        const len = Math.max(1, Math.min(steps, absStep() - n.start));
        const step = ((n.start % steps) + steps) % steps;
        const p = JSON.parse(JSON.stringify(pat));
        p.notes = p.notes.filter(x => !(x.pitch === n.pitch && x.step === step));
        p.notes.push({ step: step, len: Math.min(len, steps - step), pitch: n.pitch, vel: n.vel });
        pat = p;
        commit();
        return true;
    }
    readonly property int steps: pat ? pat.bars * Studio.beatsPerBar * 4 : 16
    readonly property int lowest: 36             // C2
    readonly property int highest: 96            // C7
    readonly property int rowH: 14
    readonly property int keyW: 64
    readonly property real stepW: Math.max(14, (area.width) / steps)
    readonly property real stepSec: 60 / Studio.bpm / 4
    readonly property int playStep: Studio.playing ? Math.floor(Math.max(0, Studio.position) / stepSec) % steps : -1
    readonly property color tint: tr && colors.length ? colors[tr.color % colors.length] : Theme.accent
    readonly property var names: ["C", "Cis", "D", "Dis", "E", "F", "Fis", "G", "Gis", "A", "B", "H"]

    function reload() {
        pat = tr && patInfo ? { bars: patInfo.bars, notes: Studio.patternData(patInfo.id, channel).notes } : null;
    }
    onChannelChanged: { centered.done = false; reload(); }
    onPatInfoChanged: if (!mouse.editing) { if (patId !== (patInfo ? patInfo.id : 0)) { patId = patInfo ? patInfo.id : 0; centered.done = false; } reload(); }
    property int patId: 0
    onTrChanged: if (!mouse.editing) reload()
    Component.onCompleted: reload()
    Connections { target: Studio; function onRackChanged() { if (!mouse.editing) pr.reload(); } }
    function commit() { Studio.setPatternNotes(Studio.currentPattern, channel, pat.notes); }
    // Podgląd nuty: krótkie uderzenie przez instrument kanału
    property int previewPitch: -1
    function preview(pitch) {
        if (previewPitch >= 0) Studio.channelNoteOff(channel, previewPitch);
        previewPitch = pitch;
        Studio.channelNoteOn(channel, pitch, 0.8);
        previewOff.restart();
    }
    Timer { id: previewOff; interval: 260; onTriggered: { Studio.channelNoteOff(pr.channel, pr.previewPitch); pr.previewPitch = -1; } }
    function black(m) { return [1, 3, 6, 8, 10].indexOf(((m % 12) + 12) % 12) >= 0; }
    function name(m) { return names[((m % 12) + 12) % 12] + (Math.floor(m / 12) - 1); }
    function snapPitch(m) {
        if (!scaleOnly || Studio.inKey(m)) return m;
        return Studio.inKey(m + 1) ? m + 1 : m - 1;
    }
    // Pierwsze otwarcie: widok na okolice nut melodii (albo środkowe C)
    function center() {
        let top = 72;
        if (pat && pat.notes.length) top = Math.max(...pat.notes.map(n => n.pitch)) + 4;
        area.contentY = Math.max(0, Math.min(area.contentHeight - area.height, (highest - top) * rowH));
    }
    onPatChanged: if (pat && pat.notes.length && !centered.done) { centered.done = true; Qt.callLater(center); }
    QtObject { id: centered; property bool done: false }

    Rectangle { anchors.fill: parent; color: Theme.dark ? "#16171C" : "#F1F2F6" }
    Rectangle { width: parent.width; height: 1; color: Theme.line }

    // ——— Pasek ———
    Item {
        id: bar
        width: parent.width; height: 52
        Row {
            x: 16; anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 34; height: 34; radius: 10
                color: pr.tint
                Text { anchors.centerIn: parent; text: "♫"; color: "white"; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text { text: pr.tr ? pr.tr.name : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Bold }
                Text {
                    text: Studio.midiDevices.length ? "Klawiatura MIDI: " + Studio.midiDevices.join(", ") : "Piano roll — klik dodaje nutę, prawy klik usuwa"
                    color: Studio.midiDevices.length ? Theme.accentText : Theme.text2
                    font.family: Theme.font; font.pixelSize: 11
                }
            }
        }
        HoverButton {
            anchors.right: parent.right; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; radius: 15
            onClicked: pr.closeRequested()
            Icon { anchors.centerIn: parent; d: Icons.close; size: 13; stroke: 2; color: Theme.text2 }
        }
    }
    Row {
        id: opts
        x: 16; y: bar.height
        height: 34
        spacing: 12
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Takty"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        Segmented {
            anchors.verticalCenter: parent.verticalCenter
            model: [{ label: "1", value: 1 }, { label: "2", value: 2 }, { label: "4", value: 4 }, { label: "8", value: 8 }]
            value: pr.pat ? pr.pat.bars : 4
            onPicked: (v) => Studio.setPatternBars(Studio.currentPattern, v)
        }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Nowa nuta"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        Segmented {
            anchors.verticalCenter: parent.verticalCenter
            model: [{ label: "1/16", value: 1 }, { label: "1/8", value: 2 }, { label: "1/4", value: 4 }, { label: "1/2", value: 8 }, { label: "cała", value: 16 }]
            value: pr.noteLen
            onPicked: (v) => pr.noteLen = v
        }
        HoverButton {
            anchors.verticalCenter: parent.verticalCenter
            width: scaleRow.implicitWidth + 16; height: 28; radius: 8
            onClicked: pr.scaleOnly = !pr.scaleOnly
            Row {
                id: scaleRow
                x: 8; anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18; radius: 5
                    color: pr.scaleOnly ? Theme.accent : "transparent"
                    border.width: pr.scaleOnly ? 0 : 1.5; border.color: Theme.text2
                    Icon { visible: pr.scaleOnly; anchors.centerIn: parent; d: Icons.check; size: 12; stroke: 2.4; color: "white" }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Tylko nuty skali (" + Studio.keyName + ")"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
            }
        }
        Pill { anchors.verticalCenter: parent.verticalCenter; height: 28; text: "Wyczyść"; icon: "trash"; onClicked: Studio.setPatternNotes(Studio.currentPattern, pr.channel, []) }
        Pill {
            anchors.verticalCenter: parent.verticalCenter; height: 28
            text: pr.keysActive ? "Klawiatura: oktawa " + pr.octave : "Klawiatura wył."
            icon: "keyboard"; active: pr.keysActive
            tip: "Graj na klawiaturze komputera: A S D F G H J K — białe klawisze, W E T Y U — czarne, Z/X — oktawa niżej/wyżej"
            onClicked: { pr.keysActive = !pr.keysActive; if (pr.keysActive) pr.forceActiveFocus(); }
        }
        Pill {
            anchors.verticalCenter: parent.verticalCenter; height: 28
            text: "Nagrywaj nuty"; icon: "mic"
            active: pr.recNotes
            tip: "Włącz, naciśnij Spację i graj na klawiaturze — nuty zapiszą się w siatce"
            onClicked: { pr.recNotes = !pr.recNotes; pr.forceActiveFocus(); }
        }
    }

    // ——— Klawiatura i siatka ———
    Item {
        id: roll
        x: 16; y: opts.y + opts.height + 8
        width: parent.width - 32; height: parent.height - y - 10
        clip: true

        // Klawiatura (przewija się w pionie razem z siatką)
        Item {
            width: pr.keyW; height: parent.height
            clip: true
            Column {
                y: -area.contentY
                Repeater {
                    model: pr.highest - pr.lowest + 1
                    delegate: Rectangle {
                        id: key
                        required property int index
                        readonly property int midi: pr.highest - index
                        width: pr.keyW - 4; height: pr.rowH
                        color: pr.heldPitches.indexOf(midi) >= 0 || keyArea.pressed ? Theme.accent
                             : pr.black(midi) ? (Theme.dark ? "#2A2C33" : "#3A3D45") : (Theme.dark ? "#D8DAE0" : "white")
                        MouseArea {
                            id: keyArea
                            anchors.fill: parent
                            onPressed: { Studio.channelNoteOn(pr.channel, key.midi, 0.85); pr.forceActiveFocus(); }
                            onReleased: Studio.channelNoteOff(pr.channel, key.midi)
                            onCanceled: Studio.channelNoteOff(pr.channel, key.midi)
                        }
                        border.width: 1; border.color: Theme.dark ? Qt.rgba(0, 0, 0, 0.5) : Qt.rgba(0, 0, 0, 0.12)
                        Text {
                            visible: key.midi % 12 === 0 || Studio.inKey(key.midi) && key.midi % 12 === Studio.keyRoot
                            anchors.right: parent.right; anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: pr.name(key.midi)
                            color: pr.black(key.midi) ? "white" : "#16181D"
                            font.family: Theme.font; font.pixelSize: 9; font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }

        Flickable {
            id: area
            x: pr.keyW; width: parent.width - pr.keyW; height: parent.height
            contentWidth: pr.steps * pr.stepW
            contentHeight: (pr.highest - pr.lowest + 1) * pr.rowH
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: false
            WheelHandler {
                acceptedModifiers: Qt.NoModifier
                onWheel: (e) => area.contentY = Math.max(0, Math.min(area.contentHeight - area.height, area.contentY - e.angleDelta.y / 2))
            }
            WheelHandler {
                acceptedModifiers: Qt.ShiftModifier
                onWheel: (e) => area.contentX = Math.max(0, Math.min(area.contentWidth - area.width, area.contentX - (e.angleDelta.y || e.angleDelta.x) / 2))
            }

            // Wiersze: tonacja jaśniejsza, czarne klawisze ciemniejsze
            Repeater {
                model: pr.highest - pr.lowest + 1
                delegate: Rectangle {
                    id: rowBg
                    required property int index
                    readonly property int midi: pr.highest - index
                    y: index * pr.rowH
                    width: area.contentWidth; height: pr.rowH
                    color: Studio.inKey(midi) ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.9))
                                              : (Theme.dark ? Qt.rgba(0, 0, 0, 0.25) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.06))
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line; opacity: rowBg.midi % 12 === 0 ? 1 : 0.4 }
                }
            }
            // Pionowe linie: takty mocno, miary słabiej
            Repeater {
                model: pr.steps / 4 + 1
                delegate: Rectangle {
                    required property int index
                    x: index * 4 * pr.stepW
                    width: 1; height: area.contentHeight
                    color: Theme.text
                    opacity: index % 4 === 0 ? 0.25 : 0.08
                }
            }
            // Głowica
            Rectangle {
                visible: pr.playStep >= 0
                x: pr.playStep * pr.stepW
                width: pr.stepW; height: area.contentHeight
                color: Theme.accentAlpha(0.12)
            }
            // Nuty
            Repeater {
                model: pr.pat ? pr.pat.notes : []
                delegate: Rectangle {
                    id: noteRect
                    required property var modelData
                    x: modelData.step * pr.stepW + 1
                    y: (pr.highest - modelData.pitch) * pr.rowH + 1
                    width: Math.max(4, modelData.len * pr.stepW - 2); height: pr.rowH - 2
                    radius: 4
                    color: Qt.rgba(pr.tint.r, pr.tint.g, pr.tint.b, 0.55 + 0.45 * (modelData.vel || 0.85))
                    border.width: 1; border.color: Qt.darker(pr.tint, 1.4)
                    Rectangle { anchors.right: parent.right; anchors.rightMargin: 2; anchors.verticalCenter: parent.verticalCenter; width: 2; height: parent.height - 6; radius: 1; color: "white"; opacity: 0.7 }
                }
            }

            MouseArea {
                id: mouse
                width: area.contentWidth; height: area.contentHeight
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                property bool editing: false
                property string mode: ""              // move | resize
                property int index: -1
                property int grabStep: 0
                function stepAt(x) { return Math.max(0, Math.min(pr.steps - 1, Math.floor(x / pr.stepW))); }
                function pitchAt(y) { return Math.max(pr.lowest, Math.min(pr.highest, pr.highest - Math.floor(y / pr.rowH))); }
                function noteAt(x, y) {
                    const s = stepAt(x), p = pitchAt(y);
                    const notes = pr.pat ? pr.pat.notes : [];
                    for (let i = notes.length - 1; i >= 0; --i)
                        if (notes[i].pitch === p && s >= notes[i].step && s < notes[i].step + notes[i].len) return i;
                    return -1;
                }
                cursorShape: {
                    const i = noteAt(mouseX, mouseY);
                    if (i < 0) return Qt.CrossCursor;
                    const n = pr.pat.notes[i];
                    return mouseX > (n.step + n.len) * pr.stepW - 7 ? Qt.SizeHorCursor : Qt.OpenHandCursor;
                }
                onPressed: (e) => {
                    if (!pr.pat) return;
                    pr.forceActiveFocus();
                    const i = noteAt(e.x, e.y);
                    const p = JSON.parse(JSON.stringify(pr.pat));
                    if (e.button === Qt.RightButton) {
                        if (i >= 0) { p.notes.splice(i, 1); pr.pat = p; pr.commit(); }
                        return;
                    }
                    editing = true;
                    if (i >= 0) {
                        index = i;
                        const n = p.notes[i];
                        mode = e.x > (n.step + n.len) * pr.stepW - 7 ? "resize" : "move";
                        grabStep = stepAt(e.x) - n.step;
                        pr.noteLen = n.len;               // następne nuty takie same jak ta
                        if (mode === "move") pr.preview(n.pitch);
                    } else {
                        p.notes.push({ step: stepAt(e.x), len: Math.min(pr.noteLen, pr.steps - stepAt(e.x)), pitch: pr.snapPitch(pitchAt(e.y)), vel: 0.85 });
                        pr.preview(p.notes[p.notes.length - 1].pitch);
                        index = p.notes.length - 1;
                        mode = "resize";
                        pr.pat = p;
                    }
                }
                onPositionChanged: (e) => {
                    if (!editing || index < 0) return;
                    const p = JSON.parse(JSON.stringify(pr.pat));
                    const n = p.notes[index];
                    if (mode === "move") {
                        n.step = Math.max(0, Math.min(pr.steps - n.len, stepAt(e.x) - grabStep));
                        const np = pr.snapPitch(pitchAt(e.y));
                        if (np !== n.pitch) pr.preview(np);
                        n.pitch = np;
                    } else {
                        n.len = Math.max(1, Math.min(pr.steps - n.step, stepAt(e.x) - n.step + 1));
                        pr.noteLen = n.len;
                    }
                    pr.pat = p;
                }
                onReleased: { if (editing) { editing = false; index = -1; pr.commit(); } }
                onDoubleClicked: (e) => {
                    const i = noteAt(e.x, e.y);
                    if (i < 0) return;
                    const p = JSON.parse(JSON.stringify(pr.pat));
                    p.notes.splice(i, 1);
                    pr.pat = p;
                    pr.commit();
                }
            }
        }
    }
}
