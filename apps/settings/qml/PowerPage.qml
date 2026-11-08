pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Settings

// Zasilanie i bateria: stan i kondycja baterii, tryb zasilania, kiedy wygaszać ekran i usypiać komputer
// (osobno na baterii i przy zasilaczu), co robi zamknięcie pokrywy i przycisk zasilania.
Page {
    id: pp
    property string profile: Power.hasBattery && !Power.pluggedIn ? "Battery" : "AC"
    function rd(groups, key, def) { Conf.revision; return Conf.read("powerdevilrc", groups, key, def); }
    function wr(groups, key, value) { Conf.write("powerdevilrc", groups, key, value); Conf.reloadPower(); }
    function minutes(m) { return m < 0 ? "" : m < 60 ? m + " min" : Math.floor(m / 60) + " godz. " + (m % 60) + " min"; }
    readonly property var lidActions: [
        { label: "Nic nie rób", value: 0 }, { label: "Uśpij", value: 1 }, { label: "Hibernuj", value: 2 },
        { label: "Wyłącz komputer", value: 8 }, { label: "Zablokuj ekran", value: 32 }, { label: "Wyłącz ekran", value: 64 }
    ]
    readonly property var timeouts: [
        { label: "1 minuta", value: 60 }, { label: "2 minuty", value: 120 }, { label: "5 minut", value: 300 },
        { label: "10 minut", value: 600 }, { label: "15 minut", value: 900 }, { label: "30 minut", value: 1800 },
        { label: "1 godzina", value: 3600 }, { label: "Nigdy", value: -1 }
    ]

    // ——— Bateria ———
    Rectangle {
        visible: Power.hasBattery
        width: parent.width; height: 132
        radius: 18
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(1, 1, 1, 0.78)
        border.width: 1; border.color: Theme.line
        Row {
            x: 24; anchors.verticalCenter: parent.verticalCenter
            spacing: 22
            // Duża bateria z wypełnieniem
            Item {
                width: 92; height: 46
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    width: 86; height: 46; radius: 12
                    color: "transparent"; border.width: 3; border.color: Theme.text2
                    Rectangle {
                        x: 6; y: 6; height: parent.height - 12; radius: 6
                        width: (parent.width - 12) * Power.level / 100
                        color: Power.level <= 20 && !Power.charging ? "#FF453A" : Power.charging || Power.pluggedIn ? "#30D158" : Theme.accent
                    }
                    Icon { anchors.centerIn: parent; visible: Power.charging; d: Icons.bolt; size: 22; stroke: 2; color: "white"; fill: "white" }
                }
                Rectangle { x: 88; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 16; radius: 2; color: Theme.text2 }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text { text: Power.level + "%"; color: Theme.text; font.family: Theme.font; font.pixelSize: 34; font.weight: Font.DemiBold; font.letterSpacing: -1 }
                Text {
                    text: Power.charging ? "Ładowanie" + (Power.minutesLeft > 0 ? " · do pełna " + pp.minutes(Power.minutesLeft) : "")
                          : Power.pluggedIn ? "Podłączono do zasilania"
                          : "Na baterii" + (Power.minutesLeft > 0 ? " · zostało " + pp.minutes(Power.minutesLeft) : "")
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                }
            }
        }
        Column {
            anchors.right: parent.right; anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            visible: Power.health >= 0
            Text { anchors.right: parent.right; text: "Kondycja " + Power.health + "%"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
            Text { anchors.right: parent.right; visible: Power.cycles >= 0; text: Power.cycles + " cykli ładowania"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
            Text { anchors.right: parent.right; text: Power.health >= 80 ? "Bateria jest w dobrym stanie" : "Bateria trzyma krócej niż nowa"; color: Power.health >= 80 ? "#30A14E" : Theme.danger; font.family: Theme.font; font.pixelSize: 12 }
        }
    }

    // ——— Tryb zasilania ———
    Section {
        visible: Power.profiles.length > 0
        title: "Tryb zasilania"
        footer: "Oszczędzanie wydłuża pracę na baterii, wydajność przyspiesza gry i ciężkie programy."
        Item {
            width: parent.width; height: 64
            Segmented {
                anchors.centerIn: parent
                model: Power.profiles.map(p => ({ label: p === "power-saver" ? "Oszczędzanie" : p === "balanced" ? "Zrównoważony" : "Wydajność", value: p }))
                value: Power.profile
                onPicked: v => Power.setProfile(v)
            }
        }
    }

    // ——— Ekran i usypianie ———
    Section {
        title: "Ekran i usypianie"
        header: [
            Segmented {
                visible: Power.hasBattery
                model: [{ label: "Na baterii", value: "Battery" }, { label: "Z zasilacza", value: "AC" }]
                value: pp.profile
                onPicked: v => pp.profile = v
            }
        ]
        SettingRow {
            title: "Przyciemnij ekran po"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: pp.timeouts
                value: pp.rd([pp.profile, "Display"], "DimDisplayWhenIdle", true) === false ? -1 : Number(pp.rd([pp.profile, "Display"], "DimDisplayIdleTimeoutSec", pp.profile === "AC" ? 300 : 120))
                onPicked: v => {
                    pp.wr([pp.profile, "Display"], "DimDisplayWhenIdle", v > 0);
                    if (v > 0) pp.wr([pp.profile, "Display"], "DimDisplayIdleTimeoutSec", v);
                }
            }
        }
        SettingRow {
            title: "Wyłącz ekran po"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: pp.timeouts
                value: pp.rd([pp.profile, "Display"], "TurnOffDisplayWhenIdle", true) === false ? -1 : Number(pp.rd([pp.profile, "Display"], "TurnOffDisplayIdleTimeoutSec", pp.profile === "AC" ? 600 : 300))
                onPicked: v => {
                    pp.wr([pp.profile, "Display"], "TurnOffDisplayWhenIdle", v > 0);
                    if (v > 0) pp.wr([pp.profile, "Display"], "TurnOffDisplayIdleTimeoutSec", v);
                }
            }
        }
        SettingRow {
            title: "Uśpij komputer po"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: pp.timeouts.filter(t => t.value >= 300 || t.value < 0)
                value: Number(pp.rd([pp.profile, "SuspendAndShutdown"], "AutoSuspendAction", pp.profile === "AC" ? 0 : 1)) === 0 ? -1
                       : Number(pp.rd([pp.profile, "SuspendAndShutdown"], "AutoSuspendIdleTimeoutSec", pp.profile === "AC" ? 3600 : 900))
                onPicked: v => {
                    pp.wr([pp.profile, "SuspendAndShutdown"], "AutoSuspendAction", v > 0 ? 1 : 0);
                    if (v > 0) pp.wr([pp.profile, "SuspendAndShutdown"], "AutoSuspendIdleTimeoutSec", v);
                }
            }
        }
    }

    // ——— Przyciski ———
    Section {
        title: "Przycisk zasilania i pokrywa"
        SettingRow {
            visible: Power.hasBattery
            title: "Po zamknięciu pokrywy"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: pp.lidActions
                value: Number(pp.rd([pp.profile, "SuspendAndShutdown"], "LidAction", 1))
                onPicked: v => { pp.wr(["AC", "SuspendAndShutdown"], "LidAction", v); pp.wr(["Battery", "SuspendAndShutdown"], "LidAction", v); }
            }
        }
        SettingRow {
            title: "Po naciśnięciu przycisku zasilania"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: [{ label: "Zapytaj, co zrobić", value: 16 }, { label: "Uśpij", value: 1 }, { label: "Hibernuj", value: 2 },
                        { label: "Wyłącz komputer", value: 8 }, { label: "Zablokuj ekran", value: 32 }, { label: "Nic nie rób", value: 0 }]
                value: Number(pp.rd(["AC", "SuspendAndShutdown"], "PowerButtonAction", 16))
                onPicked: v => { pp.wr(["AC", "SuspendAndShutdown"], "PowerButtonAction", v); pp.wr(["Battery", "SuspendAndShutdown"], "PowerButtonAction", v); }
            }
        }
    }

    Section {
        visible: Power.hasBattery
        SettingRow {
            title: "Procent baterii na górnym pasku"
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: Config.batteryPercent; onToggled: on => Config.batteryPercent = on }
        }
        SettingRow {
            title: "Oszczędzaj baterię, gdy jest jej mało"
            subtitle: "Poniżej 20% włącza się tryb oszczędzania"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: String(pp.rd(["Battery", "Performance"], "PowerProfile", "")) === "power-saver" || pp.rd(["LowBattery", "Performance"], "PowerProfile", "") === "power-saver"
                onToggled: on => pp.wr(["LowBattery", "Performance"], "PowerProfile", on ? "power-saver" : "")
            }
        }
    }
}
