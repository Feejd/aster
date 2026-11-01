import QtQuick
import Aster.Ui

// Pole tekstowe w okienkach (imię, hasło, nazwa sieci…)
Rectangle {
    id: f
    property alias text: input.text
    property string placeholder
    property bool password: false
    property alias input: input
    signal submitted()
    width: parent ? parent.width : 0
    height: 40; radius: 11
    color: Theme.fill
    border.width: input.activeFocus ? 1.5 : 0
    border.color: Theme.accent
    TextInput {
        id: input
        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
        verticalAlignment: TextInput.AlignVCenter
        echoMode: f.password ? TextInput.Password : TextInput.Normal
        color: Theme.text; selectionColor: Theme.accentSoft
        font.family: Theme.font; font.pixelSize: 14
        clip: true
        Keys.onReturnPressed: f.submitted()
        Text { anchors.verticalCenter: parent.verticalCenter; visible: !input.text; text: f.placeholder; color: Theme.text2; font: input.font }
    }
}
