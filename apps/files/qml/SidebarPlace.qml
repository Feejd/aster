import QtQuick
import Aster.Ui

// Miejsce w pasku bocznym; przyjmuje upuszczone pliki
Rectangle {
    id: pl
    property string label
    property string icon
    property string badge: ""
    property bool active: false
    signal clicked()
    signal dropped(var drop)

    height: 34
    radius: 8
    color: drop.containsDrag ? Theme.accentSoft : (active ? Theme.accentSoft : (area.containsMouse ? Theme.hover : "transparent"))
    border.width: drop.containsDrag ? 2 : 0
    border.color: Theme.accent
    Behavior on color { ColorAnimation { duration: 120 } }

    Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons[pl.icon] || ""; color: pl.active ? Theme.accentText : Theme.text }
    Text { x: 38; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 80; elide: Text.ElideRight; text: pl.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: pl.active ? Font.Medium : Font.Normal }
    Text { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: pl.badge; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }

    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; onClicked: pl.clicked() }
    DropArea { id: drop; anchors.fill: parent; keys: ["aster-files", "text/uri-list"]; onDropped: (d) => pl.dropped(d) }
}
