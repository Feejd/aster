pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui

// Przełącznik kilku wartości (np. „Oszczędzanie · Zrównoważony · Wydajność”): wybrana na białej pigułce
Rectangle {
    id: seg
    property var model: []          // [{ label, value }]
    property var value
    signal picked(var value)
    height: 32; radius: 16
    width: row.implicitWidth + 6
    color: Theme.fill
    Row {
        id: row
        x: 3; anchors.verticalCenter: parent.verticalCenter
        Repeater {
            model: seg.model
            delegate: Rectangle {
                id: opt
                required property var modelData
                readonly property bool on: modelData.value === seg.value
                width: txt.implicitWidth + 26; height: 26; radius: 13
                color: on ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : "white") : "transparent"
                border.width: on && !Theme.dark ? 1 : 0
                border.color: Theme.line
                Behavior on color { ColorAnimation { duration: 90 } }
                Text { id: txt; anchors.centerIn: parent; text: opt.modelData.label; color: opt.on ? Theme.text : Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: opt.on ? Font.DemiBold : Font.Medium }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: seg.picked(opt.modelData.value) }
            }
        }
    }
}
