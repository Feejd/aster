pragma Singleton
import QtQuick

// Kolory i czcionka Aster (powłoka i aplikacje). Jasny/ciemny motyw idzie za ustawieniem systemu, akcent — za Ustawieniami Aster.
QtObject {
    readonly property bool dark: WindowEffects.forceDark || Qt.styleHints.colorScheme === Qt.ColorScheme.Dark
    readonly property color accent: Config.accent        // wybierany w Ustawieniach → Wygląd
    readonly property string font: "Geist"      // data/fonts/geist (OFL), instalowana razem z systemem

    // Matowe, pełne powierzchnie: głębię daje odcień i cień, nie przezroczystość
    readonly property color bar: dark ? "#1C1D21" : "#F7F7F5"
    readonly property color edge: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.08)
    readonly property color rim: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.55)
    readonly property color shadow: dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.22)
    readonly property color text: dark ? "#EDEDEA" : "#1B1C20"
    readonly property color text2: dark ? "#A3A4A8" : "#62646B"
    readonly property color glass: dark ? "#232428" : "#F4F4F2"
    // Okno: pasek boczny o ton ciemniejszy od treści
    readonly property color windowGlass: dark ? "#1A1B1F" : "#F1F1EE"
    readonly property color paneGlass: dark ? "#141518" : "#FFFFFF"
    readonly property color pane: dark ? "#232428" : "#FFFFFF"
    readonly property color fill: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.06)
    readonly property color danger: dark ? "#FF8A80" : "#C62828"
    readonly property color surface: dark ? "#23262F" : "#FFFFFF"
    readonly property color line: dark ? "#303136" : "#DEDEDA"
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, dark ? 0.32 : 0.14)
    function accentAlpha(a) { return Qt.rgba(accent.r, accent.g, accent.b, a); }
    readonly property color accentText: dark ? Qt.lighter(accent, 1.55) : accent
    readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.07)
}
