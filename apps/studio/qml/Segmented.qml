pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui

// Przełącznik kilku wartości: model [{ label, value }]
Rectangle {
    id: seg
    property var model: []
    property var value
    signal picked(var value)
    height: 34; radius: 10
    color: Theme.fill
    implicitWidth: row.implicitWidth + 6
    Row {
        id: row
        x: 3; y: 3
        spacing: 2
        Repeater {
            model: seg.model
            delegate: Rectangle {
                id: opt
                required property var modelData
                readonly property bool on: seg.value === modelData.value
                width: Math.max(52, optText.implicitWidth + 24); height: 28; radius: 8
                color: on ? Theme.surface : (optArea.containsMouse ? Theme.hover : "transparent")
                border.width: on ? 1 : 0; border.color: Theme.edge
                Text {
                    id: optText
                    anchors.centerIn: parent
                    text: opt.modelData.label
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 13; font.weight: opt.on ? Font.DemiBold : Font.Normal
                }
                MouseArea { id: optArea; anchors.fill: parent; hoverEnabled: true; onClicked: seg.picked(opt.modelData.value) }
            }
        }
    }
}
