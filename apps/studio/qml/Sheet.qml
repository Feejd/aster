import QtQuick
import QtQuick.Effects
import Aster.Ui

// Arkusz: okienko na środku okna nad przyciemnionym tłem (nowy projekt, eksport, ustawienia dźwięku).
// Esc albo kliknięcie obok zamyka (chyba że closable: false — np. w trakcie eksportu).
Item {
    id: sheet
    property string title
    property bool shown: false
    property bool closable: true
    property real cardWidth: 440
    property real radius: 0                  // zaokrąglenie przyciemnienia (rogi okna)
    default property alias content: body.data
    signal closed()

    anchors.fill: parent
    visible: shown || card.opacity > 0
    z: 400

    function open() { shown = true; forceActiveFocus(); }
    function close() { if (shown) { shown = false; closed(); } }

    Keys.onEscapePressed: if (closable) close()

    Rectangle {
        anchors.fill: parent
        radius: sheet.radius
        color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.25)
        opacity: sheet.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: if (sheet.closable) sheet.close(); onWheel: {} }
    }

    RectangularShadow {
        anchors.fill: card
        radius: card.radius; blur: 40; offset.y: 14
        color: Theme.shadow
        opacity: card.opacity
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(sheet.cardWidth, sheet.width - 40)
        height: body.childrenRect.height + 82
        radius: 18
        color: Theme.surface
        border.width: 1; border.color: Theme.edge
        opacity: sheet.shown ? 1 : 0
        scale: sheet.shown ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Text {
            x: 24; y: 22
            text: sheet.title
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold
        }
        HoverButton {
            visible: sheet.closable
            anchors.right: parent.right; anchors.rightMargin: 14
            y: 16
            width: 30; height: 30; radius: 15
            onClicked: sheet.close()
            Icon { anchors.centerIn: parent; d: Icons.close; size: 13; stroke: 2; color: Theme.text2 }
        }
        Item {
            id: body
            x: 24; y: 58
            width: parent.width - 48
            height: childrenRect.height
        }
    }
}
