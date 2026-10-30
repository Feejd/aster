import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// Tapeta „Fale”: warstwy gładkich fal płynących ukosem, jak złożony jedwab.
// Każda fala rzuca miękki cień na warstwę za sobą, ma gradient od oświetlonej
// krawędzi w głąb i delikatny połysk. Jasna wersja to świt, ciemna — noc.
Item {
    id: wp
    property bool dark: false

    readonly property var layers: [
        { yl: 0.30, yr: 0.16, c1: 0.44, c2: 0.04 },
        { yl: 0.36, yr: 0.52, c1: 0.18, c2: 0.66 },
        { yl: 0.64, yr: 0.40, c1: 0.74, c2: 0.28 },
        { yl: 0.72, yr: 0.80, c1: 0.56, c2: 0.96 },
        { yl: 0.94, yr: 0.82, c1: 0.84, c2: 0.98 }
    ]
    // Warianty kolorystyczne: Świt, Laguna, Zachód — każdy w wersji jasnej i ciemnej
    property string variant: "swit"
    readonly property var palettes: ({
        swit: {
            light: { sky: ["#8FB2FF", "#CFC6FF", "#FFD6C6"], layers: [["#CDBEFF", "#9CAEFF"], ["#FFC6DC", "#C7A0FF"], ["#FFC5A8", "#EF8FB4"], ["#86A2FF", "#6455EE"], ["#4F6BEA", "#3A30B4"]] },
            dark: { sky: ["#070B22", "#141646", "#24124A"], layers: [["#3E43A8", "#1C1E62"], ["#6D3CAE", "#2A175C"], ["#B24A90", "#47194F"], ["#3456E2", "#152274"], ["#1D2B8C", "#0A0F3A"]] }
        },
        laguna: {
            light: { sky: ["#7FD3E8", "#BFEDE3", "#F3F1D8"], layers: [["#A9E7F0", "#7CC8E8"], ["#8FE3C8", "#4FBFB0"], ["#C7F0B0", "#7FD69A"], ["#3FA9C9", "#2479A8"], ["#1F6F9A", "#154C78"]] },
            dark: { sky: ["#04141C", "#0A2730", "#0D2A2A"], layers: [["#145868", "#0B3442"], ["#137A6E", "#0A4640"], ["#2E8A5A", "#164A32"], ["#1A6D9A", "#0C3A5C"], ["#0E3A5C", "#06202F"]] }
        },
        zachod: {
            light: { sky: ["#FFB38A", "#FFD0B0", "#FFE9D6"], layers: [["#FFC9A6", "#FF9F80"], ["#FF9FA8", "#E8708C"], ["#FFB070", "#F2804E"], ["#D8607A", "#A8405F"], ["#7A3A6E", "#4E2452"]] },
            dark: { sky: ["#1A0A14", "#2A0F22", "#3A1424"], layers: [["#5A2440", "#341428"], ["#8A3048", "#4A1A2A"], ["#B4522E", "#5E2614"], ["#7A2450", "#3E1230"], ["#3A1238", "#1C0A1E"]] }
        }
    })
    readonly property var pal: (palettes[variant] || palettes.swit)[dark ? "dark" : "light"]
    readonly property var sky: pal.sky
    readonly property var colors: pal.layers

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: wp.sky[0] }
            GradientStop { position: 0.55; color: wp.sky[1] }
            GradientStop { position: 1.0; color: wp.sky[2] }
        }
    }

    // Poświata za falami
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: wp.width * 0.70; centerY: wp.height * 0.22; centerRadius: wp.width * 0.42
                focalX: centerX; focalY: centerY
                GradientStop { position: 0; color: wp.dark ? Qt.rgba(0.55, 0.45, 1, 0.30) : Qt.rgba(1, 1, 1, 0.70) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathRectangle { x: 0; y: 0; width: wp.width; height: wp.height }
        }
    }

    Repeater {
        model: wp.layers
        delegate: Item {
            id: wave
            required property var modelData
            required property int index
            anchors.fill: parent
            readonly property real w: wp.width
            readonly property real h: wp.height
            readonly property real crestTop: Math.min(modelData.yl, modelData.yr) * h
            readonly property var c: wp.colors[index]

            // Cień rzucany w górę, na warstwę za falą
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                layer.enabled: true
                layer.effect: MultiEffect {
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 48
                }
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: wp.dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(50 / 255, 30 / 255, 120 / 255, 0.28)
                    startX: -wave.w * 0.05; startY: wave.modelData.yl * wave.h - 18
                    PathCubic {
                        x: wave.w * 1.05; y: wave.modelData.yr * wave.h - 18
                        control1X: wave.w * 0.35; control1Y: wave.modelData.c1 * wave.h - 18
                        control2X: wave.w * 0.70; control2Y: wave.modelData.c2 * wave.h - 18
                    }
                    PathLine { x: wave.w * 1.05; y: wave.h * 1.05 }
                    PathLine { x: -wave.w * 0.05; y: wave.h * 1.05 }
                }
            }

            // Fala
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillGradient: LinearGradient {
                        x1: 0; y1: wave.crestTop
                        x2: wave.w * 0.15; y2: wave.crestTop + wave.h * 0.38
                        GradientStop { position: 0; color: wave.c[0] }
                        GradientStop { position: 1; color: wave.c[1] }
                    }
                    startX: -wave.w * 0.05; startY: wave.modelData.yl * wave.h
                    PathCubic {
                        x: wave.w * 1.05; y: wave.modelData.yr * wave.h
                        control1X: wave.w * 0.35; control1Y: wave.modelData.c1 * wave.h
                        control2X: wave.w * 0.70; control2Y: wave.modelData.c2 * wave.h
                    }
                    PathLine { x: wave.w * 1.05; y: wave.h * 1.05 }
                    PathLine { x: -wave.w * 0.05; y: wave.h * 1.05 }
                }
                // Połysk: jaśniejsze pasmo biegnące ukosem przez falę
                ShapePath {
                    strokeColor: "transparent"
                    fillGradient: LinearGradient {
                        x1: wave.w * (0.15 + wave.index * 0.12); y1: 0
                        x2: wave.w * (0.55 + wave.index * 0.12); y2: wave.h * 0.4
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: wp.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.22) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                    startX: -wave.w * 0.05; startY: wave.modelData.yl * wave.h
                    PathCubic {
                        x: wave.w * 1.05; y: wave.modelData.yr * wave.h
                        control1X: wave.w * 0.35; control1Y: wave.modelData.c1 * wave.h
                        control2X: wave.w * 0.70; control2Y: wave.modelData.c2 * wave.h
                    }
                    PathLine { x: wave.w * 1.05; y: wave.h * 1.05 }
                    PathLine { x: -wave.w * 0.05; y: wave.h * 1.05 }
                }
                // Cienka, jasna krawędź grzbietu
                ShapePath {
                    strokeWidth: 1.2
                    strokeColor: wp.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.50)
                    fillColor: "transparent"
                    startX: -wave.w * 0.05; startY: wave.modelData.yl * wave.h
                    PathCubic {
                        x: wave.w * 1.05; y: wave.modelData.yr * wave.h
                        control1X: wave.w * 0.35; control1Y: wave.modelData.c1 * wave.h
                        control2X: wave.w * 0.70; control2Y: wave.modelData.c2 * wave.h
                    }
                }
            }
        }
    }
}
