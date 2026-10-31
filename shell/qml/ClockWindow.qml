import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Aster.Shell
import Aster.Ui

// Duża godzina na pulpicie (nad tapetą, pod oknami) — pierwsze, co widać po zalogowaniu.
// Okno przepuszcza wszystkie kliknięcia (pusty obszar wejścia).
Window {
    id: cw
    color: "transparent"
    title: "Zegar"
    visible: false
    width: Screen.width
    height: Screen.height

    Component.onCompleted: {
        Platform.makeLayer(cw, "bottom", 1 | 2 | 4 | 8, -1, "none", "aster-clock");
        visible = true;
        Platform.setInputRegion(cw, [{ x: 0, y: 0, w: 1, h: 1, r: 0 }]);
    }

    property date now: new Date()
    Timer { interval: 1000; repeat: true; running: true; onTriggered: cw.now = new Date() }

    Column {
        x: 72; y: 84
        spacing: -6
        layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 0.7
            shadowVerticalOffset: 3
            shadowColor: Qt.rgba(0, 0, 0, Theme.dark ? 0.35 : 0.10)
        }
        Text {
            text: {
                const s = cw.now.toLocaleDateString(Qt.locale("pl_PL"), "dddd, d MMMM");
                return s.charAt(0).toUpperCase() + s.slice(1);
            }
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.92) : Qt.rgba(0.11, 0.12, 0.17, 0.78)
            font.family: Theme.font
            font.pixelSize: 24; font.letterSpacing: -0.5
            font.weight: Font.DemiBold
            leftPadding: 6
        }
        Text {
            text: cw.now.toLocaleTimeString(Qt.locale("pl_PL"), "HH:mm")
            color: Theme.dark ? "white" : Qt.rgba(0.11, 0.12, 0.17, 0.88)
            font.family: Theme.font
            font.pixelSize: 148
            font.weight: Font.Light
            font.letterSpacing: -3
            font.features: { "tnum": 1 }
        }
    }
}
