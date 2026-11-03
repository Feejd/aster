pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Jedna karta edytora kodu: margines (numery wierszy i zmiany z gita), bieżący wiersz, dopasowane
// nawiasy, trafienia szukania i tekst z kolorowaniem składni (KSyntaxHighlighting — jak w Edytorze tekstu).
// Klawisze jak w VS Code: Tab/Shift+Tab, Alt+↑/↓, Shift+Alt+↑/↓, Ctrl+Shift+K, Ctrl+Enter, Home.
// Serwer języka (Lsp): podpowiedzi przy pisaniu i Ctrl+Spacja, opis po najechaniu, Ctrl+klik — definicja,
// podkreślone błędy i kropki przy numerach wierszy. Nawiasy i cudzysłowy domykają się same.
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
    property var serverInfo: ({})
    readonly property bool lspOn: !!serverInfo.id && !serverInfo.failed && (serverInfo.running || serverInfo.available)
    readonly property var diagnostics: { Lsp.revision; return path ? Lsp.diagnostics(path) : []; }
    property string lspPath: ""
    property int compSeq: -1
    property int hoverSeq: -1
    property string hoverDiag: ""
    signal zoomRequested(int d)
    signal edited()
    signal definitionRequested(int seq)
    signal contextMenuRequested(Item item, real x, real y)

    function load(text, cursor) {
        te.text = text;
        te.textDocument.modified = false;
        const ind = TextOps.detectIndent(text);
        indentTabs = ind.tabs;
        indentSize = ind.size;
        te.cursorPosition = Math.max(0, Math.min(cursor || 0, te.length));
        Qt.callLater(ensureVisible);
        requestBase();
        lspPath = path;
        Lsp.open(path, text);
        serverInfo = Lsp.serverFor(path);
    }
    onPathChanged: {
        // Zmiana nazwy pliku — serwer języka dostaje „nowy” dokument
        if (!lspPath || lspPath === path) return;
        Lsp.close(lspPath);
        lspPath = path;
        Lsp.open(path, te.text);
        serverInfo = Lsp.serverFor(path);
    }
    Component.onDestruction: if (lspPath) Lsp.close(lspPath)
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

    // ——— Serwer języka ———
    function wordBefore() {
        const start = TextOps.positionOfLine(te.textDocument, lineCol.y);
        const m = te.getText(start, te.cursorPosition).match(/[A-Za-z0-9_$]*$/);
        return m ? m[0] : "";
    }
    function requestCompletion() {
        if (!lspOn) return;
        Lsp.update(path, te.text);
        compSeq = Lsp.complete(path, lineCol.y, lineCol.x);
    }
    function afterTyped(ch) {
        const w = wordBefore();
        const before = te.getText(Math.max(0, te.cursorPosition - 2), te.cursorPosition);
        const trigger = ch === "." || before === "::" || before === "->";
        if (completion.visible) {
            if (trigger) { completion.hide(); completionTimer.restart(); }
            else if (!w) completion.hide();
            else completion.filter(w);
        } else if (lspOn && (trigger || w.length >= 1)) {
            completionTimer.restart();
        }
    }
    function acceptCompletion(item) {
        const pos = te.cursorPosition;
        let start = pos - wordBefore().length;
        if (item.startLine !== undefined && item.startLine === lineCol.y)
            start = Math.min(pos, TextOps.positionOfLine(te.textDocument, item.startLine) + item.startCol);
        te.remove(start, pos);
        te.insert(start, item.insert);
        te.cursorPosition = start + item.insert.length;
    }
    // −1: brak serwera dla tego pliku
    function goToDefinition(position) {
        if (!lspOn) return -1;
        const lc = TextOps.lineColumn(te.textDocument, position === undefined ? te.cursorPosition : position);
        Lsp.update(path, te.text);
        return Lsp.definition(path, lc.y, lc.x);
    }
    function diagnosticsAt(line, col) {
        return diagnostics.filter(d => (line > d.line || line === d.line && col >= d.col)
                                       && (line < d.endLine || line === d.endLine && col <= Math.max(d.endCol, d.col + 1)));
    }
    // Do testów (ASTER_OPEN keys:…) — znak jak z klawiatury: domykanie nawiasów, potem zwykłe wstawienie
    function typeKey(ch) {
        if (!autoPair(ch)) te.insert(te.cursorPosition, ch);
    }
    // Do testów (ASTER_OPEN hover:WIERSZ,KOLUMNA) — opis bez prawdziwej myszy
    property bool testTip: false
    function testHover(line, col) {
        const pos = TextOps.positionOfLine(te.textDocument, line - 1) + col - 1;
        const r = te.positionToRectangle(pos);
        testTip = true;
        hoverDiag = diagnosticsAt(line - 1, col - 1).map(d => d.message).join("\n");
        tip.at = Qt.point(r.x + te.x + flick.x - flick.contentX, r.y + te.y - flick.contentY);
        tip.text = hoverDiag;
        if (lspOn) { Lsp.update(path, te.text); hoverSeq = Lsp.hover(path, line - 1, col - 1); }
    }
    Timer { id: lspTimer; interval: 350; onTriggered: if (page.lspOn) Lsp.update(page.path, te.text) }
    Timer { id: completionTimer; interval: 120; onTriggered: page.requestCompletion() }
    Timer {
        id: hoverTimer
        interval: 650
        onTriggered: {
            if (!hov.hovered) return;
            const pt = hov.point.position;
            const pos = te.positionAt(pt.x, pt.y);
            const r = te.positionToRectangle(pos);
            // Za końcem wiersza — nic do opisania
            if (Math.abs(r.x - pt.x) > fm.averageCharacterWidth * 1.5 || pt.y < r.y || pt.y > r.y + r.height) return;
            const lc = TextOps.lineColumn(te.textDocument, pos);
            const diags = page.diagnosticsAt(lc.y, lc.x);
            page.hoverDiag = diags.map(d => (d.severity === 1 ? "Błąd: " : d.severity === 2 ? "Ostrzeżenie: " : "") + d.message
                                            + (d.source ? "  (" + d.source + ")" : "")).join("\n");
            tip.at = Qt.point(pt.x + te.x + flick.x - flick.contentX, r.y + te.y - flick.contentY);
            tip.text = page.hoverDiag;
            if (page.lspOn) {
                Lsp.update(page.path, te.text);
                page.hoverSeq = Lsp.hover(page.path, lc.y, lc.x);
            }
        }
    }
    Connections {
        target: Lsp
        function onCompletionReady(seq, p, items) {
            if (seq !== page.compSeq || p !== page.path || !te.activeFocus) return;
            if (items.length) completion.show(items, page.wordBefore());
        }
        function onHoverReady(seq, p, text) {
            if (seq !== page.hoverSeq || !(hov.hovered || page.testTip)) return;
            tip.text = [page.hoverDiag, text].filter(t => !!t).join("\n\n");
        }
        function onServersChanged() { page.serverInfo = Lsp.serverFor(page.path); }
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
        diagnostics: page.diagnostics
        errorColor: Theme.danger
        warningColor: Theme.dark ? "#E3B341" : "#BF8700"
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

        // Błędy i ostrzeżenia z serwera języka — podkreślenie fragmentu (w widocznej części)
        Repeater {
            model: {
                flick.contentY; flick.height; te.length;
                const d = page.diagnostics;
                if (!d.length) return [];
                const first = TextOps.lineColumn(te.textDocument, te.positionAt(0, flick.contentY)).y - 1;
                const last = TextOps.lineColumn(te.textDocument, te.positionAt(0, flick.contentY + flick.height)).y + 1;
                const out = [];
                for (let i = 0; i < d.length && out.length < 300; ++i) {
                    if (d[i].line < first || d[i].line > last || d[i].severity > 2) continue;
                    const lineStart = TextOps.positionOfLine(te.textDocument, d[i].line);
                    const lineLen = TextOps.lineText(te.textDocument, d[i].line).length;
                    const a = lineStart + Math.min(d[i].col, lineLen);
                    const b = d[i].endLine === d[i].line ? lineStart + Math.min(d[i].endCol, lineLen) : lineStart + lineLen;
                    out.push({ a: a, b: Math.max(b, a), sev: d[i].severity });
                }
                return out;
            }
            delegate: Rectangle {
                required property var modelData
                readonly property rect r1: te.positionToRectangle(modelData.a)
                readonly property rect r2: te.positionToRectangle(modelData.b)
                x: r1.x + te.x; y: r1.y + te.y + r1.height - 2
                width: Math.max(fm.averageCharacterWidth, r2.y === r1.y ? r2.x - r1.x : fm.averageCharacterWidth); height: 2
                radius: 1
                color: modelData.sev === 1 ? Theme.danger : (Theme.dark ? "#E3B341" : "#BF8700")
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
            onCursorPositionChanged: {
                Qt.callLater(page.updateBracket);
                if (completion.visible && page.lineCol.y !== completion.line) completion.hide();
            }
            onLengthChanged: { Qt.callLater(page.updateFirstLine); page.edited(); }
            onTextChanged: if (page.lspOn) lspTimer.restart()
            onActiveFocusChanged: if (!activeFocus) completion.hide()

            HoverHandler {
                id: hov
                onPointChanged: { tip.text = ""; hoverTimer.restart(); }
                onHoveredChanged: if (!hovered) { tip.text = ""; hoverTimer.stop(); }
            }
            // Prawy przycisk — menu edytora (definicja, schowek, komentarz)
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: (ev) => {
                    const p = te.positionAt(ev.position.x, ev.position.y);
                    if (te.selectedText === "" || p < te.selectionStart || p > te.selectionEnd) te.cursorPosition = p;
                    page.contextMenuRequested(te, ev.position.x, ev.position.y);
                }
            }
            // Ctrl+klik — przejdź do definicji
            TapHandler {
                acceptedModifiers: Qt.ControlModifier
                onTapped: (ev) => page.definitionRequested(page.goToDefinition(te.positionAt(ev.position.x, ev.position.y)))
            }

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
        tip.text = "";
        // Otwarte podpowiedzi przejmują strzałki, Enter, Tab i Esc
        if (completion.visible) {
            if (e.key === Qt.Key_Down || e.key === Qt.Key_Up) { completion.move(e.key === Qt.Key_Down ? 1 : -1); e.accepted = true; return; }
            if (e.key === Qt.Key_PageDown || e.key === Qt.Key_PageUp) { completion.move(e.key === Qt.Key_PageDown ? 8 : -8); e.accepted = true; return; }
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Tab) { completion.accept(); e.accepted = true; return; }
            if (e.key === Qt.Key_Escape) { completion.hide(); e.accepted = true; return; }
        }
        if (ctrl && e.key === Qt.Key_Space) { requestCompletion(); e.accepted = true; return; }
        if (!ctrl && !alt && e.text.length === 1 && autoPair(e.text)) { e.accepted = true; return; }
        if (!ctrl && !alt && e.text.length === 1 && /[A-Za-z0-9_.:>$]/.test(e.text)) {
            const ch = e.text;
            Qt.callLater(() => page.afterTyped(ch));
        }
        if (e.key === Qt.Key_Backspace && !ctrl && !alt && te.selectedText === "" && te.cursorPosition > 0) {
            // Pusta para „()” — Backspace usuwa oba znaki
            const pos = te.cursorPosition, two = te.getText(pos - 1, pos + 1);
            if (["()", "[]", "{}", "\"\"", "''", "``"].indexOf(two) >= 0) { te.remove(pos - 1, pos + 1); e.accepted = true; Qt.callLater(() => page.afterTyped("")); return; }
            Qt.callLater(() => page.afterTyped(""));
        }
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

    // Domykanie: ( [ { " ' ` wstawiają parę, zamykający znak przeskakuje istniejący, zaznaczenie trafia do środka
    function autoPair(ch) {
        const pairs = { "(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`" };
        const pos = te.cursorPosition;
        const next = te.getText(pos, pos + 1), prev = pos > 0 ? te.getText(pos - 1, pos) : "";
        if (te.selectedText === "" && ")]}\"'`".indexOf(ch) >= 0 && next === ch) { te.cursorPosition = pos + 1; return true; }
        if (!pairs[ch]) return false;
        if (te.selectedText !== "") {
            const a = te.selectionStart, b = te.selectionEnd, inner = te.getText(a, b);
            te.remove(a, b);
            te.insert(a, ch + inner + pairs[ch]);
            te.select(a + 1, a + 1 + inner.length);
            return true;
        }
        const quote = ch === pairs[ch];
        const okNext = next === "" || /[\s)\]};,:\u2029]/.test(next);
        const okPrev = !quote || !/[\w"'`\\]/.test(prev);
        if (!okNext || !okPrev) return false;
        te.insert(pos, ch + pairs[ch]);
        te.cursorPosition = pos + 1;
        return true;
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

    CompletionPopup {
        id: completion
        property int line: -1
        readonly property rect cr: te.cursorRectangle
        x: Math.max(0, Math.min(page.width - width - 8, flick.x + te.x + cr.x - flick.contentX - fm.averageCharacterWidth * page.wordBefore().length - 30))
        y: {
            const below = te.y + cr.y - flick.contentY + cr.height + 4;
            return below + height > page.height - 8 ? te.y + cr.y - flick.contentY - height - 4 : below;
        }
        fontFamily: page.fontFamily
        onVisibleChanged: if (visible) line = page.lineCol.y
        onAccepted: (item) => page.acceptCompletion(item)
    }

    // Opis po najechaniu: błąd w tym miejscu i odpowiedź serwera języka
    Rectangle {
        id: tip
        property string text
        property point at
        visible: text !== "" && (hov.hovered || page.testTip)
        z: 60
        width: Math.min(560, tipText.implicitWidth + 24)
        height: Math.min(320, tipText.implicitHeight + 16)
        x: Math.max(4, Math.min(page.width - width - 8, at.x - 20))
        y: at.y - height - 6 >= 0 ? at.y - height - 6 : at.y + fm.height + 8
        radius: 10
        color: Theme.surface
        border.width: 1; border.color: Theme.edge
        clip: true
        Text {
            id: tipText
            x: 12; y: 8
            width: Math.min(536, implicitWidth)
            wrapMode: Text.Wrap
            text: tip.text
            color: Theme.text
            font.family: page.fontFamily; font.pixelSize: 12
            lineHeight: 1.15
        }
    }

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
