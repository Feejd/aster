pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Aster.Ui

// Lista wyboru w wierszu ustawienia: pigułka z bieżącą wartością, po kliknięciu wysuwa się lista
// nad całym oknem (przewijana, przy wielu pozycjach — z wyszukiwaniem).
// model: [{ label, value, detail? }]
Rectangle {
    id: dd
    property var model: []
    property var value
    property string placeholder: "Wybierz"
    property real maxWidth: 260
    signal picked(var value)

    readonly property var current: model.find(o => o.value === value)
    width: Math.min(maxWidth, label.implicitWidth + 44)
    height: 30; radius: 15
    color: area.containsMouse ? Theme.hover : Theme.fill
    Behavior on color { ColorAnimation { duration: 100 } }
    Text {
        id: label
        x: 14; width: parent.width - 40
        anchors.verticalCenter: parent.verticalCenter
        text: dd.current ? dd.current.label : dd.placeholder
        elide: Text.ElideRight
        color: Theme.text; font.family: Theme.font; font.pixelSize: 13
    }
    Icon { anchors.right: parent.right; anchors.rightMargin: 11; anchors.verticalCenter: parent.verticalCenter; d: Icons.chevronDown; size: 13; stroke: 2; color: Theme.text2 }
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: dd.open() }

    function open() {
        const root = Window.window ? Window.window.contentItem : null;
        if (!root) return;
        const p = dd.mapToItem(root, 0, dd.height + 6);
        popup.createObject(root, { at: p, minWidth: dd.width });
    }

    Component {
        id: popup
        Item {
            id: pop
            property point at
            property real minWidth
            anchors.fill: parent
            z: 1000
            readonly property var items: search.text ? dd.model.filter(o => (o.label + " " + (o.detail || "")).toLowerCase().indexOf(search.text.toLowerCase()) >= 0) : dd.model
            readonly property bool searchable: dd.model.length > 12
            function close() { pop.destroy(); }
            MouseArea { anchors.fill: parent; onPressed: pop.close(); onWheel: {} }
            RectangularShadow { anchors.fill: box; radius: box.radius; blur: 30; offset.y: 10; color: Theme.shadow }
            Rectangle {
                id: box
                width: Math.max(pop.minWidth, 240)
                height: Math.min(col.implicitHeight + 12, pop.height - y - 16)
                x: Math.max(8, Math.min(pop.at.x + pop.minWidth - width, pop.width - width - 8))
                y: Math.min(pop.at.y, pop.height - Math.min(col.implicitHeight + 12, 380) - 16)
                radius: 14
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                clip: true
                MouseArea { anchors.fill: parent }
                Flickable {
                    id: flick
                    anchors.fill: parent; anchors.margins: 6
                    contentHeight: col.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    Column {
                        id: col
                        width: flick.width
                        Rectangle {
                            visible: pop.searchable
                            width: parent.width; height: 34; radius: 10
                            color: Theme.fill
                            Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 14; color: Theme.text2 }
                            TextInput {
                                id: search
                                x: 32; width: parent.width - 42
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                                clip: true
                                focus: pop.searchable
                                Component.onCompleted: if (pop.searchable) forceActiveFocus()
                                Keys.onEscapePressed: pop.close()
                                Text { visible: !search.text; text: "Szukaj"; color: Theme.text2; font: search.font }
                            }
                        }
                        Item { width: 1; height: pop.searchable ? 4 : 0 }
                        Repeater {
                            model: pop.items
                            delegate: Rectangle {
                                id: opt
                                required property var modelData
                                readonly property bool chosen: modelData.value === dd.value
                                width: col.width; height: modelData.detail ? 44 : 34
                                radius: 8
                                color: optArea.containsMouse ? Theme.accent : "transparent"
                                Icon {
                                    x: 9; anchors.verticalCenter: parent.verticalCenter
                                    visible: opt.chosen
                                    d: Icons.check; size: 14; stroke: 2.2
                                    color: optArea.containsMouse ? "white" : Theme.accentText
                                }
                                Column {
                                    x: 30; width: parent.width - 40
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text { width: parent.width; text: opt.modelData.label; elide: Text.ElideRight; color: optArea.containsMouse ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                                    Text { visible: !!opt.modelData.detail; width: parent.width; text: opt.modelData.detail || ""; elide: Text.ElideRight; color: optArea.containsMouse ? Qt.rgba(1, 1, 1, 0.8) : Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
                                }
                                MouseArea {
                                    id: optArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: { dd.picked(opt.modelData.value); pop.close(); }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
