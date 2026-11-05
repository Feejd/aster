pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Dialogs
import QtCore
import Aster.Ui
import Aster.Editor

// Edytor tekstu Aster (zamiast Kate i KWrite) — jak Notatnik w Windows 11:
//  • karty; zamknięcie okna niczego nie gubi — niezapisane karty wracają przy następnym otwarciu,
//  • szukanie i zamiana (Ctrl+F, Ctrl+H), przejście do wiersza (Ctrl+G), numery wierszy, zawijanie,
//  • kolorowanie kodu jak w Kate, rozpoznawanie kodowania (UTF-8, pliki z Windows: Windows-1250) i końców wierszy.
Window {
    id: win
    width: 980 + 2 * m
    height: 680 + 2 * m
    minimumWidth: 460 + 2 * m
    minimumHeight: 300 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: cur ? (cur.modified ? "• " : "") + tabTitle(current) + " — Edytor tekstu" : "Edytor tekstu"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 12

    Settings {
        id: prefs
        category: "editor"
        property bool wrap: true
        property bool lineNumbers: true
        property bool monospace: true
        property real fontSize: 14
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
    function page(i) { return pages.itemAt(i); }
    function tabTitle(i) {
        if (i < 0 || i >= tabs.count) return "";
        const t = tabs.get(i);
        return t.path ? Editor.fileName(t.path) : t.title;
    }
    function untitledName() {
        const used = [];
        for (let i = 0; i < tabs.count; ++i) if (!tabs.get(i).path) used.push(tabs.get(i).title);
        if (used.indexOf("Bez tytułu") < 0) return "Bez tytułu";
        for (let n = 2; ; ++n) if (used.indexOf("Bez tytułu " + n) < 0) return "Bez tytułu " + n;
    }
    function addTab(t, at) {
        const uid = ++uidSeq;
        pendingText[uid] = t.text || "";
        pendingCursor[uid] = t.cursor || 0;
        const i = at === undefined ? tabs.count : at;
        tabs.insert(i, { uid: uid, path: t.path || "", title: t.title || untitledName(), encoding: t.encoding || "UTF-8",
                         eol: t.eol || "\n", readOnly: !!t.readOnly, draftModified: !!t.modified, changedOnDisk: false });
        revision++;
        activate(i);
        return i;
    }
    function newTab() { addTab({}, current + 1); }
    function activate(i) {
        if (i < 0 || i >= tabs.count) return;
        current = i;
        revision++;
        Qt.callLater(() => { if (win.cur) win.cur.focusEditor(); });
    }
    function indexOfPath(p) {
        for (let i = 0; i < tabs.count; ++i) if (tabs.get(i).path === p) return i;
        return -1;
    }
    function openFile(p) {
        p = Editor.toPath(p);
        const existing = indexOfPath(p);
        if (existing >= 0) { activate(existing); return; }
        const res = Editor.load(p);
        if (!res.ok) { toast(res.error); return; }
        // Pusta, nietknięta karta „Bez tytułu” — zastąp ją zamiast dokładać nową
        if (tabs.count === 1 && !tabs.get(0).path && cur && cur.edit.length === 0 && !cur.modified) {
            tabs.remove(0);
            revision++;
        }
        addTab({ path: p, text: res.text, encoding: res.encoding, eol: res.eol, readOnly: res.readOnly });
        if (res.encoding !== "UTF-8") toast("Otwarto w kodowaniu " + res.encoding);
        watchAll();
    }
    function watchAll() {
        const list = [];
        for (let i = 0; i < tabs.count; ++i) if (tabs.get(i).path) list.push(tabs.get(i).path);
        Editor.watch(list);
    }

    // ——— Zapisywanie ———
    property var afterSave: null
    function save(i, then) {
        const t = tabs.get(i), p = page(i);
        if (!t.path) { saveAs(i, then); return; }
        lastSave[t.path] = Date.now();
        if (Editor.save(t.path, p.edit.text, t.encoding, t.eol)) {
            p.markSaved();
            tabs.setProperty(i, "draftModified", false);
            tabs.setProperty(i, "changedOnDisk", false);
            revision++;
            if (then) then();
        }
    }
    function saveAs(i, then) {
        afterSave = { index: i, then: then || null };
        const t = tabs.get(i);
        saveDialog.currentFolder = "file://" + (t.path ? Editor.folder(t.path) : Editor.documentsDir());
        saveDialog.selectedFile = "file://" + (t.path ? t.path : Editor.documentsDir() + "/" + Editor.suggestedName(page(i).edit.text));
        saveDialog.open();
    }
    function saveAll() { for (let i = 0; i < tabs.count; ++i) if (page(i).modified && tabs.get(i).path) save(i); }

    // ——— Zamykanie kart ———
    property var confirm: null
    function closeTab(i, force) {
        if (i < 0 || i >= tabs.count) return;
        const p = page(i);
        if (!force && p && p.modified && (p.edit.length > 0 || tabs.get(i).path)) {
            activate(i);
            confirm = { index: i, name: tabTitle(i) };
            return;
        }
        tabs.remove(i);
        revision++;
        if (tabs.count === 0) { addTab({}); return; }
        current = Math.min(current > i ? current - 1 : current, tabs.count - 1);
        revision++;
        activate(current);
        watchAll();
    }

    // ——— Sesja: karty wracają po ponownym otwarciu (także niezapisane) ———
    function saveSession() {
        const list = [];
        for (let i = 0; i < tabs.count; ++i) {
            const t = tabs.get(i), p = page(i);
            if (!p) continue;
            if (!t.path && p.edit.length === 0) continue;
            list.push({ path: t.path, title: t.title, encoding: t.encoding, eol: t.eol, cursor: p.edit.cursorPosition,
                        modified: p.modified, text: p.modified ? p.edit.text : "" });
        }
        Editor.saveSession(list, current);
    }
    Timer { interval: 4000; running: true; repeat: true; onTriggered: win.saveSession() }
    onClosing: saveSession()

    Component.onCompleted: {
        effectsTimer.restart();
        const s = Editor.loadSession();
        (s.tabs || []).forEach(t => win.addTab(t));
        // Pliki z wiersza poleceń (dwuklik w Plikach) — na końcu, aktywny ostatni
        const files = Editor.pendingFiles;
        if (files.length) files.forEach(f => win.openFile(f));
        else if (tabs.count) activate(Math.min(s.current || 0, tabs.count - 1));
        if (tabs.count === 0) addTab({});
        watchAll();
    }
    Connections {
        target: Editor
        function onOpenRequested(files) { files.forEach(f => win.openFile(f)); }
        function onMessage(text) { win.toast(text); }
        function onFileChanged(path) {
            const i = win.indexOfPath(path);
            if (i < 0 || Date.now() - (win.lastSave[path] || 0) < 2000) return;
            const p = win.page(i);
            if (!Editor.exists(path)) { win.tabs_setDeleted(i); return; }
            if (!p.modified) {
                // Bez własnych zmian — po cichu wczytaj nową wersję (kursor zostaje)
                const res = Editor.load(path);
                if (res.ok) p.load(res.text, p.edit.cursorPosition);
            } else {
                tabs.setProperty(i, "changedOnDisk", true);
                win.revision++;
            }
        }
    }
    function tabs_setDeleted(i) { tabs.setProperty(i, "changedOnDisk", true); revision++; }
    function reloadCurrent() {
        const t = tabs.get(current);
        const res = Editor.load(t.path);
        if (!res.ok) { toast(res.error); return; }
        cur.load(res.text, cur.edit.cursorPosition);
        tabs.setProperty(current, "changedOnDisk", false);
        revision++;
    }

    function toast(text) { toastBox.text = text; toastBox.shown = true; toastTimer.restart(); }
    function zoom(d) {
        prefs.fontSize = d === 0 ? 14 : Math.max(9, Math.min(40, prefs.fontSize + d));
        toast("Rozmiar tekstu: " + Math.round(prefs.fontSize / 14 * 100) + "%");
    }

    FileDialog {
        id: openDialog
        title: "Otwórz"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Pliki tekstowe (*.txt *.md *.log *.csv *.json *.xml *.ini *.conf *.cfg *.yaml *.yml *.sh *.py *.js *.ts *.html *.css *.c *.cpp *.h *.qml *.java *.rs *.go)", "Wszystkie pliki (*)"]
        onAccepted: selectedFiles.forEach(f => win.openFile(String(f)))
    }
    FileDialog {
        id: saveDialog
        title: "Zapisz jako"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Plik tekstowy (*.txt)", "Wszystkie pliki (*)"]
        onAccepted: {
            const a = win.afterSave;
            if (!a) return;
            const path = Editor.toPath(String(selectedFile));
            tabs.setProperty(a.index, "path", path);
            win.revision++;
            win.save(a.index, a.then);
            win.watchAll();
            win.afterSave = null;
        }
        onRejected: win.afterSave = null
    }

    // ——— Szukaj / zamień ———
    property var matches: []
    property int matchIndex: -1
    function findAll() {
        matches = [];
        matchIndex = -1;
        const q = findField.text;
        if (!q || !cur) return;
        const text = matchCase ? cur.edit.text : cur.edit.text.toLowerCase();
        const needle = matchCase ? q : q.toLowerCase();
        const out = [];
        let i = text.indexOf(needle);
        while (i >= 0 && out.length < 20000) { out.push(i); i = text.indexOf(needle, i + Math.max(1, needle.length)); }
        matches = out;
        // Najbliższe trafienie od kursora
        const c = cur.edit.selectionStart;
        let k = out.findIndex(p => p >= c);
        if (k < 0) k = out.length ? 0 : -1;
        if (k >= 0) select(k);
    }
    function select(k) {
        if (!matches.length || !cur) return;
        matchIndex = (k + matches.length) % matches.length;
        cur.edit.select(matches[matchIndex], matches[matchIndex] + findField.text.length);
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
        const n = matches.length;
        const e = cur.edit;
        // Od końca — wcześniejsze pozycje się nie przesuwają; całość cofa się kilkoma Ctrl+Z
        for (let k = matches.length - 1; k >= 0; --k) {
            e.remove(matches[k], matches[k] + findField.text.length);
            e.insert(matches[k], replaceField.text);
        }
        findAll();
        toast("Zamieniono " + Editor.number(n) + (n === 1 ? " raz" : " razy"));
    }
    property bool matchCase: false
    function openFind(replace) {
        findBar.shown = true;
        findBar.replace = replace;
        if (cur && cur.edit.selectedText && cur.edit.selectedText.indexOf(" ") < 0) findField.text = cur.edit.selectedText;
        findField.forceActiveFocus();
        findField.selectAll();
        findAll();
    }
    function closeFind() { findBar.shown = false; if (cur) cur.focusEditor(); }

    // ——— Menu ———
    function showMenu() {
        const p = moreBtn.mapToItem(frame, moreBtn.width, moreBtn.height + 6);
        menu.openAt(p.x - 250, p.y, [
            { label: "Nowa karta", icon: "plus", shortcut: "Ctrl+N", action: "new" },
            { label: "Otwórz…", icon: "folder", shortcut: "Ctrl+O", action: "open" },
            { label: "Zapisz", icon: "download", shortcut: "Ctrl+S", action: "save" },
            { label: "Zapisz jako…", icon: "filePlus", shortcut: "Ctrl+Shift+S", action: "saveas" },
            { label: "Zapisz wszystko", icon: "copy", shortcut: "Ctrl+Alt+S", action: "saveall" },
            { separator: true },
            { label: "Znajdź", icon: "search", shortcut: "Ctrl+F", action: "find" },
            { label: "Zamień", icon: "pencil", shortcut: "Ctrl+H", action: "replace" },
            { label: "Przejdź do wiersza", icon: "arrow", shortcut: "Ctrl+G", action: "goto" },
            { separator: true },
            { label: "Zawijaj wiersze", icon: prefs.wrap ? "check" : "", shortcut: "Alt+Z", action: "wrap" },
            { label: "Numery wierszy", icon: prefs.lineNumbers ? "check" : "", action: "numbers" },
            { label: "Czcionka o stałej szerokości", icon: prefs.monospace ? "check" : "", action: "mono" },
            { separator: true },
            { label: "Pokaż w folderze", icon: "folder", action: "folder", enabled: !!(tabs.count && tabs.get(win.current).path) }
        ]);
    }
    function runMenu(a) {
        if (a === "new") newTab();
        else if (a === "open") openDialog.open();
        else if (a === "save") save(current);
        else if (a === "saveas") saveAs(current);
        else if (a === "saveall") saveAll();
        else if (a === "find") openFind(false);
        else if (a === "replace") openFind(true);
        else if (a === "goto") openGoto();
        else if (a === "wrap") prefs.wrap = !prefs.wrap;
        else if (a === "numbers") prefs.lineNumbers = !prefs.lineNumbers;
        else if (a === "mono") prefs.monospace = !prefs.monospace;
        else if (a === "folder") Editor.showInFolder(tabs.get(current).path);
        else if (a.startsWith("enc:")) { tabs.setProperty(current, "encoding", a.slice(4)); revision++; if (cur) cur.edit.textDocument.modified = true; toast("Przy zapisie: " + a.slice(4)); }
        else if (a.startsWith("eol:")) { tabs.setProperty(current, "eol", a.slice(4) === "crlf" ? "\r\n" : "\n"); revision++; if (cur) cur.edit.textDocument.modified = true; }
        else if (a === "tab:close") closeTab(menu.tab);
        else if (a === "tab:others") { const keep = tabs.get(menu.tab).uid; for (let i = tabs.count - 1; i >= 0; --i) if (tabs.get(i).uid !== keep) closeTab(i); }
        else if (a === "tab:folder") Editor.showInFolder(tabs.get(menu.tab).path);
        if (!findBar.shown && !gotoBox.shown && cur) Qt.callLater(cur.focusEditor);
    }
    function showStatusMenu(kind, item) {
        const p = item.mapToItem(frame, 0, 0);
        const t = tabs.get(current);
        const items = kind === "enc"
            ? ["UTF-8", "UTF-8 BOM", "Windows-1250", "ISO-8859-2"].map(e => ({ label: e, icon: t.encoding === e ? "check" : "", action: "enc:" + e }))
            : [{ label: "Linux, macOS (LF)", icon: t.eol === "\n" ? "check" : "", action: "eol:lf" }, { label: "Windows (CRLF)", icon: t.eol === "\r\n" ? "check" : "", action: "eol:crlf" }];
        menu.openAt(p.x, p.y - items.length * 34 - 18, items);
    }
    function openGoto() { gotoBox.shown = true; gotoField.text = ""; gotoField.forceActiveFocus(); }

    // Do testów (ASTER_OPEN): find:tekst | replace | menu | goto | close | wrap
    function testOpen(what) {
        if (what.startsWith("find:")) { findField.text = what.slice(5); openFind(false); findField.text = what.slice(5); findAll(); }
        else if (what === "replace") { openFind(true); findField.text = "Aster"; replaceField.text = "System"; findAll(); }
        else if (what === "menu") showMenu();
        else if (what === "goto") openGoto();
        else if (what === "close") { cur.edit.insert(0, "x"); closeTab(current); }
        else if (what === "nowrap") prefs.wrap = false;
        else if (what === "save") { cur.edit.insert(0, "Żółw "); save(current); }
    }

    // ——— Skróty ———
    Shortcut { sequences: ["Ctrl+N", "Ctrl+T"]; onActivated: win.newTab() }
    Shortcut { sequence: "Ctrl+O"; onActivated: openDialog.open() }
    Shortcut { sequence: "Ctrl+S"; onActivated: win.save(win.current) }
    Shortcut { sequence: "Ctrl+Shift+S"; onActivated: win.saveAs(win.current) }
    Shortcut { sequence: "Ctrl+Alt+S"; onActivated: win.saveAll() }
    Shortcut { sequence: "Ctrl+W"; onActivated: win.closeTab(win.current) }
    Shortcut { sequence: "Ctrl+F"; onActivated: win.openFind(false) }
    Shortcut { sequence: "Ctrl+H"; onActivated: win.openFind(true) }
    Shortcut { sequence: "F3"; onActivated: { if (!findField.text) win.openFind(false); else win.select(win.matchIndex + 1); } }
    Shortcut { sequence: "Shift+F3"; onActivated: win.select(win.matchIndex - 1) }
    Shortcut { sequence: "Ctrl+G"; onActivated: win.openGoto() }
    Shortcut { sequence: "Alt+Z"; onActivated: prefs.wrap = !prefs.wrap }
    Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: win.zoom(1) }
    Shortcut { sequence: "Ctrl+-"; onActivated: win.zoom(-1) }
    Shortcut { sequence: "Ctrl+0"; onActivated: win.zoom(0) }
    Shortcut { sequences: ["Ctrl+Tab", "Ctrl+PgDown"]; onActivated: win.activate((win.current + 1) % tabs.count) }
    Shortcut { sequences: ["Ctrl+Shift+Tab", "Ctrl+PgUp"]; onActivated: win.activate((win.current - 1 + tabs.count) % tabs.count) }
    Shortcut { sequence: "F11"; onActivated: { if (win.visibility === Window.FullScreen) win.showNormal(); else win.showFullScreen(); } }
    Shortcut { sequence: "Esc"; enabled: findBar.shown || gotoBox.shown || !!win.confirm
        onActivated: { if (win.confirm) win.confirm = null; else if (gotoBox.shown) { gotoBox.shown = false; win.cur.focusEditor(); } else win.closeFind(); } }

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
            onDropped: (drop) => { if (drop.hasUrls) drop.urls.forEach(u => win.openFile(String(u))); }
        }

        // ——— Pasek kart ———
        Item {
            id: toolbar
            width: parent.width; height: 50
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
            TapHandler { onDoubleTapped: win.newTab() }

            Flickable {
                id: tabFlick
                x: 12
                width: Math.min(tabRow.width, rightGroup.x - x - 46)
                height: parent.height
                contentWidth: tabRow.width
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentWidth > width
                clip: true
                Row {
                    id: tabRow
                    height: parent.height
                    spacing: 4
                    readonly property real tabWidth: Math.max(110, Math.min(220, (rightGroup.x - 12 - 46 - (tabs.count - 1) * 4) / Math.max(1, tabs.count)))
                    Repeater {
                        model: tabs
                        delegate: TabButton {}
                    }
                }
            }
            ToolBtn {
                anchors.left: tabFlick.right; anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                icon: "plus"
                onClicked: win.newTab()
            }
            Row {
                id: rightGroup
                anchors.right: winButtons.left; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                ToolBtn { icon: "search"; onClicked: findBar.shown ? win.closeFind() : win.openFind(false) }
                ToolBtn { id: moreBtn; icon: "more"; onClicked: win.showMenu() }
            }
            WindowButtons {
                id: winButtons
                window: win
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ——— Tekst ———
        Rectangle {
            id: pane
            y: toolbar.height
            width: parent.width
            height: parent.height - y - status.height
            color: Theme.paneGlass
            Rectangle { width: parent.width; height: 1; color: Theme.line }

            // Plik zmieniony przez inny program
            Rectangle {
                id: banner
                visible: tabs.count > 0 && win.revision >= 0 && tabs.get(win.current).changedOnDisk
                width: parent.width; height: visible ? 40 : 0
                y: 1
                color: Theme.accentAlpha(Theme.dark ? 0.18 : 0.09)
                Text {
                    x: 18; anchors.verticalCenter: parent.verticalCenter
                    text: tabs.count && Editor.exists(tabs.get(win.current).path) ? "Ten plik zmienił inny program." : "Ten plik został usunięty albo przeniesiony."
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Pill { visible: tabs.count && Editor.exists(tabs.get(win.current).path); text: "Wczytaj tę wersję"; onClicked: win.reloadCurrent() }
                    Pill { text: "Zostaw moją"; onClicked: { tabs.setProperty(win.current, "changedOnDisk", false); win.revision++; } }
                }
            }

            Repeater {
                id: pages
                model: tabs
                delegate: EditorPage {
                    id: pg
                    required property int index
                    required property int uid
                    required property bool draftModified
                    required property var model
                    path: model.path
                    title: model.title
                    y: banner.y + banner.height
                    width: pane.width
                    height: pane.height - y
                    visible: index === win.current
                    wrap: prefs.wrap
                    lineNumbers: prefs.lineNumbers
                    fontFamily: prefs.monospace ? "JetBrains Mono" : Theme.font
                    fontSize: prefs.fontSize
                    onZoomRequested: (d) => win.zoom(d)
                    Component.onCompleted: {
                        load(win.pendingText[uid] || "", win.pendingCursor[uid] || 0);
                        if (draftModified) edit.textDocument.modified = true;     // niezapisana karta z poprzedniej sesji
                        delete win.pendingText[uid];
                        delete win.pendingCursor[uid];
                    }
                }
            }

            // Szukaj i zamień
            Rectangle {
                id: findBar
                property bool shown: false
                property bool replace: false
                anchors.right: parent.right; anchors.rightMargin: 16
                y: shown ? banner.height + 12 : -height - 4
                visible: shown || y > -height
                Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
                z: 10
                width: 420; height: replace ? 92 : 46; radius: 16
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
                                text: win.matches.length === 0 ? "Brak" : (win.matchIndex + 1) + " z " + Editor.number(win.matches.length)
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

            // Przejdź do wiersza
            Rectangle {
                id: gotoBox
                property bool shown: false
                visible: shown
                anchors.horizontalCenter: parent.horizontalCenter
                y: banner.height + 12
                z: 10
                width: 300; height: 46; radius: 16
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "Wiersz"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                TextInput {
                    id: gotoField
                    x: 76; width: parent.width - 92
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 14
                    validator: IntValidator { bottom: 1 }
                    onAccepted: { gotoBox.shown = false; if (win.cur && text) win.cur.goToLine(Number(text)); }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !gotoField.text
                        text: win.cur ? "1–" + Editor.number(Editor.lineColumn(win.cur.edit.textDocument, win.cur.edit.length).y + 1) : ""
                        color: Theme.text2; font: gotoField.font
                    }
                }
            }
        }

        // ——— Pasek stanu ———
        Item {
            id: status
            anchors.bottom: parent.bottom
            width: parent.width; height: 32
            Rectangle { width: parent.width; height: 1; color: Theme.line }
            Row {
                x: 18; anchors.verticalCenter: parent.verticalCenter
                spacing: 18
                StatusText { text: win.cur ? "Wiersz " + Editor.number(win.cur.lineCol.y + 1) + ", kolumna " + (win.cur.lineCol.x + 1) : "" }
                StatusText {
                    text: !win.cur ? "" : win.cur.edit.selectedText ? "Zaznaczono " + Editor.number(win.cur.edit.selectedText.length) + " zn."
                                                                   : Editor.number(win.cur.edit.length) + " znaków"
                }
                StatusText { visible: tabs.count > 0 && win.revision >= 0 && tabs.get(win.current).readOnly; text: "Tylko do odczytu"; color: Theme.danger }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                StatusBtn { text: win.cur ? win.cur.language : "" }
                StatusBtn { text: Math.round(prefs.fontSize / 14 * 100) + "%"; onClicked: win.zoom(0) }
                StatusBtn {
                    id: eolBtn
                    text: tabs.count && win.revision >= 0 ? (tabs.get(win.current).eol === "\r\n" ? "Windows (CRLF)" : "Linux (LF)") : ""
                    onClicked: win.showStatusMenu("eol", eolBtn)
                }
                StatusBtn {
                    id: encBtn
                    text: tabs.count && win.revision >= 0 ? tabs.get(win.current).encoding : ""
                    onClicked: win.showStatusMenu("enc", encBtn)
                }
            }
        }

        // ——— Pytanie przy zamykaniu karty ze zmianami ———
        Item {
            anchors.fill: parent
            visible: !!win.confirm
            z: 200
            Rectangle { anchors.fill: parent; radius: win.r; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.25) }
            MouseArea { anchors.fill: parent; onClicked: win.confirm = null }
            Rectangle {
                anchors.centerIn: parent
                width: 420; height: dlgCol.implicitHeight + 44
                radius: 22
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                MouseArea { anchors.fill: parent }
                Column {
                    id: dlgCol
                    x: 24; y: 22; width: parent.width - 48
                    spacing: 8
                    Text { width: parent.width; wrapMode: Text.Wrap; text: win.confirm ? "Zapisać zmiany w „" + win.confirm.name + "”?" : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold }
                    Text { width: parent.width; wrapMode: Text.Wrap; text: "Jeśli nie zapiszesz, zmiany w tej karcie przepadną."; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                    Item { width: 1; height: 10 }
                    Item {
                        width: parent.width; height: 34
                        Pill { text: "Nie zapisuj"; danger: true; onClicked: { const i = win.confirm.index; win.confirm = null; win.closeTab(i, true); } }
                        Row {
                            anchors.right: parent.right
                            spacing: 8
                            Pill { text: "Anuluj"; onClicked: win.confirm = null }
                            Pill { text: "Zapisz"; primary: true; onClicked: { const i = win.confirm.index; win.confirm = null; win.save(i, () => win.closeTab(win.indexOfUid(tabs.get(i).uid), true)); } }
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
            z: 300
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
            onTriggered: (a) => win.runMenu(a)
        }
    }
    function indexOfUid(uid) {
        for (let i = 0; i < tabs.count; ++i) if (tabs.get(i).uid === uid) return i;
        return -1;
    }

    // ——— Elementy ———
    component TabButton: Rectangle {
        id: tab
        required property int index
        required property string path
        required property string title
        readonly property bool active: index === win.current
        readonly property bool dirty: { win.revision; const p = win.page(index); return !!p && p.modified; }
        width: tabRow.tabWidth; height: 34
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        radius: 10
        color: active ? Theme.paneGlass : (tabArea.containsMouse ? Theme.hover : "transparent")
        border.width: active ? 1 : 0; border.color: Theme.edge
        Icon {
            x: 12; anchors.verticalCenter: parent.verticalCenter
            d: Icons.doc; size: 14; color: tab.active ? Theme.accentText : Theme.text2
        }
        Text {
            x: 34; width: parent.width - 34 - 30
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideMiddle
            text: tab.path ? Editor.fileName(tab.path) : tab.title
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 13; font.weight: tab.active ? Font.Medium : Font.Normal
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
                        { label: "Zamknij kartę", icon: "close", shortcut: "Ctrl+W", action: "tab:close" },
                        { label: "Zamknij pozostałe", icon: "close", action: "tab:others", enabled: tabs.count > 1 },
                        { separator: true },
                        { label: "Pokaż w folderze", icon: "folder", action: "tab:folder", enabled: !!tab.path }
                    ]);
                    return;
                }
                win.activate(tab.index);
            }
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
                color: Theme.text2
            }
            Icon {
                visible: !tab.dirty || parent.hovered || tabArea.containsMouse
                anchors.centerIn: parent; d: Icons.close; size: 12; stroke: 2; color: Theme.text2
            }
        }
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
    component StatusText: Text {
        color: Theme.text2
        font.family: Theme.font; font.pixelSize: 12
        font.features: { "tnum": 1 }
    }
    component StatusBtn: HoverButton {
        id: stb
        property string text
        width: stbText.implicitWidth + 16; height: 24; radius: 6
        Text { id: stbText; anchors.centerIn: parent; text: stb.text; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
    }
}
