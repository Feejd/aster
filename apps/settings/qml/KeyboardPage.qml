pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Settings

// Klawiatura: układy (polski programisty jako pierwszy), przełączanie Super+Spacja,
// powtarzanie klawiszy, Num Lock i skróty klawiszowe
Page {
    id: kp
    function ids() { return Inputs.layouts.map(l => l.id); }

    Section {
        title: "Układy klawiatury"
        footer: Inputs.layouts.length > 1 ? "Przełączasz je skrótem Super + Spacja (klawisz Windows i spacja)." : "Polski (programisty) to układ, w którym polskie litery piszesz z prawym Alt, np. Alt + a = ą."
        Repeater {
            model: Inputs.layouts
            delegate: SettingRow {
                id: lay
                required property var modelData
                required property int index
                title: modelData.name
                subtitle: index === 0 ? "Używany na starcie" : ""
                icon: "keyboard"
                TextButton {
                    visible: lay.index > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Ustaw jako pierwszy"
                    onClicked: { const l = kp.ids(); l.splice(lay.index, 1); l.unshift(lay.modelData.id); Inputs.setLayouts(l); }
                }
                HoverButton {
                    visible: Inputs.layouts.length > 1
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28; radius: 14
                    onClicked: Inputs.setLayouts(kp.ids().filter(i => i !== lay.modelData.id))
                    Icon { anchors.centerIn: parent; d: Icons.trash; size: 15; color: Theme.text2 }
                }
            }
        }
        SettingRow {
            title: "Dodaj układ"
            titleColor: Theme.accentText
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                placeholder: "Wybierz język"
                model: Inputs.allLayouts.filter(l => kp.ids().indexOf(l.id) < 0).map(l => ({ label: l.name, value: l.id }))
                value: ""
                onPicked: v => Inputs.setLayouts(kp.ids().concat([v]))
            }
        }
    }

    Section {
        title: "Pisanie"
        SettingRow {
            title: "Opóźnienie powtarzania"
            subtitle: "Po jakim czasie przytrzymany klawisz zaczyna się powtarzać"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: [{ label: "Krótkie", value: 250 }, { label: "Średnie", value: 400 }, { label: "Długie", value: 600 }, { label: "Bardzo długie", value: 900 }]
                value: { Conf.revision; const v = Number(Conf.read("kcminputrc", ["Keyboard"], "RepeatDelay", 600)); return [250, 400, 600, 900].reduce((a, b) => Math.abs(b - v) < Math.abs(a - v) ? b : a); }
                onPicked: v => { Conf.write("kcminputrc", ["Keyboard"], "RepeatDelay", v); Conf.reloadKWin(); }
            }
        }
        SettingRow {
            title: "Szybkość powtarzania"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: [{ label: "Wolno", value: 15 }, { label: "Średnio", value: 25 }, { label: "Szybko", value: 40 }, { label: "Bardzo szybko", value: 60 }]
                value: { Conf.revision; const v = Number(Conf.read("kcminputrc", ["Keyboard"], "RepeatRate", 25)); return [15, 25, 40, 60].reduce((a, b) => Math.abs(b - v) < Math.abs(a - v) ? b : a); }
                onPicked: v => { Conf.write("kcminputrc", ["Keyboard"], "RepeatRate", v); Conf.reloadKWin(); }
            }
        }
        SettingRow {
            title: "Num Lock włączony po uruchomieniu"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: { Conf.revision; return Number(Conf.read("kcminputrc", ["Keyboard"], "NumLock", 2)) === 0; }
                onToggled: on => Conf.write("kcminputrc", ["Keyboard"], "NumLock", on ? 0 : 2)
            }
        }
    }

    Section {
        SettingRow {
            title: "Skróty klawiszowe"
            subtitle: "Zrzuty ekranu, okna, głośność, blokada…"
            icon: "keyboard"; colors: ["#A3A9B5", "#4B5262"]
            chevron: true
            onClicked: kp.navigate("shortcuts")
        }
    }
}
