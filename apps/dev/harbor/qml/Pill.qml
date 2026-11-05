import QtQuick
import Aster.Ui

// Mała etykieta; z `clickable` działa jak przycisk (np. port → otwórz w przeglądarce)
Rectangle {
    id: pill
    property string text
    property string icon
    property color tint: Theme.text2
    property bool clickable: false
    property bool strong: false
    signal clicked()
    height: 22; radius: 11
    width: row.implicitWidth + 16
    color: area.containsMouse ? Qt.rgba(tint.r, tint.g, tint.b, Theme.dark ? 0.32 : 0.2)
                              : Qt.rgba(tint.r, tint.g, tint.b, strong ? (Theme.dark ? 0.26 : 0.16) : (Theme.dark ? 0.16 : 0.09))
    Behavior on color { ColorAnimation { duration: 120 } }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        Icon { visible: !!pill.icon; anchors.verticalCenter: parent.verticalCenter; d: Icons[pill.icon] || ""; size: 11; stroke: 2; color: label.color }
        Text {
            id: label
            text: pill.text
            color: Theme.dark ? Qt.lighter(pill.tint, 1.25) : Qt.darker(pill.tint, 1.15)
            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium; font.features: { "tnum": 1 }
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        enabled: pill.clickable
        hoverEnabled: pill.clickable
        cursorShape: pill.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: pill.clicked()
    }
}
