import QtQuick
import Aster.Ui

// Wiersz ustawienia: plakietka albo ikona, tytuł i opis, po prawej kontrolka (przełącznik, przycisk, wartość)
// i opcjonalna strzałka. Linię oddzielającą rysuje każdy wiersz poza pierwszym.
Item {
    id: row
    property string title
    property string subtitle
    property string icon
    property var colors: []
    property bool chevron: false
    property bool clickable: chevron
    property string value                 // tekst po prawej (np. „Połączono”)
    property color titleColor: Theme.text
    default property alias trailing: right.data
    signal clicked()

    width: parent ? parent.width : 0
    height: subtitle !== "" ? 58 : 46

    readonly property bool first: {
        const c = parent ? parent.children : [];
        for (let i = 0; i < c.length; ++i)
            if (c[i].visible && c[i].height > 0) return c[i] === row;
        return true;
    }
    readonly property real textX: colors.length ? 52 : (icon !== "" ? 46 : 16)

    Rectangle {
        visible: !row.first
        x: row.textX; width: parent.width - x; height: 1
        color: Theme.line
    }
    Rectangle {
        anchors.fill: parent; anchors.margins: 3
        radius: 10
        color: Theme.hover
        opacity: row.clickable && area.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 100 } }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        enabled: row.clickable
        hoverEnabled: true
        cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: row.clicked()
    }
    Badge {
        visible: row.colors.length > 0
        x: 14; anchors.verticalCenter: parent.verticalCenter
        icon: row.icon
        colors: row.colors.length ? row.colors : ["#000", "#000"]
    }
    Icon {
        visible: row.colors.length === 0 && row.icon !== ""
        x: 16; anchors.verticalCenter: parent.verticalCenter
        d: Icons[row.icon] || ""; size: 18
        color: Theme.text2
    }
    Column {
        x: row.textX
        anchors.verticalCenter: parent.verticalCenter
        width: right.x - x - 12
        spacing: 1
        Text {
            width: parent.width
            text: row.title
            elide: Text.ElideRight
            color: row.titleColor
            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
        }
        Text {
            visible: row.subtitle !== ""
            width: parent.width
            text: row.subtitle
            elide: Text.ElideRight
            color: Theme.text2
            font.family: Theme.font; font.pixelSize: 12
        }
    }
    Row {
        id: right
        anchors.right: chev.visible ? chev.left : parent.right
        anchors.rightMargin: chev.visible ? 6 : 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10
        Text {
            visible: row.value !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: row.value
            color: Theme.text2
            font.family: Theme.font; font.pixelSize: 13
        }
    }
    Icon {
        id: chev
        visible: row.chevron
        anchors.right: parent.right; anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        d: Icons.chevronRight; size: 15; stroke: 2
        color: Theme.text2
    }
}
