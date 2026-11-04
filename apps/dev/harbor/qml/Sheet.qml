import QtQuick
import QtQuick.Effects
import Aster.Ui

// Okno w oknie: przyciemnione tło i karta pośrodku. Treść układa się w kolumnie (szerokość karty − marginesy).
Item {
    id: sheet
    property bool shown: false
    property real cardWidth: 520
    property real radius: 24
    property bool dismissable: true
    default property alias content: col.data
    signal dismissed()

    anchors.fill: parent
    z: 150
    visible: opacity > 0.01
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 140 } }

    Rectangle { anchors.fill: parent; radius: sheet.radius; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.25) }
    MouseArea { anchors.fill: parent; onClicked: if (sheet.dismissable) sheet.dismissed() }
    RectangularShadow { anchors.fill: card; radius: card.radius; blur: 40; offset.y: 14; color: Theme.shadow }
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(sheet.cardWidth, sheet.width - 40)
        height: Math.min(col.implicitHeight + 46, sheet.height - 40)
        radius: 22
        color: Theme.surface
        border.width: 1; border.color: Theme.edge
        scale: sheet.shown ? 1 : 0.97
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
        clip: true
        MouseArea { anchors.fill: parent }
        Column {
            id: col
            x: 24; y: 22
            width: parent.width - 48
            spacing: 0
        }
    }
}
