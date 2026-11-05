pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Studio

// Rack kanałów: u góry wzory, niżej kanał w wierszu — wycisz, nazwa, głośność, kroki bieżącego wzoru.
// Kliknięcie lub przeciąganie włącza kroki, prawy przycisk je czyści. Kanał z nutami z piano rolla
// pokazuje je małym podglądem zamiast kroków.
Item {
    id: rk
    property var colors: []
    signal channelMenu(int id, Item item, real x, real y)
    signal pianoRequested(int id)
    signal addRequested()
    signal patternMenu(Item item)
    signal closeRequested()

    function color(i) { return colors.length ? colors[i % colors.length] : Theme.accent; }
    readonly property var pattern: Studio.patterns.find((p) => p.id === Studio.currentPattern) || null
    readonly property int steps: pattern ? pattern.bars * Studio.beatsPerBar * 4 : 16
    readonly property real stepSec: 60 / Studio.bpm / 4
    readonly property real stepW: Math.max(18, Math.min(34, (width - 296) / steps))
    readonly property int playStep: Studio.playing && Studio.patternMode ? Math.floor(Math.max(0, Studio.position) / stepSec) % steps : -1

    Rectangle { anchors.fill: parent; color: Theme.dark ? "#16171C" : "#F1F2F6" }
    Rectangle { width: parent.width; height: 1; color: Theme.line }

    // Pasek: wzór, długość, rozstaw
    Row {
        id: bar
        x: 14; y: 8; height: 34
        spacing: 10
        Pill { anchors.verticalCenter: parent.verticalCenter; height: 30; text: rk.pattern ? rk.pattern.name : "Brak wzoru"; icon: "grid"; tip: "Wybierz wzór"; onClicked: rk.patternMenu(this) }
        Pill { anchors.verticalCenter: parent.verticalCenter; height: 30; text: "Nowy"; icon: "plus"; tip: "Nowy pusty wzór"; onClicked: Studio.addPattern() }
        Pill { anchors.verticalCenter: parent.verticalCenter; height: 30; text: "Kopia"; icon: "copy"; tip: "Kopia bieżącego wzoru — do wariacji"; visible: !!rk.pattern; onClicked: Studio.duplicatePattern(Studio.currentPattern) }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Takty"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        Segmented {
            anchors.verticalCenter: parent.verticalCenter
            model: [{ label: "1", value: 1 }, { label: "2", value: 2 }, { label: "4", value: 4 }, { label: "8", value: 8 }]
            value: rk.pattern ? rk.pattern.bars : 1
            onPicked: (v) => Studio.setPatternBars(Studio.currentPattern, v)
        }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Rozstaw"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        Item {
            id: swing
            anchors.verticalCenter: parent.verticalCenter
            width: 90; height: 18
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Theme.fill }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * Studio.swing * 2; height: 4; radius: 2; color: Theme.accent }
            Rectangle { x: (parent.width - 12) * Studio.swing * 2; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6; color: "white"; border.width: 1; border.color: Theme.edge }
            MouseArea {
                anchors.fill: parent
                function put(x) { Studio.swing = Math.max(0, Math.min(0.5, x / swing.width / 2)); }
                onPressed: (e) => put(e.x)
                onPositionChanged: (e) => { if (pressed) put(e.x); }
                onDoubleClicked: Studio.swing = 0
            }
        }
    }
    HoverButton {
        anchors.right: parent.right; anchors.rightMargin: 14; y: 10
        width: 30; height: 30; radius: 15
        onClicked: rk.closeRequested()
        Icon { anchors.centerIn: parent; d: Icons.close; size: 13; stroke: 2; color: Theme.text2 }
    }

    // Wiersze
    Flickable {
        id: rows
        x: 0; y: 48
        width: parent.width; height: parent.height - y
        contentHeight: col.height + 10
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: rows.width
            spacing: 3
            Repeater {
                model: Studio.channels.length
                delegate: Item {
                    id: row
                    required property int index
                    readonly property var ch: Studio.channels[index] || null
                    readonly property bool selected: !!ch && Studio.selectedChannel === ch.id
                    readonly property color tint: rk.color(ch ? ch.color : 0)
                    // Dane kroków: odświeża je każda zmiana racka
                    readonly property var pd: ch && Studio.patterns.length >= 0 && Studio.channels ? Studio.patternData(Studio.currentPattern, ch.id) : ({ steps: [], notes: [] })
                    width: col.width; height: 34

                    Rectangle {
                        x: 8; width: 262; height: parent.height; radius: 9
                        color: row.selected ? Theme.fill : "transparent"
                    }
                    // Wycisz
                    HoverButton {
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; radius: 11
                        baseColor: row.ch && !row.ch.mute ? "#3CCB7F" : Theme.fill
                        color: baseColor
                        onClicked: Studio.setChannelMute(row.ch.id, !row.ch.mute)
                        Tip { shown: parent.hovered; text: row.ch && row.ch.mute ? "Włącz kanał" : "Wycisz kanał" }
                    }
                    // Nazwa: wybór, podgląd dźwięku, menu
                    HoverButton {
                        id: nameBtn
                        x: 42; anchors.verticalCenter: parent.verticalCenter
                        width: 136; height: 28; radius: 7
                        baseColor: Qt.rgba(row.tint.r, row.tint.g, row.tint.b, Theme.dark ? 0.32 : 0.26)
                        color: baseColor
                        Text {
                            x: 9; width: parent.width - 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.ch ? row.ch.name + (row.ch.missing ? " (brak)" : "") : ""
                            elide: Text.ElideRight
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                        }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onPressed: (e) => {
                                Studio.selectedChannel = row.ch.id;
                                if (e.button === Qt.RightButton) rk.channelMenu(row.ch.id, nameBtn, e.x, e.y);
                                else Studio.channelNoteOn(row.ch.id, row.ch.kind === "bass" ? 36 : 60, 0.85);
                            }
                            onReleased: Studio.channelNoteOff(row.ch.id, row.ch.kind === "bass" ? 36 : 60)
                            onDoubleClicked: { if (row.ch.kind === "vst") Studio.openChannelPlugin(row.ch.id); else rk.pianoRequested(row.ch.id); }
                        }
                    }
                    // Głośność kanału
                    Item {
                        id: vol
                        x: 184; anchors.verticalCenter: parent.verticalCenter
                        width: 54; height: 18
                        readonly property real pos: row.ch ? Math.max(0, Math.min(1, (row.ch.volume + 36) / 42)) : 0
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Theme.fill }
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * vol.pos; height: 4; radius: 2; color: Theme.text2 }
                        MouseArea {
                            anchors.fill: parent
                            function put(x) { const p = Math.max(0, Math.min(1, x / vol.width)); Studio.setChannelVolume(row.ch.id, p <= 0 ? -60 : p * 42 - 36); }
                            onPressed: (e) => { Studio.remember(); put(e.x); }
                            onPositionChanged: (e) => { if (pressed) put(e.x); }
                            onDoubleClicked: Studio.setChannelVolume(row.ch.id, 0)
                        }
                    }
                    // Piano roll
                    HoverButton {
                        x: 242; anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 24; radius: 7
                        onClicked: rk.pianoRequested(row.ch.id)
                        Icon { anchors.centerIn: parent; d: Icons.keyboard; size: 14; stroke: 2; color: row.pd.notes.length ? Theme.accentText : Theme.text2 }
                        Tip { shown: parent.hovered; text: "Nuty tego kanału (piano roll)" }
                    }
                    // Kroki albo podgląd nut
                    Flickable {
                        x: 278
                        width: parent.width - x - 10; height: parent.height
                        contentWidth: rk.steps * rk.stepW
                        contentX: head.contentX
                        interactive: false
                        clip: true
                        Item {
                            width: rk.steps * rk.stepW; height: 34
                            Row {
                                visible: row.pd.notes.length === 0
                                Repeater {
                                    model: rk.steps
                                    delegate: Rectangle {
                                        required property int index
                                        readonly property real vel: row.pd.steps[index] || 0
                                        readonly property bool dark4: Math.floor(index / 4) % 2 === 0
                                        y: 3
                                        width: rk.stepW - 2; height: 28; radius: 5
                                        color: vel > 0 ? rk.color(row.ch ? row.ch.color : 0)
                                                       : dark4 ? Theme.fill : Qt.rgba(Theme.fill.r, Theme.fill.g, Theme.fill.b, Theme.fill.a * 0.45)
                                        opacity: vel > 0 ? 0.45 + 0.55 * vel : 1
                                        border.width: index === rk.playStep ? 2 : 0
                                        border.color: Theme.text
                                    }
                                }
                            }
                            // Nuty: mała rolka
                            Repeater {
                                model: row.pd.notes
                                delegate: Rectangle {
                                    required property var modelData
                                    readonly property var pitches: row.pd.notes.map((n) => n.pitch)
                                    readonly property int lo: Math.min(...pitches)
                                    readonly property int hi: Math.max(...pitches)
                                    x: modelData.step * rk.stepW
                                    y: hi === lo ? 15 : 4 + (hi - modelData.pitch) * 22 / (hi - lo)
                                    width: Math.max(3, modelData.len * rk.stepW - 1); height: 4; radius: 2
                                    color: rk.color(row.ch ? row.ch.color : 0)
                                }
                            }
                            Rectangle { visible: row.pd.notes.length > 0; width: parent.width; height: 34; radius: 6; color: Theme.fill; z: -1 }
                            MouseArea {
                                anchors.fill: parent
                                enabled: row.pd.notes.length === 0
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                property real paint: 0
                                property int last: -1
                                function put(x) {
                                    const i = Math.max(0, Math.min(rk.steps - 1, Math.floor(x / rk.stepW)));
                                    if (i === last) return;
                                    last = i;
                                    Studio.setStep(Studio.currentPattern, row.ch.id, i, paint);
                                }
                                onPressed: (e) => {
                                    Studio.selectedChannel = row.ch.id;
                                    const i = Math.max(0, Math.min(rk.steps - 1, Math.floor(e.x / rk.stepW)));
                                    paint = e.button === Qt.RightButton || (row.pd.steps[i] || 0) > 0 ? 0 : 0.85;
                                    last = -1;
                                    put(e.x);
                                }
                                onPositionChanged: (e) => { if (pressed) put(e.x); }
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: row.pd.notes.length > 0
                                onClicked: rk.pianoRequested(row.ch.id)
                            }
                        }
                    }
                }
            }
            HoverButton {
                x: 14
                width: 136; height: 30; radius: 8
                onClicked: rk.addRequested()
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.plus; size: 13; stroke: 2; color: Theme.text2 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Dodaj kanał"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                }
                Tip { shown: parent.hovered; text: "Dźwięk z przeglądarki po lewej" }
            }
        }
    }
    // Wspólny przesuw kroków, gdy wzór jest długi
    Flickable {
        id: head
        x: 278; y: parent.height - 12
        width: parent.width - x - 10; height: 10
        visible: contentWidth > width
        contentWidth: rk.steps * rk.stepW
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        Rectangle { width: head.contentWidth; height: 10; color: "transparent" }
        Rectangle {
            parent: head
            x: head.width * head.contentX / head.contentWidth
            y: 3; width: head.width * head.width / head.contentWidth; height: 5; radius: 2.5
            color: Theme.text2; opacity: 0.5
        }
    }
}
