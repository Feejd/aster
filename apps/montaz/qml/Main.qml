pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Dialogs
import Aster.Ui
import Aster.Montaz

// Montaż Aster: prosty edytor filmów. Ekran startowy z wyborem formatu (pionowy, poziomy,
// kwadrat) i ostatnimi projektami, a po otwarciu — edytor z podglądem i osią czasu.
Window {
    id: win
    width: 1280 + 2 * m
    height: 800 + 2 * m
    minimumWidth: 900 + 2 * m
    minimumHeight: 600 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: Project.isOpen ? Project.name + " — Montaż" : "Montaż"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 24

    Component.onCompleted: effectsTimer.restart()
    onClosing: Project.closeProject()

    // Pliki z wiersza poleceń / upuszczone na ekran startowy: nowy projekt w formacie pierwszego filmu
    function startWith(files) {
        Project.newProject(Project.guessFormat(files));
        Project.importFiles(files, -1);
    }

    // ——— Komunikat ———
    function toast(text) { toastBox.text = text; toastBox.shown = true; toastTimer.restart(); }
    Connections {
        target: Project
        function onMessage(text) { win.toast(text) }
    }

    FileDialog {
        id: overlayDialog
        title: "Dodaj nakładkę — film albo zdjęcie"
        currentFolder: "file://" + Project.videosDir()
        nameFilters: ["Filmy i zdjęcia (*.mp4 *.mov *.mkv *.webm *.avi *.m4v *.3gp *.jpg *.jpeg *.png *.webp *.heic *.gif)", "Wszystkie pliki (*)"]
        onAccepted: editor.selected = Project.addOverlay(String(selectedFile), editor.player.position)
    }
    FileDialog {
        id: importDialog
        title: "Dodaj filmy, zdjęcia i muzykę"
        fileMode: FileDialog.OpenFiles
        currentFolder: "file://" + Project.videosDir()
        nameFilters: ["Filmy, zdjęcia i muzyka (*.mp4 *.mov *.mkv *.webm *.avi *.m4v *.3gp *.mts *.jpg *.jpeg *.png *.webp *.heic *.gif *.mp3 *.m4a *.aac *.ogg *.opus *.flac *.wav)", "Wszystkie pliki (*)"]
        onAccepted: {
            const files = selectedFiles.map(u => String(u));
            if (Project.isOpen) Project.importFiles(files, editor.insertFrame());
            else win.startWith(files);
        }
    }
    function importFiles() { importDialog.open() }

    // Do testów (ASTER_OPEN): new:9:16 | import:plik|plik | text:napis | select:N | seek:klatka | split |
    // play | pause | zoom:+/- | style:id | fade:N | speed:x | export | exportstart:plik | menu | home
    function testOpen(what) {
        const arg = what.substring(what.indexOf(":") + 1);
        if (what.startsWith("new:")) Project.newProject(arg);
        else if (what.startsWith("import:")) Project.importFiles(arg.split("|"), -1);
        else if (what.startsWith("open:")) Project.openProject(arg);
        else if (what === "home") Project.closeProject();
        else if (what === "menu" && !Project.isOpen) home.projectMenu(Project.projects[0].id, home, 420, 420);
        else editor.test(what, arg);
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

        Home {
            id: home
            anchors.fill: parent
            visible: !Project.isOpen
            window: win
            radius: win.r
            onMenuRequested: (items, x, y) => menu.openAt(x - win.m, y - win.m, items)   // współrzędne sceny
        }

        Editor {
            id: editor
            anchors.fill: parent
            visible: Project.isOpen
            window: win
            radius: win.r
            onToast: (text) => win.toast(text)
            onImportRequested: win.importFiles()
            onOverlayRequested: overlayDialog.open()
            onMenuRequested: (items, x, y) => menu.openAt(x - win.m, y - win.m, items)   // współrzędne sceny
        }

        // Pliki upuszczone na okno
        DropArea {
            anchors.fill: parent
            keys: ["text/uri-list"]
            onDropped: (drop) => {
                const files = drop.urls.map(u => String(u));
                if (files.length === 0) return;
                if (Project.isOpen && editor.dropTrack(drop.x, drop.y) === "overlay") {
                    for (const f of files) editor.selected = Project.addOverlay(f, editor.dropFrame(drop.x, drop.y));
                } else if (Project.isOpen) Project.importFiles(files, editor.dropFrame(drop.x, drop.y));
                else win.startWith(files);
            }
        }

        Rectangle {
            id: toastBox
            property bool shown: false
            property alias text: toastText.text
            anchors.horizontalCenter: parent.horizontalCenter
            y: shown ? 70 : -height - 10
            opacity: shown ? 1 : 0
            z: 300
            width: toastText.implicitWidth + 36; height: 40; radius: 20
            color: Theme.dark ? "#ECEEF3" : "#1E2027"
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Text { id: toastText; anchors.centerIn: parent; color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
            Timer { id: toastTimer; interval: 3500; onTriggered: toastBox.shown = false }
        }

        ContextMenu {
            id: menu
            onTriggered: (a) => {
                if (Project.isOpen) editor.runMenu(a);
                else home.runMenu(a);
            }
        }
    }
}
