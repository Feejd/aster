import QtQuick
import Aster.Ui
import Aster.Settings

// Konto: zdjęcie (inicjał), imię, hasło, blokada
Page {
    Item {
        width: parent.width; height: 170
        Column {
            anchors.centerIn: parent
            spacing: 10
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 92; height: 92; radius: 46
                gradient: Gradient {
                    GradientStop { position: 0; color: "#7C9BFF" }
                    GradientStop { position: 1; color: "#8B5CF6" }
                }
                Text { anchors.centerIn: parent; text: System.fullName.charAt(0).toUpperCase(); color: "white"; font.family: Theme.font; font.pixelSize: 40; font.weight: Font.DemiBold }
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: System.fullName; color: Theme.text; font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: System.userName + " · Administrator"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
        }
    }
    Section {
        SettingRow { title: "Imię, zdjęcie i hasło"; icon: "user"; chevron: true; onClicked: System.openKcm("kcm_users") }
        SettingRow { title: "Zablokuj ekran"; icon: "lock"; chevron: true; onClicked: System.run("loginctl", ["lock-session"]) }
    }
}
