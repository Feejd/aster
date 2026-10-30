import QtQuick
import QtQuick.Effects
import "Icons.js" as I

// Ekran blokady: rozmyta tapeta, duży zegar, użytkownik. Enter albo klik odblokowuje —
// ekran unosi się w górę i rozmywa, a pulpit wyłania się spod niego.
Item {
    id: ls
    property var t
    property bool dark: false
    property string variant: "swit"
    property bool locked: false
    property date now: new Date()
    signal unlockRequested()

    anchors.fill: parent
    visible: lift < 0.999
    property real lift: locked ? 0 : 1        // 0 = zablokowany, 1 = zniknął
    Behavior on lift { NumberAnimation { duration: ls.locked ? 300 : 340; easing.type: ls.locked ? Easing.OutCubic : Easing.OutQuint } }

    onLockedChanged: if (locked) { field.text = ""; focusTimer.start(); }
    Timer { id: focusTimer; interval: 50; onTriggered: field.forceActiveFocus() }
    Timer { interval: 1000; running: ls.visible; repeat: true; onTriggered: ls.now = new Date() }

    opacity: 1 - lift
    transform: Translate { y: -ls.height * 0.12 * ls.lift }

    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blur: 0.7; blurMax: 48; brightness: ls.dark ? -0.05 : -0.08; saturation: 0.2 }
        Wallpaper { anchors.fill: parent; dark: ls.dark; variant: ls.variant }
    }

    MouseArea { anchors.fill: parent; onClicked: field.forceActiveFocus() }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.12
        spacing: -10
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0, 0, 0, 0.25); shadowBlur: 0.8; shadowVerticalOffset: 2 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.locale("pl_PL").toString(ls.now, "dddd, d MMMM")
            color: Qt.rgba(1, 1, 1, 0.92)
            font.pixelSize: 24; font.weight: Font.Medium
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(ls.now, "HH:mm")
            color: "white"
            font.pixelSize: 168; font.weight: Font.DemiBold; font.letterSpacing: -5
            font.features: { "tnum": 1 }
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.12
        spacing: 14
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 76; height: 76; radius: 38
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(ls.t.accent, 1.35) }
                GradientStop { position: 1; color: ls.t.accent }
            }
            border.width: 3; border.color: Qt.rgba(1, 1, 1, 0.5)
            Text { anchors.centerIn: parent; text: "U"; color: "white"; font.pixelSize: 30; font.weight: Font.DemiBold }
        }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Użytkownik"; color: "white"; font.pixelSize: 18; font.weight: Font.DemiBold }
        Rectangle {
            id: box
            anchors.horizontalCenter: parent.horizontalCenter
            width: 310; height: 44; radius: 22
            color: Qt.rgba(1, 1, 1, 0.22)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.35)
            TextInput {
                id: field
                anchors.left: parent.left; anchors.leftMargin: 18
                anchors.right: go.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                color: "white"; font.pixelSize: 15
                echoMode: TextInput.Password
                passwordCharacter: "•"
                Text { visible: !field.text; anchors.verticalCenter: parent.verticalCenter; text: "Naciśnij Enter, aby odblokować"; color: Qt.rgba(1, 1, 1, 0.75); font.pixelSize: 14 }
                Keys.onReturnPressed: ls.unlockRequested()
                Keys.onEnterPressed: ls.unlockRequested()
            }
            Rectangle {
                id: go
                anchors.right: parent.right; anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                width: 34; height: 34; radius: 17
                color: goArea.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.85)
                Icon { anchors.centerIn: parent; d: I.arrow; size: 16; stroke: 2.2; color: ls.t.accent }
                MouseArea { id: goArea; anchors.fill: parent; hoverEnabled: true; onClicked: ls.unlockRequested() }
            }
        }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Prototyp: hasło nie jest sprawdzane"; color: Qt.rgba(1, 1, 1, 0.6); font.pixelSize: 12 }
    }
}
