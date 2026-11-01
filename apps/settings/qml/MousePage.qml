import QtQuick
import Aster.Ui
import Aster.Settings

// Mysz i touchpad: szybkość wskaźnika, kierunek przewijania, ręka, stukanie, wyłączanie podczas pisania
Page {
    component SpeedRow: Item {
        id: sr
        property string kind
        width: parent ? parent.width : 0
        height: 74
        readonly property real speed: (kind === "touchpad" ? Inputs.touchpad : Inputs.mouse).speed || 0
        Text { x: 16; y: 12; text: "Szybkość wskaźnika"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
        Text { x: 16; y: 46; text: "Wolno"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
        Text { anchors.right: parent.right; anchors.rightMargin: 16; y: 46; text: "Szybko"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
        Rectangle {
            id: track
            x: 64; y: 47; width: parent.width - 144; height: 6; radius: 3
            color: Theme.fill
            Rectangle { width: (sr.speed + 1) / 2 * parent.width; height: parent.height; radius: 3; color: Theme.accent }
            Rectangle {
                x: (sr.speed + 1) / 2 * (parent.width - width)
                anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22; radius: 11
                color: "white"; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.14)
            }
            MouseArea {
                anchors.fill: parent; anchors.margins: -10
                function apply(mx) { Inputs.set(sr.kind, "speed", Math.round((Math.max(0, Math.min(1, mx / track.width)) * 2 - 1) * 20) / 20); }
                onPressed: m => apply(m.x - 10)
                onPositionChanged: m => { if (pressed) apply(m.x - 10); }
            }
        }
    }

    Section {
        visible: Inputs.hasMouse
        title: "Mysz"
        SpeedRow { kind: "mouse" }
        SettingRow {
            title: "Naturalne przewijanie"
            subtitle: "Treść podąża za ruchem kółka — jak na telefonie"
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: !!Inputs.mouse.natural; onToggled: on => Inputs.set("mouse", "natural", on) }
        }
        SettingRow {
            title: "Mysz dla leworęcznych"
            subtitle: "Zamienia lewy i prawy przycisk"
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: !!Inputs.mouse.leftHanded; onToggled: on => Inputs.set("mouse", "leftHanded", on) }
        }
    }

    Section {
        visible: Inputs.hasTouchpad
        title: "Touchpad"
        footer: "Dwoma palcami przewijasz, trzema przełączasz okna, czterema przechodzisz między pulpitami."
        SpeedRow { kind: "touchpad" }
        SettingRow {
            title: "Stuknij, aby kliknąć"
            subtitle: "Lekkie stuknięcie zamiast wciskania touchpada"
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: !!Inputs.touchpad.tapToClick; onToggled: on => Inputs.set("touchpad", "tapToClick", on) }
        }
        SettingRow {
            title: "Naturalne przewijanie"
            subtitle: "Treść podąża za palcami"
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: !!Inputs.touchpad.natural; onToggled: on => Inputs.set("touchpad", "natural", on) }
        }
        SettingRow {
            title: "Wyłączaj podczas pisania"
            subtitle: "Nadgarstek nie przesunie kursora"
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: !!Inputs.touchpad.disableWhileTyping; onToggled: on => Inputs.set("touchpad", "disableWhileTyping", on) }
        }
    }

    Section {
        title: "Kursor"
        SettingRow {
            title: "Rozmiar kursora"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: [{ label: "Zwykły", value: 24 }, { label: "Duży", value: 32 }, { label: "Bardzo duży", value: 48 }, { label: "Ogromny", value: 64 }]
                value: { Conf.revision; return Number(Conf.read("kcminputrc", ["Mouse"], "cursorSize", 24)); }
                onPicked: v => { Conf.write("kcminputrc", ["Mouse"], "cursorSize", v); Conf.reloadKWin(); }
            }
        }
        SettingRow {
            title: "Znajdź kursor potrząsając myszą"
            subtitle: "Kursor na chwilę się powiększa"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: { Conf.revision; return Conf.read("kwinrc", ["Plugins"], "shakecursorEnabled", true); }
                onToggled: on => { Conf.write("kwinrc", ["Plugins"], "shakecursorEnabled", on); Conf.reloadKWin(); }
            }
        }
    }
}
