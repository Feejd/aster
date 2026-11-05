pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Settings

// Aktualizacje systemu: pobierają się w tle, a komputer restartuje się dopiero wtedy, gdy chcesz
Page {
    id: up
    Component.onCompleted: Updates.refresh()

    Section {
        footer: Updates.message
        SettingRow {
            title: "Aster " + (Updates.version || "…")
            subtitle: Updates.installedOn ? "Z dnia " + Updates.installedOn : ""
            icon: "gear"; colors: ["#A3A9B5", "#4B5262"]
            TextButton {
                anchors.verticalCenter: parent.verticalCenter
                text: Updates.checking ? "Sprawdzam…" : "Sprawdź teraz"
                busy: Updates.checking
                onClicked: Updates.check()
            }
        }
        SettingRow {
            visible: Updates.readyVersion !== ""
            title: "Nowa wersja jest gotowa"
            subtitle: "Aster " + Updates.readyVersion + ". Instalacja kończy się przy wyłączaniu i trwa kilka minut."
            icon: "download"; colors: ["#86EFAC", "#16A34A"]
            TextButton {
                anchors.verticalCenter: parent.verticalCenter
                text: "Uruchom ponownie"
                primary: true
                onClicked: Updates.restart()
            }
        }
    }

    Section {
        title: "Gdy coś przestanie działać"
        footer: Updates.rollbackPending ? "Poprzednia wersja uruchomi się przy następnym starcie komputera."
                                        : "Twoje pliki i programy zostają bez zmian."
        SettingRow {
            title: "Wróć do poprzedniej wersji"
            subtitle: Updates.previousVersion !== "" ? "Aster " + Updates.previousVersion : "Na razie nie ma poprzedniej wersji"
            TextButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: Updates.previousVersion !== "" && Updates.readyVersion === ""
                text: Updates.rollbackPending ? "Uruchom ponownie" : "Przywróć"
                onClicked: { if (Updates.rollbackPending) Updates.restart(); else Updates.rollback(); }
            }
        }
    }

    Section {
        title: "Programy"
        SettingRow { title: "Aktualizacje programów"; icon: "apps"; chevron: true; onClicked: System.run("aster-store") }
    }
}
