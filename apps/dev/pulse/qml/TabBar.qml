pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui

// Karty z podkreśleniem: tabs: [{ id, label, count }]
Item {
    id: bar
    property var tabs: []
    property string current
    signal picked(string id)

    implicitHeight: 36
    implicitWidth: row.implicitWidth

    Row {
        id: row
        height: parent.height
        spacing: 4
        Repeater {
            model: bar.tabs
            delegate: Item {
                id: tab
                required property var modelData
                readonly property bool active: bar.current === modelData.id
                width: label.implicitWidth + (badge.visible ? badge.width + 6 : 0) + 20
                height: row.height
                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: 4; anchors.bottomMargin: 4
                    radius: 8
                    color: tabArea.containsMouse && !tab.active ? Theme.hover : "transparent"
                }
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        id: label
                        anchors.verticalCenter: parent.verticalCenter
                        text: tab.modelData.label
                        color: tab.active ? Theme.text : Theme.text2
                        font.family: Theme.font; font.pixelSize: 13
                        font.weight: tab.active ? Font.DemiBold : Font.Normal
                    }
                    Rectangle {
                        id: badge
                        visible: (tab.modelData.count || 0) > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(18, badgeText.implicitWidth + 10); height: 18; radius: 9
                        color: tab.active ? Theme.accentSoft : Theme.fill
                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            text: tab.modelData.count || ""
                            color: tab.active ? Theme.accentText : Theme.text2
                            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium
                        }
                    }
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: tab.active ? parent.width - 16 : 0; height: 2; radius: 1
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
                MouseArea {
                    id: tabArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: bar.picked(tab.modelData.id)
                }
            }
        }
    }
}
