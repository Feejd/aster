import QtQuick
import "Icons.js" as I

// Mały przycisk z ikoną na pasku narzędzi; wyszarzony, gdy nieaktywny
HoverButton {
    id: tb
    property string icon
    width: 34
    height: 32
    radius: 8
    opacity: enabled ? 1 : 0.35
    Icon { anchors.centerIn: parent; d: I[tb.icon]; size: 17; color: tb.t.text }
}
