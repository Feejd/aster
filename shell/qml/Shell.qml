import QtQuick
import Aster.Shell

// Korzeń powłoki: tworzy jej okna-warstwy. Na razie jeden ekran (główny).
QtObject {
    property var wallpaper: WallpaperWindow {}
    property var dock: DockWindow {}
    property var horizon: HorizonWindow {}
}
