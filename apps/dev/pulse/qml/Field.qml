import QtQuick
import Aster.Ui
import Aster.Pulse

// Pole jednowierszowe: przewija się w poziomie za kursorem, ma podpowiedź i koloruje {{zmienne}}
// (nieznane w wybranym środowisku — na czerwono). edited — tylko zmiany wpisane przez użytkownika.
Rectangle {
    id: f
    property alias text: edit.text
    property alias input: edit
    property string placeholder
    property bool vars: true
    property bool mono: false
    property bool frame: true
    property bool password: false        // kropki zamiast znaków (poza edycją)
    property int fontSize: 13
    property real leftPad: 10
    signal edited()
    signal accepted()

    function setText(t) {
        if (edit.text === t) return;
        edit.internal = true;
        edit.text = t;
        edit.internal = false;
    }
    function focusEnd() { edit.forceActiveFocus(); edit.cursorPosition = edit.length; }

    implicitHeight: 34
    radius: 9
    color: frame ? Theme.fill : "transparent"
    border.width: frame && edit.activeFocus ? 1.5 : 0
    border.color: Theme.accent

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.leftMargin: f.leftPad; anchors.rightMargin: 8
        contentWidth: edit.width
        contentHeight: height
        clip: true
        interactive: false
        function ensureVisible(r) {
            if (contentX >= r.x) contentX = Math.max(0, r.x - 4);
            else if (contentX + width <= r.x + r.width) contentX = r.x + r.width - width + 4;
        }
        TextEdit {
            id: edit
            property bool internal: false
            width: Math.max(flick.width, contentWidth + 4)
            height: flick.height
            verticalAlignment: TextEdit.AlignVCenter
            wrapMode: TextEdit.NoWrap
            visible: !(f.password && !activeFocus && text !== "")
            color: Theme.text
            selectionColor: Theme.accentSoft
            selectedTextColor: Theme.text
            font.family: f.mono ? "JetBrains Mono" : Theme.font
            font.pixelSize: f.fontSize
            selectByMouse: true
            persistentSelection: false
            onCursorRectangleChanged: flick.ensureVisible(cursorRectangle)
            onTextChanged: {
                // Wklejony tekst z nowymi wierszami — w jednym wierszu
                if (text.indexOf("\n") >= 0) {
                    const p = cursorPosition;
                    text = text.replace(/\r?\n\s*/g, " ");
                    cursorPosition = Math.min(p, length);
                    return;
                }
                if (!internal && activeFocus) f.edited();
            }
            Keys.onReturnPressed: (e) => { f.accepted(); e.accepted = true; }
            Keys.onEnterPressed: (e) => { f.accepted(); e.accepted = true; }
            onActiveFocusChanged: if (!activeFocus) flick.contentX = 0
        }
        Text {
            visible: f.password && !edit.activeFocus && edit.text !== ""
            height: flick.height
            verticalAlignment: Text.AlignVCenter
            text: "•".repeat(Math.min(24, edit.text.length))
            color: Theme.text
            font.pixelSize: f.fontSize
        }
    }
    MouseArea {
        anchors.fill: parent
        visible: f.password && !edit.activeFocus && edit.text !== ""
        cursorShape: Qt.IBeamCursor
        onClicked: edit.forceActiveFocus()
    }
    Text {
        x: f.leftPad
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - f.leftPad - 8
        visible: edit.text === "" && edit.preeditText === ""
        text: f.placeholder
        elide: Text.ElideRight
        color: Theme.text2
        opacity: 0.8
        font.family: edit.font.family
        font.pixelSize: f.fontSize
    }
    SyntaxColors {
        document: f.vars ? edit.textDocument : null
        json: false
        dark: Theme.dark
        accent: Theme.accent
        known: f.vars ? Pulse.variableNames : []
    }
}
