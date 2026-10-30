import QtQuick
import QtQuick.Effects

// Pływająca szklana wyspa na dole ekranu (Start, dok, stan)
Item {
    id: isl
    property var t
    property bool dark: false
    property Item backdrop
    property real baseX: 0     // pozycja rodzica we współrzędnych tła
    property real baseY: 0
    default property alias content: inner.data

    height: 60

    RectangularShadow {
        anchors.fill: parent
        radius: 20
        blur: 30
        offset.y: 10
        color: Qt.rgba(0, 0, 0, isl.dark ? 0.35 : 0.12)
    }
    Glass {
        anchors.fill: parent
        backdrop: isl.backdrop
        sx: isl.baseX + isl.x
        sy: isl.baseY + isl.y
        radius: 20
        tint: isl.t.bar
        edge: isl.t.edge
        rim: isl.t.rim
    }
    Item { id: inner; anchors.fill: parent }
}
