import QtQuick
import Aster.Ui

// Grupa ustawień z małym nagłówkiem. collapsible — nagłówek ze strzałką zwija i rozwija grupę (panel właściwości),
// divider — cienka linia nad nagłówkiem, jak w programach graficznych
Column {
    id: section
    property string title
    property bool collapsible: false
    property bool collapsed: false
    property bool divider: false
    default property alias content: body.data
    width: parent ? parent.width : 0
    spacing: 8

    Item {
        visible: section.title !== ""
        width: parent.width
        height: section.divider ? 31 : 17
        Rectangle { visible: section.divider; width: parent.width; height: 1; color: Theme.line }
        Text {
            anchors.bottom: parent.bottom
            text: section.title
            color: section.collapsible ? Theme.text : Theme.text2
            font.family: Theme.font; font.pixelSize: 12; font.weight: section.collapsible ? Font.Bold : Font.DemiBold
        }
        Icon {
            visible: section.collapsible
            anchors.right: parent.right
            anchors.bottom: parent.bottom; anchors.bottomMargin: 1
            d: section.collapsed ? Icons.chevronRight : Icons.chevronDown
            size: 14; stroke: 2; color: Theme.text2
        }
        MouseArea {
            enabled: section.collapsible
            anchors.fill: parent; anchors.topMargin: section.divider ? 8 : 0
            cursorShape: Qt.PointingHandCursor
            onClicked: section.collapsed = !section.collapsed
        }
    }
    Column {
        id: body
        visible: !section.collapsed
        width: parent.width
        spacing: 8
    }
}
