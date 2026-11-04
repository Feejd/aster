import QtQuick
import Aster.Ui
import Aster.Store

// Ikona pozycji katalogu, niezależnie od źródła: obrazek programu, kafel Aster albo kafel aplikacji webowej
Item {
    id: g
    property string ref
    property real size: 44
    width: size
    height: size
    readonly property var info: { Store.version; return ref ? Store.item(ref) : null; }
    readonly property string kind: Store.kindOf(ref)

    Image {
        anchors.fill: parent
        visible: g.kind === "app"
        source: visible && g.info ? g.info.icon : ""
        sourceSize: Qt.size(g.size * 2, g.size * 2)
        asynchronous: true
        smooth: true; mipmap: g.size < 64
        Rectangle { anchors.fill: parent; radius: g.size / 4; visible: parent.status !== Image.Ready; color: Theme.fill }
    }
    Loader {
        active: g.kind === "aster"
        sourceComponent: AppIcon { desktopId: g.info ? g.info.id : ""; source: g.info ? g.info.id : ""; size: g.size }
    }
    Rectangle {
        anchors.fill: parent
        visible: g.kind === "web"
        radius: g.size * 0.26
        color: g.info && g.info.color ? g.info.color : Theme.accent
        Txt {
            anchors.centerIn: parent
            text: g.info ? g.info.name.charAt(0) : ""
            color: "white"
            font.pixelSize: g.size * 0.5; font.weight: Font.Bold
        }
    }
}
