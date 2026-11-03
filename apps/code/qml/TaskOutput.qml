pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Wyjście zadania (Tasks): wiersze bez kolorów, błędy i ostrzeżenia wyróżnione, wiersz z miejscem
// w pliku (plik:wiersz:kolumna) da się kliknąć. Przewija się za wyjściem, dopóki nie przewiniesz w górę.
Item {
    id: to
    signal openLocation(string path, int line, int col)
    property bool follow: true

    function kind(l) {
        if (/^✓ /.test(l)) return "ok";
        if (/^[✗■] /.test(l)) return "fail";
        if (/^> /.test(l)) return "cmd";
        if (/\b(fatal error|error)\b|Error:|Traceback|FAILED|failed/i.test(l)) return "error";
        if (/\bwarning\b/i.test(l)) return "warning";
        return "";
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.leftMargin: 14; anchors.topMargin: 6
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Tasks.lines
        reuseItems: true
        onCountChanged: if (to.follow) Qt.callLater(list.positionViewAtEnd)
        onMovementEnded: to.follow = atYEnd
        delegate: Text {
            id: ln
            required property string modelData
            readonly property string k: to.kind(modelData)
            readonly property var loc: k === "error" || k === "warning" || /:\d+|line \d+|\(\d+,\d+\)/.test(modelData) ? Tasks.locate(modelData) : ({})
            width: ListView.view.width - 14
            wrapMode: Text.WrapAnywhere
            text: modelData || " "
            color: k === "ok" ? (Theme.dark ? "#56D364" : "#1A7F37") : k === "fail" || k === "error" ? Theme.danger
                 : k === "warning" ? (Theme.dark ? "#E3B341" : "#9A6700") : k === "cmd" ? Theme.accentText : Theme.text
            font.family: "JetBrains Mono"; font.pixelSize: 12
            font.weight: k === "ok" || k === "fail" || k === "cmd" ? Font.DemiBold : Font.Normal
            font.underline: !!ln.loc.path && lnArea.containsMouse
            lineHeight: 1.15
            MouseArea {
                id: lnArea
                anchors.fill: parent
                enabled: !!ln.loc.path
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: to.openLocation(ln.loc.path, ln.loc.line, ln.loc.col)
            }
        }
    }

    Column {
        visible: Tasks.lines.length === 0
        anchors.centerIn: parent
        spacing: 6
        Icon { anchors.horizontalCenter: parent.horizontalCenter; d: Icons.play; size: 26; stroke: 1.6; color: Theme.text2; opacity: 0.6 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Uruchom zadanie: Ctrl+Shift+B"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
    }
}
