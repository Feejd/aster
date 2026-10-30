pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Aster.Ui

// Menu podręczne. items: [{ label, icon, shortcut, action, enabled, danger }] albo { separator: true }
Item {
    id: menu
    property var items: []
    property bool shown: false
    signal triggered(string action)

    anchors.fill: parent
    visible: shown
    z: 500

    function openAt(px, py, list) {
        items = list;
        box.x = Math.min(px, width - box.width - 8);
        box.y = Math.min(py, height - box.implicitHeight - 8);
        shown = true;
    }
    function close() { shown = false }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: menu.close()
        onWheel: menu.close()
    }

    RectangularShadow {
        anchors.fill: box
        radius: 12; blur: 30; offset.y: 10
        color: Theme.shadow
    }

    Rectangle {
        id: box
        width: 250
        height: implicitHeight
        implicitHeight: col.implicitHeight + 12
        radius: 12
        color: Theme.surface
        border.width: 1
        border.color: Theme.edge
        scale: menu.shown ? 1 : 0.96
        opacity: menu.shown ? 1 : 0
        transformOrigin: Item.TopLeft
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        Behavior on opacity { NumberAnimation { duration: 90 } }

        Column {
            id: col
            x: 6; y: 6
            width: parent.width - 12
            Repeater {
                model: menu.items
                delegate: Loader {
                    id: entry
                    required property var modelData
                    width: col.width
                    sourceComponent: modelData.separator ? sep : row
                    Component {
                        id: sep
                        Item { height: 9; Rectangle { y: 4; width: parent.width; height: 1; color: Theme.line } }
                    }
                    Component {
                        id: row
                        Rectangle {
                            id: r
                            readonly property bool on: entry.modelData.enabled !== false
                            readonly property color fg: area.containsMouse && on ? "white" : (entry.modelData.danger ? Theme.danger : Theme.text)
                            height: 34
                            radius: 7
                            color: area.containsMouse && on ? (entry.modelData.danger ? "#D93B3B" : Theme.accent) : "transparent"
                            opacity: on ? 1 : 0.4
                            Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; visible: !!entry.modelData.icon; d: Icons[entry.modelData.icon] || ""; size: 16; color: r.fg }
                            Text { x: 36; anchors.verticalCenter: parent.verticalCenter; text: entry.modelData.label; color: r.fg; font.family: Theme.font; font.pixelSize: 13 }
                            Text { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: entry.modelData.shortcut || ""; color: area.containsMouse && r.on ? Qt.rgba(1, 1, 1, 0.8) : Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                            MouseArea {
                                id: area
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: if (r.on) { menu.close(); menu.triggered(entry.modelData.action); }
                            }
                        }
                    }
                }
            }
        }
    }
}
