pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Settings

// Dźwięk: głośność, wyjście (głośniki, słuchawki, HDMI) i wejście (mikrofony)
Page {
    Section {
        title: "Głośność"
        Item {
            width: parent.width; height: 58
            LevelSlider {
                x: 16; width: parent.width - 32
                anchors.verticalCenter: parent.verticalCenter
                icon: System.muted || System.volume === 0 ? "volumeOff" : System.volume < 0.5 ? "volumeLow" : "volume"
                value: System.muted ? 0 : System.volume
                onMoved: v => System.setVolume(v)
                onIconClicked: System.toggleMute()
            }
        }
        SettingRow {
            title: "Wycisz"
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: System.muted; onToggled: System.toggleMute() }
        }
    }

    Section {
        title: "Wyjście"
        footer: "Dźwięk zawsze gra z zaznaczonego urządzenia. Podłączone słuchawki pojawią się tutaj same."
        Repeater {
            model: System.outputs
            delegate: DeviceRow {}
        }
        SettingRow { visible: System.outputs.length === 0; title: "Brak urządzeń wyjściowych" }
    }

    Section {
        visible: System.streams.length > 0
        title: "Programy"
        footer: "Głośność każdego programu osobno — np. cichsza muzyka podczas rozmowy."
        Repeater {
            model: System.streams
            delegate: Item {
                id: st
                required property var modelData
                width: parent.width; height: 64
                Text { x: 16; y: 8; text: st.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                LevelSlider {
                    x: 16; y: 30; width: parent.width - 32
                    icon: st.modelData.volume === 0 ? "volumeOff" : st.modelData.volume < 0.5 ? "volumeLow" : "volume"
                    value: st.modelData.volume
                    onMoved: v => System.setStreamVolume(st.modelData.id, v)
                }
            }
        }
    }

    Section {
        title: "Wejście"
        Item {
            visible: System.inputs.length > 0
            width: parent.width; height: 58
            LevelSlider {
                x: 16; width: parent.width - 32
                anchors.verticalCenter: parent.verticalCenter
                icon: "mic"
                value: System.inputVolume
                onMoved: v => System.setInputVolume(v)
            }
        }
        Repeater {
            model: System.inputs
            delegate: DeviceRow { icon: "mic" }
        }
        SettingRow { visible: System.inputs.length === 0; title: "Brak mikrofonu" }
    }

    Section {
        title: "Dźwięki systemu"
        SettingRow {
            title: "Dźwięki powiadomień i systemu"
            subtitle: "Sygnał przy powiadomieniu, podłączeniu urządzenia, błędzie"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: { Conf.revision; return Conf.read("kdeglobals", ["Sounds"], "Enable", true); }
                onToggled: on => Conf.write("kdeglobals", ["Sounds"], "Enable", on)
            }
        }
        SettingRow {
            title: "Dźwięk przy zmianie głośności"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: { Conf.revision; return Conf.read("plasmaparc", ["General"], "AudioFeedback", true); }
                onToggled: on => Conf.write("plasmaparc", ["General"], "AudioFeedback", on)
            }
        }
    }

    component DeviceRow: SettingRow {
        id: dr
        required property var modelData
        title: modelData.name
        icon: /słuch|head/i.test(modelData.name) ? "headphones" : "speaker"
        clickable: true
        onClicked: System.setDefaultDevice(modelData.id)
        Icon {
            visible: dr.modelData.default
            anchors.verticalCenter: parent.verticalCenter
            d: Icons.check; size: 17; stroke: 2.2
            color: Theme.accentText
        }
    }
}
