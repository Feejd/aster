pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Montaz

// Pasek nagrywania lektora pod podglądem: mikrofon, poziom głosu, czas, nagrywanie od miejsca głowicy.
// Podczas nagrywania film leci bez dźwięku (żeby głośniki nie wchodziły do mikrofonu).
Rectangle {
    id: vb
    property var editor
    width: Math.min(parent ? parent.width - 24 : 480, 520)
    height: 60
    radius: 10
    color: Theme.surface
    border.width: 1
    border.color: Theme.edge

    Row {
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        // Nagraj / Zatrzymaj
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 42; height: 42; radius: 21
            color: "transparent"
            border.width: 3
            border.color: VoiceRecorder.available ? "#FF3B30" : Theme.line
            opacity: VoiceRecorder.available ? 1 : 0.5
            Rectangle {
                anchors.centerIn: parent
                width: VoiceRecorder.recording ? 16 : 30; height: width
                radius: VoiceRecorder.recording ? 4 : width / 2
                color: "#FF3B30"
                Behavior on width { NumberAnimation { duration: 140 } }
            }
            MouseArea {
                anchors.fill: parent
                enabled: VoiceRecorder.available
                cursorShape: Qt.PointingHandCursor
                onClicked: VoiceRecorder.recording || vb.editor.countdown > 0 ? vb.editor.stopVoice() : vb.editor.startVoice()
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            width: vb.width - 12 - 42 - 12 - 36 - 24 - 150
            Text {
                width: parent.width
                text: !VoiceRecorder.available ? "Brak mikrofonu"
                      : VoiceRecorder.recording ? "Nagrywam lektora…  " + Project.time(Math.round(VoiceRecorder.seconds * Project.fps), false)
                      : vb.editor.countdown > 0 ? "Za chwilę nagrywanie…"
                      : "Lektor — nagranie od miejsca głowicy"
                elide: Text.ElideRight
                color: VoiceRecorder.recording ? "#FF3B30" : Theme.text
                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
            }
            // Poziom głosu
            Item {
                width: parent.width; height: 6
                visible: VoiceRecorder.available
                Rectangle { anchors.fill: parent; radius: 3; color: Theme.fill }
                Rectangle {
                    width: parent.width * Math.min(1, VoiceRecorder.level * 1.4); height: parent.height; radius: 3
                    color: VoiceRecorder.level > 0.9 ? "#FF3B30" : VoiceRecorder.level > 0.6 ? "#FFB020" : "#24A57E"
                }
            }
            Text {
                visible: !VoiceRecorder.available || VoiceRecorder.error !== ""
                width: parent.width
                text: !VoiceRecorder.available ? "Podłącz mikrofon albo słuchawki z mikrofonem." : VoiceRecorder.error
                elide: Text.ElideRight
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
            }
        }

        // Przyciszanie muzyki i filmu pod lektorem
        HoverButton {
            anchors.verticalCenter: parent.verticalCenter
            width: 150; height: 30; radius: 10
            baseColor: Project.duck ? Theme.accentSoft : Theme.fill
            onClicked: Project.setOption("duck", !Project.duck)
            Row {
                anchors.centerIn: parent
                spacing: 5
                Icon { anchors.verticalCenter: parent.verticalCenter; d: Project.duck ? Icons.check : Icons.volume; size: 12; stroke: 2.2; color: Theme.text }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Przycisz muzykę"; color: Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
            }
        }
        ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "close"; onClicked: vb.editor.closeVoice() }
    }
}
