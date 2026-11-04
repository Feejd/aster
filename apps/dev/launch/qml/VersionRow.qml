import QtQuick
import Aster.Ui
import Aster.Launch

// Jedna wersja w historii: numer, kiedy, z jakiego zatwierdzenia, stan; „Przywróć” dla wersji, które wciąż są na serwerze
Item {
    id: vr
    required property var entry
    required property var project
    required property var app
    readonly property bool live: entry.v === project.current
    readonly property bool restorable: !live && entry.status !== "failed" && (project.target !== "ssh" ? true : !!entry.onServer)
    width: parent ? parent.width : 0
    height: 56

    Rectangle { width: parent.width; height: 1; color: Theme.line }
    Rectangle {
        id: badge
        y: 12
        width: 44; height: 32; radius: 9
        color: vr.live ? Theme.accent : Theme.fill
        Text { anchors.centerIn: parent; text: "v" + vr.entry.v; color: vr.live ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold }
    }
    Column {
        x: 58; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - right.width - 12
        spacing: 2
        Row {
            spacing: 8
            Text { text: vr.app.when(vr.entry.time); color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
            Rectangle {
                visible: vr.entry.status !== "ok"
                anchors.verticalCenter: parent.verticalCenter
                width: stText.implicitWidth + 12; height: 18; radius: 9
                color: vr.entry.status === "failed" ? Qt.rgba(0.9, 0.28, 0.3, 0.16) : Qt.rgba(0.96, 0.65, 0.14, 0.18)
                Text {
                    id: stText
                    anchors.centerIn: parent
                    text: vr.entry.status === "failed" ? "nieudana" : "nie odpowiadała"
                    color: vr.entry.status === "failed" ? Theme.danger : (Theme.dark ? "#FFC56B" : "#A86200")
                    font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium
                }
            }
        }
        Text {
            width: parent.width; elide: Text.ElideRight
            text: vr.entry.commit ? vr.entry.commit + "  " + (vr.entry.subject || "") + (vr.entry.dirty ? " · z niezatwierdzonymi zmianami" : "")
                  : vr.entry.status === "failed" ? (vr.entry.message || "") : (vr.entry.url || "folder bez gita")
            color: Theme.text2; font.family: vr.entry.commit ? "JetBrains Mono" : Theme.font; font.pixelSize: 12
        }
    }
    Item {
        id: right
        anchors.right: parent.right
        width: Math.max(liveTag.visible ? liveTag.width : 0, restore.visible ? restore.width : 0, gone.visible ? gone.implicitWidth : 0)
        height: parent.height
        Rectangle {
            id: liveTag
            visible: vr.live
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: liveRow.implicitWidth + 18; height: 26; radius: 13
            color: Qt.rgba(0.18, 0.75, 0.44, 0.16)
            Row {
                id: liveRow
                anchors.centerIn: parent
                spacing: 6
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; radius: 3.5; color: "#2FBF71" }
                Text { text: "Na produkcji"; color: Theme.dark ? "#7EE2A8" : "#167A45"; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
            }
        }
        Pill {
            id: restore
            visible: vr.restorable
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            small: true
            text: "Przywróć"
            iconPath: Icons.undo
            enabled: !Launch.running && !Launch.preparing && Launch.plan.length === 0
            onClicked: vr.app.rollback(vr.entry.v)
        }
        Text {
            id: gone
            visible: !vr.live && !vr.restorable && vr.entry.status !== "failed"
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: "usunięta z serwera"
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
        }
    }
}
