import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// Poświata Aster Intelligence: tęczowa obwódka krążąca wokół zaokrąglonego prostokąta
// (wyspy, panelu albo całego ekranu) i miękkie światło, które się od niej rozlewa.
// Element ma rozmiar obejmowanego obiektu — obwódka i światło wychodzą poza niego.
// intensity 0…1 rozjaśnia całość, speed (stopnie na sekundę) — jak szybko kolory krążą.
// Rysuje się tylko, gdy jest widoczna; po zgaszeniu (intensity 0) nic nie kosztuje.
Item {
    id: g
    property real radius: 24
    property real thickness: 2.5          // ostra obwódka
    property real haloWidth: 9            // szerokość pierścienia, z którego powstaje światło
    property real haloBlur: 32            // jak daleko światło się rozlewa
    property real haloStrength: 0.9
    property real intensity: 1
    property real speed: 60
    property real textureScale: 1         // < 1: światło liczone w mniejszej rozdzielczości (cały ekran)
    property real angle: 0
    property bool animate: true           // false: kąt podaje ktoś inny (druga warstwa tej samej poświaty)
    property bool showRing: true
    // Paleta jak w Apple Intelligence: fiolet, róż, błękit, koral, brzoskwinia
    readonly property var palette: ["#BC82F3", "#F5B9EA", "#8D9FFF", "#AA6EEE", "#FF6778", "#FFBA71", "#C686FF", "#BC82F3"]

    visible: intensity > 0.005
    opacity: intensity
    Behavior on speed { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }

    FrameAnimation {
        running: g.visible && g.animate
        onTriggered: g.angle = (g.angle + frameTime * g.speed) % 360
    }

    component Ring: Shape {
        id: ring
        required property real w
        x: -w; y: -w
        width: g.width + 2 * w
        height: g.height + 2 * w
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillRule: ShapePath.OddEvenFill
            fillGradient: ConicalGradient {
                centerX: ring.width / 2; centerY: ring.height / 2
                angle: g.angle
                GradientStop { position: 0.000; color: g.palette[0] }
                GradientStop { position: 0.143; color: g.palette[1] }
                GradientStop { position: 0.286; color: g.palette[2] }
                GradientStop { position: 0.429; color: g.palette[3] }
                GradientStop { position: 0.571; color: g.palette[4] }
                GradientStop { position: 0.714; color: g.palette[5] }
                GradientStop { position: 0.857; color: g.palette[6] }
                GradientStop { position: 1.000; color: g.palette[7] }
            }
            PathRectangle { x: 0; y: 0; width: ring.width; height: ring.height; radius: g.radius + ring.w }
            PathRectangle { x: ring.w; y: ring.w; width: g.width; height: g.height; radius: g.radius }
        }
    }

    // Światło: grubszy pierścień, rozmyty
    Ring {
        id: haloRing
        w: g.haloWidth
        visible: false
        layer.enabled: true
        layer.textureSize: Qt.size(Math.max(1, width * g.textureScale), Math.max(1, height * g.textureScale))
        layer.smooth: true
    }
    MultiEffect {
        x: haloRing.x; y: haloRing.y
        width: haloRing.width; height: haloRing.height
        source: haloRing
        autoPaddingEnabled: true
        blurEnabled: true
        blurMax: g.haloBlur
        blur: 1
        saturation: 0.15
        opacity: g.haloStrength
    }
    // Ostra obwódka
    Ring { w: g.thickness; visible: g.showRing }
}
