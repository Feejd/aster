pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Wyjście zadania (Tasks): wiersze bez kolorów, błędy i ostrzeżenia wyróżnione, wiersz z miejscem
// w pliku (plik:wiersz:kolumna) da się kliknąć. Przewija się za wyjściem, dopóki nie przewiniesz w górę.
// Kilka procesów naraz — lista po lewej (stan, adres serwera, zatrzymaj / uruchom ponownie / usuń).
Item {
    id: to
    signal openLocation(string path, int line, int col)
    signal openPreview(string url)
    property bool follow: true

    function kind(l) {
        if (/^✓ /.test(l)) return "ok";
        if (/^[✗■] /.test(l)) return "fail";
        if (/^> /.test(l)) return "cmd";
        if (/\b(fatal error|error)\b|Error:|Traceback|FAILED|failed/i.test(l)) return "error";
        if (/\bwarning\b/i.test(l)) return "warning";
        return "";
    }

    // Procesy (widoczne, gdy jest więcej niż jeden)
    Item {
        id: procs
        visible: Tasks.processes.length > 1
        width: visible ? Math.min(260, parent.width * 0.3) : 0; height: parent.height
        ListView {
            anchors.fill: parent; anchors.topMargin: 4
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: Tasks.processes
            delegate: Rectangle {
                id: pr
                required property var modelData
                width: ListView.view.width - 10; x: 6; height: pr.modelData.url ? 44 : 30; radius: 7
                color: pr.modelData.id === Tasks.selected ? Theme.accentSoft : prArea.containsMouse ? Theme.hover : "transparent"
                MouseArea { id: prArea; anchors.fill: parent; hoverEnabled: true; onClicked: Tasks.select(pr.modelData.id) }
                Rectangle {
                    x: 10; y: 11
                    width: 8; height: 8; radius: 4
                    color: pr.modelData.running ? (Theme.dark ? "#3FB950" : "#1A7F37") : pr.modelData.exitCode === 0 ? Theme.text2 : Theme.danger
                }
                Text {
                    x: 26; y: 7
                    width: parent.width - 26 - prTools.width - 8
                    elide: Text.ElideRight
                    text: pr.modelData.label
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                }
                Text {
                    visible: !!pr.modelData.url
                    x: 26; y: 24
                    width: parent.width - 34
                    elide: Text.ElideRight
                    text: pr.modelData.url
                    color: Theme.accentText; font.family: Theme.font; font.pixelSize: 11; font.underline: urlArea.containsMouse
                    MouseArea { id: urlArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: to.openPreview(pr.modelData.url) }
                }
                Row {
                    id: prTools
                    anchors.right: parent.right; anchors.rightMargin: 4; y: 3
                    visible: prArea.containsMouse || prHover.hovered
                    HoverHandler { id: prHover }
                    SmallBtn { icon: pr.modelData.running ? "stop" : "reload"; onClicked: pr.modelData.running ? Tasks.stop(pr.modelData.id) : Tasks.rerun(pr.modelData.id) }
                    SmallBtn { visible: !pr.modelData.running; icon: "close"; onClicked: Tasks.remove(pr.modelData.id) }
                }
            }
        }
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }
    }
    component SmallBtn: HoverButton {
        id: sb
        property string icon
        width: 22; height: 22; radius: 6
        Icon { anchors.centerIn: parent; d: Icons[sb.icon] || ""; size: 11; stroke: 2; color: Theme.text2 }
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.leftMargin: procs.width + 14; anchors.topMargin: 6
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
