import QtQuick

// Podgląd przyciągnięcia: gdy okno dociągniesz do górnej krawędzi, pokazuje,
// gdzie wypełni ekran. Puść przycisk — okno przejdzie na pełny ekran.
Item {
    id: sp
    property var t
    property rect geo
    property bool on: false

    x: geo.x; y: geo.y; width: geo.width; height: geo.height
    opacity: on ? 1 : 0
    visible: opacity > 0.01
    scale: on ? 1 : 0.94
    transformOrigin: Item.Top
    Behavior on opacity { NumberAnimation { duration: sp.on ? 140 : 110; easing.type: Easing.OutQuad } }
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 8
        radius: 16
        color: Qt.rgba(sp.t.accent.r, sp.t.accent.g, sp.t.accent.b, 0.16)
        border.width: 1.5
        border.color: Qt.rgba(sp.t.accent.r, sp.t.accent.g, sp.t.accent.b, 0.55)
        Rectangle {
            anchors.fill: parent; anchors.margins: 1.5
            radius: 15
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.35)
        }
    }
}
