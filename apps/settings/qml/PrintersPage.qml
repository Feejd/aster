pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Settings

// Drukarki: zainstalowane i znalezione w sieci. Nowoczesne drukarki (AirPrint, IPP Everywhere, Mopria)
// działają bez sterowników — wystarczy, że są w tej samej sieci.
Page {
    id: pg
    readonly property var mine: Printers.printers.filter(p => p.installed)
    readonly property var found: Printers.printers.filter(p => !p.installed)

    Section {
        title: "Moje drukarki"
        footer: "Domyślna drukarka jest od razu wybrana w oknie drukowania każdego programu."
        Repeater {
            model: pg.mine
            delegate: SettingRow {
                id: pr
                required property var modelData
                title: modelData.label
                subtitle: (modelData.isDefault ? "Domyślna · " : "") + (modelData.state === "printing" ? "Drukuje" : modelData.state === "stopped" ? "Wstrzymana" : "Gotowa")
                icon: "printer"; colors: ["#94A3B8", "#475569"]
                TextButton { visible: !pr.modelData.isDefault; anchors.verticalCenter: parent.verticalCenter; text: "Ustaw jako domyślną"; onClicked: Printers.setDefault(pr.modelData.name) }
                TextButton { anchors.verticalCenter: parent.verticalCenter; text: "Strona testowa"; onClicked: Printers.printTestPage(pr.modelData.name) }
                HoverButton {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28; radius: 14
                    onClicked: Printers.remove(pr.modelData.name)
                    Icon { anchors.centerIn: parent; d: Icons.trash; size: 15; color: Theme.text2 }
                }
            }
        }
        SettingRow {
            visible: pg.mine.length === 0
            title: Printers.available ? "Nie dodano jeszcze drukarki" : "Drukowanie nie jest dostępne (brak usługi CUPS)"
        }
    }

    Section {
        visible: Printers.available
        title: "Znalezione w sieci"
        footer: "Włącz drukarkę i podłącz ją do tej samej sieci Wi‑Fi co komputer — pojawi się tutaj sama."
        Repeater {
            model: pg.found
            delegate: SettingRow {
                id: fp
                required property var modelData
                title: modelData.label
                subtitle: "Działa bez sterowników"
                icon: "printer"
                TextButton { anchors.verticalCenter: parent.verticalCenter; primary: true; text: "Dodaj"; onClicked: Printers.add(fp.modelData.name) }
            }
        }
        SettingRow {
            visible: pg.found.length === 0
            title: Printers.searching ? "Szukam drukarek…" : "Nie widać innych drukarek"
        }
    }
}
