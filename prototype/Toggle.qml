import QtQuick

// Przełącznik wł./wył. ze sprężystą gałką
Rectangle {
    id: tg
    property var t
    property bool checked: false
    signal toggled(bool on)
    width: 44; height: 26; radius: 13
    color: checked ? t.accent : t.fill
    border.width: checked ? 0 : 1
    border.color: t.line
    Behavior on color { ColorAnimation { duration: 160 } }
    Rectangle {
        y: 3
        x: tg.checked ? tg.width - width - 3 : 3
        width: knobArea.pressed ? 24 : 20; height: 20; radius: 10
        color: "white"
        Behavior on x { SpringAnimation { spring: 10; damping: 0.62; epsilon: 0.2 } }
        Behavior on width { NumberAnimation { duration: 120 } }
    }
    MouseArea { id: knobArea; anchors.fill: parent; onClicked: tg.toggled(!tg.checked) }
}
