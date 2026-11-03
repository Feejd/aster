import QtQuick
import Aster.Ui

// Przycisk-pigułka (ikona i/lub napis); primary — w kolorze akcentu
HoverButton {
    id: pill
    property string text
    property string icon
    property string path                   // własna ścieżka SVG zamiast ikony z Icons
    property bool primary: false
    property bool danger: false
    property bool active: false            // włączony przełącznik (np. metronom)
    property string tip
    readonly property color fg: primary || danger ? "white" : (active ? Theme.accentText : Theme.text)
    width: pillRow.implicitWidth + (text ? 30 : 18); height: 34; radius: 17
    baseColor: primary ? Theme.accent : danger ? "#E5484D" : active ? Theme.accentSoft : Theme.fill
    color: primary || danger ? (hovered ? Qt.lighter(baseColor, 1.12) : baseColor) : (hovered ? (active ? Theme.accentAlpha(Theme.dark ? 0.42 : 0.22) : Theme.hover) : baseColor)
    opacity: enabled ? 1 : 0.4
    Row {
        id: pillRow
        anchors.centerIn: parent
        spacing: 7
        Icon {
            visible: pill.icon !== "" || pill.path !== ""
            anchors.verticalCenter: parent.verticalCenter
            d: pill.path || Icons[pill.icon] || ""
            size: 15; stroke: 2
            color: pill.fg
            fill: pill.icon === "play" ? pill.fg : "transparent"
        }
        Text {
            visible: pill.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: pill.text
            color: pill.fg
            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
        }
    }
    Tip { shown: pill.hovered && pill.tip !== ""; text: pill.tip }
}
