pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Jedna karta edytora kodu: margines (numery wierszy i zmiany z gita), bieżący wiersz, dopasowane
// nawiasy, trafienia szukania i tekst z kolorowaniem składni (KSyntaxHighlighting — jak w Edytorze tekstu).
// Klawisze jak w VS Code: Tab/Shift+Tab, Alt+↑/↓, Shift+Alt+↑/↓, Ctrl+Shift+K, Ctrl+Enter, Home.
Item {
    id: page
    property string path
    property bool wrap: false
    property string fontFamily: "JetBrains Mono"
    property real fontSize: 13.5
    property bool indentTabs: false
    property int indentSize: 4
    property var matches: []                 // pozycje trafień szukania w pliku
    property int matchLength: 0
    property int currentMatch: -1
    readonly property alias edit: te
    readonly property alias gutter: gutter
    readonly property bool modified: te.textDocument.modified
    readonly property point lineCol: { te.cursorPosition; te.length; return TextOps.lineColumn(te.textDocument, te.cursorPosition); }
    readonly property alias language: hl.language
    readonly property string indentUnit: indentTabs ? "\t" : " ".repeat(indentSize)
    property var commentMarkers: ({ line: "//" })
    property var bracket: []
    signal zoomRequested(int d)
    signal edited()

    function load(text, cursor) {
        te.text = text;
        te.textDocument.modified = false;
        const ind = TextOps.detectIndent(text);
        indentTabs = ind.tabs;
        indentSize = ind.size;
        te.cursorPosition = Math.max(0, Math.min(cursor || 0, te.length));
        Qt.callLater(ensureVisible);
        requestBase();
    }
    function requestBase() { if (path) Project.requestBase(path); }
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
    // Zaznacza fragment i pokazuje go w jednej trzeciej wysokości (wyniki szukania, przejście do wiersza)
    function reveal(start, end) {
        te.select(start, end);
        const r = te.positionToRectangle(start);
        if (r.y < flick.contentY + 20 || r.y > flick.contentY + flick.height - 40)
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, r.y - flick.height / 3));
        const left = r.x + te.x;
        if (left > flick.contentX + flick.width - 40 || left < flick.contentX) flick.contentX = Math.max(0, left - flick.width / 2);
    }
    function goToLine(n, col) {
        const p = TextOps.positionOfLine(te.textDocument, n - 1) + (col || 0);
        te.forceActiveFocus();
        reveal(p, p);
    }
    function lines(op) {
        const s = TextOps.editLines(te.textDocument, te.selectionStart, te.selectionEnd, op, indentUnit, commentMarkers);
        te.select(s.start, s.end);
        ensureVisible();
    }
    function toggleComment() { lines("comment"); }
    function nextChange(back) {
        const l = gutter.nextChange(lineCol.y, back);
        if (l >= 0) goToLine(l + 1, 0);
    }

    Connections {
        target: Project
        function onBaseReady(p, text, ok) {
            if (p !== page.path) return;
            gutter.baseText = text;
            gutter.hasBase = ok;
        }
    }

    // ——— Margines ———
    Gutter {
        id: gutter
        width: Math.max(3, String(lineCount).length) * fm.averageCharacterWidth + 34
        height: parent.height
        document: te.textDocument
        offset: flick.contentY - te.topPadding
        firstPosition: { flick.contentY; flick.height; return te.positionAt(0, flick.contentY); }
        currentLine: page.lineCol.y
        font: te.font
        color: Qt.rgba(Theme.text2.r, Theme.text2.g, Theme.text2.b, 0.55)
        currentColor: Theme.text
        addedColor: Theme.dark ? "#3FB950" : "#2DA44E"
        modifiedColor: Theme.dark ? "#58A6FF" : "#3B7DDD"
        deletedColor: Theme.dark ? "#F85149" : "#CF222E"
        FontMetrics { id: fm; font: te.font }
        // Klik w numer — zaznacza wiersz
        MouseArea {
            anchors.fill: parent
            onPressed: (e) => {
                const p = te.positionAt(0, e.y + flick.contentY);
                const l = TextOps.lineColumn(te.textDocument, p).y;
                const a = TextOps.positionOfLine(te.textDocument, l);
                const b = l + 1 < TextOps.lineCount(te.textDocument) ? TextOps.positionOfLine(te.textDocument, l + 1) : te.length;
                te.forceActiveFocus();
                te.select(a, b);
            }
        }
    }

    Flickable {
        id: flick
        anchors.left: gutter.right
        width: parent.width - gutter.width
        height: parent.height
        contentWidth: page.wrap ? width : Math.max(width, te.contentWidth + te.leftPadding + te.rightPadding + 40)
        contentHeight: Math.max(height, te.contentHeight + te.topPadding + te.bottomPadding + height * 0.5)
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        interactive: false                         // przewija kółko; przeciąganie zaznacza tekst
        // Mniejszy widok (otwarty terminal) — kursor zostaje widoczny
        onHeightChanged: if (te.activeFocus) Qt.callLater(page.ensureVisible)

        // Bieżący wiersz
        Rectangle {
            visible: te.selectedText === ""
            y: te.cursorRectangle.y + te.y
            width: Math.max(flick.width, flick.contentWidth); height: te.cursorRectangle.height
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.045) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.04)
        }

        // Trafienia szukania w widocznej części
        Repeater {
            model: {
                flick.contentY; flick.height; te.length;
                if (!page.matches.length || page.matchLength <= 0) return [];
                const a = te.positionAt(0, flick.contentY - 40), b = te.positionAt(flick.contentX + flick.width, flick.contentY + flick.height + 40);
                const out = [];
                for (let i = 0; i < page.matches.length && out.length < 400; ++i)
                    if (page.matches[i] >= a && page.matches[i] <= b) out.push({ pos: page.matches[i], cur: i === page.currentMatch });
                return out;
            }
            delegate: Rectangle {
                required property var modelData
                readonly property rect r1: te.positionToRectangle(modelData.pos)
                readonly property rect r2: te.positionToRectangle(modelData.pos + page.matchLength)
                x: r1.x + te.x - 1; y: r1.y + te.y
                width: Math.max(4, (r2.y === r1.y ? r2.x : te.width) - r1.x + 2); height: r1.height
                radius: 3
                color: modelData.cur ? Qt.rgba(1, 0.72, 0.1, Theme.dark ? 0.55 : 0.5) : Qt.rgba(1, 0.75, 0.2, Theme.dark ? 0.22 : 0.28)
                border.width: modelData.cur ? 1 : 0
                border.color: "#F5A623"
            }
        }

        // Dopasowane nawiasy (czerwone obramowanie — nawias bez pary)
        Repeater {
            model: page.bracket
            delegate: Rectangle {
                required property var modelData
                readonly property rect r: te.positionToRectangle(modelData)
                readonly property rect r2: te.positionToRectangle(modelData + 1)
                visible: te.activeFocus
                x: r.x + te.x; y: r.y + te.y
                width: Math.max(2, r2.x - r.x); height: r.height
                radius: 2
                color: page.bracket.length === 2 ? Theme.accentAlpha(Theme.dark ? 0.22 : 0.14) : "transparent"
                border.width: 1
                border.color: page.bracket.length === 2 ? Theme.accentAlpha(0.7) : Theme.danger
            }
        }

        TextEdit {
            id: te
            width: page.wrap ? flick.width : Math.max(flick.width, implicitWidth)
            height: Math.max(flick.height, implicitHeight)
            leftPadding: 12; rightPadding: 24
            topPadding: 10; bottomPadding: 10
            textFormat: TextEdit.PlainText
            wrapMode: page.wrap ? TextEdit.Wrap : TextEdit.NoWrap
            font.family: page.fontFamily
            font.pixelSize: page.fontSize
            font.features: { "liga": 0, "calt": 0 }
            tabStopDistance: fm.averageCharacterWidth * page.indentSize
            color: Theme.text
            selectionColor: Theme.accentSoft
            selectedTextColor: Theme.text
            selectByMouse: true
            persistentSelection: true
            focus: true
            onCursorRectangleChanged: page.ensureVisible()
            onCursorPositionChanged: Qt.callLater(page.updateBracket)
            onLengthChanged: { Qt.callLater(page.updateFirstLine); page.edited(); }

            Keys.onPressed: (e) => page.handleKey(e)
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

    function handleKey(e) {
        const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier, alt = e.modifiers & Qt.AltModifier;
        const multi = te.selectedText.indexOf(" ") >= 0 || te.selectedText.indexOf("\n") >= 0;
        if (alt && !ctrl && (e.key === Qt.Key_Up || e.key === Qt.Key_Down)) {
            lines(shift ? (e.key === Qt.Key_Up ? "duplicateUp" : "duplicateDown") : (e.key === Qt.Key_Up ? "moveUp" : "moveDown"));
            e.accepted = true;
            return;
        }
        if (ctrl && shift && e.key === Qt.Key_K) { lines("deleteLine"); e.accepted = true; return; }
        if (e.key === Qt.Key_Tab && !ctrl) {
            if (multi) lines("indent");
            else if (indentTabs) te.insert(te.cursorPosition, "\t");
            else {
                // Spacje do następnego punktu tabulacji
                if (te.selectedText) te.remove(te.selectionStart, te.selectionEnd);
                const col = lineCol.x;
                te.insert(te.cursorPosition, " ".repeat(indentSize - col % indentSize));
            }
            e.accepted = true;
            return;
        }
        if (e.key === Qt.Key_Backtab) { lines("outdent"); e.accepted = true; return; }
        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !alt) {
            const start = TextOps.positionOfLine(te.textDocument, lineCol.y);
            const lineText = TextOps.lineText(te.textDocument, lineCol.y);
            const indent = lineText.match(/^[ \t]*/)[0];
            if (ctrl) {
                // Ctrl+Enter — nowy wiersz pod spodem, Ctrl+Shift+Enter — nad
                if (shift) { te.insert(start, indent + "\n"); te.cursorPosition = start + indent.length; }
                else { const end = start + lineText.length; te.insert(end, "\n" + indent); te.cursorPosition = end + 1 + indent.length; }
                e.accepted = true;
                return;
            }
            if (te.selectedText !== "") te.remove(te.selectionStart, te.selectionEnd);
            const pos = te.cursorPosition;
            const before = te.getText(start, pos).replace(/\s+$/, "");
            const last = before.slice(-1), next = te.getText(pos, pos + 1);
            const opens = "{[(", closes = "}])";
            if (opens.indexOf(last) >= 0 || last === ":" && /\.py$/.test(path)) {
                // Po otwierającym nawiasie wcięcie głębiej; nawias zamykający ląduje w osobnym wierszu
                const k = opens.indexOf(last);
                if (k >= 0 && next === closes[k]) {
                    te.insert(pos, "\n" + indent + indentUnit + "\n" + indent);
                    te.cursorPosition = pos + 1 + indent.length + indentUnit.length;
                } else {
                    te.insert(pos, "\n" + indent + indentUnit);
                }
            } else {
                te.insert(pos, "\n" + indent);
            }
            e.accepted = true;
            return;
        }
        if (e.key === Qt.Key_Backspace && !ctrl && !alt && te.selectedText === "" && !indentTabs) {
            // W samych spacjach wcięcia Backspace cofa do poprzedniego poziomu
            const start = TextOps.positionOfLine(te.textDocument, lineCol.y);
            const before = te.getText(start, te.cursorPosition);
            if (before.length > 0 && /^ +$/.test(before)) {
                const n = before.length % indentSize || indentSize;
                te.remove(te.cursorPosition - Math.min(n, before.length), te.cursorPosition);
                e.accepted = true;
                return;
            }
        }
        if (e.key === Qt.Key_Home && !ctrl && !alt) {
            // Home — do pierwszego znaku wiersza, drugi raz — na sam początek
            const start = TextOps.positionOfLine(te.textDocument, lineCol.y);
            const lineText = TextOps.lineText(te.textDocument, lineCol.y);
            const first = start + lineText.match(/^[ \t]*/)[0].length;
            const target = te.cursorPosition === first ? start : first;
            if (shift) te.moveCursorSelection(target, TextEdit.SelectCharacters);
            else te.cursorPosition = target;
            e.accepted = true;
        }
    }

    function updateBracket() { bracket = TextOps.matchBracket(te.textDocument, te.cursorPosition); }
    function updateFirstLine() { hl.firstLine = te.getText(0, Math.min(te.length, 120)).split("\n")[0]; }

    Highlighter {
        id: hl
        document: te.textDocument
        fileName: page.path
        dark: Theme.dark
        onLanguageChanged: page.commentMarkers = TextOps.commentMarkers(page.path, language)
    }
    Component.onCompleted: commentMarkers = TextOps.commentMarkers(path, hl.language)

    // Suwaki
    Rectangle {
        visible: flick.contentHeight > flick.height + 1
        anchors.right: parent.right; anchors.rightMargin: 3
        y: flick.visibleArea.yPosition * flick.height
        width: vArea.containsMouse || vArea.pressed ? 8 : 5; radius: width / 2
        height: Math.max(30, flick.visibleArea.heightRatio * flick.height)
        color: Theme.text2
        opacity: vArea.containsMouse || vArea.pressed ? 0.5 : 0.2
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
