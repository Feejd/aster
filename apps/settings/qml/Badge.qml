import QtQuick
import Aster.Ui

// Kolorowa plakietka z białym znakiem (pasek boczny i wiersze ustawień)
Rectangle {
    id: b
    property string icon
    property var colors: ["#A3A9B5", "#4B5262"]
    property real size: 26
    width: size; height: size
    radius: size * 0.28
    gradient: Gradient {
        GradientStop { position: 0; color: b.colors[0] }
        GradientStop { position: 1; color: b.colors[1] }
    }
    Icon { anchors.centerIn: parent; d: Icons[b.icon] || ""; size: b.size * 0.58; stroke: 2; color: "white" }
}
