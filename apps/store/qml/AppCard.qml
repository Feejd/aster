import QtQuick
import Aster.Ui
import Aster.Store

// Kafelek znanego programu na stronie głównej: ikona, nazwa, jedno słowo o tym, czym jest
Rectangle {
    id: card
    property string ref
    readonly property var info: { Store.version; return ref ? Store.item(ref) : null; }
    height: 148
    radius: 12
    color: area.containsMouse ? Theme.hover : Theme.fill
    Behavior on color { ColorAnimation { duration: 100 } }
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Store.openApp(card.ref) }
    AppGlyph {
        x: 14; y: 14
        ref: card.ref
        size: 48
    }
    Column {
        x: 14; y: 72
        width: parent.width - 28
        spacing: 1
        Txt { width: parent.width; text: card.info ? card.info.name : ""; elide: Text.ElideRight; font.pixelSize: 14; font.weight: Font.DemiBold }
        Txt {
            width: parent.width
            text: card.info ? card.info.summary : ""
            wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
            color: Theme.text2; font.pixelSize: 12
        }
    }
}
