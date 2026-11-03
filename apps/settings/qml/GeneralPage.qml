import QtQuick
import Aster.Ui
import Aster.Settings

// Ogólne: „O tym komputerze” (wersja Aster, sprzęt, dysk) i skróty do daty, języka, aplikacji domyślnych
Page {
    id: gp
    readonly property var a: System.about

    // Karta z logo
    Rectangle {
        width: parent.width; height: 168
        radius: 18
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.dark ? "#1B2340" : "#EEF2FF" }
            GradientStop { position: 1; color: Theme.dark ? "#2A1B40" : "#F5EEFF" }
        }
        border.width: 1; border.color: Theme.line
        Row {
            x: 28; anchors.verticalCenter: parent.verticalCenter
            spacing: 22
            AppIcon { desktopId: "aster-start"; size: 96; anchors.verticalCenter: parent.verticalCenter }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text { text: "Aster"; color: Theme.text; font.family: Theme.font; font.pixelSize: 34; font.weight: Font.Bold; font.letterSpacing: -0.9 }
                Text { text: "Wersja 0.1 „Świt”"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 14 }
                Text { text: "na bazie " + gp.a.os; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
            }
        }
    }

    Section {
        title: "O tym komputerze"
        SettingRow { title: "Nazwa"; value: Accounts.hostName; chevron: true; onClicked: { hostField.text = Accounts.hostName; hostSheet.open(); } }
        SettingRow { title: "Komputer"; value: gp.a.model }
        SettingRow { title: "Procesor"; value: gp.a.cpu }
        SettingRow { title: "Pamięć"; value: gp.a.memory }
        SettingRow { title: "Działa od"; value: gp.a.uptime }
        SettingRow { title: "Jądro Linux"; value: gp.a.kernel }
    }

    Section {
        title: "Dysk"
        Item {
            width: parent.width; height: 74
            Text {
                x: 16; y: 14
                text: gp.a.diskFree + " wolne z " + gp.a.diskTotal
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
            }
            Rectangle {
                x: 16; y: 40
                width: parent.width - 32; height: 12; radius: 6
                color: Theme.fill
                Rectangle {
                    width: Math.max(height, parent.width * gp.a.diskUsed); height: parent.height; radius: 6
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.35) }
                        GradientStop { position: 1; color: Theme.accent }
                    }
                }
            }
        }
    }

    Section {
        SettingRow { title: "Pamięć — co zajmuje miejsce"; icon: "drive"; chevron: true; onClicked: gp.navigate("storage") }
        SettingRow { title: "Aktualizacje oprogramowania"; icon: "download"; chevron: true; onClicked: System.run("aster-store") }
        SettingRow { title: "Data i czas"; icon: "clock"; chevron: true; onClicked: gp.navigate("datetime") }
        SettingRow { title: "Język i region"; icon: "translate"; chevron: true; onClicked: gp.navigate("language") }
        SettingRow { title: "Aplikacje domyślne"; icon: "apps"; chevron: true; onClicked: gp.navigate("apps") }
        SettingRow { title: "Skróty klawiszowe"; icon: "keyboard"; chevron: true; onClicked: gp.navigate("shortcuts") }
    }

    Section {
        footer: "Pełne ustawienia KDE — dla zaawansowanych. Większość z nich jest już w Ustawieniach Aster."
        SettingRow { title: "Zaawansowane ustawienia (KDE)"; icon: "sliders"; chevron: true; onClicked: System.run("systemsettings") }
    }

    Sheet {
        id: hostSheet
        title: "Nazwa komputera"
        subtitle: "Pod tą nazwą komputer widać w sieci, w Bluetooth i przy udostępnianiu plików."
        acceptEnabled: hostField.text.trim().length > 0
        Field { id: hostField; placeholder: "np. Laptop Dominika" }
        onAccepted: Accounts.setHostName(hostField.text)
    }
}
