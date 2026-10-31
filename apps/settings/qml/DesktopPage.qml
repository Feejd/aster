import QtQuick
import Aster.Ui
import Aster.Settings

// Pulpit i dok: zegar na pulpicie, procent baterii, skróty do zachowania okien
Page {
    Section {
        title: "Pulpit"
        SettingRow {
            title: "Zegar na pulpicie"
            subtitle: "Duża godzina i data w lewym górnym rogu"
            icon: "clock"; colors: ["#FDBA74", "#EA580C"]
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: Config.desktopClock; onToggled: on => Config.desktopClock = on }
        }
    }
    Section {
        title: "Dok"
        footer: "Programy przypinasz do doku prawym przyciskiem na ich ikonie."
        SettingRow {
            title: "Procent baterii"
            subtitle: "Pokazuj poziom baterii obok ikony w prawej wyspie"
            icon: "battery"; colors: ["#86EFAC", "#16A34A"]
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: Config.batteryPercent; onToggled: on => Config.batteryPercent = on }
        }
    }
    Section {
        title: "Okna"
        SettingRow { title: "Narożniki i krawędzie ekranu"; subtitle: "Co się dzieje, gdy kursor dotknie rogu ekranu"; chevron: true; onClicked: System.openKcm("kcm_kwinscreenedges") }
        SettingRow { title: "Zachowanie okien"; subtitle: "Przyciąganie, przełączanie, podwójne kliknięcie paska"; chevron: true; onClicked: System.openKcm("kcm_kwinoptions") }
    }
}
