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
        title: "Wejście"
        Repeater {
            model: System.inputs
            delegate: DeviceRow { icon: "mic" }
        }
        SettingRow { visible: System.inputs.length === 0; title: "Brak mikrofonu" }
        SettingRow {
            title: "Zaawansowane ustawienia dźwięku"
            chevron: true
            onClicked: System.openKcm("kcm_pulseaudio")
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
