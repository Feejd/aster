import QtQuick
import Aster.Ui

// Pole formularza: etykieta po lewej, pole tekstowe po prawej, podpowiedź pod spodem.
// Zapis przy zatwierdzeniu (Enter albo wyjście z pola) — sygnał committed(text).
Item {
    id: f
    property string label
    property string value
    property string placeholder
    property string hint
    property bool mono: false
    property bool numeric: false
    property int labelWidth: 170
    signal committed(string text)
    width: parent ? parent.width : 0
    height: Math.max(36, box.height) + (hint !== "" ? hintText.implicitHeight + 6 : 0)

    Text {
        y: 9; width: f.labelWidth - 12
        text: f.label; elide: Text.ElideRight
        color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
    }
    Rectangle {
        id: box
        x: f.labelWidth
        width: parent.width - f.labelWidth; height: 36; radius: 9
        color: Theme.fill
        border.width: input.activeFocus ? 1.5 : 0; border.color: Theme.accent
        TextInput {
            id: input
            x: 11; width: parent.width - 22
            anchors.verticalCenter: parent.verticalCenter
            text: f.value
            color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
            font.family: f.mono ? "JetBrains Mono" : Theme.font; font.pixelSize: 13
            clip: true
            selectByMouse: true
            inputMethodHints: f.numeric ? Qt.ImhDigitsOnly : Qt.ImhNone
            validator: f.numeric ? intValidator : null
            onEditingFinished: if (text !== f.value) f.committed(text)
            Keys.onEscapePressed: { text = f.value; focus = false; }
            Text { anchors.verticalCenter: parent.verticalCenter; visible: !input.text && !input.activeFocus; text: f.placeholder; color: Theme.text2; font: input.font; opacity: 0.7 }
        }
        IntValidator { id: intValidator; bottom: 1; top: 65535 }
    }
    Text {
        id: hintText
        visible: f.hint !== ""
        x: f.labelWidth; y: box.height + 6
        width: parent.width - f.labelWidth
        wrapMode: Text.Wrap
        text: f.hint
        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
    }
}
