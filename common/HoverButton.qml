import QtQuick
import QtQuick.Window

// Prostokąt reagujący na najechanie i wciśnięcie; `tip` — podpowiedź po chwili trzymania kursora (przyciski z samą ikoną)
Rectangle {
    id: hb
    property alias hovered: area.containsMouse
    property alias down: area.pressed
    property color baseColor: "transparent"
    property string tip
    signal clicked()

    radius: 8
    color: area.containsMouse && enabled ? Theme.hover : baseColor
    scale: area.pressed ? 0.96 : 1
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutQuad } }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: if (hb.enabled) hb.clicked()
        onContainsMouseChanged: if (containsMouse && hb.tip !== "") tipTimer.restart(); else { tipTimer.stop(); tipLoader.active = false; }
        onPressed: { tipTimer.stop(); tipLoader.active = false; }
    }
    Timer { id: tipTimer; interval: 550; onTriggered: tipLoader.active = hb.visible && area.containsMouse }
    Loader {
        id: tipLoader
        active: false
        sourceComponent: Rectangle {
            id: tipBox
            parent: hb.Window.contentItem
            z: 10000
            readonly property point at: hb.mapToItem(parent, hb.width / 2, hb.height)
            x: Math.max(6, Math.min(parent.width - width - 6, at.x - width / 2))
            y: at.y + 8 + height > parent.height ? hb.mapToItem(parent, 0, 0).y - height - 8 : at.y + 8
            width: tipText.implicitWidth + 18; height: tipText.implicitHeight + 10
            radius: 7
            color: Theme.dark ? "#F2F3F6" : "#22252C"
            opacity: 0
            Component.onCompleted: opacity = 1
            Behavior on opacity { NumberAnimation { duration: 120 } }
            Text {
                id: tipText
                anchors.centerIn: parent
                text: hb.tip
                color: Theme.dark ? "#16181D" : "white"
                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
            }
        }
    }
}
