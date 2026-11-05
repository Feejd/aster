import QtQuick
import QtQuick.Effects
import Aster.Ui

// Przełącznik jak w macOS: pigułka w kolorze akcentu, biała gałka przesuwa się sprężyście
Item {
    id: tg
    property bool checked: false
    signal toggled(bool on)
    width: 40; height: 24
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: tg.checked ? Theme.accent : (Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.13))
        Behavior on color { ColorAnimation { duration: 160 } }
    }
    RectangularShadow {
        x: knob.x; y: knob.y; width: knob.width; height: knob.height
        radius: knob.radius; blur: 4; offset.y: 1
        color: Qt.rgba(0, 0, 0, 0.22)
    }
    Rectangle {
        id: knob
        y: 2
        x: tg.checked ? tg.width - width - 2 : 2
        width: area.pressed ? 24 : 20; height: 20
        radius: 10
        color: "white"
        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        Behavior on width { NumberAnimation { duration: 120 } }
    }
    MouseArea {
        id: area
        anchors.fill: parent; anchors.margins: -6
        cursorShape: Qt.PointingHandCursor
        onClicked: tg.toggled(!tg.checked)
    }
}
