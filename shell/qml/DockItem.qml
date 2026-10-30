import QtQuick
import org.kde.kirigami as Kirigami
import Aster.Shell

// Jedna ikona w doku: przypięta aplikacja albo działające okno (dane z TaskManager).
Item {
    id: item
    required property var model
    required property int index
    signal activated()
    signal newInstance()

    width: 52
    height: 52

    Item {
        id: tile
        width: 48; height: 48
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        scale: area.pressed ? 0.92 : 1
        transformOrigin: Item.Bottom
        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutQuad } }

        Kirigami.Icon {
            anchors.fill: parent
            anchors.margins: 2
            source: item.model.decoration
            active: area.containsMouse
        }
    }

    // Kropka pod działającą aplikacją; dłuższa kreska — aktywne okno
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -7
        height: 4; radius: 2
        width: item.model.IsActive ? 14 : 4
        visible: item.model.IsWindow === true || item.model.IsStartup === true
        color: item.model.IsActive ? Theme.accent : Theme.text
        opacity: item.model.IsActive ? 1 : 0.55
        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
    }

    // Podpowiedź z nazwą
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: tile.top
        anchors.bottomMargin: 22
        width: tipText.implicitWidth + 20; height: 28; radius: 9
        color: Theme.dark ? "#2A2C33" : "#FFFFFF"
        border.width: 1; border.color: Theme.edge
        opacity: area.containsMouse && !area.pressed ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Text {
            id: tipText
            anchors.centerIn: parent
            text: item.model.display || ""
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: (m) => m.button === Qt.MiddleButton ? item.newInstance() : item.activated()
    }
}
