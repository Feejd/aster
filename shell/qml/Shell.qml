import QtQuick
import Aster.Shell

// Korzeń powłoki: tworzy jej okna-warstwy. Na razie jeden ekran (główny).
QtObject {
    id: shell
    property var wallpaper: WallpaperWindow {}
    property var clock: ClockWindow {}
    property var start: StartWindow { id: startWin }
    property var control: ControlCenterWindow { id: controlWin }
    property var dock: DockWindow {
        startOpen: startWin.open
        onStartRequested: { controlWin.close(); startWin.toggle(); }
    }
    property var horizon: HorizonWindow {
        controlOpen: controlWin.open
        onStartRequested: { controlWin.close(); startWin.toggle(); }
        onControlRequested: { startWin.close(); controlWin.toggle(); }
    }

    // Klawisz Super (KWin wywołuje org.kde.plasmashell → activateLauncherMenu)
    property var superKey: Connections {
        target: Platform
        function onLauncherRequested() { controlWin.close(); startWin.toggle(); }
    }
}
