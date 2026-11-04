import QtQuick
import QtQuick.Effects
import Aster.Ui

// Okienko nad oknem programu (przyciemnione tło, karta na środku). Zawartość — w `content`.
Item {
    id: sheet
    property bool shown: false
    property real cardWidth: 460
    property real radius: 24
    property string title
    property string subtitle
    default property alias content: col.data
    signal dismissed()

    anchors.fill: parent
    visible: shown
    z: 200
    Rectangle { anchors.fill: parent; radius: sheet.radius; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.25) }
    MouseArea { anchors.fill: parent; onClicked: sheet.dismissed() }
    RectangularShadow { anchors.fill: card; radius: card.radius; blur: 40; offset.y: 14; color: Theme.shadow }
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(sheet.cardWidth, sheet.width - 40)
        height: Math.min(col.implicitHeight + head.implicitHeight + 50, sheet.height - 40)
        radius: 22
        color: Theme.surface
        border.width: 1; border.color: Theme.edge
        clip: true
        MouseArea { anchors.fill: parent }
        Column {
            id: head
            x: 24; y: 22; width: parent.width - 48
            spacing: 4
            Text { width: parent.width; wrapMode: Text.Wrap; text: sheet.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold }
            Text { visible: sheet.subtitle !== ""; width: parent.width; wrapMode: Text.Wrap; text: sheet.subtitle; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.15 }
        }
        Column {
            id: col
            x: 24; y: head.y + head.implicitHeight + 16
            width: parent.width - 48
            spacing: 12
        }
    }
}
