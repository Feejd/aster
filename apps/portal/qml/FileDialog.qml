pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Qt.labs.folderlistmodel
import Aster.Ui
import Aster.Portal

// Okno „Otwórz / Zapisz” Aster dla wszystkich programów (przez xdg-desktop-portal).
// Po lewej miejsca (jak w Plikach), po prawej ścieżka, wyszukiwanie i lista plików z miniaturami zdjęć,
// na dole — przy zapisie — nazwa pliku, a do tego rodzaj plików i przyciski.
Window {
    id: dlg
    // Ustawiane przez FileChooser
    property string mode: "open"                 // "open" | "save"
    property string dialogTitle
    property string acceptLabel
    property bool multiple: false
    property bool directory: false
    property var filters: []                     // [{ name, globs }]
    property string currentFilterName
    property string currentName
    property string folder
    // Wynik dla FileChooser
    property var result: []
    signal accepted()
    signal rejected()

    width: 900 + 2 * m
    height: 580 + 2 * m
    minimumWidth: 620 + 2 * m
    minimumHeight: 400 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Dialog | Qt.FramelessWindowHint
    title: heading

    readonly property bool maxed: visibility === Window.Maximized
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 12
    readonly property bool saving: mode === "save"
    readonly property string heading: dialogTitle || (saving ? "Zapisz" : directory ? "Wybierz folder" : multiple ? "Otwórz pliki" : "Otwórz plik")
    readonly property string okLabel: acceptLabel || (saving ? "Zapisz" : directory ? "Wybierz" : "Otwórz")

    // ——— Stan ———
    property string path: folder || Portal.lastFolder() || Portal.home
    property var backStack: []
    property var fwdStack: []
    property var sel: ({})                       // ścieżka → true
    property int anchorIndex: -1
    property int filterIndex: Math.max(0, filters.findIndex(f => f.name === currentFilterName))
    property bool creatingFolder: false
    property string confirmOverwrite: ""
    readonly property var selection: Object.keys(sel)
    readonly property string query: search.text.trim().toLowerCase()
    readonly property var globs: filters.length ? (filters[filterIndex] ? filters[filterIndex].globs : ["*"]) : ["*"]

    FolderListModel {
        id: files
        folder: "file://" + dlg.path
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: false
        caseSensitive: false
        showFiles: !dlg.directory
        nameFilters: dlg.directory ? ["*"] : dlg.globs
        sortField: FolderListModel.Name
    }

    function go(p, push) {
        if (!p || p === path) return;
        if (push !== false) { backStack = backStack.concat([path]); fwdStack = []; }
        path = p;
        sel = {};
        anchorIndex = -1;
        search.text = "";
        creatingFolder = false;
        confirmOverwrite = "";
        list.forceActiveFocus();
    }
    function back() {
        if (!backStack.length) return;
        fwdStack = fwdStack.concat([path]);
        const p = backStack[backStack.length - 1];
        backStack = backStack.slice(0, -1);
        go(p, false);
    }
    function forward() {
        if (!fwdStack.length) return;
        backStack = backStack.concat([path]);
        const p = fwdStack[fwdStack.length - 1];
        fwdStack = fwdStack.slice(0, -1);
        go(p, false);
    }
    function up() { const p = Portal.parentPath(path); if (p) go(p); }

    function select(i, mods) {
        const p = files.get(i, "filePath");
        if (dlg.multiple && (mods & Qt.ControlModifier)) {
            const s = Object.assign({}, sel);
            if (s[p]) delete s[p]; else s[p] = true;
            sel = s;
            anchorIndex = i;
        } else if (dlg.multiple && (mods & Qt.ShiftModifier) && anchorIndex >= 0) {
            const s = {};
            for (let k = Math.min(anchorIndex, i); k <= Math.max(anchorIndex, i); ++k) s[files.get(k, "filePath")] = true;
            sel = s;
        } else {
            sel = ({ [p]: true });
            anchorIndex = i;
        }
        list.currentIndex = i;
        // Przy zapisie kliknięty plik podpowiada nazwę
        if (saving && !files.get(i, "fileIsDir")) nameField.text = files.get(i, "fileName");
        confirmOverwrite = "";
    }
    function activate(i) {
        if (files.get(i, "fileIsDir")) { go(files.get(i, "filePath")); return; }
        select(i, 0);
        accept();
    }

    readonly property bool canAccept: saving ? nameField.text.trim().length > 0
                                     : directory ? true
                                     : selection.some(p => !Portal.isDir(p))
    function finish(paths) {
        result = paths;
        accepted();
    }
    function accept() {
        if (saving) {
            const name = nameField.text.trim();
            if (!name) return;
            const target = (path === "/" ? "" : path) + "/" + name;
            if (Portal.isDir(target)) { go(target); return; }
            if (Portal.exists(target) && confirmOverwrite !== target) { confirmOverwrite = target; return; }
            finish([target]);
        } else if (directory) {
            const dirs = selection.filter(p => Portal.isDir(p));
            finish(dirs.length ? dirs.slice(0, multiple ? dirs.length : 1) : [path]);
        } else {
            const chosen = selection.filter(p => !Portal.isDir(p));
            if (!chosen.length) {
                // Zaznaczony folder i Enter — wejście do folderu
                if (selection.length === 1) go(selection[0]);
                return;
            }
            finish(multiple ? chosen : [chosen[0]]);
        }
    }
    function cancel() { rejected(); }
    // Testy (ASTER_PORTAL_AUTOPICK): pierwszy pasujący plik i „Otwórz”/„Zapisz”
    function testPick() {
        if (saving) { accept(); return; }
        for (let i = 0; i < files.count; ++i)
            if (!files.get(i, "fileIsDir")) { select(i, 0); break; }
        accept();
    }
    function createFolder(name) {
        const p = Portal.makeFolder(path, name);
        creatingFolder = false;
        if (p) go(p);
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
    function kind(ext, isDir) {
        if (isDir) return { icon: "folder", color: "#3B82F6" };
        const e = (ext || "").toLowerCase();
        const groups = [
            [["jpg", "jpeg", "png", "gif", "webp", "bmp", "svg", "heic", "avif"], "image", "#C026D3"],
            [["pdf"], "doc", "#D93B3B"],
            [["doc", "docx", "odt", "rtf", "txt", "md"], "doc", "#3B6FE0"],
            [["xls", "xlsx", "ods", "csv"], "sheet", "#1E9E5A"],
            [["mp3", "flac", "wav", "ogg", "m4a", "opus"], "music", "#D6457A"],
            [["mp4", "mkv", "mov", "webm", "avi"], "video", "#8B5CF6"],
            [["zip", "rar", "7z", "tar", "gz", "xz", "zst"], "drive", "#C98A12"]
        ];
        for (const g of groups) if (g[0].indexOf(e) >= 0) return { icon: g[1], color: g[2] };
        return { icon: "doc", color: "#6B7280" };
    }
    readonly property var imageExt: ["jpg", "jpeg", "png", "gif", "webp", "bmp", "svg", "avif"]

    Component.onCompleted: {
        if (saving) {
            nameField.text = currentName;
            nameField.forceActiveFocus();
            // Zaznaczona sama nazwa, bez rozszerzenia — można od razu pisać
            const dot = currentName.lastIndexOf(".");
            nameField.select(0, dot > 0 ? dot : currentName.length);
        } else {
            list.forceActiveFocus();
        }
        requestActivate();
    }

    Shortcut { sequence: "Escape"; onActivated: { if (dlg.creatingFolder) dlg.creatingFolder = false; else dlg.cancel(); } }
    Shortcut { sequences: ["Alt+Left"]; onActivated: dlg.back() }
    Shortcut { sequences: ["Alt+Right"]; onActivated: dlg.forward() }
    Shortcut { sequences: ["Alt+Up"]; onActivated: dlg.up() }
    Shortcut { sequence: "Ctrl+H"; onActivated: files.showHidden = !files.showHidden }
    Shortcut { sequences: ["Ctrl+F", "Ctrl+L"]; onActivated: search.forceActiveFocus() }
    Shortcut { sequence: "Ctrl+Shift+N"; onActivated: dlg.creatingFolder = true }

    // ——— Okno ———
    function updateEffects() {
        WindowEffects.setBlur(dlg, Qt.rect(m, m, frame.width, frame.height), r);
        WindowEffects.setInputRegion(dlg, Qt.rect(Math.max(0, m - 6), Math.max(0, m - 6), frame.width + (maxed ? 0 : 12), frame.height + (maxed ? 0 : 12)));
    }
    onWidthChanged: effectsTimer.restart()
    onHeightChanged: effectsTimer.restart()
    Timer { id: effectsTimer; interval: 16; onTriggered: dlg.updateEffects() }

    WindowShadow { window: dlg; frame: frame; radius: dlg.r; visible: !dlg.maxed }
    ResizeHandles { window: dlg; frame: frame; margin: dlg.m }

    Rectangle {
        id: frame
        x: dlg.m; y: dlg.m
        width: dlg.width - 2 * dlg.m
        height: dlg.height - 2 * dlg.m
        radius: dlg.r
        color: Theme.windowGlass
        border.width: dlg.maxed ? 0 : 1
        border.color: Theme.edge
        WindowSheen { window: dlg; radius: dlg.r; animateOpen: false }

        // ——— Pasek boczny: tytuł i miejsca ———
        Item {
            id: sidebar
            width: 210; height: parent.height
            DragHandler { target: null; onActiveChanged: if (active) dlg.startSystemMove() }
            Text {
                x: 22; y: 22
                width: parent.width - 34
                text: dlg.heading
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Column {
                x: 10; y: 62
                width: parent.width - 20
                spacing: 2
                Repeater {
                    model: Portal.places()
                    delegate: HoverButton {
                        id: place
                        required property var modelData
                        readonly property bool here: dlg.path === modelData.path
                        width: parent.width; height: 34; radius: 10
                        baseColor: here ? Theme.accentSoft : "transparent"
                        onClicked: dlg.go(modelData.path)
                        Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; d: Icons[place.modelData.icon] || Icons.folder; size: 16; color: place.here ? Theme.accentText : Theme.text2 }
                        Text {
                            x: 38; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 46; elide: Text.ElideRight
                            text: place.modelData.name
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 13; font.weight: place.here ? Font.Medium : Font.Normal
                        }
                    }
                }
            }
        }

        // ——— Treść ———
        GlassPane {
            id: pane
            x: sidebar.width
            width: parent.width - x; height: parent.height
            topRightRadius: dlg.r; bottomRightRadius: dlg.r

            // Pasek: nawigacja, ścieżka, nowy folder, szukaj
            Item {
                id: header
                width: parent.width; height: 56
                DragHandler { target: null; onActiveChanged: if (active) dlg.startSystemMove() }
                Row {
                    id: nav
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    ToolBtn { icon: "back"; enabled: dlg.backStack.length > 0; onClicked: dlg.back() }
                    ToolBtn { icon: "forward"; enabled: dlg.fwdStack.length > 0; onClicked: dlg.forward() }
                }
                Flickable {
                    id: crumbFlick
                    anchors.left: nav.right; anchors.leftMargin: 8
                    anchors.right: tools.left; anchors.rightMargin: 8
                    height: parent.height
                    contentWidth: crumbRow.width
                    contentX: Math.max(0, contentWidth - width)
                    interactive: contentWidth > width
                    clip: true
                    Row {
                        id: crumbRow
                        height: parent.height
                        Repeater {
                            model: Portal.crumbs(dlg.path)
                            delegate: Row {
                                id: crumb
                                required property int index
                                required property var modelData
                                anchors.verticalCenter: parent.verticalCenter
                                Icon { visible: crumb.index > 0; anchors.verticalCenter: parent.verticalCenter; d: Icons.chevronRight; size: 12; stroke: 2; color: Theme.text2 }
                                HoverButton {
                                    width: crumbText.implicitWidth + 16; height: 28; radius: 8
                                    onClicked: dlg.go(crumb.modelData.path)
                                    Text {
                                        id: crumbText
                                        anchors.centerIn: parent
                                        text: crumb.modelData.name
                                        color: crumb.modelData.path === dlg.path ? Theme.text : Theme.text2
                                        font.family: Theme.font; font.pixelSize: 13
                                        font.weight: crumb.modelData.path === dlg.path ? Font.DemiBold : Font.Normal
                                    }
                                }
                            }
                        }
                    }
                }
                Row {
                    id: tools
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    ToolBtn { icon: "folderPlus"; visible: dlg.saving || dlg.directory; onClicked: dlg.creatingFolder = true }
                    Rectangle {
                        width: 200; height: 32; radius: 16
                        color: Theme.fill
                        border.width: search.activeFocus ? 1.5 : 0
                        border.color: Theme.accent
                        Icon { x: 11; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 14; color: Theme.text2 }
                        TextInput {
                            id: search
                            x: 32; width: parent.width - 44
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.text; selectionColor: Theme.accentSoft
                            font.family: Theme.font; font.pixelSize: 13
                            clip: true
                            Keys.onDownPressed: list.forceActiveFocus()
                            Keys.onEscapePressed: { text = ""; list.forceActiveFocus(); }
                            Text { anchors.verticalCenter: parent.verticalCenter; visible: !search.text; text: "Szukaj w tym folderze"; color: Theme.text2; font: search.font }
                        }
                    }
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
            }

            // Nagłówki kolumn
            Item {
                id: columns
                y: header.height
                width: parent.width; height: 30
                readonly property real sizeX: width - 250
                readonly property real dateX: width - 150
                Text { x: 56; anchors.verticalCenter: parent.verticalCenter; text: "Nazwa"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
                Text { x: columns.sizeX; anchors.verticalCenter: parent.verticalCenter; text: "Rozmiar"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium; visible: !dlg.directory }
                Text { x: columns.dateX; anchors.verticalCenter: parent.verticalCenter; text: "Zmieniono"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
            }

            // Nowy folder (w miejscu, na górze listy)
            Rectangle {
                id: newFolderRow
                y: columns.y + columns.height
                x: 10; width: parent.width - 20
                height: dlg.creatingFolder ? 44 : 0
                visible: height > 0
                radius: 10
                color: Theme.accentSoft
                onVisibleChanged: if (visible) { newName.text = "Nowy folder"; newName.selectAll(); newName.forceActiveFocus(); }
                Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; d: Icons.folderPlus; size: 18; color: Theme.accentText }
                TextInput {
                    id: newName
                    x: 46; width: parent.width - 60
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text; selectionColor: Theme.accentSoft
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                    Keys.onReturnPressed: dlg.createFolder(text)
                    Keys.onEnterPressed: dlg.createFolder(text)
                    Keys.onEscapePressed: dlg.creatingFolder = false
                }
            }

            ListView {
                id: list
                y: newFolderRow.y + newFolderRow.height
                x: 10; width: parent.width - 20
                height: footer.y - y
                clip: true
                model: files
                currentIndex: -1
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: true
                highlightFollowsCurrentItem: false
                Keys.onReturnPressed: { if (currentIndex >= 0) dlg.activate(currentIndex); else dlg.accept(); }
                Keys.onEnterPressed: { if (currentIndex >= 0) dlg.activate(currentIndex); else dlg.accept(); }
                Keys.onUpPressed: (e) => { if (currentIndex > 0) dlg.select(currentIndex - 1, e.modifiers); }
                Keys.onDownPressed: (e) => { if (currentIndex < count - 1) dlg.select(currentIndex + 1, e.modifiers); }
                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_Backspace) { dlg.up(); e.accepted = true; }
                    else if (e.key === Qt.Key_A && (e.modifiers & Qt.ControlModifier) && dlg.multiple) {
                        const s = {};
                        for (let i = 0; i < count; ++i) s[files.get(i, "filePath")] = true;
                        dlg.sel = s; e.accepted = true;
                    }
                }

                delegate: Item {
                    id: row
                    required property int index
                    required property string fileName
                    required property string filePath
                    required property string fileSuffix
                    required property bool fileIsDir
                    required property var fileSize
                    required property var fileModified
                    readonly property bool chosen: !!dlg.sel[filePath]
                    readonly property bool match: !dlg.query || fileName.toLowerCase().indexOf(dlg.query) >= 0
                    readonly property var k: dlg.kind(fileSuffix, fileIsDir)
                    width: ListView.view.width
                    height: match ? 44 : 0
                    visible: match
                    // Pliki, których nie można wybrać (folder przy wyborze folderu — można; przy zapisie pliki są tylko podpowiedzią)
                    opacity: dlg.directory && !fileIsDir ? 0.4 : 1

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: row.chosen ? Theme.accentSoft : rowArea.containsMouse ? Theme.hover : "transparent"
                    }
                    Rectangle {
                        id: tile
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        width: 30; height: 30; radius: 8
                        color: Qt.rgba(Qt.color(row.k.color).r, Qt.color(row.k.color).g, Qt.color(row.k.color).b, Theme.dark ? 0.22 : 0.13)
                        Icon { anchors.centerIn: parent; visible: thumb.status !== Image.Ready; d: Icons[row.k.icon] || Icons.doc; size: 16; stroke: 1.9; color: Theme.dark ? Qt.lighter(row.k.color, 1.4) : row.k.color }
                        Image {
                            id: thumb
                            anchors.fill: parent
                            source: dlg.imageExt.indexOf(row.fileSuffix.toLowerCase()) >= 0 ? "file://" + row.filePath : ""
                            sourceSize: Qt.size(64, 64)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: status === Image.Ready
                        }
                    }
                    Text {
                        x: 52; width: columns.sizeX - 60
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.fileName
                        elide: Text.ElideMiddle
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 13
                    }
                    Text {
                        x: columns.sizeX - 10
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !row.fileIsDir
                        text: Portal.sizeText(row.fileSize)
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 12
                    }
                    Text {
                        x: columns.dateX - 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: dlg.when(row.fileModified)
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 12
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: (e) => { list.forceActiveFocus(); dlg.select(row.index, e.modifiers); }
                        onDoubleClicked: dlg.activate(row.index)
                    }
                }

                // Pusty folder
                Column {
                    anchors.centerIn: parent
                    visible: files.status === FolderListModel.Ready && (files.count === 0 || (dlg.query && !list.anyMatch))
                    spacing: 8
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; d: dlg.query ? Icons.search : Icons.folder; size: 34; stroke: 1.5; color: Theme.text2 }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: dlg.query ? "Nic nie pasuje do „" + search.text.trim() + "”" : dlg.directory ? "Brak podfolderów" : "Ten folder jest pusty"
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                    }
                }
                readonly property bool anyMatch: {
                    if (!dlg.query) return true;
                    for (let i = 0; i < files.count; ++i) if (files.get(i, "fileName").toLowerCase().indexOf(dlg.query) >= 0) return true;
                    return false;
                }
            }

            // ——— Dół: nazwa (zapis), rodzaj plików, przyciski ———
            Item {
                id: footer
                anchors.bottom: parent.bottom
                width: parent.width
                height: (dlg.saving ? 58 : 0) + (dlg.confirmOverwrite ? 40 : 0) + 64
                Rectangle { width: parent.width; height: 1; color: Theme.line }

                Item {
                    id: nameRow
                    visible: dlg.saving
                    y: 14; x: 20; width: parent.width - 40; height: 38
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Nazwa"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                    Rectangle {
                        x: 64; width: parent.width - 64; height: 38; radius: 19
                        color: Theme.fill
                        border.width: nameField.activeFocus ? 1.5 : 0
                        border.color: Theme.accent
                        TextInput {
                            id: nameField
                            x: 16; width: parent.width - 32
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                            font.family: Theme.font; font.pixelSize: 14
                            clip: true
                            onTextEdited: dlg.confirmOverwrite = ""
                            Keys.onReturnPressed: dlg.accept()
                            Keys.onEnterPressed: dlg.accept()
                            Keys.onDownPressed: list.forceActiveFocus()
                        }
                    }
                }

                // Plik już istnieje
                Rectangle {
                    visible: !!dlg.confirmOverwrite
                    x: 20; y: (dlg.saving ? 58 : 0) + 8
                    width: parent.width - 40; height: 32; radius: 10
                    color: Qt.rgba(0.9, 0.3, 0.3, Theme.dark ? 0.22 : 0.12)
                    Text {
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 28; elide: Text.ElideMiddle
                        text: "„" + dlg.confirmOverwrite.split("/").pop() + "” już istnieje. Kliknij „Zastąp”, żeby go nadpisać."
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                    }
                }

                Item {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 64
                    // Rodzaj plików (gdy program podał kilka)
                    HoverButton {
                        id: filterButton
                        visible: dlg.filters.length > 1 && !dlg.directory
                        x: 20; anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(260, filterText.implicitWidth + 44); height: 36; radius: 18
                        baseColor: Theme.fill
                        onClicked: {
                            const p = filterButton.mapToItem(frame, 0, -8 - dlg.filters.length * 34 - 12);
                            menu.openAt(p.x, p.y, dlg.filters.map((f, i) => ({ label: f.name, icon: i === dlg.filterIndex ? "check" : "", action: String(i) })));
                        }
                        Text {
                            id: filterText
                            x: 16; width: parent.width - 40
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: dlg.filters[dlg.filterIndex] ? dlg.filters[dlg.filterIndex].name : ""
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                        }
                        Icon { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; d: Icons.chevronDown; size: 12; stroke: 2; color: Theme.text2 }
                    }
                    Text {
                        visible: !filterButton.visible && dlg.multiple && dlg.selection.length > 1
                        x: 22; anchors.verticalCenter: parent.verticalCenter
                        text: "Zaznaczono: " + dlg.selection.length
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                    }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Pill { text: "Anuluj"; onClicked: dlg.cancel() }
                        Pill {
                            text: dlg.confirmOverwrite ? "Zastąp" : dlg.okLabel
                            primary: true
                            danger: !!dlg.confirmOverwrite
                            enabled: dlg.canAccept
                            onClicked: { if (dlg.confirmOverwrite) dlg.finish([dlg.confirmOverwrite]); else dlg.accept(); }
                        }
                    }
                }
            }
        }

        ContextMenu {
            id: menu
            onTriggered: (a) => dlg.filterIndex = parseInt(a)
        }
    }

    component Pill: HoverButton {
        id: pill
        property string text
        property bool primary: false
        property bool danger: false
        width: Math.max(104, pillText.implicitWidth + 36); height: 38; radius: 19
        baseColor: danger ? "#E5484D" : primary ? Theme.accent : Theme.fill
        color: hovered && enabled ? (primary || danger ? Qt.darker(baseColor, 1.1) : Theme.hover) : baseColor
        opacity: enabled ? 1 : 0.45
        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.text
            color: pill.primary || pill.danger ? "white" : Theme.text
            font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium
        }
    }
}
