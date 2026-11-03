pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Podgląd różnic jednego pliku (git diff) nad edytorem: numery wierszy starej i nowej wersji,
// dodane na zielono, usunięte na czerwono. Esc albo × zamyka; „Dodaj” / „Wycofaj” — cały plik,
// przyciski przy nagłówku fragmentu — tylko ten fragment (dodaj, wycofaj, odrzuć).
// Tryb zatwierdzenia (z historii): zmiany pliku w jednym zatwierdzeniu i „Przywróć tę wersję”.
Rectangle {
    id: dv
    property bool shown: false
    property string path
    property bool staged: false
    property var rows: []
    property string fontFamily: "JetBrains Mono"
    property real fontSize: 13
    signal openFile(string path)
    signal discardHunk(string path, int index)
    signal restoreVersion(string path, string hash, string rel)
    property string commit: ""                  // pusty — zmiany robocze; inaczej hash zatwierdzenia
    property string commitRel: ""
    property string commitTitle: ""

    visible: shown
    color: Theme.dark ? "#090A0D" : "#FFFFFF"
    // Kliknięcia i kółko nie przechodzą do edytora pod spodem
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (w) => w.accepted = true }

    function open(p, isStaged) {
        commit = "";
        path = p;
        staged = isStaged;
        reload();
        shown = true;
        list.positionViewAtBeginning();
    }
    function openCommit(p, rel, hash, title) {
        commit = hash;
        commitRel = rel;
        commitTitle = title;
        path = p;
        rows = Project.commitDiff(hash, rel);
        shown = true;
        list.positionViewAtBeginning();
    }
    function close() { shown = false; }
    function reload() { if (!commit) rows = Project.diff(path, staged); }

    // Po dodaniu / wycofaniu plik może zniknąć z tej strony różnic
    Connections {
        target: Project
        function onGitChanged() { if (dv.shown) dv.reload(); }
    }

    readonly property int added: rows.filter(r => r.kind === "+").length
    readonly property int removed: rows.filter(r => r.kind === "-").length

    Item {
        id: header
        width: parent.width; height: 44
        FileIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; name: Project.fileName(dv.path); size: 16 }
        Column {
            x: 42; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 42 - btns.width - 20
            Text {
                width: parent.width; elide: Text.ElideMiddle
                text: Project.fileName(dv.path) + "  —  " + (dv.commit ? dv.commitTitle : dv.staged ? "dodane do zatwierdzenia" : "zmiany względem zatwierdzonej wersji")
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
            }
            Text {
                textFormat: Text.StyledText
                text: "<font color=\"" + (Theme.dark ? "#3FB950" : "#1A7F37") + "\">+" + dv.added + "</font>  <font color=\"" + Theme.danger + "\">−" + dv.removed + "</font>  ·  " + (dv.commit ? dv.commit.slice(0, 8) + "  ·  " : "") + Project.relative(dv.path)
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
            }
        }
        Row {
            id: btns
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Pill { text: "Otwórz plik"; visible: Project.exists(dv.path); onClicked: { dv.close(); dv.openFile(dv.path); } }
            Pill {
                visible: !!dv.commit
                text: "Przywróć tę wersję"
                onClicked: { dv.close(); dv.restoreVersion(dv.path, dv.commit, dv.commitRel); }
            }
            Pill {
                visible: !dv.commit
                text: dv.staged ? "Wycofaj" : "Dodaj"
                onClicked: { if (dv.staged) Project.unstage([dv.path]); else Project.stage([dv.path]); dv.close(); }
            }
            HoverButton {
                width: 30; height: 30; radius: 8
                onClicked: dv.close()
                Icon { anchors.centerIn: parent; d: Icons.close; size: 13; stroke: 2; color: Theme.text2 }
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
    }

    FontMetrics { id: fm; font.family: dv.fontFamily; font.pixelSize: dv.fontSize; font.features: { "liga": 0, "calt": 0 } }
    readonly property real numW: fm.averageCharacterWidth * 5 + 10

    ListView {
        id: list
        y: header.height
        width: parent.width; height: parent.height - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: dv.rows
        reuseItems: true
        delegate: Rectangle {
            id: line
            required property var modelData
            width: ListView.view.width
            height: modelData.kind === "@" ? 26 : Math.ceil(fm.height * 1.35)
            color: modelData.kind === "+" ? Qt.rgba(0.25, 0.73, 0.31, Theme.dark ? 0.16 : 0.13)
                 : modelData.kind === "-" ? Qt.rgba(0.97, 0.32, 0.29, Theme.dark ? 0.16 : 0.11)
                 : modelData.kind === "@" ? Theme.accentAlpha(Theme.dark ? 0.12 : 0.06) : "transparent"
            Text {
                visible: line.modelData.kind !== "@"
                width: dv.numW; horizontalAlignment: Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
                text: line.modelData.old !== undefined ? line.modelData.old : ""
                color: Theme.text2; opacity: 0.6; font: fm.font
            }
            Text {
                visible: line.modelData.kind !== "@"
                x: dv.numW; width: dv.numW; horizontalAlignment: Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
                text: line.modelData.new !== undefined ? line.modelData.new : ""
                color: Theme.text2; opacity: 0.6; font: fm.font
            }
            // Fragment: dodaj / wycofaj / odrzuć tylko ten kawałek
            Row {
                visible: line.modelData.kind === "@" && !dv.commit
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                HunkBtn {
                    visible: !dv.staged
                    text: "Odrzuć"; danger: true
                    onClicked: dv.discardHunk(dv.path, line.modelData.hunk)
                }
                HunkBtn {
                    text: dv.staged ? "Wycofaj fragment" : "Dodaj fragment"
                    onClicked: Project.applyHunk(dv.path, dv.staged, line.modelData.hunk, dv.staged ? "unstage" : "stage")
                }
            }
            Text {
                x: line.modelData.kind === "@" ? 16 : dv.numW * 2 + 14
                anchors.verticalCenter: parent.verticalCenter
                text: line.modelData.kind === "@" ? "⋯  " + (line.modelData.text || "") : (line.modelData.kind === " " ? "  " : line.modelData.kind + " ") + line.modelData.text.replace(/\t/g, "    ")
                color: line.modelData.kind === "@" ? Theme.text2 : line.modelData.kind === "+" ? (Theme.dark ? "#7EE0A0" : "#116329")
                     : line.modelData.kind === "-" ? (Theme.dark ? "#FF8B96" : "#A40E26") : Theme.text
                font: fm.font
            }
        }
    }

    Text {
        visible: dv.rows.length === 0
        anchors.centerIn: parent
        text: "Brak różnic do pokazania"
        color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
    }

    component HunkBtn: HoverButton {
        id: hb
        property string text
        property bool danger: false
        width: hbText.implicitWidth + 16; height: 20; radius: 6
        baseColor: Theme.fill
        Text { id: hbText; anchors.centerIn: parent; text: hb.text; color: hb.danger ? Theme.danger : Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
    }
    component Pill: HoverButton {
        id: pill
        property string text
        width: pillText.implicitWidth + 24; height: 30; radius: 15
        baseColor: Theme.fill
        Text { id: pillText; anchors.centerIn: parent; text: pill.text; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
    }
}
