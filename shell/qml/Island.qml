import QtQuick
import QtQuick.Effects
import Aster.Shell
import Aster.Ui

// „Ciekłe szkło”: rozmycie robi KWin (Platform.setBlur), a tu jest to, co daje wrażenie
// prawdziwego materiału — dwa cienie (miękki i kontaktowy), lekki odcień, połysk u góry,
// jasny rant od środka i cienka ciemna linia od zewnątrz.
// solid: true — czarna, prawie nieprzezroczysta wersja (górna wyspa w stylu „Dynamic Island”).
Item {
    id: island
    property real radius: 24
    property bool dark: Theme.dark
    property bool solid: false
    default property alias content: body.data

    // Cienie: szeroki „otaczający” i krótki tuż pod krawędzią
    RectangularShadow {
        anchors.fill: parent
        radius: island.radius
        blur: 44
        offset.y: 16
        spread: -6
        color: Qt.rgba(0, 0, 0, island.dark || island.solid ? 0.42 : 0.16)
    }
    RectangularShadow {
        anchors.fill: parent
        radius: island.radius
        blur: 6
        offset.y: 1
        color: Qt.rgba(0, 0, 0, island.dark || island.solid ? 0.35 : 0.10)
    }

    // Odcień szkła
    Rectangle {
        anchors.fill: parent
        radius: island.radius
        color: island.solid ? Qt.rgba(0.04, 0.04, 0.05, 0.92)
             : island.dark ? Qt.rgba(0.12, 0.12, 0.14, 0.48) : Qt.rgba(1, 1, 1, 0.42)
    }
    // Połysk: jasno u góry, gaśnie do połowy wysokości
    Rectangle {
        anchors.fill: parent
        radius: island.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, island.solid ? 0.10 : (island.dark ? 0.12 : 0.42)) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, island.dark || island.solid ? 0.02 : 0.10) }
        }
    }
    // Zewnętrzna linia i jasny rant
    Rectangle {
        anchors.fill: parent
        radius: island.radius
        color: "transparent"
        border.width: 1
        border.color: island.dark || island.solid ? Qt.rgba(0, 0, 0, 0.5) : Qt.rgba(0, 0, 0, 0.10)
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: island.radius - 1
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, island.solid ? 0.12 : (island.dark ? 0.16 : 0.7))
    }
    Item { id: body; anchors.fill: parent }
}
