import QtQuick
import QtQuick.Effects

// Szklana wyspa: cień, półprzezroczysty odcień, cienka krawędź i jasny „rant” od środka.
// Samo rozmycie tła robi KWin — okno zgłasza obszary wysp przez Platform.setBlur().
Item {
    id: island
    property real radius: 22
    default property alias content: body.data

    RectangularShadow {
        anchors.fill: parent
        radius: island.radius
        blur: 28
        offset.y: 8
        color: Theme.shadow
    }
    Rectangle {
        anchors.fill: parent
        radius: island.radius
        color: Theme.bar
        border.width: 1
        border.color: Theme.edge
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: island.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Theme.rim
        }
    }
    Item { id: body; anchors.fill: parent }
}
