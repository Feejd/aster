import QtQuick
import Aster.Ui

// Grupa ustawień (jak w macOS): podpis nad kartą, wiersze rozdzielone cienką linią, opis pod spodem
Column {
    id: sec
    property string title
    property string footer
    default property alias rows: body.data
    property alias header: headerRow.data      // np. przycisk „Szukaj” obok tytułu
    width: parent ? parent.width : 0
    spacing: 7

    Item {
        width: parent.width
        height: sec.title !== "" ? 20 : 0
        visible: sec.title !== ""
        Text {
            x: 4; anchors.verticalCenter: parent.verticalCenter
            text: sec.title
            color: Theme.text2
            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
        }
        Row { id: headerRow; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8 }
    }
    Rectangle {
        width: parent.width
        height: body.height
        visible: body.height > 0
        radius: 22
        color: Theme.dark ? "#1C1D21" : "#FFFFFF"
        border.width: 0
        border.color: Theme.line
        Column { id: body; width: parent.width }
    }
    Text {
        visible: sec.footer !== ""
        width: parent.width
        leftPadding: 4; rightPadding: 4
        text: sec.footer
        wrapMode: Text.Wrap
        color: Theme.text2
        font.family: Theme.font; font.pixelSize: 12; font.letterSpacing: 0.05
        lineHeight: 1.15
    }
}
