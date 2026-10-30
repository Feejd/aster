import QtQuick
import QtQuick.Effects

// Duży zegar na pulpicie: cienka, duża godzina i data — widoczne, gdy nic nie zasłania pulpitu
Item {
    id: dc
    property bool dark: false
    property date now: new Date()
    width: col.implicitWidth
    height: col.implicitHeight

    Timer { interval: 1000; running: true; repeat: true; onTriggered: dc.now = new Date() }

    Column {
        id: col
        spacing: -6
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, dc.dark ? 0.5 : 0.18)
            shadowBlur: 0.8
            shadowVerticalOffset: 2
        }
        Text {
            text: Qt.locale("pl_PL").toString(dc.now, "dddd, d MMMM")
            color: Qt.rgba(1, 1, 1, 0.92)
            font.pixelSize: 22
            font.weight: Font.Medium
            leftPadding: 6
        }
        Text {
            text: Qt.formatTime(dc.now, "HH:mm")
            color: "white"
            font.pixelSize: 132
            font.weight: Font.DemiBold
            font.letterSpacing: -4
            font.features: { "tnum": 1 }
        }
    }
}
