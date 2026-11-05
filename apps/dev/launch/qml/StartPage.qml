import QtQuick
import Aster.Ui
import "LaunchIcons.js" as LI

// Ekran startowy: nic jeszcze nie ma — wybierz albo upuść folder projektu
Item {
    id: sp
    signal addRequested()

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 620)
        spacing: 0

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 72; height: 72; radius: 12
            gradient: Gradient {
                GradientStop { position: 0; color: "#FFB27A" }
                GradientStop { position: 1; color: "#E5366F" }
            }
            Icon { anchors.centerIn: parent; d: LI.rocket; size: 38; stroke: 1.7; color: "white" }
        }
        Item { width: 1; height: 22 }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter
            text: "Wdróż stronę albo aplikację"
            color: Theme.text; font.family: Theme.font; font.pixelSize: 26; font.weight: Font.Bold; font.letterSpacing: -0.5
        }
        Item { width: 1; height: 8 }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: "Wybierz folder z kodem — Aster Launch rozpozna, co to jest, i wyśle to na Twój serwer albo do hostingu. Każdą zmianę zobaczysz, zanim się wydarzy."
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 14; lineHeight: 1.2
        }
        Item { width: 1; height: 24 }
        Pill {
            anchors.horizontalCenter: parent.horizontalCenter
            primary: true
            text: "Wybierz folder projektu"
            iconPath: Icons.folder
            onClicked: sp.addRequested()
        }
        Item { width: 1; height: 8 }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter
            text: "albo przeciągnij go tutaj · Ctrl+O"
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
        }
        Item { width: 1; height: 38 }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12
            Repeater {
                model: [
                    { icon: LI.server, title: "Własny serwer", text: "SSH, usługa systemd albo kontener, Caddy z HTTPS dla Twojej domeny" },
                    { icon: LI.cloud, title: "Hostingi", text: "Netlify, Vercel i Cloudflare Pages przez ich programy" },
                    { icon: LI.history, title: "Bez strachu", text: "Historia wersji i powrót do poprzedniej jednym kliknięciem" }
                ]
                delegate: Rectangle {
                    id: feat
                    required property var modelData
                    width: 196; height: 138; radius: 10
                    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(1, 1, 1, 0.9)
                    border.width: 1; border.color: Theme.line
                    Column {
                        x: 16; y: 16; width: parent.width - 32
                        spacing: 7
                        Rectangle {
                            width: 32; height: 32; radius: 10
                            color: Theme.accentSoft
                            Icon { anchors.centerIn: parent; d: feat.modelData.icon; size: 17; stroke: 1.8; color: Theme.accentText }
                        }
                        Text { text: feat.modelData.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text { width: parent.width; wrapMode: Text.Wrap; text: feat.modelData.text; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                    }
                }
            }
        }
        Item { width: 1; height: 26 }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: "Rozpoznaje: statyczne strony (też z Vite, React, Astro), Node.js, Python, Dockerfile i Docker Compose"
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; opacity: 0.85
        }
    }
}
