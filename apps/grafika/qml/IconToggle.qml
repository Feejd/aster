import QtQuick
import Aster.Ui

// Kwadratowy przycisk z ikoną, który może być włączony (pogrubienie, wyrównanie, warstwy)
HoverButton {
    id: it
    property string icon
    property string label            // zamiast ikony, np. „Aa”
    property bool on: false
    width: 32
    height: 32
    radius: 10
    baseColor: on ? Theme.accentSoft : "transparent"
    color: on ? baseColor : hovered ? Theme.hover : baseColor
    opacity: enabled ? 1 : 0.35
    Icon {
        visible: it.label === ""
        anchors.centerIn: parent
        d: Icons[it.icon] || ""
        size: 17; stroke: 1.9
        color: it.on ? Theme.accentText : Theme.text
    }
    Text {
        visible: it.label !== ""
        anchors.centerIn: parent
        text: it.label
        color: it.on ? Theme.accentText : Theme.text
        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
    }
}
