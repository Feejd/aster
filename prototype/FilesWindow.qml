import QtQuick
import QtQuick.Effects
import "Icons.js" as I

// Menedżer plików: nawigacja, zaznaczanie, wytnij/kopiuj/wklej, przeciąganie,
// zmiana nazwy, kosz z przywracaniem, cofanie, podgląd pod spacją, siatka i lista.
Item {
    id: win
    property var t
    property var store
    property Item backdrop
    property bool open: true
    property bool maximized: false
    property rect normalGeometry: Qt.rect(150, 56, 1000, 620)
    property rect maxGeometry: Qt.rect(0, 0, 1440, 844)

    property string currentDir: "work"
    property var backStack: []
    property var fwdStack: []
    property var sel: ({})
    property int lastIndex: -1
    property var clip: ({ ids: [], mode: "" })
    property string viewMode: "grid"
    property string sortKey: "name"
    property bool ascending: true
    property string renaming: ""
    property string quickLook: ""
    property var confirm: null
    property string toastText: ""
    property bool toastUndo: false

    readonly property bool isMac: Qt.platform.os === "osx"
    readonly property bool inTrash: currentDir === store.trashId
    readonly property string query: searchField.text.trim()
    readonly property var items: {
        store.rev;
        return query ? store.search(query, currentDir) : store.children(currentDir, sortKey, ascending);
    }
    readonly property var selection: {
        store.rev;
        return Object.keys(sel).filter(id => store.exists(id));
    }
    readonly property int trashCount: { store.rev; return store.children(store.trashId).length; }
    readonly property var current: store.get(currentDir)
    readonly property var crumbs: { store.rev; return store.path(currentDir); }

    signal closeRequested()
    signal minimizeRequested()
    signal activated()
    TapHandler { gesturePolicy: TapHandler.DragThreshold; onPressedChanged: if (pressed) win.activated() }

    x: maximized ? maxGeometry.x : normalGeometry.x
    y: maximized ? maxGeometry.y : normalGeometry.y
    width: maximized ? maxGeometry.width : normalGeometry.width
    height: maximized ? maxGeometry.height : normalGeometry.height

    Behavior on x { enabled: !titleDrag.active; SpringAnimation { spring: 9; damping: 0.72; epsilon: 0.5 } }
    Behavior on y { enabled: !titleDrag.active; SpringAnimation { spring: 9; damping: 0.72; epsilon: 0.5 } }
    Behavior on width { SpringAnimation { spring: 9; damping: 0.72; epsilon: 0.5 } }
    Behavior on height { SpringAnimation { spring: 9; damping: 0.72; epsilon: 0.5 } }

    // Minimalizacja „zasysa” okno do ikony na pasku: wysokość znika szybciej niż szerokość,
    // a całość zjeżdża do ikony. Otwieranie to samo wstecz, ze sprężystym dociągnięciem.
    property point minimizeTarget: Qt.point(560, 900)
    property real gx: 1
    property real gy: 1
    property real gp: 0
    visible: opacity > 0.01
    transform: [
        Scale { origin.x: win.width / 2; origin.y: win.height; xScale: win.gx; yScale: win.gy },
        Translate {
            x: win.gp * (win.minimizeTarget.x - (win.x + win.width / 2))
            y: win.gp * (win.minimizeTarget.y - (win.y + win.height))
        }
    ]
    states: State {
        name: "closed"
        when: !win.open
        PropertyChanges { win.gx: 0.1; win.gy: 0.03; win.gp: 1; win.opacity: 0 }
    }
    transitions: [
        Transition {
            to: "closed"
            ParallelAnimation {
                NumberAnimation { target: win; property: "gy"; duration: 150; easing.type: Easing.InCubic }
                NumberAnimation { target: win; property: "gx"; duration: 200; easing.type: Easing.InQuart }
                NumberAnimation { target: win; property: "gp"; duration: 200; easing.type: Easing.InQuad }
                SequentialAnimation {
                    PauseAnimation { duration: 170 }
                    NumberAnimation { target: win; property: "opacity"; duration: 90 }
                }
            }
        },
        Transition {
            from: "closed"
            ParallelAnimation {
                NumberAnimation { target: win; property: "gy"; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 0.6 }
                NumberAnimation { target: win; property: "gx"; duration: 250; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
                NumberAnimation { target: win; property: "gp"; duration: 190; easing.type: Easing.OutCubic }
                NumberAnimation { target: win; property: "opacity"; duration: 110 }
            }
        }
    ]

    // Krótko po wejściu do folderu nowe elementy wjeżdżają kaskadą
    property bool entering: false
    Timer { id: enterTimer; interval: 300; onTriggered: win.entering = false }

    onOpenChanged: if (open) keys.forceActiveFocus()

    // ——— Pomocnicze ———

    function key(s) { return isMac ? s.replace("Ctrl+Shift+", "⇧⌘").replace("Ctrl+", "⌘").replace("Delete", "⌘⌫") : s }
    function count(n) { return store.countText(n) }

    function showToast(text, undoable) {
        toastText = text;
        toastUndo = !!undoable;
        toastTimer.restart();
    }

    function navigate(id, push) {
        if (!store.isDir(id)) return;
        if (id !== currentDir && push !== false) {
            backStack = backStack.concat([currentDir]);
            fwdStack = [];
        }
        entering = true;
        enterTimer.restart();
        currentDir = id;
        searchField.text = "";
        clearSel();
        renaming = "";
        keys.forceActiveFocus();
    }
    function goBack() {
        if (!backStack.length) return;
        const b = backStack.slice(), prev = b.pop();
        backStack = b;
        fwdStack = fwdStack.concat([currentDir]);
        navigate(store.exists(prev) ? prev : store.rootId, false);
    }
    function goForward() {
        if (!fwdStack.length) return;
        const f = fwdStack.slice(), next = f.pop();
        fwdStack = f;
        backStack = backStack.concat([currentDir]);
        navigate(store.exists(next) ? next : store.rootId, false);
    }
    function reveal(id) {
        const f = store.get(id);
        if (!f) return;
        navigate(f.parent);
        setSel([id]);
        lastIndex = items.findIndex(x => x.id === id);
        if (!f.dir) quickLook = id;
    }
    function goUp() { if (current && current.parent) navigate(current.parent) }

    function setSel(ids) {
        const s = {};
        for (const id of ids) s[id] = true;
        sel = s;
    }
    function clearSel() { sel = {}; lastIndex = -1; }
    function toggleSel(id) {
        const s = Object.assign({}, sel);
        if (s[id]) delete s[id]; else s[id] = true;
        sel = s;
    }
    function selectAll() { setSel(items.map(f => f.id)) }

    function itemClicked(index, mods, button, wx, wy) {
        const id = items[index].id;
        keys.forceActiveFocus();
        if (button === Qt.RightButton) {
            if (!sel[id]) { setSel([id]); lastIndex = index; }
            showItemMenu(wx, wy);
            return;
        }
        if (mods & Qt.ControlModifier) toggleSel(id);
        else if ((mods & Qt.ShiftModifier) && lastIndex >= 0) {
            const a = Math.min(lastIndex, index), b = Math.max(lastIndex, index);
            setSel(items.slice(a, b + 1).map(f => f.id));
            return;
        } else setSel([id]);
        lastIndex = index;
    }

    function openItem(file) {
        if (!file) return;
        if (file.dir) navigate(file.id);
        else quickLook = file.id;
    }
    function openSelected() {
        if (selection.length === 1) openItem(store.get(selection[0]));
    }

    function doCut() { if (selection.length && !inTrash) { clip = { ids: selection, mode: "cut" }; showToast("Wycięto " + count(selection.length) + " — wklej w innym folderze"); } }
    function doCopy() { if (selection.length && !inTrash) { clip = { ids: selection, mode: "copy" }; showToast("Skopiowano " + count(selection.length) + " do schowka"); } }
    function doPaste() {
        if (!clip.ids.length || inTrash || query) return;
        if (clip.mode === "cut") {
            const ids = clip.ids;
            const n = store.move(ids, currentDir, "Przeniesienie");
            clip = { ids: [], mode: "" };
            if (n) { setSel(ids); showToast("Przeniesiono " + count(n) + " tutaj", true); }
            else showToast("Te elementy już tu są.");
        } else {
            const ids = store.copy(clip.ids, currentDir);
            if (ids.length) { setSel(ids); showToast("Wklejono " + count(ids.length), true); }
            else showToast("Nie można skopiować folderu do jego wnętrza.");
        }
    }
    function moveTo(ids, dest) {
        if (dest === store.trashId) { setSel(ids); trashSelected(); return; }
        const n = store.move(ids, dest, "Przeniesienie");
        if (n) showToast("Przeniesiono " + count(n) + " do: " + store.get(dest).name, true);
    }
    function trashSelected() {
        if (!selection.length) return;
        const n = store.trash(selection);
        clearSel();
        if (n) showToast("Przeniesiono " + count(n) + " do kosza", true);
        else showToast("Tego folderu nie można usunąć.");
    }
    function deleteSelected() {
        if (inTrash) askPurge(selection);
        else trashSelected();
    }
    function restoreSelected() {
        const n = store.restore(selection);
        clearSel();
        if (n) showToast("Przywrócono " + count(n), true);
    }
    function askPurge(ids) {
        if (!ids.length) return;
        confirm = {
            title: ids.length === 1 ? "Usunąć „" + store.get(ids[0]).name + "” na zawsze?" : "Usunąć " + count(ids.length) + " na zawsze?",
            text: "Tych plików nie będzie można przywrócić z kosza.",
            button: "Usuń na zawsze",
            run: () => { const n = store.purge(ids); clearSel(); if (n) showToast("Usunięto " + count(n)); }
        };
    }
    function askEmptyTrash() {
        if (!trashCount) return;
        confirm = {
            title: "Opróżnić kosz?",
            text: "Usuniesz na zawsze " + count(trashCount) + ". Tych plików nie będzie można przywrócić.",
            button: "Opróżnij kosz",
            run: () => { store.emptyTrash(); clearSel(); showToast("Kosz jest pusty"); }
        };
    }
    function newFolder() {
        if (inTrash || query) return;
        const id = store.mkdir(currentDir, "Nowy folder");
        setSel([id]);
        renaming = id;
    }
    function newDocument() {
        if (inTrash || query) return;
        const id = store.mkfile(currentDir, "Nowy dokument.docx");
        setSel([id]);
        renaming = id;
    }
    function startRename() { if (selection.length === 1 && !inTrash) renaming = selection[0] }
    function commitRename(id, name) {
        if (renaming !== id) return;
        renaming = "";
        const err = store.rename(id, name);
        if (err) showToast(err);
        keys.forceActiveFocus();
    }
    function doUndo() {
        const label = store.undo();
        clearSel();
        renaming = "";
        if (!store.exists(currentDir)) currentDir = store.rootId;
        showToast(label ? "Cofnięto: " + label.toLowerCase() : "Nie ma czego cofnąć");
    }
    function toggleQuickLook() {
        if (quickLook) quickLook = "";
        else if (selection.length === 1 && !store.isDir(selection[0])) quickLook = selection[0];
    }
    function moveCursor(dx, dy, extend) {
        if (!items.length) return;
        const cols = viewMode === "grid" ? Math.max(1, Math.floor(gridView.width / gridView.cellWidth)) : 1;
        let i = lastIndex < 0 ? 0 : lastIndex + dx + dy * cols;
        i = Math.max(0, Math.min(items.length - 1, i));
        if (extend && lastIndex >= 0) {
            const s = Object.assign({}, sel);
            s[items[i].id] = true;
            sel = s;
        } else setSel([items[i].id]);
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
            if (e.key === Qt.Key_Space || e.key === Qt.Key_Escape) quickLook = "";
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
        else if (e.key === Qt.Key_Delete || (ctrl && e.key === Qt.Key_Backspace)) deleteSelected();
        else if (e.key === Qt.Key_F2) startRename();
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
        const one = selection.length === 1;
        const isDir = one && store.isDir(selection[0]);
        if (inTrash) {
            menu.openAt(wx, wy, [
                { label: "Przywróć", icon: "undo", action: "restore" },
                { separator: true },
                { label: "Usuń na zawsze", icon: "trash", action: "purge", danger: true }
            ]);
            return;
        }
        menu.openAt(wx, wy, [
            { label: isDir ? "Otwórz" : "Podgląd", icon: isDir ? "folder" : "eye", shortcut: isDir ? "Enter" : "Spacja", action: "open", enabled: one },
            { separator: true },
            { label: "Wytnij", icon: "scissors", shortcut: key("Ctrl+X"), action: "cut" },
            { label: "Kopiuj", icon: "copy", shortcut: key("Ctrl+C"), action: "copy" },
            { label: "Zmień nazwę", icon: "pencil", shortcut: "F2", action: "rename", enabled: one },
            { separator: true },
            { label: "Przenieś do kosza", icon: "trash", shortcut: key("Delete"), action: "trash", danger: true }
        ]);
    }
    function showBackgroundMenu(wx, wy) {
        clearSel();
        if (inTrash) {
            menu.openAt(wx, wy, [{ label: "Opróżnij kosz", icon: "trash", action: "empty", danger: true, enabled: trashCount > 0 }]);
            return;
        }
        menu.openAt(wx, wy, [
            { label: "Nowy folder", icon: "folderPlus", shortcut: key("Ctrl+Shift+N"), action: "newFolder", enabled: !query },
            { label: "Nowy dokument", icon: "filePlus", action: "newDoc", enabled: !query },
            { separator: true },
            { label: "Wklej", icon: "paste", shortcut: key("Ctrl+V"), action: "paste", enabled: clip.ids.length > 0 && !query },
            { label: "Zaznacz wszystko", shortcut: key("Ctrl+A"), action: "selectAll" },
            { label: "Cofnij", icon: "undo", shortcut: key("Ctrl+Z"), action: "undo", enabled: store.undoStack.length > 0 }
        ]);
    }
    function showSortMenu(wx, wy) {
        const mark = (k) => sortKey === k ? "check" : "";
        menu.openAt(wx, wy, [
            { label: "Nazwa", icon: mark("name"), action: "sort:name" },
            { label: "Data zmiany", icon: mark("date"), action: "sort:date" },
            { label: "Rozmiar", icon: mark("size"), action: "sort:size" },
            { label: "Typ", icon: mark("kind"), action: "sort:kind" },
            { separator: true },
            { label: ascending ? "Malejąco" : "Rosnąco", icon: "sort", action: "sort:flip" }
        ]);
    }
    function showNewMenu(wx, wy) {
        menu.openAt(wx, wy, [
            { label: "Folder", icon: "folderPlus", shortcut: key("Ctrl+Shift+N"), action: "newFolder" },
            { label: "Dokument", icon: "filePlus", action: "newDoc" }
        ]);
    }
    function runAction(a) {
        if (a === "open") openSelected();
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
        else if (a === "undo") doUndo();
        else if (a === "sort:flip") ascending = !ascending;
        else if (a.indexOf("sort:") === 0) setSort(a.slice(5));
        if (!renaming) keys.forceActiveFocus();
    }
    function setSort(k) {
        if (sortKey === k) ascending = !ascending;
        else { sortKey = k; ascending = k === "name" || k === "kind"; }
    }

    // ——— Przeciąganie ———

    function dragStart(index) {
        const id = items[index].id;
        if (!sel[id]) { setSel([id]); lastIndex = index; }
        ghost.ids = selection;
        ghost.label = selection.length === 1 ? store.get(selection[0]).name : count(selection.length);
        ghost.Drag.active = true;
    }
    function dragMove(wx, wy) { ghost.x = wx; ghost.y = wy; }
    function dragEnd() {
        ghost.Drag.drop();
        ghost.Drag.active = false;
    }


    // ——— Przeciąganie; dociągnięcie do górnej krawędzi = pełny ekran (jak w macOS) ———
    property bool snapArmed: false
    property rect dragStart
    property rect preDrag
    function beginDrag(p) {
        win.activated();
        if (win.maximized) {
            // okno „odkleja się” od pełnego ekranu tak, żeby pasek tytułu został pod kursorem
            const ratio = (p.x - win.x) / Math.max(1, win.width);
            const nw = win.normalGeometry.width, nh = win.normalGeometry.height;
            win.normalGeometry = Qt.rect(p.x - ratio * nw, Math.max(0, p.y - 24), nw, nh);
            win.maximized = false;
        }
        dragStart = win.normalGeometry;
        preDrag = win.normalGeometry;
    }
    function moveDrag(p, tr) {
        win.normalGeometry = Qt.rect(dragStart.x + tr.x, Math.max(0, dragStart.y + tr.y), dragStart.width, dragStart.height);
        snapArmed = p.y < 10;
    }
    function endDrag() {
        if (snapArmed) {
            win.normalGeometry = preDrag;
            win.maximized = true;
        }
        snapArmed = false;
    }
    SnapPreview {
        parent: win.parent
        z: win.z - 0.5
        t: win.t
        geo: win.maxGeometry
        on: win.snapArmed
    }

    RectangularShadow {
        anchors.fill: parent
        radius: win.maximized ? 0 : 18
        blur: 60
        offset.y: 24
        color: win.t.shadow
    }

    Glass {
        anchors.fill: parent
        backdrop: win.backdrop
        sx: win.x
        sy: win.y
        radius: win.maximized ? 0 : 18
        tint: win.t.windowGlass
        rim: win.t.rim
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: win.maximized ? 0 : 18
        color: "transparent"
        border.width: 1
        border.color: win.t.edge
        clip: true
        Behavior on radius { NumberAnimation { duration: 200 } }

        Rectangle {
            x: sidebar.width; y: titlebar.height
            width: parent.width - sidebar.width
            height: parent.height - titlebar.height
            color: win.t.pane
            bottomRightRadius: win.maximized ? 0 : 18
        }

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
                id: titleDrag
                target: null
                onActiveChanged: if (active) win.beginDrag(centroid.scenePosition); else win.endDrag()
                onTranslationChanged: if (active) win.moveDrag(centroid.scenePosition, translation)
            }
            TapHandler { onDoubleTapped: win.maximized = !win.maximized }

            Row {
                id: navButtons
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                ToolBtn { t: win.t; icon: "back"; enabled: win.backStack.length > 0; onClicked: win.goBack() }
                ToolBtn { t: win.t; icon: "forward"; enabled: win.fwdStack.length > 0; onClicked: win.goForward() }
                ToolBtn { t: win.t; icon: "up"; enabled: !!(win.current && win.current.parent); onClicked: win.goUp() }
            }

            // Ścieżka — każdy segment klikalny i przyjmuje upuszczone pliki
            Rectangle {
                anchors.left: navButtons.right; anchors.leftMargin: 8
                anchors.right: searchBox.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: 34
                radius: 9
                color: win.t.fill
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
                            Text { visible: seg.index > 0; anchors.verticalCenter: parent.verticalCenter; text: "›"; color: win.t.text2; font.pixelSize: 13; leftPadding: 2; rightPadding: 2 }
                            Rectangle {
                                width: segText.implicitWidth + 12; height: 26; radius: 6
                                anchors.verticalCenter: parent.verticalCenter
                                color: segDrop.containsDrag ? Qt.rgba(52 / 255, 86 / 255, 232 / 255, 0.3) : (segArea.containsMouse && !seg.last ? win.t.hover : "transparent")
                                Text { id: segText; anchors.centerIn: parent; text: seg.modelData.name; color: seg.last ? win.t.text : win.t.text2; font.pixelSize: 13; font.weight: seg.last ? Font.Medium : Font.Normal }
                                MouseArea { id: segArea; anchors.fill: parent; hoverEnabled: true; onClicked: win.navigate(seg.modelData.id) }
                                DropArea { id: segDrop; anchors.fill: parent; keys: ["aster-files"]; onDropped: win.moveTo(ghost.ids, seg.modelData.id) }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: searchBox
                anchors.right: controls.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 220; height: 34; radius: 9
                color: win.t.fill
                border.width: searchField.activeFocus ? 1.5 : 0
                border.color: win.t.accent
                Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: I.search; size: 16; color: win.t.text2 }
                TextInput {
                    id: searchField
                    x: 34; width: parent.width - 44
                    anchors.verticalCenter: parent.verticalCenter
                    color: win.t.text; font.pixelSize: 13; clip: true
                    selectionColor: win.t.accentSoft
                    onTextChanged: win.clearSel()
                    Keys.onEscapePressed: { text = ""; keys.forceActiveFocus(); }
                    Keys.onDownPressed: { keys.forceActiveFocus(); win.moveCursor(0, 0, false); }
                    Text { visible: !searchField.text; text: "Szukaj w: " + (win.current ? win.current.name : ""); width: parent.width; elide: Text.ElideRight; color: win.t.text2; font.pixelSize: 13 }
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
                        color: wcArea.containsMouse ? modelData.hover : win.t.fill
                        scale: wcArea.pressed ? 0.9 : 1
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        Icon { anchors.centerIn: parent; d: I[wc.modelData.icon]; size: 13; stroke: 2; color: wcArea.containsMouse ? "white" : win.t.text2 }
                        MouseArea {
                            id: wcArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (wc.modelData.act === "min") win.minimizeRequested();
                                else if (wc.modelData.act === "max") win.maximized = !win.maximized;
                                else win.closeRequested();
                            }
                        }
                    }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: win.t.line }
        }

        // ——— Pasek boczny ———
        Rectangle {
            id: sidebar
            y: titlebar.height
            width: 208; height: parent.height - titlebar.height
            color: "transparent"
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: win.t.line }

            Column {
                x: 10; y: 14
                width: parent.width - 20
                spacing: 2
                Text { text: "ULUBIONE"; color: win.t.text2; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4; leftPadding: 10; bottomPadding: 6; topPadding: 4 }
                Repeater {
                    model: win.store.places
                    delegate: SidebarPlace {
                        required property var modelData
                        width: parent.width
                        t: win.t
                        label: modelData.name
                        icon: modelData.icon
                        active: win.currentDir === modelData.id
                        onClicked: win.navigate(modelData.id)
                        onDropped: win.moveTo(ghost.ids, modelData.id)
                    }
                }
                Text { text: "TEN KOMPUTER"; color: win.t.text2; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4; leftPadding: 10; bottomPadding: 6; topPadding: 16 }
                SidebarPlace {
                    width: parent.width; t: win.t
                    label: "Dysk systemowy (C:)"; icon: "drive"
                    active: win.currentDir === win.store.rootId
                    onClicked: win.navigate(win.store.rootId)
                    onDropped: win.moveTo(ghost.ids, win.store.rootId)
                }
                Item {
                    width: parent.width; height: 22
                    Rectangle {
                        x: 38; y: 2; width: parent.width - 48; height: 4; radius: 2; color: win.t.line
                        Rectangle { width: parent.width * 0.46; height: 4; radius: 2; color: win.t.accent }
                    }
                    Text { x: 38; y: 9; text: "238 GB wolne z 512 GB"; color: win.t.text2; font.pixelSize: 11 }
                }
                SidebarPlace {
                    width: parent.width; t: win.t
                    label: "Windows (D:)"; icon: "drive"
                    active: win.currentDir === win.store.winId
                    onClicked: win.navigate(win.store.winId)
                    onDropped: win.moveTo(ghost.ids, win.store.winId)
                }
                Item { width: 1; height: 12 }
                SidebarPlace {
                    width: parent.width; t: win.t
                    label: "Kosz"; icon: "trash"
                    badge: win.trashCount ? String(win.trashCount) : ""
                    active: win.inTrash
                    onClicked: win.navigate(win.store.trashId)
                    onDropped: win.moveTo(ghost.ids, win.store.trashId)
                }
            }
        }

        // ——— Pasek narzędzi ———
        Item {
            id: toolbar
            x: sidebar.width; y: titlebar.height
            width: parent.width - sidebar.width; height: 48

            Row {
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                visible: !win.inTrash

                Rectangle {
                    id: newBtn
                    width: newRow.implicitWidth + 22; height: 32; radius: 8
                    opacity: win.query ? 0.4 : 1
                    color: newArea.containsMouse ? Qt.darker(win.t.accent, 1.1) : win.t.accent
                    Row {
                        id: newRow
                        anchors.centerIn: parent
                        spacing: 6
                        Icon { anchors.verticalCenter: parent.verticalCenter; d: I.plus; size: 16; color: "white" }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Nowy"; color: "white"; font.pixelSize: 13; font.weight: Font.Medium }
                        Icon { anchors.verticalCenter: parent.verticalCenter; d: I.chevronDown; size: 14; color: "white" }
                    }
                    MouseArea {
                        id: newArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !win.query
                        onClicked: { const p = newBtn.mapToItem(win, 0, newBtn.height + 4); win.showNewMenu(p.x, p.y); }
                    }
                }
                Item { width: 8; height: 1 }
                ToolBtn { t: win.t; icon: "scissors"; enabled: win.selection.length > 0; onClicked: win.doCut() }
                ToolBtn { t: win.t; icon: "copy"; enabled: win.selection.length > 0; onClicked: win.doCopy() }
                ToolBtn { t: win.t; icon: "paste"; enabled: win.clip.ids.length > 0 && !win.query; onClicked: win.doPaste() }
                ToolBtn { t: win.t; icon: "pencil"; enabled: win.selection.length === 1; onClicked: win.startRename() }
                ToolBtn { t: win.t; icon: "trash"; enabled: win.selection.length > 0; onClicked: win.trashSelected() }
            }

            Row {
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                visible: win.inTrash
                HoverButton {
                    t: win.t
                    width: restoreRow.implicitWidth + 22; height: 32; radius: 8
                    color: win.t.fill
                    enabled: win.selection.length > 0
                    opacity: enabled ? 1 : 0.4
                    onClicked: win.restoreSelected()
                    Row {
                        id: restoreRow
                        anchors.centerIn: parent
                        spacing: 6
                        Icon { anchors.verticalCenter: parent.verticalCenter; d: I.undo; size: 16; color: win.t.text }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Przywróć"; color: win.t.text; font.pixelSize: 13; font.weight: Font.Medium }
                    }
                }
                HoverButton {
                    t: win.t
                    width: emptyText.implicitWidth + 24; height: 32; radius: 8
                    color: win.t.fill
                    enabled: win.trashCount > 0
                    opacity: enabled ? 1 : 0.4
                    onClicked: win.askEmptyTrash()
                    Text { id: emptyText; anchors.centerIn: parent; text: "Opróżnij kosz"; color: win.t.dark ? "#FF8A80" : "#C62828"; font.pixelSize: 13; font.weight: Font.Medium }
                }
            }

            Row {
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                HoverButton {
                    id: sortBtn
                    t: win.t
                    width: sortRow.implicitWidth + 20; height: 32; radius: 8
                    onClicked: { const p = sortBtn.mapToItem(win, 0, sortBtn.height + 4); win.showSortMenu(p.x, p.y); }
                    Row {
                        id: sortRow
                        anchors.centerIn: parent
                        spacing: 6
                        Icon { anchors.verticalCenter: parent.verticalCenter; d: I.sort; size: 16; color: win.t.text }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: ({ name: "Nazwa", date: "Data", size: "Rozmiar", kind: "Typ" })[win.sortKey] + (win.ascending ? " ↑" : " ↓"); color: win.t.text; font.pixelSize: 13 }
                    }
                }
                Rectangle {
                    width: 70; height: 32; radius: 9
                    color: win.t.fill
                    Row {
                        anchors.centerIn: parent
                        spacing: 2
                        Repeater {
                            model: ["grid", "list"]
                            delegate: Rectangle {
                                id: vm
                                required property string modelData
                                width: 32; height: 26; radius: 7
                                color: win.viewMode === modelData ? win.t.surface : "transparent"
                                Icon { anchors.centerIn: parent; d: I[vm.modelData]; size: 15; color: win.viewMode === vm.modelData ? win.t.text : win.t.text2 }
                                MouseArea { anchors.fill: parent; onClicked: { win.viewMode = vm.modelData; keys.forceActiveFocus(); } }
                            }
                        }
                    }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: win.t.line }
        }

        // ——— Zawartość folderu ———
        Item {
            id: content
            x: sidebar.width; y: titlebar.height + toolbar.height
            width: parent.width - sidebar.width
            height: parent.height - y - status.height

            // Upuszczenie na puste miejsce = przeniesienie do bieżącego folderu
            DropArea {
                anchors.fill: parent
                keys: ["aster-files"]
                enabled: !win.inTrash && !win.query
                onDropped: win.moveTo(ghost.ids, win.currentDir)
            }

            // Nagłówek listy (klik sortuje)
            Item {
                id: listHeader
                visible: win.viewMode === "list"
                width: parent.width; height: visible ? 34 : 0
                readonly property string arrow: win.ascending ? " ↑" : " ↓"
                Repeater {
                    model: [
                        { k: "name", label: "Nazwa", x: 62 },
                        { k: "date", label: "Zmodyfikowano", x: listHeader.width - 24 - 390 + 12 },
                        { k: "kind", label: "Typ", x: listHeader.width - 24 - 220 + 12 },
                        { k: "size", label: "Rozmiar", x: listHeader.width - 24 - 90 + 12 }
                    ]
                    delegate: Text {
                        required property var modelData
                        x: modelData.x
                        anchors.verticalCenter: parent.verticalCenter
                        text: (modelData.k === "date" && win.query ? "Lokalizacja" : modelData.label) + (win.sortKey === modelData.k ? listHeader.arrow : "")
                        color: win.sortKey === modelData.k ? win.t.text : win.t.text2
                        font.pixelSize: 12; font.weight: Font.DemiBold
                        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: win.setSort(parent.modelData.k) }
                    }
                }
                Rectangle { anchors.bottom: parent.bottom; x: 12; width: parent.width - 24; height: 1; color: win.t.line }
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
                model: win.items
                delegate: FileItem {
                    required property var modelData
                    required property int index
                    width: gridView.cellWidth; height: gridView.cellHeight
                    t: win.t
                    file: modelData
                    coordRoot: win
                    enterDelay: win.entering ? Math.min(index, 16) * 8 : -1
                    showWhere: !!win.query
                    selected: !!win.sel[modelData.id]
                    cut: win.clip.mode === "cut" && win.clip.ids.indexOf(modelData.id) >= 0
                    renaming: win.viewMode === "grid" && win.renaming === modelData.id
                    onClicked: (mods, button, wx, wy) => win.itemClicked(index, mods, button, wx, wy)
                    onDoubleClicked: win.openItem(modelData)
                    onDragStarted: win.dragStart(index)
                    onDragMoved: (wx, wy) => win.dragMove(wx, wy)
                    onDragEnded: win.dragEnd()
                    onDroppedOn: win.moveTo(ghost.ids, modelData.id)
                    onRenameCommitted: (name) => win.commitRename(modelData.id, name)
                    onRenameCancelled: { win.renaming = ""; keys.forceActiveFocus(); }
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onTapped: (pt, button) => {
                        if (gridView.indexAt(pt.position.x + gridView.contentX, pt.position.y + gridView.contentY) >= 0) return;
                        keys.forceActiveFocus();
                        const p = gridView.mapToItem(win, pt.position.x, pt.position.y);
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
                model: win.items
                delegate: FileItem {
                    required property var modelData
                    required property int index
                    width: listView.width; height: 38
                    listMode: true
                    t: win.t
                    file: modelData
                    coordRoot: win
                    enterDelay: win.entering ? Math.min(index, 16) * 8 : -1
                    showWhere: !!win.query
                    selected: !!win.sel[modelData.id]
                    cut: win.clip.mode === "cut" && win.clip.ids.indexOf(modelData.id) >= 0
                    renaming: win.viewMode === "list" && win.renaming === modelData.id
                    onClicked: (mods, button, wx, wy) => win.itemClicked(index, mods, button, wx, wy)
                    onDoubleClicked: win.openItem(modelData)
                    onDragStarted: win.dragStart(index)
                    onDragMoved: (wx, wy) => win.dragMove(wx, wy)
                    onDragEnded: win.dragEnd()
                    onDroppedOn: win.moveTo(ghost.ids, modelData.id)
                    onRenameCommitted: (name) => win.commitRename(modelData.id, name)
                    onRenameCancelled: { win.renaming = ""; keys.forceActiveFocus(); }
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onTapped: (pt, button) => {
                        if (listView.indexAt(pt.position.x + listView.contentX, pt.position.y + listView.contentY) >= 0) return;
                        keys.forceActiveFocus();
                        const p = listView.mapToItem(win, pt.position.x, pt.position.y);
                        if (button === Qt.RightButton) win.showBackgroundMenu(p.x, p.y);
                        else win.clearSel();
                    }
                }
            }

            // Pusty folder / brak wyników
            Column {
                anchors.centerIn: parent
                spacing: 8
                visible: win.items.length === 0
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 64; height: 64; radius: 18
                    color: win.t.fill
                    Icon { anchors.centerIn: parent; d: win.query ? I.search : (win.inTrash ? I.trash : I.folder); size: 28; color: win.t.text2 }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.query ? "Brak wyników dla „" + win.query + "”" : (win.inTrash ? "Kosz jest pusty" : "Ten folder jest pusty")
                    color: win.t.text; font.pixelSize: 15; font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.query ? "Szukam też we wszystkich podfolderach." : (win.inTrash ? "Usunięte pliki trafiają tutaj — możesz je przywrócić." : "Przeciągnij tu pliki albo kliknij prawym przyciskiem, żeby coś utworzyć.")
                    color: win.t.text2; font.pixelSize: 13
                }
            }
        }

        // ——— Pasek stanu ———
        Item {
            id: status
            x: sidebar.width; anchors.bottom: parent.bottom
            width: parent.width - sidebar.width; height: 32
            Rectangle { width: parent.width; height: 1; color: win.t.line }
            Text {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                text: {
                    const n = win.items.length;
                    let s = win.query ? n + (n === 1 ? " wynik" : " wyników") : win.count(n);
                    const k = win.selection.length;
                    if (k) {
                        let size = 0;
                        for (const id of win.selection) size += win.store.totalSize(id);
                        s += " · zaznaczono " + k + " (" + win.store.sizeText(size) + ")";
                    }
                    return s;
                }
                color: win.t.text2; font.pixelSize: 12
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: "Spacja — podgląd · F2 — nazwa · " + win.key("Ctrl+Z") + " — cofnij"
                color: win.t.text2; font.pixelSize: 12
            }
        }

        // ——— Podgląd (spacja) ———
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.25)
            visible: opacity > 0
            opacity: win.quickLook ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            MouseArea { anchors.fill: parent; onClicked: win.quickLook = "" }
            Rectangle {
                id: ql
                readonly property var f: win.quickLook ? win.store.get(win.quickLook) : null
                anchors.centerIn: parent
                width: 380; height: 440; radius: 18
                color: win.t.surface
                border.width: 1; border.color: win.t.edge
                scale: win.quickLook ? 1 : 0.92
                Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack; easing.overshoot: 1.0 } }
                MouseArea { anchors.fill: parent }
                Rectangle {
                    x: 20; y: 20; width: parent.width - 40; height: 230; radius: 12
                    color: win.t.fill
                    FileBadge { anchors.centerIn: parent; t: win.t; file: ql.f; scale: 2.4 }
                }
                Column {
                    x: 24; y: 270
                    width: parent.width - 48
                    spacing: 6
                    Text { width: parent.width; text: ql.f ? ql.f.name : ""; color: win.t.text; font.pixelSize: 17; font.weight: Font.DemiBold; elide: Text.ElideMiddle }
                    Text { text: ql.f ? ql.f.kind + " · " + ql.f.sizeText : ""; color: win.t.text2; font.pixelSize: 13 }
                    Text { text: ql.f ? "Zmieniono: " + ql.f.date : ""; color: win.t.text2; font.pixelSize: 13 }
                    Text { width: parent.width; text: ql.f ? ql.f.where : ""; color: win.t.text2; font.pixelSize: 13; elide: Text.ElideMiddle }
                }
                Rectangle {
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 20
                    x: 20; width: parent.width - 40; height: 40; radius: 10
                    color: win.t.accent
                    Text { anchors.centerIn: parent; text: "Zamknij podgląd (spacja)"; color: "white"; font.pixelSize: 13; font.weight: Font.DemiBold }
                    MouseArea { anchors.fill: parent; onClicked: win.quickLook = "" }
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
                color: win.t.surface
                border.width: 1; border.color: win.t.edge
                MouseArea { anchors.fill: parent }
                Column {
                    id: confirmCol
                    x: 24; y: 24
                    width: parent.width - 48
                    spacing: 10
                    Text { width: parent.width; text: win.confirm ? win.confirm.title : ""; color: win.t.text; font.pixelSize: 17; font.weight: Font.DemiBold; wrapMode: Text.Wrap }
                    Text { width: parent.width; text: win.confirm ? win.confirm.text : ""; color: win.t.text2; font.pixelSize: 13; wrapMode: Text.Wrap }
                    Item { width: 1; height: 8 }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        HoverButton {
                            t: win.t; width: 90; height: 38; color: win.t.fill
                            onClicked: win.confirm = null
                            Text { anchors.centerIn: parent; text: "Anuluj"; color: win.t.text; font.pixelSize: 13; font.weight: Font.Medium }
                        }
                        Rectangle {
                            width: dangerText.implicitWidth + 30; height: 38; radius: 10
                            color: dangerArea.containsMouse ? "#B92E2E" : "#D93B3B"
                            Text { id: dangerText; anchors.centerIn: parent; text: win.confirm ? win.confirm.button : ""; color: "white"; font.pixelSize: 13; font.weight: Font.DemiBold }
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
            width: toastRow.implicitWidth + 32; height: 42; radius: 21
            color: win.t.text
            opacity: toastTimer.running ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
            Row {
                id: toastRow
                anchors.centerIn: parent
                spacing: 14
                Text { anchors.verticalCenter: parent.verticalCenter; text: win.toastText; color: win.t.surface; font.pixelSize: 13 }
                Text {
                    visible: win.toastUndo
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Cofnij"
                    color: win.t.dark ? "#3456E8" : "#8FA6FF"
                    font.pixelSize: 13; font.weight: Font.Bold
                    MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: { toastTimer.stop(); win.doUndo(); } }
                }
            }
        }
        Timer { id: toastTimer; interval: 4500 }
    }

    // Duch przeciąganych plików
    Item {
        id: ghost
        property var ids: []
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
            color: win.t.accent
            Row {
                id: ghostRow
                anchors.centerIn: parent
                spacing: 6
                Icon { anchors.verticalCenter: parent.verticalCenter; d: I.copy; size: 15; color: "white" }
                Text { anchors.verticalCenter: parent.verticalCenter; text: ghost.label; color: "white"; font.pixelSize: 13; font.weight: Font.Medium }
            }
        }
    }

    ContextMenu {
        id: menu
        t: win.t
        onTriggered: (a) => win.runAction(a)
    }
}
