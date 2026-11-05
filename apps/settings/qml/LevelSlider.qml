import QtQuick
import QtQuick.Effects
import Aster.Ui

// Suwak jak w macOS (ten sam co w centrum sterowania): gruba ścieżka, biała część z gałką, ikona po lewej
Item {
    id: sl
    property string icon
    property real value: 0
    signal moved(real v)
    signal iconClicked()
    height: 26
    readonly property real fillW: height + (width - height) * value
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.09)
    }
    Rectangle {
        width: sl.fillW; height: parent.height
        radius: 8
        color: Theme.dark ? "#E8EAF0" : Theme.accentAlpha(0.18)
        Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
    RectangularShadow {
        x: sl.fillW - sl.height; width: sl.height; height: sl.height
        radius: sl.height / 2; blur: 8; offset.y: 1
        color: Qt.rgba(0, 0, 0, 0.3)
    }
    Rectangle {
        x: sl.fillW - sl.height; width: sl.height; height: sl.height
        radius: sl.height / 2
        color: "white"
        border.width: 1
        border.color: Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.10)
    }
    Icon {
        x: 5; anchors.verticalCenter: parent.verticalCenter
        d: Icons[sl.icon] || ""; size: 16; stroke: 2
        color: "#5B6270"
    }
    MouseArea {
        id: drag
        anchors.fill: parent
        function apply(mx) { sl.moved(Math.max(0, Math.min(1, (mx - sl.height / 2) / (sl.width - sl.height)))); }
        onPressed: m => { if (m.x >= sl.height - 2) apply(m.x); }
        onPositionChanged: m => { if (pressed && m.x >= 0) apply(m.x); }
        onClicked: m => { if (m.x < sl.height - 2) sl.iconClicked(); }
    }
}
