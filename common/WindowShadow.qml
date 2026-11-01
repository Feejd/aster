import QtQuick
import QtQuick.Effects

// Cień okna Aster w trzech warstwach, jak w fizycznym świetle: szeroki rozproszony,
// główny pod oknem i krótki kontaktowy przy krawędzi. Okno w tle ma cień płytszy i jaśniejszy,
// więc aktywne okno wyraźnie „unosi się” nad resztą.
Item {
    id: ws
    required property Window window
    required property Item frame
    property real radius: 14
    readonly property bool lifted: window.active || WindowEffects.preview
    property real depth: lifted ? 1 : 0.55
    Behavior on depth { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    readonly property real a: Theme.dark ? 1.6 : 1

    x: frame.x; y: frame.y
    width: frame.width; height: frame.height
    scale: frame.scale

    RectangularShadow {
        anchors.fill: parent
        radius: ws.radius
        blur: 80 * ws.depth + 20
        offset.y: 34 * ws.depth
        spread: -12
        color: Qt.rgba(0.06, 0.07, 0.12, 0.16 * ws.depth * ws.a)
    }
    RectangularShadow {
        anchors.fill: parent
        radius: ws.radius
        blur: 22
        offset.y: 8 * ws.depth + 2
        spread: -2
        color: Qt.rgba(0.06, 0.07, 0.12, (0.10 + 0.08 * ws.depth) * ws.a)
    }
    RectangularShadow {
        anchors.fill: parent
        radius: ws.radius
        blur: 3
        offset.y: 1
        color: Qt.rgba(0, 0, 0, 0.10 * ws.a)
    }
}
