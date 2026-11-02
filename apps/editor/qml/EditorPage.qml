import QtQuick
import Aster.Ui
import Aster.Editor

// Jedna karta: numery wierszy, podświetlony bieżący wiersz, tekst z kolorowaniem składni.
// Enter zachowuje wcięcie poprzedniego wiersza; Tab przy zaznaczeniu wcina wiele wierszy.
Item {
    id: page
    property string path
    property string title
    property bool wrap: true
    property bool lineNumbers: true
    property string fontFamily: "JetBrains Mono"
    property real fontSize: 14
    readonly property alias edit: te
    readonly property alias flick: flick
    readonly property bool modified: te.textDocument.modified
    readonly property point lineCol: { te.cursorPosition; te.length; return Editor.lineColumn(te.textDocument, te.cursorPosition); }
    readonly property alias language: hl.language

    function load(text, cursor) {
        te.text = text;
        te.textDocument.modified = false;
        te.cursorPosition = Math.max(0, Math.min(cursor || 0, te.length));
        Qt.callLater(ensureVisible);
    }
    function markSaved() { te.textDocument.modified = false; }
    function focusEditor() { te.forceActiveFocus(); }
    function ensureVisible() {
        const r = te.cursorRectangle;
        const top = r.y + te.y, bottom = top + r.height;
        if (top < flick.contentY + 8) flick.contentY = Math.max(0, top - 8);
        else if (bottom > flick.contentY + flick.height - 8) flick.contentY = bottom - flick.height + 8;
        const left = r.x + te.x;
        if (left < flick.contentX + 8) flick.contentX = Math.max(0, left - 40);
        else if (left > flick.contentX + flick.width - 20) flick.contentX = left - flick.width + 60;
    }
    function goToLine(n) {
        te.cursorPosition = Editor.positionOfLine(te.textDocument, n - 1);
        te.forceActiveFocus();
        // Wiersz w okolicy jednej trzeciej wysokości, nie na samej krawędzi
        flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, te.cursorRectangle.y - flick.height / 3));
    }

    // Numery wierszy
    LineNumbers {
        id: gutter
        visible: page.lineNumbers
        width: visible ? Math.max(3, String(lineCount).length) * fm.averageCharacterWidth + 26 : 0
        height: parent.height
        document: te.textDocument
        offset: flick.contentY - te.topPadding
        firstPosition: { flick.contentY; flick.height; return te.positionAt(0, flick.contentY); }
        currentLine: page.lineCol.y
        font: te.font
        color: Qt.rgba(Theme.text2.r, Theme.text2.g, Theme.text2.b, 0.6)
        currentColor: Theme.text
        FontMetrics { id: fm; font: te.font }
    }

    Flickable {
        id: flick
        anchors.left: gutter.right
        width: parent.width - gutter.width
        height: parent.height
        contentWidth: page.wrap ? width : Math.max(width, te.contentWidth + te.leftPadding + te.rightPadding + 40)
        contentHeight: Math.max(height, te.contentHeight + te.topPadding + te.bottomPadding + height * 0.4)
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        interactive: false                         // przewija kółko; przeciąganie zaznacza tekst

        // Bieżący wiersz
        Rectangle {
            visible: te.activeFocus && te.selectedText === ""
            y: te.cursorRectangle.y + te.y
            width: Math.max(flick.width, flick.contentWidth); height: te.cursorRectangle.height
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.035)
        }

        TextEdit {
            id: te
            width: page.wrap ? flick.width : Math.max(flick.width, implicitWidth)
            height: Math.max(flick.height, implicitHeight)
            leftPadding: page.lineNumbers ? 10 : 22; rightPadding: 22
            topPadding: 14; bottomPadding: 14
            textFormat: TextEdit.PlainText
            wrapMode: page.wrap ? TextEdit.Wrap : TextEdit.NoWrap
            font.family: page.fontFamily
            font.pixelSize: page.fontSize
            tabStopDistance: fm.averageCharacterWidth * 4
            color: Theme.text
            selectionColor: Theme.accentSoft
            selectedTextColor: Theme.text
            selectByMouse: true
            persistentSelection: true
            focus: true
            onCursorRectangleChanged: page.ensureVisible()
            // Pierwsza linia (#!/bin/bash) wybiera język pliku bez rozszerzenia — po zmianie, nie w wiązaniu (kolorowanie zmienia dokument)
            onLengthChanged: Qt.callLater(page.updateFirstLine)

            Keys.onPressed: (e) => {
                // Enter: nowy wiersz z wcięciem poprzedniego
                if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
                    const pos = te.cursorPosition;
                    const start = Editor.positionOfLine(te.textDocument, page.lineCol.y);
                    const line = te.getText(start, pos);
                    const indent = line.match(/^[ \t]*/)[0];
                    if (te.selectedText !== "") te.remove(te.selectionStart, te.selectionEnd);
                    te.insert(te.cursorPosition, "\n" + indent);
                    e.accepted = true;
                    return;
                }
                // Tab / Shift+Tab przy zaznaczeniu kilku wierszy — wcięcie bloku
                if ((e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) && te.selectedText.indexOf(" ") >= 0) {
                    page.indentSelection(e.key === Qt.Key_Backtab || (e.modifiers & Qt.ShiftModifier));
                    e.accepted = true;
                }
            }
        }

        WheelHandler {
            acceptedModifiers: Qt.ControlModifier
            onWheel: (e) => page.zoomRequested(e.angleDelta.y > 0 ? 1 : -1)
        }
        // Przewijanie kółkiem i touchpadem (Flickable nieinteraktywny — sam by tego nie robił)
        WheelHandler {
            acceptedModifiers: Qt.NoModifier | Qt.ShiftModifier
            onWheel: (e) => {
                const step = te.cursorRectangle.height || 20;
                let dx = e.pixelDelta.x !== 0 ? e.pixelDelta.x : e.angleDelta.x / 120 * step * 3;
                let dy = e.pixelDelta.y !== 0 ? e.pixelDelta.y : e.angleDelta.y / 120 * step * 3;
                if (e.modifiers & Qt.ShiftModifier) { dx = dy; dy = 0; }
                flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY - dy));
                flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - dx));
            }
        }
    }
    signal zoomRequested(int d)

    function updateFirstLine() { hl.firstLine = te.getText(0, Math.min(te.length, 120)).split("\n")[0]; }
    function indentSelection(out) {
        const a = Editor.positionOfLine(te.textDocument, Editor.lineColumn(te.textDocument, te.selectionStart).y);
        const endLine = Editor.lineColumn(te.textDocument, te.selectionEnd - 1).y;
        const b = Editor.positionOfLine(te.textDocument, endLine + 1);
        const last = endLine + 1 >= Editor.lineColumn(te.textDocument, te.length).y + 1;
        const block = te.getText(a, last ? te.length : b - 1);
        const lines = block.split("\n").map(l => out ? l.replace(/^(\t| {1,4})/, "") : "\t" + l);
        const result = lines.join("\n");
        te.remove(a, a + block.length);
        te.insert(a, result);
        te.select(a, a + result.length);
    }

    Highlighter {
        id: hl
        document: te.textDocument
        fileName: page.path || page.title
        dark: Theme.dark
    }

    // Suwaki
    Rectangle {
        visible: flick.contentHeight > flick.height + 1
        anchors.right: parent.right; anchors.rightMargin: 3
        y: flick.visibleArea.yPosition * flick.height
        width: vArea.containsMouse || vArea.pressed ? 8 : 5; radius: width / 2
        height: Math.max(30, flick.visibleArea.heightRatio * flick.height)
        color: Theme.text2
        opacity: flick.moving || vArea.containsMouse || vArea.pressed ? 0.5 : 0.18
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea {
            id: vArea
            anchors.fill: parent; anchors.margins: -4
            hoverEnabled: true
            property real sy: 0
            property real sc: 0
            onPressed: (e) => { sy = mapToItem(page, e.x, e.y).y; sc = flick.contentY; }
            onPositionChanged: (e) => {
                if (!pressed) return;
                const dy = mapToItem(page, e.x, e.y).y - sy;
                flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, sc + dy / flick.height * flick.contentHeight));
            }
        }
    }
    Rectangle {
        visible: flick.contentWidth > flick.width + 1
        anchors.bottom: parent.bottom; anchors.bottomMargin: 3
        x: flick.x + flick.visibleArea.xPosition * flick.width
        height: 5; radius: 2.5
        width: Math.max(30, flick.visibleArea.widthRatio * flick.width)
        color: Theme.text2
        opacity: 0.25
    }
}
