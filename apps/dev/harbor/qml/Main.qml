pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Dialogs
import Aster.Ui
import Aster.Harbor

// Aster Harbor — kontenery i środowiska programisty:
//  • Środowiska: toolboxy i kontenery podmana (stan, porty, CPU/RAM), start/stop/restart/usuń, logi, terminal,
//  • Projekty compose: foldery z compose.yaml — up/down i usługi,
//  • Obrazy: lista i sprzątanie nieużywanych,
//  • „Nowe środowisko”: toolbox z gotowymi narzędziami (Node, Python, Go, Rust, C/C++, PHP, Java, Ruby).
Window {
    id: win
    property string startPage: ""
    property string page: "envs"
    property string selected: ""
    property bool newEnv: false
    property var confirm: null                  // { text, detail, button, action }

    width: 1040 + 2 * m
    height: 680 + 2 * m
    minimumWidth: 800 + 2 * m
    minimumHeight: 480 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: "Aster Harbor"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 24

    readonly property var pages: [
        { id: "envs", name: "Środowiska", icon: "terminal", colors: ["#5EE7DF", "#2E9BEF"] },
        { id: "compose", name: "Projekty compose", icon: "layers", colors: ["#C4B5FD", "#7C3AED"] },
        { id: "images", name: "Obrazy", icon: "disc", colors: ["#FDBA74", "#EA580C"] }
    ]
    readonly property var current: pages.find(p => p.id === page) || pages[0]

    // Odświeżanie tylko przy widocznym oknie (lekko dla słabszych laptopów)
    Binding { target: Harbor; property: "active"; value: win.visible && win.visibility !== Window.Minimized }

    function go(id) {
        if (id === page) return;
        page = id;
        if (id === "images") Harbor.refreshImages();
        pageAnim.restart();
    }
    function openPage(p) {
        if (p === "new") openNewEnv();
        else if (pages.find(x => x.id === p)) go(p);
    }
    Component.onCompleted: { effectsTimer.restart(); if (startPage) openPage(startPage); }

    function plural(n, one, few, many) {
        const t = n % 100, u = n % 10;
        return n + " " + (n === 1 ? one : (u >= 2 && u <= 4 && (t < 12 || t > 14)) ? few : many);
    }
    function kindInfo(id) { return Harbor.kinds.find(k => k.id === id) || null; }
    function toast(text) { toastBox.text = text; toastBox.shown = true; toastTimer.restart(); }
    Connections { target: Harbor; function onMessage(text) { win.toast(text); } }

    function openNewEnv() { newEnv = true; newEnvSheet.reset(); }

    function askRemove(name) {
        const c = Harbor.info(name);
        if (!c.name) return;
        confirm = {
            text: "Usunąć „" + name + "”?",
            detail: c.toolbox
                ? "Toolbox zniknie razem z programami doinstalowanymi w środku. Twoje pliki w folderze domowym zostają."
                : "Kontener zostanie zatrzymany i usunięty. Dane spoza wolumenów przepadną; obraz zostaje.",
            button: "Usuń", action: () => Harbor.remove(name)
        };
    }
    function askPrune() {
        const s = Harbor.imageSummary;
        confirm = {
            text: "Usunąć nieużywane obrazy?",
            detail: s.unusedCount > 0
                ? "Obrazy bez żadnego kontenera (" + s.unusedCount + ") zostaną usunięte — zwolni to około " + s.unusedText + ". W razie potrzeby pobiorą się ponownie."
                : "Nie ma obrazów bez kontenerów — nic do usunięcia.",
            button: "Usuń nieużywane", action: () => Harbor.pruneImages()
        };
    }

    function showRowMenu(name, item, x, y) {
        const c = Harbor.info(name);
        if (!c.name) return;
        selected = name;
        const items = [];
        if (c.running) items.push({ label: "Zatrzymaj", icon: "stop", action: "stop" });
        else items.push({ label: "Uruchom", icon: "play", action: "start" });
        items.push({ label: "Uruchom ponownie", icon: "reload", action: "restart", enabled: c.running });
        items.push({ separator: true });
        items.push({ label: "Otwórz terminal", icon: "prompt", shortcut: "Enter", action: "terminal" });
        items.push({ label: "Logi", icon: "list", shortcut: "L", action: "logs" });
        if (c.folder) {
            items.push({ separator: true });
            items.push({ label: "Otwórz folder projektu", icon: "folder", action: "folder" });
            items.push({ label: "Otwórz w Aster Code", icon: "code", action: "code" });
        }
        items.push({ separator: true });
        items.push({ label: "Kopiuj nazwę", icon: "copy", action: "copy" });
        items.push({ label: "Usuń…", icon: "trash", shortcut: "Del", action: "remove", danger: true });
        menu.target = name;
        const p = item.mapToItem(frame, x, y);
        menu.openAt(p.x, p.y, items);
    }
    function runMenuAction(a) {
        const name = menu.target;
        const c = Harbor.info(name);
        if (a === "start") Harbor.start(name);
        else if (a === "stop") Harbor.stop(name);
        else if (a === "restart") Harbor.restart(name);
        else if (a === "terminal") Harbor.openTerminal(name);
        else if (a === "logs") Harbor.openLogs(name);
        else if (a === "folder") Harbor.openFolder(c.folder);
        else if (a === "code") Harbor.openInCode(c.folder);
        else if (a === "copy") { clip.text = name; clip.selectAll(); clip.copy(); toast("Skopiowano „" + name + "”"); }
        else if (a === "remove") askRemove(name);
        else if (a.startsWith("project:")) {
            const f = a.slice(a.indexOf(":", 8) + 1);
            if (a.startsWith("project:folder:")) Harbor.openFolder(f);
            else if (a.startsWith("project:code:")) Harbor.openInCode(f);
            else if (a.startsWith("project:forget:")) Harbor.forgetProject(f);
        }
    }
    TextEdit { id: clip; visible: false }

    // Do testów (ASTER_OPEN): new | new:python | create:rodzaj:nazwa[:folder] | logs:NAZWA (z filtrem listy) | menu:NAZWA | confirm:NAZWA | compose | images | prune | project:FOLDER | up:FOLDER | call:metoda:arg
    function testOpen(what) {
        if (what === "new") openNewEnv();
        else if (what.startsWith("new:")) { openNewEnv(); newEnvSheet.pick(what.slice(4)); }
        else if (what.startsWith("create:")) {
            const p = what.slice(7).split(":");   // create:kind:name:folder
            Harbor.createEnvironment(p[0], p[1], p[2] || Harbor.defaultFolder(p[1]));
        }
        else if (what.startsWith("logs:")) { search.text = what.slice(5); win.selected = what.slice(5); Harbor.openLogs(what.slice(5)); }
        else if (what.startsWith("menu:")) showRowMenu(what.slice(5), envPage, 640, 120);
        else if (what.startsWith("confirm:")) askRemove(what.slice(8));
        else if (what === "compose" || what === "images" || what === "envs") go(what);
        else if (what === "prune") { go("images"); pruneTimer.start(); }
        else if (what.startsWith("project:")) { go("compose"); Harbor.addProject("file://" + what.slice(8)); }
        else if (what.startsWith("up:")) { go("compose"); Harbor.addProject("file://" + what.slice(3)); Harbor.composeUp(what.slice(3)); }
        else if (what.startsWith("find:")) search.text = what.slice(5);
        else if (what.startsWith("call:")) {   // call:metoda[:argument] — akcje Harbora bez klikania (testy)
            const rest = what.slice(5), i = rest.indexOf(":");
            if (i < 0) Harbor[rest](); else Harbor[rest.slice(0, i)](rest.slice(i + 1));
        }
    }
    Timer { id: pruneTimer; interval: 800; onTriggered: win.askPrune() }

    Shortcut { sequence: "Ctrl+N"; onActivated: win.openNewEnv() }
    Shortcut { sequence: "Ctrl+F"; onActivated: { win.go("envs"); search.forceActiveFocus(); } }
    Shortcut { sequence: "F5"; onActivated: { Harbor.refresh(); Harbor.refreshImages(); } }
    Shortcut { sequence: "Ctrl+1"; onActivated: win.go("envs") }
    Shortcut { sequence: "Ctrl+2"; onActivated: win.go("compose") }
    Shortcut { sequence: "Ctrl+3"; onActivated: win.go("images") }
    Shortcut { sequence: "Ctrl+W"; onActivated: win.close() }
    Shortcut {
        sequence: "Esc"
        enabled: !!win.confirm || win.newEnv || Harbor.logName !== "" || menu.shown
        onActivated: {
            if (menu.shown) menu.close();
            else if (win.confirm) win.confirm = null;
            else if (win.newEnv && Harbor.taskState !== "running") { win.newEnv = false; Harbor.closeTask(); }
            else if (Harbor.logName !== "") Harbor.closeLogs();
        }
    }
    Shortcut { sequence: "L"; enabled: win.page === "envs" && win.selected !== "" && !search.activeFocus; onActivated: Harbor.openLogs(win.selected) }
    Shortcut { sequence: "Return"; enabled: win.page === "envs" && win.selected !== "" && !search.activeFocus && !win.newEnv; onActivated: Harbor.openTerminal(win.selected) }
    Shortcut { sequence: "Del"; enabled: win.page === "envs" && win.selected !== "" && !search.activeFocus; onActivated: win.askRemove(win.selected) }

    FolderDialog {
        id: projectDialog
        title: "Folder z projektem compose"
        onAccepted: Harbor.addProject(selectedFolder)
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
            width: 222; height: parent.height
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }

            Row {
                x: 20; y: 22
                spacing: 9
                Rectangle {
                    width: 26; height: 26; radius: 8
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#5EE7DF" }
                        GradientStop { position: 0.5; color: "#2E9BEF" }
                        GradientStop { position: 1; color: "#3F4BD8" }
                    }
                    Icon { anchors.centerIn: parent; d: Icons.layers; size: 15; stroke: 2; color: "white" }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Harbor"
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                }
            }

            Column {
                x: 10; y: 66
                width: parent.width - 20
                spacing: 2
                Repeater {
                    model: win.pages
                    delegate: NavItem {
                        required property var modelData
                        item: modelData
                        count: modelData.id === "envs" ? Harbor.summary.total || 0
                             : modelData.id === "compose" ? Harbor.summary.projects || 0
                             : Harbor.imageSummary.count || 0
                    }
                }
            }

            // Na dole: ile działa i ile zużywa
            Column {
                x: 18; anchors.bottom: parent.bottom; anchors.bottomMargin: 18
                width: parent.width - 36
                spacing: 10
                visible: Harbor.ready && Harbor.available
                Item {
                    width: parent.width; height: 18
                    Row {
                        spacing: 7
                        anchors.verticalCenter: parent.verticalCenter
                        StateDot { anchors.verticalCenter: parent.verticalCenter; running: (Harbor.summary.running || 0) > 0; size: 8 }
                        Text {
                            text: "Działa " + (Harbor.summary.running || 0) + " z " + (Harbor.summary.total || 0)
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                        }
                    }
                }
                Repeater {
                    model: [
                        ["Procesor", (Harbor.summary.cpu || 0).toLocaleString(Qt.locale("pl_PL"), "f", 1) + "%", Math.min(100, Harbor.summary.cpu || 0), "#5B8CFF"],
                        ["Pamięć", Harbor.summary.memText || "0 B", Math.min(100, (Harbor.summary.mem || 0) / 8e9 * 100), "#B072FF"]
                    ]
                    delegate: Column {
                        id: mini
                        required property var modelData
                        width: parent.width
                        spacing: 5
                        Item {
                            width: parent.width; height: 15
                            Text { text: mini.modelData[0]; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                            Text { anchors.right: parent.right; text: mini.modelData[1]; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium; font.features: { "tnum": 1 } }
                        }
                        Rectangle {
                            width: parent.width; height: 5; radius: 2.5
                            color: Theme.fill
                            Rectangle {
                                width: Math.max(height, parent.width * mini.modelData[2] / 100); height: parent.height; radius: 2.5
                                color: mini.modelData[3]
                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
            }
        }

        // ——— Strona ———
        GlassPane {
            id: main
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
                Text {
                    id: pageTitle
                    x: 28; anchors.verticalCenter: parent.verticalCenter
                    text: win.current.name
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4
                }

                Row {
                    anchors.right: winButtons.left; anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Rectangle {
                        visible: win.page === "envs"
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(120, Math.min(220, topBar.width - pageTitle.width - 440)); height: 34; radius: 10
                        color: Theme.fill
                        border.width: search.activeFocus ? 1.5 : 0
                        border.color: Theme.accent
                        Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 15; color: Theme.text2 }
                        TextInput {
                            id: search
                            x: 32; width: parent.width - 42
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                            selectionColor: Theme.accentSoft
                            clip: true
                            Keys.onEscapePressed: { text = ""; focus = false; }
                            Text { visible: !search.text; text: "Szukaj"; color: Theme.text2; font: search.font }
                        }
                    }
                    ActionButton {
                        visible: win.page === "envs"
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Nowe środowisko"; icon: "plus"; primary: true
                        onClicked: win.openNewEnv()
                    }
                    ActionButton {
                        visible: win.page === "compose"
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Dodaj folder…"; icon: "folderPlus"; primary: true
                        onClicked: projectDialog.open()
                    }
                    ToolBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "reload"; tip: "Odśwież (F5)"
                        onClicked: { Harbor.refresh(); Harbor.refreshImages(); }
                    }
                }
                WindowButtons {
                    id: winButtons
                    window: win
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Item {
                id: pageHolder
                y: topBar.height
                width: parent.width
                height: parent.height - y - (logs.open ? logs.height : 0)
                property real shift: 0
                transform: Translate { x: pageHolder.shift }

                // Podman niedostępny
                Column {
                    visible: Harbor.ready && (!Harbor.available || Harbor.error !== "")
                    anchors.centerIn: parent
                    width: Math.min(440, parent.width - 60)
                    spacing: 10
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 64; height: 64; radius: 20
                        color: Theme.fill
                        Icon { anchors.centerIn: parent; d: Icons.warning; size: 30; color: Theme.text2 }
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: Harbor.available ? "Podman nie odpowiada" : "Podman nie jest zainstalowany"
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                        text: Harbor.available ? Harbor.error
                                               : "Harbor zarządza kontenerami przez podmana. W Asterze jest od razu; w innym systemie zainstaluj pakiety podman i toolbox."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.3
                    }
                }

                EnvironmentsPage {
                    id: envPage
                    anchors.fill: parent
                    visible: win.page === "envs" && Harbor.available && Harbor.error === ""
                    filter: search.text
                    selected: win.selected
                    onSelect: (name) => win.selected = name
                    onMenuRequested: (name, item, x, y) => win.showRowMenu(name, item, x, y)
                    onNewRequested: win.openNewEnv()
                    onRemoveRequested: (name) => win.askRemove(name)
                }
                Loader {
                    anchors.fill: parent
                    active: win.page === "compose" && Harbor.available && Harbor.error === ""
                    sourceComponent: ComposePage {
                        onAddRequested: projectDialog.open()
                        onMenuRequested: (folder, item, x, y) => {
                            const p = item.mapToItem(frame, x, y);
                            menu.target = folder;
                            menu.openAt(p.x, p.y, [
                                { label: "Otwórz folder", icon: "folder", action: "project:folder:" + folder },
                                { label: "Otwórz w Aster Code", icon: "code", action: "project:code:" + folder },
                                { separator: true },
                                { label: "Usuń z listy", icon: "close", action: "project:forget:" + folder }
                            ]);
                        }
                    }
                }
                Loader {
                    anchors.fill: parent
                    active: win.page === "images" && Harbor.available && Harbor.error === ""
                    sourceComponent: ImagesPage { onPruneRequested: win.askPrune() }
                }
            }
            ParallelAnimation {
                id: pageAnim
                NumberAnimation { target: pageHolder; property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutQuad }
                NumberAnimation { target: pageHolder; property: "shift"; from: 14; to: 0; duration: 240; easing.type: Easing.OutQuint }
            }

            LogsPanel {
                id: logs
                // Wysuwa się od dołu
                y: parent.height - (open ? height : 0)
                visible: open || slideAnim.running
                Behavior on y { NumberAnimation { id: slideAnim; duration: 220; easing.type: Easing.OutQuint } }
                width: parent.width
                height: Math.round(parent.height * (expanded ? 0.78 : 0.46))
                bottomRightRadius: win.r
            }

            // Komunikat na dole
            Rectangle {
                id: toastBox
                property bool shown: false
                property alias text: toastText.text
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - (shown ? height + 22 + (logs.open ? logs.height : 0) : 0)
                opacity: shown ? 1 : 0
                z: 20
                width: Math.min(parent.width - 40, toastText.implicitWidth + 36); height: 40; radius: 20
                color: Theme.dark ? "#ECEEF3" : "#1E2027"
                Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
                Behavior on opacity { NumberAnimation { duration: 160 } }
                Text { id: toastText; anchors.centerIn: parent; width: Math.min(implicitWidth, parent.width - 36); elide: Text.ElideRight; color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                Timer { id: toastTimer; interval: 3200; onTriggered: toastBox.shown = false }
            }
        }

        ContextMenu {
            id: menu
            property string target
            onTriggered: (a) => win.runMenuAction(a)
        }

        NewEnvSheet {
            id: newEnvSheet
            radius: win.r
            shown: win.newEnv || Harbor.taskState !== ""
            onDone: { win.newEnv = false; Harbor.closeTask(); }
        }

        // ——— Pytanie (usuń, posprzątaj) ———
        Sheet {
            id: confirmSheet
            radius: win.r
            shown: !!win.confirm
            cardWidth: 420
            onDismissed: win.confirm = null
            readonly property var c: win.confirm || ({})
            Text {
                width: parent.width; wrapMode: Text.Wrap
                text: confirmSheet.c.text || ""
                color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Item { width: 1; height: 8 }
            Text {
                width: parent.width; wrapMode: Text.Wrap
                text: confirmSheet.c.detail || ""
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.3
            }
            Item { width: 1; height: 20 }
            Row {
                anchors.right: parent.right
                spacing: 8
                ActionButton { text: "Anuluj"; onClicked: win.confirm = null }
                ActionButton {
                    text: confirmSheet.c.button || "OK"; danger: true
                    onClicked: { const a = win.confirm.action; win.confirm = null; a(); }
                }
            }
        }
    }

    component NavItem: Rectangle {
        id: nav
        property var item
        property int count: 0
        readonly property bool active: win.page === item.id
        width: parent ? parent.width : 0; height: 34
        radius: 9
        color: active ? Theme.accent : (navArea.containsMouse ? Theme.hover : "transparent")
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
            width: parent.width - 80
            text: nav.item.name
            elide: Text.ElideRight
            color: nav.active ? "white" : Theme.text
            font.family: Theme.font; font.pixelSize: 13; font.weight: nav.active ? Font.Medium : Font.Normal
        }
        Text {
            visible: nav.count > 0
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: nav.count
            color: nav.active ? Qt.rgba(1, 1, 1, 0.85) : Theme.text2
            font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 }
        }
        MouseArea {
            id: navArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: win.go(nav.item.id)
        }
    }
}
