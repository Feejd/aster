import QtQuick
import Aster.Ui
import Aster.Store

// Wiersz aplikacji (listy, ranking, wyniki): ikona, nazwa, opis, przycisk
Item {
    id: row
    property var app                    // {id, name, summary, icon}
    property string rank: ""
    property string note: ""            // np. „zamiast Photoshopa”
    property bool separator: true
    signal opened(string appId)
    height: 76

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: 14
        color: hover.containsMouse ? Theme.hover : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
    }
    MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; onClicked: row.opened(row.app.id) }

    Text {
        id: rankText
        visible: row.rank !== ""
        width: visible ? 26 : 0
        anchors.verticalCenter: parent.verticalCenter
        text: row.rank
        color: Theme.text
        font.family: Theme.font; font.pixelSize: 17; font.letterSpacing: -0.2; font.weight: Font.Bold
    }
    Image {
        id: icon
        anchors.left: rankText.right; anchors.leftMargin: row.rank ? 6 : 0
        anchors.verticalCenter: parent.verticalCenter
        width: 56; height: 56
        source: row.app ? row.app.icon : ""
        sourceSize: Qt.size(112, 112)
        asynchronous: true
        smooth: true; mipmap: true
        Rectangle {
            anchors.fill: parent; radius: 14
            visible: parent.status !== Image.Ready
            color: Theme.fill
        }
    }
    Column {
        anchors.left: icon.right; anchors.leftMargin: 14
        anchors.right: get.left; anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text { width: parent.width; text: row.app ? row.app.name : ""; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
        Text { width: parent.width; text: row.note ? row.note : (row.app ? row.app.summary : ""); elide: Text.ElideRight; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
    }
    GetButton {
        id: get
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        appId: row.app ? row.app.id : ""
    }
    Rectangle {
        visible: row.separator
        anchors.bottom: parent.bottom
        anchors.left: icon.left; anchors.leftMargin: 70
        anchors.right: parent.right
        height: 1
        color: Theme.line
    }
}
