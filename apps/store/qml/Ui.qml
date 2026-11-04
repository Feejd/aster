pragma Singleton
import QtQuick
import Aster.Ui

// Język wizualny sklepu: płaskie, zabarwione kafle i wyraźna typografia zamiast zdjęć w gradientach.
// Barwa zadania przychodzi z katalogu, jasność zależy od motywu.
QtObject {
    readonly property int gutter: 36
    readonly property int maxWidth: 1120

    function tile(hue, hover) {
        const h = hue / 360;
        return Theme.dark ? Qt.hsla(h, 0.30, hover ? 0.21 : 0.17, 1) : Qt.hsla(h, 0.62, hover ? 0.90 : 0.93, 1);
    }
    function ink(hue) {
        const h = hue / 360;
        return Theme.dark ? Qt.hsla(h, 0.65, 0.84, 1) : Qt.hsla(h, 0.62, 0.26, 1);
    }
    function tone(t) {
        if (t === "ok") return Theme.dark ? "#6FD8A0" : "#16895A";
        if (t === "warn") return Theme.dark ? "#F2C35B" : "#B26B00";
        if (t === "bad") return Theme.dark ? "#FF8A80" : "#C62828";
        if (t === "info") return Theme.text2;
        return Theme.dark ? "#6A7180" : "#A0A6B2";      // nie sprawdziliśmy
    }
}
