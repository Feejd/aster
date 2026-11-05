import QtQuick
import Aster.Ui

// Przycisk tekstowy: główny (akcent) albo spokojny
HoverButton {
    id: b
    property string text
    property bool primary: false
    property string icon: ""
    property bool danger: false
    implicitWidth: row.implicitWidth + 28
    implicitHeight: 38
    width: implicitWidth
    height: implicitHeight
    radius: 8
    baseColor: primary ? Theme.accent : Theme.fill
    opacity: enabled ? 1 : 0.5
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Icon {
            visible: b.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            d: Icons[b.icon] || ""; size: 15
            color: b.primary ? "white" : b.danger ? Theme.danger : Theme.text
        }
        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: b.text
            color: b.primary ? "white" : b.danger ? Theme.danger : Theme.text
            font.pixelSize: 13; font.weight: Font.Medium
        }
    }
}
