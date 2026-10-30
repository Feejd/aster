import QtQuick
import "Icons.js" as I

// Miejsce w pasku bocznym Plików; przyjmuje upuszczone pliki
Rectangle {
    id: pl
    property var t
    property string label
    property string icon
    property string badge: ""
    property bool active: false
    signal clicked()
    signal dropped()

    height: 34
    radius: 8
    color: drop.containsDrag ? Qt.rgba(52 / 255, 86 / 255, 232 / 255, 0.3) : (active ? t.accentSoft : (area.containsMouse ? t.hover : "transparent"))
    border.width: drop.containsDrag ? 2 : 0
    border.color: t.accent

    Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: I[pl.icon]; color: pl.active ? pl.t.accentText : pl.t.text }
    Text { x: 38; anchors.verticalCenter: parent.verticalCenter; text: pl.label; color: pl.t.text; font.pixelSize: 13; font.weight: pl.active ? Font.Medium : Font.Normal }
    Text { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: pl.badge; color: pl.t.text2; font.pixelSize: 12 }

    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; onClicked: pl.clicked() }
    DropArea { id: drop; anchors.fill: parent; keys: ["aster-files"]; onDropped: pl.dropped() }
}
