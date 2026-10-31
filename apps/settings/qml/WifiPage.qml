pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Aster.Ui
import Aster.Settings

// Wi‑Fi i sieć: włącznik, połączona sieć, sieci w pobliżu (z hasłem w okienku), sieć przewodowa
Item {
    id: wifi
    readonly property var active: System.networks.find(n => n.active) || null
    readonly property var others: System.networks.filter(n => !n.active)
    property var asking: null            // sieć, do której pytamy o hasło

    function pick(n) {
        if (n.secure && !n.known) { asking = n; pw.text = ""; pw.forceActiveFocus(); }
        else System.connectWifi(n.ssid, "");
    }

    Component.onCompleted: System.scanWifi()

    Page {
        anchors.fill: parent

        Section {
            SettingRow {
                title: "Wi‑Fi"
                subtitle: !System.wifiAvailable ? "Ten komputer nie ma karty Wi‑Fi"
                        : System.wifiOn ? (wifi.active ? "Połączono z „" + wifi.active.ssid + "”" : "Nie połączono") : "Wyłączone"
                icon: "wifi"; colors: ["#5AB4FF", "#2563EB"]
                Toggle {
                    visible: System.wifiAvailable
                    anchors.verticalCenter: parent.verticalCenter
                    checked: System.wifiOn
                    onToggled: on => System.setWifi(on)
                }
            }
            SettingRow {
                visible: wifi.active !== null
                title: wifi.active ? wifi.active.ssid : ""
                subtitle: "Połączono" + (wifi.active && wifi.active.secure ? " · zabezpieczona" : "")
                icon: "check"
                TextButton { anchors.verticalCenter: parent.verticalCenter; text: "Rozłącz"; onClicked: System.disconnectWifi() }
                SignalBars { anchors.verticalCenter: parent.verticalCenter; signal: wifi.active ? wifi.active.signal : 0 }
            }
        }

        Section {
            visible: System.wifiAvailable && System.wifiOn
            title: "Sieci w pobliżu"
            header: [
                TextButton {
                    text: System.scanning ? "Szukam" : "Odśwież"
                    busy: System.scanning
                    enabled: !System.scanning
                    onClicked: System.scanWifi()
                }
            ]
            Repeater {
                model: wifi.others
                delegate: SettingRow {
                    id: net
                    required property var modelData
                    title: modelData.ssid
                    subtitle: System.connecting === modelData.ssid ? "Łączenie…" : (modelData.known ? "Znana sieć" : "")
                    clickable: true
                    onClicked: wifi.pick(modelData)
                    Icon { visible: net.modelData.secure; anchors.verticalCenter: parent.verticalCenter; d: Icons.lock; size: 14; color: Theme.text2 }
                    SignalBars { anchors.verticalCenter: parent.verticalCenter; signal: net.modelData.signal }
                }
            }
            SettingRow {
                visible: wifi.others.length === 0
                title: System.scanning ? "Szukam sieci…" : "Nie widać innych sieci"
            }
        }

        Section {
            title: "Sieć przewodowa"
            SettingRow {
                title: "Ethernet"
                subtitle: System.wiredName ? "Połączono · " + System.wiredName : "Kabel nie jest podłączony"
                icon: "ethernet"; colors: ["#86EFAC", "#16A34A"]
            }
            SettingRow {
                title: "Zaawansowane ustawienia sieci"
                subtitle: "VPN, adresy IP, DNS, serwer proxy"
                chevron: true
                onClicked: System.openKcm("kcm_networkmanagement")
            }
        }
    }

    // ——— Okienko z hasłem ———
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.25)
        opacity: wifi.asking ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        MouseArea { anchors.fill: parent; onClicked: wifi.asking = null }

        Rectangle {
            id: sheet
            anchors.centerIn: parent
            width: 380; height: sheetCol.height + 44
            radius: 18
            color: Theme.surface
            scale: wifi.asking ? 1 : 0.94
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
            MouseArea { anchors.fill: parent }
            layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 1; shadowVerticalOffset: 10; shadowColor: Qt.rgba(0, 0, 0, 0.3) }

            Column {
                id: sheetCol
                x: 22; y: 22
                width: parent.width - 44
                spacing: 14
                Badge { anchors.horizontalCenter: parent.horizontalCenter; size: 48; icon: "wifi"; colors: ["#5AB4FF", "#2563EB"] }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "Hasło do sieci „" + (wifi.asking ? wifi.asking.ssid : "") + "”"
                    wrapMode: Text.Wrap
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                }
                Rectangle {
                    width: parent.width; height: 38; radius: 10
                    color: Theme.fill
                    border.width: pw.activeFocus ? 1.5 : 0
                    border.color: Theme.accent
                    TextInput {
                        id: pw
                        x: 12; width: parent.width - 54
                        anchors.verticalCenter: parent.verticalCenter
                        echoMode: showPw.on ? TextInput.Normal : TextInput.Password
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 14
                        clip: true
                        Keys.onReturnPressed: connectBtn.clicked()
                        Keys.onEscapePressed: wifi.asking = null
                    }
                    Icon {
                        id: showPw
                        property bool on: false
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        d: Icons.eye; size: 17
                        color: on ? Theme.accentText : Theme.text2
                        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: showPw.on = !showPw.on }
                    }
                }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    TextButton { text: "Anuluj"; onClicked: wifi.asking = null }
                    TextButton {
                        id: connectBtn
                        text: "Połącz"; primary: true
                        enabled: pw.text.length >= 8
                        onClicked: { if (!enabled) return; System.connectWifi(wifi.asking.ssid, pw.text); pw.text = ""; wifi.asking = null; }
                    }
                }
            }
        }
    }
}
