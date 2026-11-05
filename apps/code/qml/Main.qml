pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Dialogs
import QtCore
import Aster.Ui
import Aster.Code

// Aster Code — edytor kodu dla przesiadających się z VS Code: ten sam układ (drzewo plików,
// karty, paleta Ctrl+P, szukanie w projekcie, terminal na dole, git przy marginesie i na pasku
// stanu), ale w wyglądzie Aster: szkło okna, panel treści, kropki okna, spokojna typografia.
Window {
    id: win
    width: 1240 + 2 * m
    height: 800 + 2 * m
    minimumWidth: 640 + 2 * m
    minimumHeight: 420 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: (cur ? (cur.modified ? "• " : "") + tabTitle(current) + " — " : "") + (Project.name ? Project.name + " — " : "") + "Aster Code"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: maxed ? 0 : 24
    readonly property bool hasProject: Project.root !== ""

    Settings {
        id: prefs
        category: "code"
        property real sidebarWidth: 280
        property real terminalHeight: 260
        property real fontSize: 13.5
        property bool wrap: false
        property bool sidebar: true
        property bool blame: true
        property bool minimap: true
        property string fontFamily: "JetBrains Mono"
        property bool autoClose: true
        property bool autoComplete: true
        property string defaultIndent: "4"
        property string autoSave: "off"          // off | delay | focus
        property bool formatOnSave: false
        property bool trimTrailing: false
        property bool finalNewline: false
        property bool autoFetch: true
        property bool lsp: true
        property string recentTasks: "{}"        // folder projektu → ostatnie polecenia (JSON)
        property string debugPrograms: "{}"      // folder projektu → program i argumenty do debugowania (JSON)
        property real previewWidth: 0.45
        property bool previewOnSave: true
        property bool previewAuto: true
        property bool diffSideBySide: false
    }
    Binding { target: Lsp; property: "enabled"; value: prefs.lsp }
    Binding { target: ProjectEnv; property: "root"; value: Project.root }
    Binding { target: Secrets; property: "root"; value: Project.root }

    // Samozapis po chwili od ostatniej zmiany (bez porządkowania pliku — nie przeszkadza w pisaniu)
    Timer {
        id: autoSaveTimer
        interval: 1000
        onTriggered: { for (let i = 0; i < tabs.count; ++i) if (win.page(i) && win.page(i).modified && !tabs.get(i).readOnly) win.save(i, null, true); }
    }
    // Kopie niezapisanych kart (bez plików z sekretami) — po awarii wracają przy otwarciu projektu
    Timer {
        id: backupTimer
        interval: 2000
        onTriggered: { for (let i = 0; i < tabs.count; ++i) if (win.page(i) && win.page(i).modified && !Secrets.secretFile(tabs.get(i).path)) Project.backupWrite(tabs.get(i).path, win.page(i).edit.text); }
    }
    // Sprawdzanie serwera gita w tle
    Timer {
        interval: 5 * 60 * 1000; repeat: true
        running: prefs.autoFetch && Project.isGit && !!Project.upstream
        onTriggered: Project.fetch(true)
    }
    // Formatowanie przy zapisie: zapis czeka na serwer języka najwyżej 2 s
    property var formatSaves: ({})
    Timer {
        id: formatTimeout
        interval: 2000
        onTriggered: {
            const pend = win.formatSaves;
            win.formatSaves = {};
            for (const k in pend) { const i = win.indexOfUid(pend[k].uid); if (i >= 0) win.save(i, pend[k].then, true); }
        }
    }

    // ——— Karty ———
    ListModel { id: tabs }
    property int current: 0
    property int uidSeq: 0
    property int revision: 0
    property var pendingText: ({})
    property var pendingCursor: ({})
    property var lastSave: ({})
    readonly property var cur: { revision; return tabs.count ? pages.itemAt(Math.min(current, tabs.count - 1)) : null; }
    readonly property string curPath: { revision; return tabs.count ? tabs.get(Math.min(current, tabs.count - 1)).path : ""; }
    function page(i) { return pages.itemAt(i); }
    function tabTitle(i) { return i >= 0 && i < tabs.count ? Project.fileName(tabs.get(i).path) : ""; }
    // ——— Podział edytora: dwie grupy kart (0 — lewa, 1 — prawa) ———
    property int focusGroup: 0
    property int g0Uid: 0                       // aktywna karta każdej grupy (uid — indeksy się przesuwają)
    property int g1Uid: 0
    property var pendingPrimary: ({})           // duplikat pliku z drugiej grupy nie otwiera go w serwerze języka
    readonly property bool split: { revision; for (let i = 0; i < tabs.count; ++i) if (tabs.get(i).group === 1) return true; return false; }
    readonly property real splitX: split ? Math.round(pane.width / 2) : pane.width
    function groupActive(g) {
        const i = indexOfUid(g === 0 ? g0Uid : g1Uid);
        if (i >= 0 && tabs.get(i).group === g) return i;
        for (let k = 0; k < tabs.count; ++k) if (tabs.get(k).group === g) return k;
        return -1;
    }
    function anyInGroup(g) { for (let k = 0; k < tabs.count; ++k) if (tabs.get(k).group === g) return true; return false; }
    function indexOfPathInGroup(p, g) {
        for (let i = 0; i < tabs.count; ++i) if (tabs.get(i).path === p && tabs.get(i).group === g) return i;
        return -1;
    }
    // Ctrl+\ — bieżący plik także w drugiej grupie (ta sama treść, zmiany w obu na bieżąco)
    function splitEditor() {
        if (!cur) return;
        const t = tabs.get(current);
        const other = 1 - t.group;
        const existing = indexOfPathInGroup(t.path, other);
        if (existing >= 0) { activate(existing); return; }
        const src = cur;
        const uid = ++uidSeq;
        pendingText[uid] = src.edit.text;
        pendingCursor[uid] = src.edit.cursorPosition;
        pendingPrimary[uid] = false;
        let at = tabs.count;
        for (let k = tabs.count - 1; k >= 0; --k) if (tabs.get(k).group === other) { at = k + 1; break; }
        tabs.insert(at, { uid: uid, path: t.path, preview: false, encoding: t.encoding, eol: t.eol, readOnly: t.readOnly, changedOnDisk: false, group: other });
        revision++;
        const i = indexOfUid(uid), dup = page(i);
        if (src.modified) dup.edit.textDocument.modified = true;
        TextOps.link(dup.edit.textDocument, src.edit.textDocument);
        activate(i);
    }
    function moveToOtherGroup(i) {
        if (i < 0 || i >= tabs.count) return;
        const t = tabs.get(i), other = 1 - t.group;
        const existing = indexOfPathInGroup(t.path, other);
        if (existing >= 0) { const uid = tabs.get(existing).uid; closeTab(i, true); activate(indexOfUid(uid)); return; }
        tabs.setProperty(i, "group", other);
        revision++;
        normalizeGroups();
        activate(i);
    }
    // Pusta lewa grupa — prawa staje się jedyną (jak w VS Code)
    function normalizeGroups() {
        if (tabs.count && !anyInGroup(0)) {
            for (let k = 0; k < tabs.count; ++k) tabs.setProperty(k, "group", 0);
            g0Uid = g1Uid; g1Uid = 0;
            revision++;
        }
        if (!anyInGroup(focusGroup)) focusGroup = 0;
    }
    function focusGroupN(g) {
        const i = groupActive(g);
        if (i >= 0) activate(i);
    }
    // Klik w edytor drugiej grupy — ta grupa staje się aktywna
    function editorFocused(i) {
        if (i < 0 || i >= tabs.count || i === current) return;
        current = i;
        focusGroup = tabs.get(i).group;
        if (focusGroup === 0) g0Uid = tabs.get(i).uid; else g1Uid = tabs.get(i).uid;
        revision++;
    }
    function indexOfPath(p) {
        for (let i = 0; i < tabs.count; ++i) if (tabs.get(i).path === p) return i;
        return -1;
    }
    function indexOfUid(uid) {
        for (let i = 0; i < tabs.count; ++i) if (tabs.get(i).uid === uid) return i;
        return -1;
    }
    function openPaths() { const l = []; for (let i = 0; i < tabs.count; ++i) l.push(tabs.get(i).path); return l; }
    function activate(i) {
        if (i < 0 || i >= tabs.count) return;
        if (prefs.autoSave === "focus" && i !== current && current < tabs.count && page(current) && page(current).modified && !tabs.get(current).readOnly)
            save(current);
        current = i;
        focusGroup = tabs.get(i).group;
        if (focusGroup === 0) g0Uid = tabs.get(i).uid; else g1Uid = tabs.get(i).uid;
        revision++;
        Qt.callLater(() => { if (win.cur) win.cur.focusEditor(); });
        if (findBar.shown) Qt.callLater(findAll);
        diffView.close();
    }
    // Pojedynczy klik w drzewie otwiera kartę podglądu (kursywa), którą zastępuje następny plik — jak w VS Code;
    // edycja albo podwójny klik zostawia kartę na stałe.
    function openFile(p, opts) {
        opts = opts || {};
        p = Project.toPath(p);
        // Najpierw karta w aktywnej grupie, potem w drugiej
        let i = indexOfPathInGroup(p, focusGroup);
        if (i < 0) i = indexOfPath(p);
        if (i < 0) {
            const res = Project.load(p);
            if (!res.ok) { toast(res.error); return; }
            const g = anyInGroup(focusGroup) ? focusGroup : 0;
            let at = tabs.count && tabs.get(current).group === g ? current + 1 : tabs.count;
            if (opts.preview) {
                for (let k = 0; k < tabs.count; ++k)
                    if (tabs.get(k).preview && tabs.get(k).group === g && !page(k).modified) { tabs.remove(k); revision++; at = k; break; }
            }
            const uid = ++uidSeq;
            pendingText[uid] = res.text;
            pendingCursor[uid] = 0;
            tabs.insert(Math.min(at, tabs.count), { uid: uid, path: p, preview: !!opts.preview, encoding: res.encoding, eol: res.eol,
                                                   readOnly: res.readOnly, changedOnDisk: false, group: g });
            revision++;
            i = indexOfUid(uid);
            watchAll();
            Qt.callLater(saveSession);
        } else if (!opts.preview && tabs.get(i).preview) {
            tabs.setProperty(i, "preview", false);
        }
        activate(i);
        if (opts.line !== undefined) {
            const pg = page(i);
            Qt.callLater(() => {
                const a = TextOps.positionOfLine(pg.edit.textDocument, opts.line) + (opts.col || 0);
                pg.reveal(a, a + (opts.length || 0));
            });
        }
        if (Project.tree) {
            const row = Project.tree.reveal(p);
            if (row >= 0) treeList.positionViewAtIndex(row, ListView.Contain);
        }
    }
    function watchAll() { Project.watch(openPaths()); }
    function pin(i) { if (i >= 0 && i < tabs.count && tabs.get(i).preview) tabs.setProperty(i, "preview", false); }

    // ——— Zapisywanie ———
    // skipCleanup — bez porządkowania z ustawień (samozapis, drugi krok po formatowaniu)
    function save(i, then, skipCleanup) {
        if (i < 0 || i >= tabs.count) return;
        const t = tabs.get(i), p = page(i);
        if (!skipCleanup && !t.readOnly) {
            TextOps.cleanupOnSave(p.edit.textDocument, prefs.trimTrailing, prefs.finalNewline);
            if (prefs.formatOnSave && p.lspOn) {
                const seq = p.formatDocument();
                if (seq >= 0) {
                    const f = Object.assign({}, formatSaves);
                    f[seq] = { uid: t.uid, then: then };
                    formatSaves = f;
                    formatTimeout.restart();
                    return;
                }
            }
        }
        lastSave[t.path] = Date.now();
        if (Project.save(t.path, p.edit.text, t.encoding, t.eol)) {
            p.markSaved();
            if (prefs.previewOnSave) preview.reload();
            for (let k = 0; k < tabs.count; ++k) if (k !== i && tabs.get(k).path === t.path) page(k).markSaved();
            Lsp.saved(t.path);
            p.refreshBlame();
            tabs.setProperty(i, "changedOnDisk", false);
            pin(i);
            revision++;
            if (then) then();
        }
    }
    function saveAll() { for (let i = 0; i < tabs.count; ++i) if (page(i).modified) save(i); }
    function dirtyCount() {
        const seen = {};
        let n = 0;
        for (let i = 0; i < tabs.count; ++i) if (page(i) && page(i).modified && !seen[tabs.get(i).path]) { seen[tabs.get(i).path] = true; n++; }
        return n;
    }

    // ——— Zamykanie ———
    property var confirm: null           // { kind: "tab", index, name } albo { kind: "all", count, then }
    function closeTab(i, force) {
        if (i < 0 || i >= tabs.count) return;
        const p = page(i);
        if (!force && p && p.modified) {
            activate(i);
            confirm = { kind: "tab", index: i, name: tabTitle(i) };
            return;
        }
        const g = tabs.get(i).group, uid = tabs.get(i).uid, path = tabs.get(i).path;
        if (force && p && p.modified) Project.backupRemove(path);        // „Nie zapisuj”
        // Duplikat tego pliku w drugiej grupie przejmuje dokument w serwerze języka
        const wasPrimary = p ? p.lspPrimary : false;
        const wasFocused = i === current;
        tabs.remove(i);
        if (wasPrimary) {
            const d = indexOfPath(path);
            if (d >= 0) { page(d).lspPrimary = true; Lsp.open(path, page(d).edit.text); }
        }
        // Następna karta w tej samej grupie
        let next = -1;
        for (let k = i; k < tabs.count && next < 0; ++k) if (tabs.get(k).group === g) next = k;
        for (let k = i - 1; k >= 0 && next < 0; --k) if (tabs.get(k).group === g) next = k;
        if ((g === 0 ? g0Uid : g1Uid) === uid) { if (g === 0) g0Uid = next >= 0 ? tabs.get(next).uid : 0; else g1Uid = next >= 0 ? tabs.get(next).uid : 0; }
        revision++;
        normalizeGroups();
        if (!tabs.count) { current = 0; focusGroup = 0; revision++; watchAll(); Qt.callLater(saveSession); return; }
        if (wasFocused || !anyInGroup(focusGroup)) activate(groupActive(anyInGroup(g) ? g : focusGroup));
        else { current = indexOfUid(focusGroup === 0 ? g0Uid : g1Uid); if (current < 0) current = groupActive(focusGroup); revision++; }
        watchAll();
        Qt.callLater(saveSession);
    }
    function closeAllTabs() { while (tabs.count) { tabs.remove(tabs.count - 1); } revision++; current = 0; focusGroup = 0; g0Uid = g1Uid = 0; watchAll(); }
    // Przed zamknięciem okna albo zmianą folderu — pytanie o niezapisane pliki
    function whenSaved(then) {
        const n = dirtyCount();
        if (n === 0) { then(); return; }
        confirm = { kind: "all", count: n, then: then };
    }
    property bool quitting: false
    onClosing: (close) => {
        if (quitting) return;
        saveSession();
        if (dirtyCount() > 0) {
            close.accepted = false;
            whenSaved(() => { win.quitting = true; win.close(); });
        }
    }

    // ——— Projekt ———
    function openFolder(path) {
        whenSaved(() => {
            saveSession();
            closeAllTabs();
            if (Project.open(path)) restoreSession();
        });
    }
    function closeFolder() {
        whenSaved(() => { saveSession(); closeAllTabs(); terminalShown = false; Project.close(); });
    }
    function restoreSession() {
        // Kopie odczytane przed otwarciem kart — wczytanie pliku ustawia stan „bez zmian” i kasuje jego kopię
        const saved = Project.backups();
        const list = Project.sessionTabs();
        list.forEach(p => openFile(p));
        if (tabs.count) activate(Math.min(Project.sessionCurrent(), tabs.count - 1));
        const l = Project.sessionLayout();
        sidebarView = l.sidebarView || 0;
        terminalShown = !!l.terminal;
        restoreBackups(saved);
    }
    // Program zakończył się bez zapisu (awaria, zanik zasilania) — niezapisana treść wraca do kart
    function restoreBackups(saved) {
        let n = 0;
        for (const b of saved) {
            if (!Project.exists(b.path)) continue;
            openFile(b.path, { preview: false });
            const i = indexOfPath(b.path);
            if (i < 0) continue;
            const e = page(i).edit;
            if (e.text === b.text) { Project.backupRemove(b.path); continue; }
            TextOps.multiEdit(e.textDocument, [{ a: 0, b: e.length }], [b.text], 0);
            n++;
        }
        if (n) toast("Przywrócono niezapisane zmiany: " + n + (n === 1 ? " plik" : " pliki") + " (Ctrl+Z wraca do wersji z dysku)");
    }
    function saveSession() {
        if (!hasProject) return;
        const list = [];
        for (let i = 0; i < tabs.count; ++i) if (!tabs.get(i).preview && list.indexOf(tabs.get(i).path) < 0) list.push(tabs.get(i).path);
        Project.saveSession(list, Math.max(0, list.indexOf(curPath)), terminalShown, sidebarView);
    }
    Timer { interval: 5000; running: win.hasProject; repeat: true; onTriggered: win.saveSession() }
    // Git w tle: co kilka sekund, gdy okno jest aktywne, i po powrocie do okna
    Timer { interval: 4000; running: win.hasProject && win.active; repeat: true; onTriggered: Project.refreshGit() }
    onActiveChanged: {
        if (active && hasProject) Project.refreshGit();
        if (!active && prefs.autoSave === "focus") for (let i = 0; i < tabs.count; ++i) if (page(i) && page(i).modified && !tabs.get(i).readOnly) save(i);
    }
    property string lastHead: ""
    Connections {
        target: Project
        function onGitChanged() {
            // Nowy commit (np. z terminala) — znaczniki przy marginesie liczą się od nowej wersji
            if (Project.head !== win.lastHead) {
                win.lastHead = Project.head;
                for (let i = 0; i < tabs.count; ++i) win.page(i).requestBase();
            }
        }
        function onMessage(text) { win.toast(text); }
        function onRootChanged() { Lsp.setRoot(Project.root); ProjectEnv.root = Project.root; }
        function onFileChanged(path) {
            const i = win.indexOfPath(path);
            if (i < 0 || Date.now() - (win.lastSave[path] || 0) < 2000) return;
            const p = win.page(i);
            if (!Project.exists(path)) { tabs.setProperty(i, "changedOnDisk", true); win.revision++; return; }
            if (!p.modified) {
                const res = Project.load(path);
                if (res.ok) p.load(res.text, p.edit.cursorPosition);
            } else {
                tabs.setProperty(i, "changedOnDisk", true);
                win.revision++;
            }
        }
    }
    // ——— Serwer języka ———
    Connections {
        target: Lsp
        function onDefinitionReady(seq, path, line, col) { win.openFile(path, { line: line, col: col, length: 0 }); }
        function onDefinitionMissing(seq) { win.toast("Nie znaleziono definicji"); }
        function onMessage(text) { win.toast(text); }
    }
    // Zmiana nazwy symbolu w całym projekcie (F2)
    property string renameFrom: ""
    function startRename() {
        if (!cur) return;
        if (!cur.lspOn) { lspHint(); return; }
        const w = cur.symbolAt();
        if (!w.text) { toast("Ustaw kursor na nazwie, którą chcesz zmienić"); return; }
        nameBox.ask("Zmień nazwę „" + w.text + "”", w.text, "We wszystkich plikach projektu (" + cur.serverInfo.name + ")", (name) => {
            if (name === w.text) return;
            win.renameFrom = w.text;
            win.cur.renameSymbol(name);
        });
    }
    function findReferences() {
        if (!cur) return;
        if (!cur.lspOn) { lspHint(); return; }
        refName = cur.symbolAt().text;
        cur.findReferences();
    }
    property string refName: ""
    function formatDocument() {
        if (!cur) return;
        if (cur.formatDocument() === -1) lspHint();
    }
    Connections {
        target: Lsp
        function onRenameReady(seq, files, error) {
            if (error) { win.toast(error); return; }
            win.applyWorkspace(files);
        }
        function onWorkspaceEditReady(files) { if (files.length) win.applyWorkspace(files); }
        function onCodeActionsReady(seq, path, actions) {
            if (seq !== win.quickFixSeq || !win.cur) return;
            if (!actions.length) { win.toast("Brak szybkich poprawek w tym miejscu"); return; }
            const r = win.cur.edit.cursorRectangle;
            const p = win.cur.edit.mapToItem(frame, r.x, r.y + r.height + 4);
            menu.openAt(p.x, p.y, actions.slice(0, 14).map(a => ({ label: a.title.length > 34 ? a.title.slice(0, 33) + "…" : a.title,
                                                                 icon: a.preferred ? "bolt" : "", action: "qa:" + a.index })));
        }
        function onSymbolsReady(seq, path, symbols) {
            if (palette.shown && palette.mode === "symbols") palette.setSymbols(symbols.map(s => Object.assign({}, s, { path: path })));
        }
        function onWorkspaceSymbolsReady(seq, symbols) { if (palette.shown && palette.mode === "workspace") palette.setSymbols(symbols); }
    }
    property int quickFixSeq: -1
    function quickFix() {
        if (!cur) return;
        if (!cur.lspOn) { lspHint(); return; }
        quickFixSeq = cur.requestCodeActions();
    }
    function symbolQuery(mode, q) {
        if (mode === "symbols") {
            if (!cur || !cur.lspOn || Lsp.documentSymbols(curPath) < 0) palette.setSymbols([], "Brak serwera języka dla tego pliku");
        } else if (q.trim().length >= 2) {
            if (Lsp.workspaceSymbols(q.trim()) < 0) palette.setSymbols([], "Żaden działający serwer języka nie szuka symboli w całym projekcie");
        } else {
            palette.setSymbols([]);
        }
    }
    // Zmiany w wielu plikach (zmiana nazwy, szybka poprawka) idą do kart — pliki spoza kart otwierają się w tle
    function applyWorkspace(files) {
        const back = win.curPath;
        let total = 0, others = 0;
        for (const f of files) {
            let i = win.indexOfPath(f.path);
            if (i < 0) { win.openFile(f.path); i = win.indexOfPath(f.path); }
            if (i < 0) continue;
            total += win.page(i).applyEdits(f.edits);
            if (f.path !== back) { win.pin(i); others++; }
        }
        if (back) win.activate(win.indexOfPath(back));
        win.revision++;
        win.toast("Zmieniono " + total + (total === 1 ? " miejsce" : total % 10 >= 2 && total % 10 <= 4 && (total % 100 < 10 || total % 100 >= 20) ? " miejsca" : " miejsc")
                  + (files.length > 1 ? " w " + files.length + " plikach" : "") + (others ? " — zapisz wszystko: Ctrl+Alt+S" : ""));
    }
    Connections {
        target: Lsp
        function onReferencesReady(seq, groups, total) {
            if (!total) { win.toast("Brak odwołań"); return; }
            terminalPanel.refGroups = groups;
            terminalPanel.refTitle = total + (total === 1 ? " odwołanie" : total % 10 >= 2 && total % 10 <= 4 && (total % 100 < 10 || total % 100 >= 20) ? " odwołania" : " odwołań")
                                     + (win.refName ? " do „" + win.refName + "”" : "") + " w " + groups.length + (groups.length === 1 ? " pliku" : " plikach");
            win.terminalShown = true;
            terminalPanel.tab = 2;
        }
        function onFormatReady(seq, path, edits) {
            // Zapis z formatowaniem: zmiany po cichu, potem właściwy zapis
            const pend = win.formatSaves[seq];
            if (pend) {
                const f = Object.assign({}, win.formatSaves);
                delete f[seq];
                win.formatSaves = f;
                const k = win.indexOfUid(pend.uid);
                if (k < 0) return;
                if (edits.length) win.page(k).applyEdits(edits);
                win.save(k, pend.then, true);
                return;
            }
            const i = win.indexOfPath(path);
            if (i < 0) return;
            if (!edits.length) { win.toast("Plik jest już sformatowany"); return; }
            win.page(i).applyEdits(edits);
            win.toast("Sformatowano");
        }
    }
    function goToDefinition() {
        if (!cur) return;
        definitionFeedback(cur.goToDefinition());
    }
    function definitionFeedback(seq) { if (seq === -1) lspHint(); }
    // Bez serwera języka — co doinstalować (polecenie trafia do schowka)
    function lspHint() {
        const s = cur ? Lsp.serverFor(curPath) : {};
        if (!s.id) { toast("Dla tego rodzaju pliku nie ma serwera języka"); return; }
        if (s.failed) { toast("Serwer języka " + s.name + " przestał działać — otwórz folder ponownie"); return; }
        if (s.available) { toast("Serwer języka " + s.name + " się uruchamia…"); return; }
        Project.copyText(s.package);
        toast("Brak serwera języka " + s.name + " — polecenie w schowku: " + s.package);
    }
    // Odrzucenie zmian: otwarte karty bez własnych zmian wczytują się na nowo (obserwacja pliku), reszta zostaje
    function discardPaths(paths) {
        Project.discard(paths);
        diffView.close();
    }
    Connections {
        target: Project
        function onGitDone(op, ok, message) {
            if (message && (!ok || ["commit", "push", "pull", "checkout", "branch", "merge", "deleteBranch", "stash"].indexOf(op) >= 0)) win.toast(message);
        }
    }
    // Gałęzie: przełączenie podmienia pliki na dysku — najpierw pytanie o niezapisane karty
    function branchAction(mode, name, remote, isNew) {
        if (mode === "merge") { whenSaved(() => Project.mergeBranch(name)); return; }
        if (mode === "delete") { Project.deleteBranch(name); return; }
        whenSaved(() => { if (isNew) Project.createBranch(name); else Project.checkout(name, remote); });
    }
    // Zamiana w projekcie: otwarte karty — w edytorze (do cofnięcia i zapisania), reszta plików — od razu na dysku
    function replaceInPaths(paths) {
        const q = searchView.query, r = searchView.replacement;
        const mc = searchView.matchCase, ww = searchView.wholeWord, re = searchView.regex;
        let total = 0, files = 0, inTabs = 0;
        for (const p of paths) {
            const i = indexOfPath(p);
            const n = i >= 0 ? TextOps.replaceAll(page(i).edit.textDocument, q, mc, ww, re, r) : Project.replaceInFile(p, q, mc, ww, re, r);
            if (n) { total += n; files++; if (i >= 0) inTabs++; }
        }
        revision++;
        toast(total ? "Zamieniono " + total + (files > 1 ? " razy w " + files + " plikach" : total === 1 ? " raz" : " razy")
                      + (inTabs ? " — otwarte karty zapisz (Ctrl+Alt+S)" : "") : "Nic nie zamieniono");
        searchView.run();
    }
    function replaceMatch(path, line, col) {
        openFile(path, { preview: true, line: line, col: col, length: 0 });
        const i = indexOfPath(path);
        if (i < 0) return;
        if (!TextOps.replaceAt(page(i).edit.textDocument, line, col, searchView.query, searchView.matchCase, searchView.wholeWord, searchView.regex, searchView.replacement))
            toast("To miejsce już się zmieniło — szukam ponownie");
        pin(i);
        searchView.run();
    }
    // ——— Zadania (Ctrl+Shift+B) ———
    function recentTasksFor() {
        try { return (JSON.parse(prefs.recentTasks)[Project.root] || []); } catch (e) { return []; }
    }
    function taskList() {
        const recent = recentTasksFor().map(t => Object.assign({}, t, { recent: true }));
        const found = Tasks.detect(Project.root).filter(t => !recent.some(r => r.command === t.command));
        return recent.concat(found);
    }
    function showTasks() { if (hasProject) palette.openTasks(taskList()); }
    function runTask(t) {
        saveAll();
        Tasks.run(t.label, t.command, t.cwd || Project.root, taskEnv(t.cwd || Project.root));
        // Ostatnie 6 poleceń na projekt — na górze listy
        let all = {};
        try { all = JSON.parse(prefs.recentTasks); } catch (e) {}
        const list = (all[Project.root] || []).filter(r => r.command !== t.command);
        list.unshift({ label: t.label, command: t.command, group: t.group === "custom" ? "custom" : t.group });
        all[Project.root] = list.slice(0, 6);
        prefs.recentTasks = JSON.stringify(all);
        terminalShown = true;
        terminalPanel.tab = 3;
    }
    // ▶ Uruchom (Ctrl+F5): serwer deweloperski z każdego projektu naraz (np. frontend i backend), każdy z własnymi logami
    function runApp() {
        if (!hasProject) return;
        const targets = Tasks.runTargets(Project.root);
        if (!targets.length) { showTasks(); return; }
        saveAll();
        previewScore = -1;
        for (const t of targets) Tasks.run(t.label, t.command, t.cwd || Project.root, win.taskEnv(t.cwd || Project.root));
        terminalShown = true;
        terminalPanel.tab = 3;
    }
    function showRunMenu() {
        const p = runBtn.mapToItem(frame, 0, runBtn.height + 6);
        const targets = Tasks.runTargets(Project.root);
        const items = [];
        if (targets.length > 1) items.push({ label: "Uruchom wszystko (" + targets.length + ")", icon: "play", shortcut: "Ctrl+F5", action: "run:all" });
        targets.forEach((t, i) => items.push({ label: t.label, icon: "play", action: "run:" + i, shortcut: targets.length === 1 ? "Ctrl+F5" : "" }));
        if (Tasks.runningCount) items.push({ separator: true }, { label: "Zatrzymaj wszystko", icon: "stop", action: "run:stop", danger: true });
        items.push({ separator: true }, { label: "Inne zadania…", icon: "apps", action: "tasks" }, { label: "Podgląd strony", icon: "globe", action: "preview" });
        runMenuTargets = targets;
        menu.openAt(Math.min(p.x, frame.width - 280), p.y, items);
    }
    property var runMenuTargets: []
    property int previewScore: -1
    // Zmienne środowiska dla zadania (sekrety projektu — punkt „Sekrety”)
    function taskEnv(cwd) { return Secrets.names.length ? { __secrets: true } : {}; }
    Connections {
        target: Tasks
        // Kilka serwerów — w podglądzie strona (frontend), nie API; lepszy adres zastępuje gorszy
        function onUrlDetected(id, label, url) {
            const score = /back|api|server|uvicorn|flask|django|baza|db/i.test(label) ? 0 : /front|web|client|ui|site|vite|next|dev|start/i.test(label) ? 2 : 1;
            if (prefs.previewAuto && (!preview.shown || score > win.previewScore || !preview.url)) {
                win.previewScore = score;
                preview.open(url);
            }
            win.toast("„" + label + "” działa: " + url);
        }
    }
    // Ctrl+Shift+B: ostatnio uruchomione zadanie budowania od razu, inaczej lista
    function buildTask() {
        if (!hasProject) return;
        const r = recentTasksFor().find(t => t.group === "build");
        const found = Tasks.detect(Project.root).filter(t => t.group === "build");
        if (r) runTask(r);
        else if (found.length === 1) runTask(found[0]);
        else showTasks();
    }
    Connections {
        target: Tasks
        function onFinished(title, code) {
            if (win.terminalShown && terminalPanel.tab === 3 && win.active) return;
            win.toast(code === 0 ? "„" + title + "” — gotowe" : code === -2 ? "„" + title + "” — przerwano"
                     : "„" + title + "” — błąd" + (Tasks.errorCount ? " (" + Tasks.errorCount + ")" : ""));
        }
    }
    // ——— Debugowanie (F5) ———
    // Plik .py — debugpy dla bieżącego pliku; inaczej program z projektu (zapamiętany albo najnowszy plik ELF)
    function startDebug(ask) {
        if (Debugger.state) { Debugger.resume(); return; }
        if (!hasProject) return;
        const py = curPath.endsWith(".py");
        const ad = Debugger.adapterFor(py ? "python" : "native");
        if (!ad.available) { Project.copyText(ad.install); toast("Brak debugera " + ad.name + " — polecenie w schowku: " + ad.install); return; }
        if (py) { saveAll(); launchDebug("python", curPath, ""); return; }
        let all = {};
        try { all = JSON.parse(prefs.debugPrograms); } catch (e) {}
        const saved = all[Project.root];
        if (saved && !ask && Project.exists(Project.root + "/" + saved.program)) { launchDebug("native", Project.root + "/" + saved.program, saved.args); return; }
        const guess = saved ? saved.program + (saved.args ? " " + saved.args : "") : Project.relative(Debugger.guessProgram(Project.root));
        nameBox.ask("Program do debugowania", guess, "Ścieżka w projekcie, po spacji argumenty. Zbuduj go z -g (informacje dla debugera).", (text) => {
            const parts = text.trim().split(/\s+/);
            if (!parts[0]) return;
            const prog = parts[0], args = parts.slice(1).join(" ");
            all[Project.root] = { program: prog, args: args };
            prefs.debugPrograms = JSON.stringify(all);
            win.launchDebug("native", prog.startsWith("/") ? prog : Project.root + "/" + prog, args);
        });
    }
    function launchDebug(kind, program, args) {
        if (!Debugger.start(kind, program, args, Project.root)) return;
        terminalShown = true;
        terminalPanel.tab = 4;
    }
    function toggleBreakpointHere() { if (cur) Debugger.toggleBreakpoint(curPath, cur.lineCol.y); }
    Connections {
        target: Debugger
        // Zatrzymanie — plik i wiersz na wierzchu
        function onStopChanged() { if (Debugger.stopPath && Debugger.stopLine >= 0) win.openFile(Debugger.stopPath, { line: Debugger.stopLine, col: 0, length: 0 }); }
        function onMessage(text) { win.toast(text); }
        function onEnded(code) { win.toast(code >= 0 ? "Program zakończył się (kod " + code + ")" : "Debugowanie zakończone"); }
    }
    // ——— Historia pliku ———
    function showHistory(path) {
        if (!Project.isGit) { toast("Historia jest dostępna w repozytorium gita"); return; }
        if (path && path !== curPath) openFile(path);
        historyView.commitData = null;
        prefs.sidebar = true;
        sidebarView = 3;
    }
    function showCommit(hash) {
        historyView.openCommit(hash);
        prefs.sidebar = true;
        sidebarView = 3;
    }
    // Starsza wersja wchodzi do edytora jak zwykła zmiana — da się ją przejrzeć, cofnąć (Ctrl+Z) albo zapisać
    function restoreVersion(path, hash, rel) {
        const f = Project.fileAt(hash, rel);
        if (!f.ok) { toast("Nie udało się wczytać tej wersji"); return; }
        openFile(path);
        const i = indexOfPath(path);
        if (i < 0) return;
        const e = page(i).edit;
        const pos = e.cursorPosition;
        TextOps.multiEdit(e.textDocument, [{ a: 0, b: e.length }], [f.text], 0);
        e.cursorPosition = Math.min(pos, e.length);
        pin(i);
        toast("Wersja z " + hash.slice(0, 7) + " w edytorze — zapisz (Ctrl+S) albo cofnij (Ctrl+Z)");
    }
    // ——— Środowisko projektu (kontener) ———
    property string envState: ProjectEnv.state
    onEnvStateChanged: Lsp.restartServers()
    function createContainer() {
        if (!ProjectEnv.toolAvailable()) { toast("W systemie nie ma toolbox ani distrobox"); return; }
        nameBox.ask("Kontener dla „" + Project.name + "”", ProjectEnv.suggestPackages().join(" "),
                    "Pakiety Fedory do zainstalowania (spacja między nimi). Wszystko trafi do kontenera — w systemie nic nie przybędzie.", (text) => {
            ProjectEnv.useContainer(true);
            const pk = text.trim().split(/\s+/).filter(x => !!x);
            win.envTask("Kontener: przygotowanie", ProjectEnv.createCommand(pk));
        });
    }
    function envTask(label, command) {
        Tasks.run(label, command, Project.root, { __host: true });
        terminalShown = true;
        terminalPanel.tab = 3;
    }
    function showEnvMenu() {
        const p = envBtn.mapToItem(frame, 0, 0);
        const st = ProjectEnv.state;
        const items = st === "ready" ? [
            { label: "Terminal w kontenerze", icon: "terminal", action: "env:terminal" },
            { label: "Zainstaluj pakiety…", icon: "download", action: "env:install" },
            { separator: true },
            { label: "Pracuj w systemie (kontener zostaje)", icon: "monitor", action: "env:off" },
            { label: "Usuń kontener…", icon: "trash", action: "env:remove", danger: true }
        ] : st === "none" ? [
            { label: "Załóż kontener " + ProjectEnv.container, icon: "plus", action: "env:create" },
            { label: "Pracuj w systemie", icon: "monitor", action: "env:off" }
        ] : [
            { label: "Utwórz kontener projektu…", icon: "plus", action: "env:create", enabled: ProjectEnv.toolAvailable() },
            { label: ProjectEnv.toolAvailable() ? "Node, Python, bazy danych — w kontenerze, nie w systemie" : "Brak toolbox — zainstaluj: rpm-ostree install toolbox",
              icon: "info", action: "", enabled: false }
        ];
        menu.openAt(Math.max(8, p.x - 160), p.y - items.length * 34 - 18, items);
    }
    Connections {
        target: Tasks
        function onFinished(title, code) {
            if (!title.startsWith("Kontener")) return;
            ProjectEnv.refresh();
            if (code === 0) win.toast(title === "Kontener: usuwanie" ? "Kontener usunięty" : "Kontener gotowy — terminal, zadania i serwery języków działają w nim");
        }
    }
    // ——— Nowa aplikacja z szablonu ———
    // Folder → kontener z pakietami → instalacja zależności (każda jako zadanie z logami) → README
    property var pendingSetup: []
    function startFromTemplate(r, container) {
        openFolder(r.path);
        ProjectEnv.root = r.path;
        pendingSetup = r.setup;
        Qt.callLater(() => win.openFile(r.path + "/README.md", { preview: false }));
        if (container) {
            ProjectEnv.useContainer(true);
            envTask("Kontener: przygotowanie", ProjectEnv.createCommand(r.packages));
        } else {
            runPendingSetup();
        }
        toast("Aplikacja „" + Project.name + "” utworzona — instaluję zależności");
    }
    function runPendingSetup() {
        const steps = pendingSetup;
        pendingSetup = [];
        for (const s of steps) Tasks.run(s.label, s.command, s.cwd, {});
        if (steps.length) { terminalShown = true; terminalPanel.tab = 3; setupLeft = steps.length; }
    }
    property int setupLeft: 0
    Connections {
        target: Tasks
        function onFinished(title, code) {
            if (title === "Kontener: przygotowanie" && code === 0 && win.pendingSetup.length) Qt.callLater(win.runPendingSetup);
            else if (win.setupLeft > 0 && (title.indexOf("install") >= 0 || title.indexOf("zależności") >= 0)) {
                if (--win.setupLeft === 0) win.toast(code === 0 ? "Gotowe — ▶ Uruchom (Ctrl+F5) startuje aplikację" : "Instalacja zależności nie powiodła się — szczegóły w karcie Zadania");
            }
        }
    }
    // ——— Agent ———
    // Kontekst dla modelu: projekt, otwarty plik, zaznaczenie, problemy, git, środowisko — bez .env i wartości sekretów
    function agentContext(o) {
        const out = [];
        out.push("Projekt w Aster Code: " + Project.name + " (" + Project.root + ")");
        out.push("Środowisko poleceń: " + (ProjectEnv.state === "ready" ? "kontener " + ProjectEnv.container + " (" + ProjectEnv.tool + ") — pakiety instaluj w nim: sudo dnf install -y …" : "system (/usr tylko do odczytu — bez sudo dnf; kontener projektu można założyć w Aster Code)"));
        if (Project.isGit) out.push("Git: gałąź " + Project.branch + (Project.changes.length ? ", zmienione: " + Project.changes.slice(0, 30).map(c => c.rel + " (" + c.status + ")").join(", ") : ", bez zmian"));
        const open = []; for (let i = 0; i < tabs.count; ++i) if (open.indexOf(Project.relative(tabs.get(i).path)) < 0) open.push(Project.relative(tabs.get(i).path));
        if (open.length) out.push("Otwarte karty: " + open.join(", "));
        out.push("Pliki projektu (część): " + Project.quickOpen("", 150).map(f => f.rel).filter(r => !Secrets.secretFile(r)).join(", "));
        if (cur && curPath) {
            const rel = Project.relative(curPath);
            out.push("\nOtwarty plik: " + rel + " (" + (cur.language || "tekst") + "), kursor w wierszu " + (cur.lineCol.y + 1));
            if (Secrets.secretFile(curPath)) {
                out.push("(To plik z sekretami — jego treść nie jest dołączona.)");
            } else {
                const sel = cur.edit.selectedText.replace(/\u2029/g, "\n");
                if (o.selection && sel) {
                    const a = TextOps.lineColumn(cur.edit.textDocument, cur.edit.selectionStart).y + 1;
                    out.push("Zaznaczenie (wiersze " + a + "–" + (a + sel.split("\n").length - 1) + "):\n```\n" + sel + "\n```");
                }
                if (o.file) {
                    const t = cur.edit.text;
                    if (t.length <= 60000) out.push("Treść " + rel + ":\n```\n" + t + "\n```");
                    else {
                        const ls = t.split("\n"), c = cur.lineCol.y;
                        out.push("Fragment " + rel + " (wiersze " + Math.max(1, c - 150) + "–" + Math.min(ls.length, c + 150) + " z " + ls.length + "):\n```\n" + ls.slice(Math.max(0, c - 150), c + 150).join("\n") + "\n```");
                    }
                }
            }
        }
        if (o.problems) {
            const probs = [];
            for (const f of Lsp.problems.concat(Tasks.problems))
                for (const d of f.items) if (probs.length < 40 && d.severity <= 2) probs.push(Project.relative(f.path) + ":" + (d.line + 1) + ":" + (d.col + 1) + " " + (d.severity === 1 ? "błąd" : "ostrzeżenie") + ": " + d.message + (d.source ? " [" + d.source + "]" : ""));
            if (probs.length) out.push("\nProblemy (serwery języków i kompilator):\n" + probs.join("\n"));
        }
        out.push("\nZmiany w plikach proponuj wyłącznie blokami — bez sed, cat > ani echo do plików. Użytkownik przejrzy różnice i zaakceptuje je plik po pliku:\n"
                 + "```aster-edit ścieżka/względem/projektu\n<<<<<<< SZUKAJ\n(dokładnie skopiowany fragment obecnej treści, kilka wierszy)\n=======\n(nowa treść tego fragmentu)\n>>>>>>> ZAMIEŃ\n```\n"
                 + "W jednym bloku może być kilka par SZUKAJ/ZAMIEŃ. Nowy plik albo cała nowa treść: ```aster-file ścieżka (nowa linia, cała treść)```. "
                 + "Polecenia (testy, budowanie, instalacja pakietów) — jedno w bloku ```bash; działają w folderze projektu. Pisz po polsku, zwięźle.");
        const text = out.join("\n");
        return Secrets.names.length ? Secrets.redact(text) : text;
    }
    function agentFileText(abs) {
        const i = indexOfPath(abs);
        return i >= 0 && page(i) ? page(i).edit.text : Agent.readFile(abs);
    }
    // Zaakceptowana zmiana: plik w edytorze (do cofnięcia Ctrl+Z) i zapis — testy agenta widzą nową treść
    function applyAgentEdit(path, text) {
        if (!Project.exists(path)) {
            Project.save(path, text, "UTF-8", "LF");
            Project.refreshFiles();
        }
        openFile(path, { preview: false });
        const i = indexOfPath(path);
        if (i < 0) return;
        const e = page(i).edit;
        if (e.text !== text) {
            const pos = e.cursorPosition;
            TextOps.multiEdit(e.textDocument, [{ a: 0, b: e.length }], [text], 0);
            e.cursorPosition = Math.min(pos, e.length);
        }
        save(i, null, true);
    }
    function askAgent(prompt) { agentPanel.ask(prompt); }
    // ——— Wdrożenie ———
    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function deployCommand(c) {
        const build = c.build ? "(cd " + shq(c.buildDir || ".") + " && " + c.build + ") && " : "";
        const send = c.send || ".";
        if (c.target === "ssh") {
            // Ścieżka bez ~/ — rsync i tak liczy ją od katalogu domowego na serwerze
            const remote = String(c.path || "aplikacja").replace(/^~\//, "").replace(/\/$/, "");
            const src = send === "." ? "./" : send.replace(/\/?$/, "/");
            return build + "rsync -az --delete --mkpath --exclude .git --exclude node_modules --exclude .venv --exclude .env --exclude '.env.*' --exclude .aster "
                 + "-e 'ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new' " + shq(src) + " " + shq(c.host + ":" + remote + "/")
                 + (c.post ? " && ssh -o BatchMode=yes " + shq(c.host) + " " + shq("cd " + remote + " && " + c.post) : "")
                 + " && echo " + shq("Wdrożono: " + c.host + ":" + remote);
        }
        if (c.target === "pages") return build + "npx --yes gh-pages -d " + shq(send) + " -t true && echo 'Wdrożono na gałąź gh-pages'";
        if (c.target === "netlify") return build + "npx --yes netlify-cli deploy --prod --dir " + shq(send) + (c.project ? " --site " + shq(c.project) : "");
        if (c.target === "vercel") return "cd " + shq(c.buildDir || ".") + " && npx --yes vercel deploy --prod --yes --token \"$VERCEL_TOKEN\"";
        if (c.target === "cloudflare") return build + "npx --yes wrangler pages deploy " + shq(send) + " --project-name " + shq(c.project || "strona");
        return "";
    }
    function runDeploy(c) {
        const names = { ssh: "serwer", pages: "GitHub Pages", netlify: "Netlify", vercel: "Vercel", cloudflare: "Cloudflare Pages" };
        saveAll();
        Tasks.run("Wdrożenie: " + (names[c.target] || c.target), deployCommand(c), Project.root, { __secrets: Secrets.names.length > 0, __github: c.target === "pages" });
        terminalShown = true;
        terminalPanel.tab = 3;
    }
    // ⇪ Wdróż: zapisane ustawienia — od razu, inaczej ekran wdrożenia
    function quickDeploy() {
        let c = null;
        try { c = JSON.parse(Agent.readFile(Project.root + "/.aster/wdrozenie.json") || "null"); } catch (e) {}
        if (c && c.target && (c.target !== "ssh" || c.host)) runDeploy(c);
        else deployView.open();
    }
    property string lastDeployUrl: ""
    Connections {
        target: Tasks
        function onFinished(title, code) {
            if (!title.startsWith("Wdrożenie")) return;
            const m = Tasks.lines.join("\n").match(/https:\/\/[^\s'"]+\.(?:netlify\.app|vercel\.app|pages\.dev|github\.io)[^\s'"]*/g);
            win.lastDeployUrl = m ? m[m.length - 1] : "";
            win.toast(code === 0 ? "Wdrożono" + (win.lastDeployUrl ? ": " + win.lastDeployUrl : "") : "Wdrożenie nie powiodło się — szczegóły w karcie Zadania");
        }
    }
    Connections {
        target: GitHub
        function onMessage(text) { win.toast(text); }
        function onRepoCreated(url) { win.toast("Repozytorium na GitHubie: " + url); Project.refreshGit(); }
    }
    function showProblems() {
        if (!hasProject) return;
        if (terminalShown && terminalPanel.tab === 1) { terminalShown = false; return; }
        terminalShown = true;
        terminalPanel.tab = 1;
    }
    function showEditorMenu(item, x, y) {
        const p = item.mapToItem(frame, x, y);
        const e = cur.edit;
        menu.openAt(p.x, p.y, [
            { label: "Przejdź do definicji", icon: "arrow", shortcut: "F12", action: "definition", enabled: cur.lspOn },
            { label: "Zapytaj agenta o zaznaczenie", icon: "sparkles", action: "agent:selection", enabled: e.selectedText !== "" },
            { label: "Szybka poprawka", icon: "bolt", shortcut: "Ctrl+.", action: "quickfix", enabled: cur.lspOn },
            { label: "Znajdź odwołania", icon: "search", shortcut: "Shift+F12", action: "references", enabled: cur.lspOn },
            { label: "Zmień nazwę", icon: "pencil", shortcut: "F2", action: "rename", enabled: cur.lspOn },
            { label: "Podpowiedzi", icon: "sparkle", shortcut: "Ctrl+Spacja", action: "complete", enabled: cur.lspOn },
            { label: "Formatuj dokument", icon: "textSize", shortcut: "Shift+Alt+F", action: "format", enabled: cur.lspOn },
            { separator: true },
            { label: "Wytnij", icon: "scissors", shortcut: "Ctrl+X", action: "cut", enabled: e.selectedText !== "" },
            { label: "Kopiuj", icon: "copy", shortcut: "Ctrl+C", action: "copy", enabled: e.selectedText !== "" },
            { label: "Wklej", icon: "paste", shortcut: "Ctrl+V", action: "paste", enabled: e.canPaste },
            { separator: true },
            { label: "Przełącz komentarz", icon: "code", shortcut: "Ctrl+/", action: "comment" },
            { label: "Zaznacz wszystko", icon: "check", shortcut: "Ctrl+A", action: "selectAll" }
        ]);
    }

    function reloadCurrent() {
        const res = Project.load(curPath);
        if (!res.ok) { toast(res.error); return; }
        cur.load(res.text, cur.edit.cursorPosition);
        tabs.setProperty(current, "changedOnDisk", false);
        revision++;
    }

    Component.onCompleted: {
        effectsTimer.restart();
        const folder = Project.pendingFolder || "";
        if (folder && Project.open(folder)) {
            restoreSession();
            Project.pendingFiles.forEach(f => win.openFile(f));
        }
    }

    // ——— Pliki: nowy, zmiana nazwy, kosz ———
    function targetDir(path) {
        if (!path) return curPath ? Project.folder(curPath) : Project.root;
        return Project.isDir(path) ? path : Project.folder(path);
    }
    function newFile(path) {
        const dir = targetDir(path);
        nameBox.ask("Nowy plik w „" + Project.relative(dir) + "”", "", "Nazwa może zawierać foldery, np. src/main.cpp", (name) => {
            const p = Project.createFile(dir, name);
            if (p) win.openFile(p);
        });
    }
    function newFolder(path) {
        const dir = targetDir(path);
        nameBox.ask("Nowy folder w „" + Project.relative(dir) + "”", "", "", (name) => Project.createFolder(dir, name));
    }
    function renamePath(path) {
        nameBox.ask("Nowa nazwa", Project.fileName(path), Project.relative(path), (name) => {
            const np = Project.rename(path, name);
            if (!np || np === path) return;
            // Otwarte karty idą za nową nazwą (także pliki w przemianowanym folderze)
            for (let i = 0; i < tabs.count; ++i) {
                const tp = tabs.get(i).path;
                if (tp === path || tp.startsWith(path + "/")) { tabs.setProperty(i, "path", np + tp.slice(path.length)); win.page(i).requestBase(); }
            }
            win.revision++;
            win.watchAll();
        }, !Project.isDir(path));
    }
    function trashPath(path) {
        const name = Project.fileName(path);
        if (!Project.trash(path)) return;
        for (let i = tabs.count - 1; i >= 0; --i) {
            const tp = tabs.get(i).path;
            if (tp === path || tp.startsWith(path + "/")) closeTab(i, true);
        }
        toast("Przeniesiono do Kosza: " + name);
    }

    function toast(text) { toastBox.text = text; toastBox.shown = true; toastTimer.restart(); }
    function zoom(d) {
        prefs.fontSize = d === 0 ? 13.5 : Math.max(9, Math.min(32, prefs.fontSize + d));
        toast("Rozmiar tekstu: " + Math.round(prefs.fontSize / 13.5 * 100) + "%");
    }

    FolderDialog {
        id: folderDialog
        title: "Otwórz folder"
        onAccepted: win.openFolder(String(selectedFolder))
    }

    // ——— Szukaj / zamień w pliku ———
    property var matches: []
    property int matchIndex: -1
    property bool matchCase: false
    function findAll() {
        const q = findField.text;
        const out = [];
        if (q && cur) {
            const text = matchCase ? cur.edit.text : cur.edit.text.toLowerCase();
            const needle = matchCase ? q : q.toLowerCase();
            let i = text.indexOf(needle);
            while (i >= 0 && out.length < 20000) { out.push(i); i = text.indexOf(needle, i + Math.max(1, needle.length)); }
        }
        matches = out;
        matchIndex = -1;
        if (cur) { cur.matches = out; cur.matchLength = q.length; cur.currentMatch = -1; }
        if (!cur || !out.length) return;
        const c = cur.edit.selectionStart;
        let k = out.findIndex(p => p >= c);
        if (k < 0) k = 0;
        select(k);
    }
    function select(k) {
        if (!matches.length || !cur) return;
        matchIndex = (k + matches.length) % matches.length;
        cur.currentMatch = matchIndex;
        cur.reveal(matches[matchIndex], matches[matchIndex] + findField.text.length);
    }
    function replaceOne() {
        if (!cur || matchIndex < 0) return;
        const e = cur.edit, start = matches[matchIndex];
        e.remove(start, start + findField.text.length);
        e.insert(start, replaceField.text);
        e.cursorPosition = start + replaceField.text.length;
        findAll();
    }
    function replaceAll() {
        if (!cur || !matches.length) return;
        const n = matches.length, e = cur.edit;
        for (let k = matches.length - 1; k >= 0; --k) {
            e.remove(matches[k], matches[k] + findField.text.length);
            e.insert(matches[k], replaceField.text);
        }
        findAll();
        toast("Zamieniono " + Project.number(n) + (n === 1 ? " raz" : " razy"));
    }
    function openFind(replace) {
        if (!cur) return;
        findBar.shown = true;
        findBar.replace = replace;
        if (cur.edit.selectedText && cur.edit.selectedText.indexOf(" ") < 0) findField.text = cur.edit.selectedText;
        findField.forceActiveFocus();
        findField.selectAll();
        findAll();
    }
    function closeFind() {
        findBar.shown = false;
        if (cur) { cur.matches = []; cur.focusEditor(); }
    }

    // ——— Widoki ———
    property int sidebarView: 0          // 0 pliki, 1 szukaj, 2 zmiany, 3 historia
    property bool terminalShown: false
    property bool terminalMax: false
    function showView(v) {
        if (prefs.sidebar && sidebarView === v && v === 0) { prefs.sidebar = false; return; }
        prefs.sidebar = true;
        sidebarView = v;
        if (v === 1) Qt.callLater(() => searchView.focusField(win.cur && win.cur.edit.selectedText && win.cur.edit.selectedText.indexOf(" ") < 0 ? win.cur.edit.selectedText : ""));
    }
    function toggleTerminal() {
        if (!hasProject) return;
        // Ctrl+` z edytora: pokaż i przejdź do terminala; z terminala — schowaj i wróć do edytora
        if (terminalShown && terminalPanel.tab === 0 && terminalPanel.term && terminalPanel.term.activeFocus) { terminalShown = false; if (cur) cur.focusEditor(); return; }
        terminalShown = true;
        terminalPanel.tab = 0;
        Qt.callLater(terminalPanel.focusTerminal);
    }

    // ——— Polecenia (paleta i menu) ———
    readonly property var commands: [
        { label: "Otwórz folder…", shortcut: "Ctrl+O", action: "openFolder", icon: "folder" },
        { label: "Nowy plik", shortcut: "Ctrl+N", action: "newFile", icon: "filePlus" },
        { label: "Nowy folder", shortcut: "", action: "newFolder", icon: "folderPlus" },
        { label: "Zapisz", shortcut: "Ctrl+S", action: "save", icon: "download" },
        { label: "Zapisz wszystko", shortcut: "Ctrl+Alt+S", action: "saveAll", icon: "copy" },
        { label: "Zamknij kartę", shortcut: "Ctrl+W", action: "closeTab", icon: "close" },
        { label: "Zamknij wszystkie karty", shortcut: "", action: "closeAll", icon: "close" },
        { label: "Szybkie otwieranie pliku", shortcut: "Ctrl+P", action: "quickOpen", icon: "search" },
        { label: "Przejdź do wiersza", shortcut: "Ctrl+G", action: "goto", icon: "arrow" },
        { label: "Znajdź", shortcut: "Ctrl+F", action: "find", icon: "search" },
        { label: "Zamień", shortcut: "Ctrl+H", action: "replace", icon: "pencil" },
        { label: "Szukaj w projekcie", shortcut: "Ctrl+Shift+F", action: "searchProject", icon: "search" },
        { label: "Przejdź do definicji", shortcut: "F12", action: "definition", icon: "arrow" },
        { label: "Znajdź odwołania", shortcut: "Shift+F12", action: "references", icon: "search" },
        { label: "Szybka poprawka", shortcut: "Ctrl+.", action: "quickfix", icon: "bolt" },
        { label: "Symbole w pliku", shortcut: "Ctrl+Shift+O", action: "symbols", icon: "list" },
        { label: "Symbole w projekcie", shortcut: "Ctrl+T", action: "workspaceSymbols", icon: "list" },
        { label: "Zmień nazwę symbolu", shortcut: "F2", action: "rename", icon: "pencil" },
        { label: "Formatuj dokument", shortcut: "Shift+Alt+F", action: "format", icon: "textSize" },
        { label: "Problemy", shortcut: "Ctrl+Shift+M", action: "problems", icon: "alertCircle" },
        { label: "Przełącz komentarz", shortcut: "Ctrl+/", action: "comment", icon: "code" },
        { label: "Duplikuj wiersz", shortcut: "Shift+Alt+↓", action: "duplicate", icon: "copy" },
        { label: "Podziel edytor", shortcut: "Ctrl+\\", action: "split", icon: "sidebar" },
        { label: "Ustawienia", shortcut: "Ctrl+,", action: "settings", icon: "gear" },
        { label: "Uruchom zadanie…", shortcut: "", action: "tasks", icon: "play" },
        { label: "Nowa aplikacja…", shortcut: "", action: "newApp", icon: "sparkle" },
        { label: "Agent", shortcut: "Ctrl+Shift+I", action: "agent", icon: "sparkles" },
        { label: "Wdróż", shortcut: "", action: "deploy", icon: "upload" },
        { label: "Wdrożenie: ustawienia…", shortcut: "", action: "deploySettings", icon: "upload" },
        { label: "GitHub: zaloguj / utwórz repozytorium…", shortcut: "", action: "deploySettings", icon: "gitBranch" },
        { label: "Agent: napraw problemy", shortcut: "", action: "agent:fix", icon: "sparkles" },
        { label: "Kontener projektu: utwórz…", shortcut: "", action: "env:create", icon: "box" },
        { label: "Sekrety projektu (.env, klucze API)", shortcut: "", action: "secrets", icon: "key" },
        { label: "Kontener projektu: zainstaluj pakiety…", shortcut: "", action: "env:install", icon: "box" },
        { label: "Uruchom aplikację (serwery)", shortcut: "Ctrl+F5", action: "run:all", icon: "play" },
        { label: "Zatrzymaj wszystkie procesy", shortcut: "", action: "run:stop", icon: "stop" },
        { label: "Podgląd strony", shortcut: "", action: "preview", icon: "globe" },
        { label: "Debuguj", shortcut: "F5", action: "debug", icon: "bug" },
        { label: "Debuguj inny program…", shortcut: "", action: "debugAsk", icon: "bug" },
        { label: "Punkt przerwania", shortcut: "F9", action: "breakpoint", icon: "bug" },
        { label: "Usuń wszystkie punkty przerwania", shortcut: "", action: "clearBreakpoints", icon: "trash" },
        { label: "Zbuduj", shortcut: "Ctrl+Shift+B", action: "build", icon: "bolt" },
        { label: "Uruchom ponownie ostatnie zadanie", shortcut: "", action: "rerun", icon: "reload" },
        { label: "Zatrzymaj zadanie", shortcut: "", action: "stopTask", icon: "stop" },
        { label: "Zwiń blok", shortcut: "Ctrl+Shift+[", action: "fold", icon: "chevronRight" },
        { label: "Rozwiń blok", shortcut: "Ctrl+Shift+]", action: "unfold", icon: "chevronDown" },
        { label: "Zwiń wszystko", shortcut: "Ctrl+K Ctrl+0", action: "foldAll", icon: "chevronRight" },
        { label: "Rozwiń wszystko", shortcut: "Ctrl+K Ctrl+J", action: "unfoldAll", icon: "chevronDown" },
        { label: "Minimapa", shortcut: "", action: "minimap", icon: "sidebar" },
        { label: "Dodaj następne wystąpienie", shortcut: "Ctrl+D", action: "nextOccurrence", icon: "cursor" },
        { label: "Zaznacz wszystkie wystąpienia", shortcut: "Ctrl+Shift+L", action: "allOccurrences", icon: "cursor" },
        { label: "Dodaj kursor powyżej", shortcut: "Ctrl+Alt+↑", action: "cursorAbove", icon: "up" },
        { label: "Dodaj kursor poniżej", shortcut: "Ctrl+Alt+↓", action: "cursorBelow", icon: "chevronDown" },
        { label: "Usuń wiersz", shortcut: "Ctrl+Shift+K", action: "deleteLine", icon: "trash" },
        { label: "Następna zmiana", shortcut: "Alt+F5", action: "nextChange", icon: "chevronDown" },
        { label: "Poprzednia zmiana", shortcut: "Shift+Alt+F5", action: "prevChange", icon: "up" },
        { label: "Pokaż pliki", shortcut: "Ctrl+Shift+E", action: "viewFiles", icon: "files" },
        { label: "Pokaż zmiany (git)", shortcut: "Ctrl+Shift+G", action: "viewChanges", icon: "gitBranch" },
        { label: "Pasek boczny", shortcut: "Ctrl+B", action: "sidebar", icon: "sidebar" },
        { label: "Terminal", shortcut: "Ctrl+`", action: "terminal", icon: "terminal" },
        { label: "Nowy terminal", shortcut: "", action: "newTerminal", icon: "prompt" },
        { label: "Zawijaj wiersze", shortcut: "Alt+Z", action: "wrap", icon: "textSize" },
        { label: "Wcięcia: spacje", shortcut: "", action: "indent:spaces", icon: "sliders" },
        { label: "Wcięcia: tabulatory", shortcut: "", action: "indent:tabs", icon: "sliders" },
        { label: "Powiększ tekst", shortcut: "Ctrl+=", action: "zoomIn", icon: "plus" },
        { label: "Pomniejsz tekst", shortcut: "Ctrl+-", action: "zoomOut", icon: "minus" },
        { label: "Odśwież stan gita", shortcut: "", action: "gitRefresh", icon: "reload" },
        { label: "Git: zatwierdź", shortcut: "", action: "git:commit", icon: "check" },
        { label: "Git: dodaj wszystkie zmiany", shortcut: "", action: "git:stageAll", icon: "plus" },
        { label: "Git: wyślij (push)", shortcut: "", action: "git:push", icon: "upload" },
        { label: "Git: pobierz (pull)", shortcut: "", action: "git:pull", icon: "download" },
        { label: "Git: pokaż zmiany w pliku", shortcut: "", action: "git:diff", icon: "gitBranch" },
        { label: "Git: historia pliku", shortcut: "", action: "fileHistory", icon: "clock" },
        { label: "Git: przełącz gałąź…", shortcut: "", action: "git:checkout", icon: "gitBranch" },
        { label: "Git: nowa gałąź…", shortcut: "", action: "git:checkout", icon: "plus" },
        { label: "Git: połącz gałąź z bieżącą…", shortcut: "", action: "git:merge", icon: "gitBranch" },
        { label: "Git: usuń gałąź…", shortcut: "", action: "git:deleteBranch", icon: "trash" },
        { label: "Git: odłóż zmiany (stash)", shortcut: "", action: "git:stash", icon: "archive" },
        { label: "Git: autor wiersza — pokaż/ukryj", shortcut: "", action: "blame", icon: "user" },
        { label: "Git: przerwij łączenie", shortcut: "", action: "git:mergeAbort", icon: "close" },
        { label: "Git: przywróć odłożone zmiany", shortcut: "", action: "git:stashPop", icon: "undo" },
        { label: "Kopiuj ścieżkę pliku", shortcut: "", action: "copyPath", icon: "copy" },
        { label: "Kopiuj ścieżkę względną", shortcut: "", action: "copyRel", icon: "copy" },
        { label: "Pokaż w Plikach", shortcut: "", action: "showInFiles", icon: "folder" },
        { label: "Zamknij folder", shortcut: "", action: "closeFolder", icon: "close" }
    ]
    function run(a) {
        if (a === "openFolder") folderDialog.open();
        else if (a === "newFile") newFile("");
        else if (a === "newFolder") newFolder("");
        else if (a === "save") save(current);
        else if (a === "saveAll") saveAll();
        else if (a === "closeTab") closeTab(current);
        else if (a === "closeAll") { for (let i = tabs.count - 1; i >= 0; --i) closeTab(i); }
        else if (a === "quickOpen") palette.open("");
        else if (a === "commands") palette.open(">");
        else if (a === "goto") palette.open(":");
        else if (a === "find") openFind(false);
        else if (a === "replace") openFind(true);
        else if (a === "searchProject") showView(1);
        else if (a === "comment") { if (cur) cur.toggleComment(); }
        else if (a === "definition") goToDefinition();
        else if (a === "references") findReferences();
        else if (a === "quickfix") quickFix();
        else if (a === "symbols") palette.open("@");
        else if (a === "workspaceSymbols") palette.open("#");
        else if (a.startsWith("qa:")) Lsp.runCodeAction(Number(a.slice(3)));
        else if (a === "rename") startRename();
        else if (a === "format") formatDocument();
        else if (a === "complete") { if (cur) { cur.focusEditor(); cur.requestCompletion(); } }
        else if (a === "problems") showProblems();
        else if (a === "cut") { if (cur) cur.edit.cut(); }
        else if (a === "copy") { if (cur) cur.edit.copy(); }
        else if (a === "paste") { if (cur) cur.edit.paste(); }
        else if (a === "selectAll") { if (cur) cur.edit.selectAll(); }
        else if (a === "duplicate") { if (cur) cur.lines("duplicateDown"); }
        else if (a === "nextOccurrence") { if (cur) cur.addNextOccurrence(); }
        else if (a === "fold") { if (cur) cur.foldAtCursor(true); }
        else if (a === "unfold") { if (cur) cur.foldAtCursor(false); }
        else if (a === "foldAll") { if (cur) cur.foldAllBlocks(); }
        else if (a === "unfoldAll") { if (cur) cur.unfoldAllBlocks(); }
        else if (a === "minimap") prefs.minimap = !prefs.minimap;
        else if (a === "allOccurrences") { if (cur) cur.selectAllOccurrences(); }
        else if (a === "cursorAbove") { if (cur) cur.addCursorVertical(-1); }
        else if (a === "cursorBelow") { if (cur) cur.addCursorVertical(1); }
        else if (a === "deleteLine") { if (cur) cur.lines("deleteLine"); }
        else if (a === "nextChange") { if (cur) cur.nextChange(false); }
        else if (a === "prevChange") { if (cur) cur.nextChange(true); }
        else if (a === "viewFiles") showView(0);
        else if (a === "viewChanges") showView(2);
        else if (a === "sidebar") prefs.sidebar = !prefs.sidebar;
        else if (a === "terminal") toggleTerminal();
        else if (a === "newTerminal") { terminalShown = true; terminalPanel.restart(); }
        else if (a === "wrap") prefs.wrap = !prefs.wrap;
        else if (a === "indent:spaces") { if (cur) { cur.indentTabs = false; toast("Wcięcia: " + cur.indentSize + " spacje"); } }
        else if (a === "indent:tabs") { if (cur) { cur.indentTabs = true; toast("Wcięcia: tabulatory"); } }
        else if (a.startsWith("indent:size:")) { if (cur) { cur.indentTabs = false; cur.indentSize = Number(a.slice(12)); } }
        else if (a === "zoomIn") zoom(1);
        else if (a === "zoomOut") zoom(-1);
        else if (a === "gitRefresh") Project.refreshGit();
        else if (a === "git:commit") { showView(2); Qt.callLater(changesView.focusMessage); }
        else if (a === "git:stageAll") Project.stage(Project.changes.filter(c => !!c.work).map(c => c.path));
        else if (a === "git:push") Project.push();
        else if (a === "git:pull") Project.pull();
        else if (a === "git:diff") { if (curPath) diffView.open(curPath, false); }
        else if (a === "git:checkout") palette.openBranches("checkout");
        else if (a === "git:merge") palette.openBranches("merge");
        else if (a === "git:deleteBranch") palette.openBranches("delete");
        else if (a === "git:stash") whenSaved(() => Project.stash(false));
        else if (a === "blame") prefs.blame = !prefs.blame;
        else if (a === "git:mergeAbort") whenSaved(() => Project.mergeAbort());
        else if (a === "git:stashPop") Project.stash(true);
        else if (a === "copyPath") { if (curPath) Project.copyText(curPath); }
        else if (a === "copyRel") { if (curPath) Project.copyText(Project.relative(curPath)); }
        else if (a === "showInFiles") Project.showInFiles(curPath || Project.root);
        else if (a === "closeFolder") closeFolder();
        else if (a.startsWith("recent:")) openFolder(a.slice(7));
        else if (a.startsWith("enc:")) { tabs.setProperty(current, "encoding", a.slice(4)); revision++; if (cur) cur.edit.textDocument.modified = true; toast("Przy zapisie: " + a.slice(4)); }
        else if (a.startsWith("eol:")) { tabs.setProperty(current, "eol", a.slice(4) === "crlf" ? "\r\n" : "\n"); revision++; if (cur) cur.edit.textDocument.modified = true; }
        else if (a.startsWith("tree:")) runTree(a.slice(5), menu.path);
        else if (a === "tab:close") closeTab(menu.tab);
        else if (a === "tab:others") { const keep = tabs.get(menu.tab).uid; for (let i = tabs.count - 1; i >= 0; --i) if (tabs.get(i).uid !== keep) closeTab(i); }
        else if (a === "tab:right") { for (let i = tabs.count - 1; i > menu.tab; --i) closeTab(i); }
        else if (a === "tab:reveal") { prefs.sidebar = true; sidebarView = 0; const row = Project.tree.reveal(tabs.get(menu.tab).path); if (row >= 0) treeList.positionViewAtIndex(row, ListView.Center); }
        else if (a === "tab:copy") Project.copyText(Project.relative(tabs.get(menu.tab).path));
        else if (a === "tab:split") { activate(menu.tab); splitEditor(); }
        else if (a === "tab:history") showHistory(tabs.get(menu.tab).path);
        else if (a === "fileHistory") showHistory(curPath);
        else if (a === "tab:move") moveToOtherGroup(menu.tab);
        else if (a === "split") splitEditor();
        else if (a === "settings") settingsView.open();
        else if (a === "tasks") showTasks();
        else if (a === "env:create") createContainer();
        else if (a === "secrets") secretsView.open();
        else if (a === "newApp") newAppView.open();
        else if (a === "deploy") quickDeploy();
        else if (a === "deploySettings") deployView.open();
        else if (a === "agent") agentPanel.shown ? agentPanel.close() : agentPanel.open();
        else if (a === "agent:fix") askAgent("Napraw błędy z panelu Problemy w tym pliku.");
        else if (a === "agent:selection") askAgent("Wyjaśnij zaznaczony kod i zaproponuj poprawki, jeśli są potrzebne.");
        else if (a === "env:terminal") { terminalShown = true; terminalPanel.tab = 0; terminalPanel.restart(); }
        else if (a === "env:off") ProjectEnv.useContainer(false);
        else if (a === "env:install") nameBox.ask("Zainstaluj w kontenerze", "", "Pakiety Fedory, np. nodejs postgresql-server redis", (t) => { if (t.trim()) win.envTask("Kontener: pakiety", ProjectEnv.installCommand(t.trim().split(/\s+/))); });
        else if (a === "env:remove") win.confirm = { kind: "envRemove", name: ProjectEnv.container };
        else if (a === "run:all") runApp();
        else if (a === "run:stop") Tasks.stopAll();
        else if (a === "preview") preview.shown ? preview.close() : preview.open("");
        else if (a.startsWith("run:")) { const t = runMenuTargets[Number(a.slice(4))]; if (t) { saveAll(); Tasks.run(t.label, t.command, t.cwd || Project.root, taskEnv(t.cwd || Project.root)); terminalShown = true; terminalPanel.tab = 3; } }
        else if (a === "debug") startDebug(false);
        else if (a === "debugAsk") startDebug(true);
        else if (a === "breakpoint") toggleBreakpointHere();
        else if (a === "clearBreakpoints") Debugger.clearBreakpoints();
        else if (a === "build") buildTask();
        else if (a === "rerun") { saveAll(); Tasks.rerun(); terminalShown = true; terminalPanel.tab = 3; }
        else if (a === "stopTask") Tasks.stop();
    }
    function runTree(a, path) {
        if (a === "newFile") newFile(path);
        else if (a === "newFolder") newFolder(path);
        else if (a === "rename") renamePath(path);
        else if (a === "history") showHistory(path);
        else if (a === "trash") trashPath(path);
        else if (a === "copyPath") Project.copyText(path);
        else if (a === "copyRel") Project.copyText(Project.relative(path));
        else if (a === "show") Project.showInFiles(path);
        else if (a === "terminal") {
            terminalShown = true;
            const dir = Project.isDir(path) ? path : Project.folder(path);
            Qt.callLater(() => { if (terminalPanel.term) { terminalPanel.term.sendText("cd '" + dir.replace(/'/g, "'\\''") + "'\r"); terminalPanel.focusTerminal(); } });
        }
    }
    function showMenu() {
        const p = moreBtn.mapToItem(frame, moreBtn.width, moreBtn.height + 6);
        menu.openAt(p.x - 250, p.y, [
            { label: "Otwórz folder…", icon: "folder", shortcut: "Ctrl+O", action: "openFolder" },
            { label: "Nowy plik", icon: "filePlus", shortcut: "Ctrl+N", action: "newFile" },
            { label: "Nowa aplikacja…", icon: "sparkle", action: "newApp" },
            { label: "Zapisz", icon: "download", shortcut: "Ctrl+S", action: "save", enabled: !!win.cur },
            { label: "Zapisz wszystko", icon: "copy", shortcut: "Ctrl+Alt+S", action: "saveAll" },
            { separator: true },
            { label: "Polecenia…", icon: "apps", shortcut: "Ctrl+Shift+P", action: "commands" },
            { label: "Szukaj w projekcie", icon: "search", shortcut: "Ctrl+Shift+F", action: "searchProject" },
            { separator: true },
            { label: "Pasek boczny", icon: prefs.sidebar ? "check" : "", shortcut: "Ctrl+B", action: "sidebar" },
            { label: "Terminal", icon: win.terminalShown ? "check" : "", shortcut: "Ctrl+`", action: "terminal" },
            { label: "Zawijaj wiersze", icon: prefs.wrap ? "check" : "", shortcut: "Alt+Z", action: "wrap" },
            { label: "Autor wiersza (git)", icon: prefs.blame ? "check" : "", action: "blame" },
            { label: "Minimapa", icon: prefs.minimap ? "check" : "", action: "minimap" },
            { separator: true },
            { label: "Ustawienia…", icon: "gear", shortcut: "Ctrl+,", action: "settings" },
            { separator: true },
            { label: "Zamknij folder", icon: "close", action: "closeFolder" }
        ]);
    }
    function showProjectMenu() {
        const p = projectBtn.mapToItem(frame, 0, projectBtn.height + 4);
        const items = Project.recent.filter(r => r.path !== Project.root).slice(0, 8)
            .map(r => ({ label: r.name, icon: "folder", shortcut: "", action: "recent:" + r.path }));
        menu.openAt(p.x, p.y, items.concat(items.length ? [{ separator: true }] : [], [
            { label: "Otwórz folder…", icon: "folder", shortcut: "Ctrl+O", action: "openFolder" },
            { label: "Pokaż w Plikach", icon: "folder", action: "showInFiles" },
            { label: "Zamknij folder", icon: "close", action: "closeFolder" }
        ]));
    }
    function showTreeMenu(path, isDir, x, y) {
        menu.path = path;
        menu.openAt(x, y, [
            { label: "Nowy plik", icon: "filePlus", action: "tree:newFile" },
            { label: "Nowy folder", icon: "folderPlus", action: "tree:newFolder" },
            { separator: true },
            { label: "Zmień nazwę", icon: "pencil", action: "tree:rename", enabled: path !== Project.root },
            { label: "Przenieś do Kosza", icon: "trash", action: "tree:trash", danger: true, enabled: path !== Project.root },
            { separator: true },
            { label: "Historia pliku", icon: "clock", action: "tree:history", enabled: !isDir && Project.isGit },
            { label: "Kopiuj ścieżkę", icon: "copy", action: "tree:copyPath" },
            { label: "Kopiuj ścieżkę względną", icon: "copy", action: "tree:copyRel" },
            { label: "Otwórz w terminalu", icon: "terminal", action: "tree:terminal" },
            { label: "Pokaż w Plikach", icon: "folder", action: "tree:show" }
        ]);
    }
    function showStatusMenu(kind, item) {
        const p = item.mapToItem(frame, 0, 0);
        const t = tabs.get(current);
        let items;
        if (kind === "enc") items = ["UTF-8", "UTF-8 BOM", "Windows-1250", "ISO-8859-2"].map(e => ({ label: e, icon: t.encoding === e ? "check" : "", action: "enc:" + e }));
        else if (kind === "eol") items = [{ label: "Linux, macOS (LF)", icon: t.eol === "\n" ? "check" : "", action: "eol:lf" }, { label: "Windows (CRLF)", icon: t.eol === "\r\n" ? "check" : "", action: "eol:crlf" }];
        else items = [{ label: "Tabulatory", icon: cur.indentTabs ? "check" : "", action: "indent:tabs" }]
            .concat([2, 4, 8].map(n => ({ label: n + (n === 8 ? " spacji" : " spacje"), icon: !cur.indentTabs && cur.indentSize === n ? "check" : "", action: "indent:size:" + n })));
        menu.openAt(Math.min(p.x, frame.width - 260), p.y - items.length * 34 - 18, items);
    }

    // Do testów (ASTER_OPEN, kroki po „;”): folder:ŚCIEŻKA | open:WZGLĘDNA | line:N | type:TEKST | lines:OPERACJA
    // | selectLines:OD,DO | terminal | term:POLECENIE
    // | search:TEKST | palette:TEKST | find:TEKST | view:N | expand:WZGLĘDNA | menu | tree:WZGLĘDNA | close
    function testOpen(what) {
        const arg = what.slice(what.indexOf(":") + 1);
        if (what.startsWith("folder:")) openFolder(arg);
        else if (what.startsWith("open:")) openFile(Project.root + "/" + arg, { preview: false });
        else if (what.startsWith("preview:")) openFile(Project.root + "/" + arg, { preview: true });
        else if (what.startsWith("line:")) { if (cur) { const lc = arg.split(","); cur.goToLine(Number(lc[0]), Number(lc[1] || 1) - 1); } }
        else if (what.startsWith("type:")) { if (cur) { cur.edit.insert(cur.edit.cursorPosition, arg.replace(/\\n/g, "\n")); pin(current); } }
        else if (what.startsWith("del:")) { if (cur) { const p = cur.edit.cursorPosition; cur.edit.remove(p, p + Number(arg)); } }
        else if (what.startsWith("lines:")) { if (cur) cur.lines(arg); }
        else if (what.startsWith("selectLines:")) { if (cur) { const ab = arg.split(","); cur.edit.select(TextOps.positionOfLine(cur.edit.textDocument, Number(ab[0]) - 1), TextOps.positionOfLine(cur.edit.textDocument, Number(ab[1]))); } }
        else if (what === "terminal") { terminalShown = true; }
        else if (what.startsWith("term:")) { if (terminalPanel.term) terminalPanel.term.sendText(arg + "\r"); }
        else if (what.startsWith("search:")) { showView(1); searchView.focusField(arg); searchView.run(); }
        else if (what.startsWith("replaceWith:")) searchView.setReplacement(arg);
        else if (what === "regexOn") searchView.regex = true;
        else if (what === "replaceAllAsk") { win.confirm = { kind: "replace", count: Project.resultCount, files: Project.results.length, paths: Project.results.map(r => r.path) }; }
        else if (what === "replaceAllNow") replaceInPaths(Project.results.map(r => r.path));
        else if (what.startsWith("palette:")) palette.open(arg);
        else if (what.startsWith("find:")) { openFind(false); findField.text = arg; findAll(); }
        else if (what.startsWith("view:")) { prefs.sidebar = true; sidebarView = Number(arg); }
        else if (what.startsWith("expand:")) Project.tree.expandPath(Project.root + "/" + arg);
        else if (what.startsWith("tree:")) { const row = Project.tree.indexOf(Project.root + "/" + arg); const it = treeList.itemAtIndex(row); if (it) { const pp = it.mapToItem(frame, 60, 14); showTreeMenu(Project.root + "/" + arg, false, pp.x, pp.y); } }
        else if (what === "menu") showMenu();
        else if (what === "complete") { if (cur) cur.requestCompletion(); }
        else if (what.startsWith("diff:")) diffView.open(Project.root + "/" + arg, false);
        else if (what.startsWith("stage:")) Project.stage([Project.root + "/" + arg]);
        else if (what.startsWith("commitmsg:")) { showView(2); changesView.setMessage(arg); }
        else if (what === "commit") changesView.commitNow();
        else if (what === "push") Project.push();
        else if (what === "save") save(current);
        else if (what === "split") splitEditor();
        else if (what === "settings") settingsView.open();
        else if (what === "tasks") showTasks();
        else if (what === "runapp") runApp();
        else if (what === "envcreate") { ProjectEnv.useContainer(true); envTask("Kontener: przygotowanie", ProjectEnv.createCommand(ProjectEnv.suggestPackages())); }
        else if (what === "envmenu") showEnvMenu();
        else if (what === "secrets") secretsView.open();
        else if (what === "newapp") newAppView.open();
        else if (what === "agent") agentPanel.open();
        else if (what.startsWith("ask:")) askAgent(arg);
        else if (what === "acceptall") agentPanel.acceptAll();
        else if (what.startsWith("replaceline:")) { if (cur) { const kv = arg.split("=>"); const t = cur.edit.text.replace(kv[0], kv[1]); TextOps.multiEdit(cur.edit.textDocument, [{ a: 0, b: cur.edit.length }], [t], 0); } }
        else if (what === "sidebyside") prefs.diffSideBySide = true;
        else if (what === "deployview") deployView.open();
        else if (what.startsWith("deploycfg:")) { Project.save(Project.root + "/.aster/wdrozenie.json", arg, "UTF-8", "LF"); }
        else if (what === "deploy") quickDeploy();
        else if (what === "ghlogin") { deployView.open(); GitHub.loginBrowser(); }
        else if (what === "reviewfirst") { const e = agentPanel.edits.find(x => x.state === "pending"); if (e) agentPanel.review(e.path); }
        else if (what.startsWith("mkapp:")) { const o = JSON.parse(arg); const r = Templates.create(o); if (r.ok) startFromTemplate(r, !!o.container); else toast(r.error); }
        else if (what === "importenv") Secrets.importEnv(Project.root + "/.env", true);
        else if (what.startsWith("secret:")) { const kv = arg.split("="); Secrets.set(kv[0], kv.slice(1).join("=")); }
        else if (what.startsWith("preview:")) preview.open(arg);
        else if (what === "phone") preview.phone = true;
        else if (what === "pconsole") preview.consoleOpen = true;
        else if (what === "history") showHistory(curPath);
        else if (what.startsWith("histdiff:")) { const n = Number(arg); const e = historyView.entries[n]; if (e) diffView.openCommit(curPath, e.rel, e.hash, e.subject); }
        else if (what.startsWith("histfiles:")) { const e = historyView.entries[Number(arg)]; if (e) showCommit(e.hash); }
        else if (what.startsWith("restore:")) { const e = historyView.entries[Number(arg)]; if (e) restoreVersion(curPath, e.hash, e.rel); }
        else if (what.startsWith("bp:")) Debugger.toggleBreakpoint(curPath, Number(arg) - 1);
        else if (what.startsWith("debug:")) { const d = arg.split(" "); launchDebug("native", Project.root + "/" + d[0], d.slice(1).join(" ")); }
        else if (what === "dnext") Debugger.next();
        else if (what === "dstep") Debugger.stepIn();
        else if (what === "dcont") Debugger.resume();
        else if (what.startsWith("deval:")) Debugger.evaluate(arg);
        else if (what.startsWith("runcmd:")) runTask({ label: arg, command: arg, group: "custom" });
        else if (what.startsWith("settingsSearch:")) { settingsView.open(); Qt.callLater(() => settingsView.searchFor(arg)); }
        else if (what.startsWith("pref:")) { const kv = arg.split("="); prefs[kv[0]] = kv[1] === "true" ? true : kv[1] === "false" ? false : kv[1]; }
        else if (what.startsWith("focus:")) focusGroupN(Number(arg));
        else if (what === "moveTab") moveToOtherGroup(current);
        else if (what.startsWith("fold:")) { if (cur) cur.toggleFold(Number(arg) - 1); }
        else if (what === "foldAll") { if (cur) cur.foldAllBlocks(); }
        else if (what === "ctrlD") { if (cur) cur.addNextOccurrence(); }
        else if (what === "allOcc") { if (cur) cur.selectAllOccurrences(); }
        else if (what === "cursorBelow") { if (cur) cur.addCursorVertical(1); }
        else if (what === "end") { if (cur) cur.moveAll(c => cur.lineEndOf(c.p), false); }
        else if (what.startsWith("resolve:")) { if (cur) { const r = arg.split(","); cur.resolve(Number(r[0]) - 1, r[1]); } }
        else if (what.startsWith("branches:")) { palette.openBranches(arg.split(",")[0]); }
        else if (what.startsWith("newbranch:")) branchAction("checkout", arg, false, true);
        else if (what.startsWith("checkout:")) branchAction("checkout", arg, false, false);
        else if (what.startsWith("checkoutRemote:")) branchAction("checkout", arg, true, false);
        else if (what === "stash") Project.stash(false);
        else if (what === "stashPop") Project.stash(true);
        else if (what.startsWith("merge:")) branchAction("merge", arg, false, false);
        else if (what.startsWith("hunk:")) { const h = arg.split(","); Project.applyHunk(Project.root + "/" + h[0], h[2] === "staged", Number(h[1]), h[3] || "stage"); }
        else if (what.startsWith("discardNow:")) win.discardPaths([Project.root + "/" + arg]);
        else if (what.startsWith("discard:")) win.confirm = { kind: "discard", paths: [Project.root + "/" + arg], name: Project.fileName(arg) };
        else if (what === "problems") showProblems();
        else if (what === "definition") goToDefinition();
        else if (what === "refs") findReferences();
        else if (what === "quickfix") quickFix();
        else if (what.startsWith("runqa:")) { menu.close(); Lsp.runCodeAction(Number(arg)); }
        else if (what === "format") formatDocument();
        else if (what.startsWith("rename:")) { if (cur) { renameFrom = cur.symbolAt().text; cur.renameSymbol(arg); } }
        else if (what.startsWith("keys:")) { if (cur) for (const ch of arg) cur.typeKey(ch); }
        else if (what.startsWith("hover:")) { if (cur) { const ab = arg.split(","); cur.testHover(Number(ab[0]), Number(ab[1])); } }
        else if (what === "newfile") newFile("");
        else if (what === "close") win.close();
    }

    // ——— Skróty ———
    Shortcut { sequence: "Ctrl+O"; onActivated: folderDialog.open() }
    Shortcut { sequence: "Ctrl+N"; enabled: win.hasProject; onActivated: win.newFile("") }
    Shortcut { sequence: "Ctrl+S"; enabled: !!win.cur; onActivated: win.save(win.current) }
    Shortcut { sequence: "Ctrl+Alt+S"; onActivated: win.saveAll() }
    Shortcut { sequence: "Ctrl+W"; enabled: tabs.count > 0; onActivated: win.closeTab(win.current) }
    Shortcut { sequence: "Ctrl+\\"; enabled: !!win.cur; onActivated: win.splitEditor() }
    Shortcut { sequence: "Ctrl+Shift+B"; enabled: win.hasProject; onActivated: win.buildTask() }
    Shortcut { sequence: "Ctrl+F5"; enabled: win.hasProject; onActivated: win.runApp() }
    Shortcut { sequence: "Ctrl+Shift+I"; enabled: win.hasProject; onActivated: agentPanel.shown ? agentPanel.close() : agentPanel.open() }
    Shortcut { sequence: "F5"; enabled: win.hasProject; onActivated: win.startDebug(false) }
    Shortcut { sequence: "Shift+F5"; enabled: !!Debugger.state; onActivated: Debugger.stop() }
    Shortcut { sequence: "F6"; enabled: Debugger.state === "running"; onActivated: Debugger.pause() }
    Shortcut { sequence: "F10"; enabled: Debugger.state === "stopped"; onActivated: Debugger.next() }
    Shortcut { sequence: "F11"; enabled: Debugger.state === "stopped"; onActivated: Debugger.stepIn() }
    Shortcut { sequence: "Shift+F11"; enabled: Debugger.state === "stopped"; onActivated: Debugger.stepOut() }
    Shortcut { sequence: "F9"; enabled: !!win.cur; onActivated: win.toggleBreakpointHere() }
    Shortcut { sequence: "Ctrl+,"; onActivated: settingsView.shown ? settingsView.close() : settingsView.open() }
    Shortcut { sequence: "Ctrl+1"; enabled: win.split; onActivated: win.focusGroupN(0) }
    Shortcut { sequence: "Ctrl+2"; enabled: win.split; onActivated: win.focusGroupN(1) }
    Shortcut { sequences: ["Ctrl+P", "Ctrl+E"]; enabled: win.hasProject; onActivated: palette.open("") }
    Shortcut { sequences: ["Ctrl+Shift+P", "F1"]; enabled: win.hasProject; onActivated: palette.open(">") }
    Shortcut { sequence: "Ctrl+G"; enabled: !!win.cur; onActivated: palette.open(":") }
    Shortcut { sequence: "Ctrl+F"; enabled: !!win.cur; onActivated: win.openFind(false) }
    Shortcut { sequence: "Ctrl+H"; enabled: !!win.cur; onActivated: win.openFind(true) }
    Shortcut { sequence: "F3"; onActivated: { if (!findField.text) win.openFind(false); else win.select(win.matchIndex + 1); } }
    Shortcut { sequence: "Shift+F3"; onActivated: win.select(win.matchIndex - 1) }
    Shortcut { sequence: "Ctrl+Shift+F"; enabled: win.hasProject; onActivated: win.showView(1) }
    Shortcut { sequence: "Ctrl+Shift+E"; enabled: win.hasProject; onActivated: { prefs.sidebar = true; win.sidebarView = 0; } }
    Shortcut { sequence: "Ctrl+Shift+G"; enabled: win.hasProject; onActivated: win.showView(2) }
    Shortcut { sequence: "Ctrl+B"; enabled: win.hasProject; onActivated: prefs.sidebar = !prefs.sidebar }
    Shortcut { sequences: ["Ctrl+`", "Ctrl+J"]; enabled: win.hasProject; onActivated: win.toggleTerminal() }
    Shortcut { sequences: ["Ctrl+/", "Ctrl+K,Ctrl+C"]; enabled: !!win.cur && win.cur.edit.activeFocus; onActivated: win.cur.toggleComment() }
    Shortcut { sequence: "F12"; enabled: !!win.cur; onActivated: win.goToDefinition() }
    Shortcut { sequence: "Shift+F12"; enabled: !!win.cur; onActivated: win.findReferences() }
    Shortcut { sequence: "Ctrl+."; enabled: !!win.cur; onActivated: win.quickFix() }
    Shortcut { sequences: ["Ctrl+Shift+[", "Ctrl+{"]; enabled: !!win.cur; onActivated: win.cur.foldAtCursor(true) }
    Shortcut { sequences: ["Ctrl+Shift+]", "Ctrl+}"]; enabled: !!win.cur; onActivated: win.cur.foldAtCursor(false) }
    Shortcut { sequence: "Ctrl+K,Ctrl+0"; enabled: !!win.cur; onActivated: win.cur.foldAllBlocks() }
    Shortcut { sequence: "Ctrl+K,Ctrl+J"; enabled: !!win.cur; onActivated: win.cur.unfoldAllBlocks() }
    Shortcut { sequence: "Ctrl+Shift+O"; enabled: !!win.cur; onActivated: palette.open("@") }
    Shortcut { sequence: "Ctrl+T"; enabled: win.hasProject; onActivated: palette.open("#") }
    Shortcut { sequence: "F2"; enabled: !!win.cur; onActivated: win.startRename() }
    Shortcut { sequence: "Shift+Alt+F"; enabled: !!win.cur; onActivated: win.formatDocument() }
    Shortcut { sequence: "Ctrl+Shift+M"; enabled: win.hasProject; onActivated: win.showProblems() }
    Shortcut { sequence: "Alt+F5"; enabled: !!win.cur; onActivated: win.cur.nextChange(false) }
    Shortcut { sequence: "Shift+Alt+F5"; enabled: !!win.cur; onActivated: win.cur.nextChange(true) }
    Shortcut { sequence: "Alt+Z"; onActivated: prefs.wrap = !prefs.wrap }
    Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: win.zoom(1) }
    Shortcut { sequence: "Ctrl+-"; onActivated: win.zoom(-1) }
    Shortcut { sequence: "Ctrl+0"; onActivated: win.zoom(0) }
    Shortcut { sequences: ["Ctrl+Tab", "Ctrl+PgDown"]; enabled: tabs.count > 1; onActivated: win.activate((win.current + 1) % tabs.count) }
    Shortcut { sequences: ["Ctrl+Shift+Tab", "Ctrl+PgUp"]; enabled: tabs.count > 1; onActivated: win.activate((win.current - 1 + tabs.count) % tabs.count) }
    Shortcut { sequence: "F11"; onActivated: { if (win.visibility === Window.FullScreen) win.showNormal(); else win.showFullScreen(); } }
    Shortcut { sequence: "Esc"; enabled: findBar.shown || !!win.confirm || diffView.shown || settingsView.shown || secretsView.shown || deployView.shown
        onActivated: { if (win.confirm) win.confirm = null; else if (deployView.shown) deployView.close(); else if (secretsView.shown) secretsView.close(); else if (settingsView.shown) settingsView.close(); else if (diffView.shown) { diffView.close(); if (win.cur) win.cur.focusEditor(); } else win.closeFind(); } }

    // ——— Okno ———
    function updateEffects() {
        WindowEffects.setBlur(win, Qt.rect(m, m, frame.width, frame.height), r);
        WindowEffects.setInputRegion(win, Qt.rect(Math.max(0, m - 6), Math.max(0, m - 6), frame.width + (maxed ? 0 : 12), frame.height + (maxed ? 0 : 12)));
    }
    onWidthChanged: effectsTimer.restart()
    onHeightChanged: effectsTimer.restart()
    onMaxedChanged: effectsTimer.restart()
    Timer { id: effectsTimer; interval: 16; onTriggered: win.updateEffects() }

    WindowShadow { window: win; frame: frame; radius: win.r; visible: !win.maxed }
    ResizeHandles { window: win; frame: frame; margin: win.m }

    Rectangle {
        id: frame
        x: win.m; y: win.m
        width: win.width - 2 * win.m
        height: win.height - 2 * win.m
        radius: win.r
        color: Theme.windowGlass
        border.width: win.maxed ? 0 : 1
        border.color: Theme.edge
        WindowSheen { window: win; radius: win.r }
        clip: true

        DropArea {
            anchors.fill: parent
            onEntered: (drag) => drag.accept(Qt.CopyAction)
            onDropped: (drop) => {
                if (!drop.hasUrls) return;
                const first = Project.toPath(String(drop.urls[0]));
                if (Project.isDir(first)) win.openFolder(first);
                else if (win.hasProject) drop.urls.forEach(u => win.openFile(String(u)));
            }
        }

        // ——— Panel treści ———
        GlassPane {
            id: pane
            visible: win.hasProject
            x: sidebar.width
            width: parent.width - sidebar.width
            height: parent.height
            topRightRadius: win.r; bottomRightRadius: win.r
            topLeftRadius: prefs.sidebar ? 0 : win.r; bottomLeftRadius: prefs.sidebar ? 0 : win.r
            leftLine: prefs.sidebar

            // Pasek kart
            Item {
                id: tabBar
                width: parent.width; height: 46
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }
                Flickable {
                    id: tabFlick
                    x: 8
                    width: Math.min(tabRow.width, (win.split ? win.splitX : rightGroup.x) - x - 8)
                    height: parent.height
                    contentWidth: tabRow.width
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentWidth > width
                    clip: true
                    Row {
                        id: tabRow
                        height: parent.height
                        spacing: 2
                        Repeater { model: tabs; delegate: TabButton { shownGroup: 0 } }
                    }
                }
                // Karty prawej grupy
                Flickable {
                    visible: win.split
                    x: win.splitX + 8
                    width: Math.min(tabRow1.width, rightGroup.x - x - 8)
                    height: parent.height
                    contentWidth: tabRow1.width
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentWidth > width
                    clip: true
                    Row {
                        id: tabRow1
                        height: parent.height
                        spacing: 2
                        Repeater { model: tabs; delegate: TabButton { shownGroup: 1 } }
                    }
                }
                Rectangle { visible: win.split; x: win.splitX; y: 10; width: 1; height: parent.height - 20; color: Theme.line }
                Row {
                    id: rightGroup
                    anchors.right: winButtons.left; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    // ▶ Uruchom — z wykrytych serwerów; zielony, gdy coś działa
                    ToolBtn {
                        id: runBtn
                        visible: win.hasProject
                        icon: "play"
                        opacity: 1
                        onClicked: Tasks.runningCount ? win.showRunMenu() : win.runApp()
                        Rectangle {
                            visible: Tasks.runningCount > 0
                            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 3
                            width: 8; height: 8; radius: 4
                            color: Theme.dark ? "#3FB950" : "#1A7F37"
                        }
                    }
                    ToolBtn { icon: "chevronDown"; visible: win.hasProject; width: 18; onClicked: win.showRunMenu() }
                    ToolBtn { icon: "globe"; visible: win.hasProject; opacity: preview.shown ? 1 : 0.7; onClicked: preview.shown ? preview.close() : preview.open("") }
                    ToolBtn { icon: "upload"; visible: win.hasProject; onClicked: win.quickDeploy() }
                    ToolBtn { icon: "sparkles"; visible: win.hasProject; opacity: agentPanel.shown ? 1 : 0.7; onClicked: agentPanel.shown ? agentPanel.close() : agentPanel.open() }
                    ToolBtn { icon: "search"; onClicked: palette.open("") }
                    ToolBtn { icon: "sidebar"; rotation: 180; enabled: !!win.cur; onClicked: win.splitEditor() }
                    ToolBtn { icon: "panelBottom"; opacity: win.terminalShown ? 1 : 0.7; onClicked: win.toggleTerminal() }
                    ToolBtn { id: moreBtn; icon: "more"; onClicked: win.showMenu() }
                }
                WindowButtons {
                    id: winButtons
                    window: win
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
            }

            // Ścieżka pliku (okruszki)
            Item {
                id: crumbs
                y: tabBar.height
                width: parent.width; height: win.cur ? 28 : 0
                visible: !!win.cur
                Repeater {
                    model: win.split ? [0, 1] : [0]
                    delegate: Row {
                        id: crumbRow
                        required property int modelData
                        readonly property string gpath: { win.revision; const i = win.groupActive(modelData); return i >= 0 ? tabs.get(i).path : ""; }
                        readonly property var parts: gpath ? Project.relative(gpath).split("/") : []
                        x: (modelData === 1 ? win.splitX : 0) + 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: (win.split ? win.splitX : crumbs.width) - 24
                        clip: true
                        spacing: 4
                        opacity: !win.split || modelData === win.focusGroup ? 1 : 0.6
                        Repeater {
                            model: crumbRow.parts
                            delegate: Row {
                                id: crumb
                                required property string modelData
                                required property int index
                                spacing: 4
                                Icon { visible: crumb.index > 0; anchors.verticalCenter: parent.verticalCenter; d: Icons.chevronRight; size: 11; stroke: 2; color: Theme.text2 }
                                FileIcon {
                                    visible: crumb.index === crumbRow.parts.length - 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: crumb.modelData; size: 13
                                }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: crumb.modelData; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                            }
                        }
                    }
                }
            }

            // Edytor
            Item {
                id: editorArea
                y: crumbs.y + crumbs.height
                width: parent.width - (preview.shown ? preview.width : 0) - (agentPanel.shown ? agentPanel.width : 0)
                height: (win.terminalShown && win.terminalMax ? 0 : parent.height - y - status.height - (win.terminalShown ? terminalPanel.height : 0))
                clip: true

                // Plik zmieniony przez inny program
                Rectangle {
                    id: banner
                    visible: tabs.count > 0 && win.revision >= 0 && tabs.get(win.current).changedOnDisk
                    width: parent.width; height: visible ? 40 : 0
                    color: Theme.accentAlpha(Theme.dark ? 0.18 : 0.09)
                    Text {
                        x: 18; anchors.verticalCenter: parent.verticalCenter
                        text: tabs.count && Project.exists(win.curPath) ? "Ten plik zmienił inny program." : "Ten plik został usunięty albo przeniesiony."
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                    }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Pill { visible: tabs.count && Project.exists(win.curPath); text: "Wczytaj tę wersję"; onClicked: win.reloadCurrent() }
                        Pill { text: "Zostaw moją"; onClicked: { tabs.setProperty(win.current, "changedOnDisk", false); win.revision++; } }
                    }
                }

                Repeater {
                    id: pages
                    model: tabs
                    delegate: CodePage {
                        id: pg
                        required property int index
                        required property int uid
                        required property var model
                        required property int group
                        path: model.path
                        x: group === 1 ? win.splitX : 0
                        y: banner.height
                        width: win.split ? (group === 0 ? win.splitX : editorArea.width - win.splitX) : editorArea.width
                        height: editorArea.height - y
                        visible: { win.revision; return index === win.groupActive(group); }
                        onEditFocused: win.editorFocused(index)
                        wrap: prefs.wrap
                        showBlame: prefs.blame
                        showMinimap: prefs.minimap
                        fontFamily: prefs.fontFamily
                        autoClose: prefs.autoClose
                        autoComplete: prefs.autoComplete
                        defaultIndent: prefs.defaultIndent
                        onEdited: { if (prefs.autoSave === "delay") autoSaveTimer.restart(); backupTimer.restart(); }
                        fontSize: prefs.fontSize
                        onZoomRequested: (d) => win.zoom(d)
                        onDefinitionRequested: (seq) => win.definitionFeedback(seq)
                        onQuickFixRequested: win.quickFix()
                        onContextMenuRequested: (item, x, y) => win.showEditorMenu(item, x, y)
                        onModifiedChanged: { if (modified) win.pin(index); else Project.backupRemove(path); win.revision++; }
                        Component.onCompleted: {
                            if (win.pendingPrimary[uid] === false) lspPrimary = false;
                            delete win.pendingPrimary[uid];
                            load(win.pendingText[uid] || "", win.pendingCursor[uid] || 0);
                            delete win.pendingText[uid];
                            delete win.pendingCursor[uid];
                        }
                    }
                }

                // Linia między grupami
                Rectangle { visible: win.split; x: win.splitX; width: 1; height: parent.height; color: Theme.line; z: 6 }

                // Pasek sterowania debugowaniem (u góry edytora, na środku)
                Rectangle {
                    visible: !!Debugger.state
                    z: 8
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 6
                    width: dbgRow.width + 12; height: 34; radius: 10
                    color: Theme.surface
                    border.width: 1; border.color: Theme.edge
                    Row {
                        id: dbgRow
                        anchors.centerIn: parent
                        spacing: 2
                        DbgBtn { icon: Debugger.state === "running" ? "pause" : "play"; tint: Theme.dark ? "#56D364" : "#1A7F37"
                                 onClicked: Debugger.state === "running" ? Debugger.pause() : Debugger.resume() }
                        DbgBtn { icon: "stepOver"; enabled: Debugger.state === "stopped"; onClicked: Debugger.next() }
                        DbgBtn { icon: "stepIn"; enabled: Debugger.state === "stopped"; onClicked: Debugger.stepIn() }
                        DbgBtn { icon: "stepOut"; enabled: Debugger.state === "stopped"; onClicked: Debugger.stepOut() }
                        DbgBtn { icon: "stop"; tint: Theme.danger; onClicked: Debugger.stop() }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            leftPadding: 6; rightPadding: 4
                            text: Debugger.state === "stopped" ? "Zatrzymany" : Debugger.state === "running" ? "Działa" : "Start…"
                            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                        }
                    }
                }

                // Wdrożenie i GitHub
                DeployView {
                    id: deployView
                    parent: pane
                    x: 0; y: editorArea.y
                    width: pane.width; height: status.y - y
                    z: 50
                    root: Project.root
                    onDeploy: (c) => win.runDeploy(c)
                    onOpenSecrets: { deployView.shown = false; secretsView.open(); }
                    onInstallRequested: (pkg) => win.envTask("Kontener: pakiety", ProjectEnv.installCommand([pkg]))
                    onClosed: if (win.cur) win.cur.focusEditor()
                }

                // Sekrety projektu
                SecretsView {
                    id: secretsView
                    parent: pane
                    x: 0; y: editorArea.y
                    width: pane.width; height: status.y - y
                    z: 50
                    onClosed: if (win.cur) win.cur.focusEditor()
                }

                // Ustawienia (Ctrl+,)
                SettingsView {
                    id: settingsView
                    // Nad edytorem i terminalem, aż do paska stanu
                    parent: pane
                    x: 0; y: editorArea.y
                    width: pane.width; height: status.y - y
                    z: 50
                    prefs: prefs
                    onClosed: if (win.cur) win.cur.focusEditor()
                }

                // Podgląd różnic (z widoku zmian)
                DiffView {
                    id: diffView
                    anchors.fill: parent
                    anchors.topMargin: banner.height
                    z: 8
                    fontSize: prefs.fontSize - 0.5
                    onOpenFile: (path) => win.openFile(path)
                    onRestoreVersion: (path, hash, rel) => win.restoreVersion(path, hash, rel)
                    sideBySide: prefs.diffSideBySide
                    onSideBySideChanged: prefs.diffSideBySide = sideBySide
                    onAgentAccept: (path) => agentPanel.accept(path)
                    onAgentReject: (path) => agentPanel.reject(path)
                    onDiscardHunk: (path, index) => win.confirm = { kind: "discard", paths: [path], name: Project.fileName(path), hunk: index }
                }

                // Bez otwartych plików — znak programu i skróty
                Column {
                    visible: tabs.count === 0
                    anchors.centerIn: parent
                    spacing: 10
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; d: Icons.code; size: 64; stroke: 1.2; color: Theme.text2; opacity: 0.35 }
                    Item { width: 1; height: 8 }
                    Repeater {
                        model: [["Szybkie otwieranie pliku", "Ctrl+P"], ["Wszystkie polecenia", "Ctrl+Shift+P"], ["Szukaj w projekcie", "Ctrl+Shift+F"],
                                ["Nowy plik", "Ctrl+N"], ["Terminal", "Ctrl+`"]]
                        delegate: Item {
                            id: hint
                            required property var modelData
                            width: 340; height: 24
                            Text { anchors.right: parent.horizontalCenter; anchors.rightMargin: 10; text: hint.modelData[0]; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                            Rectangle {
                                anchors.left: parent.horizontalCenter; anchors.leftMargin: 4
                                width: keyT.implicitWidth + 14; height: 22; radius: 6
                                color: Theme.fill
                                Text { id: keyT; anchors.centerIn: parent; text: hint.modelData[1]; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
                            }
                        }
                    }
                }

                // Szukaj i zamień w pliku
                Rectangle {
                    id: findBar
                    property bool shown: false
                    property bool replace: false
                    anchors.right: parent.right; anchors.rightMargin: 22
                    y: shown ? banner.height + 8 : -height - 4
                    visible: shown || y > -height
                    // Bez animacji w rendererze programowym (zostawiał ślady ikon w poprzednim położeniu)
                    Behavior on y { enabled: findBar.GraphicsInfo.api !== GraphicsInfo.Software; NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
                    z: 10
                    width: 430; height: replace ? 92 : 46; radius: 14
                    color: Theme.surface
                    border.width: 1; border.color: Theme.edge
                    Column {
                        x: 8; y: 6
                        width: parent.width - 16
                        spacing: 4
                        Item {
                            width: parent.width; height: 34
                            Icon { x: 8; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 15; color: Theme.text2 }
                            TextInput {
                                id: findField
                                x: 32; width: parent.width - 32 - findTools.width - 8
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                                font.family: Theme.font; font.pixelSize: 13
                                clip: true
                                onTextChanged: win.findAll()
                                Keys.onReturnPressed: (e) => win.select(win.matchIndex + ((e.modifiers & Qt.ShiftModifier) ? -1 : 1))
                                Keys.onEnterPressed: win.select(win.matchIndex + 1)
                                Keys.onTabPressed: if (findBar.replace) replaceField.forceActiveFocus()
                                Text { anchors.verticalCenter: parent.verticalCenter; visible: !findField.text; text: "Znajdź"; color: Theme.text2; font: findField.font }
                            }
                            Row {
                                id: findTools
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !!findField.text
                                    rightPadding: 6
                                    text: win.matches.length === 0 ? "Brak" : (win.matchIndex + 1) + " z " + Project.number(win.matches.length)
                                    color: win.matches.length === 0 ? Theme.danger : Theme.text2
                                    font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 }
                                }
                                SmallBtn { text: "Aa"; on: win.matchCase; onClicked: { win.matchCase = !win.matchCase; win.findAll(); } }
                                SmallBtn { icon: "up"; onClicked: win.select(win.matchIndex - 1) }
                                SmallBtn { icon: "chevronDown"; onClicked: win.select(win.matchIndex + 1) }
                                SmallBtn { icon: findBar.replace ? "up" : "pencil"; onClicked: findBar.replace = !findBar.replace }
                                SmallBtn { icon: "close"; onClicked: win.closeFind() }
                            }
                        }
                        Item {
                            visible: findBar.replace
                            width: parent.width; height: 38
                            Rectangle {
                                width: parent.width - replaceBtns.width - 8; height: 34; radius: 10
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.fill
                                TextInput {
                                    id: replaceField
                                    x: 12; width: parent.width - 24
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                                    font.family: Theme.font; font.pixelSize: 13
                                    clip: true
                                    Keys.onReturnPressed: win.replaceOne()
                                    Keys.onTabPressed: findField.forceActiveFocus()
                                    Text { anchors.verticalCenter: parent.verticalCenter; visible: !replaceField.text; text: "Zamień na"; color: Theme.text2; font: replaceField.font }
                                }
                            }
                            Row {
                                id: replaceBtns
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Pill { text: "Zamień"; onClicked: win.replaceOne() }
                                Pill { text: "Wszystkie"; onClicked: win.replaceAll() }
                            }
                        }
                    }
                }
            }

            // Podgląd strony obok edytora (szerokość do przeciągnięcia)
            PreviewPane {
                id: preview
                x: editorArea.width
                y: editorArea.y
                width: Math.max(320, Math.min(parent.width - 360, parent.width * prefs.previewWidth))
                height: editorArea.height
                onClosed: if (win.cur) win.cur.focusEditor()
                Rectangle { width: 1; height: parent.height; color: Theme.line }
                MouseArea {
                    width: 8; height: parent.height; x: -4
                    cursorShape: Qt.SplitHCursor
                    property real startX
                    onPressed: (e) => startX = e.x
                    onPositionChanged: (e) => { if (pressed) prefs.previewWidth = Math.max(0.2, Math.min(0.8, (preview.width - (e.x - startX)) / preview.parent.width)); }
                }
            }

            // Agent po prawej (Ctrl+Shift+I) — od paska kart do paska stanu
            AgentPanel {
                id: agentPanel
                x: parent.width - width
                y: editorArea.y
                width: Math.max(320, Math.min(520, parent.width * 0.3))
                height: status.y - y
                z: 5
                root: Project.root
                fileRel: win.curPath ? Project.relative(win.curPath) : ""
                selectionLines: { win.revision; return win.cur && win.cur.edit.selectedText ? win.cur.edit.selectedText.split("\u2029").length : 0; }
                problemCount: Lsp.errorCount + Lsp.warningCount + Tasks.errorCount + Tasks.warningCount
                buildContext: (o) => win.agentContext(o)
                fileText: (abs) => win.agentFileText(abs)
                onApplyEdit: (path, text) => win.applyAgentEdit(path, text)
                onShowEdit: (path, title, rows) => diffView.openRows(path, title, rows)
                onOpenPath: (path) => win.openFile(path)
                onClosed: if (win.cur) win.cur.focusEditor()
            }

            // Terminal
            TerminalPanel {
                id: terminalPanel
                visible: win.terminalShown
                y: editorArea.y + editorArea.height
                width: parent.width - (agentPanel.shown ? agentPanel.width : 0)
                height: win.terminalMax ? parent.height - editorArea.y - status.height : Math.max(120, Math.min(prefs.terminalHeight, parent.height - 200))
                dir: Project.root
                maximized: win.terminalMax
                onHideRequested: { win.terminalShown = false; win.terminalMax = false; if (win.cur) win.cur.focusEditor(); }
                onMaximizeRequested: win.terminalMax = !win.terminalMax
                onOpenProblem: (path, line, col) => win.openFile(path, { line: line, col: col, length: 0 })
                onOpenReference: (path, line, col, length) => win.openFile(path, { line: line, col: col, length: length })
                onOpenLocation: (path, line, col) => win.openFile(path, { line: line, col: col, length: 0 })
                onOpenFrame: (i) => Debugger.selectFrame(i)
                onOpenPreview: (url) => preview.open(url)
                MouseArea {
                    width: parent.width; height: 6; y: -3
                    z: 5
                    cursorShape: Qt.SplitVCursor
                    enabled: !win.terminalMax
                    property real startY: 0
                    property real startH: 0
                    onPressed: (e) => { startY = mapToItem(frame, 0, e.y).y; startH = terminalPanel.height; }
                    onPositionChanged: (e) => { if (pressed) prefs.terminalHeight = Math.max(120, Math.min(pane.height - 200, startH - (mapToItem(frame, 0, e.y).y - startY))); }
                }
            }

            // Pasek stanu
            Item {
                id: status
                anchors.bottom: parent.bottom
                width: parent.width; height: 30
                Rectangle { width: parent.width; height: 1; color: Theme.line }
                Row {
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    StatusBtn {
                        visible: Project.isGit
                        icon: "gitBranch"
                        text: Project.branch + (Project.ahead || Project.behind ? "  " + (Project.behind ? "↓" + Project.behind : "") + (Project.ahead ? "↑" + Project.ahead : "") : "")
                        onClicked: palette.openBranches("checkout")
                    }
                    StatusBtn {
                        visible: Project.isGit && Project.changes.length > 0
                        icon: "pencil"
                        text: Project.changes.length
                        onClicked: win.showView(2)
                    }
                    StatusBtn {
                        visible: Tasks.running || (!!Tasks.title && Tasks.exitCode !== 0 && Tasks.exitCode !== -1)
                        icon: Tasks.running ? "reload" : "close"
                        text: Tasks.title + (Tasks.running ? "…" : "")
                        onClicked: { win.terminalShown = true; terminalPanel.tab = 3; }
                    }
                    StatusBtn {
                        icon: "alertCircle"
                        text: (Lsp.errorCount + Tasks.errorCount) + "   ⚠ " + (Lsp.warningCount + Tasks.warningCount)
                        onClicked: win.showProblems()
                    }
                    StatusBtn {
                        visible: !!win.cur && win.cur.gutter.changeCount > 0
                        text: win.cur ? "zmiany w pliku: " + win.cur.gutter.changeCount : ""
                        onClicked: win.cur.nextChange(false)
                    }
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    visible: !!win.cur
                    StatusBtn {
                        visible: !!win.cur && win.cur.cursorCount > 1
                        icon: "cursor"
                        text: !win.cur ? "" : win.cur.cursorCount + (win.cur.cursorCount % 10 >= 2 && win.cur.cursorCount % 10 <= 4 && (win.cur.cursorCount % 100 < 10 || win.cur.cursorCount % 100 >= 20) ? " kursory" : " kursorów")
                        onClicked: win.cur.clearExtras()
                    }
                    StatusBtn {
                        text: !win.cur ? "" : (win.cur.edit.selectedText ? "(zaznaczono " + Project.number(win.cur.edit.selectedText.length) + ")  " : "")
                                             + "Wiersz " + Project.number(win.cur.lineCol.y + 1) + ", kol. " + (win.cur.lineCol.x + 1)
                        onClicked: palette.open(":")
                    }
                    StatusBtn {
                        id: indentBtn
                        text: win.cur ? (win.cur.indentTabs ? "Tabulatory" : "Spacje: " + win.cur.indentSize) : ""
                        onClicked: win.showStatusMenu("indent", indentBtn)
                    }
                    StatusBtn {
                        id: encBtn
                        text: tabs.count && win.revision >= 0 ? tabs.get(win.current).encoding : ""
                        onClicked: win.showStatusMenu("enc", encBtn)
                    }
                    StatusBtn {
                        id: eolBtn
                        text: tabs.count && win.revision >= 0 ? (tabs.get(win.current).eol === "\r\n" ? "CRLF" : "LF") : ""
                        onClicked: win.showStatusMenu("eol", eolBtn)
                    }
                    // Agent pracuje, a panel jest schowany — co robi
                    StatusBtn {
                        visible: !agentPanel.shown && !!agentPanel.statusText
                        icon: "sparkles"
                        text: agentPanel.statusText
                        onClicked: agentPanel.open()
                    }
                    // Sekrety projektu (gdy są albo gdy w projekcie leży .env z wartościami)
                    StatusBtn {
                        visible: win.hasProject && Secrets.names.length > 0
                        icon: "key"
                        text: Secrets.names.length
                        onClicked: secretsView.open()
                    }
                    // Środowisko projektu: kontener albo system
                    StatusBtn {
                        id: envBtn
                        visible: win.hasProject && (ProjectEnv.toolAvailable() || ProjectEnv.state !== "off")
                        icon: ProjectEnv.state === "ready" ? "box" : ProjectEnv.state === "off" ? "monitor" : "alertCircle"
                        text: ProjectEnv.state === "ready" ? ProjectEnv.container : ProjectEnv.state === "none" ? "Kontener do założenia"
                            : ProjectEnv.state === "missing" ? "Brak toolbox" : "System"
                        onClicked: win.showEnvMenu()
                    }
                    StatusBtn { text: win.cur ? win.cur.language : "" }
                    // Serwer języka: nazwa (działa), „uruchamia się” albo podpowiedź, co doinstalować
                    StatusBtn {
                        visible: !!win.cur && !!win.cur.serverInfo.id
                        icon: !win.cur ? "" : win.cur.serverInfo.running ? "check" : win.cur.serverInfo.available && !win.cur.serverInfo.failed ? "clock" : "info"
                        text: !win.cur ? "" : win.cur.serverInfo.running ? win.cur.serverInfo.name
                            : win.cur.serverInfo.available && !win.cur.serverInfo.failed ? win.cur.serverInfo.name + "…" : "Brak " + (win.cur.serverInfo.name || "")
                        onClicked: win.lspHint()
                    }
                    StatusBtn {
                        visible: tabs.count > 0 && win.revision >= 0 && tabs.get(win.current).readOnly
                        text: "Tylko do odczytu"
                    }
                }
            }

            Palette {
                id: palette
                commands: win.commands
                recentPaths: { win.revision; return win.openPaths(); }
                onFileChosen: (path) => win.openFile(path)
                onCommandChosen: (action) => win.run(action)
                onLineChosen: (line) => { if (win.cur) win.cur.goToLine(line); }
                onBranchChosen: (mode, name, remote, isNew) => win.branchAction(mode, name, remote, isNew)
                onTaskChosen: (task) => win.runTask(task)
                onSymbolQuery: (mode, q) => win.symbolQuery(mode, q)
                onSymbolChosen: (path, line, col) => win.openFile(path || win.curPath, { line: line, col: col, length: 0 })
                onClosed: if (win.cur) win.cur.focusEditor()
            }
            NameBox {
                id: nameBox
                onClosed: if (win.cur) win.cur.focusEditor()
            }
        }

        // ——— Pasek boczny ———
        Item {
            id: sidebar
            visible: win.hasProject && prefs.sidebar
            width: visible ? Math.max(200, Math.min(prefs.sidebarWidth, frame.width * 0.5)) : 0
            height: parent.height

            Item {
                id: sideTop
                width: parent.width; height: 52
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }
                // Przełącznik widoków (jak nawigator w Xcode): pliki, szukaj, zmiany
                Row {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    ViewBtn { icon: "files"; view: 0 }
                    ViewBtn { icon: "search"; view: 1 }
                    ViewBtn { icon: "gitBranch"; view: 2; badge: Project.changes.length }
                    ViewBtn { icon: "clock"; view: 3; visible: Project.isGit }
                }
            }

            // Pliki
            Item {
                id: explorer
                visible: win.sidebarView === 0
                y: sideTop.height
                width: parent.width; height: parent.height - y

                Item {
                    id: explorerHead
                    width: parent.width; height: 34
                    HoverButton {
                        id: projectBtn
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        width: projRow.implicitWidth + 16; height: 28; radius: 7
                        onClicked: win.showProjectMenu()
                        Row {
                            id: projRow
                            x: 8; anchors.verticalCenter: parent.verticalCenter
                            spacing: 5
                            Text {
                                width: Math.min(implicitWidth, explorerHead.width - 160)
                                elide: Text.ElideRight
                                text: Project.name.toUpperCase()
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.5
                            }
                            Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.chevronDown; size: 12; stroke: 2; color: Theme.text2 }
                        }
                    }
                    Row {
                        id: headTools
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        visible: explorerHover.hovered
                        SideBtn { icon: "filePlus"; onClicked: win.newFile(Project.root) }
                        SideBtn { icon: "folderPlus"; onClicked: win.newFolder(Project.root) }
                        SideBtn { icon: "reload"; onClicked: { Project.tree.refresh(); Project.refreshGit(); } }
                        SideBtn { icon: "minus"; onClicked: Project.tree.collapseAll() }
                    }
                }
                HoverHandler { id: explorerHover }

                ListView {
                    id: treeList
                    y: explorerHead.height
                    width: parent.width; height: parent.height - y
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: Project.tree
                    reuseItems: true
                    delegate: TreeRow {}
                    // Klik w puste miejsce pod drzewem — menu folderu projektu
                    footer: Item {
                        width: treeList.width; height: 80
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: (e) => { const p = mapToItem(frame, e.x, e.y); win.showTreeMenu(Project.root, true, p.x, p.y); }
                        }
                    }
                }
            }

            SearchView {
                id: searchView
                buffers: () => {
                    const b = {};
                    for (let i = 0; i < tabs.count; ++i) if (win.page(i) && win.page(i).modified) b[tabs.get(i).path] = win.page(i).edit.text;
                    return b;
                }
                visible: win.sidebarView === 1
                y: sideTop.height
                width: parent.width; height: parent.height - y
                onOpenMatch: (path, line, col, length) => win.openFile(path, { preview: true, line: line, col: col, length: length })
                onReplaceAllRequested: {
                    const files = Project.results.length;
                    win.confirm = { kind: "replace", count: Project.resultCount, files: files, paths: Project.results.map(r => r.path) };
                }
                onReplaceFileRequested: (path) => win.replaceInPaths([path])
                onReplaceMatchRequested: (path, line, col) => win.replaceMatch(path, line, col)
            }
            HistoryView {
                id: historyView
                visible: win.sidebarView === 3
                y: sideTop.height
                width: parent.width; height: parent.height - y
                path: win.curPath
                onShowDiff: (path, rel, hash, title) => diffView.openCommit(path, rel, hash, title)
            }

            ChangesView {
                id: changesView
                visible: win.sidebarView === 2
                y: sideTop.height
                width: parent.width; height: parent.height - y
                onOpenFile: (path) => win.openFile(path, { preview: true })
                onShowDiff: (path, staged) => diffView.open(path, staged)
                onDiscardRequested: (paths) => win.confirm = { kind: "discard", paths: paths, name: Project.fileName(paths[0] || "") }
                onPickBranch: palette.openBranches("checkout")
                onShowCommit: (hash) => win.showCommit(hash)
            }

            // Zmiana szerokości paska
            MouseArea {
                x: parent.width - 4; width: 8; height: parent.height
                z: 5
                cursorShape: Qt.SplitHCursor
                property real startX: 0
                property real startW: 0
                onPressed: (e) => { startX = mapToItem(frame, e.x, 0).x; startW = sidebar.width; }
                onPositionChanged: (e) => { if (pressed) prefs.sidebarWidth = Math.max(200, Math.min(frame.width * 0.5, startW + mapToItem(frame, e.x, 0).x - startX)); }
            }
        }

        // ——— Okno startowe (bez folderu) ———
        StartPage {
            anchors.fill: parent
            visible: !win.hasProject
            radius: win.r
            onOpenFolder: folderDialog.open()
            onOpenRecent: (path) => win.openFolder(path)
            onNewApp: newAppView.open()
        }

        // Nowa aplikacja z szablonu — nad całym oknem (działa też bez otwartego projektu)
        NewAppView {
            id: newAppView
            anchors.fill: parent
            anchors.margins: 1
            radius: win.r
            z: 700
            onCreated: (r, container) => win.startFromTemplate(r, container)
        }
        Item {
            visible: !win.hasProject
            width: parent.width; height: 52
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
            WindowButtons { window: win; anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter }
        }

        // ——— Pytanie o niezapisane zmiany ———
        Item {
            anchors.fill: parent
            visible: !!win.confirm
            z: 600
            Rectangle { anchors.fill: parent; radius: win.r; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.25) }
            MouseArea { anchors.fill: parent; onClicked: win.confirm = null }
            Rectangle {
                anchors.centerIn: parent
                width: 440; height: dlgCol.implicitHeight + 44
                radius: 22
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                MouseArea { anchors.fill: parent }
                Column {
                    id: dlgCol
                    x: 24; y: 22; width: parent.width - 48
                    spacing: 8
                    Text {
                        width: parent.width; wrapMode: Text.Wrap
                        text: !win.confirm ? "" : win.confirm.kind === "envRemove" ? "Usunąć kontener „" + win.confirm.name + "”?"
                            : win.confirm.kind === "replace"
                              ? "Zamienić " + win.confirm.count + " wystąpień w " + win.confirm.files + (win.confirm.files === 1 ? " pliku?" : " plikach?")
                            : win.confirm.kind === "discard"
                              ? (win.confirm.hunk !== undefined ? "Odrzucić ten fragment zmian w „" + win.confirm.name + "”?"
                                 : win.confirm.paths.length === 1 ? "Odrzucić zmiany w „" + win.confirm.name + "”?" : "Odrzucić zmiany w " + win.confirm.paths.length + " plikach?")
                            : win.confirm.kind === "tab" ? "Zapisać zmiany w „" + win.confirm.name + "”?"
                            : win.confirm.count === 1 ? "Zapisać zmiany w 1 pliku?" : "Zapisać zmiany w " + win.confirm.count + " plikach?"
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width; wrapMode: Text.Wrap
                        text: win.confirm && win.confirm.kind === "envRemove" ? "Zainstalowane w nim programy znikną. Pliki projektu zostają (są w katalogu domowym)."
                            : win.confirm && win.confirm.kind === "replace" ? "„" + searchView.query + "” → „" + searchView.replacement + "”. Otwarte karty zmienią się w edytorze (do cofnięcia), pozostałe pliki zostaną zapisane od razu."
                            : win.confirm && win.confirm.kind === "discard" ? "Pliki wrócą do ostatniej zatwierdzonej wersji — tego nie da się cofnąć. Nowe pliki trafią do Kosza."
                                                                           : "Jeśli nie zapiszesz, zmiany przepadną."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                    }
                    Item { width: 1; height: 10 }
                    Item {
                        width: parent.width; height: 34
                        Pill {
                            visible: !!win.confirm && ["discard", "replace", "envRemove"].indexOf(win.confirm.kind) < 0
                            text: "Nie zapisuj"; danger: true
                            onClicked: {
                                const c = win.confirm;
                                win.confirm = null;
                                if (c.kind === "tab") { win.closeTab(c.index, true); return; }
                                for (let i = 0; i < tabs.count; ++i) win.page(i).markSaved();
                                c.then();
                            }
                        }
                        Row {
                            anchors.right: parent.right
                            spacing: 8
                            Pill { text: "Anuluj"; onClicked: win.confirm = null }
                            Pill {
                                visible: !!win.confirm && win.confirm.kind === "discard"
                                text: "Odrzuć zmiany"; danger: true
                                onClicked: {
                                    const c = win.confirm;
                                    win.confirm = null;
                                    if (c.hunk !== undefined) Project.applyHunk(c.paths[0], false, c.hunk, "discard");
                                    else win.discardPaths(c.paths);
                                }
                            }
                            Pill {
                                visible: !!win.confirm && win.confirm.kind === "envRemove"
                                text: "Usuń kontener"; danger: true
                                onClicked: { win.confirm = null; const cmd = ProjectEnv.removeCommand(); ProjectEnv.useContainer(false); win.envTask("Kontener: usuwanie", cmd); }
                            }
                            Pill {
                                visible: !!win.confirm && win.confirm.kind === "replace"
                                text: "Zamień wszystko"; primary: true
                                onClicked: { const c = win.confirm; win.confirm = null; win.replaceInPaths(c.paths); }
                            }
                            Pill {
                                visible: !win.confirm || ["discard", "replace", "envRemove"].indexOf(win.confirm.kind) < 0
                                text: win.confirm && win.confirm.kind === "all" ? "Zapisz wszystkie" : "Zapisz"; primary: true
                                onClicked: {
                                    const c = win.confirm;
                                    win.confirm = null;
                                    if (c.kind === "tab") { const uid = tabs.get(c.index).uid; win.save(c.index, () => win.closeTab(win.indexOfUid(uid), true)); return; }
                                    win.saveAll();
                                    if (win.dirtyCount() === 0) c.then();
                                }
                            }
                        }
                    }
                }
            }
        }

        // Komunikat na dole
        Rectangle {
            id: toastBox
            property bool shown: false
            property alias text: toastText.text
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - (shown ? height + 44 : 0)
            opacity: shown ? 1 : 0
            z: 700
            width: toastText.implicitWidth + 36; height: 38; radius: 19
            color: Theme.dark ? "#ECEEF3" : "#1E2027"
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Text { id: toastText; anchors.centerIn: parent; color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
            Timer { id: toastTimer; interval: 2600; onTriggered: toastBox.shown = false }
        }

        ContextMenu {
            id: menu
            property int tab: -1
            property string path
            onTriggered: (a) => win.run(a)
        }
    }

    // ——— Elementy ———
    component TreeRow: Item {
        id: row
        required property int index
        required property string path
        required property string name
        required property int depth
        required property bool isDir
        required property bool expanded
        required property string git
        required property bool ignored
        readonly property bool active: !isDir && path === win.curPath
        width: ListView.view.width; height: 26
        Rectangle {
            anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
            radius: 6
            color: row.active ? Theme.accentSoft : rowArea.containsMouse ? Theme.hover : "transparent"
        }
        Icon {
            visible: row.isDir
            x: 12 + row.depth * 14; anchors.verticalCenter: parent.verticalCenter
            d: row.expanded ? Icons.chevronDown : Icons.chevronRight; size: 12; stroke: 2; color: Theme.text2
        }
        FileIcon {
            id: ficon
            x: 28 + row.depth * 14; anchors.verticalCenter: parent.verticalCenter
            name: row.name; isDir: row.isDir; expanded: row.expanded; size: 16
            opacity: row.ignored ? 0.5 : 1
        }
        Text {
            anchors.left: ficon.right; anchors.leftMargin: 7
            anchors.right: gitMark.left; anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: row.name
            color: row.git === "M" ? (Theme.dark ? "#E3B341" : "#9A6700")
                 : row.git === "U" || row.git === "A" ? (Theme.dark ? "#56D364" : "#1A7F37")
                 : row.git === "C" || row.git === "D" ? Theme.danger
                 : Theme.text
            opacity: row.ignored ? 0.5 : 1
            font.family: Theme.font; font.pixelSize: 13; font.weight: row.active ? Font.Medium : Font.Normal
        }
        // Litera stanu gita (plik) albo kropka (folder ze zmianami)
        Item {
            id: gitMark
            anchors.right: parent.right; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: row.git ? 12 : 0; height: 14
            Text {
                visible: !row.isDir && !!row.git
                anchors.centerIn: parent
                text: row.git
                color: row.git === "M" ? (Theme.dark ? "#E3B341" : "#9A6700") : row.git === "C" || row.git === "D" ? Theme.danger : (Theme.dark ? "#56D364" : "#1A7F37")
                font.family: "JetBrains Mono"; font.pixelSize: 11; font.weight: Font.Bold
            }
            Rectangle {
                visible: row.isDir && !!row.git
                anchors.centerIn: parent
                width: 6; height: 6; radius: 3
                color: row.git === "U" ? (Theme.dark ? "#56D364" : "#1A7F37") : (Theme.dark ? "#E3B341" : "#9A6700")
            }
        }
        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (e) => {
                if (e.button === Qt.RightButton) { const p = mapToItem(frame, e.x, e.y); win.showTreeMenu(row.path, row.isDir, p.x, p.y); return; }
                if (row.isDir) Project.tree.toggle(row.index);
                else win.openFile(row.path, { preview: true });
            }
            onDoubleClicked: if (!row.isDir) win.openFile(row.path, { preview: false })
        }
    }
    component DbgBtn: HoverButton {
        id: db
        property string icon
        property color tint: Theme.accentText
        width: 30; height: 28; radius: 7
        opacity: enabled ? 1 : 0.35
        Icon { anchors.centerIn: parent; d: Icons[db.icon] || ""; size: 15; stroke: 2; color: db.tint }
    }
    component TabButton: Rectangle {
        id: tab
        required property int index
        required property string path
        required property bool preview
        required property int group
        property int shownGroup: 0
        visible: group === shownGroup
        // Aktywna w swojej grupie; wyraźniej — w grupie z fokusem
        readonly property bool active: { win.revision; return index === win.groupActive(group); }
        readonly property bool focused: active && (!win.split || group === win.focusGroup)
        readonly property bool dirty: { win.revision; const p = win.page(index); return !!p && p.modified; }
        width: Math.min(240, tabLabel.implicitWidth + 70); height: 34
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        radius: 9
        color: focused ? Theme.fill : active ? Qt.rgba(Theme.fill.r, Theme.fill.g, Theme.fill.b, Theme.fill.a * 0.5) : (tabArea.containsMouse ? Theme.hover : "transparent")
        FileIcon { x: 11; anchors.verticalCenter: parent.verticalCenter; name: Project.fileName(tab.path); size: 14 }
        Text {
            id: tabLabel
            x: 32; width: parent.width - 32 - 30
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideMiddle
            text: Project.fileName(tab.path)
            color: tab.active ? Theme.text : Theme.text2
            font.family: Theme.font; font.pixelSize: 13; font.weight: tab.active ? Font.Medium : Font.Normal
            font.italic: tab.preview
        }
        MouseArea {
            id: tabArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onClicked: (e) => {
                if (e.button === Qt.MiddleButton) { win.closeTab(tab.index); return; }
                if (e.button === Qt.RightButton) {
                    const p = mapToItem(frame, e.x, e.y);
                    menu.tab = tab.index;
                    menu.openAt(p.x, p.y, [
                        { label: "Zamknij", icon: "close", shortcut: "Ctrl+W", action: "tab:close" },
                        { label: "Zamknij pozostałe", icon: "close", action: "tab:others", enabled: tabs.count > 1 },
                        { label: "Zamknij karty po prawej", icon: "close", action: "tab:right", enabled: tab.index < tabs.count - 1 },
                        { separator: true },
                        { label: "Podziel w prawo", icon: "sidebar", shortcut: "Ctrl+\\", action: "tab:split" },
                        { label: tab.group === 0 ? "Przenieś do prawej grupy" : "Przenieś do lewej grupy", icon: "forward", action: "tab:move" },
                        { separator: true },
                        { label: "Pokaż w drzewie plików", icon: "files", action: "tab:reveal" },
                        { label: "Historia pliku", icon: "clock", action: "tab:history" },
                        { label: "Kopiuj ścieżkę względną", icon: "copy", action: "tab:copy" }
                    ]);
                    return;
                }
                win.activate(tab.index);
            }
            onDoubleClicked: win.pin(tab.index)
        }
        // Kropka — niezapisane zmiany; pod kursorem zamienia się w „×”
        HoverButton {
            anchors.right: parent.right; anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 22; height: 22; radius: 7
            visible: tab.dirty || tabArea.containsMouse || hovered || tab.active
            onClicked: win.closeTab(tab.index)
            Rectangle {
                visible: tab.dirty && !parent.hovered && !tabArea.containsMouse
                anchors.centerIn: parent
                width: 8; height: 8; radius: 4
                color: Theme.text
            }
            Icon {
                visible: !tab.dirty || parent.hovered || tabArea.containsMouse
                anchors.centerIn: parent; d: Icons.close; size: 12; stroke: 2; color: Theme.text2
            }
        }
    }
    component ViewBtn: HoverButton {
        id: vb
        property string icon
        property int view
        property int badge: 0
        readonly property bool on: prefs.sidebar && win.sidebarView === view
        width: 36; height: 32; radius: 8
        baseColor: on ? Theme.fill : "transparent"
        onClicked: win.showView(view)
        Icon { anchors.centerIn: parent; d: Icons[vb.icon] || ""; size: 17; color: vb.on ? Theme.accentText : Theme.text2 }
        Rectangle {
            visible: vb.badge > 0
            x: parent.width - width + 2; y: 1
            width: Math.max(16, badgeText.implicitWidth + 8); height: 16; radius: 8
            color: Theme.accent
            Text { id: badgeText; anchors.centerIn: parent; text: vb.badge > 99 ? "99+" : vb.badge; color: "white"; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold }
        }
    }
    component SideBtn: HoverButton {
        id: sbtn
        property string icon
        width: 26; height: 26; radius: 6
        Icon { anchors.centerIn: parent; d: Icons[sbtn.icon] || ""; size: 14; color: Theme.text2 }
    }
    component SmallBtn: HoverButton {
        id: sb
        property string icon
        property string text
        property bool on: false
        width: 28; height: 28; radius: 7
        baseColor: on ? Theme.accentSoft : "transparent"
        Icon { visible: !!sb.icon; anchors.centerIn: parent; d: Icons[sb.icon] || ""; size: 14; color: Theme.text }
        Text { visible: !!sb.text; anchors.centerIn: parent; text: sb.text; color: sb.on ? Theme.accentText : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
    }
    component Pill: HoverButton {
        id: pill
        property string text
        property bool danger: false
        property bool primary: false
        width: pillText.implicitWidth + 26; height: 32; radius: 16
        baseColor: danger ? "transparent" : primary ? Theme.accent : Theme.fill
        color: hovered ? (primary ? Qt.darker(Theme.accent, 1.1) : Theme.hover) : baseColor
        Text { id: pillText; anchors.centerIn: parent; text: pill.text; color: pill.primary ? "white" : pill.danger ? Theme.danger : Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
    }
    component StatusBtn: HoverButton {
        id: stb
        property string text
        property string icon
        width: stbRow.implicitWidth + 14; height: 22; radius: 6
        Row {
            id: stbRow
            anchors.centerIn: parent
            spacing: 5
            Icon { visible: !!stb.icon; anchors.verticalCenter: parent.verticalCenter; d: Icons[stb.icon] || ""; size: 12; stroke: 2; color: Theme.text2 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: stb.text; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 } }
        }
    }
}
