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
        current = i;
        revision++;
        Qt.callLater(() => { if (win.cur) win.cur.focusEditor(); });
        if (findBar.shown) Qt.callLater(findAll);
    }
    // Pojedynczy klik w drzewie otwiera kartę podglądu (kursywa), którą zastępuje następny plik — jak w VS Code;
    // edycja albo podwójny klik zostawia kartę na stałe.
    function openFile(p, opts) {
        opts = opts || {};
        p = Project.toPath(p);
        let i = indexOfPath(p);
        if (i < 0) {
            const res = Project.load(p);
            if (!res.ok) { toast(res.error); return; }
            let at = tabs.count ? current + 1 : 0;
            if (opts.preview) {
                for (let k = 0; k < tabs.count; ++k)
                    if (tabs.get(k).preview && !page(k).modified) { tabs.remove(k); revision++; at = k; break; }
            }
            const uid = ++uidSeq;
            pendingText[uid] = res.text;
            pendingCursor[uid] = 0;
            tabs.insert(Math.min(at, tabs.count), { uid: uid, path: p, preview: !!opts.preview, encoding: res.encoding, eol: res.eol,
                                                   readOnly: res.readOnly, changedOnDisk: false });
            revision++;
            i = indexOfPath(p);
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
    function save(i, then) {
        if (i < 0 || i >= tabs.count) return;
        const t = tabs.get(i), p = page(i);
        lastSave[t.path] = Date.now();
        if (Project.save(t.path, p.edit.text, t.encoding, t.eol)) {
            p.markSaved();
            tabs.setProperty(i, "changedOnDisk", false);
            pin(i);
            revision++;
            if (then) then();
        }
    }
    function saveAll() { for (let i = 0; i < tabs.count; ++i) if (page(i).modified) save(i); }
    function dirtyCount() { let n = 0; for (let i = 0; i < tabs.count; ++i) if (page(i) && page(i).modified) n++; return n; }

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
        tabs.remove(i);
        revision++;
        current = Math.max(0, Math.min(current > i ? current - 1 : current, tabs.count - 1));
        revision++;
        if (tabs.count) activate(current);
        watchAll();
        Qt.callLater(saveSession);
    }
    function closeAllTabs() { while (tabs.count) { tabs.remove(tabs.count - 1); } revision++; current = 0; watchAll(); }
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
        const list = Project.sessionTabs();
        list.forEach(p => openFile(p));
        if (tabs.count) activate(Math.min(Project.sessionCurrent(), tabs.count - 1));
        const l = Project.sessionLayout();
        sidebarView = l.sidebarView || 0;
        terminalShown = !!l.terminal;
    }
    function saveSession() {
        if (!hasProject) return;
        const list = [];
        for (let i = 0; i < tabs.count; ++i) if (!tabs.get(i).preview) list.push(tabs.get(i).path);
        Project.saveSession(list, Math.max(0, list.indexOf(curPath)), terminalShown, sidebarView);
    }
    Timer { interval: 5000; running: win.hasProject; repeat: true; onTriggered: win.saveSession() }
    // Git w tle: co kilka sekund, gdy okno jest aktywne, i po powrocie do okna
    Timer { interval: 4000; running: win.hasProject && win.active; repeat: true; onTriggered: Project.refreshGit() }
    onActiveChanged: if (active && hasProject) Project.refreshGit()
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
    property int sidebarView: 0          // 0 pliki, 1 szukaj, 2 zmiany
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
        if (terminalShown && terminalPanel.term && terminalPanel.term.activeFocus) { terminalShown = false; if (cur) cur.focusEditor(); return; }
        terminalShown = true;
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
        { label: "Przełącz komentarz", shortcut: "Ctrl+/", action: "comment", icon: "code" },
        { label: "Duplikuj wiersz", shortcut: "Shift+Alt+↓", action: "duplicate", icon: "copy" },
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
        else if (a === "duplicate") { if (cur) cur.lines("duplicateDown"); }
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
    }
    function runTree(a, path) {
        if (a === "newFile") newFile(path);
        else if (a === "newFolder") newFolder(path);
        else if (a === "rename") renamePath(path);
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
            { label: "Zapisz", icon: "download", shortcut: "Ctrl+S", action: "save", enabled: !!win.cur },
            { label: "Zapisz wszystko", icon: "copy", shortcut: "Ctrl+Alt+S", action: "saveAll" },
            { separator: true },
            { label: "Polecenia…", icon: "apps", shortcut: "Ctrl+Shift+P", action: "commands" },
            { label: "Szukaj w projekcie", icon: "search", shortcut: "Ctrl+Shift+F", action: "searchProject" },
            { separator: true },
            { label: "Pasek boczny", icon: prefs.sidebar ? "check" : "", shortcut: "Ctrl+B", action: "sidebar" },
            { label: "Terminal", icon: win.terminalShown ? "check" : "", shortcut: "Ctrl+`", action: "terminal" },
            { label: "Zawijaj wiersze", icon: prefs.wrap ? "check" : "", shortcut: "Alt+Z", action: "wrap" },
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
        else if (what.startsWith("line:")) { if (cur) cur.goToLine(Number(arg)); }
        else if (what.startsWith("type:")) { if (cur) { cur.edit.insert(cur.edit.cursorPosition, arg.replace(/\\n/g, "\n")); pin(current); } }
        else if (what.startsWith("del:")) { if (cur) { const p = cur.edit.cursorPosition; cur.edit.remove(p, p + Number(arg)); } }
        else if (what.startsWith("lines:")) { if (cur) cur.lines(arg); }
        else if (what.startsWith("selectLines:")) { if (cur) { const ab = arg.split(","); cur.edit.select(TextOps.positionOfLine(cur.edit.textDocument, Number(ab[0]) - 1), TextOps.positionOfLine(cur.edit.textDocument, Number(ab[1]))); } }
        else if (what === "terminal") { terminalShown = true; }
        else if (what.startsWith("term:")) { if (terminalPanel.term) terminalPanel.term.sendText(arg + "\r"); }
        else if (what.startsWith("search:")) { showView(1); searchView.focusField(arg); searchView.run(); }
        else if (what.startsWith("palette:")) palette.open(arg);
        else if (what.startsWith("find:")) { openFind(false); findField.text = arg; findAll(); }
        else if (what.startsWith("view:")) { prefs.sidebar = true; sidebarView = Number(arg); }
        else if (what.startsWith("expand:")) Project.tree.expandPath(Project.root + "/" + arg);
        else if (what.startsWith("tree:")) { const row = Project.tree.indexOf(Project.root + "/" + arg); const it = treeList.itemAtIndex(row); if (it) { const pp = it.mapToItem(frame, 60, 14); showTreeMenu(Project.root + "/" + arg, false, pp.x, pp.y); } }
        else if (what === "menu") showMenu();
        else if (what === "newfile") newFile("");
        else if (what === "close") win.close();
    }

    // ——— Skróty ———
    Shortcut { sequence: "Ctrl+O"; onActivated: folderDialog.open() }
    Shortcut { sequence: "Ctrl+N"; enabled: win.hasProject; onActivated: win.newFile("") }
    Shortcut { sequence: "Ctrl+S"; enabled: !!win.cur; onActivated: win.save(win.current) }
    Shortcut { sequence: "Ctrl+Alt+S"; onActivated: win.saveAll() }
    Shortcut { sequence: "Ctrl+W"; enabled: tabs.count > 0; onActivated: win.closeTab(win.current) }
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
    Shortcut { sequence: "Alt+F5"; enabled: !!win.cur; onActivated: win.cur.nextChange(false) }
    Shortcut { sequence: "Shift+Alt+F5"; enabled: !!win.cur; onActivated: win.cur.nextChange(true) }
    Shortcut { sequence: "Alt+Z"; onActivated: prefs.wrap = !prefs.wrap }
    Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: win.zoom(1) }
    Shortcut { sequence: "Ctrl+-"; onActivated: win.zoom(-1) }
    Shortcut { sequence: "Ctrl+0"; onActivated: win.zoom(0) }
    Shortcut { sequences: ["Ctrl+Tab", "Ctrl+PgDown"]; enabled: tabs.count > 1; onActivated: win.activate((win.current + 1) % tabs.count) }
    Shortcut { sequences: ["Ctrl+Shift+Tab", "Ctrl+PgUp"]; enabled: tabs.count > 1; onActivated: win.activate((win.current - 1 + tabs.count) % tabs.count) }
    Shortcut { sequence: "F11"; onActivated: { if (win.visibility === Window.FullScreen) win.showNormal(); else win.showFullScreen(); } }
    Shortcut { sequence: "Esc"; enabled: findBar.shown || !!win.confirm
        onActivated: { if (win.confirm) win.confirm = null; else win.closeFind(); } }

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
                    width: Math.min(tabRow.width, rightGroup.x - x - 8)
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
                        Repeater { model: tabs; delegate: TabButton {} }
                    }
                }
                Row {
                    id: rightGroup
                    anchors.right: winButtons.left; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    ToolBtn { icon: "search"; onClicked: palette.open("") }
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
                Row {
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Repeater {
                        model: win.curPath ? Project.relative(win.curPath).split("/") : []
                        delegate: Row {
                            id: crumb
                            required property string modelData
                            required property int index
                            spacing: 4
                            Icon { visible: crumb.index > 0; anchors.verticalCenter: parent.verticalCenter; d: Icons.chevronRight; size: 11; stroke: 2; color: Theme.text2 }
                            FileIcon {
                                visible: crumb.index === Project.relative(win.curPath).split("/").length - 1
                                anchors.verticalCenter: parent.verticalCenter
                                name: crumb.modelData; size: 13
                            }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: crumb.modelData; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                        }
                    }
                }
            }

            // Edytor
            Item {
                id: editorArea
                y: crumbs.y + crumbs.height
                width: parent.width
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
                        path: model.path
                        y: banner.height
                        width: editorArea.width
                        height: editorArea.height - y
                        visible: index === win.current
                        wrap: prefs.wrap
                        fontSize: prefs.fontSize
                        onZoomRequested: (d) => win.zoom(d)
                        onModifiedChanged: { if (modified) win.pin(index); win.revision++; }
                        Component.onCompleted: {
                            load(win.pendingText[uid] || "", win.pendingCursor[uid] || 0);
                            delete win.pendingText[uid];
                            delete win.pendingCursor[uid];
                        }
                    }
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

            // Terminal
            TerminalPanel {
                id: terminalPanel
                visible: win.terminalShown
                y: editorArea.y + editorArea.height
                width: parent.width
                height: win.terminalMax ? parent.height - editorArea.y - status.height : Math.max(120, Math.min(prefs.terminalHeight, parent.height - 200))
                dir: Project.root
                maximized: win.terminalMax
                onHideRequested: { win.terminalShown = false; win.terminalMax = false; if (win.cur) win.cur.focusEditor(); }
                onMaximizeRequested: win.terminalMax = !win.terminalMax
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
                        onClicked: win.showView(2)
                    }
                    StatusBtn {
                        visible: Project.isGit && Project.changes.length > 0
                        icon: "pencil"
                        text: Project.changes.length
                        onClicked: win.showView(2)
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
                    StatusBtn { text: win.cur ? win.cur.language : "" }
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
                visible: win.sidebarView === 1
                y: sideTop.height
                width: parent.width; height: parent.height - y
                onOpenMatch: (path, line, col, length) => win.openFile(path, { preview: true, line: line, col: col, length: length })
            }
            ChangesView {
                visible: win.sidebarView === 2
                y: sideTop.height
                width: parent.width; height: parent.height - y
                onOpenFile: (path) => win.openFile(path, { preview: true })
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
                        text: !win.confirm ? "" : win.confirm.kind === "tab" ? "Zapisać zmiany w „" + win.confirm.name + "”?"
                            : win.confirm.count === 1 ? "Zapisać zmiany w 1 pliku?" : "Zapisać zmiany w " + win.confirm.count + " plikach?"
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                    }
                    Text { width: parent.width; wrapMode: Text.Wrap; text: "Jeśli nie zapiszesz, zmiany przepadną."; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                    Item { width: 1; height: 10 }
                    Item {
                        width: parent.width; height: 34
                        Pill {
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
    component TabButton: Rectangle {
        id: tab
        required property int index
        required property string path
        required property bool preview
        readonly property bool active: index === win.current
        readonly property bool dirty: { win.revision; const p = win.page(index); return !!p && p.modified; }
        width: Math.min(240, tabLabel.implicitWidth + 70); height: 34
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        radius: 9
        color: active ? Theme.fill : (tabArea.containsMouse ? Theme.hover : "transparent")
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
                        { label: "Pokaż w drzewie plików", icon: "files", action: "tab:reveal" },
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
