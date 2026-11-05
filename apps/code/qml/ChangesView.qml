pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Zmiany w repozytorium gita (jak „Kontrola źródła” w VS Code): gałąź i synchronizacja z serwerem,
// opis zmian i „Zatwierdź” (Ctrl+Enter), pliki dodane do zatwierdzenia i pozostałe zmiany
// (+ dodaj, − wycofaj, ↶ odrzuć), ostatnie zatwierdzenia. Klik w plik — podgląd różnic.
Item {
    id: cv
    signal openFile(string path)
    signal showDiff(string path, bool staged)
    signal discardRequested(var paths)
    signal pickBranch()
    signal publishRequested()
    signal showCommit(string hash)
    property bool amend: false

    function statusColor(s) {
        if (s === "A" || s === "U") return Theme.dark ? "#3FB950" : "#1A7F37";
        if (s === "D" || s === "C") return Theme.dark ? "#F85149" : "#CF222E";
        if (s === "R") return Theme.dark ? "#58A6FF" : "#0969DA";
        return Theme.dark ? "#D29922" : "#9A6700";
    }
    function ago(t) {
        const s = Math.max(0, Date.now() / 1000 - t);
        if (s < 60) return "przed chwilą";
        if (s < 3600) return Math.floor(s / 60) + " min temu";
        if (s < 86400) return Math.floor(s / 3600) + " godz. temu";
        const d = Math.floor(s / 86400);
        if (d === 1) return "wczoraj";
        if (d < 7) return d + " dni temu";
        return new Date(t * 1000).toLocaleDateString(Qt.locale("pl_PL"), "d.MM.yyyy");
    }
    readonly property var staged: Project.changes.filter(c => !!c.index)
    readonly property var unstaged: Project.changes.filter(c => !!c.work && c.work !== "C")
    // Łączenie z konfliktami — opis zatwierdzenia z .git/MERGE_MSG
    Connections {
        target: Project
        function onGitChanged() { if (Project.merging && !msg.text) msg.text = Project.mergeMessage(); }
    }
    function focusMessage() { msg.forceActiveFocus(); }
    function setMessage(t) { msg.text = t; }
    readonly property var conflicted: Project.changes.filter(c => c.work === "C")
    function commitNow() {
        if (Project.gitBusy) return;
        // Z nierozwiązanymi konfliktami zatwierdzenie zapisałoby znaczniki <<<<<<< w plikach
        if (conflicted.length) { Project.gitDone("commit", false, "Najpierw rozwiąż konflikty i dodaj pliki (+): " + conflicted.map(c => c.name).join(", ")); return; }
        Project.commit(msg.text, amend, staged.length === 0);
    }
    Connections {
        target: Project
        function onGitDone(op, ok, message) {
            if (op === "commit" && ok) { msg.text = ""; cv.amend = false; }
        }
    }

    readonly property var rows: {
        const out = [];
        if (conflicted.length) {
            out.push({ kind: "header", title: "KONFLIKTY", count: conflicted.length, which: "conflict" });
            conflicted.forEach(c => out.push(Object.assign({ kind: "file", which: "conflict", letter: "C" }, c)));
        }
        if (staged.length) {
            out.push({ kind: "header", title: "DODANE DO ZATWIERDZENIA", count: staged.length, which: "staged" });
            staged.forEach(c => out.push(Object.assign({ kind: "file", which: "staged", letter: c.index }, c)));
        }
        out.push({ kind: "header", title: "ZMIANY", count: unstaged.length, which: "work" });
        unstaged.forEach(c => out.push(Object.assign({ kind: "file", which: "work", letter: c.work }, c)));
        if (Project.commits.length) {
            out.push({ kind: "header", title: "OSTATNIE ZATWIERDZENIA", count: 0, which: "log" });
            Project.commits.forEach(c => out.push(Object.assign({ kind: "commit" }, c)));
        }
        return out;
    }

    Column {
        id: head
        x: 10; width: parent.width - 20
        spacing: 8
        visible: Project.isGit

        // Trwa łączenie gałęzi
        Rectangle {
            visible: Project.merging
            width: parent.width; height: mergeCol.implicitHeight + 20; radius: 10
            color: Qt.rgba(0.89, 0.55, 0.1, Theme.dark ? 0.18 : 0.12)
            Column {
                id: mergeCol
                x: 12; y: 10; width: parent.width - 24
                spacing: 8
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    text: cv.conflicted.length ? "Łączenie gałęzi: konflikty w " + cv.conflicted.length + (cv.conflicted.length === 1 ? " pliku" : " plikach") + ". Wybierz w edytorze, którą wersję zostawić, zapisz i dodaj plik (+)."
                                               : "Konflikty rozwiązane — zatwierdź, żeby zakończyć łączenie."
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.15
                }
                HoverButton {
                    width: abortText.implicitWidth + 20; height: 26; radius: 7
                    baseColor: Theme.fill
                    onClicked: Project.mergeAbort()
                    Text { id: abortText; anchors.centerIn: parent; text: "Przerwij łączenie"; color: Theme.danger; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                }
            }
        }

        // Gałąź i synchronizacja
        Rectangle {
            width: parent.width; height: 40; radius: 10
            color: Theme.fill
            Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; d: Icons.gitBranch; size: 16; color: Theme.accentText }
            Text {
                x: 36; width: parent.width - 36 - syncBtn.width - 16
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: Project.branch || "—"
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: cv.pickBranch() }
            }
            HoverButton {
                id: syncBtn
                anchors.right: parent.right; anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                width: syncRow.implicitWidth + 16; height: 30; radius: 8
                enabled: !Project.gitBusy
                readonly property string mode: Project.behind > 0 ? "pull" : (Project.ahead > 0 || !Project.upstream) ? "push" : "fetch"
                onClicked: {
                    if (mode === "pull") Project.pull();
                    else if (mode === "push") { if (Project.hasRemote()) Project.push(); else cv.publishRequested(); }
                    else Project.fetch();
                }
                Row {
                    id: syncRow
                    anchors.centerIn: parent
                    spacing: 5
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        d: syncBtn.mode === "pull" ? Icons.download : syncBtn.mode === "push" ? Icons.upload : Icons.reload
                        size: 14; color: Theme.text2
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Project.gitBusy === "push" ? "Wysyłam…" : Project.gitBusy === "pull" ? "Pobieram…" : Project.gitBusy === "fetch" ? "Sprawdzam…"
                            : syncBtn.mode === "pull" ? "Pobierz " + Project.behind
                            : syncBtn.mode === "push" ? (Project.upstream ? "Wyślij " + Project.ahead : "Opublikuj")
                            : "Synchronizuj"
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 }
                    }
                }
            }
        }

        // Opis zmian
        Rectangle {
            width: parent.width
            height: Math.max(62, Math.min(150, msg.contentHeight + 20))
            radius: 10
            color: Theme.fill
            border.width: msg.activeFocus ? 1.5 : 0
            border.color: Theme.accent
            Flickable {
                id: msgFlick
                x: 10; y: 9
                width: parent.width - 20; height: parent.height - 18
                contentHeight: msg.contentHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                TextEdit {
                    id: msg
                    width: msgFlick.width
                    wrapMode: TextEdit.Wrap
                    color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                    font.family: Theme.font; font.pixelSize: 13
                    Keys.onPressed: (e) => {
                        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ControlModifier)) { cv.commitNow(); e.accepted = true; }
                    }
                    Text {
                        visible: !msg.text && !msg.activeFocus
                        width: parent.width; wrapMode: Text.Wrap
                        text: cv.amend ? "Opis poprzedniego zatwierdzenia (bez zmian — zostaje)" : "Opis zmian (Ctrl+Enter — zatwierdź)"
                        color: Theme.text2; font: msg.font
                    }
                }
            }
        }

        Item {
            width: parent.width; height: 32
            HoverButton {
                id: commitBtn
                width: parent.width - amendBtn.width - 6; height: 32; radius: 9
                enabled: !Project.gitBusy && (Project.changes.length > 0 || cv.amend)
                opacity: enabled ? 1 : 0.45
                baseColor: Theme.accent
                color: hovered && enabled ? Qt.darker(Theme.accent, 1.1) : baseColor
                onClicked: cv.commitNow()
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.check; size: 15; stroke: 2; color: "white" }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Project.gitBusy === "commit" ? "Zatwierdzam…" : cv.amend ? "Popraw ostatnie" : "Zatwierdź"
                        color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                    }
                }
            }
            HoverButton {
                id: amendBtn
                anchors.right: parent.right
                width: 32; height: 32; radius: 9
                visible: Project.commits.length > 0
                baseColor: cv.amend ? Theme.accentSoft : Theme.fill
                onClicked: {
                    cv.amend = !cv.amend;
                    if (cv.amend && !msg.text) msg.text = Project.lastCommitMessage();
                }
                Icon { anchors.centerIn: parent; d: Icons.pencil; size: 14; color: cv.amend ? Theme.accentText : Theme.text2 }
            }
        }
        Text {
            visible: cv.staged.length === 0 && cv.unstaged.length > 0 && !cv.amend
            width: parent.width; leftPadding: 4
            wrapMode: Text.Wrap
            text: "Nic nie dodano — zatwierdzone zostaną wszystkie zmiany"
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
        }
    }

    ListView {
        visible: Project.isGit
        y: head.height + 10
        width: parent.width; height: parent.height - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: cv.rows
        delegate: Item {
            id: row
            required property var modelData
            width: ListView.view.width
            height: modelData.kind === "header" ? 32 : modelData.kind === "commit" ? 40 : 28

            // Nagłówek sekcji
            Item {
                visible: row.modelData.kind === "header"
                anchors.fill: parent
                Text {
                    x: 16; anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                    text: row.modelData.title + (row.modelData.count ? " · " + row.modelData.count : "")
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 0.4
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                    visible: row.modelData.which !== "log" && row.modelData.which !== "conflict" && row.modelData.count > 0
                    RowBtn {
                        visible: row.modelData.which === "work"
                        icon: "undo"
                        onClicked: cv.discardRequested(cv.unstaged.map(c => c.path))
                    }
                    RowBtn {
                        icon: row.modelData.which === "staged" ? "minus" : "plus"
                        onClicked: {
                            if (row.modelData.which === "staged") Project.unstage(cv.staged.map(c => c.path));
                            else Project.stage(cv.unstaged.map(c => c.path));
                        }
                    }
                }
            }

            // Plik
            Item {
                visible: row.modelData.kind === "file"
                anchors.fill: parent
                Rectangle {
                    anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                    radius: 7
                    color: fileArea.containsMouse ? Theme.hover : "transparent"
                }
                MouseArea {
                    id: fileArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (row.modelData.isDir) return;
                        // Plik z konfliktem otwiera się w edytorze — tam są przyciski wyboru wersji
                        if (row.modelData.which === "conflict") cv.openFile(row.modelData.path);
                        else cv.showDiff(row.modelData.path, row.modelData.which === "staged");
                    }
                    onDoubleClicked: if (row.modelData.letter !== "D" && !row.modelData.isDir) cv.openFile(row.modelData.path)
                }
                FileIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; name: row.modelData.name || ""; isDir: !!row.modelData.isDir; size: 15 }
                Text {
                    id: nm
                    x: 40; anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width - 40 - 90)
                    elide: Text.ElideRight
                    text: row.modelData.name || ""
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                    font.strikeout: row.modelData.letter === "D"
                }
                Text {
                    anchors.left: nm.right; anchors.leftMargin: 6
                    anchors.right: tools.left; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideLeft
                    text: row.modelData.dir || ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                }
                Row {
                    id: tools
                    anchors.right: letter.left; anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    visible: fileArea.containsMouse || hoverTools.hovered
                    HoverHandler { id: hoverTools }
                    RowBtn {
                        visible: row.modelData.letter !== "D" && !row.modelData.isDir
                        icon: "doc"
                        onClicked: cv.openFile(row.modelData.path)
                    }
                    RowBtn {
                        visible: row.modelData.which === "work"
                        icon: "undo"
                        onClicked: cv.discardRequested([row.modelData.path])
                    }
                    RowBtn {
                        icon: row.modelData.which === "staged" ? "minus" : "plus"
                        onClicked: {
                            if (row.modelData.which === "staged") Project.unstage([row.modelData.path]);
                            else Project.stage([row.modelData.path]);
                        }
                    }
                }
                Text {
                    id: letter
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    text: row.modelData.letter || ""
                    color: cv.statusColor(row.modelData.letter)
                    font.family: "JetBrains Mono"; font.pixelSize: 12; font.weight: Font.Bold
                }
            }

            // Zatwierdzenie z historii — klik: zmienione pliki
            Item {
                visible: row.modelData.kind === "commit"
                anchors.fill: parent
                Rectangle { anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6; radius: 7; color: commitArea.containsMouse ? Theme.hover : "transparent" }
                MouseArea { id: commitArea; anchors.fill: parent; hoverEnabled: true; onClicked: cv.showCommit(row.modelData.hash) }
                Rectangle { x: 20; y: 0; width: 2; height: parent.height; color: Theme.line }
                Rectangle {
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    width: 10; height: 10; radius: 5
                    color: Theme.surface
                    border.width: 2; border.color: Theme.accent
                }
                Column {
                    x: 36; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 36 - 12
                    spacing: 1
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: row.modelData.subject || ""
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: (row.modelData.hash || "") + " · " + (row.modelData.author || "") + " · " + (row.modelData.time ? cv.ago(row.modelData.time) : "")
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                    }
                }
            }
        }
    }

    Column {
        visible: !Project.isGit
        anchors.centerIn: parent
        width: parent.width - 40
        spacing: 8
        Icon { anchors.horizontalCenter: parent.horizontalCenter; d: Icons.gitBranch; size: 34; stroke: 1.4; color: Theme.text2; opacity: 0.6 }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: "Git zapamiętuje wersje projektu i pozwala je publikować. Zmiany pojawią się tutaj."
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
        }
        HoverButton {
            anchors.horizontalCenter: parent.horizontalCenter
            width: initText.implicitWidth + 28; height: 34; radius: 9
            baseColor: Theme.accent
            onClicked: if (!Project.initGit()) Project.message("Nie udało się włączyć gita — czy jest zainstalowany?")
            Text { id: initText; anchors.centerIn: parent; text: "Włącz wersje (git)"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
        }
    }

    component RowBtn: HoverButton {
        id: rb
        property string icon
        width: 24; height: 24; radius: 6
        Icon { anchors.centerIn: parent; d: Icons[rb.icon] || ""; size: 13; stroke: 2; color: Theme.text2 }
    }
}
