pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Settings

// Aplikacje: czym otwierać strony, pocztę, pliki, zdjęcia, muzykę, filmy i dokumenty
// oraz programy, które uruchamiają się same po zalogowaniu
Page {
    id: ap
    readonly property var colors: ({
        browser: ["#6EF0D6", "#2A62E8"], mail: ["#7DD3FC", "#2563EB"], files: ["#74CCFF", "#2457E6"], terminal: ["#6B6D7C", "#14151B"],
        text: ["#FFCB73", "#EF6420"], image: ["#FFB0DC", "#B23DE0"], music: ["#FFA394", "#E2283E"], video: ["#C4B5FD", "#7C3AED"], pdf: ["#FF9AAE", "#DC2550"]
    })

    Section {
        title: "Aplikacje domyślne"
        footer: "Program, którym otwierają się linki i pliki danego rodzaju (np. dwukliknięcie zdjęcia w Plikach)."
        Repeater {
            model: Apps.categories
            delegate: SettingRow {
                id: cat
                required property var modelData
                title: modelData.name
                icon: modelData.icon
                colors: ap.colors[modelData.id] || ["#A3A9B5", "#4B5262"]
                Dropdown {
                    anchors.verticalCenter: parent.verticalCenter
                    model: cat.modelData.choices.map(c => ({ label: c.name, value: c.id }))
                    value: cat.modelData.current
                    placeholder: "Brak"
                    onPicked: v => Apps.setDefault(cat.modelData.id, v)
                }
            }
        }
    }

    Section {
        title: "Uruchamiane po zalogowaniu"
        footer: "Te programy włączają się same, gdy zaczynasz pracę. Mniej programów — szybszy start."
        Repeater {
            model: Apps.autostart
            delegate: SettingRow {
                id: au
                required property var modelData
                title: modelData.name
                Toggle { anchors.verticalCenter: parent.verticalCenter; checked: au.modelData.enabled; onToggled: on => Apps.setAutostartEnabled(au.modelData.file, on) }
                HoverButton {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28; radius: 14
                    onClicked: Apps.removeAutostart(au.modelData.file)
                    Icon { anchors.centerIn: parent; d: Icons.trash; size: 15; color: Theme.text2 }
                }
            }
        }
        SettingRow {
            visible: Apps.autostart.length === 0
            title: "Żaden program nie uruchamia się sam"
        }
        SettingRow {
            title: "Dodaj program"
            titleColor: Theme.accentText
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                placeholder: "Wybierz program"
                model: Apps.installed.map(a => ({ label: a.name, value: a.id }))
                value: ""
                onPicked: v => Apps.addAutostart(v)
            }
        }
    }
}
