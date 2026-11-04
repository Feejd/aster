import QtQuick
import Aster.Ui
import Aster.Store

// Wiersz katalogu: ikona, nazwa, nasz opis (albo podana notatka), przycisk
Item {
    id: row
    property string ref
    property var hit: null              // program spoza katalogu: dane z wyszukiwania
    property string note: ""
    property string tag: ""             // np. rola w zestawie
    property bool separator: true
    height: 72

    readonly property var info: { Store.version; return hit || (ref ? Store.item(ref) : null); }
    readonly property string kind: Store.kindOf(ref)

    Rectangle {
        anchors.fill: parent
        anchors.margins: -2; anchors.leftMargin: -8; anchors.rightMargin: -8
        radius: 12
        color: hover.containsMouse ? Theme.hover : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }
    }
    MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Store.openApp(row.ref) }

    AppGlyph {
        id: icon
        anchors.verticalCenter: parent.verticalCenter
        ref: row.ref
        size: 48
    }
    Column {
        anchors.left: icon.right; anchors.leftMargin: 14
        anchors.right: get.left; anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Row {
            width: parent.width
            spacing: 8
            Txt {
                width: Math.min(implicitWidth, parent.width - (badge.visible ? badge.width + 8 : 0))
                text: row.info ? row.info.name : ""
                elide: Text.ElideRight
                font.pixelSize: 15; font.weight: Font.DemiBold
            }
            Txt {
                id: badge
                visible: text !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: row.tag || (row.kind === "web" ? "W przeglądarce" : row.kind === "aster" ? "Aster" : row.kind === "get" ? "Od producenta" : row.kind === "via" ? "Przez Lutris" : "")
                color: Theme.accentText
                font.pixelSize: 11; font.weight: Font.DemiBold
            }
        }
        Txt {
            width: parent.width
            text: row.note || (row.info ? row.info.summary : "")
            elide: Text.ElideRight
            color: Theme.text2
            font.pixelSize: 13
        }
    }
    GetButton {
        id: get
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        ref: row.ref
    }
    Rectangle {
        visible: row.separator
        anchors.bottom: parent.bottom
        anchors.left: parent.left; anchors.leftMargin: 62
        anchors.right: parent.right
        height: 1
        color: Theme.line
    }
}
