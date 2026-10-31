pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Settings

// Bluetooth: włącznik, moje (sparowane) urządzenia, urządzenia w pobliżu z wyszukiwaniem
Item {
    id: bt
    readonly property var mine: System.devices.filter(d => d.paired)
    readonly property var nearby: System.devices.filter(d => !d.paired)
    readonly property var kindIcon: ({ headphones: "headphones", mouse: "mouse", keyboard: "keyboard", speaker: "speaker", phone: "phone", bluetooth: "bluetooth" })

    Page {
        anchors.fill: parent

        Section {
            footer: System.bluetoothAvailable ? "Ten komputer jest widoczny dla urządzeń w pobliżu jako „" + System.about.host + "”, gdy otwarte są ustawienia Bluetooth." : ""
            SettingRow {
                title: "Bluetooth"
                subtitle: !System.bluetoothAvailable ? "Ten komputer nie ma Bluetooth" : System.bluetoothOn ? "Włączony" : "Wyłączony"
                icon: "bluetooth"; colors: ["#60A5FA", "#1D4ED8"]
                Toggle {
                    visible: System.bluetoothAvailable
                    anchors.verticalCenter: parent.verticalCenter
                    checked: System.bluetoothOn
                    onToggled: on => System.setBluetooth(on)
                }
            }
        }

        Section {
            visible: System.bluetoothOn && bt.mine.length > 0
            title: "Moje urządzenia"
            Repeater {
                model: bt.mine
                delegate: SettingRow {
                    id: dev
                    required property var modelData
                    title: modelData.name
                    subtitle: modelData.connected ? "Połączono" : "Niepołączone"
                    icon: bt.kindIcon[modelData.kind] || "bluetooth"
                    TextButton {
                        anchors.verticalCenter: parent.verticalCenter
                        text: dev.modelData.connected ? "Rozłącz" : "Połącz"
                        onClicked: dev.modelData.connected ? System.disconnectDevice(dev.modelData.mac) : System.connectDevice(dev.modelData.mac)
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28; height: 28; radius: 14
                        color: forgetArea.containsMouse ? Theme.hover : "transparent"
                        Icon { anchors.centerIn: parent; d: Icons.trash; size: 15; color: Theme.text2 }
                        MouseArea { id: forgetArea; anchors.fill: parent; hoverEnabled: true; onClicked: System.forgetDevice(dev.modelData.mac) }
                    }
                }
            }
        }

        Section {
            visible: System.bluetoothOn
            title: "Urządzenia w pobliżu"
            footer: "Włącz tryb parowania w urządzeniu (zwykle przytrzymaj jego przycisk), a potem kliknij „Połącz”."
            header: [
                TextButton {
                    text: System.discovering ? "Szukam" : "Szukaj"
                    busy: System.discovering
                    enabled: !System.discovering
                    onClicked: System.discover()
                }
            ]
            Repeater {
                model: bt.nearby
                delegate: SettingRow {
                    id: near
                    required property var modelData
                    title: modelData.name
                    icon: bt.kindIcon[modelData.kind] || "bluetooth"
                    TextButton { anchors.verticalCenter: parent.verticalCenter; text: "Połącz"; primary: true; onClicked: System.connectDevice(near.modelData.mac) }
                }
            }
            SettingRow {
                visible: bt.nearby.length === 0
                title: System.discovering ? "Szukam urządzeń…" : "Kliknij „Szukaj”, aby znaleźć urządzenia"
            }
        }
    }
}
