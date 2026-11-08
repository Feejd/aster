import QtQuick
import QtQuick.Effects

// Chwila między zalogowaniem a pulpitem (ksplashqml): ta sama rozmyta tapeta co na ekranie
// logowania, bez napisów i paska — ekran logowania gaśnie, a pulpit wyłania się z tego samego tła.
Rectangle {
    id: root
    color: "black"
    property int stage                     // ustawia ksplashqml (1…6)

    Image {
        id: wall
        anchors.fill: parent
        source: "file:///usr/share/aster/wallpapers/swit-dark.jpg"
        fillMode: Image.PreserveAspectCrop
        visible: GraphicsInfo.api === GraphicsInfo.Software
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        visible: GraphicsInfo.api !== GraphicsInfo.Software
        blurEnabled: true
        blurMax: 64
        blur: 0.85
        saturation: 0.15
        autoPaddingEnabled: false
    }
    Rectangle {
        anchors.fill: parent
        color: "black"
        // Na końcu przyciemnienie z ekranu logowania znika — tapeta „wyostrza się” w pulpit
        opacity: root.stage >= 5 ? 0 : 0.28
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
    }
}
