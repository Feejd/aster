import QtQuick
import QtQuick.Effects
import Aster.Ui

// Wyskakująca karta nad oknem (kolor, czcionka, eksport). Zamyka się po kliknięciu obok i klawiszem Esc.
Item {
    id: pop
    property bool shown: false
    property real cardWidth: 280
    property real cardHeight: content.childrenRect.height + 32
    default property alias content: content.data
    signal closed()

    anchors.fill: parent
    visible: shown || card.opacity > 0
    z: 400

    // Pokazuje kartę pod (albo obok) `item`, w granicach okna
    function openAt(item, side) {
        const p = item.mapToItem(pop, 0, 0);
        let x, y;
        if (side === "left") { x = p.x - cardWidth - 10; y = p.y - 10; }
        else if (side === "right") { x = p.x + item.width + 10; y = p.y - 10; }
        else { x = p.x + item.width - cardWidth; y = p.y + item.height + 8; }
        card.x = Math.max(10, Math.min(x, width - cardWidth - 10));
        card.y = Math.max(10, Math.min(y, height - cardHeight - 10));
        shown = true;
        card.forceActiveFocus();
    }
    function close() { if (shown) { shown = false; closed(); } }

    MouseArea {
        anchors.fill: parent
        enabled: pop.shown
        acceptedButtons: Qt.AllButtons
        onPressed: pop.close()
        onWheel: (e) => e.accepted = true
    }
    RectangularShadow {
        anchors.fill: card
        visible: GraphicsInfo.api !== GraphicsInfo.Software
        radius: card.radius; blur: 36; offset.y: 12
        color: Theme.shadow
        opacity: card.opacity
    }
    Rectangle {
        id: card
        width: pop.cardWidth
        height: pop.cardHeight
        radius: 12
        color: Theme.surface
        border.width: 1
        border.color: Theme.edge
        opacity: pop.shown ? 1 : 0
        scale: pop.shown ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: 110 } }
        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutQuad } }
        Keys.onEscapePressed: pop.close()
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (e) => e.accepted = false }
        Item {
            id: content
            x: 16; y: 16
            width: parent.width - 32
            height: parent.height - 32
        }
    }
}
