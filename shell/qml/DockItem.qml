import QtQuick
import org.kde.kirigami as Kirigami
import Aster.Shell
import Aster.Ui

// Jedna ikona w doku: przypięta aplikacja albo działające okno (dane z TaskManager).
Item {
    id: item
    required property var model
    required property int index
    signal activated()
    signal newInstance()

    width: 60
    height: 60

    // Ikona w kształcie squircle; po najechaniu lekko się unosi, po wciśnięciu przyciemnia i zmniejsza
    AppIcon {
        id: tile
        size: 52
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4 + (area.containsMouse && !area.pressed ? 3 : 0)
        desktopId: item.desktopId
        source: item.model.decoration
        scale: area.pressed ? 0.9 : 1
        transformOrigin: Item.Bottom
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 160; easing.type: Easing.OutQuint } }
        Rectangle {
            anchors.fill: parent
            radius: width * 0.26
            color: "black"
            opacity: area.pressed ? 0.18 : 0
            Behavior on opacity { NumberAnimation { duration: 90 } }
        }
    }

    // Liczba nieprzeczytanych (komunikatory, poczta, aplikacje webowe)
    readonly property string desktopId: {
        const u = (item.model.LauncherUrlWithoutIcon || "").toString();
        return u.replace(/^.*[\/:]/, "").replace(/\.desktop$/, "");
    }
    readonly property int badge: Platform.badges[desktopId] || 0
    Rectangle {
        x: tile.x + tile.width - width + 6
        y: tile.y - 4
        z: 2
        height: 20
        width: Math.max(20, badgeText.implicitWidth + 12)
        radius: 10
        color: "#F0524F"
        border.width: 2
        border.color: Theme.dark ? "#2A2C33" : "white"
        scale: item.badge > 0 ? 1 : 0
        visible: scale > 0.01
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
        Text {
            id: badgeText
            anchors.centerIn: parent
            text: item.badge > 99 ? "99+" : String(item.badge)
            color: "white"
            font.family: Theme.font; font.pixelSize: 11; font.letterSpacing: 0.1; font.weight: Font.DemiBold
        }
    }

    // Kropka pod działającą aplikacją (jaśniejsza przy aktywnym oknie)
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -5
        width: 5; height: 5; radius: 2.5
        visible: item.model.IsWindow === true || item.model.IsStartup === true
        color: Theme.text
        opacity: item.model.IsActive ? 0.9 : 0.45
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }

    // Podpowiedź z nazwą (ciemna pigułka nad ikoną)
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: tile.top
        anchors.bottomMargin: 16
        width: tipText.implicitWidth + 20; height: 26; radius: 8
        color: Qt.rgba(0.09, 0.09, 0.1, 0.9)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.08)
        opacity: area.containsMouse && !area.pressed ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Text {
            id: tipText
            anchors.centerIn: parent
            text: item.model.display || ""
            color: "white"
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
