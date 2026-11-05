pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Pole „Co chcesz zrobić?” u góry okna: jedno miejsce na pliki, polecenia, ustawienia, szukanie w kodzie
// i pytanie do agenta — wystarczy pisać, bez znajomości skrótów i przedrostków. Zdanie idzie najpierw do agenta,
// liczba — do wiersza. Przedrostki dla wprawnych (Ctrl+P):
// „>” — polecenia (Ctrl+Shift+P), „:” — przejście do wiersza (Ctrl+G), „@” — symbole pliku (Ctrl+Shift+O),
// „#” — symbole projektu (Ctrl+T, z serwera języka); osobno wybór gałęzi gita
// (przełącz albo utwórz nową, połącz z bieżącą, usuń).
Item {
    id: pal
    property bool shown: false
    property var commands: []            // [{ label, shortcut, action, icon }]
    property var settings: []            // ustawienia ([{ section, label, desc }]) — też do znalezienia
    property int currentLine: 0          // > 0: otwarty plik, liczba przenosi do wiersza
    // Bez wielkości liter i polskich znaków: „ustawienia” = „Ustawienia”, „zolty” = „żółty”
    function norm(s) { return String(s).toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/ł/g, "l"); }
    function matches(text, q) { const h = norm(text); return norm(q).split(/\s+/).filter(w => !!w).every(w => h.indexOf(w) >= 0); }
    property var recentPaths: []         // otwarte karty — pierwsze przy pustym zapytaniu
    property var items: []
    property int current: 0
    signal fileChosen(string path)
    signal commandChosen(string action)
    signal lineChosen(int line)
    signal branchChosen(string mode, string name, bool remote, bool isNew)
    property string special: ""          // "", "checkout", "merge", "delete", "tasks"
    property var taskList: []
    signal taskChosen(var task)
    function openTasks(list) { taskList = list; openBranches("tasks"); }
    property var symbols: []             // symbole z serwera języka (dla „@” i „#”)
    property bool symbolsLoading: false
    signal symbolChosen(string path, int line, int col)
    signal symbolQuery(string mode, string query)
    signal closed()

    anchors.fill: parent
    visible: shown
    z: 450

    readonly property string mode: special ? "branches" : field.text.startsWith(">") ? "commands" : field.text.startsWith(":") ? "line"
        : field.text.startsWith("@") ? "symbols" : field.text.startsWith("#") ? "workspace" : "files"
    onModeChanged: if (shown && (mode === "symbols" || mode === "workspace")) { symbols = []; symbolsLoading = true; symbolQuery(mode, field.text.slice(1)); }
    Timer { id: wsTimer; interval: 220; onTriggered: pal.symbolQuery("workspace", field.text.slice(1)) }
    property string symbolsNote: ""
    function setSymbols(list, note) { symbols = list; symbolsNote = note || ""; symbolsLoading = false; rebuild(); }
    function kindInfo(k) {
        if (k === 5 || k === 23 || k === 11 || k === 26) return ["T", "#F59E0B"];
        if (k === 6 || k === 9 || k === 12) return ["f", "#A855F7"];
        if (k === 7 || k === 8 || k === 20) return ["p", "#3B82F6"];
        if (k === 13) return ["v", "#06B6D4"];
        if (k === 14 || k === 22) return ["c", "#0EA5E9"];
        if (k === 10) return ["E", "#EAB308"];
        if (k === 2 || k === 3 || k === 4) return ["m", "#64748B"];
        if (k === 19) return ["o", "#10B981"];
        if (k === 24) return ["s", "#EC4899"];
        return ["·", "#94A3B8"];
    }

    function openBranches(what) {
        special = what;
        shown = true;
        field.text = "";
        field.forceActiveFocus();
        rebuild();
    }

    function open(prefix) {
        special = "";
        shown = true;
        field.text = prefix || "";
        field.forceActiveFocus();
        if (mode === "files") Project.refreshFiles();
        rebuild();
    }
    function close() { shown = false; closed(); }
    function rebuild() {
        current = 0;
        const t = field.text;
        if (mode === "commands") {
            const q = t.slice(1).trim().toLowerCase();
            items = commands.filter(c => !q || c.label.toLowerCase().indexOf(q) >= 0
                                         || c.label.toLowerCase().split(" ").some(w => w.startsWith(q)))
                            .map(c => ({ kind: "command", label: c.label, shortcut: c.shortcut || "", action: c.action, icon: c.icon || "" }));
        } else if (mode === "branches") {
            const q = t.trim().toLowerCase();
            if (special === "tasks") {
                // Zadania projektu i ostatnie własne polecenia; wpisany tekst — „Uruchom polecenie”
                const hay = (x) => (x.label + " " + x.command).toLowerCase();
                const list = taskList.filter(x => !q || hay(x).indexOf(q) >= 0).map(x => ({ kind: "task", label: x.label, task: x }));
                if (t.trim() && !taskList.some(x => x.command === t.trim()))
                    list.push({ kind: "task", label: "Uruchom polecenie: " + t.trim(), task: { label: t.trim(), command: t.trim(), group: "custom", custom: true } });
                items = list;
                return;
            }
            let list = Project.branches().filter(b => !q || b.name.toLowerCase().indexOf(q) >= 0);
            if (special !== "checkout") list = list.filter(b => !b.current && (special === "merge" || !b.remote));
            const out = list.map(b => ({ kind: "branch", label: b.name, branch: b }));
            // Nowa gałąź z wpisanej nazwy
            if (special === "checkout" && q && !list.some(b => b.name.toLowerCase() === q))
                out.unshift({ kind: "newBranch", label: "Nowa gałąź „" + t.trim().replace(/\s+/g, "-") + "”", name: t.trim() });
            items = out;
        } else if (mode === "symbols" || mode === "workspace") {
            const q = t.slice(1).trim().toLowerCase();
            if (mode === "workspace" && shown) wsTimer.restart();
            items = symbols.filter(sy => mode === "workspace" || !q || sy.name.toLowerCase().indexOf(q) >= 0).slice(0, 300)
                .map(sy => ({ kind: "symbol", label: sy.name, symbol: sy }));
        } else if (mode === "line") {
            items = [];
        } else {
            let list = Project.quickOpen(t, 60);
            if (!t.trim()) {
                // Pusta paleta: najpierw otwarte pliki, potem reszta projektu
                const open = recentPaths.filter(p => p.startsWith(Project.root + "/"))
                    .map(p => { const rel = Project.relative(p); const i = rel.lastIndexOf("/");
                                return { path: p, rel: rel, name: rel.slice(i + 1), dir: i > 0 ? rel.slice(0, i) : "", html: "", opened: true }; });
                list = open.concat(list.filter(f => recentPaths.indexOf(f.path) < 0));
            }
            const files = list.map(f => Object.assign({ kind: "file" }, f));
            const q = t.trim();
            if (!q) { items = files; return; }
            const cmd = (label, action, icon, right) => ({ kind: "command", label: label, shortcut: right || "", action: action, icon: icon });
            const cmds = commands.filter(c => matches(c.label, q)).slice(0, 5).map(c => cmd(c.label, c.action, c.icon || "", c.shortcut));
            const sets = settings.filter(s => s.type !== "servers" && matches(s.section + " " + s.label + " " + s.desc, q)).slice(0, 3)
                                 .map(s => cmd(s.label, "setting:" + s.label, "gear", "ustawienie"));
            const ask = cmd("Zapytaj agenta: " + q, "ask:" + q, "sparkles", "agent");
            const find = cmd("Szukaj w kodzie: " + q, "searchtext:" + q, "search", "");
            const line = /^\d+$/.test(q) && currentLine > 0 ? [cmd("Przejdź do wiersza " + q, "gotoline:" + q, "arrow", "")] : [];
            // Zdanie to pytanie albo prośba — najpierw agent; krótkie hasło — najpierw pliki i polecenia
            const sentence = q.split(/\s+/).length >= 3 || q.endsWith("?");
            items = sentence ? [ask].concat(cmds, sets, files.slice(0, 5), [find])
                             : line.concat(files.slice(0, 6), cmds, sets, [find, ask]);
        }
    }
    function accept() {
        if (mode === "line") {
            const n = parseInt(field.text.slice(1));
            close();
            if (n > 0) lineChosen(n);
            return;
        }
        const it = items[current];
        if (!it) return;
        const sp = special;
        close();
        if (it.kind === "task") taskChosen(it.task);
        else if (it.kind === "symbol") symbolChosen(it.symbol.path || "", it.symbol.line, it.symbol.col);
        else if (it.kind === "branch") branchChosen(sp, it.branch.name, it.branch.remote, false);
        else if (it.kind === "newBranch") branchChosen(sp, it.name, false, true);
        else if (it.kind === "file") fileChosen(it.path);
        else commandChosen(it.action);
    }
    function move(d) {
        if (!items.length) return;
        current = (current + d + items.length) % items.length;
        list.positionViewAtIndex(current, ListView.Contain);
    }

    Connections {
        target: Project
        function onFilesReady() { if (pal.shown && pal.mode === "files") pal.rebuild(); }
    }

    MouseArea { anchors.fill: parent; onPressed: pal.close() }

    Rectangle {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8
        width: Math.min(640, parent.width - 40)
        height: 54 + (list.count ? Math.min(list.contentHeight, 420) + 8 : (pal.mode === "line" || empty.visible ? 40 : 0))
        radius: 14
        color: Theme.surface
        border.width: 1; border.color: Theme.edge
        clip: true
        MouseArea { anchors.fill: parent }

        Rectangle {
            x: 10; y: 10
            width: parent.width - 20; height: 34; radius: 9
            color: Theme.fill
            border.width: 1.5; border.color: Theme.accent
            Icon {
                x: 10; anchors.verticalCenter: parent.verticalCenter
                d: pal.mode === "commands" ? Icons.apps : pal.mode === "line" ? Icons.arrow : pal.mode === "branches" ? (pal.special === "tasks" ? Icons.play : Icons.gitBranch) : Icons.search
                size: 15; color: Theme.text2
            }
            TextInput {
                id: field
                x: 34; width: parent.width - 44
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                font.family: Theme.font; font.pixelSize: 14
                clip: true
                onTextChanged: pal.rebuild()
                Keys.onEscapePressed: pal.close()
                Keys.onUpPressed: pal.move(-1)
                Keys.onDownPressed: pal.move(1)
                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_PageDown) { pal.move(8); e.accepted = true; }
                    else if (e.key === Qt.Key_PageUp) { pal.move(-8); e.accepted = true; }
                }
                onAccepted: pal.accept()
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !field.text
                    text: pal.special === "tasks" ? "Wybierz zadanie albo wpisz polecenie"
                        : pal.special === "checkout" ? "Wybierz gałąź albo wpisz nazwę nowej"
                        : pal.special === "merge" ? "Którą gałąź połączyć z bieżącą?"
                        : pal.special === "delete" ? "Którą gałąź usunąć?"
                        : "Plik, polecenie, ustawienie albo pytanie do agenta"
                    color: Theme.text2; font: field.font
                }
            }
        }

        Text {
            id: empty
            x: 22; y: 58
            visible: pal.mode === "line" || (list.count === 0 && (pal.mode === "branches" || pal.mode === "symbols" || pal.mode === "workspace"
                                                                 || field.text.length > (pal.mode === "commands" ? 1 : 0)))
            text: pal.mode === "line" ? (parseInt(field.text.slice(1)) > 0 ? "Enter — przejdź do wiersza " + parseInt(field.text.slice(1)) : "Wpisz numer wiersza")
                                      : pal.mode === "commands" ? "Brak takiego polecenia"
                                      : pal.special === "tasks" ? "Nie znaleziono zadań — wpisz polecenie, np. make"
                                      : pal.mode === "branches" ? "Brak innych gałęzi"
                                      : pal.mode === "symbols" || pal.mode === "workspace" ? (pal.symbolsLoading ? "Pytam serwer języka…"
                                          : pal.symbolsNote ? pal.symbolsNote
                                          : pal.mode === "workspace" && field.text.length < 2 ? "Wpisz nazwę symbolu" : "Brak symboli (albo serwera języka dla tego pliku)")
                                      : "Brak pasujących plików"
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
        }

        ListView {
            id: list
            x: 6; y: 52
            width: parent.width - 12
            height: Math.min(contentHeight, 420)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: pal.items
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool sel: index === pal.current
                width: ListView.view.width; height: 34; radius: 8
                color: sel ? Theme.accentSoft : rowArea.containsMouse ? Theme.hover : "transparent"
                FileIcon {
                    visible: row.modelData.kind === "file"
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    name: row.modelData.name || ""
                }
                Rectangle {
                    visible: row.modelData.kind === "symbol"
                    readonly property var ki: row.modelData.kind === "symbol" ? pal.kindInfo(row.modelData.symbol.kind) : ["", "#000000"]
                    x: 9 + (row.modelData.kind === "symbol" && pal.mode === "symbols" ? Math.min(4, row.modelData.symbol.depth) * 12 : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18; radius: 5
                    color: Qt.rgba(Qt.color(ki[1]).r, Qt.color(ki[1]).g, Qt.color(ki[1]).b, Theme.dark ? 0.28 : 0.16)
                    Text { anchors.centerIn: parent; text: parent.ki[0]; color: parent.ki[1]; font.family: "JetBrains Mono"; font.pixelSize: 11; font.weight: Font.Bold }
                }
                Icon {
                    visible: row.modelData.kind === "task"
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    d: row.modelData.kind !== "task" ? "" : row.modelData.task.group === "build" ? Icons.bolt : row.modelData.task.group === "test" ? Icons.check
                     : row.modelData.task.group === "custom" || row.modelData.task.recent ? Icons.prompt : Icons.play
                    size: 15; color: Theme.text2
                }
                Icon {
                    visible: row.modelData.kind === "branch" || row.modelData.kind === "newBranch"
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    d: row.modelData.kind === "newBranch" ? Icons.plus : row.modelData.kind === "branch" && row.modelData.branch.remote ? Icons.globe : Icons.gitBranch
                    size: 15; color: row.modelData.kind === "branch" && row.modelData.branch.current ? Theme.accentText : Theme.text2
                }
                Icon {
                    visible: row.modelData.kind === "command"
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    d: Icons[row.modelData.icon] || ""; size: 16; color: Theme.text2
                }
                Row {
                    x: 36 + (row.modelData.kind === "symbol" && pal.mode === "symbols" ? Math.min(4, row.modelData.symbol.depth) * 12 : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 36 - shortcutText.width - 16
                    spacing: 8
                    clip: true
                    Text {
                        id: nameText
                        text: row.modelData.kind === "file"
                              ? (row.modelData.html ? row.modelData.html.replace(/<b>/g, "<font color=\"" + Theme.accentText + "\"><b>").replace(/<\/b>/g, "</b></font>") : row.modelData.name)
                              : row.modelData.label
                        textFormat: row.modelData.html ? Text.StyledText : Text.PlainText
                        font.weight: row.modelData.kind === "branch" && row.modelData.branch.current ? Font.DemiBold : Font.Normal
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.modelData.kind === "file" || row.modelData.kind === "branch" || row.modelData.kind === "symbol" || row.modelData.kind === "task"
                        width: Math.max(0, parent.width - nameText.width - 8); elide: row.modelData.kind === "file" ? Text.ElideLeft : Text.ElideRight
                        text: row.modelData.kind === "task" ? (row.modelData.task.label !== row.modelData.task.command ? row.modelData.task.command : "")
                            : row.modelData.kind === "branch" ? (row.modelData.branch.subject || "")
                            : row.modelData.kind === "symbol" ? (pal.mode === "workspace" ? (row.modelData.symbol.container ? row.modelData.symbol.container + " · " : "") + (row.modelData.symbol.rel || "")
                                                                                          : row.modelData.symbol.detail || "")
                            : (row.modelData.dir || "")
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                    }
                }
                Text {
                    id: shortcutText
                    anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.kind === "command" ? row.modelData.shortcut
                        : row.modelData.kind === "branch" ? (row.modelData.branch.current ? "bieżąca" : row.modelData.branch.remote ? "zdalna" : "")
                        : row.modelData.kind === "task" ? (row.modelData.task.recent ? "ostatnio" : { build: "budowanie", run: "uruchom", test: "testy", other: row.modelData.task.source || "", custom: "" }[row.modelData.task.group] || "")
                        : row.modelData.kind === "symbol" ? "wiersz " + (row.modelData.symbol.line + 1)
                        : (row.modelData.opened ? "otwarty" : "")
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { pal.current = row.index; pal.accept(); }
                }
            }
        }
    }
}
