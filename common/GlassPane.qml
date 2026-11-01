import QtQuick
import QtQuick.Effects

// Pływający panel treści w oknie Aster — ten sam materiał co widżety na pulpicie:
// szkło nad szkłem okna, wsunięte od krawędzi, z miękkim cieniem, połyskiem u góry,
// jasnym rantem i świetlną linią na górnej krawędzi. Pasek boczny zostaje na szkle okna,
// a treść „unosi się” nad nim jak karta.
Item {
    id: gp
    property real radius: 16
    default property alias content: body.data

    // Cień pod panelem (tylko z kartą graficzną)
    RectangularShadow {
        anchors.fill: parent
        radius: gp.radius
        blur: 26
        offset.y: 6
        spread: -6
        color: Qt.rgba(0.04, 0.05, 0.10, Theme.dark ? 0.38 : 0.10)
    }
    // Odcień szkła
    Rectangle {
        anchors.fill: parent
        radius: gp.radius
        color: Theme.paneGlass
    }
    // Połysk u góry
    Rectangle {
        anchors.fill: parent
        radius: gp.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, Theme.dark ? 0.06 : 0.40) }
            GradientStop { position: Math.min(0.5, 220 / Math.max(1, gp.height)); color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
        }
    }
    // Zewnętrzna linia i jasny rant od środka
    Rectangle {
        anchors.fill: parent
        radius: gp.radius
        color: "transparent"
        border.width: 1
        border.color: Theme.dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.07)
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: gp.radius - 1
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, Theme.dark ? 0.08 : 0.75)
    }
    // Świetlna linia na górnej krawędzi
    Rectangle {
        x: gp.radius; y: 1
        width: parent.width - 2 * x
        height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, Theme.dark ? 0.22 : 1) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
        }
    }
    Item { id: body; anchors.fill: parent; clip: true }
}
