import QtQuick

// Mały przycisk z ikoną na pasku narzędzi; wyszarzony, gdy nieaktywny
HoverButton {
    id: tb
    property string icon
    width: 34
    height: 32
    opacity: enabled ? 1 : 0.35
    Icon { anchors.centerIn: parent; d: Icons[tb.icon] || ""; size: 17; color: Theme.text }
}
