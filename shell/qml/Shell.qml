import QtQuick
import Aster.Shell

// Korzeń powłoki: tworzy jej okna-warstwy. Na razie jeden ekran (główny).
QtObject {
    id: shell
    property var wallpaper: WallpaperWindow {}
    property var start: StartWindow { id: startWin }
    property var dock: DockWindow {
        startOpen: startWin.open
        onStartRequested: startWin.toggle()
    }
    property var horizon: HorizonWindow {}

    // Klawisz Super (KWin wywołuje org.kde.plasmashell → activateLauncherMenu)
    property var superKey: Connections {
        target: Platform
        function onLauncherRequested() { startWin.toggle(); }
    }
}
