import QtQuick
import Aster.Ui

// Pole tekstowe w panelu właściwości: `edited(text, done)` przy pisaniu (done = false) i po zatwierdzeniu (true)
Column {
    id: tb
    property string label
    property string text
    property string placeholder
    property bool numeric: false
    property bool secret: false
    signal edited(string text, bool done)
    width: parent ? parent.width : 200
    spacing: 4
    onTextChanged: if (!input.activeFocus) input.text = text

    Text {
        visible: tb.label !== ""
        text: tb.label
        color: Theme.text; font.family: Theme.font; font.pixelSize: 12
    }
    Rectangle {
        width: parent.width; height: 36; radius: 12
        color: Theme.fill
        border.width: input.activeFocus ? 1.5 : 0
        border.color: Theme.accent
        TextInput {
            id: input
            x: 10; width: parent.width - 20
            anchors.verticalCenter: parent.verticalCenter
            text: tb.text
            color: Theme.text
            clip: true
            selectByMouse: true
            selectionColor: Theme.accent
            echoMode: tb.secret && !activeFocus ? TextInput.Password : TextInput.Normal
            inputMethodHints: tb.numeric ? Qt.ImhFormattedNumbersOnly : Qt.ImhNone
            font.family: Theme.font; font.pixelSize: 13
            onTextEdited: tb.edited(text, false)
            onEditingFinished: tb.edited(text, true)
            Keys.onEscapePressed: focus = false
            Text { visible: !input.text; text: tb.placeholder; color: Theme.text2; font: input.font }
        }
    }
}
