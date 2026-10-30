pragma Singleton
import QtQuick

// Kolory i czcionka powłoki — te same co w prototypie. Jasny/ciemny motyw idzie za ustawieniem systemu.
QtObject {
    readonly property bool dark: Qt.styleHints.colorScheme === Qt.ColorScheme.Dark
    readonly property color accent: "#3456E8"
    readonly property string font: "Inter"

    // Szkło: półprzezroczysty odcień nad rozmyciem z KWin
    readonly property color bar: dark ? Qt.rgba(24 / 255, 24 / 255, 30 / 255, 0.58) : Qt.rgba(250 / 255, 250 / 255, 252 / 255, 0.56)
    readonly property color edge: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.08)
    readonly property color rim: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.55)
    readonly property color shadow: dark ? Qt.rgba(0, 0, 0, 0.45) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.22)
    readonly property color text: dark ? "#ECEEF3" : "#16181D"
    readonly property color text2: dark ? "#A2A9B6" : "#5B6270"
    readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.07)
}
