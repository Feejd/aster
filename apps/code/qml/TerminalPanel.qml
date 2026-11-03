pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Panel na dole okna: terminal (Ctrl+`) — powłoka w folderze projektu, ten sam silnik co Terminal Aster —
// problemy z serwerów języków i kompilatora (Ctrl+Shift+M), odwołania i wyjście zadania (Ctrl+Shift+B).
// Po wyjściu z powłoki (exit) panel się chowa; „+” uruchamia nową powłokę.
Item {
    id: tp
    property string dir
    property bool maximized: false
    property bool started: false          // powłoka startuje dopiero przy pierwszym pokazaniu panelu
    property bool reloading: false
    property int tab: 0                    // 0 terminal, 1 problemy, 2 odwołania, 3 zadanie
    property var refGroups: []
    property string refTitle
    signal openProblem(string path, int line, int col)
    signal openReference(string path, int line, int col, int length)
    signal openLocation(string path, int line, int col)
    readonly property var term: loader.item
    signal hideRequested()
    signal maximizeRequested()

    function focusTerminal() { const t = loader.item as CodeTerminal; if (t) t.forceActiveFocus(); }
    function restart() {
        reloading = true;
        Qt.callLater(() => { tp.reloading = false; Qt.callLater(tp.focusTerminal); });
    }
    onVisibleChanged: if (visible && tab === 0) started = true
    onTabChanged: if (visible && tab === 0) started = true
    onDirChanged: if (started) restart()

    readonly property var colors: Theme.dark
        ? { fg: "#E6E8EE", bg: "#090A0D", palette: ["#1C1E26", "#FF6B7A", "#7EE0A0", "#F5D07A", "#6EA8FF", "#C79BFF", "#67E1E6", "#C9CED8",
                                                     "#5C6370", "#FF8B96", "#9BF0B8", "#FFE09A", "#8DBBFF", "#D8B4FF", "#8EEBEE", "#F4F6FA"] }
        : { fg: "#1E2128", bg: "#FFFFFF", palette: ["#1E2128", "#D7263D", "#1A8F4C", "#A86A00", "#2459D6", "#8E3FD1", "#0B8796", "#8A909C",
                                                     "#5C6370", "#E5484D", "#22A35A", "#C27C00", "#3B6EF0", "#A855F7", "#0E9FB0", "#B5BAC4"] }

    Rectangle { width: parent.width; height: 1; color: Theme.line }

    Item {
        id: header
        y: 1; width: parent.width; height: 34
        Row {
            x: 10; anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            PanelTab { label: "TERMINAL"; icon: "prompt"; on: tp.tab === 0; onClicked: { tp.tab = 0; Qt.callLater(tp.focusTerminal); } }
            PanelTab {
                label: "PROBLEMY"; icon: "alertCircle"; on: tp.tab === 1
                badge: Lsp.errorCount + Lsp.warningCount + Tasks.errorCount + Tasks.warningCount
                onClicked: tp.tab = 1
            }
            PanelTab {
                visible: Tasks.lines.length > 0 || Tasks.running
                label: "ZADANIE"; icon: Tasks.running ? "reload" : "play"; on: tp.tab === 3
                onClicked: tp.tab = 3
            }
            PanelTab {
                visible: tp.refGroups.length > 0
                label: "ODWOŁANIA"; icon: "search"; on: tp.tab === 2
                onClicked: tp.tab = 2
            }
            Text {
                visible: tp.tab === 0
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 8
                text: !tp.term ? "" : (tp.term.program ? tp.term.program + " · " : "") + Project.pretty(tp.term.currentDirectory || tp.dir)
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                visible: tp.tab === 3 && !!Tasks.title
                anchors.verticalCenter: parent.verticalCenter
                rightPadding: 6
                text: Tasks.title
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
            PanelBtn { visible: tp.tab === 3 && Tasks.running; icon: "stop"; onClicked: Tasks.stop() }
            PanelBtn { visible: tp.tab === 3 && !Tasks.running && !!Tasks.title; icon: "reload"; onClicked: Tasks.rerun() }
            PanelBtn { visible: tp.tab === 3 && !Tasks.running; icon: "trash"; onClicked: Tasks.clear() }
            PanelBtn { visible: tp.tab === 0; icon: "plus"; onClicked: tp.restart() }
            PanelBtn { visible: tp.tab === 0; icon: "trash"; onClicked: if (tp.term) tp.term.clear() }
            PanelBtn { icon: tp.maximized ? "exitFullscreen" : "fullscreen"; onClicked: tp.maximizeRequested() }
            PanelBtn { icon: "close"; onClicked: tp.hideRequested() }
        }
    }

    TaskOutput {
        visible: tp.tab === 3
        anchors.fill: parent
        anchors.topMargin: header.height + 1
        onOpenLocation: (path, line, col) => tp.openLocation(path, line, col)
    }

    ReferencesView {
        visible: tp.tab === 2
        anchors.fill: parent
        anchors.topMargin: header.height + 1
        groups: tp.refGroups
        title: tp.refTitle
        onOpenReference: (path, line, col, length) => tp.openReference(path, line, col, length)
    }

    ProblemsView {
        visible: tp.tab === 1
        anchors.fill: parent
        anchors.topMargin: header.height + 1
        onOpenProblem: (path, line, col) => tp.openProblem(path, line, col)
    }

    Loader {
        id: loader
        visible: tp.tab === 0
        active: tp.started && !tp.reloading && tp.dir !== ""
        anchors.fill: parent
        anchors.topMargin: header.height + 1
        anchors.leftMargin: 16; anchors.rightMargin: 10; anchors.bottomMargin: 6
        sourceComponent: CodeTerminal {
            workingDirectory: tp.dir
            fontFamily: "JetBrains Mono"
            fontSize: 13
            lineHeight: 1.2
            foreground: tp.colors.fg
            background: tp.colors.bg
            colorPalette: tp.colors.palette
            cursorColor: Theme.dark ? Qt.lighter(Theme.accent, 1.35) : Theme.accent
            selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.dark ? 0.42 : 0.24)
            cursorStyle: 3
            cursorBlinking: true
            historyLimit: 10000
            // exit w powłoce — panel się chowa, przy następnym otwarciu czeka nowa powłoka
            onFinished: { tp.hideRequested(); tp.restart(); }
        }
    }
    Rectangle {
        visible: tp.tab === 0
        anchors.fill: loader
        z: -1
        color: tp.colors.bg
    }

    component PanelTab: HoverButton {
        id: ptab
        property string label
        property string icon
        property bool on: false
        property int badge: 0
        width: ptabRow.implicitWidth + 16; height: 26; radius: 7
        baseColor: on ? Theme.fill : "transparent"
        Row {
            id: ptabRow
            anchors.centerIn: parent
            spacing: 6
            Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons[ptab.icon] || ""; size: 13; stroke: 2; color: ptab.on ? Theme.accentText : Theme.text2 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: ptab.label; color: ptab.on ? Theme.text : Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.5 }
            Rectangle {
                visible: ptab.badge > 0
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(16, bt.implicitWidth + 8); height: 16; radius: 8
                color: Theme.fill
                Text { id: bt; anchors.centerIn: parent; text: ptab.badge; color: Theme.text2; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold }
            }
        }
    }
    component PanelBtn: HoverButton {
        id: pb
        property string icon
        width: 28; height: 26; radius: 7
        Icon { anchors.centerIn: parent; d: Icons[pb.icon] || ""; size: 14; color: Theme.text2 }
    }
}
