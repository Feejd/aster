import QtQuick
import QtQuick.Effects
import Aster.Ui

// Powierzchnia powłoki: pełny, matowy kolor, cienka krawędź i jeden miękki cień.
// solid: ciemna wersja (dynamiczna wyspa). flat: bez tła, element leży wprost na górnym pasku.
// spot, spotX, spotY zostają w interfejsie dla zgodności z wywołaniami, ale matowa powierzchnia ich nie rysuje.
Item {
    id: island
    property real radius: 24
    property bool dark: Theme.dark
    property bool solid: false
    property bool flat: false
    property real spot: 0
    property real spotX: width / 2
    property real spotY: height / 2
    property real shadowStrength: 1
    default property alias content: body.data

    RectangularShadow {
        visible: !island.flat
        anchors.fill: parent
        radius: island.radius
        blur: 40
        offset.y: 12
        color: Qt.rgba(0.08, 0.09, 0.12, (island.dark || island.solid ? 0.5 : 0.2) * island.shadowStrength)
    }
    Rectangle {
        visible: !island.flat
        anchors.fill: parent
        radius: island.radius
        color: island.solid ? "#17181C" : island.dark ? "#1C1D21" : "#FFFFFF"
        border.width: island.dark || island.solid ? 1 : 0
        border.color: island.solid ? "#26272C" : "#2A2B30"
    }
    Item { id: body; anchors.fill: parent }
}
