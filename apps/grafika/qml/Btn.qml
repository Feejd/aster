import QtQuick
import Aster.Ui

// Przycisk z tekstem i opcjonalną ikoną; `primary` — w kolorze akcentu
HoverButton {
    id: btn
    property string text
    property string icon
    property bool primary: false
    property real textSize: 13
    width: btnRow.implicitWidth + 30
    height: 36
    radius: height / 2
    baseColor: primary ? Theme.accent : Theme.fill
    color: !enabled ? baseColor : primary ? (hovered ? Qt.lighter(Theme.accent, 1.12) : baseColor) : (hovered ? Theme.hover : baseColor)
    opacity: enabled ? 1 : 0.45
    Row {
        id: btnRow
        anchors.centerIn: parent
        spacing: 7
        Icon { visible: btn.icon !== ""; anchors.verticalCenter: parent.verticalCenter; d: Icons[btn.icon] || ""; size: 16; stroke: 2; color: btn.primary ? "white" : Theme.text }
        Text {
            visible: btn.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: btn.text
            color: btn.primary ? "white" : Theme.text
            font.family: Theme.font; font.pixelSize: btn.textSize; font.weight: Font.DemiBold
        }
    }
}
