pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Dialogs
import Aster.Ui
import Aster.Files

// Pliki: okno bez ramki systemowej — pasek tytułu z nawigacją, wyszukiwaniem i okrągłymi
// przyciskami jest częścią okna (jak w prototypie). Wokół okna jest margines na cień;
// kliknięcia w cień przechodzą do okien pod spodem (Files.setInputRegion).
Window {
    id: win
    property string startUrl
    property string extractOnStart: ""                 // archiwum 7z/RAR otwarte z innego programu — wypakuj obok

    width: 1060 + 2 * m
    height: 680 + 2 * m
    minimumWidth: 720 + 2 * m
    minimumHeight: 440 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: Files.displayName(folder.url.toString())

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26           // margines na cień
    readonly property real r: maxed ? 0 : 24          // zaokrąglenie rogów

    // ——— Stan ———
    property var backStack: []
    property var fwdStack: []
    property var sel: ({})                             // zaznaczone: url → true
    property int lastIndex: -1
    property string renaming: ""                       // url elementu, którego nazwę zmieniamy
    property string pendingRename: ""                  // nazwa nowego elementu — zmiana nazwy, gdy się pojawi
    property string viewMode: "grid"
    property var quickLook: null                       // podgląd (spacja)
    property var confirm: null                         // okno potwierdzenia
    property string toastText: ""
    property bool toastUndo: false
    property bool entering: false

    readonly property string currentUrl: folder.url.toString()
    readonly property bool inTrash: currentUrl.indexOf("trash:") === 0
    readonly property string query: searchField.text.trim()
    readonly property var crumbs: Files.crumbs(currentUrl)
    readonly property var selection: Object.keys(sel)
    // Wnętrze archiwum ZIP/TAR (zip:/…) — tylko do odczytu
    readonly property string archiveFile: Archiver.archiveOf(currentUrl)
    readonly property bool inArchive: archiveFile !== ""
    property var archiveSheet: null                    // okno: hasło do archiwum albo „Kompresuj”
    property string pendingSelect: ""                  // wynik pakowania/wypakowania — zaznacz, gdy się pojawi

    FolderModel {
        id: folder
        url: win.startUrl
        onCountChanged: {
            win.selectPending();
            if (win.pendingRename) {
                const i = folder.indexOfName(win.pendingRename);
                if (i >= 0) {
                    const u = folder.get(i).url;
                    win.pendingRename = "";
                    win.setSel([u]);
                    win.lastIndex = i;
                    win.renaming = u;
                    if (win.viewMode === "grid") gridView.positionViewAtIndex(i, GridView.Contain);
                    else listView.positionViewAtIndex(i, ListView.Contain);
                }
            }
        }
    }

    Connections {
        target: Files
        function onFailed(message) { win.showToast(message, false); }
    }
    Connections {
        target: Drives
        function onOpened(url) { win.navigate(url); }
        function onMessage(text) { win.showToast(text, false); }
        function onEjected(url) { if (win.currentUrl.indexOf(url) === 0) win.navigate(Files.homeUrl); }
    }
    function driveMenu(d, x, y) {
        driveMenuData = d;
        menu.openAt(x, y, [
            { label: "Otwórz", icon: "folder", action: "drive:open" },
            { label: "Wysuń", icon: "eject", action: "drive:eject", enabled: d.removable && !d.busy },
            { separator: true },
            { label: "Formatuj…", icon: "drive", action: "drive:format", enabled: !d.busy, danger: true }
        ]);
    }
    property var driveMenuData: null
    property var formatSheet: null                     // { udi, name, sizeText }
    Connections {
        target: Archiver
        function onFinished(id, ok, message, resultUrl) {
            win.showToast(message, false);
            if (ok && resultUrl) { win.pendingSelect = resultUrl; win.selectPending(); }
        }
        function onPasswordNeeded(archiveUrl, destDirUrl, wrong) {
            win.archiveSheet = { kind: "password", archive: archiveUrl, dest: destDirUrl, wrong: wrong };
        }
    }

    // ——— Archiwa ———
    function selectPending() {
        if (!pendingSelect) return;
        const i = folder.indexOfUrl(pendingSelect);
        if (i < 0) return;
        pendingSelect = "";
        setSel([folder.get(i).url]);
        lastIndex = i;
        if (viewMode === "grid") gridView.positionViewAtIndex(i, GridView.Contain);
        else listView.positionViewAtIndex(i, ListView.Contain);
    }
    function localSelection() { return selection.filter(u => u.indexOf("file:") === 0); }
    function extractHere(url) { Archiver.extract(url, "", ""); }
    function extractTo(url) { extractDialog.archive = url; extractDialog.open(); }
    function compressZip() {
        const urls = localSelection();
        if (urls.length) Archiver.compress(urls, Archiver.suggestedName(urls, "zip"), "zip", "");
    }
    function askCompress() {
        const urls = localSelection();
        if (!urls.length) return;
        const name = Archiver.suggestedName(urls, "zip");
        archiveSheet = { kind: "compress", urls: urls, name: name.substring(0, name.length - 4) };
    }

    // ——— Pomocnicze ———
    function countText(n) {
        const last = n % 10, lastTwo = n % 100;
        if (n === 1) return "1 element";
        if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) return n + " elementy";
        return n + " elementów";
    }
    // „dziś, 08:16” / „wczoraj, 10:40” / „13 paź” / „13 paź 2024”
    function when(d) {
        if (!d || isNaN(d.getTime())) return "";
        const loc = Qt.locale("pl_PL");
        const now = new Date();
        const a = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        const b = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const diff = Math.round((b - a) / 86400000);
        if (diff === 0) return "dziś, " + d.toLocaleTimeString(loc, "HH:mm");
        if (diff === 1) return "wczoraj, " + d.toLocaleTimeString(loc, "HH:mm");
        return d.toLocaleDateString(loc, d.getFullYear() === now.getFullYear() ? "d MMM" : "d MMM yyyy");
    }
    function showToast(text, undoable) {
        toastText = text;
        toastUndo = undoable;
        toastTimer.restart();
    }

    function navigate(url, push) {
        if (!url || url === currentUrl) return;
        if (push !== false) { backStack = backStack.concat([currentUrl]); fwdStack = []; }
        searchField.text = "";
        clearSel();
        renaming = "";
        quickLook = null;
        folder.url = url;
        entering = true;
        enterTimer.restart();
        keys.forceActiveFocus();
    }
    Timer { id: enterTimer; interval: 400; onTriggered: win.entering = false }
    function goBack() {
        if (!backStack.length) return;
        fwdStack = fwdStack.concat([currentUrl]);
        const u = backStack[backStack.length - 1];
        backStack = backStack.slice(0, -1);
        navigate(u, false);
    }
    function goForward() {
        if (!fwdStack.length) return;
        backStack = backStack.concat([currentUrl]);
        const u = fwdStack[fwdStack.length - 1];
        fwdStack = fwdStack.slice(0, -1);
        navigate(u, false);
    }
    function goUp() { const p = Files.parentUrl(currentUrl); if (p) navigate(p); }

    function setSel(urls) {
        const s = {};
        for (const u of urls) s[u] = true;
        sel = s;
    }
    function clearSel() { sel = {}; lastIndex = -1; }
    function toggleSel(u) {
        const s = Object.assign({}, sel);
        if (s[u]) delete s[u]; else s[u] = true;
        sel = s;
    }
    function allUrls() {
        const out = [];
        for (let i = 0; i < folder.count; ++i) out.push(folder.get(i).url);
        return out;
    }
    function selectAll() { setSel(allUrls()) }

    function itemClicked(index, mods, button, wx, wy) {
        const u = folder.get(index).url;
        keys.forceActiveFocus();
        if (button === Qt.RightButton) {
            if (!sel[u]) { setSel([u]); lastIndex = index; }
            showItemMenu(wx, wy);
            return;
        }
        if (mods & Qt.ControlModifier) toggleSel(u);
        else if ((mods & Qt.ShiftModifier) && lastIndex >= 0) {
            const a = Math.min(lastIndex, index), b = Math.max(lastIndex, index);
            const urls = [];
            for (let i = a; i <= b; ++i) urls.push(folder.get(i).url);
            setSel(urls);
            return;
        } else setSel([u]);
        lastIndex = index;
    }

    function openItem(file) {
        if (!file) return;
        if (file.isDir) navigate(file.url);
        else if (inTrash) quickLook = file;
        else if (Archiver.browseUrl(file.url)) navigate(Archiver.browseUrl(file.url));    // ZIP/TAR jak folder
        else if (Archiver.isArchive(file.url)) extractHere(file.url);                    // 7z, RAR… — od razu obok
        else Files.open(file.url);
    }
    function selectedFile() {
        if (selection.length !== 1) return null;
        const i = folder.indexOfUrl(selection[0]);
        return i >= 0 ? folder.get(i) : null;
    }
    function openSelected() { openItem(selectedFile()); }

    function doCut() { if (selection.length && !inTrash && !inArchive) { Files.setClipboard(selection, true); showToast("Wycięto " + countText(selection.length) + " — wklej w innym folderze", false); } }
    function doCopy() { if (selection.length && !inTrash) { Files.setClipboard(selection, false); showToast("Skopiowano " + countText(selection.length) + " do schowka", false); } }
    function doPaste() {
        if (inArchive) return;
        if (inTrash || query) return;
        const cut = Files.clipboardCut;
        const n = Files.paste(currentUrl);
        if (n) showToast((cut ? "Przeniesiono " : "Wklejono ") + countText(n), true);
    }
    function moveTo(urls, dest) {
        if (!urls.length || dest === currentUrl && !query) return;
        if (dest.indexOf("trash:") === 0) { Files.trash(urls); clearSel(); showToast("Przeniesiono " + countText(urls.length) + " do kosza", true); return; }
        Files.move(urls, dest);
        showToast("Przeniesiono " + countText(urls.length) + " do: " + Files.displayName(dest), true);
    }
    function copyIn(urls, dest) {
        if (!urls.length) return;
        Files.copy(urls, dest);
        showToast("Kopiuję " + countText(urls.length) + " do: " + Files.displayName(dest), true);
    }
    // Upuszczenie: z tego okna przenosi, z innych aplikacji kopiuje
    function handleDrop(drop, dest) {
        if (drop.source === ghost) moveTo(ghost.urls, dest);
        else if (drop.hasUrls) copyIn(drop.urls.map(u => u.toString()), dest);
    }
    function trashSelected() {
        if (inArchive) return;
        if (!selection.length) return;
        const n = selection.length;
        Files.trash(selection);
        clearSel();
        showToast("Przeniesiono " + countText(n) + " do kosza", true);
    }
    function deleteSelected() {
        if (inTrash) askPurge(selection);
        else trashSelected();
    }
    function restoreSelected() {
        const n = selection.length;
        if (!n) return;
        Files.restore(selection);
        clearSel();
        showToast("Przywrócono " + countText(n), false);
    }
    function askPurge(urls) {
        if (!urls.length) return;
        const one = urls.length === 1 ? folder.get(folder.indexOfUrl(urls[0])) : null;
        confirm = {
            title: one ? "Usunąć „" + one.name + "” na zawsze?" : "Usunąć " + countText(urls.length) + " na zawsze?",
            text: "Tych plików nie będzie można przywrócić.",
            button: "Usuń na zawsze",
            run: () => { Files.deletePermanently(urls); clearSel(); showToast("Usunięto " + countText(urls.length), false); }
        };
    }
    function askEmptyTrash() {
        if (!Files.trashCount) return;
        confirm = {
            title: "Opróżnić kosz?",
            text: "Usuniesz na zawsze " + countText(Files.trashCount) + ". Tych plików nie będzie można przywrócić.",
            button: "Opróżnij kosz",
            run: () => { Files.emptyTrash(); clearSel(); showToast("Kosz jest pusty", false); }
        };
    }
    function newFolder() {
        if (inTrash || inArchive || query) return;
        pendingRename = Files.newFolder(currentUrl);
    }
    function newDocument() {
        if (inTrash || query) return;
        pendingRename = Files.newTextFile(currentUrl);
    }
    function startRename() { if (selection.length === 1 && !inTrash && !inArchive) renaming = selection[0]; }
    function commitRename(url, name) {
        if (renaming !== url) return;
        renaming = "";
        const err = Files.rename(url, name);
        if (err) showToast(err, false);
        keys.forceActiveFocus();
    }
    function doUndo() {
        if (!Files.canUndo) { showToast("Nie ma czego cofnąć", false); return; }
        const label = Files.undoText;
        Files.undo();
        clearSel();
        renaming = "";
        showToast(label || "Cofnięto", false);
    }
    function toggleQuickLook() {
        if (quickLook) quickLook = null;
        else { const f = selectedFile(); if (f && !f.isDir) quickLook = f; }
    }
    function moveCursor(dx, dy, extend) {
        if (!folder.count) return;
        const cols = viewMode === "grid" ? Math.max(1, Math.floor(gridView.width / gridView.cellWidth)) : 1;
        let i = lastIndex < 0 ? 0 : lastIndex + dx + dy * cols;
        i = Math.max(0, Math.min(folder.count - 1, i));
        const u = folder.get(i).url;
        if (extend && lastIndex >= 0) {
            const s = Object.assign({}, sel);
            s[u] = true;
            sel = s;
        } else setSel([u]);
        lastIndex = i;
        if (viewMode === "grid") gridView.positionViewAtIndex(i, GridView.Contain);
        else listView.positionViewAtIndex(i, ListView.Contain);
    }

    function handleKey(e) {
        const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier, alt = e.modifiers & Qt.AltModifier;
        if (formatSheet) {
            if (e.key === Qt.Key_Escape) formatSheet = null;
            e.accepted = true;
            return;
        }
        if (archiveSheet) {
            if (e.key === Qt.Key_Escape) archiveSheet = null;
            e.accepted = true;
            return;
        }
        if (confirm) {
            if (e.key === Qt.Key_Escape) confirm = null;
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { const c = confirm; confirm = null; c.run(); }
            e.accepted = true;
            return;
        }
        if (quickLook) {
            if (e.key === Qt.Key_Space || e.key === Qt.Key_Escape) quickLook = null;
            e.accepted = true;
            return;
        }
        if (ctrl && shift && e.key === Qt.Key_N) newFolder();
        else if (ctrl && e.key === Qt.Key_A) selectAll();
        else if (ctrl && e.key === Qt.Key_C) doCopy();
        else if (ctrl && e.key === Qt.Key_X) doCut();
        else if (ctrl && e.key === Qt.Key_V) doPaste();
        else if (ctrl && e.key === Qt.Key_Z) doUndo();
        else if (ctrl && e.key === Qt.Key_F) searchField.forceActiveFocus();
        else if (ctrl && e.key === Qt.Key_H) folder.showHidden = !folder.showHidden;
        else if (ctrl && e.key === Qt.Key_W) win.close();
        else if (e.key === Qt.Key_Delete && shift && !inTrash) askPurge(selection);
        else if (e.key === Qt.Key_Delete) deleteSelected();
        else if (e.key === Qt.Key_F2) startRename();
        else if (e.key === Qt.Key_F5) { const u = currentUrl; folder.url = ""; folder.url = u; }
        else if (e.key === Qt.Key_Space) toggleQuickLook();
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) openSelected();
        else if ((alt || ctrl) && e.key === Qt.Key_Up) goUp();
        else if (e.key === Qt.Key_Backspace || (alt && e.key === Qt.Key_Left)) goBack();
        else if (alt && e.key === Qt.Key_Right) goForward();
        else if (e.key === Qt.Key_Left) moveCursor(-1, 0, shift);
        else if (e.key === Qt.Key_Right) moveCursor(1, 0, shift);
        else if (e.key === Qt.Key_Up) moveCursor(0, -1, shift);
        else if (e.key === Qt.Key_Down) moveCursor(0, 1, shift);
        else if (e.key === Qt.Key_Escape) clearSel();
        else return;
        e.accepted = true;
    }

    // ——— Menu ———
    function showItemMenu(wx, wy) {
        const f = selectedFile();
        const isDir = !!f && f.isDir;
        if (inTrash) {
            menu.openAt(wx, wy, [
                { label: "Przywróć", icon: "undo", action: "restore" },
                { separator: true },
                { label: "Usuń na zawsze", icon: "trash", action: "purge", danger: true }
            ]);
            return;
        }
        if (inArchive) {
            menu.openAt(wx, wy, [
                { label: "Otwórz", icon: isDir ? "folder" : "arrow", shortcut: "Enter", action: "open", enabled: !!f },
                { label: "Kopiuj", icon: "copy", shortcut: "Ctrl+C", action: "copy" },
                { separator: true },
                { label: "Wypakuj wszystko", icon: "archive", action: "extractArchive" }
            ]);
            return;
        }
        const archive = !!f && !isDir && Archiver.isArchive(f.url);
        const local = localSelection().length === selection.length;
        const items = [
            { label: "Otwórz", icon: isDir ? "folder" : "arrow", shortcut: "Enter", action: "open", enabled: !!f },
            { label: "Podgląd", icon: "eye", shortcut: "Spacja", action: "preview", enabled: !!f && !isDir },
            { separator: true },
            { label: "Wytnij", icon: "scissors", shortcut: "Ctrl+X", action: "cut" },
            { label: "Kopiuj", icon: "copy", shortcut: "Ctrl+C", action: "copy" },
            { label: "Zmień nazwę", icon: "pencil", shortcut: "F2", action: "rename", enabled: !!f },
            { separator: true }
        ];
        if (archive) items.push({ label: "Wypakuj wszystko", icon: "archive", action: "extract" },
                                { label: "Wypakuj do…", icon: "folder", action: "extractTo" });
        if (local) items.push({ label: "Kompresuj do pliku ZIP", icon: "archive", action: "zip" },
                              { label: "Kompresuj…", icon: "sliders", action: "compress" });
        if (archive || local) items.push({ separator: true });
        items.push({ label: "Otwórz w Terminalu", icon: "terminal", action: "terminalHere", enabled: isDir && f.url.indexOf("file:") === 0 },
                   { separator: true },
                   { label: "Przenieś do kosza", icon: "trash", shortcut: "Delete", action: "trash", danger: true });
        menu.openAt(wx, wy, items);
    }
    function showBackgroundMenu(wx, wy) {
        clearSel();
        if (inTrash) {
            menu.openAt(wx, wy, [{ label: "Opróżnij kosz", icon: "trash", action: "empty", danger: true, enabled: Files.trashCount > 0 }]);
            return;
        }
        if (inArchive) {
            menu.openAt(wx, wy, [{ label: "Wypakuj wszystko", icon: "archive", action: "extractArchive" },
                                 { label: "Wypakuj do…", icon: "folder", action: "extractArchiveTo" }]);
            return;
        }
        menu.openAt(wx, wy, [
            { label: "Nowy folder", icon: "folderPlus", shortcut: "Ctrl+Shift+N", action: "newFolder", enabled: !query },
            { label: "Nowy dokument tekstowy", icon: "filePlus", action: "newDoc", enabled: !query },
            { separator: true },
            { label: "Wklej", icon: "paste", shortcut: "Ctrl+V", action: "paste", enabled: Files.clipboardCount > 0 && !query },
            { label: "Zaznacz wszystko", shortcut: "Ctrl+A", action: "selectAll" },
            { label: folder.showHidden ? "Ukryj ukryte pliki" : "Pokaż ukryte pliki", icon: "eye", shortcut: "Ctrl+H", action: "hidden" },
            { label: "Cofnij", icon: "undo", shortcut: "Ctrl+Z", action: "undo", enabled: Files.canUndo },
            { separator: true },
            { label: "Otwórz w Terminalu", icon: "terminal", action: "terminal", enabled: currentUrl.indexOf("file:") === 0 }
        ]);
    }
    function showSortMenu(wx, wy) {
        const mark = (k) => folder.sortKey === k ? "check" : "";
        menu.openAt(wx, wy, [
            { label: "Nazwa", icon: mark("name"), action: "sort:name" },
            { label: "Data zmiany", icon: mark("date"), action: "sort:date" },
            { label: "Rozmiar", icon: mark("size"), action: "sort:size" },
            { label: "Typ", icon: mark("kind"), action: "sort:kind" },
            { separator: true },
            { label: folder.ascending ? "Malejąco" : "Rosnąco", icon: "sort", action: "sort:flip" }
        ]);
    }
    function showNewMenu(wx, wy) {
        menu.openAt(wx, wy, [
            { label: "Folder", icon: "folderPlus", shortcut: "Ctrl+Shift+N", action: "newFolder" },
            { label: "Dokument tekstowy", icon: "filePlus", action: "newDoc" }
        ]);
    }
    function runAction(a) {
        if (a === "open") openSelected();
        else if (a === "preview") toggleQuickLook();
        else if (a === "cut") doCut();
        else if (a === "copy") doCopy();
        else if (a === "paste") doPaste();
        else if (a === "rename") startRename();
        else if (a === "trash") trashSelected();
        else if (a === "restore") restoreSelected();
        else if (a === "purge") askPurge(selection);
        else if (a === "empty") askEmptyTrash();
        else if (a === "newFolder") newFolder();
        else if (a === "newDoc") newDocument();
        else if (a === "selectAll") selectAll();
        else if (a === "hidden") folder.showHidden = !folder.showHidden;
        else if (a === "undo") doUndo();
        else if (a === "terminal") Files.openTerminal(currentUrl);
        else if (a === "terminalHere") Files.openTerminal(selectedFile().url);
        else if (a === "extract") extractHere(selectedFile().url);
        else if (a === "extractTo") extractTo(selectedFile().url);
        else if (a === "extractArchive") extractHere(archiveFile);
        else if (a === "extractArchiveTo") extractTo(archiveFile);
        else if (a === "zip") compressZip();
        else if (a === "drive:open") Drives.open(driveMenuData.udi);
        else if (a === "drive:eject") Drives.eject(driveMenuData.udi);
        else if (a === "drive:format") formatSheet = { udi: driveMenuData.udi, name: driveMenuData.name, sizeText: driveMenuData.sizeText };
        else if (a === "compress") askCompress();
        else if (a === "sort:flip") folder.ascending = !folder.ascending;
        else if (a.indexOf("sort:") === 0) setSort(a.slice(5));
        if (!renaming) keys.forceActiveFocus();
    }
    function setSort(k) {
        if (folder.sortKey === k) folder.ascending = !folder.ascending;
        else { folder.sortKey = k; folder.ascending = k === "name" || k === "kind"; }
    }

    // ——— Przeciąganie plików ———
    function dragStart(index) {
        const f = folder.get(index);
        if (!sel[f.url]) { setSel([f.url]); lastIndex = index; }
        ghost.urls = selection;
        ghost.label = selection.length === 1 ? f.name : countText(selection.length);
        ghost.Drag.active = true;
    }
    function dragMove(wx, wy) { ghost.x = wx; ghost.y = wy; }
    function dragEnd() {
        ghost.Drag.drop();
        ghost.Drag.active = false;
    }

    // ——— Okno: rozmycie i obszar kliknięć po każdej zmianie rozmiaru ———
    function updateEffects() {
        WindowEffects.setBlur(win, Qt.rect(m, m, frame.width, frame.height), r);
        WindowEffects.setInputRegion(win, Qt.rect(Math.max(0, m - 6), Math.max(0, m - 6), frame.width + (maxed ? 0 : 12), frame.height + (maxed ? 0 : 12)));
    }
    onWidthChanged: effectsTimer.restart()
    onHeightChanged: effectsTimer.restart()
    onMaxedChanged: effectsTimer.restart()
    Component.onCompleted: {
        effectsTimer.restart();
        keys.forceActiveFocus();
        if (extractOnStart) extractHere(extractOnStart);
    }
    Timer { id: effectsTimer; interval: 16; onTriggered: win.updateEffects() }

    WindowShadow { window: win; frame: frame; radius: win.r; visible: !win.maxed }

    // Uchwyty zmiany rozmiaru (krawędzie i rogi, tuż przy oknie)
    Repeater {
        model: win.maxed ? [] : [
            { e: Qt.LeftEdge, x: 0, y: 1, w: 0, h: 1, c: Qt.SizeHorCursor },
            { e: Qt.RightEdge, x: 1, y: 1, w: 0, h: 1, c: Qt.SizeHorCursor },
            { e: Qt.TopEdge, x: 1, y: 0, w: 1, h: 0, c: Qt.SizeVerCursor },
            { e: Qt.BottomEdge, x: 1, y: 2, w: 1, h: 0, c: Qt.SizeVerCursor },
            { e: Qt.TopEdge | Qt.LeftEdge, x: 0, y: 0, w: 0, h: 0, c: Qt.SizeFDiagCursor },
            { e: Qt.TopEdge | Qt.RightEdge, x: 2, y: 0, w: 0, h: 0, c: Qt.SizeBDiagCursor },
            { e: Qt.BottomEdge | Qt.LeftEdge, x: 0, y: 2, w: 0, h: 0, c: Qt.SizeBDiagCursor },
            { e: Qt.BottomEdge | Qt.RightEdge, x: 2, y: 2, w: 0, h: 0, c: Qt.SizeFDiagCursor }
        ]
        delegate: MouseArea {
            required property var modelData
            readonly property int g: 8
            x: modelData.x === 0 ? win.m - g : modelData.x === 1 ? win.m + g : win.m + frame.width - g
            y: modelData.y === 0 ? win.m - g : modelData.y === 1 ? win.m + g : win.m + frame.height - g
            width: modelData.w ? frame.width - 2 * g : 2 * g
            height: modelData.h ? frame.height - 2 * g : 2 * g
            cursorShape: modelData.c
            onPressed: win.startSystemResize(modelData.e)
        }
    }

    // ——— Okno ———
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

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: (e) => win.handleKey(e)
        }

        // ——— Pasek tytułu ———
        Item {
            id: titlebar
            width: parent.width; height: 52

            DragHandler {
                target: null
                onActiveChanged: if (active) win.startSystemMove()
            }
            TapHandler {
                onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized()
            }

            Row {
                id: navButtons
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                ToolBtn { icon: "back"; enabled: win.backStack.length > 0; onClicked: win.goBack() }
                ToolBtn { icon: "forward"; enabled: win.fwdStack.length > 0; onClicked: win.goForward() }
                ToolBtn { icon: "up"; enabled: Files.parentUrl(win.currentUrl) !== ""; onClicked: win.goUp() }
            }

            // Ścieżka — każdy segment klikalny i przyjmuje upuszczone pliki
            Rectangle {
                anchors.left: navButtons.right; anchors.leftMargin: 8
                anchors.right: searchBox.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: 34
                radius: 9
                color: Theme.fill
                clip: true
                Row {
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: win.crumbs
                        delegate: Row {
                            id: seg
                            required property var modelData
                            required property int index
                            readonly property bool last: index === win.crumbs.length - 1
                            Text { visible: seg.index > 0; anchors.verticalCenter: parent.verticalCenter; text: "›"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; leftPadding: 2; rightPadding: 2 }
                            Rectangle {
                                width: segText.implicitWidth + 12; height: 26; radius: 6
                                anchors.verticalCenter: parent.verticalCenter
                                color: segDrop.containsDrag ? Theme.accentSoft : (segArea.containsMouse && !seg.last ? Theme.hover : "transparent")
                                Text { id: segText; anchors.centerIn: parent; text: seg.modelData.name; color: seg.last ? Theme.text : Theme.text2; font.family: Theme.font; font.pixelSize: 13; font.weight: seg.last ? Font.Medium : Font.Normal }
                                MouseArea { id: segArea; anchors.fill: parent; hoverEnabled: true; onClicked: win.navigate(seg.modelData.url) }
                                DropArea { id: segDrop; anchors.fill: parent; keys: ["aster-files", "text/uri-list"]; onDropped: (d) => win.handleDrop(d, seg.modelData.url) }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: searchBox
                anchors.right: controls.left; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 220; height: 34; radius: 9
                color: Theme.fill
                border.width: searchField.activeFocus ? 1.5 : 0
                border.color: Theme.accent
                Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 16; color: Theme.text2 }
                TextInput {
                    id: searchField
                    x: 34; width: parent.width - 44
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13; clip: true
                    selectionColor: Theme.accentSoft
                    selectedTextColor: Theme.text
                    onTextChanged: { win.clearSel(); folder.search = text; }
                    Keys.onEscapePressed: { text = ""; keys.forceActiveFocus(); }
                    Keys.onDownPressed: { keys.forceActiveFocus(); win.moveCursor(0, 0, false); }
                    Text { visible: !searchField.text; text: "Szukaj w: " + Files.displayName(win.currentUrl); width: parent.width; elide: Text.ElideRight; color: Theme.text2; font: searchField.font }
                }
            }

            WindowButtons {
                id: controls
                window: win
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ——— Pasek boczny ———
        Item {
            id: sidebar
            y: titlebar.height
            width: 210; height: parent.height - titlebar.height

            Column {
                x: 10; y: 14
                width: parent.width - 20
                spacing: 2
                Text { text: "ULUBIONE"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 0.4; leftPadding: 10; bottomPadding: 6; topPadding: 4 }
                Repeater {
                    model: Files.places()
                    delegate: SidebarPlace {
                        required property var modelData
                        width: parent.width
                        label: modelData.name
                        icon: modelData.icon
                        active: win.currentUrl === modelData.url
                        onClicked: win.navigate(modelData.url)
                        onDropped: (d) => win.handleDrop(d, modelData.url)
                    }
                }
                Text { text: "TEN KOMPUTER"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 0.4; leftPadding: 10; bottomPadding: 6; topPadding: 16 }
                SidebarPlace {
                    id: drivePlace
                    readonly property var info: Files.systemDrive()
                    width: parent.width
                    label: "Dysk systemowy"; icon: "drive"
                    active: win.currentUrl === "file:///"
                    onClicked: win.navigate("file:///")
                    onDropped: (d) => win.handleDrop(d, "file:///")
                }
                Item {
                    width: parent.width; height: 24
                    Rectangle {
                        x: 38; y: 2; width: parent.width - 48; height: 4; radius: 2; color: Theme.line
                        Rectangle { width: parent.width * drivePlace.info.usedRatio; height: 4; radius: 2; color: Theme.accent }
                    }
                    Text { x: 38; y: 9; text: drivePlace.info.freeText; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.letterSpacing: 0.1 }
                }
                // Pendrive’y, karty, dodatkowe dyski
                Repeater {
                    model: Drives.list
                    delegate: Column {
                        id: driveItem
                        required property var modelData
                        width: parent.width
                        SidebarPlace {
                            width: parent.width
                            label: driveItem.modelData.name
                            icon: "drive"
                            badge: driveItem.modelData.busy || ""
                            ejectable: driveItem.modelData.removable && !driveItem.modelData.busy
                            active: !!driveItem.modelData.url && win.currentUrl === driveItem.modelData.url
                            onClicked: Drives.open(driveItem.modelData.udi)
                            onEjectClicked: Drives.eject(driveItem.modelData.udi)
                            onRightClicked: (x, y) => { const p = mapToItem(frame, x, y); win.driveMenu(driveItem.modelData, p.x, p.y); }
                            onDropped: (d) => { if (driveItem.modelData.url) win.handleDrop(d, driveItem.modelData.url); }
                        }
                        Item {
                            visible: driveItem.modelData.mounted && !!driveItem.modelData.freeText
                            width: parent.width; height: visible ? 24 : 0
                            Rectangle {
                                x: 38; y: 2; width: parent.width - 48; height: 4; radius: 2; color: Theme.line
                                Rectangle { width: parent.width * (driveItem.modelData.usedRatio || 0); height: 4; radius: 2; color: Theme.accent }
                            }
                            Text { x: 38; y: 9; text: driveItem.modelData.freeText || ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.letterSpacing: 0.1 }
                        }
                    }
                }
                Item { width: 1; height: 10 }
                SidebarPlace {
                    width: parent.width
                    label: "Kosz"; icon: "trash"
                    badge: Files.trashCount ? String(Files.trashCount) : ""
                    active: win.inTrash
                    onClicked: win.navigate("trash:/")
                    onDropped: (d) => { if (d.source === ghost) win.moveTo(ghost.urls, "trash:/"); }
                }
            }
        }

        // ——— Panel treści (prawa część okna: pasek narzędzi, folder, pasek stanu) ———
        GlassPane {
            id: pane
            z: -1                       // pod paskiem tytułu, który biegnie nad całym oknem
            x: sidebar.width
            width: parent.width - sidebar.width
            height: parent.height
            topRightRadius: win.r; bottomRightRadius: win.r
        }

        // ——— Pasek narzędzi ———
        Item {
            id: toolbar
            x: pane.x; y: titlebar.height
            width: pane.width; height: 48

            Row {
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                visible: !win.inTrash

                Rectangle {
                    id: newBtn
                    width: newRow.implicitWidth + 22; height: 32; radius: 8
                    opacity: win.query || win.inArchive ? 0.4 : 1
                    color: newArea.containsMouse ? Qt.darker(Theme.accent, 1.1) : Theme.accent
                    Row {
                        id: newRow
                        anchors.centerIn: parent
                        spacing: 6
                        Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.plus; size: 16; color: "white" }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Nowy"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                        Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.chevronDown; size: 14; color: "white" }
                    }
                    MouseArea {
                        id: newArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !win.query && !win.inArchive
                        onClicked: { const p = newBtn.mapToItem(frame, 0, newBtn.height + 4); win.showNewMenu(p.x, p.y); }
                    }
                }
                Item { width: 8; height: 1 }
                ToolBtn { icon: "scissors"; enabled: win.selection.length > 0 && !win.inArchive; onClicked: win.doCut() }
                ToolBtn { icon: "copy"; enabled: win.selection.length > 0; onClicked: win.doCopy() }
                ToolBtn { icon: "paste"; enabled: Files.clipboardCount > 0 && !win.query && !win.inArchive; onClicked: win.doPaste() }
                ToolBtn { icon: "pencil"; enabled: win.selection.length === 1 && !win.inArchive; onClicked: win.startRename() }
                ToolBtn { icon: "trash"; enabled: win.selection.length > 0 && !win.inArchive; onClicked: win.trashSelected() }
            }

            Row {
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                visible: win.inTrash
                HoverButton {
                    width: restoreRow.implicitWidth + 22; height: 32
                    baseColor: Theme.fill
                    enabled: win.selection.length > 0
                    opacity: enabled ? 1 : 0.4
                    onClicked: win.restoreSelected()
                    Row {
                        id: restoreRow
                        anchors.centerIn: parent
                        spacing: 6
                        Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.undo; size: 16; color: Theme.text }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Przywróć"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                    }
                }
                HoverButton {
                    width: emptyText.implicitWidth + 24; height: 32
                    baseColor: Theme.fill
                    enabled: Files.trashCount > 0
                    opacity: enabled ? 1 : 0.4
                    onClicked: win.askEmptyTrash()
                    Text { id: emptyText; anchors.centerIn: parent; text: "Opróżnij kosz"; color: Theme.danger; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                }
            }

            Row {
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                HoverButton {
                    id: sortBtn
                    width: sortRow.implicitWidth + 20; height: 32
                    onClicked: { const p = sortBtn.mapToItem(frame, 0, sortBtn.height + 4); win.showSortMenu(p.x, p.y); }
                    Row {
                        id: sortRow
                        anchors.centerIn: parent
                        spacing: 6
                        Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.sort; size: 16; color: Theme.text }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: ({ name: "Nazwa", date: "Data", size: "Rozmiar", kind: "Typ" })[folder.sortKey] + (folder.ascending ? " ↑" : " ↓"); color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                    }
                }
                Rectangle {
                    width: 70; height: 32; radius: 9
                    color: Theme.fill
                    Row {
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: ["grid", "list"]
                            delegate: Rectangle {
                                id: vm
                                required property string modelData
                                width: 32; height: 26; radius: 7
                                color: win.viewMode === modelData ? Theme.surface : "transparent"
                                Icon { anchors.centerIn: parent; d: Icons[vm.modelData]; size: 15; color: win.viewMode === vm.modelData ? Theme.text : Theme.text2 }
                                MouseArea { anchors.fill: parent; onClicked: { win.viewMode = vm.modelData; keys.forceActiveFocus(); } }
                            }
                        }
                    }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        }

        // ——— Zawartość folderu ———
        Rectangle {
            id: content
            x: pane.x; y: toolbar.y + toolbar.height
            width: pane.width
            height: pane.y + pane.height - y - status.height
            color: "transparent"
            clip: true

            // Upuszczenie na puste miejsce = do bieżącego folderu
            DropArea {
                anchors.fill: parent
                keys: ["aster-files", "text/uri-list"]
                enabled: !win.inTrash && !win.query
                onDropped: (d) => win.handleDrop(d, win.currentUrl)
            }

            // Nagłówek listy (klik sortuje)
            Item {
                id: listHeader
                visible: win.viewMode === "list"
                width: parent.width; height: visible ? 34 : 0
                readonly property string arrow: folder.ascending ? " ↑" : " ↓"
                Repeater {
                    model: [
                        { k: "name", label: "Nazwa", x: 62 },
                        { k: "date", label: "Zmodyfikowano", x: listHeader.width - 24 - 390 + 12 },
                        { k: "kind", label: "Typ", x: listHeader.width - 24 - 220 + 12 },
                        { k: "size", label: "Rozmiar", x: listHeader.width - 24 - 90 + 12 }
                    ]
                    delegate: Text {
                        id: hdr
                        required property var modelData
                        x: modelData.x
                        anchors.verticalCenter: parent.verticalCenter
                        text: (modelData.k === "date" && (win.query || win.inTrash) ? "Lokalizacja" : modelData.label) + (folder.sortKey === modelData.k ? listHeader.arrow : "")
                        color: folder.sortKey === modelData.k ? Theme.text : Theme.text2
                        font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: win.setSort(hdr.modelData.k) }
                    }
                }
                Rectangle { anchors.bottom: parent.bottom; x: 12; width: parent.width - 24; height: 1; color: Theme.line }
            }

            GridView {
                id: gridView
                visible: win.viewMode === "grid"
                x: 16; y: 12
                width: parent.width - 32
                height: parent.height - 12
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 128)))
                cellHeight: 156
                model: folder
                delegate: FileItem {
                    id: gItem
                    required property var model
                    required property int index
                    width: gridView.cellWidth; height: gridView.cellHeight
                    file: model
                    dateText: win.when(model.modified)
                    coordRoot: frame
                    enterDelay: win.entering ? Math.min(index, 16) * 8 : -1
                    showWhere: !!win.query || win.inTrash
                    selected: !!win.sel[model.url]
                    cut: Files.clipboardCut && Files.clipboardUrls.indexOf(model.url) >= 0
                    renaming: win.viewMode === "grid" && win.renaming === model.url
                    onClicked: (mods, button, wx, wy) => win.itemClicked(index, mods, button, wx, wy)
                    onDoubleClicked: win.openItem(folder.get(index))
                    onDragStarted: win.dragStart(index)
                    onDragMoved: (wx, wy) => win.dragMove(wx, wy)
                    onDragEnded: win.dragEnd()
                    onDroppedOn: (d) => win.handleDrop(d, gItem.model.url)
                    onRenameCommitted: (name) => win.commitRename(gItem.model.url, name)
                    onRenameCancelled: { win.renaming = ""; keys.forceActiveFocus(); }
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onTapped: (pt, button) => {
                        if (gridView.indexAt(pt.position.x + gridView.contentX, pt.position.y + gridView.contentY) >= 0) return;
                        keys.forceActiveFocus();
                        const p = gridView.mapToItem(frame, pt.position.x, pt.position.y);
                        if (button === Qt.RightButton) win.showBackgroundMenu(p.x, p.y);
                        else win.clearSel();
                    }
                }
            }

            ListView {
                id: listView
                visible: win.viewMode === "list"
                x: 12; y: listHeader.height + 4
                width: parent.width - 24
                height: parent.height - y
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: folder
                delegate: FileItem {
                    id: lItem
                    required property var model
                    required property int index
                    width: listView.width; height: 38
                    listMode: true
                    file: model
                    dateText: win.when(model.modified)
                    coordRoot: frame
                    enterDelay: win.entering ? Math.min(index, 16) * 8 : -1
                    showWhere: !!win.query || win.inTrash
                    selected: !!win.sel[model.url]
                    cut: Files.clipboardCut && Files.clipboardUrls.indexOf(model.url) >= 0
                    renaming: win.viewMode === "list" && win.renaming === model.url
                    onClicked: (mods, button, wx, wy) => win.itemClicked(index, mods, button, wx, wy)
                    onDoubleClicked: win.openItem(folder.get(index))
                    onDragStarted: win.dragStart(index)
                    onDragMoved: (wx, wy) => win.dragMove(wx, wy)
                    onDragEnded: win.dragEnd()
                    onDroppedOn: (d) => win.handleDrop(d, lItem.model.url)
                    onRenameCommitted: (name) => win.commitRename(lItem.model.url, name)
                    onRenameCancelled: { win.renaming = ""; keys.forceActiveFocus(); }
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onTapped: (pt, button) => {
                        if (listView.indexAt(pt.position.x + listView.contentX, pt.position.y + listView.contentY) >= 0) return;
                        keys.forceActiveFocus();
                        const p = listView.mapToItem(frame, pt.position.x, pt.position.y);
                        if (button === Qt.RightButton) win.showBackgroundMenu(p.x, p.y);
                        else win.clearSel();
                    }
                }
            }

            // Pusty folder / brak wyników
            Column {
                anchors.centerIn: parent
                spacing: 8
                visible: folder.count === 0 && !folder.loading
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 64; height: 64; radius: 18
                    color: Theme.fill
                    Icon { anchors.centerIn: parent; d: win.query ? Icons.search : (win.inTrash ? Icons.trash : Icons.folder); size: 28; color: Theme.text2 }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.query ? "Brak wyników dla „" + win.query + "”" : (win.inTrash ? "Kosz jest pusty" : "Ten folder jest pusty")
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.query ? "Szukam też we wszystkich podfolderach." : (win.inTrash ? "Usunięte pliki trafiają tutaj — możesz je przywrócić." : "Przeciągnij tu pliki albo kliknij prawym przyciskiem, żeby coś utworzyć.")
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                }
            }
        }

        // ——— Pasek stanu ———
        Rectangle {
            id: status
            x: pane.x; anchors.bottom: pane.bottom
            width: pane.width; height: 32
            color: "transparent"
            Rectangle { width: parent.width; height: 1; color: Theme.line }
            Text {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                text: {
                    const n = folder.count;
                    let s = folder.loading && win.query ? "Szukam…" : (win.query ? n + (n === 1 ? " wynik" : " wyników") : win.countText(n));
                    const k = win.selection.length;
                    if (k) s += " · zaznaczono " + k + " (" + folder.sizeText(win.selection) + ")";
                    return s;
                }
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "Spacja — podgląd · F2 — nazwa · Ctrl+Z — cofnij"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
        }

        // ——— Podgląd (spacja) ———
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.25)
            visible: opacity > 0
            opacity: win.quickLook ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
            MouseArea { anchors.fill: parent; onClicked: win.quickLook = null }
            Rectangle {
                id: ql
                readonly property var f: win.quickLook
                readonly property string text: f && !f.isImage ? Files.previewText(f.url) : ""
                anchors.centerIn: parent
                width: Math.min(parent.width - 80, f && (f.isImage || text) ? 640 : 380)
                height: Math.min(parent.height - 60, f && (f.isImage || text) ? 560 : 440)
                radius: 18
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                scale: win.quickLook ? 1 : 0.94
                Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack; easing.overshoot: 1.0 } }
                MouseArea { anchors.fill: parent }
                Rectangle {
                    id: qlBox
                    x: 20; y: 20; width: parent.width - 40; height: parent.height - 190; radius: 12
                    color: Theme.fill
                    clip: true
                    Image {
                        anchors.fill: parent; anchors.margins: 8
                        visible: !!ql.f && ql.f.isImage
                        source: ql.f && ql.f.isImage ? "file://" + ql.f.localPath : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                    Text {
                        anchors.fill: parent; anchors.margins: 14
                        visible: ql.text !== ""
                        text: ql.text
                        color: Theme.text
                        font.family: "monospace"; font.pixelSize: 12
                        wrapMode: Text.WrapAnywhere
                        elide: Text.ElideRight
                    }
                    Item {
                        anchors.centerIn: parent
                        width: 1; height: 1
                        visible: !!ql.f && !ql.f.isImage && ql.text === ""
                        Rectangle {
                            readonly property string ext: ql.f && ql.f.name.lastIndexOf(".") > 0 ? ql.f.name.slice(ql.f.name.lastIndexOf(".") + 1).toUpperCase() : ""
                            readonly property color tint: FileKinds.tint(ext)
                            anchors.centerIn: parent
                            width: 100; height: 124; radius: 16
                            color: Qt.alpha(tint, Theme.dark ? 0.28 : 0.16)
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 14
                                text: parent.ext
                                color: Theme.dark ? Qt.lighter(parent.tint, 1.9) : parent.tint
                                font.family: Theme.font; font.pixelSize: 20; font.letterSpacing: -0.4; font.weight: Font.Bold
                            }
                        }
                    }
                }
                Column {
                    x: 24; y: qlBox.y + qlBox.height + 18
                    width: parent.width - 48
                    spacing: 6
                    Text { width: parent.width; text: ql.f ? ql.f.name : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.letterSpacing: -0.2; font.weight: Font.DemiBold; elide: Text.ElideMiddle }
                    Text { text: ql.f ? ql.f.kind + (ql.f.sizeText ? " · " + ql.f.sizeText : "") + " · zmieniono " + win.when(ql.f.modified) : ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                    Text { width: parent.width; text: ql.f ? ql.f.where : ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; elide: Text.ElideMiddle }
                }
                Row {
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 20
                    x: 20
                    spacing: 8
                    Rectangle {
                        width: ql.width - 40 - 8 - 120; height: 40; radius: 10
                        color: Theme.accent
                        visible: !win.inTrash
                        Text { anchors.centerIn: parent; text: "Otwórz"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                        MouseArea { anchors.fill: parent; onClicked: { Files.open(ql.f.url); win.quickLook = null; } }
                    }
                    HoverButton {
                        width: win.inTrash ? ql.width - 40 : 120; height: 40; radius: 10
                        baseColor: Theme.fill
                        onClicked: win.quickLook = null
                        Text { anchors.centerIn: parent; text: "Zamknij"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                    }
                }
            }
        }

        // ——— Potwierdzenie ———
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.3)
            visible: !!win.confirm
            MouseArea { anchors.fill: parent; onClicked: win.confirm = null }
            Rectangle {
                anchors.centerIn: parent
                width: 400; height: confirmCol.implicitHeight + 48; radius: 16
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                MouseArea { anchors.fill: parent }
                Column {
                    id: confirmCol
                    x: 24; y: 24
                    width: parent.width - 48
                    spacing: 10
                    Text { width: parent.width; text: win.confirm ? win.confirm.title : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.letterSpacing: -0.2; font.weight: Font.DemiBold; wrapMode: Text.Wrap }
                    Text { width: parent.width; text: win.confirm ? win.confirm.text : ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; wrapMode: Text.Wrap }
                    Item { width: 1; height: 8 }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        HoverButton {
                            width: 90; height: 38; radius: 10; baseColor: Theme.fill
                            onClicked: win.confirm = null
                            Text { anchors.centerIn: parent; text: "Anuluj"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                        }
                        Rectangle {
                            width: dangerText.implicitWidth + 30; height: 38; radius: 10
                            color: dangerArea.containsMouse ? "#B92E2E" : "#D93B3B"
                            Text { id: dangerText; anchors.centerIn: parent; text: win.confirm ? win.confirm.button : ""; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                            MouseArea { id: dangerArea; anchors.fill: parent; hoverEnabled: true; onClicked: { const c = win.confirm; win.confirm = null; c.run(); keys.forceActiveFocus(); } }
                        }
                    }
                }
            }
        }

        // ——— Archiwum: „tylko do odczytu” i Wypakuj wszystko ———
        Rectangle {
            visible: win.inArchive
            anchors.horizontalCenter: content.horizontalCenter
            y: content.y + content.height - height - 14 - (toastTimer.running ? 54 : 0)
            Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
            width: archRow.implicitWidth + 16; height: 46; radius: 23
            color: Theme.surface
            border.width: 1; border.color: Theme.edge
            Row {
                id: archRow
                x: 18; anchors.verticalCenter: parent.verticalCenter
                spacing: 14
                Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.archive; size: 17; color: Theme.text2 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Archiwum — tylko do odczytu"
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                }
                HoverButton {
                    anchors.verticalCenter: parent.verticalCenter
                    width: extractAllText.implicitWidth + 28; height: 34; radius: 17
                    baseColor: Theme.accent
                    color: hovered ? Qt.lighter(Theme.accent, 1.12) : baseColor
                    onClicked: win.extractHere(win.archiveFile)
                    Text { id: extractAllText; anchors.centerIn: parent; text: "Wypakuj wszystko"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                }
            }
        }

        // ——— Postęp pakowania / wypakowywania ———
        Column {
            x: content.x + content.width - width - 16
            y: content.y + content.height - height - 16
            spacing: 8
            z: 50
            Repeater {
                model: Archiver.jobs
                delegate: Rectangle {
                    id: jobCard
                    required property var modelData
                    width: 320; height: 66; radius: 14
                    color: Theme.surface
                    border.width: 1; border.color: Theme.edge
                    Icon { x: 16; y: 14; d: Icons.archive; size: 18; color: Theme.accentText }
                    Text {
                        x: 44; y: 13; width: parent.width - 44 - 44
                        text: jobCard.modelData.title
                        elide: Text.ElideMiddle
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                    }
                    Text {
                        anchors.right: cancelJob.left; anchors.rightMargin: 4; y: 14
                        text: Math.round(jobCard.modelData.progress * 100) + "%"
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 }
                    }
                    Rectangle {
                        x: 44; y: 42; width: parent.width - 44 - 44; height: 5; radius: 2.5
                        color: Theme.fill
                        Rectangle {
                            width: parent.width * jobCard.modelData.progress; height: parent.height; radius: parent.radius
                            color: Theme.accent
                            Behavior on width { NumberAnimation { duration: 200 } }
                        }
                    }
                    HoverButton {
                        id: cancelJob
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30; height: 30; radius: 15
                        onClicked: Archiver.cancel(jobCard.modelData.id)
                        Icon { anchors.centerIn: parent; d: Icons.close; size: 13; stroke: 2; color: Theme.text2 }
                    }
                }
            }
        }

        // ——— Hasło do archiwum / Kompresuj… ———
        Rectangle {
            id: sheetShade
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.3)
            visible: !!win.archiveSheet
            z: 60
            readonly property bool compress: !!win.archiveSheet && win.archiveSheet.kind === "compress"
            property string format: "zip"
            property bool protect: false
            function close() { win.archiveSheet = null; keys.forceActiveFocus(); }
            function accept() {
                const s = win.archiveSheet;
                if (!s) return;
                if (compress) {
                    if (protect && pass.text === "") { pass.forceActiveFocus(); return; }
                    Archiver.compress(s.urls, nameField.text.trim() || s.name, format, protect && format === "zip" ? pass.text : "");
                } else {
                    if (pass.text === "") return;
                    Archiver.extract(s.archive, s.dest, pass.text);
                }
                close();
            }
            onVisibleChanged: {
                if (!visible) return;
                pass.text = "";
                protect = false;
                format = "zip";
                if (compress) { nameField.text = win.archiveSheet.name; nameField.selectAll(); nameField.forceActiveFocus(); }
                else pass.forceActiveFocus();
            }
            MouseArea { anchors.fill: parent; onClicked: sheetShade.close() }
            Rectangle {
                anchors.centerIn: parent
                width: 420; height: sheetCol.implicitHeight + 48; radius: 16
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                MouseArea { anchors.fill: parent }
                Column {
                    id: sheetCol
                    x: 24; y: 24
                    width: parent.width - 48
                    spacing: 12
                    Text {
                        width: parent.width
                        text: !win.archiveSheet ? "" : sheetShade.compress ? "Kompresuj " + win.countText(win.archiveSheet.urls.length)
                            : "„" + decodeURIComponent(win.archiveSheet.archive.split("/").pop()) + "” jest chronione hasłem"
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.letterSpacing: -0.2; font.weight: Font.DemiBold; wrapMode: Text.Wrap
                    }
                    Text {
                        visible: !sheetShade.compress
                        width: parent.width
                        text: win.archiveSheet && win.archiveSheet.wrong ? "Nieprawidłowe hasło. Spróbuj jeszcze raz." : "Wpisz hasło, aby wypakować pliki."
                        color: win.archiveSheet && win.archiveSheet.wrong ? Theme.danger : Theme.text2
                        font.family: Theme.font; font.pixelSize: 13; wrapMode: Text.Wrap
                    }
                    // Nazwa i format (tylko „Kompresuj”)
                    Field {
                        id: nameBox
                        visible: sheetShade.compress
                        label: "Nazwa"
                        suffix: "." + sheetShade.format
                        TextInput {
                            id: nameField
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: nameBox.suffixWidth + 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                            font.family: Theme.font; font.pixelSize: 13
                            clip: true
                            Keys.onReturnPressed: sheetShade.accept()
                            Keys.onEscapePressed: sheetShade.close()
                        }
                    }
                    Row {
                        visible: sheetShade.compress
                        spacing: 6
                        Repeater {
                            model: [["zip", "ZIP"], ["7z", "7z"], ["tar.gz", "TAR.GZ"], ["tar.xz", "TAR.XZ"]]
                            delegate: HoverButton {
                                id: fmt
                                required property var modelData
                                readonly property bool on: sheetShade.format === modelData[0]
                                width: fmtText.implicitWidth + 24; height: 30; radius: 15
                                baseColor: on ? Theme.accent : Theme.fill
                                color: on ? baseColor : (hovered ? Theme.hover : baseColor)
                                onClicked: sheetShade.format = fmt.modelData[0]
                                Text { id: fmtText; anchors.centerIn: parent; text: fmt.modelData[1]; color: fmt.on ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                            }
                        }
                    }
                    // Hasło: przy wypakowywaniu zawsze, przy pakowaniu — opcjonalnie (tylko ZIP, AES-256)
                    Row {
                        visible: sheetShade.compress && sheetShade.format === "zip"
                        spacing: 10
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20; radius: 6
                            color: sheetShade.protect ? Theme.accent : "transparent"
                            border.width: sheetShade.protect ? 0 : 1.5; border.color: Theme.text2
                            Icon { anchors.centerIn: parent; visible: sheetShade.protect; d: Icons.check; size: 14; stroke: 2.4; color: "white" }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Chroń hasłem"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                        TapHandler { onTapped: { sheetShade.protect = !sheetShade.protect; if (sheetShade.protect) pass.forceActiveFocus(); } }
                    }
                    Field {
                        visible: !sheetShade.compress || (sheetShade.protect && sheetShade.format === "zip")
                        label: "Hasło"
                        TextInput {
                            id: pass
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                            font.family: Theme.font; font.pixelSize: 13
                            clip: true
                            Keys.onReturnPressed: sheetShade.accept()
                            Keys.onEscapePressed: sheetShade.close()
                        }
                    }
                    Item { width: 1; height: 4 }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        HoverButton {
                            width: 90; height: 38; radius: 10; baseColor: Theme.fill
                            onClicked: sheetShade.close()
                            Text { anchors.centerIn: parent; text: "Anuluj"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                        }
                        HoverButton {
                            width: okText.implicitWidth + 30; height: 38; radius: 10
                            baseColor: Theme.accent
                            color: hovered ? Qt.lighter(Theme.accent, 1.12) : baseColor
                            onClicked: sheetShade.accept()
                            Text { id: okText; anchors.centerIn: parent; text: sheetShade.compress ? "Kompresuj" : "Wypakuj"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                        }
                    }
                }
            }
        }

        // ——— Formatuj dysk ———
        Rectangle {
            id: formatShade
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.3)
            visible: !!win.formatSheet
            z: 60
            property string type: "exfat"
            readonly property var types: [
                { id: "exfat", name: "exFAT", hint: "Zalecany — działa w Windows, macOS, telewizorach; pliki dowolnej wielkości" },
                { id: "vfat", name: "FAT32", hint: "Dla starszych urządzeń (radio, drukarka); pliki do 4 GB" },
                { id: "ntfs", name: "NTFS", hint: "Dla dysków używanych głównie z Windows" },
                { id: "ext4", name: "ext4", hint: "Tylko dla Linuksa (np. kopie zapasowe Aster)" }
            ]
            readonly property var current: types.find(t => t.id === type)
            function close() { win.formatSheet = null; keys.forceActiveFocus(); }
            function accept() {
                const s = win.formatSheet;
                if (!s) return;
                Drives.format(s.udi, type, labelField.text);
                close();
            }
            onVisibleChanged: {
                if (!visible) return;
                type = "exfat";
                labelField.text = win.formatSheet.name === "Dysk USB" ? "" : win.formatSheet.name;
                labelField.selectAll();
                labelField.forceActiveFocus();
            }
            MouseArea { anchors.fill: parent; onClicked: formatShade.close() }
            Rectangle {
                anchors.centerIn: parent
                width: 440; height: formatCol.implicitHeight + 48; radius: 16
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                MouseArea { anchors.fill: parent }
                Column {
                    id: formatCol
                    x: 24; y: 24
                    width: parent.width - 48
                    spacing: 12
                    Text {
                        width: parent.width
                        text: win.formatSheet ? "Formatuj „" + win.formatSheet.name + "” (" + win.formatSheet.sizeText + ")" : ""
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.letterSpacing: -0.2; font.weight: Font.DemiBold; wrapMode: Text.Wrap
                    }
                    Field {
                        id: labelBox
                        label: "Nazwa dysku"
                        TextInput {
                            id: labelField
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            maximumLength: Drives.labelLimit(formatShade.type)
                            color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                            font.family: Theme.font; font.pixelSize: 13
                            font.capitalization: formatShade.type === "vfat" ? Font.AllUppercase : Font.MixedCase
                            clip: true
                            Keys.onReturnPressed: formatShade.accept()
                            Keys.onEscapePressed: formatShade.close()
                        }
                    }
                    Text { text: "System plików"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                    Row {
                        spacing: 6
                        Repeater {
                            model: formatShade.types
                            delegate: HoverButton {
                                id: fsBtn
                                required property var modelData
                                readonly property bool on: formatShade.type === modelData.id
                                width: fsText.implicitWidth + 26; height: 30; radius: 15
                                baseColor: on ? Theme.accent : Theme.fill
                                color: on ? baseColor : (hovered ? Theme.hover : baseColor)
                                onClicked: formatShade.type = fsBtn.modelData.id
                                Text { id: fsText; anchors.centerIn: parent; text: fsBtn.modelData.name; color: fsBtn.on ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        text: formatShade.current ? formatShade.current.hint : ""
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; wrapMode: Text.Wrap
                    }
                    Rectangle {
                        width: parent.width; height: warnText.implicitHeight + 20; radius: 10
                        color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.1)
                        Text {
                            id: warnText
                            x: 12; width: parent.width - 24
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Wszystkie pliki na tym dysku zostaną usunięte. Tego nie da się cofnąć."
                            color: Theme.danger; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium; wrapMode: Text.Wrap
                        }
                    }
                    Item { width: 1; height: 2 }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        HoverButton {
                            width: 90; height: 38; radius: 10; baseColor: Theme.fill
                            onClicked: formatShade.close()
                            Text { anchors.centerIn: parent; text: "Anuluj"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                        }
                        HoverButton {
                            width: fmtOk.implicitWidth + 30; height: 38; radius: 10
                            baseColor: "#D93B3B"
                            color: hovered ? "#B92E2E" : baseColor
                            onClicked: formatShade.accept()
                            Text { id: fmtOk; anchors.centerIn: parent; text: "Formatuj"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                        }
                    }
                }
            }
        }

        // ——— Komunikat z „Cofnij” ———
        Rectangle {
            anchors.horizontalCenter: content.horizontalCenter
            y: parent.height - status.height - height - (toastTimer.running ? 16 : -8)
            width: Math.min(content.width - 40, toastRow.implicitWidth + 32); height: 42; radius: 21
            color: Theme.text
            opacity: toastTimer.running ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
            Row {
                id: toastRow
                anchors.centerIn: parent
                spacing: 14
                Text { anchors.verticalCenter: parent.verticalCenter; text: win.toastText; color: Theme.surface; font.family: Theme.font; font.pixelSize: 13; elide: Text.ElideRight; width: Math.min(implicitWidth, content.width - 140) }
                Text {
                    visible: win.toastUndo
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Cofnij"
                    color: Theme.dark ? Theme.accent : Qt.lighter(Theme.accent, 1.6)
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold
                    MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: { toastTimer.stop(); win.doUndo(); } }
                }
            }
        }
        Timer { id: toastTimer; interval: 4500 }

        // Przeciągane pliki — etykieta przy kursorze
        Item {
            id: ghost
            property var urls: []
            property string label
            width: 1; height: 1
            z: 400
            visible: Drag.active
            Drag.keys: ["aster-files"]
            Drag.hotSpot.x: 0
            Drag.hotSpot.y: 0
            Rectangle {
                x: 14; y: 10
                width: ghostRow.implicitWidth + 20; height: 34; radius: 17
                color: Theme.accent
                Row {
                    id: ghostRow
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.copy; size: 15; color: "white" }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: ghost.label; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                }
            }
        }

        ContextMenu {
            id: menu
            onTriggered: (a) => win.runAction(a)
        }
    }

    FolderDialog {
        id: extractDialog
        property string archive
        title: "Wypakuj do folderu"
        onAccepted: Archiver.extract(archive, String(selectedFolder), "")
    }

    // Pole z podpisem nad nim; suffix — stała końcówka po prawej (np. „.zip”)
    component Field: Column {
        id: fld
        property string label
        property string suffix
        readonly property real suffixWidth: suffixText.visible ? suffixText.implicitWidth + 4 : 0
        default property alias input: box.data
        width: parent ? parent.width : 300
        spacing: 6
        Text { text: fld.label; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
        Rectangle {
            id: box
            width: parent.width; height: 38; radius: 10
            color: Theme.fill
            border.width: 1; border.color: Theme.edge
            Text {
                id: suffixText
                visible: fld.suffix !== ""
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: fld.suffix
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
            }
        }
    }

    // Do testów (ASTER_OPEN, kroki po „;”): menu:nazwa | open:nazwa | compress | zip | extract:nazwa
    function testOpen(what) {
        const pick = (name) => { const i = folder.indexOfName(name); if (i >= 0) { setSel([folder.get(i).url]); lastIndex = i; } return i; };
        if (what.startsWith("menu:")) { pick(what.substring(5)); showItemMenu(420, 220); }
        else if (what.startsWith("open:")) { if (pick(what.substring(5)) >= 0) openSelected(); }
        else if (what.startsWith("select:")) setSel(what.substring(7).split(",").map(n => folder.get(folder.indexOfName(n)).url));
        else if (what === "compress") askCompress();
        else if (what === "zip") compressZip();
        else if (what === "zippass") Archiver.compress(localSelection(), "Szyfrowane", "zip", "haslo");
        else if (what.startsWith("extract:")) { if (pick(what.substring(8)) >= 0) extractHere(selectedFile().url); }
        else if (what === "bgmenu") showBackgroundMenu(420, 220);
        else if (what === "drivemenu") driveMenu(Drives.list[0], 120, 470);
        else if (what === "format") formatSheet = { udi: Drives.list[0].udi, name: Drives.list[0].name, sizeText: Drives.list[0].sizeText };
    }
}
