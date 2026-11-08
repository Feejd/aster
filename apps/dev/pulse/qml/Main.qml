pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Dialogs
import Aster.Ui
import Aster.Pulse

// Aster Pulse — testowanie API: zapytanie u góry, odpowiedź pod nim, kolekcje i historia z boku.
// Zapytania są w plikach JSON obszaru roboczego (pulse/ w projekcie albo ~/Dokumenty/Pulse), środowiska
// w pulse.json, tajne wartości w portfelu systemu. To samo uruchamia `aster-pulse run` i usługa D-Bus.
Window {
    id: win
    width: 1180 + 2 * m
    height: 760 + 2 * m
    minimumWidth: 860 + 2 * m
    minimumHeight: 560 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: (dirty ? "• " : "") + (req.name || "Aster Pulse") + " — Aster Pulse"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 24

    // ——— Bieżące zapytanie ———
    property var req: Pulse.newRequest()
    property string reqFile: ""                // plik kolekcji; pusty — szkic jeszcze niezapisany
    property bool dirty: false
    property var drafts: ({})                  // id → { req, file } — niezapisane zmiany innych zapytań
    property var sheet: null                   // okno dialogowe: { kind: import|export|save|prompt|confirm, … }
    property real split: 0.46
    readonly property var dirtyMap: {
        const d = {};
        for (const id in drafts) d[id] = true;
        if (dirty) d[req.id] = true;
        return d;
    }
    readonly property string collectionName: {
        const c = Pulse.collections.find(c => c.file === reqFile);
        return c ? c.name : "";
    }

    function normalized(r) {
        const out = JSON.parse(JSON.stringify(r));
        // Adres z ?a=1 zapisany ręcznie w pliku — parametry do tabeli
        const q = (out.url || "").indexOf("?");
        if (q >= 0) {
            const s = requestPane.splitUrl(out.url);
            out.url = s.base;
            out.params = s.params.concat(out.params || []);
        }
        return out;
    }
    function stash() {
        const d = Object.assign({}, drafts);
        if (dirty) d[req.id] = { req: req, file: reqFile };
        else delete d[req.id];
        drafts = d;
    }
    function openRequest(file, r) {
        if (r.id === req.id && file === reqFile) return;
        stash();
        const draft = drafts[r.id];
        req = draft ? draft.req : normalized(r);
        reqFile = file;
        dirty = !!draft;
        requestPane.reload();
        Pulse.clearResponse();
    }
    function openDraft(r, file) {
        stash();
        req = normalized(r);
        reqFile = file || "";
        dirty = true;
        requestPane.reload();
        Pulse.clearResponse();
    }
    function patch(changes) {
        req = Object.assign({}, req, changes);
        dirty = true;
    }
    function newRequest(file) {
        const target = file || reqFile || (Pulse.collections.length ? Pulse.collections[0].file : "");
        const r = Pulse.newRequest();
        if (target === "") { openDraft(r, ""); requestPane.focusUrl(); return; }
        const saved = Pulse.saveRequest(target, r);
        openRequest(target, saved);
        requestPane.focusUrl();
    }
    function save() {
        if (reqFile === "" || !Pulse.collections.some(c => c.file === reqFile)) { sheet = { kind: "save" }; return; }
        const saved = Pulse.saveRequest(reqFile, req);
        if (!saved.id) return;
        req = Object.assign({}, req, { id: saved.id });
        dirty = false;
        const d = Object.assign({}, drafts);
        delete d[req.id];
        drafts = d;
        toast("Zapisano „" + req.name + "”");
    }
    function send() { Pulse.send(req); }
    function toast(text) { toastBox.text = text; toastBox.shown = true; toastTimer.restart(); }
    Connections { target: Pulse; function onMessage(text) { win.toast(text); } }
    Connections {
        target: Pulse
        function onWorkspaceChanged() {
            // Inny obszar: zaczynamy od pierwszego zapytania (bez szkiców z poprzedniego)
            win.drafts = {};
            win.dirty = false;
            const c = Pulse.collections.find(c => c.requests.length > 0);
            win.reqFile = c ? c.file : "";
            win.req = c ? win.normalized(c.requests[0]) : Pulse.newRequest();
            requestPane.reload();
            Pulse.clearResponse();
        }
    }
    Component.onCompleted: {
        const c = Pulse.collections.find(c => c.requests.length > 0);
        if (c) { reqFile = c.file; req = normalized(c.requests[0]); }
        requestPane.reload();
        effectsTimer.restart();
    }

    function envColor(name) { return /prod/i.test(name) ? "#E5484D" : /stag|test/i.test(name) ? "#F5A623" : "#21B35A"; }

    // ——— Menu ———
    function showMenu(anchor, dx, items, kind, data) {
        const p = anchor.mapToItem(frame, dx, anchor.height + 6);
        menu.kind = kind;
        menu.payload = data;
        menu.openAt(p.x, p.y, items);
    }
    function methodMenu(anchor) {
        const ms = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"];
        showMenu(anchor, 0, ms.map(m => ({ label: m, icon: m === req.method ? "check" : "", action: m })), "method");
    }
    function envMenu() {
        const items = Pulse.environments.map(e => ({ label: e.name, icon: e.name === Pulse.activeEnv ? "check" : "", action: "env:" + e.name }));
        items.push({ separator: true });
        items.push({ label: "Zarządzaj środowiskami…", icon: "sliders", shortcut: "Ctrl+E", action: "envs" });
        showMenu(envButton, envButton.width - 250, items, "main");
    }
    function moreMenu() {
        showMenu(moreButton, moreButton.width - 250, [
            { label: "Zapisz", icon: "check", shortcut: "Ctrl+S", action: "save" },
            { label: "Zapisz jako kopię", icon: "copy", action: "duplicate", enabled: reqFile !== "" },
            { label: "Nowe zapytanie", icon: "plus", shortcut: "Ctrl+N", action: "new" },
            { separator: true },
            { label: "Importuj z cURL…", icon: "download", shortcut: "Ctrl+I", action: "import" },
            { label: "Kopiuj jako cURL…", icon: "terminal", shortcut: "Ctrl+Shift+C", action: "export" },
            { separator: true },
            { label: "Środowiska…", icon: "sliders", shortcut: "Ctrl+E", action: "envs" },
            { label: "Pomiń sprawdzanie certyfikatu", icon: req.insecure ? "check" : "shield", action: "insecure" },
            { separator: true },
            { label: "Usuń zapytanie", icon: "trash", action: "delete", danger: true, enabled: reqFile !== "" }
        ], "main");
    }
    function workspaceMenu(anchor) {
        const items = Pulse.recentWorkspaces.map(d => ({ label: Pulse.prettyPath(d), icon: "folder", action: "ws:" + d }));
        if (items.length) items.push({ separator: true });
        items.push({ label: "Otwórz folder projektu…", icon: "folderPlus", shortcut: "Ctrl+O", action: "openFolder" });
        items.push({ label: "Pokaż folder w Plikach", icon: "folder", action: "reveal" });
        showMenu(anchor, 0, items, "main");
    }
    function collectionMenu(file, x, y) {
        const p = sidebar.mapToItem(frame, x, y);
        menu.kind = "collection"; menu.payload = file;
        menu.openAt(p.x, p.y, [
            { label: "Nowe zapytanie", icon: "plus", action: "new" },
            { label: "Zmień nazwę…", icon: "pencil", action: "rename" },
            { separator: true },
            { label: "Usuń kolekcję", icon: "trash", action: "delete", danger: true }
        ]);
    }
    function requestMenu(file, r, x, y) {
        const p = sidebar.mapToItem(frame, x, y);
        menu.kind = "request"; menu.payload = { file: file, req: r };
        const items = [
            { label: "Otwórz", icon: "arrow", action: "open" },
            { label: "Wyślij", icon: "send", action: "send" },
            { label: "Duplikuj", icon: "copy", action: "duplicate" },
            { label: "Kopiuj polecenie dla agenta", icon: "terminal", action: "cli" }
        ];
        const others = Pulse.collections.filter(c => c.file !== file);
        if (others.length) {
            items.push({ separator: true });
            for (const c of others.slice(0, 5)) items.push({ label: "Przenieś do „" + c.name + "”", icon: "folder", action: "move:" + c.file });
        }
        items.push({ separator: true });
        items.push({ label: "Usuń", icon: "trash", action: "delete", danger: true });
        menu.openAt(p.x, p.y, items);
    }
    function treeMenu(row, x, y) {
        const p = responsePane.mapToItem(frame, x, y);
        menu.kind = "tree"; menu.payload = row;
        menu.openAt(p.x, p.y, [
            { label: "Kopiuj wartość", icon: "copy", action: "value" },
            { label: "Kopiuj ścieżkę", icon: "braces", action: "path" },
            { label: "Rozwiń wszystko", icon: "plus", action: "expand" },
            { label: "Zwiń wszystko", icon: "minus", action: "collapse" }
        ]);
    }
    function runMenu(a) {
        const kind = menu.kind, data = menu.payload;
        if (kind === "method") { patch({ method: a }); return; }
        if (kind === "tree") {
            if (a === "value") { Pulse.copy(Pulse.tree.valueText(data)); toast("Skopiowano wartość"); }
            else if (a === "path") { Pulse.copy(Pulse.tree.pathText(data)); toast("Skopiowano " + Pulse.tree.pathText(data)); }
            else if (a === "expand") Pulse.tree.expandAll();
            else if (a === "collapse") Pulse.tree.collapseAll();
            return;
        }
        if (kind === "collection") {
            const c = Pulse.collections.find(c => c.file === data);
            if (a === "new") newRequest(data);
            else if (a === "rename") sheet = { kind: "prompt", title: "Nazwa kolekcji", value: c ? c.name : "", button: "Zmień", action: (t) => Pulse.renameCollection(data, t) };
            else if (a === "delete") sheet = { kind: "confirm", title: "Usunąć kolekcję „" + (c ? c.name : "") + "”?",
                                               detail: "Plik " + data + " zniknie z folderu razem z " + (c ? c.requests.length : 0) + " zapisanymi zapytaniami.",
                                               button: "Usuń", action: () => { Pulse.deleteCollection(data); if (reqFile === data) { reqFile = ""; dirty = true; } } };
            return;
        }
        if (kind === "request") {
            if (a === "open") openRequest(data.file, data.req);
            else if (a === "send") { openRequest(data.file, data.req); send(); }
            else if (a === "duplicate") { const d = Pulse.duplicateRequest(data.file, data.req.id); if (d.id) openRequest(data.file, d); }
            else if (a === "cli") { Pulse.copy(Pulse.cliCommand(data.file, data.req.name)); toast("Skopiowano polecenie aster-pulse run"); }
            else if (a.startsWith("move:")) { Pulse.moveRequest(data.file, data.req.id, a.slice(5)); if (req.id === data.req.id) reqFile = a.slice(5); }
            else if (a === "delete") sheet = { kind: "confirm", title: "Usunąć „" + data.req.name + "”?", detail: "Zapytanie zniknie z kolekcji.", button: "Usuń",
                                               action: () => { Pulse.deleteRequest(data.file, data.req.id); if (req.id === data.req.id) { reqFile = ""; dirty = true; } } };
            return;
        }
        if (a.startsWith("env:")) Pulse.activeEnv = a.slice(4);
        else if (a === "envs") envDialog.open();
        else if (a === "save") save();
        else if (a === "new") newRequest("");
        else if (a === "duplicate") { const d = Pulse.duplicateRequest(reqFile, req.id); if (d.id) openRequest(reqFile, d); }
        else if (a === "import") openImport();
        else if (a === "export") sheet = { kind: "export" };
        else if (a === "insecure") patch({ insecure: !req.insecure });
        else if (a === "delete") runMenuDelete();
        else if (a.startsWith("ws:")) Pulse.openFolder(a.slice(3));
        else if (a === "openFolder") folderDialog.open();
        else if (a === "reveal") Qt.openUrlExternally("file://" + Pulse.workspaceDir);
    }
    function runMenuDelete() {
        const id = req.id, file = reqFile, name = req.name;
        sheet = { kind: "confirm", title: "Usunąć „" + name + "”?", detail: "Zapytanie zniknie z kolekcji.", button: "Usuń",
                  action: () => { Pulse.deleteRequest(file, id); reqFile = ""; dirty = true; } };
    }
    function openImport(text) {
        const clip = Pulse.clipboardText();
        sheet = { kind: "import", text: text || (/^\s*curl\s/.test(clip) ? clip : "") };
    }

    // Do testów (ASTER_OPEN, rozdzielone „;”): send | open:kolekcja/zapytanie | tab:headers | rtab:raw | env | import | export
    //   | save | history | search:tekst | find:tekst | dark
    property string pendingSearch
    Connections {
        target: Pulse
        function onResponseChanged() { if (win.pendingSearch !== "" && Pulse.response.has) { Pulse.tree.filter = win.pendingSearch; win.pendingSearch = ""; } }
    }
    function testOpen(what) {
        for (const w of what.split(";")) {
            if (w === "send") send();
            else if (w.startsWith("open:")) {
                const [cn, rn] = w.slice(5).split("/");
                const c = Pulse.collections.find(c => c.name === cn || c.file === cn + ".json");
                const r = c ? c.requests.find(r => r.name === rn) : null;
                if (r) openRequest(c.file, r);
            }
            else if (w.startsWith("tab:")) requestPane.tab = w.slice(4);
            else if (w.startsWith("rtab:")) responsePane.tab = w.slice(5);
            else if (w === "env") envDialog.open();
            else if (w === "import") openImport("curl -X POST 'https://api.example.com/v1/orders?expand=items' \\\n  -H 'Authorization: Bearer {{token}}' \\\n  -H 'Content-Type: application/json' \\\n  --data-raw '{\"product\": 42, \"qty\": 2}'");
            else if (w === "export") sheet = { kind: "export" };
            else if (w === "save") sheet = { kind: "save" };
            else if (w === "history") sidebar.page = "history";
            else if (w.startsWith("search:")) pendingSearch = w.slice(7);
            else if (w === "menu") moreMenu();
            else if (w.startsWith("url:")) requestPane.testTypeUrl(w.slice(4));
            else if (w.startsWith("param:")) requestPane.testParam(w.slice(6));
            else if (w.startsWith("env:")) Pulse.activeEnv = w.slice(4);
            else if (w === "new") newRequest("");
            else if (w === "envsave") { envDialog.open(); envDialog.save(); }
        }
    }

    Shortcut { sequences: ["Ctrl+Return", "Ctrl+Enter"]; onActivated: win.send() }
    Shortcut { sequence: "Ctrl+S"; onActivated: win.save() }
    Shortcut { sequence: "Ctrl+N"; onActivated: win.newRequest("") }
    Shortcut { sequence: "Ctrl+L"; onActivated: requestPane.focusUrl() }
    Shortcut { sequence: "Ctrl+F"; enabled: Pulse.response.kind === "json"; onActivated: responsePane.focusSearch() }
    Shortcut { sequence: "Ctrl+P"; onActivated: { sidebar.page = "collections"; sidebar.focusSearch(); } }
    Shortcut { sequence: "Ctrl+E"; onActivated: envDialog.open() }
    Shortcut { sequence: "Ctrl+I"; onActivated: win.openImport() }
    Shortcut { sequence: "Ctrl+O"; onActivated: folderDialog.open() }
    Shortcut { sequence: "Ctrl+M"; onActivated: requestPane.methodMenu(requestPane) }
    Shortcut { sequence: "Ctrl+Shift+C"; onActivated: win.sheet = { kind: "export" } }
    Shortcut { sequence: "Ctrl+W"; onActivated: win.close() }
    Shortcut {
        sequence: "Esc"
        onActivated: {
            if (menu.shown) menu.close();
            else if (envDialog.shown) envDialog.shown = false;
            else if (win.sheet) win.sheet = null;
            else if (Pulse.busy) Pulse.cancel();
        }
    }

    FolderDialog {
        id: folderDialog
        title: "Folder projektu albo obszaru Pulse"
        onAccepted: Pulse.openFolder(selectedFolder)
    }

    // ——— Okno ———
    function updateEffects() {
        WindowEffects.setBlur(win, Qt.rect(m, m, frame.width, frame.height), r);
        WindowEffects.setInputRegion(win, Qt.rect(Math.max(0, m - 6), Math.max(0, m - 6), frame.width + (maxed ? 0 : 12), frame.height + (maxed ? 0 : 12)));
    }
    onWidthChanged: effectsTimer.restart()
    onHeightChanged: effectsTimer.restart()
    onMaxedChanged: effectsTimer.restart()
    Timer { id: effectsTimer; interval: 16; onTriggered: win.updateEffects() }

    WindowShadow { window: win; frame: frame; radius: win.r; visible: !win.maxed }
    ResizeHandles { window: win; frame: frame; margin: win.m }

    Rectangle {
        id: frame
        x: win.m; y: win.m
        width: win.width - 2 * win.m
        height: win.height - 2 * win.m
        radius: win.r
        color: Theme.windowGlass
        border.width: win.maxed ? 0 : 1
        border.color: Theme.edge
        WindowSheen { window: win; radius: win.r }
        clip: true

        Sidebar {
            id: sidebar
            width: 264; height: parent.height
            selectedId: win.req.id || ""
            dirty: win.dirtyMap
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
            onOpenRequest: (file, r) => win.openRequest(file, r)
            onOpenHistory: (e) => {
                const c = Pulse.collections.find(c => c.requests.some(r => r.id === e.request.id));
                win.openDraft(e.request, c ? c.file : "");
                win.dirty = !c;
            }
            onNewRequest: (file) => win.newRequest(file)
            onNewCollection: win.sheet = { kind: "prompt", title: "Nowa kolekcja", value: "", button: "Utwórz", placeholder: "np. Użytkownicy",
                                           action: (t) => { const f = Pulse.createCollection(t); if (f) win.newRequest(f); } }
            onCollectionMenu: (file, x, y) => win.collectionMenu(file, x, y)
            onRequestMenu: (file, r, x, y) => win.requestMenu(file, r, x, y)
            onWorkspaceMenu: (a) => win.workspaceMenu(a)
        }

        GlassPane {
            id: main
            x: sidebar.width
            width: parent.width - sidebar.width
            height: parent.height
            topRightRadius: win.r; bottomRightRadius: win.r

            // ——— Pasek tytułu ———
            Item {
                id: topBar
                width: parent.width; height: 60
                z: 5
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }

                Column {
                    x: 24; anchors.verticalCenter: parent.verticalCenter
                    width: envButton.x - x - 20
                    spacing: 1
                    Text {
                        visible: text !== ""
                        text: win.reqFile === "" ? "Szkic — niezapisany" : win.collectionName
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 11
                    }
                    Row {
                        spacing: 8
                        width: parent.width
                        TextInput {
                            id: nameInput
                            width: Math.min(parent.width - 20, Math.max(60, contentWidth + 4))
                            text: win.req.name || ""
                            color: Theme.text
                            selectionColor: Theme.accentSoft
                            selectByMouse: true
                            clip: true
                            font.family: Theme.font; font.pixelSize: 19; font.weight: Font.Bold; font.letterSpacing: -0.3
                            onTextEdited: win.patch({ name: text })
                            Keys.onReturnPressed: { focus = false; win.save(); }
                            Keys.onEscapePressed: focus = false
                        }
                        Rectangle {
                            visible: win.dirty
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8; height: 8; radius: 4
                            color: Theme.accent
                        }
                    }
                }

                // Środowisko
                HoverButton {
                    id: envButton
                    anchors.right: saveButton.visible ? saveButton.left : moreButton.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: envRow.implicitWidth + 26; height: 34; radius: 17
                    baseColor: Theme.fill
                    tip: "Środowisko (zmienne {{…}})"
                    onClicked: win.envMenu()
                    Row {
                        id: envRow
                        anchors.centerIn: parent
                        spacing: 8
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: win.envColor(Pulse.activeEnv) }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Pulse.activeEnv || "Bez środowiska"
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                        }
                        Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.chevronDown; size: 12; stroke: 2; color: Theme.text2 }
                    }
                }
                Pill {
                    id: saveButton
                    visible: win.dirty
                    anchors.right: moreButton.left; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Zapisz"
                    icon: "check"
                    tip: "Ctrl+S"
                    onClicked: win.save()
                }
                ToolBtn {
                    id: moreButton
                    anchors.right: winButtons.left; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "more"
                    tip: "Więcej"
                    onClicked: win.moreMenu()
                }
                WindowButtons {
                    id: winButtons
                    window: win
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            RequestPane {
                id: requestPane
                y: topBar.height
                width: parent.width
                height: Math.round((parent.height - topBar.height) * win.split)
                req: win.req
                busy: Pulse.busy
                onPatch: (c) => win.patch(c)
                onSendRequested: win.send()
                onCancelRequested: Pulse.cancel()
                onMethodMenu: (a) => win.methodMenu(a)
                onImportCurl: (t) => win.openImport(t)
            }

            // Uchwyt podziału
            Item {
                id: splitter
                y: requestPane.y + requestPane.height - 4
                width: parent.width; height: 9
                z: 4
                Rectangle { anchors.centerIn: parent; width: parent.width; height: 1; color: Theme.line }
                Rectangle {
                    anchors.centerIn: parent
                    width: 36; height: 4; radius: 2
                    color: splitArea.containsMouse || splitArea.pressed ? Theme.accent : Theme.text2
                    opacity: splitArea.containsMouse || splitArea.pressed ? 0.8 : 0.25
                }
                MouseArea {
                    id: splitArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.SplitVCursor
                    onPositionChanged: (m) => {
                        if (!pressed) return;
                        const yy = mapToItem(main, 0, m.y).y - topBar.height;
                        win.split = Math.max(0.22, Math.min(0.75, yy / (main.height - topBar.height)));
                    }
                }
            }

            ResponsePane {
                id: responsePane
                y: splitter.y + splitter.height
                width: parent.width
                height: parent.height - y
                onRowMenu: (row, x, y) => win.treeMenu(row, x, y)
                onToast: (t) => win.toast(t)
            }

            // Komunikat na dole
            Rectangle {
                id: toastBox
                property bool shown: false
                property alias text: toastText.text
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - (shown ? height + 22 : 0)
                opacity: shown ? 1 : 0
                z: 20
                width: Math.min(parent.width - 40, toastText.implicitWidth + 36); height: 40; radius: 20
                color: Theme.dark ? "#ECEEF3" : "#1E2027"
                Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutQuint } }
                Behavior on opacity { NumberAnimation { duration: 100 } }
                Text { id: toastText; anchors.centerIn: parent; width: Math.min(implicitWidth, parent.width - 30); elide: Text.ElideRight; color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                Timer { id: toastTimer; interval: 3000; onTriggered: toastBox.shown = false }
            }
        }

        ContextMenu {
            id: menu
            property string kind
            property var payload
            onTriggered: (a) => win.runMenu(a)
        }

        EnvironmentsDialog {
            id: envDialog
            radius: win.r
        }

        // ——— Okna dialogowe ———
        Item {
            anchors.fill: parent
            visible: !!win.sheet
            z: 200
            Rectangle { anchors.fill: parent; radius: win.r; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.25) }
            MouseArea { anchors.fill: parent; onClicked: win.sheet = null }
            RectangularShadow { anchors.fill: dlg; radius: dlg.radius; blur: 40; offset.y: 14; color: Theme.shadow }
            Rectangle {
                id: dlg
                anchors.centerIn: parent
                width: Math.min(parent.width - 60, win.sheet && (win.sheet.kind === "import" || win.sheet.kind === "export") ? 680 : 440)
                height: dlgLoader.item ? dlgLoader.item.implicitHeight + 44 : 100
                radius: 22
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                MouseArea { anchors.fill: parent }
                Loader {
                    id: dlgLoader
                    x: 24; y: 22; width: parent.width - 48
                    active: !!win.sheet
                    sourceComponent: !win.sheet ? null
                                    : win.sheet.kind === "import" ? importSheet
                                    : win.sheet.kind === "export" ? exportSheet
                                    : win.sheet.kind === "save" ? saveSheet
                                    : win.sheet.kind === "prompt" ? promptSheet : confirmSheet
                }
            }
        }
    }

    Component {
        id: importSheet
        Column {
            spacing: 10
            Title { text: "Importuj z cURL" }
            Detail { text: "Wklej polecenie — np. z dokumentacji API albo z przeglądarki (Narzędzia → Sieć → Kopiuj jako cURL)." }
            CodeArea {
                id: curlIn
                width: parent.width; height: 200
                json: false; numbers: false; wrap: true
                placeholder: "curl -X POST https://api.example.com/users -H 'Content-Type: application/json' -d '{\"name\": \"Ala\"}'"
                Component.onCompleted: { setText(win.sheet.text || ""); edit.forceActiveFocus(); edit.cursorPosition = edit.length; }
            }
            Text { id: importError; visible: text !== ""; color: Theme.danger; font.family: Theme.font; font.pixelSize: 12 }
            Item {
                width: parent.width; height: 34
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Pill { text: "Anuluj"; onClicked: win.sheet = null }
                    Pill {
                        text: "Importuj"; primary: true
                        onClicked: {
                            const res = Pulse.importCurl(curlIn.text);
                            if (res.error) { importError.text = res.error; return; }
                            win.sheet = null;
                            win.openDraft(res.request, "");
                            win.toast("Zaimportowano — zapisz zapytanie w kolekcji (Ctrl+S)");
                        }
                    }
                }
            }
        }
    }
    Component {
        id: exportSheet
        Column {
            id: ex
            property bool resolve: true
            spacing: 10
            Title { text: "Kopiuj jako cURL" }
            Detail { text: ex.resolve ? "Zmienne środowiska „" + Pulse.activeEnv + "” podstawione; tajne zostają jako {{nazwa}}, więc polecenie można wkleić do zgłoszenia czy czatu." : "Polecenie z {{zmiennymi}} tak jak w zapytaniu." }
            CodeArea {
                id: curlOut
                width: parent.width; height: 170
                readOnly: true; json: false; numbers: false
                text: Pulse.exportCurl(win.req, ex.resolve)
            }
            Row {
                spacing: 8
                Pill { small: true; text: ex.resolve ? "Pokaż ze zmiennymi" : "Podstaw zmienne"; onClicked: ex.resolve = !ex.resolve }
                Pill { small: true; text: "Kopiuj"; icon: "copy"; primary: true; onClicked: { Pulse.copy(curlOut.text); win.toast("Skopiowano polecenie cURL"); } }
            }
            Item { width: 1; height: 6 }
            Title { text: "Dla terminala i asystenta"; font.pixelSize: 15 }
            Detail {
                text: win.reqFile === "" ? "Zapisz zapytanie w kolekcji, a agent i skrypty uruchomią je poleceniem aster-pulse run (wynik jako JSON)."
                                         : "To polecenie wysyła zapisane zapytanie i wypisuje wynik jako JSON (kod, czas, nagłówki, treść). Asystent Aster może go używać do testowania backendu."
            }
            Rectangle {
                visible: win.reqFile !== ""
                width: parent.width; height: 40; radius: 10
                color: Theme.fill
                Text {
                    id: cli
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 60
                    elide: Text.ElideMiddle
                    text: win.reqFile !== "" ? Pulse.cliCommand(win.reqFile, win.req.name) : ""
                    color: Theme.text; font.family: "JetBrains Mono"; font.pixelSize: 12
                }
                ToolBtn { anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; icon: "copy"; tip: "Kopiuj"; onClicked: { Pulse.copy(cli.text); win.toast("Skopiowano polecenie"); } }
            }
            Item {
                width: parent.width; height: 34
                Pill { anchors.right: parent.right; text: "Zamknij"; onClicked: win.sheet = null }
            }
        }
    }
    Component {
        id: saveSheet
        Column {
            id: sv
            property string target: Pulse.collections.length ? Pulse.collections[0].file : ""
            spacing: 10
            Title { text: "Zapisz zapytanie" }
            Detail { text: "Kolekcja to plik JSON w " + Pulse.prettyPath(Pulse.workspaceDir) }
            Field { id: saveName; width: parent.width; vars: false; text: win.req.name; Component.onCompleted: focusEnd() }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: Pulse.collections
                    delegate: HoverButton {
                        id: cc
                        required property var modelData
                        readonly property bool active: sv.target === modelData.file
                        width: ccText.implicitWidth + 24; height: 30; radius: 15
                        baseColor: active ? Theme.accentSoft : Theme.fill
                        border.width: active ? 1 : 0; border.color: Theme.accentAlpha(0.5)
                        onClicked: sv.target = modelData.file
                        Text { id: ccText; anchors.centerIn: parent; text: cc.modelData.name; color: cc.active ? Theme.accentText : Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                    }
                }
                HoverButton {
                    width: ncText.implicitWidth + 24; height: 30; radius: 15
                    baseColor: sv.target === "" ? Theme.accentSoft : Theme.fill
                    onClicked: { sv.target = ""; newCol.focusEnd(); }
                    Text { id: ncText; anchors.centerIn: parent; text: "+ Nowa kolekcja"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                }
            }
            Field { id: newCol; visible: sv.target === ""; width: parent.width; vars: false; placeholder: "Nazwa nowej kolekcji" }
            Item {
                width: parent.width; height: 34
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Pill { text: "Anuluj"; onClicked: win.sheet = null }
                    Pill {
                        text: "Zapisz"; primary: true
                        enabled: saveName.text.trim() !== "" && (sv.target !== "" || newCol.text.trim() !== "")
                        onClicked: {
                            const file = sv.target !== "" ? sv.target : Pulse.createCollection(newCol.text);
                            if (!file) return;
                            const saved = Pulse.saveRequest(file, Object.assign({}, win.req, { name: saveName.text.trim() }));
                            if (!saved.id) return;
                            win.sheet = null;
                            win.req = Object.assign({}, win.req, { id: saved.id, name: saved.name });
                            win.reqFile = file;
                            win.dirty = false;
                            win.toast("Zapisano w „" + (Pulse.collections.find(c => c.file === file) || { name: file }).name + "”");
                        }
                    }
                }
            }
        }
    }
    Component {
        id: promptSheet
        Column {
            spacing: 12
            Title { text: win.sheet.title }
            Field {
                id: promptField
                width: parent.width; vars: false
                placeholder: win.sheet.placeholder || ""
                Component.onCompleted: { setText(win.sheet.value || ""); focusEnd(); }
                onAccepted: okBtn.clicked()
            }
            Item {
                width: parent.width; height: 34
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Pill { text: "Anuluj"; onClicked: win.sheet = null }
                    Pill {
                        id: okBtn
                        text: win.sheet.button; primary: true
                        enabled: promptField.text.trim() !== ""
                        onClicked: { const a = win.sheet.action; const t = promptField.text.trim(); win.sheet = null; a(t); }
                    }
                }
            }
        }
    }
    Component {
        id: confirmSheet
        Column {
            spacing: 8
            Title { text: win.sheet.title }
            Detail { text: win.sheet.detail || "" }
            Item { width: 1; height: 8 }
            Item {
                width: parent.width; height: 34
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Pill { text: "Anuluj"; onClicked: win.sheet = null }
                    Pill { text: win.sheet.button; danger: true; onClicked: { const a = win.sheet.action; win.sheet = null; a(); } }
                }
            }
        }
    }
    component Title: Text { width: parent ? parent.width : 300; wrapMode: Text.Wrap; color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold }
    component Detail: Text { width: parent ? parent.width : 300; wrapMode: Text.Wrap; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2 }
}
