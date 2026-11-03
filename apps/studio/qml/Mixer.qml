pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Studio

// Mikser: dla każdej ścieżki panorama, suwak głośności ze wskaźnikiem poziomu, wycisz i solo; z prawej — suma.
// Dwuklik na suwaku wraca do 0 dB (panoramę — do środka).
Item {
    id: mx
    property var colors: []
    function color(i) { return colors.length ? colors[i % colors.length] : Theme.accent; }

    // Suwak: pozycja 0…1 ↔ decybele (0 dB przy ~71%, +6 dB na górze)
    function dbAt(p) { return p <= 0.001 ? -60 : Math.max(-60, Math.min(6, 6 + 40 * Math.log(p) / Math.LN10)); }
    function posOf(db) { return db <= -60 ? 0 : Math.pow(10, (db - 6) / 40); }
    function meterPos(level) { return level <= 0 ? 0 : Math.max(0, Math.min(1, (20 * Math.log(level) / Math.LN10 + 60) / 66)); }
    function dbText(db) { return db <= -60 ? "−∞" : (db > 0 ? "+" : db < 0 ? "−" : "") + Math.abs(db).toFixed(1); }

    // Pełne tło: pasy osi czasu nie prześwitują (ikony wektorowe nie zawsze są przycinane)
    Rectangle { anchors.fill: parent; color: Theme.dark ? "#16171C" : "#F1F2F6" }
    Rectangle { width: parent.width; height: 1; color: Theme.line }

    Flickable {
        id: strips
        x: 12; y: 10
        width: parent.width - master.width - 36; height: parent.height - 20
        contentWidth: row.width
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        Row {
            id: row
            spacing: 8
            Repeater {
                model: Studio.tracks
                delegate: Strip {
                    required property var modelData
                    required property int index
                    label: modelData.name
                    tint: mx.color(modelData.color)
                    readonly property var m: Studio.mix[index] || {}
                    volume: m.volume || 0
                    pan: m.pan || 0
                    mute: !!m.mute
                    solo: !!m.solo
                    level: Studio.levels[index] || 0
                    selected: Studio.selectedTrack === index
                    onVolumeMoved: (db) => Studio.setTrackVolume(index, db)
                    onPanMoved: (p) => Studio.setTrackPan(index, p)
                    onMuteToggled: Studio.setTrackMute(index, !mute)
                    onSoloToggled: Studio.setTrackSolo(index, !solo)
                    onPicked: Studio.selectedTrack = index
                }
            }
        }
    }
    Rectangle { x: master.x - 12; y: 14; width: 1; height: parent.height - 28; color: Theme.line }
    Strip {
        id: master
        anchors.right: parent.right; anchors.rightMargin: 12
        y: 10; height: parent.height - 20
        label: "Suma"
        tint: Theme.text2
        isMaster: true
        volume: Studio.masterVolume
        level: Math.max(Studio.masterLevel[0], Studio.masterLevel[1])
        levelR: Studio.masterLevel[1]
        levelL: Studio.masterLevel[0]
        onVolumeMoved: (db) => Studio.masterVolume = db
    }

    component Strip: Rectangle {
        id: st
        property string label
        property color tint
        property real volume: 0
        property real pan: 0
        property bool mute: false
        property bool solo: false
        property real level: 0
        property real levelL: level
        property real levelR: level
        property bool selected: false
        property bool isMaster: false
        signal volumeMoved(real db)
        signal panMoved(real p)
        signal muteToggled()
        signal soloToggled()
        signal picked()
        width: 92; height: strips.height
        radius: 12
        color: selected ? Theme.fill : "transparent"
        border.width: selected ? 1 : 0; border.color: Theme.edge
        MouseArea { anchors.fill: parent; onPressed: st.picked() }

        Rectangle { x: 10; y: 8; width: parent.width - 20; height: 3; radius: 1.5; color: st.tint }
        Text {
            x: 6; y: 16; width: parent.width - 12
            horizontalAlignment: Text.AlignHCenter
            text: st.label
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
        }

        // Panorama (L … P)
        Item {
            id: panBox
            visible: !st.isMaster
            x: 10; y: 38; width: parent.width - 20; height: 18
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Theme.fill }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: Math.min(parent.width / 2, parent.width / 2 * (1 + st.pan))
                width: Math.abs(st.pan) * parent.width / 2; height: 4
                color: Theme.accent
            }
            Rectangle { x: parent.width / 2 - 0.5; anchors.verticalCenter: parent.verticalCenter; width: 1; height: 10; color: Theme.text2; opacity: 0.6 }
            Rectangle {
                x: (parent.width - width) * (st.pan + 1) / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 12; height: 12; radius: 6
                color: "white"; border.width: 1; border.color: Theme.edge
            }
            MouseArea {
                anchors.fill: parent; anchors.margins: -4
                function at(x) { const p = Math.max(-1, Math.min(1, (x - 4) / panBox.width * 2 - 1)); return Math.abs(p) < 0.06 ? 0 : p; }
                onPressed: (e) => st.panMoved(at(e.x))
                onPositionChanged: (e) => { if (pressed) st.panMoved(at(e.x)); }
                onDoubleClicked: st.panMoved(0)
            }
        }
        Text {
            visible: !st.isMaster
            anchors.horizontalCenter: parent.horizontalCenter; y: 56
            text: Math.abs(st.pan) < 0.01 ? "Środek" : (st.pan < 0 ? "L " : "P ") + Math.round(Math.abs(st.pan) * 100)
            color: Theme.text2
            font.family: Theme.font; font.pixelSize: 10
        }

        // Suwak głośności i wskaźnik poziomu
        Item {
            id: faderBox
            x: 14; y: st.isMaster ? 44 : 76
            width: parent.width - 28
            height: parent.height - y - (st.isMaster ? 34 : 64)
            // Skala
            Repeater {
                model: [6, 0, -6, -12, -24, -48]
                delegate: Item {
                    id: tick
                    required property var modelData
                    y: faderBox.height * (1 - mx.posOf(modelData))
                    Rectangle { x: 0; width: 5; height: 1; color: Theme.text2; opacity: 0.5 }
                    Text {
                        id: tickText
                        x: -1; y: -6
                        visible: faderBox.height > 90
                        text: tick.modelData > 0 ? "+" + tick.modelData : tick.modelData
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 8; font.features: { "tnum": 1 }
                        transform: Translate { x: -tickText.width - 2 }
                    }
                }
            }
            // Tor suwaka
            Rectangle {
                id: trackLine
                x: 14; width: 4; height: parent.height; radius: 2
                color: Theme.fill
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; radius: 2
                    height: parent.height * mx.posOf(st.volume)
                    color: Theme.accentSoft
                }
            }
            Rectangle {
                id: thumb
                x: trackLine.x + 2 - width / 2
                y: (parent.height) * (1 - mx.posOf(st.volume)) - height / 2
                width: 26; height: 14; radius: 4
                color: Theme.surface
                border.width: 1; border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.25)
                Rectangle { anchors.centerIn: parent; width: 14; height: 2; radius: 1; color: Theme.text2 }
            }
            MouseArea {
                x: 0; width: 40; height: parent.height
                anchors.topMargin: -8; anchors.bottomMargin: -8
                property real grabOffset: 0
                function posAt(y) { return Math.max(0, Math.min(1, 1 - y / faderBox.height)); }
                onPressed: (e) => {
                    // Złapany uchwyt nie skacze; klik obok — suwak tam przeskakuje
                    const ty = thumb.y + thumb.height / 2;
                    grabOffset = Math.abs(e.y - ty) < 10 ? e.y - ty : 0;
                    st.volumeMoved(mx.dbAt(posAt(e.y - grabOffset)));
                }
                onPositionChanged: (e) => { if (pressed) st.volumeMoved(mx.dbAt(posAt(e.y - grabOffset))); }
                onDoubleClicked: st.volumeMoved(0)
                onWheel: (w) => st.volumeMoved(Math.max(-60, Math.min(6, (st.volume <= -60 ? -40 : st.volume) + (w.angleDelta.y > 0 ? 1 : -1))))
            }
            // Wskaźnik (dla sumy — dwa kanały)
            Row {
                x: 40; spacing: 2
                height: parent.height
                Repeater {
                    model: st.isMaster ? [st.levelL, st.levelR] : [st.level]
                    delegate: Rectangle {
                        id: meter
                        required property real modelData
                        width: st.isMaster ? 5 : 7; height: faderBox.height; radius: 2
                        color: Theme.fill
                        clip: true
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: parent.height * mx.meterPos(meter.modelData)
                            gradient: Gradient {
                                GradientStop { position: 0; color: meter.modelData >= 0.99 ? "#E5484D" : "#E8A317" }
                                GradientStop { position: 0.12; color: "#E8C317" }
                                GradientStop { position: 0.35; color: "#30C26B" }
                                GradientStop { position: 1; color: "#26A65B" }
                            }
                        }
                    }
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: faderBox.y + faderBox.height + 6
            text: mx.dbText(st.volume) + " dB"
            color: Theme.text2
            font.family: Theme.font; font.pixelSize: 11; font.features: { "tnum": 1 }
        }
        Row {
            visible: !st.isMaster
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 10
            spacing: 6
            ToggleChip { label: "M"; on: st.mute; onColor: "#E8A317"; onClicked: st.muteToggled() }
            ToggleChip { label: "S"; on: st.solo; onColor: "#2F80ED"; onClicked: st.soloToggled() }
        }
    }

    component ToggleChip: HoverButton {
        id: tc
        property string label
        property bool on
        property color onColor
        width: 30; height: 24; radius: 7
        baseColor: on ? onColor : Theme.fill
        color: on ? (hovered ? Qt.lighter(onColor, 1.1) : onColor) : (hovered ? Theme.hover : baseColor)
        Text { anchors.centerIn: parent; text: tc.label; color: tc.on ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Bold }
    }
}
