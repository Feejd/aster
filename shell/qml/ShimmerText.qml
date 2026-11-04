import QtQuick
import Aster.Ui

// Napis, po którym przebiega tęczowy połysk — „Myślę…”, zanim przyjdzie odpowiedź.
// Połysk to kilka przyciętych pasów z tym samym napisem w innym kolorze (bez shaderów —
// lekko nawet na starym komputerze): szeroki fioletowy, węższy brzoskwiniowy i wąski biały.
Item {
    id: s
    property alias text: label.text
    property color base: Qt.rgba(1, 1, 1, 0.45)
    property int pixelSize: 14
    property real p: 0
    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight
    width: implicitWidth; height: implicitHeight

    NumberAnimation on p {
        running: s.visible
        loops: Animation.Infinite
        from: 0; to: 1
        duration: 1600
        easing.type: Easing.InOutSine
    }

    Text {
        id: label
        color: s.base
        font.family: Theme.font; font.pixelSize: s.pixelSize; font.weight: Font.Medium
    }
    Repeater {
        model: [
            { w: 0.55, c: "#38BDF8", o: 0.75 },
            { w: 0.32, c: "#7DD3FC", o: 0.9 },
            { w: 0.12, c: "#FFFFFF", o: 1.0 }
        ]
        delegate: Item {
            id: band
            required property var modelData
            readonly property real bw: Math.max(14, s.width * band.modelData.w)
            readonly property real center: -0.35 * s.width + s.p * 1.7 * s.width
            x: center - bw / 2
            width: bw
            height: s.height
            clip: true
            Text {
                x: -band.x
                text: label.text
                font: label.font
                color: band.modelData.c
                opacity: band.modelData.o
            }
        }
    }
}
