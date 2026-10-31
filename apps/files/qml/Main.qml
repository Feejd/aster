pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Aster.Ui
import Aster.Files

// Pliki: okno bez ramki systemowej — pasek tytułu z nawigacją, wyszukiwaniem i okrągłymi
// przyciskami jest częścią okna (jak w prototypie). Wokół okna jest margines na cień;
// kliknięcia w cień przechodzą do okien pod spodem (Files.setInputRegion).
Window {
    id: win
    property string startUrl

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
    readonly property real r: maxed ? 0 : 14          // zaokrąglenie rogów

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

    FolderModel {
        id: folder
        url: win.startUrl
        onCountChanged: {
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
        else Files.open(file.url);
    }
    function selectedFile() {
        if (selection.length !== 1) return null;
        const i = folder.indexOfUrl(selection[0]);
        return i >= 0 ? folder.get(i) : null;
    }
    function openSelected() { openItem(selectedFile()); }

    function doCut() { if (selection.length && !inTrash) { Files.setClipboard(selection, true); showToast("Wycięto " + countText(selection.length) + " — wklej w innym folderze", false); } }
    function doCopy() { if (selection.length && !inTrash) { Files.setClipboard(selection, false); showToast("Skopiowano " + countText(selection.length) + " do schowka", false); } }
    function doPaste() {
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
        if (inTrash || query) return;
        pendingRename = Files.newFolder(currentUrl);
    }
    function newDocument() {
        if (inTrash || query) return;
        pendingRename = Files.newTextFile(currentUrl);
    }
    function startRename() { if (selection.length === 1 && !inTrash) renaming = selection[0]; }
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
        menu.openAt(wx, wy, [
            { label: "Otwórz", icon: isDir ? "folder" : "arrow", shortcut: "Enter", action: "open", enabled: !!f },
            { label: "Podgląd", icon: "eye", shortcut: "Spacja", action: "preview", enabled: !!f && !isDir },
            { separator: true },
            { label: "Wytnij", icon: "scissors", shortcut: "Ctrl+X", action: "cut" },
            { label: "Kopiuj", icon: "copy", shortcut: "Ctrl+C", action: "copy" },
            { label: "Zmień nazwę", icon: "pencil", shortcut: "F2", action: "rename", enabled: !!f },
            { separator: true },
            { label: "Przenieś do kosza", icon: "trash", shortcut: "Delete", action: "trash", danger: true }
        ]);
    }
    function showBackgroundMenu(wx, wy) {
        clearSel();
        if (inTrash) {
            menu.openAt(wx, wy, [{ label: "Opróżnij kosz", icon: "trash", action: "empty", danger: true, enabled: Files.trashCount > 0 }]);
            return;
        }
        menu.openAt(wx, wy, [
            { label: "Nowy folder", icon: "folderPlus", shortcut: "Ctrl+Shift+N", action: "newFolder", enabled: !query },
            { label: "Nowy dokument tekstowy", icon: "filePlus", action: "newDoc", enabled: !query },
            { separator: true },
            { label: "Wklej", icon: "paste", shortcut: "Ctrl+V", action: "paste", enabled: Files.clipboardCount > 0 && !query },
            { label: "Zaznacz wszystko", shortcut: "Ctrl+A", action: "selectAll" },
            { label: folder.showHidden ? "Ukryj ukryte pliki" : "Pokaż ukryte pliki", icon: "eye", shortcut: "Ctrl+H", action: "hidden" },
            { label: "Cofnij", icon: "undo", shortcut: "Ctrl+Z", action: "undo", enabled: Files.canUndo }
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
    Component.onCompleted: { effectsTimer.restart(); keys.forceActiveFocus(); }
    Timer { id: effectsTimer; interval: 16; onTriggered: win.updateEffects() }

    RectangularShadow {
        anchors.fill: frame
        visible: !win.maxed
        radius: win.r
        blur: 40
        offset.y: 12
        color: Theme.shadow
    }

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

            Row {
                id: controls
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Repeater {
                    model: [
                        { icon: "minimize", act: "min", hover: "#F2B33D" },
                        { icon: "maximize", act: "max", hover: "#34C27A" },
                        { icon: "close", act: "close", hover: "#F0524F" }
                    ]
                    delegate: Rectangle {
                        id: wc
                        required property var modelData
                        width: 28; height: 28; radius: 14
                        color: wcArea.containsMouse ? modelData.hover : Theme.fill
                        scale: wcArea.pressed ? 0.9 : 1
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        Icon { anchors.centerIn: parent; d: Icons[wc.modelData.icon]; size: 13; stroke: 2; color: wcArea.containsMouse ? "white" : Theme.text2 }
                        MouseArea {
                            id: wcArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (wc.modelData.act === "min") win.showMinimized();
                                else if (wc.modelData.act === "max") { if (win.maxed) win.showNormal(); else win.showMaximized(); }
                                else win.close();
                            }
                        }
                    }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        }

        // ——— Pasek boczny ———
        Item {
            id: sidebar
            y: titlebar.height
            width: 210; height: parent.height - titlebar.height
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }

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

        // ——— Pasek narzędzi ———
        Item {
            id: toolbar
            x: sidebar.width; y: titlebar.height
            width: parent.width - sidebar.width; height: 48

            Rectangle { anchors.fill: parent; color: Theme.pane }

            Row {
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                visible: !win.inTrash

                Rectangle {
                    id: newBtn
                    width: newRow.implicitWidth + 22; height: 32; radius: 8
                    opacity: win.query ? 0.4 : 1
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
                        enabled: !win.query
                        onClicked: { const p = newBtn.mapToItem(frame, 0, newBtn.height + 4); win.showNewMenu(p.x, p.y); }
                    }
                }
                Item { width: 8; height: 1 }
                ToolBtn { icon: "scissors"; enabled: win.selection.length > 0; onClicked: win.doCut() }
                ToolBtn { icon: "copy"; enabled: win.selection.length > 0; onClicked: win.doCopy() }
                ToolBtn { icon: "paste"; enabled: Files.clipboardCount > 0 && !win.query; onClicked: win.doPaste() }
                ToolBtn { icon: "pencil"; enabled: win.selection.length === 1; onClicked: win.startRename() }
                ToolBtn { icon: "trash"; enabled: win.selection.length > 0; onClicked: win.trashSelected() }
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
            x: sidebar.width; y: titlebar.height + toolbar.height
            width: parent.width - sidebar.width
            height: parent.height - y - status.height
            color: Theme.pane

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
            x: sidebar.width; anchors.bottom: parent.bottom
            width: parent.width - sidebar.width; height: 32
            color: Theme.pane
            bottomRightRadius: win.r
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
}
