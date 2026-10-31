import QtQuick
import Aster.Ui

// Mały przycisk w wierszu (Połącz, Rozłącz, Szukaj…); `primary` — w kolorze akcentu
Rectangle {
    id: tb
    property string text
    property bool primary: false
    property bool busy: false
    signal clicked()
    width: label.implicitWidth + 24; height: 28
    radius: 14
    color: primary ? (area.containsMouse ? Qt.darker(Theme.accent, 1.1) : Theme.accent) : (area.containsMouse ? Theme.hover : Theme.fill)
    scale: area.pressed ? 0.95 : 1
    opacity: enabled ? 1 : 0.5
    Behavior on scale { NumberAnimation { duration: 100 } }
    Text {
        id: label
        anchors.centerIn: parent
        text: tb.busy ? tb.text + "…" : tb.text
        color: tb.primary ? "white" : Theme.text
        font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
    }
    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.clicked() }
}
