import QtQuick
import Aster.Ui

// Pigułka do wyboru jednej z kilku wartości (format, kategoria)
HoverButton {
    id: chip
    property string text
    property bool on: false
    width: chipText.implicitWidth + 26
    height: 32
    radius: height / 2
    baseColor: on ? Theme.accent : Theme.fill
    color: on ? baseColor : hovered ? Theme.hover : baseColor
    Text {
        id: chipText
        anchors.centerIn: parent
        text: chip.text
        color: chip.on ? "white" : Theme.text
        font.family: Theme.font; font.pixelSize: 13; font.weight: chip.on ? Font.DemiBold : Font.Normal
    }
}
