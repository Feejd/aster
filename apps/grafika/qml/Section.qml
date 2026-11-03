import QtQuick
import Aster.Ui

// Grupa ustawień z małym nagłówkiem
Column {
    id: section
    property string title
    width: parent ? parent.width : 0
    spacing: 8
    Text {
        visible: section.title !== ""
        text: section.title
        color: Theme.text2
        font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
    }
}
