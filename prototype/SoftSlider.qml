import QtQuick

// Gruby suwak z wypełnieniem, przeciągany myszą
Item {
    id: s
    property var t
    property real value: 0.5
    property string icon
    signal moved(real v)

    height: 32

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: s.t.fill
        clip: true

        Rectangle {
            width: Math.max(track.height, track.width * s.value)
            height: parent.height
            radius: height / 2
            color: s.t.accent
            Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
        }
        Icon { x: 9; anchors.verticalCenter: parent.verticalCenter; d: s.icon; size: 16; color: "white" }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        onPressed: (m) => s.moved(Math.max(0, Math.min(1, m.x / width)))
        onPositionChanged: (m) => { if (pressed) s.moved(Math.max(0, Math.min(1, m.x / width))) }
    }
}
