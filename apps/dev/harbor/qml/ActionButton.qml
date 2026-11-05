import QtQuick
import Aster.Ui

// Przycisk z tekstem (zwykły, główny w kolorze akcentu albo czerwony)
HoverButton {
    id: ab
    property string text
    property string icon
    property bool primary: false
    property bool danger: false
    width: abRow.implicitWidth + 28; height: 34; radius: 10
    baseColor: danger ? "#E5484D" : primary ? Theme.accent : Theme.fill
    color: hovered && enabled ? (danger ? "#D93B40" : primary ? Qt.darker(Theme.accent, 1.08) : Theme.hover) : baseColor
    opacity: enabled ? 1 : 0.5
    readonly property color fg: danger || primary ? "white" : Theme.text
    Row {
        id: abRow
        anchors.centerIn: parent
        spacing: 6
        Icon { visible: !!ab.icon; anchors.verticalCenter: parent.verticalCenter; d: Icons[ab.icon] || ""; size: 14; stroke: 2; color: ab.fg }
        Text { text: ab.text; color: ab.fg; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
    }
}
