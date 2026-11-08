pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Jedna karta edytora kodu: margines (numery wierszy i zmiany z gita), bieżący wiersz, dopasowane
// nawiasy, trafienia szukania i tekst z kolorowaniem składni (KSyntaxHighlighting — jak w Edytorze tekstu).
// Klawisze jak w VS Code: Tab/Shift+Tab, Alt+↑/↓, Shift+Alt+↑/↓, Ctrl+Shift+K, Ctrl+Enter, Home.
// Serwer języka (Lsp): podpowiedzi przy pisaniu i Ctrl+Spacja, opis po najechaniu, Ctrl+klik — definicja,
// podkreślone błędy i kropki przy numerach wierszy. Nawiasy i cudzysłowy domykają się same.
// Wiele kursorów: Ctrl+D (następne wystąpienie), Ctrl+Shift+L (wszystkie), Alt+klik, Ctrl+Alt+↑/↓, Esc — jeden.
// Zwijanie bloków (z wcięć): strzałki w marginesie, Ctrl+Shift+[ / ], „⋯” za zwiniętym wierszem; minimapa po prawej.
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
    // Z serwera języka i z ostatniego zadania (błędy kompilatora)
    readonly property var diagnostics: { Lsp.revision; Tasks.errorCount; Tasks.warningCount; return path ? Lsp.diagnostics(path).concat(Tasks.diagnostics(path)) : []; }
    property string lspPath: ""
    property int compSeq: -1
    property int hoverSeq: -1
    property string hoverDiag: ""
    signal zoomRequested(int d)
    signal edited()
    signal definitionRequested(int seq)
    signal editFocused()
    property bool lspPrimary: true                  // duplikat w drugiej grupie nie otwiera dokumentu w serwerze
    // Z ustawień
    property bool autoClose: true
    property bool autoComplete: true
    property string defaultIndent: "4"              // dla plików bez wcięć: "2", "4", "tab"
    signal quickFixRequested()
    // ——— Zwijanie i minimapa ———
    property var foldRanges: []
    property var folded: []                         // wiersze-nagłówki zwiniętych bloków
    property bool showMinimap: true
    function updateFolds() {
        TextOps.repairFolds(te.textDocument);
        foldRanges = TextOps.foldRanges(te.textDocument);
        folded = TextOps.foldedLines(te.textDocument);
    }
    function toggleFold(line) {
        TextOps.setFolded(te.textDocument, line, folded.indexOf(line) < 0);
        folded = TextOps.foldedLines(te.textDocument);
        // Kursor nie zostaje w ukrytym wierszu
        if (!TextOps.lineVisible(te.textDocument, lineCol.y)) te.cursorPosition = TextOps.positionOfLine(te.textDocument, line);
    }
    // Najmniejszy blok obejmujący wiersz kursora (albo zaczynający się w nim)
    function foldAtCursor(fold) {
        const l = lineCol.y;
        let best = null;
        for (const r of foldRanges) {
            if (r.start <= l && r.end >= l && (fold ? folded.indexOf(r.start) < 0 : folded.indexOf(r.start) >= 0))
                if (!best || r.start > best.start) best = r;
        }
        if (fold && !best) return;
        if (!fold) {
            const f = folded.find(h => h === l);
            if (f !== undefined) { toggleFold(f); return; }
            if (!best) return;
        }
        toggleFold(best.start);
    }
    function foldAllBlocks() { TextOps.foldAll(te.textDocument); folded = TextOps.foldedLines(te.textDocument); TextOps.revealLine(te.textDocument, lineCol.y); }
    function unfoldAllBlocks() { TextOps.unfoldAll(te.textDocument); folded = []; }
    Timer { id: foldTimer; interval: 300; onTriggered: page.updateFolds() }

    // ——— Wiele kursorów ———
    // TextEdit ma jeden kursor (główny); dodatkowe są tu: [{ a: kotwica, p: pozycja }], rysowane i obsługiwane ręcznie
    property var extras: []
    readonly property int cursorCount: extras.length + 1
    property bool occurrenceWord: false            // Ctrl+D zaczęło od słowa — szukamy całych słów
    function primaryCursor() {
        const p = te.cursorPosition;
        return { a: p === te.selectionStart ? te.selectionEnd : te.selectionStart, p: p };
    }
    function allCursors() { return [primaryCursor()].concat(extras); }
    function setCursors(list) {
        if (!list.length) return;
        const pr = list[0];
        te.cursorPosition = pr.a;
        if (pr.p !== pr.a) te.moveCursorSelection(pr.p, TextEdit.SelectCharacters);
        const seen = {}, out = [];
        seen[pr.a + ":" + pr.p] = true;
        for (let i = 1; i < list.length; ++i) {
            const k = list[i].a + ":" + list[i].p;
            if (!seen[k]) { seen[k] = true; out.push(list[i]); }
        }
        extras = out;
    }
    function clearExtras() { if (extras.length) extras = []; }
    function addCursorAt(pos) { if (pos !== te.cursorPosition) extras = extras.concat([{ a: pos, p: pos }]); }
    // Zamiana zaznaczeń (albo zakresów z rangeFn) przy wszystkich kursorach — jeden krok cofania
    function multiReplace(text, caretOffset, rangeFn) {
        const cs = allCursors();
        const ranges = cs.map(c => rangeFn ? rangeFn(c) : { a: Math.min(c.a, c.p), b: Math.max(c.a, c.p) });
        const texts = cs.map((c, i) => typeof text === "function" ? text(c, i) : text);
        const res = TextOps.multiEdit(te.textDocument, ranges, texts, caretOffset === undefined ? -1 : caretOffset);
        if (!res.length) return;
        const prim = res.find(r => r.i === 0) || res[0];
        setCursors([{ a: prim.p, p: prim.p }].concat(res.filter(r => r !== prim).map(r => ({ a: r.p, p: r.p }))));
    }
    function moveAll(fn, extend) {
        setCursors(allCursors().map(c => { const np = fn(c); return { a: extend ? c.a : np, p: np }; }));
    }
    function lineStartOf(pos) { return TextOps.positionOfLine(te.textDocument, TextOps.lineColumn(te.textDocument, pos).y); }
    function lineEndOf(pos) { const l = TextOps.lineColumn(te.textDocument, pos).y; return TextOps.positionOfLine(te.textDocument, l) + TextOps.lineText(te.textDocument, l).length; }
    function verticalPos(pos, dir) {
        const r = te.positionToRectangle(pos);
        return te.positionAt(r.x + 1, dir < 0 ? r.y - r.height / 2 : r.y + r.height * 1.5);
    }
    // Ctrl+D: pierwsze naciśnięcie zaznacza słowo, kolejne dodają następne wystąpienie
    function addNextOccurrence() {
        if (te.selectedText === "") {
            const w = TextOps.wordAt(te.textDocument, te.cursorPosition);
            if (!w.text) return;
            te.select(w.start, w.end);
            occurrenceWord = true;
            return;
        }
        const needle = te.selectedText;
        if (needle.indexOf("\u2029") >= 0) return;
        const cs = allCursors();
        const last = Math.max.apply(null, cs.map(c => Math.max(c.a, c.p)));
        const next = TextOps.findNext(te.textDocument, needle, last, occurrenceWord);
        if (next < 0 || cs.some(c => Math.min(c.a, c.p) === next)) return;
        extras = extras.concat([{ a: next, p: next + needle.length }]);
        const r = te.positionToRectangle(next);
        if (r.y < flick.contentY || r.y > flick.contentY + flick.height - r.height)
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, r.y - flick.height / 3));
    }
    function selectAllOccurrences() {
        if (te.selectedText === "") {
            const w = TextOps.wordAt(te.textDocument, te.cursorPosition);
            if (!w.text) return;
            te.select(w.start, w.end);
            occurrenceWord = true;
        }
        const needle = te.selectedText;
        if (!needle || needle.indexOf("\u2029") >= 0) return;
        const all = TextOps.findAll(te.textDocument, needle, occurrenceWord);
        const cur = te.selectionStart;
        extras = all.filter(p => p !== cur).map(p => ({ a: p, p: p + needle.length }));
    }
    function addCursorVertical(dir) {
        const cs = allCursors();
        const edge = cs.reduce((m, c) => dir < 0 ? (c.p < m.p ? c : m) : (c.p > m.p ? c : m), cs[0]);
        const lc = TextOps.lineColumn(te.textDocument, edge.p);
        const line = lc.y + dir;
        if (line < 0 || line >= TextOps.lineCount(te.textDocument)) return;
        const pos = TextOps.positionOfLine(te.textDocument, line) + Math.min(lc.x, TextOps.lineText(te.textDocument, line).length);
        extras = extras.concat([{ a: pos, p: pos }]);
    }
    // Klawisze przy kilku kursorach; true — obsłużone
    function multiKey(e) {
        const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier, alt = e.modifiers & Qt.AltModifier;
        const k = e.key;
        if (k === Qt.Key_Escape) { clearExtras(); return true; }
        if (ctrl && (k === Qt.Key_Z || k === Qt.Key_Y || k === Qt.Key_A)) { clearExtras(); return false; }
        if (!ctrl && !alt) {
            if (k === Qt.Key_Left) { moveAll(c => c.a !== c.p && !shift ? Math.min(c.a, c.p) : Math.max(0, c.p - 1), shift); return true; }
            if (k === Qt.Key_Right) { moveAll(c => c.a !== c.p && !shift ? Math.max(c.a, c.p) : Math.min(te.length, c.p + 1), shift); return true; }
            if (k === Qt.Key_Home) { moveAll(c => lineStartOf(c.p), shift); return true; }
            if (k === Qt.Key_End) { moveAll(c => lineEndOf(c.p), shift); return true; }
            if (k === Qt.Key_Up || k === Qt.Key_Down) { moveAll(c => verticalPos(c.p, k === Qt.Key_Up ? -1 : 1), shift); return true; }
            if (k === Qt.Key_Backspace) { multiReplace("", -1, c => c.a !== c.p ? { a: Math.min(c.a, c.p), b: Math.max(c.a, c.p) } : { a: Math.max(0, c.p - 1), b: c.p }); return true; }
            if (k === Qt.Key_Delete) { multiReplace("", -1, c => c.a !== c.p ? { a: Math.min(c.a, c.p), b: Math.max(c.a, c.p) } : { a: c.p, b: Math.min(te.length, c.p + 1) }); return true; }
            if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                multiReplace(c => "\n" + TextOps.lineText(te.textDocument, TextOps.lineColumn(te.textDocument, c.p).y).match(/^[ \t]*/)[0]);
                return true;
            }
            if (k === Qt.Key_Tab) { multiReplace(indentUnit); return true; }
        }
        // Schowek: każde zaznaczenie w osobnym wierszu; wklejanie rozdziela wiersze po kursorach, gdy ich liczba się zgadza
        const ordered = () => allCursors().map((c, i) => ({ c: c, i: i })).sort((x, y) => Math.min(x.c.a, x.c.p) - Math.min(y.c.a, y.c.p));
        if (ctrl && !alt && (k === Qt.Key_C || k === Qt.Key_X)) {
            Project.copyText(ordered().map(o => te.getText(Math.min(o.c.a, o.c.p), Math.max(o.c.a, o.c.p))).join("\n"));
            if (k === Qt.Key_X) multiReplace("");
            return true;
        }
        if (ctrl && !alt && k === Qt.Key_V) {
            const t = Project.clipboardText(), lines = t.split("\n");
            if (lines.length === cursorCount) {
                const rank = {};
                ordered().forEach((o, r) => rank[o.i] = r);
                multiReplace((c, i) => lines[rank[i]]);
            } else {
                multiReplace(t);
            }
            return true;
        }
        if (!ctrl && e.text.length === 1 && e.text >= " ") {
            const pairs = { "(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`" };
            if (pairs[e.text] && allCursors().every(c => c.a === c.p)) multiReplace(e.text + pairs[e.text], 1);
            else multiReplace(e.text);
            return true;
        }
        return false;
    }

    // Konflikty łączenia i autor wierszy (git blame)
    property var conflicts: []
    property bool showBlame: true
    property var blameCommits: []
    property var blameLines: []
    function refreshBlame() { if (path && showBlame && Project.isGit) Project.blame(path, te.text); }
    function updateConflicts() { conflicts = te.text.indexOf("<<<<<<<") >= 0 ? TextOps.conflicts(te.textDocument) : []; }
    function resolve(startLine, choice) { TextOps.resolveConflict(te.textDocument, startLine, choice); Qt.callLater(updateConflicts); }
    function lineY(n) { return te.positionToRectangle(TextOps.positionOfLine(te.textDocument, n)).y + te.y; }
    function ago(t) {
        const s = Math.max(0, Date.now() / 1000 - t);
        if (s < 60) return "przed chwilą";
        if (s < 3600) return Math.floor(s / 60) + " min temu";
        if (s < 86400) return Math.floor(s / 3600) + " godz. temu";
        const d = Math.floor(s / 86400);
        if (d === 1) return "wczoraj";
        if (d < 30) return d + " dni temu";
        if (d < 365) return Math.floor(d / 30) + " mies. temu";
        return new Date(t * 1000).toLocaleDateString(Qt.locale("pl_PL"), "d.MM.yyyy");
    }
    readonly property string blameText: {
        if (!showBlame || !blameLines.length) return "";
        const c = blameCommits[blameLines[lineCol.y]];
        if (!c) return "";
        if (c.uncommitted) return "Ty · niezatwierdzone";
        return (c.author || "") + ", " + ago(c.time || 0) + " · " + (c.summary || "");
    }
    onShowBlameChanged: if (showBlame) refreshBlame(); else { blameCommits = []; blameLines = []; }
    property int sigSeq: -1
    signal contextMenuRequested(Item item, real x, real y)

    function load(text, cursor) {
        te.text = text;
        te.textDocument.modified = false;
        const ind = TextOps.detectIndent(text);
        // Bez żadnego wciętego wiersza — wcięcie z ustawień
        const known = /^[ \t]+\S/m.test(text);
        indentTabs = known ? ind.tabs : defaultIndent === "tab";
        indentSize = known ? ind.size : (defaultIndent === "2" ? 2 : 4);
        te.cursorPosition = Math.max(0, Math.min(cursor || 0, te.length));
        Qt.callLater(ensureVisible);
        requestBase();
        lspPath = path;
        if (lspPrimary) Lsp.open(path, text);
        serverInfo = Lsp.serverFor(path);
        updateConflicts();
        updateFolds();
    }
    onPathChanged: {
        // Zmiana nazwy pliku — serwer języka dostaje „nowy” dokument
        if (!lspPath || lspPath === path) return;
        if (lspPrimary) Lsp.close(lspPath);
        lspPath = path;
        if (lspPrimary) Lsp.open(path, te.text);
        serverInfo = Lsp.serverFor(path);
    }
    Component.onDestruction: if (lspPath && lspPrimary) Lsp.close(lspPath)
    function requestBase() { if (path) Project.requestBase(path); refreshBlame(); }
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
        clearExtras();
        // Cel w zwiniętym bloku — najpierw rozwiń, potem licz położenie
        if (folded.length) {
            TextOps.revealLine(te.textDocument, TextOps.lineColumn(te.textDocument, start).y);
            folded = TextOps.foldedLines(te.textDocument);
        }
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
        if (ch === "(" || ch === ",") signatureTimer.restart();
        else if (ch === ")") sig.text = "";
        if (completion.visible) {
            if (trigger) { completion.hide(); completionTimer.restart(); }
            else if (!w) completion.hide();
            else completion.filter(w);
        } else if (lspOn && autoComplete && (trigger || w.length >= 1)) {
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
    // Zmiana nazwy, odwołania, formatowanie — numer zapytania albo −1 (brak serwera)
    function symbolAt() { return TextOps.wordAt(te.textDocument, te.cursorPosition); }
    function renameSymbol(name) {
        if (!lspOn) return -1;
        const w = symbolAt(), lc = TextOps.lineColumn(te.textDocument, w.start);
        Lsp.update(path, te.text);
        return Lsp.rename(path, lc.y, lc.x, name);
    }
    function findReferences() {
        if (!lspOn) return -1;
        const w = symbolAt(), lc = TextOps.lineColumn(te.textDocument, w.start);
        Lsp.update(path, te.text);
        return Lsp.references(path, lc.y, lc.x);
    }
    function formatDocument() {
        if (!lspOn) return -1;
        Lsp.update(path, te.text);
        return Lsp.format(path, indentSize, !indentTabs);
    }
    function requestCodeActions() {
        if (!lspOn) return -1;
        const a = TextOps.lineColumn(te.textDocument, te.selectionStart), b = TextOps.lineColumn(te.textDocument, te.selectionEnd);
        Lsp.update(path, te.text);
        return Lsp.codeActions(path, a.y, a.x, b.y, b.x);
    }
    function requestSignature() {
        if (!lspOn) return;
        Lsp.update(path, te.text);
        sigSeq = Lsp.signatureHelp(path, lineCol.y, lineCol.x);
    }
    readonly property bool lineHasProblem: { diagnostics; lineCol; return diagnostics.some(d => d.line === lineCol.y && d.severity <= 2); }
    function applyEdits(edits) {
        const cursor = te.cursorPosition;
        const n = TextOps.applyEdits(te.textDocument, edits);
        te.cursorPosition = Math.min(cursor, te.length);
        return n;
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
        if (extras.length) { multiReplace(ch); return; }
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
    Timer { id: conflictTimer; interval: 200; onTriggered: page.updateConflicts() }
    Timer { id: blameTimer; interval: 1500; onTriggered: page.refreshBlame() }
    Timer { id: signatureTimer; interval: 80; onTriggered: page.requestSignature() }
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
        // Serwery włączone z powrotem w ustawieniach — karta zgłasza swój plik
        function onEnabledChanged() { if (Lsp.enabled && page.lspPrimary && page.path) Lsp.open(page.path, te.text); }
        function onSignatureReady(seq, p, label, a, b) {
            if (seq !== page.sigSeq || !te.activeFocus) return;
            const esc = (t) => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
            sig.line = page.lineCol.y;
            sig.text = !label ? "" : a >= 0 ? esc(label.slice(0, a)) + "<b><font color=\"" + Theme.accentText + "\">" + esc(label.slice(a, b)) + "</font></b>" + esc(label.slice(b)) : esc(label);
        }
    }

    Connections {
        target: Project
        function onBlameReady(p, commits, lines) {
            if (p !== page.path) return;
            page.blameCommits = commits;
            page.blameLines = lines;
        }
        function onBaseReady(p, text, ok) {
            if (p !== page.path) return;
            gutter.baseText = text;
            gutter.hasBase = ok;
        }
    }

    // ——— Margines ———
    Gutter {
        id: gutter
        width: Math.max(3, String(lineCount).length) * fm.averageCharacterWidth + 48
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
        breakpoints: { Debugger.revision; return page.path ? Debugger.breakpoints(page.path) : []; }
        stopLine: Debugger.stopPath === page.path ? Debugger.stopLine : -1
        errorColor: Theme.danger
        warningColor: Theme.dark ? "#E3B341" : "#BF8700"
        FontMetrics { id: fm; font: te.font }
        // Klik w numer — zaznacza wiersz
        MouseArea {
            id: gutterArea
            anchors.fill: parent
            hoverEnabled: true
            onPressed: (e) => {
                const p = te.positionAt(0, e.y + flick.contentY);
                const l = TextOps.lineColumn(te.textDocument, p).y;
                // Lewy brzeg marginesu — punkt przerwania
                if (e.x < 17) { Debugger.toggleBreakpoint(page.path, l); return; }
                const a = TextOps.positionOfLine(te.textDocument, l);
                const b = l + 1 < TextOps.lineCount(te.textDocument) ? TextOps.positionOfLine(te.textDocument, l + 1) : te.length;
                te.forceActiveFocus();
                te.select(a, b);
            }
        }
    }

    // Strzałki zwijania w marginesie (pokazują się po najechaniu; zwinięte — zawsze)
    Item {
        id: foldMarks
        x: gutter.x + gutter.width - 30
        width: 16; height: parent.height
        clip: true
        HoverHandler { id: gutterHover; target: null }
        Repeater {
            model: {
                flick.contentY; flick.height; te.length; page.folded;
                const first = TextOps.lineColumn(te.textDocument, te.positionAt(0, flick.contentY)).y;
                const last = TextOps.lineColumn(te.textDocument, te.positionAt(0, flick.contentY + flick.height)).y;
                return page.foldRanges.filter(r => r.start >= first - 1 && r.start <= last + 1 && TextOps.lineVisible(te.textDocument, r.start));
            }
            delegate: HoverButton {
                id: fb
                required property var modelData
                readonly property bool isFolded: page.folded.indexOf(modelData.start) >= 0
                readonly property rect r: { te.length; page.folded; return te.positionToRectangle(TextOps.positionOfLine(te.textDocument, modelData.start)); }
                visible: isFolded || gutterHover.hovered || gutterArea.containsMouse
                x: 0; y: r.y + te.y - flick.contentY + (r.height - height) / 2
                width: 16; height: 16; radius: 4
                onClicked: page.toggleFold(modelData.start)
                Icon { anchors.centerIn: parent; d: fb.isFolded ? Icons.chevronRight : Icons.chevronDown; size: 11; stroke: 2; color: fb.isFolded ? Theme.accentText : Theme.text2 }
            }
        }
    }

    Flickable {
        id: flick
        anchors.left: gutter.right
        width: parent.width - gutter.width - (page.showMinimap ? minimap.width + 6 : 0)
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
                flick.contentY; flick.height; te.length; page.folded;
                if (!page.matches.length || page.matchLength <= 0) return [];
                const a = te.positionAt(0, flick.contentY - 40), b = te.positionAt(flick.contentX + flick.width, flick.contentY + flick.height + 40);
                const out = [];
                for (let i = 0; i < page.matches.length && out.length < 400; ++i)
                    if (page.matches[i] >= a && page.matches[i] <= b
                        && (!page.folded.length || TextOps.lineVisible(te.textDocument, TextOps.lineColumn(te.textDocument, page.matches[i]).y)))
                        out.push({ pos: page.matches[i], cur: i === page.currentMatch });
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

        // Wiersz, w którym zatrzymał się debuger
        Rectangle {
            visible: Debugger.stopPath === page.path && Debugger.stopLine >= 0
            readonly property rect r: { te.length; page.folded; return te.positionToRectangle(TextOps.positionOfLine(te.textDocument, Math.max(0, Debugger.stopLine))); }
            y: te.y + r.y; width: Math.max(flick.width, flick.contentWidth); height: r.height
            color: Qt.rgba(0.96, 0.76, 0.24, Theme.dark ? 0.20 : 0.28)
        }

        // Konflikty łączenia: moja wersja na zielono, przychodząca na niebiesko, przyciski przy znaczniku <<<<<<<
        Repeater {
            model: page.conflicts
            delegate: Item {
                id: block
                required property var modelData
                readonly property real y0: { te.length; return page.lineY(modelData.startLine); }
                readonly property real y1: { te.length; return page.lineY(modelData.startLine + 1); }
                readonly property real yb: { te.length; return page.lineY(modelData.baseLine >= 0 ? modelData.baseLine : modelData.sepLine); }
                readonly property real ys: { te.length; return page.lineY(modelData.sepLine); }
                readonly property real ys1: { te.length; return page.lineY(modelData.sepLine + 1); }
                readonly property real ye: { te.length; return page.lineY(modelData.endLine); }
                readonly property real ye1: { te.length; return page.lineY(modelData.endLine) + fm.height * 1.0 + 3; }
                readonly property color oursColor: Theme.dark ? "#3FB950" : "#1A7F37"
                readonly property color theirsColor: Theme.dark ? "#58A6FF" : "#0969DA"
                width: Math.max(flick.width, flick.contentWidth)
                Rectangle { y: block.y0; width: parent.width; height: block.y1 - block.y0; color: Qt.rgba(block.oursColor.r, block.oursColor.g, block.oursColor.b, 0.28) }
                Rectangle { y: block.y1; width: parent.width; height: block.yb - block.y1; color: Qt.rgba(block.oursColor.r, block.oursColor.g, block.oursColor.b, 0.10) }
                Rectangle { y: block.yb; width: parent.width; height: block.ys1 - block.yb; color: Qt.rgba(0.5, 0.5, 0.5, 0.12) }
                Rectangle { y: block.ys1; width: parent.width; height: block.ye - block.ys1; color: Qt.rgba(block.theirsColor.r, block.theirsColor.g, block.theirsColor.b, 0.10) }
                Rectangle { y: block.ye; width: parent.width; height: block.ye1 - block.ye; color: Qt.rgba(block.theirsColor.r, block.theirsColor.g, block.theirsColor.b, 0.28) }
                Row {
                    z: 4
                    readonly property rect endRect: { te.length; return te.positionToRectangle(TextOps.positionOfLine(te.textDocument, block.modelData.startLine)
                                                                                                  + TextOps.lineText(te.textDocument, block.modelData.startLine).length); }
                    x: te.x + endRect.x + 18; y: block.y0 + (block.y1 - block.y0 - 20) / 2
                    spacing: 4
                    ConflictBtn { text: "Zostaw moją"; tint: block.oursColor; onClicked: page.resolve(block.modelData.startLine, "ours") }
                    ConflictBtn { text: "Weź przychodzącą (" + block.modelData.theirs + ")"; tint: block.theirsColor; onClicked: page.resolve(block.modelData.startLine, "theirs") }
                    ConflictBtn { text: "Obie"; tint: Theme.text2; onClicked: page.resolve(block.modelData.startLine, "both") }
                }
            }
        }

        // Błędy i ostrzeżenia z serwera języka — podkreślenie fragmentu (w widocznej części)
        Repeater {
            model: {
                flick.contentY; flick.height; te.length; page.folded;
                const d = page.diagnostics;
                if (!d.length) return [];
                const first = TextOps.lineColumn(te.textDocument, te.positionAt(0, flick.contentY)).y - 1;
                const last = TextOps.lineColumn(te.textDocument, te.positionAt(0, flick.contentY + flick.height)).y + 1;
                const out = [];
                for (let i = 0; i < d.length && out.length < 300; ++i) {
                    if (d[i].line < first || d[i].line > last || d[i].severity > 2 || !TextOps.lineVisible(te.textDocument, d[i].line)) continue;
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

        // Zaznaczenia dodatkowych kursorów
        Repeater {
            model: {
                te.length; te.contentWidth;
                const rects = [];
                for (const c of page.extras) {
                    const a = Math.min(c.a, c.p), b = Math.max(c.a, c.p);
                    if (a === b) continue;
                    const la = TextOps.lineColumn(te.textDocument, a).y, lb = TextOps.lineColumn(te.textDocument, b).y;
                    for (let l = la; l <= lb && rects.length < 1000; ++l) {
                        const ls = TextOps.positionOfLine(te.textDocument, l), le = ls + TextOps.lineText(te.textDocument, l).length;
                        const r1 = te.positionToRectangle(l === la ? a : ls), r2 = te.positionToRectangle(l === lb ? b : le);
                        rects.push({ x: r1.x, y: r1.y, w: Math.max(2, r2.x - r1.x + (l < lb ? fm.averageCharacterWidth * 0.6 : 0)), h: r1.height });
                    }
                }
                return rects;
            }
            delegate: Rectangle {
                required property var modelData
                x: te.x + modelData.x; y: te.y + modelData.y
                width: modelData.w; height: modelData.h
                color: Theme.accentSoft
            }
        }

        TextEdit {
            id: te
            // Naturalna szerokość przez callLater — inaczej zmiana szerokości okna (podział) wiąże width z implicitWidth w pętlę
            property real naturalWidth: 0
            onImplicitWidthChanged: Qt.callLater(() => te.naturalWidth = te.implicitWidth)
            Component.onCompleted: naturalWidth = implicitWidth
            width: page.wrap ? flick.width : Math.max(flick.width, naturalWidth)
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
                // Kursor wszedł w zwinięty blok (strzałki, szukanie) — rozwiń
                if (page.folded.length && !TextOps.lineVisible(te.textDocument, page.lineCol.y)) {
                    TextOps.revealLine(te.textDocument, page.lineCol.y);
                    page.folded = TextOps.foldedLines(te.textDocument);
                }
                if (sig.text && page.lineCol.y !== sig.line) sig.text = "";
                if (completion.visible && page.lineCol.y !== completion.line) completion.hide();
            }
            onLengthChanged: { Qt.callLater(page.updateFirstLine); page.edited(); }
            onTextChanged: {
                if (page.lspOn) lspTimer.restart();
                conflictTimer.restart();
                foldTimer.restart();
                if (page.showBlame && page.blameLines.length) blameTimer.restart();
            }
            onActiveFocusChanged: { if (!activeFocus) { completion.hide(); sig.text = ""; } else page.editFocused(); }

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
            // Alt+klik — dodatkowy kursor; zwykły klik — z powrotem jeden kursor
            TapHandler {
                acceptedModifiers: Qt.AltModifier
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: (ev) => page.addCursorAt(te.positionAt(ev.position.x, ev.position.y))
            }
            TapHandler {
                acceptedModifiers: Qt.NoModifier
                onPressedChanged: if (pressed) page.clearExtras()
            }
            // Ctrl+klik — przejdź do definicji
            TapHandler {
                acceptedModifiers: Qt.ControlModifier
                onTapped: (ev) => page.definitionRequested(page.goToDefinition(te.positionAt(ev.position.x, ev.position.y)))
            }

            Keys.onPressed: (e) => page.handleKey(e)
        }

        // Dodatkowe kursory (bez migania)
        Repeater {
            model: page.extras
            delegate: Rectangle {
                required property var modelData
                readonly property rect r: { te.length; te.contentWidth; return te.positionToRectangle(modelData.p); }
                visible: te.activeFocus
                x: te.x + r.x; y: te.y + r.y
                width: 2; height: r.height
                color: Theme.text
            }
        }

        // Żarówka przy wierszu z problemem — szybkie poprawki (Ctrl+.)
        HoverButton {
            readonly property rect endRect: { te.length; page.lineCol; page.folded; return te.positionToRectangle(TextOps.positionOfLine(te.textDocument, page.lineCol.y) + TextOps.lineText(te.textDocument, page.lineCol.y).length); }
            visible: page.lineHasProblem && te.activeFocus
            z: 3
            x: te.x + endRect.x + 12; y: te.y + endRect.y + (endRect.height - height) / 2
            width: 22; height: 20; radius: 6
            baseColor: Theme.dark ? Qt.rgba(0.89, 0.70, 0.25, 0.18) : Qt.rgba(0.75, 0.53, 0, 0.12)
            onClicked: page.quickFixRequested()
            Icon { anchors.centerIn: parent; d: Icons.bolt; size: 13; stroke: 1.8; color: Theme.dark ? "#E3B341" : "#9A6700" }
        }

        // „⋯” za zwiniętym wierszem — klik rozwija
        Repeater {
            model: page.folded
            delegate: HoverButton {
                required property int modelData
                readonly property rect endRect: { te.length; page.folded; return te.positionToRectangle(TextOps.positionOfLine(te.textDocument, modelData) + TextOps.lineText(te.textDocument, modelData).length); }
                z: 3
                x: te.x + endRect.x + 8; y: te.y + endRect.y + (endRect.height - height) / 2
                width: 30; height: 16; radius: 5
                baseColor: Theme.accentAlpha(Theme.dark ? 0.22 : 0.12)
                onClicked: page.toggleFold(modelData)
                Text { anchors.centerIn: parent; anchors.verticalCenterOffset: -3; text: "⋯"; color: Theme.accentText; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Bold }
            }
        }

        // Autor bieżącego wiersza (git blame) — szary dopisek za końcem wiersza
        Text {
            readonly property rect endRect: { te.length; page.lineCol; page.folded; return te.positionToRectangle(TextOps.positionOfLine(te.textDocument, page.lineCol.y) + TextOps.lineText(te.textDocument, page.lineCol.y).length); }
            visible: page.blameText !== "" && te.activeFocus && te.selectedText === "" && !page.conflicts.length && !page.extras.length
            x: te.x + endRect.x + (page.lspOn && page.lineHasProblem ? 48 : 28)
            y: te.y + endRect.y + (endRect.height - height) / 2
            text: page.blameText
            color: Theme.text2; opacity: 0.6
            font.family: Theme.font; font.pixelSize: 12; font.italic: true
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
        if (ctrl && !shift && !alt && e.key === Qt.Key_D) { addNextOccurrence(); e.accepted = true; return; }
        if (ctrl && shift && e.key === Qt.Key_L) { selectAllOccurrences(); e.accepted = true; return; }
        if (ctrl && alt && (e.key === Qt.Key_Up || e.key === Qt.Key_Down)) { addCursorVertical(e.key === Qt.Key_Up ? -1 : 1); e.accepted = true; return; }
        if (extras.length && multiKey(e)) { e.accepted = true; return; }
        if (ctrl && e.key === Qt.Key_Space) { requestCompletion(); e.accepted = true; return; }
        if (!ctrl && !alt && e.text.length === 1 && (autoClose || ")]}\"'`".indexOf(e.text) >= 0) && autoPair(e.text)) {
            const pc = e.text;
            Qt.callLater(() => page.afterTyped(pc));
            e.accepted = true;
            return;
        }
        if (!ctrl && !alt && e.text === ",") Qt.callLater(() => page.afterTyped(","));
        if (e.key === Qt.Key_Escape && sig.text) { sig.text = ""; e.accepted = true; return; }
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
    component ConflictBtn: HoverButton {
        id: cb
        property string text
        property color tint
        width: cbText.implicitWidth + 16; height: 20; radius: 6
        baseColor: Qt.rgba(cb.tint.r, cb.tint.g, cb.tint.b, Theme.dark ? 0.22 : 0.14)
        Text { id: cbText; anchors.centerIn: parent; text: cb.text; color: Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
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

    // Podpowiedź parametrów nad kursorem (po „(” i „,”), aktywny parametr wyróżniony
    Rectangle {
        id: sig
        property string text
        property int line: -1
        readonly property rect cr: te.cursorRectangle
        visible: text !== "" && !completion.visible
        z: 55
        width: Math.min(page.width - 16, sigText.implicitWidth + 20)
        height: sigText.implicitHeight + 12
        x: Math.max(4, Math.min(page.width - width - 8, flick.x + te.x + cr.x - flick.contentX - 20))
        y: te.y + cr.y - flick.contentY - height - 4 >= 0 ? te.y + cr.y - flick.contentY - height - 4 : te.y + cr.y - flick.contentY + cr.height + 4
        radius: 8
        color: Theme.surface
        border.width: 1; border.color: Theme.edge
        Text {
            id: sigText
            x: 10; y: 6
            width: Math.min(implicitWidth, page.width - 36)
            elide: Text.ElideRight
            textFormat: Text.StyledText
            text: sig.text
            color: Theme.text; font.family: page.fontFamily; font.pixelSize: 12
        }
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

    // Przewijanie kółkiem i touchpadem na całej karcie, także nad marginesem (Flickable jest nieinteraktywny —
    // przeciąganie zaznacza tekst — więc sam nie przewija). Shift — w bok, Ctrl — powiększenie.
    // Bez acceptedModifiers: Qt porównuje je dokładnie, „NoModifier | Shift” znaczyłoby „tylko z Shiftem”.
    function wheelScroll(e) {
        if (e.modifiers & Qt.ControlModifier) {
            if (e.angleDelta.y !== 0) page.zoomRequested(e.angleDelta.y > 0 ? 1 : -1);
            return;
        }
        const step = te.cursorRectangle.height || 20;
        let dx = e.pixelDelta.x !== 0 ? e.pixelDelta.x : e.angleDelta.x / 120 * step * 3;
        let dy = e.pixelDelta.y !== 0 ? e.pixelDelta.y : e.angleDelta.y / 120 * step * 3;
        if (e.modifiers & Qt.ShiftModifier) { dx = dx || dy; dy = 0; }
        flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY - dy));
        flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - dx));
    }
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (e) => page.wheelScroll(e)
    }
    WheelHandler {
        orientation: Qt.Horizontal
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (e) => page.wheelScroll(e)
    }

    // Minimapa
    Minimap {
        id: minimap
        visible: page.showMinimap
        anchors.right: parent.right; anchors.rightMargin: 4
        width: 74; height: parent.height
        document: te.textDocument
        firstLine: { flick.contentY; return TextOps.lineColumn(te.textDocument, te.positionAt(0, flick.contentY)).y; }
        visibleLines: Math.max(1, Math.floor(flick.height / Math.max(1, fm.height)))
        textColor: Theme.text2
        sliderColor: Theme.dark ? Qt.rgba(1, 1, 1, mapArea.containsMouse || mapArea.pressed ? 0.12 : 0.07) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, mapArea.containsMouse || mapArea.pressed ? 0.10 : 0.06)
        marks: {
            const out = [];
            for (const d of page.diagnostics) if (d.severity <= 2) out.push({ line: d.line, color: d.severity === 1 ? String(Theme.danger) : "#D29922" });
            for (let i = 0; i < page.matches.length && i < 2000; ++i)
                out.push({ line: TextOps.lineColumn(te.textDocument, page.matches[i]).y, color: "#F5A623" });
            return out;
        }
        MouseArea {
            id: mapArea
            anchors.fill: parent
            hoverEnabled: true
            // Klik i przeciąganie: wskazany wiersz na środku widoku
            function scrollTo(y) {
                const line = Math.max(0, minimap.lineAt(y) - Math.floor(minimap.visibleLines / 2));
                const r = te.positionToRectangle(TextOps.positionOfLine(te.textDocument, line));
                flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, r.y + te.y));
            }
            onPressed: (e) => scrollTo(e.y)
            onPositionChanged: (e) => { if (pressed) scrollTo(e.y); }
            onWheel: (w) => page.wheelScroll(w)
        }
    }

    // Suwaki
    Rectangle {
        visible: flick.contentHeight > flick.height + 1
        anchors.right: flick.right; anchors.rightMargin: 3
        y: flick.visibleArea.yPosition * flick.height
        width: vArea.containsMouse || vArea.pressed ? 8 : 5; radius: width / 2
        height: Math.max(30, flick.visibleArea.heightRatio * flick.height)
        color: Theme.text2
        opacity: vArea.containsMouse || vArea.pressed ? 0.5 : 0.2
        Behavior on opacity { NumberAnimation { duration: 120 } }
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
