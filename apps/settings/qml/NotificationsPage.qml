pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Settings

// Powiadomienia: „Nie przeszkadzać”, próbne powiadomienie i włącznik dla każdego programu,
// który już coś wysłał (wyciszony program nie pokazuje dymków — licznik w doku zostaje)
Page {
    Section {
        footer: "Gdy „Nie przeszkadzać” jest włączone, powiadomienia nie wyskakują pod górną wyspą. Liczniki na ikonach w doku dalej się pojawiają."
        SettingRow {
            title: "Nie przeszkadzać"
            subtitle: Config.doNotDisturb ? "Włączone — powiadomienia są wyciszone" : "Wyłączone"
            icon: "moon"; colors: ["#A78BFA", "#6D28D9"]
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: Config.doNotDisturb; onToggled: on => Config.doNotDisturb = on }
        }
        SettingRow {
            title: "Dźwięk powiadomień"
            subtitle: "Krótki sygnał przy nowym powiadomieniu"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: { Conf.revision; return Conf.read("kdeglobals", ["Sounds"], "Enable", true); }
                onToggled: on => Conf.write("kdeglobals", ["Sounds"], "Enable", on)
            }
        }
        SettingRow {
            title: "Pokaż próbne powiadomienie"
            icon: "bell"
            TextButton { anchors.verticalCenter: parent.verticalCenter; text: "Pokaż"; onClicked: System.testNotification() }
        }
    }

    Section {
        title: "Programy"
        footer: "Programy pojawiają się tu, gdy wyślą pierwsze powiadomienie."
        Repeater {
            model: Config.notifyApps
            delegate: SettingRow {
                id: app
                required property var modelData
                title: modelData.name
                subtitle: Config.mutedApps.indexOf(modelData.id) >= 0 ? "Bez dymków" : "Dymki i dźwięk"
                Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Config.mutedApps.indexOf(app.modelData.id) < 0
                    onToggled: on => Config.setAppMuted(app.modelData.id, !on)
                }
            }
        }
        SettingRow {
            visible: Config.notifyApps.length === 0
            title: "Żaden program nie wysłał jeszcze powiadomienia"
        }
    }
}
