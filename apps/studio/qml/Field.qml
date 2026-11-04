import QtQuick
import Aster.Ui

// Pole tekstowe w stylu Aster
Rectangle {
    id: field
    property alias text: input.text
    property alias input: input
    property string placeholder
    signal accepted()
    height: 38; radius: 10
    color: Theme.fill
    border.width: input.activeFocus ? 2 : 0
    border.color: Theme.accent
    TextInput {
        id: input
        x: 12; width: parent.width - 24
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.text
        selectionColor: Theme.accentSoft
        selectedTextColor: Theme.text
        selectByMouse: true
        font.family: Theme.font; font.pixelSize: 14
        clip: true
        onAccepted: field.accepted()
        Text {
            visible: !parent.text
            text: field.placeholder
            color: Theme.text2
            font: parent.font
        }
    }
}
