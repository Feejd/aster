import QtQuick
import Aster.Ui
import Aster.Pulse

// Edytor kodu (treść JSON, surowa odpowiedź, cURL): czcionka o stałej szerokości, numery wierszy,
// kolory JSON i {{zmiennych}}, Tab = 2 spacje, Enter zachowuje wcięcie (po { i [ — o poziom głębiej).
Rectangle {
    id: ca
    property alias text: edit.text
    property alias edit: edit
    property bool readOnly: false
    property bool json: true
    property bool numbers: true
    property bool vars: !readOnly
    property string placeholder
    property bool wrap: false
    signal edited()

    function setText(t) {
        if (edit.text === t) return;
        edit.internal = true;
        edit.text = t;
        edit.internal = false;
        flick.contentY = 0;
        flick.contentX = 0;
    }

    radius: 10
    color: Theme.fill
    border.width: edit.activeFocus && !readOnly ? 1.5 : 0
    border.color: Theme.accent
    clip: true

    property bool heavy: false                                // duże teksty bez kolorów (szybkość)

    Text {
        id: gutter
        visible: ca.numbers
        x: 0; y: 10 - flick.contentY
        width: visible ? Math.max(30, String(edit.lineCount).length * 7.5 + 16) : 0
        horizontalAlignment: Text.AlignRight
        rightPadding: 8
        text: {
            const n = Math.min(edit.lineCount, 100000);
            let s = "";
            for (let i = 1; i <= n; ++i) s += (i > 1 ? "\n" : "") + i;
            return s;
        }
        color: Theme.text2
        opacity: 0.6
        font: edit.font
        lineHeight: 1
    }

    Flickable {
        id: flick
        x: gutter.width + 8; y: 10
        width: parent.width - x - 8; height: parent.height - 20
        contentWidth: edit.width
        contentHeight: edit.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        function ensureVisible(r) {
            if (contentX >= r.x) contentX = Math.max(0, r.x - 8);
            else if (contentX + width <= r.x + r.width) contentX = r.x + r.width - width + 8;
            if (contentY >= r.y) contentY = r.y;
            else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height;
        }
        TextEdit {
            id: edit
            property bool internal: false
            width: ca.wrap ? flick.width : Math.max(flick.width, contentWidth + 8)
            height: Math.max(flick.height, contentHeight)
            wrapMode: ca.wrap ? TextEdit.WrapAnywhere : TextEdit.NoWrap
            readOnly: ca.readOnly
            selectByMouse: true
            color: Theme.text
            selectionColor: Theme.accentSoft
            selectedTextColor: Theme.text
            font.family: "JetBrains Mono"
            font.pixelSize: 12
            tabStopDistance: 24
            onCursorRectangleChanged: if (activeFocus) flick.ensureVisible(cursorRectangle)
            onTextChanged: {
                const h = length > 300000;
                if (h !== ca.heavy) ca.heavy = h;
                if (!internal && activeFocus) ca.edited();
            }
            Keys.onTabPressed: (e) => {
                if (readOnly) { e.accepted = false; return; }
                insert(cursorPosition, "  ");
                e.accepted = true;
            }
            Keys.onReturnPressed: (e) => {
                if (readOnly || (e.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) { e.accepted = false; return; }
                // Wcięcie z bieżącego wiersza (+2 po { albo [)
                const before = getText(0, cursorPosition);
                const line = before.slice(before.lastIndexOf("\n") + 1);
                let indent = line.match(/^\s*/)[0];
                const last = line.trim().slice(-1);
                if (last === "{" || last === "[") indent += "  ";
                const after = getText(cursorPosition, Math.min(length, cursorPosition + 1));
                if ((last === "{" && after === "}") || (last === "[" && after === "]")) {
                    const p = cursorPosition;
                    insert(p, "\n" + indent + "\n" + indent.slice(2));
                    cursorPosition = p + 1 + indent.length;
                } else {
                    insert(cursorPosition, "\n" + indent);
                }
                e.accepted = true;
            }
        }
        MouseArea {
            // Kliknięcie pod tekstem — kursor na koniec
            y: edit.contentHeight; width: flick.width; height: Math.max(0, flick.height - edit.contentHeight)
            visible: !ca.readOnly
            cursorShape: Qt.IBeamCursor
            onClicked: { edit.forceActiveFocus(); edit.cursorPosition = edit.length; }
        }
    }
    Text {
        x: flick.x; y: 10
        visible: edit.text === "" && ca.placeholder !== ""
        width: flick.width
        wrapMode: Text.Wrap
        text: ca.placeholder
        color: Theme.text2
        opacity: 0.8
        font.family: "JetBrains Mono"; font.pixelSize: 12
        lineHeight: 1.2
    }
    SyntaxColors {
        document: ca.heavy ? null : edit.textDocument
        json: ca.json
        dark: Theme.dark
        accent: Theme.accent
        known: ca.vars ? Pulse.variableNames : []
    }
    // Pasek przewijania
    Rectangle {
        visible: flick.contentHeight > flick.height
        x: parent.width - 6; width: 4; radius: 2
        y: flick.y + flick.visibleArea.yPosition * flick.height
        height: Math.max(24, flick.visibleArea.heightRatio * flick.height)
        color: Theme.text2
        opacity: flick.moving ? 0.5 : 0.25
    }
}
