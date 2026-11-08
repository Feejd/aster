import QtQuick
import QtQuick.Window
import Aster.Shell
import Aster.Ui

// Tapeta na warstwie tła, pod wszystkimi oknami. Dzień i noc przenikają się przy zmianie motywu.
Window {
    id: wp
    color: "black"
    title: "Tapeta"
    visible: false
    width: Screen.width
    height: Screen.height
    readonly property string variant: Config.wallpaper     // Ustawienia → Tapeta

    Component.onCompleted: {
        Platform.makeLayer(wp, "background", 1 | 2 | 4 | 8, -1, "none", "aster-wallpaper");
        visible = true;
    }

    // Własne zdjęcie (np. „Ustaw jako tapetę” w Zdjęciach) — pełna ścieżka, to samo w jasnym i ciemnym motywie
    readonly property bool custom: variant.startsWith("/")
    function src(mode) {
        if (custom) return "file://" + variant;
        return "file://" + Platform.dataDir + "/wallpapers/" + wp.variant + "-" + mode + ".jpg";
    }

    Image {
        anchors.fill: parent
        source: wp.src("light")
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
    }
    Image {
        anchors.fill: parent
        source: wp.src("dark")
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        opacity: Theme.dark && !wp.custom ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
}
