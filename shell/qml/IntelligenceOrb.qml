import QtQuick
import QtQuick.Shapes
import Aster.Ui

// Znak Aster Intelligence: kula z kolorów, które powoli krążą, z iskrą w środku.
// Gdy model myśli (busy), kolory przyspieszają, a iskra pulsuje.
Item {
    id: o
    property real size: 30
    property bool busy: false
    property real angle: 0
    property real speed: busy ? 260 : 45
    Behavior on speed { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
    width: size; height: size

    FrameAnimation {
        running: o.visible
        onTriggered: o.angle = (o.angle + frameTime * o.speed) % 360
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: ConicalGradient {
                centerX: o.size / 2; centerY: o.size / 2
                angle: o.angle
                GradientStop { position: 0.00; color: "#60A5FA" }
                GradientStop { position: 0.25; color: "#22D3EE" }
                GradientStop { position: 0.50; color: "#2563EB" }
                GradientStop { position: 0.72; color: "#7DD3FC" }
                GradientStop { position: 1.00; color: "#60A5FA" }
            }
            PathRectangle { width: o.size; height: o.size; radius: o.size / 2 }
        }
    }
    // Szklany połysk u góry i ciemniejsze dno — kula, a nie płaski krążek
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.42) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop { position: 1.0; color: Qt.rgba(0.02, 0.10, 0.35, 0.30) }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.35)
    }
    Icon {
        id: star
        anchors.centerIn: parent
        d: Icons.sparkle
        size: o.size * 0.53
        stroke: 2
        color: "white"
        property real pulse: 1
        scale: pulse
        SequentialAnimation on pulse {
            running: o.busy
            loops: Animation.Infinite
            NumberAnimation { to: 1.18; duration: 420; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.92; duration: 420; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) star.pulse = 1
        }
    }
}
