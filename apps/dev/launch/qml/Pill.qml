import QtQuick
import Aster.Ui

// Przycisk w kształcie pigułki: zwykły, główny (akcent) albo niebezpieczny; opcjonalnie z ikoną
HoverButton {
    id: pill
    property string text
    property string iconPath: ""
    property bool danger: false
    property bool primary: false
    property bool small: false
    width: row.implicitWidth + (small ? 22 : 30); height: small ? 28 : 34; radius: height / 2
    opacity: enabled ? 1 : 0.5
    baseColor: danger ? "#E5484D" : primary ? Theme.accent : Theme.fill
    color: hovered && enabled ? (danger ? "#D93B40" : primary ? Qt.darker(Theme.accent, 1.1) : Theme.hover) : baseColor
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Icon {
            visible: pill.iconPath !== ""
            anchors.verticalCenter: parent.verticalCenter
            d: pill.iconPath; size: pill.small ? 13 : 15; stroke: 2
            color: pill.danger || pill.primary ? "white" : Theme.text
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.text
            color: pill.danger || pill.primary ? "white" : Theme.text
            font.family: Theme.font; font.pixelSize: pill.small ? 12 : 13; font.weight: Font.Medium
        }
    }
}
