import QtQuick
import QtQuick.Effects
import Aster.Ui

// Powierzchnia powłoki: pełny, matowy kolor, cienka krawędź i jeden miękki cień.
// solid: ciemna wersja (dynamiczna wyspa). flat: bez tła, element leży wprost na górnym pasku.
// spot, spotX, spotY zostają w interfejsie dla zgodności z wywołaniami, ale matowa powierzchnia ich nie rysuje.
Item {
    id: island
    property real radius: 14
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
        blur: 26
        offset.y: 8
        color: Qt.rgba(0.08, 0.09, 0.12, (island.dark || island.solid ? 0.5 : 0.2) * island.shadowStrength)
    }
    Rectangle {
        visible: !island.flat
        anchors.fill: parent
        radius: island.radius
        color: island.solid ? "#17181C" : island.dark ? "#232428" : "#F7F7F5"
        border.width: 1
        border.color: island.solid ? "#2B2C31" : island.dark ? "#3A3B41" : "#C9C9C4"
    }
    Item { id: body; anchors.fill: parent }
}
