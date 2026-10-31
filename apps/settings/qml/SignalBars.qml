pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui

// Siła sygnału Wi‑Fi: cztery słupki
Row {
    id: sb
    property int signal: 0
    property color color: Theme.text
    spacing: 2
    Repeater {
        model: 4
        delegate: Rectangle {
            required property int index
            anchors.bottom: parent.bottom
            width: 3; height: 4 + index * 3
            radius: 1.5
            color: sb.color
            opacity: sb.signal >= [1, 30, 55, 75][index] ? 1 : 0.22
        }
    }
}
