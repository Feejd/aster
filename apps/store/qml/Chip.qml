import QtQuick
import Aster.Ui

// Kapsułka do wybierania (programy z Windowsa, działy katalogu)
Rectangle {
    id: c
    property string text
    property bool selected: false
    signal clicked()
    implicitWidth: label.implicitWidth + 26
    implicitHeight: 34
    width: implicitWidth
    height: implicitHeight
    radius: 8
    color: selected ? Theme.accent : (area.containsMouse ? Theme.hover : Theme.fill)
    Behavior on color { ColorAnimation { duration: 100 } }
    Txt {
        id: label
        anchors.centerIn: parent
        text: c.text
        color: c.selected ? "white" : Theme.text
        font.pixelSize: 13; font.weight: c.selected ? Font.Medium : Font.Normal
    }
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: c.clicked() }
}
