pragma Singleton
import QtQuick

// Kolory i czcionka Aster (powłoka i aplikacje). Jasny/ciemny motyw idzie za ustawieniem systemu, akcent — za Ustawieniami Aster.
QtObject {
    readonly property bool dark: WindowEffects.forceDark || Qt.styleHints.colorScheme === Qt.ColorScheme.Dark
    readonly property color accent: Config.accent        // wybierany w Ustawieniach → Wygląd
    readonly property string font: "Geist"      // data/fonts/geist (OFL), instalowana razem z systemem

    // Szkło: półprzezroczysty odcień nad rozmyciem z KWin
    readonly property color bar: dark ? Qt.rgba(24 / 255, 24 / 255, 30 / 255, 0.58) : Qt.rgba(250 / 255, 250 / 255, 252 / 255, 0.56)
    readonly property color edge: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.08)
    readonly property color rim: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.55)
    readonly property color shadow: dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.22)
    readonly property color text: dark ? "#ECEEF3" : "#16181D"
    readonly property color text2: dark ? "#A2A9B6" : "#5B6270"
    readonly property color glass: dark ? Qt.rgba(32 / 255, 32 / 255, 38 / 255, 0.72) : Qt.rgba(246 / 255, 246 / 255, 250 / 255, 0.74)
    readonly property color windowGlass: dark ? Qt.rgba(36 / 255, 36 / 255, 42 / 255, 0.78) : Qt.rgba(240 / 255, 240 / 255, 245 / 255, 0.78)
    readonly property color pane: dark ? Qt.rgba(30 / 255, 30 / 255, 34 / 255, 0.97) : Qt.rgba(1, 1, 1, 0.97)
    readonly property color fill: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.06)
    readonly property color danger: dark ? "#FF8A80" : "#C62828"
    readonly property color surface: dark ? "#23262F" : "#FFFFFF"
    readonly property color line: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.08)
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, dark ? 0.32 : 0.14)
    function accentAlpha(a) { return Qt.rgba(accent.r, accent.g, accent.b, a); }
    readonly property color accentText: dark ? Qt.lighter(accent, 1.55) : accent
    readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.07)
}
