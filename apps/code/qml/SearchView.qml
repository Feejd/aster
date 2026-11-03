pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Szukanie w całym projekcie (Ctrl+Shift+F): pole z opcjami (wielkość liter, całe słowa, wyrażenie
// regularne), wyniki pogrupowane według plików — klik otwiera plik w miejscu trafienia. Zamiana: pole
// „Zamień na” (grupy $1 przy wyrażeniach), podgląd w wynikach, zamiana wszystkiego, w pliku albo jednego trafienia.
Item {
    id: sv
    property bool matchCase: false
    property bool wholeWord: false
    property bool regex: false
    property var collapsed: ({})
    signal openMatch(string path, int line, int col, int length)
    signal replaceAllRequested()
    signal replaceFileRequested(string path)
    signal replaceMatchRequested(string path, int line, int col)
    property bool replaceOpen: false
    readonly property string query: field.text
    readonly property string replacement: replaceField.text

    function focusField(text) {
        if (text) field.text = text;
        field.forceActiveFocus();
        field.selectAll();
    }
    // Treść niezapisanych kart (ścieżka → tekst) — szukanie widzi to, co w edytorze, nie na dysku
    property var buffers: () => ({})
    function run() { Project.search(field.text, matchCase, wholeWord, regex, buffers()); }
    function setReplacement(t) { replaceOpen = true; replaceField.text = t; }

    // Wyniki jako płaska lista: nagłówek pliku, potem jego trafienia
    readonly property var rows: {
        const out = [];
        const res = Project.results;
        for (let i = 0; i < res.length; ++i) {
            const f = res[i];
            const closed = !!collapsed[f.path];
            out.push({ kind: "file", path: f.path, name: f.name, dir: f.dir, count: f.matches.length, closed: closed });
            if (closed) continue;
            for (let k = 0; k < f.matches.length; ++k) {
                const m = f.matches[k];
                out.push({ kind: "match", path: f.path, line: m.line, col: m.col, length: m.length, before: m.before, match: m.match, after: m.after });
            }
        }
        return out;
    }

    Timer { id: debounce; interval: 300; onTriggered: sv.run() }

    Column {
        id: head
        x: 10; y: 0
        width: parent.width - 20
        spacing: 6
        Item {
        width: parent.width; height: 34
        // Strzałka: pokaż / schowaj zamianę (jak w VS Code)
        HoverButton {
            x: 0; y: 5
            width: 22; height: 24; radius: 6
            onClicked: { sv.replaceOpen = !sv.replaceOpen; if (sv.replaceOpen) Qt.callLater(() => replaceField.forceActiveFocus()); }
            Icon { anchors.centerIn: parent; d: sv.replaceOpen ? Icons.chevronDown : Icons.chevronRight; size: 12; stroke: 2; color: Theme.text2 }
        }
        Rectangle {
            id: findBox
            x: 26; width: parent.width - 26; height: 34; radius: 9
            color: Theme.fill
            border.width: field.activeFocus ? 1.5 : 0
            border.color: Theme.accent
            Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 15; color: Theme.text2 }
            TextInput {
                id: field
                x: 32; width: parent.width - 32 - opts.width - 6
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                font.family: Theme.font; font.pixelSize: 13
                clip: true
                onTextChanged: debounce.restart()
                onAccepted: { debounce.stop(); sv.run(); }
                Keys.onEscapePressed: { text = ""; }
                Text { anchors.verticalCenter: parent.verticalCenter; visible: !field.text; text: "Szukaj w projekcie"; color: Theme.text2; font: field.font }
            }
            Row {
                id: opts
                anchors.right: parent.right; anchors.rightMargin: 3
                anchors.verticalCenter: parent.verticalCenter
                Opt { text: "Aa"; on: sv.matchCase; onClicked: { sv.matchCase = !sv.matchCase; sv.run(); } }
                Opt { text: "ab"; underline: true; on: sv.wholeWord; onClicked: { sv.wholeWord = !sv.wholeWord; sv.run(); } }
                Opt { text: ".*"; on: sv.regex; onClicked: { sv.regex = !sv.regex; sv.run(); } }
            }
        }
        }
        Item {
            visible: sv.replaceOpen
            x: 26; width: parent.width - 26; height: 34
            Rectangle {
                width: parent.width - replaceAllBtn.width - 6; height: 34; radius: 9
                color: Theme.fill
                border.width: replaceField.activeFocus ? 1.5 : 0
                border.color: Theme.accent
                Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.pencil; size: 14; color: Theme.text2 }
                TextInput {
                    id: replaceField
                    x: 32; width: parent.width - 40
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                    font.family: Theme.font; font.pixelSize: 13
                    clip: true
                    onAccepted: if (Project.resultCount) sv.replaceAllRequested()
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: !replaceField.text; text: sv.regex ? "Zamień na ($1 — grupa)" : "Zamień na"; color: Theme.text2; font: replaceField.font }
                }
            }
            HoverButton {
                id: replaceAllBtn
                anchors.right: parent.right
                width: 34; height: 34; radius: 9
                enabled: Project.resultCount > 0 && !Project.searching
                opacity: enabled ? 1 : 0.4
                baseColor: Theme.fill
                onClicked: sv.replaceAllRequested()
                Icon { anchors.centerIn: parent; d: Icons.check; size: 15; stroke: 2; color: Theme.text }
            }
        }
        Text {
            width: parent.width
            leftPadding: 4
            wrapMode: Text.Wrap
            visible: !!field.text
            text: Project.searchError ? Project.searchError
                : Project.searching ? "Szukam…"
                : Project.resultCount === 0 ? "Brak wyników"
                : Project.number(Project.resultCount) + (Project.resultCount === 1 ? " wynik" : Project.resultCount % 10 >= 2 && Project.resultCount % 10 <= 4 && (Project.resultCount % 100 < 10 || Project.resultCount % 100 >= 20) ? " wyniki" : " wyników")
                  + " w " + Project.number(Project.results.length) + (Project.results.length === 1 ? " pliku" : " plikach")
                  + (Project.resultsTruncated ? " (pokazano pierwsze)" : "")
            color: Project.searchError ? Theme.danger : Theme.text2
            font.family: Theme.font; font.pixelSize: 12
        }
    }

    ListView {
        id: list
        y: head.height + 8
        width: parent.width; height: parent.height - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: sv.rows
        reuseItems: true
        delegate: Item {
            id: row
            required property var modelData
            width: ListView.view.width; height: modelData.kind === "file" ? 28 : 24
            Rectangle {
                anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                radius: 6
                color: rowArea.containsMouse ? Theme.hover : "transparent"
            }
            // Nagłówek pliku
            Item {
                visible: row.modelData.kind === "file"
                z: 2                            // przycisk „zamień w pliku” nad obszarem kliknięcia wiersza
                anchors.fill: parent
                Icon {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    d: row.modelData.closed ? Icons.chevronRight : Icons.chevronDown; size: 12; stroke: 2; color: Theme.text2
                }
                FileIcon { x: 28; anchors.verticalCenter: parent.verticalCenter; name: row.modelData.name || ""; size: 15 }
                Text {
                    id: fname
                    x: 50; anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.name || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                }
                Text {
                    anchors.left: fname.right; anchors.leftMargin: 6
                    anchors.right: countBadge.left; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideLeft
                    text: row.modelData.dir || ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                }
                HoverButton {
                    visible: sv.replaceOpen && (rowArea.containsMouse || hovered)
                    z: 2
                    anchors.right: countBadge.left; anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22; radius: 6
                    onClicked: sv.replaceFileRequested(row.modelData.path)
                    Icon { anchors.centerIn: parent; d: Icons.check; size: 12; stroke: 2; color: Theme.text2 }
                }
                Rectangle {
                    id: countBadge
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(20, countText.implicitWidth + 10); height: 18; radius: 9
                    color: Theme.fill
                    Text { id: countText; anchors.centerIn: parent; text: row.modelData.count || ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.features: { "tnum": 1 } }
                }
            }
            // Trafienie: fragment wiersza z wyróżnionym tekstem
            Text {
                visible: row.modelData.kind === "match"
                x: 50; width: parent.width - 50 - 12 - (sv.replaceOpen ? 26 : 0)
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                textFormat: Text.StyledText
                // Z zamianą: stare przekreślone na czerwono, nowe na zielono
                text: row.modelData.kind !== "match" ? ""
                    : sv.replaceOpen && sv.replacement !== "" || sv.replaceOpen && replaceField.activeFocus
                      ? sv.esc(row.modelData.before) + "<s><font color=\"" + Theme.danger + "\">" + sv.esc(row.modelData.match) + "</font></s>"
                        + "<font color=\"" + (Theme.dark ? "#56D364" : "#1A7F37") + "\"><b>" + sv.esc(sv.replacement) + "</b></font>" + sv.esc(row.modelData.after)
                      : sv.esc(row.modelData.before) + "<font color=\"" + Theme.text + "\"><b>" + sv.esc(row.modelData.match) + "</b></font>" + sv.esc(row.modelData.after)
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
            HoverButton {
                visible: row.modelData.kind === "match" && sv.replaceOpen && (rowArea.containsMouse || hovered)
                z: 2
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 20; radius: 6
                onClicked: sv.replaceMatchRequested(row.modelData.path, row.modelData.line, row.modelData.col)
                Icon { anchors.centerIn: parent; d: Icons.check; size: 12; stroke: 2; color: Theme.text2 }
            }
            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (row.modelData.kind === "file") {
                        const c = Object.assign({}, sv.collapsed);
                        c[row.modelData.path] = !c[row.modelData.path];
                        sv.collapsed = c;
                    } else {
                        sv.openMatch(row.modelData.path, row.modelData.line, row.modelData.col, row.modelData.length);
                    }
                }
            }
        }
    }
    function esc(s) { return String(s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\t/g, "  "); }

    component Opt: HoverButton {
        id: opt
        property string text
        property bool on: false
        property bool underline: false
        width: 26; height: 26; radius: 6
        baseColor: on ? Theme.accentSoft : "transparent"
        Text {
            anchors.centerIn: parent
            text: opt.text; color: opt.on ? Theme.accentText : Theme.text2
            font.family: "JetBrains Mono"; font.pixelSize: 11; font.weight: Font.DemiBold; font.underline: opt.underline
        }
    }
}
