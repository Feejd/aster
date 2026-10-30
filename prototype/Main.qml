import QtQuick
import QtQuick.Window
import QtQuick.Effects

Window {
    id: root
    width: 1440
    height: 900
    visible: true
    title: "Aster — prototyp powłoki"
    color: t.bg

    property bool dark: false
    property string panel: ""          // "", "start", "control", "assistant"
    property bool filesOpen: true
    property real volume: 0.45
    property string output: "Głośniki laptopa"
    property color accent: "#3456E8"
    property string wallpaperVariant: "szczyty"
    property real glassLevel: 0.74          // krycie szkła paneli (0.5 = bardzo przezroczyste, 0.95 = prawie jednolite)
    property bool showDesktopClock: true
    property bool settingsOpen: false
    property bool storeOpen: false
    property bool locked: false
    property string front: "files"          // które okno jest na wierzchu

    readonly property QtObject t: QtObject {
        readonly property bool dark: root.dark
        readonly property color bg: root.dark ? "#0F1218" : "#D9E0EA"
        readonly property color w1: root.dark ? "#1A2233" : "#C4CEDF"
        readonly property color w2: root.dark ? "#221F29" : "#E8E1D5"
        readonly property color w3: root.dark ? "#26324D" : "#AEBBD3"
        readonly property color glass: root.dark ? Qt.rgba(32 / 255, 32 / 255, 38 / 255, root.glassLevel - 0.02) : Qt.rgba(246 / 255, 246 / 255, 250 / 255, root.glassLevel)
        readonly property color bar: root.dark ? Qt.rgba(24 / 255, 24 / 255, 30 / 255, root.glassLevel - 0.12) : Qt.rgba(250 / 255, 250 / 255, 252 / 255, root.glassLevel - 0.12)
        readonly property color windowGlass: root.dark ? Qt.rgba(36 / 255, 36 / 255, 42 / 255, Math.min(0.97, root.glassLevel + 0.04)) : Qt.rgba(240 / 255, 240 / 255, 245 / 255, Math.min(0.97, root.glassLevel + 0.04))
        readonly property color pane: root.dark ? Qt.rgba(30 / 255, 30 / 255, 34 / 255, 0.97) : Qt.rgba(255 / 255, 255 / 255, 255 / 255, 0.97)
        readonly property color surface: root.dark ? "#23262F" : "#FFFFFF"
        readonly property color sidebar: root.dark ? "#1A1D24" : "#F8F9FB"
        readonly property color fill: root.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.06)
        readonly property color line: root.dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.08)
        readonly property color edge: root.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.08)
        readonly property color rim: root.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.55)
        readonly property color text: root.dark ? "#ECEEF3" : "#16181D"
        readonly property color text2: root.dark ? "#A2A9B6" : "#5B6270"
        readonly property color accent: root.accent
        readonly property color accentText: root.dark ? Qt.lighter(root.accent, 1.55) : root.accent
        readonly property color accentSoft: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, root.dark ? 0.28 : 0.14)
        readonly property color hover: root.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.05)
        readonly property color shadow: root.dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.24)
    }

    readonly property var apps: [
        { name: "Pliki", color: "#3456E8", icon: "folder" },
        { name: "Przeglądarka", color: "#0F7F8C", icon: "globe", running: true },
        { name: "Poczta", color: "#C8551F", icon: "mail" },
        { name: "Dokumenty", color: "#5B45D6", icon: "doc", running: true },
        { name: "Arkusze", color: "#1F7A4D", icon: "sheet" },
        { name: "Zdjęcia", color: "#B83A6F", icon: "image" },
        { name: "Muzyka", color: "#A63D2A", icon: "music" },
        { name: "Kalendarz", color: "#C8551F", icon: "calendar" },
        { name: "Notatki", color: "#9A6B00", icon: "note" },
        { name: "Sklep", color: "#1F7A4D", icon: "bag" },
        { name: "Ustawienia", color: "#535A68", icon: "sliders" }
    ]
    // Aplikacje zainstalowane ze Sklepu dochodzą do doku i do Startu
    property var installedApps: []
    property var runningExtra: ({})
    readonly property var taskbarApps: apps.filter(a => ["Pliki", "Przeglądarka", "Poczta", "Dokumenty", "Zdjęcia", "Muzyka", "Sklep", "Ustawienia"].indexOf(a.name) >= 0)
        .concat(installedApps.map(a => ({ name: a.name, color: a.color, icon: a.icon })))

    FileStore { id: store }
    readonly property var files: store.flat

    property point filesTarget: Qt.point(560, height)
    property point settingsTarget: Qt.point(760, height)
    property point storeTarget: Qt.point(700, height)
    function updateTargets() { filesTarget = taskbar.appCenter("Pliki"); settingsTarget = taskbar.appCenter("Ustawienia"); storeTarget = taskbar.appCenter("Sklep"); }
    function openStore() { storeOpen = true; front = "store"; panel = ""; }
    function openSettings() { settingsOpen = true; front = "settings"; panel = ""; }
    onWidthChanged: Qt.callLater(updateTargets)
    Component.onCompleted: Qt.callLater(updateTargets)

    function togglePanel(name) { panel = panel === name ? "" : name }

    // Płynne przejście jasny ↔ ciemny: zrzut starego wyglądu i jego wygaszenie
    // Zmiana motywu: nowy wygląd rozlewa się kołem od miejsca kliknięcia
    function toggleDark(px, py) {
        if (reveal.running) return;
        const cx = px === undefined ? root.width / 2 : px;
        const cy = py === undefined ? root.height / 2 : py;
        root.contentItem.grabToImage(function (res) {
            snapshot.source = res.url;
            hole.cx = cx;
            hole.cy = cy;
            hole.r = 0;
            revealLayer.visible = true;
            root.dark = !root.dark;
            reveal.to = Math.hypot(Math.max(cx, root.width - cx), Math.max(cy, root.height - cy)) + 40;
            reveal.restart();
        });
    }

    function launch(name) {
        if (name === "Pliki") { filesOpen = true; front = "files"; }
        if (name === "Ustawienia") openSettings();
        if (name === "Sklep") openStore();
    }

    // Wszystko, co leży pod panelami — to jest rozmywane za szkłem
    Item {
        id: scene
        anchors.fill: parent

        Wallpaper {
            id: wallpaper
            anchors.fill: parent
            dark: root.dark
            variant: root.wallpaperVariant
        }

        DesktopClock {
            visible: root.showDesktopClock
            x: 56
            y: 70
            dark: root.dark
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.panel = ""
        }

        FilesWindow {
            t: root.t
            id: filesWindow
            z: root.front === "files" ? 2 : 1
            onActivated: root.front = "files"
            minimizeTarget: root.filesTarget
            backdrop: wallpaper
            store: store
            open: root.filesOpen
            maxGeometry: Qt.rect(0, 0, root.width, root.height - 84)
            normalGeometry: Qt.rect(Math.max(20, (root.width - 1040) / 2) + 60, 64, 1040, Math.min(620, root.height - 84 - 78))
            onCloseRequested: root.filesOpen = false
            onMinimizeRequested: root.filesOpen = false
        }

        SettingsWindow {
            id: settingsWindow
            z: root.front === "settings" ? 2 : 1
            t: root.t
            sys: root
            backdrop: wallpaper
            open: root.settingsOpen
            minimizeTarget: root.settingsTarget
            normalGeometry: Qt.rect(Math.max(20, (root.width - 900) / 2) - 40, 80, 900, Math.min(600, root.height - 84 - 100))
            maxGeometry: Qt.rect(0, 0, root.width, root.height - 84)
            onActivated: root.front = "settings"
            onCloseRequested: root.settingsOpen = false
            onMinimizeRequested: root.settingsOpen = false
        }

        StoreWindow {
            id: storeWindow
            z: root.front === "store" ? 2 : 1
            t: root.t
            sys: root
            backdrop: wallpaper
            open: root.storeOpen
            minimizeTarget: root.storeTarget
            normalGeometry: Qt.rect(Math.max(20, (root.width - 1080) / 2), 66, 1080, Math.min(680, root.height - 84 - 82))
            maxGeometry: Qt.rect(0, 0, root.width, root.height - 84)
            onActivated: root.front = "store"
            onCloseRequested: root.storeOpen = false
            onMinimizeRequested: root.storeOpen = false
            onInstalled: (a) => {
                if (root.installedApps.some(x => x.name === a.name)) return;
                taskbar.lastAdded = a.name;
                root.installedApps = root.installedApps.concat([a]);
                horizon.notify("check", "#22A06B", "Zainstalowano: " + a.name);
            }
            onLaunched: (a) => {
                const r = Object.assign({}, root.runningExtra);
                r[a.name] = true;
                root.runningExtra = r;
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.panel !== ""
        onClicked: root.panel = ""
    }

    StartMenu {
        objectName: "startMenu"
        t: root.t
        backdrop: scene
        apps: root.apps.concat(root.installedApps.map(a => ({ name: a.name, color: a.color, icon: a.icon })))
        files: root.files
        open: root.panel === "start"
        x: 14
        height: Math.min(640, root.height - 84 - 6 - 24)
        y: root.height - 84 - 6 - height
        onLaunch: (name) => root.launch(name)
        onOpenFile: (id) => { root.filesOpen = true; root.front = "files"; filesWindow.reveal(id); }
        onLockRequested: { root.panel = ""; root.locked = true; }
        onCloseRequested: root.panel = ""
    }

    ControlCenter {
        t: root.t
        backdrop: scene
        dark: root.dark
        volume: root.volume
        output: root.output
        onVolumeMoved: (v) => root.volume = v
        open: root.panel === "control"
        x: root.width - width - 14
        y: root.height - 84 - 6 - height
        onDarkClicked: (at) => root.toggleDark(at.x, at.y)
        onSettingsRequested: root.openSettings()
    }

    AssistantPanel {
        objectName: "assistant"
        t: root.t
        backdrop: scene
        dark: root.dark
        volume: root.volume
        output: root.output
        files: root.files
        open: root.panel === "assistant"
        x: Math.round((root.width - width) / 2)
        y: Math.max(20, Math.round((root.height - 84 - height) / 2) - 20)
        onSetDark: (on) => { if (on !== root.dark) root.toggleDark() }
        onSetOutput: (name) => root.output = name
        onSetVolume: (v) => root.volume = v
        onOpenFiles: root.filesOpen = true
        onCloseRequested: root.panel = ""
    }

    readonly property bool anyMaximized: (root.filesOpen && filesWindow.maximized)
        || (root.settingsOpen && settingsWindow.maximized) || (root.storeOpen && storeWindow.maximized)
    // Uchwyt: cienka kreska u góry podpowiada, gdzie schowała się wyspa
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 5; z: 5
        width: 46; height: 5; radius: 2.5
        color: root.dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.75)
        opacity: horizon.hideP * (topHot.hovered ? 0 : 1)
        visible: opacity > 0.01 && !root.locked && !root.anyMaximized
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
    // Strefa u góry: dotknięcie kursorem wysuwa wyspę (kliknięcia przechodzą dalej)
    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0; z: 6
        width: 520; height: 14
        HoverHandler { id: topHot }
    }

    Horizon {
        id: horizon
        t: root.t
        backdrop: scene
        dark: root.dark
        open: root.panel === "today"
        peek: topHot.hovered
        anchors.horizontalCenter: parent.horizontalCenter
        y: 10
        z: 5
        onToggle: root.togglePanel("today")
    }

    // Przykładowe powiadomienia, żeby było widać, jak wyspa sama się wysuwa
    property int demoNote: 0
    readonly property var demoNotes: [
        { icon: "mail", color: "#F2753A", text: "Ania: „Wysłałam poprawioną ofertę”" },
        { icon: "calendar", color: "#F2B33D", text: "Za 15 min: spotkanie z zespołem" },
        { icon: "download", color: "#22A06B", text: "Pobrano: raport-q4.pdf" },
        { icon: "battery", color: "#5B7CFF", text: "Bateria naładowana · 100%" }
    ]
    Timer {
        interval: root.demoNote === 0 ? 5000 : 26000
        repeat: true
        running: !root.locked
        onTriggered: {
            const n = root.demoNotes[root.demoNote % root.demoNotes.length];
            horizon.notify(n.icon, n.color, n.text);
            root.demoNote++;
        }
    }

    Taskbar {
        id: taskbar
        anchors.left: parent.left
        anchors.right: parent.right
        y: root.height - height
        t: root.t
        apps: root.taskbarApps
        backdrop: scene
        panel: root.panel
        filesOpen: root.filesOpen
        dark: root.dark
        onStartClicked: root.togglePanel("start")
        onTrayClicked: root.togglePanel("control")
        onDarkClicked: (at) => root.toggleDark(at.x, at.y)
        onAssistantClicked: root.togglePanel("assistant")
        recent: store.flat.slice(0, 3)
        onOpenFile: (id) => { root.panel = ""; root.filesOpen = true; filesWindow.reveal(id); }
        openApps: Object.assign({ "Pliki": root.filesOpen, "Ustawienia": root.settingsOpen, "Sklep": root.storeOpen }, root.runningExtra)
        onAppClicked: (name) => {
            if (name === "Pliki") { root.filesOpen = !(root.filesOpen && root.front === "files"); if (root.filesOpen) root.front = "files"; }
            else if (name === "Ustawienia") { root.settingsOpen = !(root.settingsOpen && root.front === "settings"); if (root.settingsOpen) root.front = "settings"; }
            else if (name === "Sklep") { root.storeOpen = !(root.storeOpen && root.front === "store"); if (root.storeOpen) root.front = "store"; }
            root.panel = "";
        }
    }

    LockScreen {
        z: 900
        t: root.t
        dark: root.dark
        variant: root.wallpaperVariant
        locked: root.locked
        onUnlockRequested: root.locked = false
    }

    // Stary wygląd na wierzchu, z rosnącą „dziurą” w kształcie koła
    Item {
        id: revealLayer
        anchors.fill: parent
        visible: false
        z: 1000
        Image { id: snapshot; anchors.fill: parent; visible: false }
        Item {
            id: holeMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Rectangle {
                id: hole
                property real cx: 0
                property real cy: 0
                property real r: 0
                x: cx - r; y: cy - r
                width: r * 2; height: r * 2; radius: r
                color: "black"
            }
        }
        MultiEffect {
            anchors.fill: parent
            source: snapshot
            maskEnabled: true
            maskInverted: true
            maskSource: holeMask
            maskThresholdMin: 0.4
            maskSpreadAtMin: 0.25
        }
        NumberAnimation {
            id: reveal
            target: hole
            property: "r"
            from: 0
            duration: 340
            easing.type: Easing.OutCubic
            onFinished: revealLayer.visible = false
        }
    }

    Shortcut { sequence: "Alt+Space"; context: Qt.ApplicationShortcut; onActivated: root.togglePanel("start") }
    Shortcut { sequence: "Alt+A"; context: Qt.ApplicationShortcut; onActivated: root.togglePanel("assistant") }
    Shortcut { sequence: "Esc"; context: Qt.ApplicationShortcut; enabled: root.panel !== ""; onActivated: root.panel = "" }
    Shortcut { sequence: "Ctrl+L"; context: Qt.ApplicationShortcut; onActivated: { root.panel = ""; root.locked = true; } }
    Shortcut { sequence: "Ctrl+,"; context: Qt.ApplicationShortcut; onActivated: root.openSettings() }
    Shortcut { sequence: "Ctrl+D"; context: Qt.ApplicationShortcut; onActivated: root.toggleDark() }
}
