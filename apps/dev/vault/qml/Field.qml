import QtQuick
import Aster.Ui

// Pole tekstowe z podpisem nad nim (formularz połączenia, hasło)
Column {
    id: field
    property string label
    property alias text: input.text
    property string placeholder
    property bool password: false
    property bool mono: false
    property alias input: input
    signal accepted()
    spacing: 6
    Text { visible: field.label !== ""; text: field.label; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
    Rectangle {
        width: parent.width; height: 36; radius: 10
        color: Theme.fill
        border.width: input.activeFocus ? 1.5 : 0
        border.color: Theme.accent
        TextInput {
            id: input
            x: 12; width: parent.width - 24
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
            font.family: field.mono ? "JetBrains Mono" : Theme.font; font.pixelSize: 13
            echoMode: field.password ? TextInput.Password : TextInput.Normal
            clip: true
            selectByMouse: true
            onAccepted: field.accepted()
            Text { visible: !input.text && !input.activeFocus; text: field.placeholder; color: Theme.text2; opacity: 0.7; font: input.font }
        }
    }
}
