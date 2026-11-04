import QtQuick
import Aster.Ui

// Kropka stanu: zielona — działa, bursztynowa i pulsująca — trwa akcja, szara — zatrzymany
Item {
    id: dot
    property bool running: false
    property bool busy: false
    property bool paused: false
    property real size: 10
    width: size; height: size
    readonly property color tone: busy || paused ? "#F5A623" : running ? "#22C55E" : (Theme.dark ? "#6B7280" : "#A3A9B5")

    Rectangle {
        anchors.centerIn: parent
        width: dot.size * 2.2; height: width; radius: width / 2
        color: dot.tone
        opacity: 0
        visible: dot.busy
        // Pulsuje tylko w trakcie akcji — stała animacja przy każdym wierszu kosztowałaby procesor
        SequentialAnimation on opacity {
            running: dot.busy
            loops: Animation.Infinite
            NumberAnimation { from: 0.45; to: 0; duration: 700; easing.type: Easing.OutQuad }
            PauseAnimation { duration: 100 }
        }
    }
    Rectangle {
        anchors.fill: parent; radius: width / 2
        color: dot.tone
        border.width: 1.5
        border.color: Theme.dark ? Qt.rgba(0, 0, 0, 0.4) : "white"
    }
}
