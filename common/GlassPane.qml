import QtQuick

// Panel treści w oknie Aster: pasek boczny leży na ledwie przezroczystym szkle okna,
// a treść — na tym panelu w głębokim, nieprzezroczystym kolorze (w ciemnym motywie
// niemal czerń). Panel dochodzi do krawędzi okna; zaokrąglone są tylko rogi, które się z nimi stykają.
Item {
    id: gp
    property real topLeftRadius: 0
    property real topRightRadius: 0
    property real bottomLeftRadius: 0
    property real bottomRightRadius: 0
    property bool leftLine: true           // cienka linia oddzielająca od paska bocznego
    default property alias content: body.data

    Rectangle {
        anchors.fill: parent
        topLeftRadius: gp.topLeftRadius; topRightRadius: gp.topRightRadius
        bottomLeftRadius: gp.bottomLeftRadius; bottomRightRadius: gp.bottomRightRadius
        color: Theme.paneGlass
    }
    Rectangle {
        visible: gp.leftLine
        width: 1; height: parent.height
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.07)
    }
    Item { id: body; anchors.fill: parent; clip: true }
}
