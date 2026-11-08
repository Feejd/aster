pragma Singleton
import QtQuick

// Kolory i czcionka Aster (powłoka i aplikacje). Jasny/ciemny motyw idzie za ustawieniem systemu, akcent — za Ustawieniami Aster.
QtObject {
    readonly property bool dark: WindowEffects.forceDark || Qt.styleHints.colorScheme === Qt.ColorScheme.Dark
    readonly property color accent: Config.accent        // wybierany w Ustawieniach → Wygląd
    readonly property string font: "Manrope"     // data/fonts/manrope (OFL): okrągła i spokojna, z polskimi znakami

    // Matowe, pełne powierzchnie: głębię daje odcień i cień, nie przezroczystość
    readonly property color bar: "transparent"   // pasek stanu leży wprost na tapecie
    readonly property color edge: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.08)
    readonly property color rim: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.55)
    readonly property color shadow: dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.22)
    readonly property color text: dark ? "#F2F2F4" : "#141518"
    readonly property color text2: dark ? "#9C9EA6" : "#6A6D75"
    readonly property color glass: dark ? "#1C1D21" : "#FFFFFF"
    // Okno: pasek boczny o ton ciemniejszy od treści
    readonly property color windowGlass: dark ? "#0F1012" : "#F2F3F5"
    readonly property color paneGlass: dark ? "#0F1012" : "#F2F3F5"
    readonly property color pane: dark ? "#1C1D21" : "#FFFFFF"
    readonly property color fill: dark ? "#26272C" : "#E9EBEE"
    readonly property color danger: dark ? "#FF8A80" : "#C62828"
    readonly property color surface: dark ? "#1C1D21" : "#FFFFFF"
    readonly property color line: dark ? "#26272C" : "#E6E7EA"
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, dark ? 0.32 : 0.14)
    function accentAlpha(a) { return Qt.rgba(accent.r, accent.g, accent.b, a); }
    readonly property color accentText: dark ? Qt.lighter(accent, 1.55) : accent
    readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.07)
}
