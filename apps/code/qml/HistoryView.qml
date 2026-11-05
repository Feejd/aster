pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Historia w pasku bocznym (jak „Oś czasu” w VS Code): każdy zapis pliku (historia lokalna, działa bez gita)
// i zatwierdzenia zmieniające bieżący plik
// (git log --follow) — klik pokazuje zmiany pliku w tym zatwierdzeniu; „Pliki” — całe zatwierdzenie
// z listą zmienionych plików (także z ostatnich zatwierdzeń w widoku zmian).
Item {
    id: hv
    property string path                       // bieżący plik edytora
    property var gitEntries: []
    property var localEntries: []
    // Zapisy i zatwierdzenia na jednej osi czasu, od najnowszych
    readonly property var entries: localEntries.slice(0, 40).map(l => ({ local: true, id: l.id, time: l.time, subject: "Zapisano", hash: "", author: "", added: 0, removed: 0, rel: "" }))
        .concat(gitEntries).sort((a, b) => b.time - a.time)
    property bool loading: false
    property var commitData: null              // otwarte zatwierdzenie albo null — historia pliku
    property string lastHead
    signal showDiff(string path, string rel, string hash, string title)
    signal showLocal(string path, string id, string title)

    function refresh() {
        localEntries = path ? Project.localHistory(path) : [];
        if (!path || !Project.isGit) { gitEntries = []; return; }
        loading = true;
        Project.requestHistory(path);
    }
    function openCommit(hash) { commitData = Project.commitInfo(hash); }
    onPathChanged: if (visible && !commitData) refresh()
    onVisibleChanged: if (visible) refresh()
    Connections {
        target: Project
        function onHistoryReady(p, list) { if (p === hv.path) { hv.gitEntries = list; hv.loading = false; } }
        function onLocalHistoryChanged(p) { if (p === hv.path && hv.visible) hv.localEntries = Project.localHistory(p); }
        // Nowe zatwierdzenie (HEAD) — odśwież
        function onGitChanged() { if (Project.head !== hv.lastHead) { hv.lastHead = Project.head; if (hv.visible && !hv.commitData) hv.refresh(); } }
    }
    function ago(t) {
        const s = Math.max(0, Date.now() / 1000 - t);
        if (s < 60) return "przed chwilą";
        if (s < 3600) return Math.floor(s / 60) + " min temu";
        if (s < 86400) return Math.floor(s / 3600) + " godz. temu";
        const d = Math.floor(s / 86400);
        if (d === 1) return "wczoraj";
        if (d < 30) return d + " dni temu";
        return new Date(t * 1000).toLocaleDateString(Qt.locale("pl_PL"), "d MMM yyyy");
    }
    readonly property color addColor: Theme.dark ? "#3FB950" : "#1A7F37"

    // ——— Historia pliku ———
    Item {
        anchors.fill: parent
        visible: !hv.commitData
        Item {
            id: head
            width: parent.width; height: 34
            FileIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; name: Project.fileName(hv.path); size: 14; visible: !!hv.path }
            Text {
                x: 38; width: parent.width - 38 - 40
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideMiddle
                text: hv.path ? Project.fileName(hv.path) : ""
                color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
            }
            HoverButton {
                anchors.right: parent.right; anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 24; radius: 6
                onClicked: hv.refresh()
                Icon { anchors.centerIn: parent; d: Icons.reload; size: 13; color: Theme.text2 }
            }
        }
        ListView {
            y: head.height
            width: parent.width; height: parent.height - y
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: hv.entries
            delegate: Item {
                id: en
                required property var modelData
                required property int index
                width: ListView.view.width; height: 50
                Rectangle { anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6; radius: 8; color: enArea.containsMouse ? Theme.hover : "transparent" }
                Rectangle { x: 21; y: en.index === 0 ? parent.height / 2 : 0; width: 2; height: en.index === 0 ? parent.height / 2 : parent.height; color: Theme.line }
                Rectangle {
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    width: 12; height: 12; radius: 6
                    color: en.index === 0 ? Theme.accent : Theme.surface
                    border.width: 2; border.color: en.modelData.local ? Theme.text2 : Theme.accent
                }
                Column {
                    x: 38; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 38 - filesBtn.width - 14
                    spacing: 2
                    Text { width: parent.width; elide: Text.ElideRight; text: en.modelData.subject; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        textFormat: Text.StyledText
                        text: en.modelData.local ? hv.ago(en.modelData.time)
                            : en.modelData.author + " · " + hv.ago(en.modelData.time) + "  <font color=\"" + hv.addColor + "\">+" + en.modelData.added
                              + "</font> <font color=\"" + Theme.danger + "\">−" + en.modelData.removed + "</font>"
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                    }
                }
                MouseArea {
                    id: enArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (en.modelData.local) hv.showLocal(hv.path, en.modelData.id, "zapis z " + new Date(en.modelData.time * 1000).toLocaleString(Qt.locale("pl_PL"), "d MMM, HH:mm"));
                        else hv.showDiff(hv.path, en.modelData.rel, en.modelData.hash, en.modelData.subject);
                    }
                }
                HoverButton {
                    id: filesBtn
                    visible: !en.modelData.local && (enArea.containsMouse || hovered)
                    anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: filesText.implicitWidth + 14; height: 22; radius: 6
                    baseColor: Theme.fill
                    onClicked: hv.openCommit(en.modelData.hash)
                    Text { id: filesText; anchors.centerIn: parent; text: "Pliki"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
                }
            }
        }
        Text {
            visible: !hv.loading && hv.entries.length === 0
            anchors.centerIn: parent
            width: parent.width - 40; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: !hv.path ? "Otwórz plik, żeby zobaczyć jego historię" : "Każdy zapis tego pliku pojawi się tutaj — można do niego wrócić"
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
        }
    }

    // ——— Zatwierdzenie ———
    Item {
        anchors.fill: parent
        visible: !!hv.commitData
        Column {
            id: chead
            x: 12; width: parent.width - 24
            spacing: 6
            HoverButton {
                width: backRow.implicitWidth + 14; height: 26; radius: 7
                onClicked: hv.commitData = null
                Row {
                    id: backRow
                    anchors.centerIn: parent
                    spacing: 4
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.back; size: 12; stroke: 2; color: Theme.text2 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Historia pliku"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                }
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap
                text: hv.commitData ? hv.commitData.subject : ""
                color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            }
            Text {
                visible: !!(hv.commitData && hv.commitData.body)
                width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 8; elide: Text.ElideRight
                text: hv.commitData ? hv.commitData.body : ""
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.15
            }
            Row {
                spacing: 6
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: hv.commitData ? hv.commitData.author + " · " + hv.ago(hv.commitData.time) : ""
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                }
                HoverButton {
                    width: hashText.implicitWidth + 12; height: 20; radius: 5
                    baseColor: Theme.fill
                    onClicked: { Project.copyText(hv.commitData.hash); Project.message("Skopiowano " + hv.commitData.short); }
                    Text { id: hashText; anchors.centerIn: parent; text: hv.commitData ? hv.commitData.short : ""; color: Theme.text2; font.family: "JetBrains Mono"; font.pixelSize: 11 }
                }
            }
            Text {
                topPadding: 6
                text: hv.commitData ? "ZMIENIONE PLIKI · " + hv.commitData.files.length : ""
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 0.4
            }
        }
        ListView {
            y: chead.height + 6
            width: parent.width; height: parent.height - y
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: hv.commitData ? hv.commitData.files : []
            delegate: Item {
                id: cf
                required property var modelData
                width: ListView.view.width; height: 28
                Rectangle { anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6; radius: 7; color: cfArea.containsMouse ? Theme.hover : "transparent" }
                FileIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; name: cf.modelData.name; size: 15 }
                Text {
                    id: cfName
                    x: 40; anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width - 40 - stat.width - 20)
                    elide: Text.ElideRight
                    text: cf.modelData.name
                    color: cf.modelData.exists ? Theme.text : Theme.text2; font.family: Theme.font; font.pixelSize: 13
                    font.strikeout: !cf.modelData.exists
                }
                Text {
                    anchors.left: cfName.right; anchors.leftMargin: 6
                    anchors.right: stat.left; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideLeft
                    text: cf.modelData.dir; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                }
                Text {
                    id: stat
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.StyledText
                    text: cf.modelData.added < 0 ? "plik binarny" : "<font color=\"" + hv.addColor + "\">+" + cf.modelData.added + "</font> <font color=\"" + Theme.danger + "\">−" + cf.modelData.removed + "</font>"
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                }
                MouseArea {
                    id: cfArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: if (cf.modelData.added >= 0) hv.showDiff(cf.modelData.path, cf.modelData.rel, hv.commitData.hash, hv.commitData.subject)
                }
            }
        }
    }
}
