import QtQuick
import Aster.Ui

// Suwak z podpisem i wartością. `moved(v, done)` — done = puszczono (zamyka krok cofania)
Item {
    id: vs
    property string label
    property real from: 0
    property real to: 1
    property real value: 0
    property real step: 0.01
    property string suffix
    property real shown: value          // wartość pokazana obok (np. procenty)
    property int decimals: 0
    signal moved(real v, bool done)

    width: parent ? parent.width : 200
    height: 44

    Text {
        text: vs.label
        color: Theme.text
        font.family: Theme.font; font.pixelSize: 12
    }
    Text {
        anchors.right: parent.right
        text: vs.shown.toFixed(vs.decimals) + vs.suffix
        color: Theme.text2
        font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 }
    }
    Item {
        id: track
        y: 22
        width: parent.width; height: 20
        readonly property real t: Math.max(0, Math.min(1, (vs.value - vs.from) / (vs.to - vs.from)))
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 4; radius: 2
            color: Theme.fill
            Rectangle { width: parent.width * track.t; height: parent.height; radius: 2; color: Theme.accent }
        }
        Rectangle {
            x: track.t * (track.width - width)
            anchors.verticalCenter: parent.verticalCenter
            width: 16; height: 16; radius: 8
            color: "white"
            border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.18)
            scale: area.pressed ? 1.15 : 1
            Behavior on scale { NumberAnimation { duration: 100 } }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            function pick(mx, done) {
                const t = Math.max(0, Math.min(1, (mx - 8) / (track.width - 16)));
                let v = vs.from + t * (vs.to - vs.from);
                v = Math.round(v / vs.step) * vs.step;
                vs.moved(v, done);
            }
            onPressed: (e) => pick(e.x, false)
            onPositionChanged: (e) => { if (pressed) pick(e.x, false); }
            onReleased: (e) => pick(e.x, true)
        }
    }
}
