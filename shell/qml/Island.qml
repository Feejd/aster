import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Aster.Ui

// „Ciekłe szkło”: rozmycie robi KWin (Platform.setBlur), a tu jest to, co daje wrażenie
// prawdziwego materiału — dwa cienie (miękki i kontaktowy), lekki odcień, połysk u góry,
// jasny rant od środka, cienka ciemna linia od zewnątrz i „odblask” na górnej krawędzi
// (świetlna linia gasnąca ku bokom, jak na kartach nowoczesnych stron).
// spotlight: miękka poświata podążająca za kursorem (spotX/spotY w układzie wyspy, spot 0…1).
// solid: true — czarna, prawie nieprzezroczysta wersja (dynamiczna wyspa na górze).
Item {
    id: island
    property real radius: 24
    property bool dark: Theme.dark
    property bool solid: false
    property real spot: 0
    property real spotX: width / 2
    property real spotY: height / 2
    property real shadowStrength: 1
    default property alias content: body.data

    readonly property bool deep: dark || solid

    // Cienie: szeroki „otaczający” i krótki tuż pod krawędzią
    RectangularShadow {
        anchors.fill: parent
        radius: island.radius
        blur: 48
        offset.y: 18
        spread: -8
        color: Qt.rgba(0, 0, 0, (island.deep ? 0.45 : 0.18) * island.shadowStrength)
    }
    RectangularShadow {
        anchors.fill: parent
        radius: island.radius
        blur: 5
        offset.y: 1
        color: Qt.rgba(0, 0, 0, (island.deep ? 0.35 : 0.09) * island.shadowStrength)
    }

    // Odcień szkła
    Rectangle {
        anchors.fill: parent
        radius: island.radius
        color: island.solid ? Qt.rgba(0.03, 0.03, 0.04, 0.94)
             : island.dark ? Qt.rgba(0.11, 0.11, 0.13, 0.46) : Qt.rgba(1, 1, 1, 0.38)
    }
    // Połysk: jasno u góry, gaśnie do połowy wysokości
    Rectangle {
        anchors.fill: parent
        radius: island.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, island.solid ? 0.09 : (island.dark ? 0.11 : 0.46)) }
            GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, island.deep ? 0.03 : 0.14) }
        }
    }
    // Poświata pod kursorem
    Shape {
        anchors.fill: parent
        visible: island.spot > 0.01
        opacity: island.spot
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: island.spotX; centerY: island.spotY
                focalX: island.spotX; focalY: island.spotY
                centerRadius: 120
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, island.deep ? 0.16 : 0.55) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
            }
            PathRectangle {
                width: island.width; height: island.height
                radius: island.radius
            }
        }
    }
    // Zewnętrzna linia i jasny rant
    Rectangle {
        anchors.fill: parent
        radius: island.radius
        color: "transparent"
        border.width: 1
        border.color: island.deep ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0, 0, 0, 0.09)
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: island.radius - 1
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, island.solid ? 0.10 : (island.dark ? 0.13 : 0.62))
    }
    // Odblask na górnej krawędzi
    Rectangle {
        x: island.radius * 0.6
        y: 1
        width: parent.width - 2 * x
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, island.deep ? 0.32 : 0.95) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
        }
    }
    Item { id: body; anchors.fill: parent }
}
