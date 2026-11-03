pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Terminal na dole okna (Ctrl+`): powłoka w folderze projektu, ten sam silnik co Terminal Aster.
// Po wyjściu z powłoki (exit) panel się chowa; „+” uruchamia nową powłokę.
Item {
    id: tp
    property string dir
    property bool maximized: false
    property bool started: false          // powłoka startuje dopiero przy pierwszym pokazaniu panelu
    property bool reloading: false
    readonly property var term: loader.item
    signal hideRequested()
    signal maximizeRequested()

    function focusTerminal() { const t = loader.item as CodeTerminal; if (t) t.forceActiveFocus(); }
    function restart() {
        reloading = true;
        Qt.callLater(() => { tp.reloading = false; Qt.callLater(tp.focusTerminal); });
    }
    onVisibleChanged: if (visible) started = true
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
            x: 16; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.prompt; size: 14; stroke: 2; color: Theme.accentText }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "TERMINAL"; color: Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.5 }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: !tp.term ? "" : (tp.term.program ? tp.term.program + " · " : "") + Project.pretty(tp.term.currentDirectory || tp.dir)
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            PanelBtn { icon: "plus"; onClicked: tp.restart() }
            PanelBtn { icon: "trash"; onClicked: if (tp.term) tp.term.clear() }
            PanelBtn { icon: tp.maximized ? "exitFullscreen" : "fullscreen"; onClicked: tp.maximizeRequested() }
            PanelBtn { icon: "close"; onClicked: tp.hideRequested() }
        }
    }

    Loader {
        id: loader
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
        anchors.fill: loader
        z: -1
        color: tp.colors.bg
    }

    component PanelBtn: HoverButton {
        id: pb
        property string icon
        width: 28; height: 26; radius: 7
        Icon { anchors.centerIn: parent; d: Icons[pb.icon] || ""; size: 14; color: Theme.text2 }
    }
}
