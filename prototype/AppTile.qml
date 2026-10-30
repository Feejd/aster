import QtQuick
import "Icons.js" as I

// Ikona aplikacji: zaokrąglony kwadrat z gradientem, połyskiem i białym symbolem
Rectangle {
    id: at
    property var app
    property real size: 56
    width: size; height: size
    radius: size * 0.27
    gradient: Gradient {
        GradientStop { position: 0; color: at.app ? Qt.lighter(at.app.color, 1.3) : "gray" }
        GradientStop { position: 1; color: at.app ? at.app.color : "gray" }
    }
    Rectangle { anchors.fill: parent; radius: parent.radius; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.22) }
    Icon { anchors.centerIn: parent; d: at.app ? (I[at.app.icon] || "") : ""; size: at.size * 0.46; stroke: 1.8; color: "white" }
}
