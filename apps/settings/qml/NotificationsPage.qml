import QtQuick
import Aster.Ui
import Aster.Settings

// Powiadomienia: „Nie przeszkadzać”, próbne powiadomienie, ustawienia poszczególnych aplikacji
Page {
    Section {
        footer: "Gdy „Nie przeszkadzać” jest włączone, powiadomienia nie wyskakują pod górną wyspą. Liczniki na ikonach w doku dalej się pojawiają."
        SettingRow {
            title: "Nie przeszkadzać"
            subtitle: Config.doNotDisturb ? "Włączone — powiadomienia są wyciszone" : "Wyłączone"
            icon: "moon"; colors: ["#A78BFA", "#6D28D9"]
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: Config.doNotDisturb; onToggled: on => Config.doNotDisturb = on }
        }
    }
    Section {
        SettingRow {
            title: "Pokaż próbne powiadomienie"
            subtitle: "Zobacz, jak wygląda powiadomienie w Aster"
            icon: "bell"
            TextButton { anchors.verticalCenter: parent.verticalCenter; text: "Pokaż"; onClicked: System.testNotification() }
        }
        SettingRow {
            title: "Powiadomienia aplikacji"
            subtitle: "Które programy mogą wysyłać powiadomienia i z dźwiękiem czy bez"
            chevron: true
            onClicked: System.openKcm("kcm_notifications")
        }
    }
}
