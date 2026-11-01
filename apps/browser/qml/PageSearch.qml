import QtQuick
import Aster.Ui

// Pole szukania w nagłówku strony wewnętrznej
Rectangle {
    id: ps
    property alias text: input.text
    property string placeholder
    width: 240; height: 38; radius: 19
    color: Theme.fill
    border.width: input.activeFocus ? 1.5 : 0
    border.color: Theme.accent
    Icon { x: 13; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 15; color: Theme.text2 }
    TextInput {
        id: input
        x: 36; width: parent.width - 48
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.text; selectionColor: Theme.accentSoft
        font.family: Theme.font; font.pixelSize: 13
        clip: true
        Keys.onEscapePressed: text = ""
        Text { anchors.verticalCenter: parent.verticalCenter; visible: !input.text; text: ps.placeholder; color: Theme.text2; font: input.font }
    }
}
