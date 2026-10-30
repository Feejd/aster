import QtQuick
import QtQuick.Effects

// Wysuwany panel ze szklanym tłem i cieniem (Start, centrum sterowania, asystent).
// Otwiera się sprężyście z punktu, z którego go wywołano (originX/originY),
// wyostrza się z lekkiego rozmycia, a elementy w środku wchodzą kaskadą (stagger()).
Item {
    id: p
    property var t
    property Item backdrop
    property bool open: false
    property real originX: 0.5          // skąd rośnie panel (0..1 szerokości)
    property real originY: 1.0          // (0..1 wysokości)
    default property alias content: body.data

    property real s: 0.92               // skala
    property real offset: 14            // przesunięcie w pionie
    property real blurAmount: 1         // rozmycie treści przy wejściu
    property real reveal: 0             // postęp kaskady 0..1

    // Postęp wejścia i-tego elementu (0..1), opóźniony względem poprzedniego
    function stagger(i) {
        return Math.max(0, Math.min(1, (reveal - i * 0.022) / 0.40));
    }

    opacity: 0
    visible: opacity > 0.01
    transform: [
        Scale { origin.x: p.width * p.originX; origin.y: p.height * p.originY; xScale: p.s; yScale: p.s },
        Translate { y: p.offset }
    ]

    states: State {
        name: "shown"
        when: p.open
        PropertyChanges { p.s: 1; p.offset: 0; p.opacity: 1; p.blurAmount: 0; p.reveal: 1 }
    }
    transitions: [
        Transition {
            to: "shown"
            ParallelAnimation {
                NumberAnimation { target: p; property: "s"; duration: 230; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
                NumberAnimation { target: p; property: "offset"; duration: 200; easing.type: Easing.OutQuint }
                NumberAnimation { target: p; property: "opacity"; duration: 70; easing.type: Easing.OutQuad }
                NumberAnimation { target: p; property: "blurAmount"; duration: 130; easing.type: Easing.OutCubic }
                NumberAnimation { target: p; property: "reveal"; from: 0; duration: 300; easing.type: Easing.OutCubic }
            }
        },
        Transition {
            from: "shown"
            ParallelAnimation {
                NumberAnimation { target: p; property: "s"; to: 0.96; duration: 90; easing.type: Easing.InCubic }
                NumberAnimation { target: p; property: "offset"; to: 6; duration: 90; easing.type: Easing.InCubic }
                NumberAnimation { target: p; property: "opacity"; duration: 90; easing.type: Easing.InQuad }
                NumberAnimation { target: p; property: "blurAmount"; to: 0.5; duration: 90 }
                NumberAnimation { target: p; property: "reveal"; to: 0; duration: 1 }
            }
        }
    ]

    RectangularShadow {
        anchors.fill: parent
        radius: 22
        blur: 70
        offset.y: 24
        color: p.t.shadow
    }

    Glass {
        anchors.fill: parent
        backdrop: p.backdrop
        sx: p.x
        sy: p.y + p.offset
        radius: 22
        tint: p.t.glass
        edge: p.t.edge
        rim: p.t.rim
    }

    Item {
        id: body
        anchors.fill: parent
        layer.enabled: p.blurAmount > 0.02
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: p.blurAmount
            blurMax: 20
        }
    }
}
