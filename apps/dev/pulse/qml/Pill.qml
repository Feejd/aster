import QtQuick
import Aster.Ui

// Przycisk-pigułka: tekst, opcjonalna ikona; primary — w kolorze akcentu, danger — czerwony
HoverButton {
    id: pill
    property string text
    property string icon
    property bool primary: false
    property bool danger: false
    property bool small: false
    readonly property color fg: primary || danger ? "white" : Theme.text

    width: row.implicitWidth + (small ? 20 : 28)
    height: small ? 28 : 34
    radius: 8
    baseColor: danger ? "#E5484D" : primary ? Theme.accent : Theme.fill
    color: hovered && enabled ? (danger ? "#D93B40" : primary ? Qt.darker(Theme.accent, 1.1) : Theme.hover) : baseColor
    opacity: enabled ? 1 : 0.45

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Icon {
            visible: pill.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            d: Icons[pill.icon] || ""
            size: pill.small ? 13 : 15
            stroke: 2
            color: pill.fg
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.text
            color: pill.fg
            font.family: Theme.font; font.pixelSize: pill.small ? 12 : 13; font.weight: Font.Medium
        }
    }
}
