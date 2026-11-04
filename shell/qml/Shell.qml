import QtQuick
import QtQml.Models
import Aster.Shell

// Korzeń powłoki: tworzy jej okna-warstwy. Tapeta i górny pasek są na każdym ekranie (jak w macOS),
// dok, Start i centrum sterowania — na głównym. Podłączenie albo odłączenie monitora tworzy je od nowa.
QtObject {
    id: shell
    property var wallpapers: Instantiator {
        model: Qt.application.screens
        delegate: WallpaperWindow {
            required property var modelData
            screen: modelData
        }
    }
    property var horizons: Instantiator {
        model: Qt.application.screens
        delegate: HorizonWindow {
            required property var modelData
            screen: modelData
            primary: modelData === Qt.application.screens[0]
            controlOpen: controlWin.open
            onStartRequested: { controlWin.close(); startWin.toggle(); }
            onControlRequested: { startWin.close(); controlWin.toggle(); }
        }
    }
    property var clock: ClockWindow {}
    property var start: StartWindow { id: startWin }
    property var control: ControlCenterWindow { id: controlWin }
    property var auth: AuthWindow {}            // hasło administratora (agent polkit)
    property var dock: DockWindow {
        startOpen: startWin.open
        onStartRequested: { controlWin.close(); startWin.toggle(); }
    }

    // Klawisz Super (KWin wywołuje org.kde.plasmashell → activateLauncherMenu)
    property var superKey: Connections {
        target: Platform
        function onLauncherRequested() { controlWin.close(); startWin.toggle(); }
    }
}
