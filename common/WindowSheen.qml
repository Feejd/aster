import QtQuick
import QtQuick.Shapes

// Wykończenie okna Aster, kładzione na wierzch ramki (nie łapie kliknięć):
//  • „zorza”: dwie bardzo delikatne plamy koloru akcentu w przeciwległych rogach (siatka gradientów),
//  • sprężyste pojawienie się okna przy otwarciu (lekkie powiększenie i rozjaśnienie).
Item {
    id: sh
    required property Window window
    property real radius: 14
    property bool animateOpen: true
    property bool aurora: false
    readonly property bool active: window.active || WindowEffects.preview
    readonly property bool maxed: window.visibility === Window.Maximized || window.visibility === Window.FullScreen
    anchors.fill: parent
    z: 1000
    enabled: false

    // Zorza w kolorze akcentu: lewy górny róg i (przesunięty odcień) prawy dolny
    readonly property color hue2: Qt.hsla((Theme.accent.hslHue + 0.11) % 1, Math.min(1, Theme.accent.hslSaturation + 0.1), Theme.accent.hslLightness, 1)
    Shape {
        anchors.fill: parent
        visible: sh.aurora
        opacity: sh.active ? 1 : 0.5
        Behavior on opacity { NumberAnimation { duration: 260 } }
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: 0; centerY: 0; focalX: 0; focalY: 0
                centerRadius: Math.max(360, sh.width * 0.45)
                GradientStop { position: 0; color: Theme.accentAlpha(Theme.dark ? 0.20 : 0.12) }
                GradientStop { position: 1; color: Theme.accentAlpha(0) }
            }
            PathRectangle { width: sh.width; height: sh.height; radius: sh.radius }
        }
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: sh.width; centerY: sh.height; focalX: sh.width; focalY: sh.height
                centerRadius: Math.max(320, sh.width * 0.4)
                GradientStop { position: 0; color: Qt.rgba(sh.hue2.r, sh.hue2.g, sh.hue2.b, Theme.dark ? 0.14 : 0.08) }
                GradientStop { position: 1; color: Qt.rgba(sh.hue2.r, sh.hue2.g, sh.hue2.b, 0) }
            }
            PathRectangle { width: sh.width; height: sh.height; radius: sh.radius }
        }
    }
    // Otwarcie okna: zawartość wyrasta z 94% i rozjaśnia się
    Component.onCompleted: if (animateOpen) intro.start()
    ParallelAnimation {
        id: intro
        NumberAnimation { target: sh.window.contentItem; property: "scale"; from: 0.94; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
        NumberAnimation { target: sh.window.contentItem; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutQuad }
    }
}
