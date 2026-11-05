import QtQuick
import Aster.Ui

// Kółko z kolorem; puste (przekreślone), gdy koloru brak
HoverButton {
    id: cw
    property string value          // "#rrggbb", "#aarrggbb" albo "" (brak)
    property string label
    width: label !== "" ? 36 + labelText.implicitWidth + 10 : 34
    height: 34
    radius: 8
    baseColor: label !== "" ? Theme.fill : "transparent"

    Rectangle {
        id: dot
        x: 5; anchors.verticalCenter: parent.verticalCenter
        width: 24; height: 24; radius: 12
        color: cw.value !== "" ? cw.value : "white"
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, Theme.dark ? 0.4 : 0.15)
        Rectangle {
            visible: cw.value === ""
            anchors.centerIn: parent
            width: 2; height: parent.width - 4
            rotation: 45
            color: "#E53935"
        }
    }
    Text {
        id: labelText
        visible: cw.label !== ""
        x: 36; anchors.verticalCenter: parent.verticalCenter
        text: cw.label
        color: Theme.text
        font.family: Theme.font; font.pixelSize: 13
    }
}
