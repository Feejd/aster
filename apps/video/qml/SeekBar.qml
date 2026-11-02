import QtQuick
import Aster.Ui
import Aster.Video

// Pasek postępu filmu: pogrubia się pod kursorem, pokazuje czas w miejscu wskazania;
// przeciąganie przewija na bieżąco (nie częściej niż co 120 ms).
Item {
    id: bar
    property real duration: 0
    property real position: 0
    readonly property bool dragging: area.pressed
    property real dragPos: 0
    signal seekRequested(real ms)

    height: 20
    readonly property real shown: dragging ? dragPos : position
    readonly property real ratio: duration > 0 ? Math.max(0, Math.min(1, shown / duration)) : 0
    readonly property bool hot: area.containsMouse || dragging

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: bar.hot ? 6 : 4; radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.25)
        Behavior on height { NumberAnimation { duration: 120 } }
        Rectangle {
            visible: area.containsMouse && !bar.dragging
            width: Math.max(0, area.mouseX - x); height: parent.height; radius: parent.radius
            color: Qt.rgba(1, 1, 1, 0.25)
        }
        Rectangle { width: parent.width * bar.ratio; height: parent.height; radius: parent.radius; color: Theme.accent }
    }
    Rectangle {
        x: track.width * bar.ratio - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: bar.hot ? 14 : 0; height: width; radius: width / 2
        color: "white"
        Behavior on width { NumberAnimation { duration: 120 } }
    }
    Rectangle {
        visible: bar.hot && bar.duration > 0
        readonly property real at: bar.dragging ? track.width * bar.ratio : area.mouseX
        x: Math.max(0, Math.min(bar.width - width, at - width / 2))
        y: -height - 8
        width: tipText.implicitWidth + 16; height: 24; radius: 6
        color: Qt.rgba(0, 0, 0, 0.75)
        Text {
            id: tipText
            anchors.centerIn: parent
            text: Video.time(bar.dragging ? bar.dragPos : bar.duration * Math.max(0, Math.min(1, area.mouseX / bar.width)))
            color: "white"; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium; font.features: { "tnum": 1 }
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent; anchors.topMargin: -6; anchors.bottomMargin: -6
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        function at(x) { return bar.duration * Math.max(0, Math.min(1, x / bar.width)); }
        onPressed: (e) => { bar.dragPos = at(e.x); bar.seekRequested(bar.dragPos); }
        onPositionChanged: (e) => { if (pressed) { bar.dragPos = at(e.x); if (!throttle.running) { bar.seekRequested(bar.dragPos); throttle.start(); } } }
        onReleased: bar.seekRequested(bar.dragPos)
    }
    Timer { id: throttle; interval: 120 }
}
