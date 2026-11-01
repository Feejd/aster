import QtQuick
import Aster.Ui

// Nagłówek strony wewnętrznej: duży tytuł po lewej, przyciski i pole szukania po prawej
Item {
    id: ph
    property string title
    default property alias actions: actionRow.data
    width: parent ? parent.width : 0
    height: 92

    Item {
        width: Math.min(860, ph.width - 64)
        height: parent.height
        x: (ph.width - width) / 2
        Text {
            x: 4; anchors.verticalCenter: parent.verticalCenter
            text: ph.title
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 28; font.weight: Font.DemiBold; font.letterSpacing: -0.7
        }
        Row {
            id: actionRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
        }
    }
}
