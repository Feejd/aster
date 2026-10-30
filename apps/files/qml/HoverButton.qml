import QtQuick
import Aster.Ui

// Prostokąt reagujący na najechanie i wciśnięcie
Rectangle {
    id: hb
    property alias hovered: area.containsMouse
    property alias down: area.pressed
    property color baseColor: "transparent"
    signal clicked()

    radius: 8
    color: area.containsMouse && enabled ? Theme.hover : baseColor
    scale: area.pressed ? 0.96 : 1
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutQuad } }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: if (hb.enabled) hb.clicked()
    }
}
