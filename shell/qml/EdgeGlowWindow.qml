import QtQuick
import QtQuick.Window
import Aster.Shell

// Poświata na krawędziach ekranu, gdy Aster Intelligence myśli (jak przy Siri w Apple Intelligence).
// Warstwa „overlay” na cały ekran, przezroczysta dla myszy i klawiatury; okno istnieje
// tylko wtedy, gdy świeci — poza tym jest schowane i nic nie rysuje.
// flash(): krótki błysk przy otwarciu pola pytania.
Window {
    id: ew
    color: "transparent"
    title: "Poświata"
    visible: false
    flags: Qt.FramelessWindowHint | Qt.WindowTransparentForInput
    width: Screen.width
    height: Screen.height
    readonly property int shotX: 0
    readonly property int shotY: 0

    property bool active: false
    readonly property bool lit: active || flashTimer.running
    property real level: 0

    Component.onCompleted: Platform.makeLayer(ew, "overlay", 1 | 2 | 4 | 8, -1, "none", "aster-intelligence-glow")

    function flash() { flashTimer.restart(); }
    Timer { id: flashTimer; interval: 900 }

    onLitChanged: {
        if (lit) visible = true;
        fade.to = lit ? 1 : 0;
        fade.duration = lit ? 420 : 750;
        fade.restart();
    }
    NumberAnimation {
        id: fade
        target: ew; property: "level"
        easing.type: Easing.OutCubic
        onFinished: if (!ew.lit) ew.visible = false
    }

    // Oddech: światło lekko przygasa i rozjaśnia się, kiedy model pracuje
    property real breath: 1
    SequentialAnimation on breath {
        running: ew.visible
        loops: Animation.Infinite
        NumberAnimation { to: 0.7; duration: 1100; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 1100; easing.type: Easing.InOutSine }
    }

    IntelligenceGlow {
        // Obwódka leży dokładnie przy krawędzi ekranu, światło rozlewa się do środka
        anchors.fill: parent
        anchors.margins: thickness
        radius: 14
        thickness: 3.5
        haloWidth: 30
        haloBlur: 64
        haloStrength: ew.breath
        textureScale: 0.35
        speed: 90
        intensity: ew.level
    }
}
