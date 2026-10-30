import QtQuick
import QtQuick.Effects

// Matowe szkło: rozmyty fragment `backdrop` pod spodem + półprzezroczysty kolor.
// sx/sy to pozycja tego elementu w układzie współrzędnych `backdrop`.
Item {
    id: g
    property Item backdrop
    property real sx: 0
    property real sy: 0
    property real radius: 18
    property color tint: "#CCFFFFFF"
    property color edge: "transparent"
    property color rim: "transparent"

    ShaderEffectSource {
        id: src
        width: g.width
        height: g.height
        sourceItem: g.backdrop
        sourceRect: Qt.rect(g.sx, g.sy, g.width, g.height)
        visible: false
    }

    Item {
        id: mask
        width: g.width
        height: g.height
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: g.radius; color: "black" }
    }

    MultiEffect {
        anchors.fill: parent
        source: src
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        saturation: 0.7
        maskEnabled: g.radius > 0
        maskSource: mask
    }

    Rectangle {
        anchors.fill: parent
        radius: g.radius
        color: g.tint
        border.width: 1
        border.color: g.edge
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, g.radius - 1)
        color: "transparent"
        border.width: 1
        border.color: g.rim
    }
}
