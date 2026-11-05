pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Dialogs
import Aster.Ui
import Aster.Photos

// Zdjęcia Aster (zamiast Gwenview): biblioteka — siatka zdjęć z Obrazów, Pobranych, Pulpitu i dodanych
// folderów — oraz oglądanie jednego zdjęcia z resztą folderu pod strzałkami. Otwarte z pliku
// (np. dwuklik w Plikach) od razu pokazuje zdjęcie.
Window {
    id: win
    property string startFile
    property string startFolder

    width: 1100 + 2 * m
    height: 720 + 2 * m
    minimumWidth: 640 + 2 * m
    minimumHeight: 420 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: viewing && viewer && viewer.photo.name ? viewer.photo.name + " — Zdjęcia" : "Zdjęcia"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 12

    // ——— Miejsca i zdjęcia ———
    PhotoModel { id: libModel }
    PhotoModel { id: folderModel }
    property string placeId: startFolder ? "open" : "all"
    readonly property var places: {
        const list = Photos.places.slice();
        if (startFolder) list.unshift({ id: "open", name: Photos.folderName(startFolder), icon: "folder", roots: [startFolder], colors: ["#74CCFF", "#2457E6"], folder: startFolder });
        return list;
    }
    readonly property var place: places.find(p => p.id === placeId) || places[0]
    function openPlace(id) {
        placeId = id;
        const p = place;
        if (p.folder) libModel.openFolder(p.folder);
        else libModel.openLibrary(p.roots);
    }

    property bool viewing: false
    property var viewerModel: libModel
    property bool fromLibrary: false
    function view(model, index, back) {
        viewerModel = model;
        fromLibrary = back;
        viewing = true;
        viewer.index = index;
        viewer.forceActiveFocus();
    }
    function closeViewer() {
        if (!fromLibrary) { win.close(); return; }
        const i = viewer.index;
        viewing = false;
        if (win.visibility === Window.FullScreen) win.showNormal();
        library.positionAt(i);
    }

    Component.onCompleted: {
        effectsTimer.restart();
        if (startFile) {
            viewing = true;
            viewerModel = folderModel;
            viewer.forceActiveFocus();
            const dir = startFile.substring(0, startFile.lastIndexOf("/")) || "/";
            folderModel.openFolder(dir);
        }
        openPlace(placeId);
    }
    Connections {
        target: folderModel
        function onLoaded() {
            if (!win.startFile || !viewer) return;
            viewer.index = Math.max(0, folderModel.indexOf(win.startFile));
            win.startFile = "";
        }
    }

    // ——— Komunikaty (z „Cofnij” po przeniesieniu do kosza) ———
    function toast(text, undo) { toastBox.text = text; toastBox.undo = !!undo; toastBox.shown = true; toastTimer.restart(); }
    Connections { target: Photos; function onMessage(text) { win.toast(text, false); } }
    function undoTrash() {
        const path = Photos.undoTrash();
        toastBox.shown = false;
        if (!path) return;
        const model = viewing ? viewerModel : libModel;
        restorePath = path;
        model.reload();
    }
    property string restorePath: ""
    Connections {
        target: win.viewing ? win.viewerModel : libModel
        function onLoaded() {
            if (!win.restorePath) return;
            const i = (win.viewing ? win.viewerModel : libModel).indexOf(win.restorePath);
            if (i >= 0 && win.viewing) viewer.index = i;
            win.restorePath = "";
        }
    }

    // ——— Menu ———
    function setWallpaper(path) {
        const copy = Photos.wallpaperCopy(path);
        if (!copy) { toast("Nie udało się ustawić tapety", false); return; }
        Config.wallpaper = copy;
        toast("Ustawiono jako tapetę", false);
    }
    function photoMenu(model, index, x, y, inViewer) {
        const p = model.get(index);
        if (!p.path) return;
        menu.path = p.path;
        menu.model = model;
        menu.index = index;
        const items = [];
        if (!inViewer) items.push({ label: "Otwórz", icon: "image", action: "open" }, { separator: true });
        items.push({ label: "Kopiuj", icon: "copy", shortcut: "Ctrl+C", action: "copy" });
        items.push({ label: "Pokaż w folderze", icon: "folder", action: "folder" });
        items.push({ label: "Ustaw jako tapetę", icon: "desktop", action: "wallpaper" });
        if (inViewer) {
            items.push({ separator: true });
            items.push({ label: "Obróć w lewo", icon: "rotateLeft", shortcut: "Ctrl+Shift+R", action: "rotateLeft" });
            items.push({ label: "Obróć w prawo", icon: "rotate", shortcut: "Ctrl+R", action: "rotateRight" });
            items.push({ label: "Pokaz slajdów", icon: "play", shortcut: "F5", action: "slideshow" });
            items.push({ label: win.visibility === Window.FullScreen ? "Zakończ pełny ekran" : "Pełny ekran", icon: "fullscreen", shortcut: "F11", action: "fullscreen" });
        }
        items.push({ separator: true });
        items.push({ label: "Przenieś do kosza", icon: "trash", shortcut: "Del", action: "trash", danger: true });
        const pt = (inViewer ? viewer : library).mapToItem(frame, x, y);
        menu.openAt(inViewer ? pt.x - 250 : pt.x, pt.y, items);
    }
    function runMenu(a) {
        const v = viewer;
        if (a === "open") view(menu.model, menu.index, true);
        else if (a === "copy") { Photos.copy(menu.path); toast("Skopiowano zdjęcie", false); }
        else if (a === "folder") Photos.showInFolder(menu.path);
        else if (a === "wallpaper") setWallpaper(menu.path);
        else if (a === "rotateLeft") v.rotate(false);
        else if (a === "rotateRight") v.rotate(true);
        else if (a === "slideshow") v.toggleSlideshow();
        else if (a === "fullscreen") { if (win.visibility === Window.FullScreen) win.showNormal(); else win.showFullScreen(); }
        else if (a === "trash") {
            if (viewing) v.trash();
            else {
                const name = menu.model.get(menu.index).name;
                if (Photos.trash(menu.path)) { menu.model.removeAt(menu.index); toast("„" + name + "” przeniesiono do kosza", true); }
            }
        }
        if (viewing) Qt.callLater(() => v.forceActiveFocus());
    }

    // Do testów (ASTER_OPEN): view | info | menu | zoom | grid-menu | wallpaper
    function testOpen(what) {
        if (what === "view") view(libModel, 1, true);
        else if (what === "info") { if (!viewing) view(libModel, 1, true); viewer.infoOpen = true; }
        else if (what === "menu") { if (!viewing) view(libModel, 1, true); viewer.menuRequested(frame.width - 120, 50); }
        else if (what === "zoom") { if (!viewing) view(libModel, 1, true); viewer.view.zoomBy(2.4); }
        else if (what === "grid-menu") photoMenu(libModel, 2, 420, 260, false);
        else if (what === "rotate") viewer.rotate(true);
        else if (what === "trash") { if (!viewing) view(libModel, 0, true); viewer.trash(); }
    }

    FolderDialog {
        id: folderDialog
        title: "Dodaj folder do Zdjęć"
        onAccepted: Photos.addFolder(String(selectedFolder))
    }

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

        // ——— Pasek boczny ———
        Item {
            id: side
            visible: !win.viewing
            width: 220; height: parent.height
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }

            Column {
                x: 10; y: 58
                width: parent.width - 20
                spacing: 2
                Repeater {
                    model: win.places
                    delegate: NavItem {
                        required property var modelData
                        required property int index
                        item: modelData
                        // Dodane foldery — oddzielone odstępem
                        topGap: index > 0 && !!modelData.removable && !win.places[index - 1].removable
                    }
                }
                Item { width: 1; height: 6 }
                HoverButton {
                    width: parent.width; height: 34; radius: 9
                    onClicked: folderDialog.open()
                    Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; d: Icons.plus; size: 16; stroke: 2; color: Theme.text2 }
                    Text { x: 42; anchors.verticalCenter: parent.verticalCenter; text: "Dodaj folder…"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                }
            }
        }

        // ——— Biblioteka ———
        GlassPane {
            id: main
            visible: !win.viewing
            x: side.width
            width: parent.width - side.width
            height: parent.height
            topRightRadius: win.r; bottomRightRadius: win.r

            Item {
                id: topBar
                width: parent.width; height: 64
                z: 5
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }
                Column {
                    x: 28; anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        text: win.place.name
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4
                    }
                    Text {
                        text: libModel.loading ? "Szukam zdjęć…" : Photos.plural(libModel.count)
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 12
                    }
                }
                Row {
                    anchors.right: winButtons.left; anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    ToolBtn { icon: "minus"; onClicked: library.tile = Math.max(90, library.tile / 1.25) }
                    ToolBtn { icon: "plus"; onClicked: library.tile = Math.min(360, library.tile * 1.25) }
                    ToolBtn { icon: "play"; enabled: libModel.count > 0; onClicked: { win.view(libModel, 0, true); viewer.toggleSlideshow(); } }
                }
                WindowButtons {
                    id: winButtons
                    window: win
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Library {
                id: library
                y: topBar.height
                width: parent.width; height: parent.height - y
                model: libModel
                emptyText: libModel.loading ? "" : "Brak zdjęć"
                emptyHint: win.place.id === "screenshots" ? "Zrzuty ekranu (Win+Shift+S) zapisują się w folderze Obrazy/Zrzuty ekranu."
                         : "Zdjęcia zapisane w tym miejscu pojawią się tutaj. Dodaj inne foldery przyciskiem „Dodaj folder…”."
                onOpenPhoto: (i) => win.view(libModel, i, true)
                onContextMenu: (i, x, y) => win.photoMenu(libModel, i, x, y, false)
            }
        }

        // ——— Oglądanie ———
        Rectangle {
            anchors.fill: parent
            visible: win.viewing
            radius: win.r
            color: Theme.paneGlass
        }
        Viewer {
            id: viewer
            anchors.fill: parent
            visible: win.viewing
            model: win.viewerModel
            window: win
            canGoBack: win.fromLibrary
            focus: win.viewing
            onBackRequested: win.closeViewer()
            onMenuRequested: (x, y) => win.photoMenu(win.viewerModel, viewer.index, x, y, true)
            onToast: (text, undo) => win.toast(text, undo)
        }

        // Komunikat na dole
        Rectangle {
            id: toastBox
            property bool shown: false
            property bool undo: false
            property alias text: toastText.text
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - (shown ? height + (win.viewing ? 96 : 22) : 0)
            opacity: shown ? 1 : 0
            z: 300
            width: toastRow.implicitWidth + 36; height: 40; radius: 20
            color: Theme.dark ? "#ECEEF3" : "#1E2027"
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Row {
                id: toastRow
                anchors.centerIn: parent
                spacing: 14
                Text { id: toastText; anchors.verticalCenter: parent.verticalCenter; color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                Text {
                    visible: toastBox.undo
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Cofnij"
                    color: Theme.dark ? Qt.darker(Theme.accent, 1.2) : Qt.lighter(Theme.accent, 1.6)
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: win.undoTrash() }
                }
            }
            Timer { id: toastTimer; interval: 5000; onTriggered: toastBox.shown = false }
        }

        ContextMenu {
            id: menu
            property string path
            property var model
            property int index
            onTriggered: (a) => win.runMenu(a)
        }
    }

    // Pozycja paska bocznego: plakietka i nazwa; dodane foldery można usunąć z listy (prawy przycisk)
    component NavItem: Rectangle {
        id: nav
        property var item
        property bool topGap: false
        readonly property bool active: win.placeId === item.id
        width: parent ? parent.width : 0; height: 34 + (topGap ? 12 : 0)
        color: "transparent"
        Rectangle {
            anchors.fill: parent; anchors.topMargin: nav.topGap ? 12 : 0
            radius: 9
            color: nav.active ? Theme.accent : (navArea.containsMouse ? Theme.hover : "transparent")
            Rectangle {
                x: 8; anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 24; radius: 7
                gradient: Gradient {
                    GradientStop { position: 0; color: nav.item.colors[0] }
                    GradientStop { position: 1; color: nav.item.colors[1] }
                }
                Icon { anchors.centerIn: parent; d: Icons[nav.item.icon] || ""; size: 14; stroke: 2; color: "white" }
            }
            Text {
                x: 42; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 50
                text: nav.item.name
                elide: Text.ElideRight
                color: nav.active ? "white" : Theme.text
                font.family: Theme.font; font.pixelSize: 13; font.weight: nav.active ? Font.Medium : Font.Normal
            }
            MouseArea {
                id: navArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (e) => {
                    if (e.button === Qt.RightButton && nav.item.removable) {
                        const p = mapToItem(frame, e.x, e.y);
                        folderMenu.path = nav.item.path;
                        folderMenu.openAt(p.x, p.y, [{ label: "Pokaż w Plikach", icon: "folder", action: "show" },
                                                     { label: "Usuń ze Zdjęć", icon: "close", action: "remove" }]);
                        return;
                    }
                    win.openPlace(nav.item.id);
                }
            }
        }
    }
    ContextMenu {
        id: folderMenu
        parent: frame
        property string path
        onTriggered: (a) => {
            if (a === "show") Qt.openUrlExternally("file://" + path);
            else { Photos.removeFolder(path); if (win.placeId === "folder:" + path) win.openPlace("all"); }
        }
    }
}
