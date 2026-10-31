import QtQuick
import Aster.Ui
import Aster.Settings

// Ekran: nocne światło i skrót do rozdzielczości, skalowania i układu monitorów
Page {
    Section {
        footer: "Nocne światło ociepla kolory ekranu, żeby wieczorem mniej męczyły oczy. Jasność zmienisz w centrum sterowania."
        SettingRow {
            title: "Nocne światło"
            subtitle: System.nightLight ? "Włączone" : "Wyłączone"
            icon: "moon"; colors: ["#FDBA74", "#EA580C"]
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: System.nightLight; onToggled: on => System.setNightLight(on) }
        }
    }
    Section {
        SettingRow {
            title: "Rozdzielczość i skalowanie"
            subtitle: "Rozmiar wszystkiego na ekranie, odświeżanie, kilka monitorów"
            icon: "desktop"; colors: ["#7DD3FC", "#2563EB"]
            chevron: true
            onClicked: System.openKcm("kcm_kscreen")
        }
    }
}
