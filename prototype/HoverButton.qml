import QtQuick

// Przycisk bez ramki: tło przy najechaniu, lekkie wciśnięcie przy kliknięciu
Rectangle {
    id: b
    property var t
    property bool active: false
    property color activeColor: t.accentSoft
    default property alias content: inner.data
    readonly property bool hovered: area.containsMouse
    readonly property bool down: area.pressed
    signal clicked()

    radius: 10
    color: active ? activeColor : (area.containsMouse ? t.hover : "transparent")
    scale: area.pressed ? 0.96 : 1

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }

    Item { id: inner; anchors.fill: parent }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: b.clicked()
    }
}
