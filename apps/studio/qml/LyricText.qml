import QtQuick
import Aster.Ui
import Aster.Studio

// Wers z pokolorowaną rymującą końcówką (ten sam kolor — ta sama grupa rymów)
Text {
    id: lt
    property var line: null
    property bool rhymes: true
    readonly property var rhymeColors: ["#E5484D", "#3E8EF7", "#30A46C", "#E38A0B", "#8E4EC6", "#E93D82", "#0D9488"]
    function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
    textFormat: Text.StyledText
    wrapMode: Text.WordWrap
    color: Theme.text
    font.family: Theme.font
    text: {
        const l = lt.line;
        if (!l) return "";
        if (!lt.rhymes || l.rhyme < 0 || l.rhymeAt < 0) return esc(l.text);
        const c = rhymeColors[l.rhyme % rhymeColors.length];
        return esc(l.text.substring(0, l.rhymeAt)) + "<font color=\"" + c + "\"><b>" + esc(l.text.substring(l.rhymeAt)) + "</b></font>";
    }
}
