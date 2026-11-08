import QtQuick
import Aster.Ui

// Miejsce w pasku bocznym; przyjmuje upuszczone pliki
Rectangle {
    id: pl
    property string label
    property string icon
    property string badge: ""
    property bool active: false
    property bool ejectable: false             // przycisk „Wysuń” po prawej (pendrive)
    signal clicked()
    signal rightClicked(real x, real y)
    signal ejectClicked()
    signal dropped(var drop)

    height: 42
    radius: 21
    color: drop.containsDrag ? Theme.accentSoft : (active ? Theme.accent : (area.containsMouse ? Theme.hover : "transparent"))
    border.width: drop.containsDrag ? 2 : 0
    border.color: Theme.accent
    Behavior on color { ColorAnimation { duration: 120 } }

    Icon { x: 15; anchors.verticalCenter: parent.verticalCenter; d: Icons[pl.icon] || ""; size: 18; color: pl.active && !drop.containsDrag ? "white" : Theme.text }
    Text { x: 44; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 86; elide: Text.ElideRight; text: pl.label; color: pl.active && !drop.containsDrag ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: pl.active ? Font.DemiBold : Font.Normal }
    Text { anchors.right: parent.right; anchors.rightMargin: pl.ejectable ? 38 : 16; anchors.verticalCenter: parent.verticalCenter; text: pl.badge; color: pl.active ? Qt.rgba(1, 1, 1, 0.8) : Theme.text2; font.family: Theme.font; font.pixelSize: 12 }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (e) => { if (e.button === Qt.RightButton) pl.rightClicked(e.x, e.y); else pl.clicked(); }
    }
    HoverButton {
        visible: pl.ejectable
        anchors.right: parent.right; anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 30; height: 30; radius: 15
        onClicked: pl.ejectClicked()
        Icon { anchors.centerIn: parent; d: Icons.eject; size: 15; color: pl.active ? "white" : Theme.text2 }
    }
    DropArea { id: drop; anchors.fill: parent; keys: ["aster-files", "text/uri-list"]; onDropped: (d) => pl.dropped(d) }
}
