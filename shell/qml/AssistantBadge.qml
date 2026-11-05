import QtQuick
import Aster.Ui

// Znaczek przy odpowiedzi asystenta: kto odpowiedział.
// „Na tym komputerze” (zielony, procesor) albo „Chmura: <dostawca>” / „Serwer: <adres>” (niebieski, glob).
// onDark: na czarnej wyspie; inaczej w kolorach motywu (panel).
Rectangle {
    id: b
    property string text
    property bool onDark: true
    readonly property bool local: text.indexOf("Na tym komputerze") === 0
    readonly property color tint: local ? "#34C759" : "#5AA9FF"
    visible: text !== ""
    width: row.implicitWidth + 16
    height: 22
    radius: 11
    color: Qt.rgba(tint.r, tint.g, tint.b, onDark ? 0.16 : (Theme.dark ? 0.18 : 0.12))
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            d: b.local ? Icons.cpu : Icons.globe
            size: 12; stroke: 2
            color: b.onDark ? Qt.lighter(b.tint, 1.25) : (Theme.dark ? Qt.lighter(b.tint, 1.2) : Qt.darker(b.tint, 1.35))
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: b.text
            color: b.onDark ? Qt.rgba(1, 1, 1, 0.82) : (Theme.dark ? Qt.lighter(b.tint, 1.3) : Qt.darker(b.tint, 1.6))
            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium
        }
    }
}
