import QtQuick
import Aster.Ui

// Karta z tytułem (opcjonalnym) i treścią w kolumnie
Rectangle {
    id: card
    property string title
    property string subtitle
    default property alias content: col.data
    property alias spacing: col.spacing
    width: parent ? parent.width : 0
    readonly property real naturalHeight: col.y + col.implicitHeight + 18
    height: naturalHeight
    radius: 10
    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(1, 1, 1, 0.9)
    border.width: 1; border.color: Theme.line
    Column {
        id: head
        visible: card.title !== ""
        x: 20; y: 16; width: parent.width - 40
        spacing: 3
        Text { text: card.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
        Text { visible: card.subtitle !== ""; width: parent.width; wrapMode: Text.Wrap; text: card.subtitle; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
    }
    Column {
        id: col
        x: 20; y: card.title !== "" ? head.y + head.height + 12 : 18
        width: parent.width - 40
        spacing: 10
    }
}
