import QtQuick
import Aster.Ui

// Przycisk w kształcie pigułki: zwykły (szare tło) albo główny (kolor akcentu)
Rectangle {
    id: pb
    property string text
    property bool primary: false
    property bool danger: false
    signal clicked()

    width: label.implicitWidth + 32
    height: 38
    radius: 10
    opacity: enabled ? 1 : 0.45
    color: primary ? (area.containsMouse ? Qt.darker(Theme.accent, 1.08) : Theme.accent)
                   : (area.containsMouse ? Theme.hover : Theme.fill)
    scale: area.pressed ? 0.97 : 1
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on scale { NumberAnimation { duration: 90 } }

    Text {
        id: label
        anchors.centerIn: parent
        text: pb.text
        color: pb.primary ? "white" : (pb.danger ? Theme.danger : Theme.text)
        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (pb.enabled) pb.clicked()
    }
}
