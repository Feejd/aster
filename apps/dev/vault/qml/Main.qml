pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Dialogs
import QtQuick.Effects
import Aster.Ui
import Aster.Vault

// Aster Vault — bazy danych dla programistów: SQLite (plik), PostgreSQL i MySQL/MariaDB.
//  • z lewej: tabele i widoki otwartej bazy (szukanie, przełączanie baz na serwerze),
//  • Dane: siatka z edycją, dodawaniem i usuwaniem — zmiany czekają na podgląd i zapis w jednej transakcji,
//  • Struktura: kolumny, klucze, indeksy, definicja; SQL: edytor z podpowiedziami, wynik, historia, eksport.
Window {
    id: win
    width: 1180 + 2 * m
    height: 740 + 2 * m
    minimumWidth: 820 + 2 * m
    minimumHeight: 500 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: Vault.state === "open" ? (Vault.current.name || "") + " — Aster Vault" : "Aster Vault"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 24
    readonly property bool open: Vault.state === "open"

    property string page: "data"          // data | structure | query
    property string search: ""
    property var detail: null             // { row, grid: "table"|"result", values }
    property var confirm: null            // { text, detail, button, action }
    property string exportWhat: "result"
    property string exportFormat: "csv"

    function toast(text) { toastBox.text = text; toastBox.shown = true; toastTimer.restart(); }
    function plural(n, one, few, many) {
        const t = n % 100, u = n % 10;
        return n + " " + (n === 1 ? one : (u >= 2 && u <= 4 && (t < 12 || t > 14)) ? few : many);
    }
    function kindColor(k) { return k === "postgres" ? "#4F6BED" : k === "mysql" ? "#E8833A" : "#2BA3C9"; }

    // Tabele i widoki w grupach, po filtrze
    readonly property var objectList: {
        const q = search.toLowerCase();
        const pg = Vault.current.kind === "postgres";
        const out = [];
        for (const o of Vault.objects) {
            if (q && o.name.toLowerCase().indexOf(q) < 0) continue;
            const kind = o.type === "view" ? "Widoki" : "Tabele";
            out.push({ schema: o.schema, name: o.name, type: o.type,
                       group: pg && o.schema !== "public" ? o.schema + " · " + kind : kind });
        }
        return out;
    }

    function openTable(schema, name) {
        if (Vault.table.changeCount > 0) {
            confirm = { text: "Porzucić niezapisane zmiany?", detail: "W tabeli „" + Vault.tableName + "” są zmiany, które nie trafiły jeszcze do bazy.",
                        button: "Porzuć", action: () => { Vault.table.revertAll(); win.openTable(schema, name); } };
            return;
        }
        Vault.selectTable(schema, name);
        if (page === "query") page = "data";
        filterInput.text = "";
    }
    function openTableByName(full) {
        let schema = "", name = full;
        const dot = full.indexOf(".");
        if (dot > 0 && Vault.current.kind === "postgres") { schema = full.slice(0, dot); name = full.slice(dot + 1); }
        for (const o of Vault.objects)
            if (o.name === name && (!schema || o.schema === schema)) { openTable(o.schema, o.name); return; }
        toast("Nie ma tabeli „" + full + "”");
    }
    function runSql(sql) {
        if (Vault.risky(sql) && !Vault.readOnly) {
            confirm = { text: "Wykonać zmianę, której nie da się cofnąć?",
                        detail: "Zapytanie usuwa tabelę albo zmienia/usuwa wszystkie wiersze (bez WHERE):\n\n" + sql.trim().slice(0, 300),
                        button: "Wykonaj", action: () => Vault.runQuery(sql) };
            return;
        }
        Vault.runQuery(sql);
    }
    function askExport(what, format) {
        exportWhat = what; exportFormat = format;
        exportDialog.currentFile = "file://" + Vault.suggestedExportPath(what, format);
        exportDialog.open();
    }
    function showRow(gridName, row) {
        const g = gridName === "table" ? Vault.table : Vault.result;
        // Typ z bazy (tabela) albo czytelna nazwa typu Qt (wynik zapytania)
        const names = { QString: "tekst", int: "liczba", qlonglong: "liczba", uint: "liczba", qulonglong: "liczba", double: "liczba",
                        bool: "tak/nie", QDateTime: "data i czas", QDate: "data", QTime: "czas", QByteArray: "dane" };
        const cols = (gridName === "table" && Vault.tableInfo.columns) || [];
        const values = g.rowValues(row).map(v => {
            const c = cols.find(x => x.name === v.name);
            v.type = c ? c.type : (names[v.type] || v.type);
            return v;
        });
        detail = { grid: gridName, row: row, values: values, editable: g.editable };
    }
    function closeConnection() {
        if (Vault.table.changeCount > 0) {
            confirm = { text: "Rozłączyć bez zapisu zmian?", detail: "Niezapisane zmiany w „" + Vault.tableName + "” przepadną.", button: "Rozłącz",
                        action: () => { Vault.table.revertAll(); Vault.close(); } };
            return;
        }
        Vault.close();
    }

    // ——— Menu ———
    function showConnectionMenu(c, x, y) {
        menu.ctx = c;
        menu.openAt(x, y, [
            { label: "Połącz", icon: "play", action: "conn-open" },
            { label: "Edytuj…", icon: "pencil", action: "conn-edit" },
            { separator: true },
            { label: "Usuń połączenie", icon: "trash", action: "conn-remove", danger: true }
        ]);
    }
    function showCellMenu(gridName, row, col, x, y) {
        const g = gridName === "table" ? Vault.table : Vault.result;
        menu.ctx = { grid: gridName, row: row, col: col };
        const items = [];
        if (g.cellEditable(row, col)) {
            items.push({ label: "Edytuj komórkę", icon: "pencil", shortcut: "Enter", action: "cell-edit" });
            items.push({ label: "Ustaw NULL", icon: "close", action: "cell-null" });
        }
        items.push({ label: "Pokaż cały wiersz", icon: "eye", action: "cell-row" });
        items.push({ separator: true });
        items.push({ label: "Kopiuj wartość", icon: "copy", shortcut: "Ctrl+C", action: "cell-copy" });
        items.push({ label: "Kopiuj wiersz", icon: "copy", shortcut: "Ctrl+Shift+C", action: "cell-copy-row" });
        if (gridName === "table" && g.editable) {
            items.push({ separator: true });
            items.push({ label: "Usuń wiersz / przywróć", icon: "trash", shortcut: "Del", action: "cell-delete", danger: true });
        }
        menu.openAt(x, y, items);
    }
    function runMenu(a) {
        const c = menu.ctx;
        if (a === "conn-open") Vault.open(c.id);
        else if (a === "conn-edit") connSheet.openFor(c);
        else if (a === "conn-remove")
            confirm = { text: "Usunąć połączenie „" + c.name + "”?", detail: "Zniknie z listy razem z historią zapytań i hasłem w portfelu. Sama baza danych zostaje nietknięta.",
                        button: "Usuń", action: () => Vault.removeConnection(c.id) };
        else if (a.startsWith("cell-")) {
            const g = c.grid === "table" ? Vault.table : Vault.result;
            const gridItem = c.grid === "table" ? dataGrid : null;
            if (a === "cell-edit" && gridItem) { gridItem.select(c.row, c.col); gridItem.startEdit(); }
            else if (a === "cell-null") g.setCell(c.row, c.col, "", true);
            else if (a === "cell-row") showRow(c.grid, c.row);
            else if (a === "cell-copy") { Vault.copy(g.copyText(c.row, c.col, false)); toast("Skopiowano"); }
            else if (a === "cell-copy-row") { Vault.copy(g.copyText(c.row, c.col, true)); toast("Skopiowano wiersz"); }
            else if (a === "cell-delete") g.toggleDelete(c.row);
        } else if (a === "side-refresh") Vault.refresh();
        else if (a === "side-edit") connSheet.openFor(Vault.connection(Vault.current.id));
        else if (a === "side-close") closeConnection();
        else if (a.startsWith("db:")) Vault.useDatabase(a.slice(3));
        else if (a.startsWith("export:")) askExport("table", a.slice(7));
        else if (a === "table-sql") { page = "query"; queryPage.text = Vault.selectSql(Vault.tableSchema, Vault.tableName); queryPage.focusEditor(); }
        else if (a === "table-copy-name") { Vault.copy(Vault.tableName); toast("Skopiowano nazwę"); }
    }

    // ——— Testy (ASTER_OPEN) ———
    function testOpen(what) {
        const s = String(what);
        if (s.startsWith("file:")) Vault.openFile(s.slice(5));
        else if (s.startsWith("conn:")) {
            const parts = s.slice(5).split(":");
            for (const c of Vault.connections) if (c.name === parts[0]) Vault.open(c.id, parts[1] || "");
        }
        else if (s.startsWith("table:")) openTableByName(s.slice(6));
        else if (s === "structure") page = "structure";
        else if (s === "data") page = "data";
        else if (s.startsWith("query:")) { page = "query"; queryPage.text = s.slice(6); Qt.callLater(() => runSql(s.slice(6))); }
        else if (s.startsWith("sql:")) { page = "query"; queryPage.text = s.slice(4).replace(/\\n/g, "\n"); }
        else if (s.startsWith("complete:")) { queryPage.cursorAfter(s.slice(9)); queryPage.updateCompletion(true); }
        else if (s === "new") connSheet.openFor({});
        else if (s.startsWith("export:")) { const p = s.slice(7).split(","); Vault.exportTo(p[0], p[2], p[1]); }
        else if (s.startsWith("save:")) {
            // save:id:hasło — zapis hasła do portfela tak jak z formularza
            const p = s.slice(5).split(":");
            const c = Vault.connection(p[0]); c.savePassword = true; c.askPassword = false;
            Vault.saveConnection(c, p.slice(1).join(":"));
        }
        else if (s.startsWith("edit:")) {
            // edit:wiersz,kolumna,wartość
            const p = s.slice(5).split(",");
            Vault.table.setCell(Number(p[0]), Number(p[1]), p.slice(2).join(","), false);
        }
        else if (s.startsWith("delete:")) Vault.table.toggleDelete(Number(s.slice(7)));
        else if (s === "add") { const r = Vault.table.addRow(); Vault.table.setCell(r, 1, "Nowy produkt", false); }
        else if (s === "preview") changes.openPreview();
        else if (s === "more") Vault.loadMore();
        else if (s === "commit") Vault.commitChanges();
        else if (s.startsWith("row:")) showRow("table", Number(s.slice(4)));
        else if (s.startsWith("filter:")) { filterInput.text = s.slice(7); Vault.setFilter(s.slice(7)); }
        else if (s.startsWith("sort:")) Vault.sortBy(s.slice(5));
        else if (s.startsWith("select:")) { const p = s.slice(7).split(","); dataGrid.select(Number(p[0]), Number(p[1])); }
        else if (s === "menu") showCellMenu("table", 1, 1, 520, 260);
    }

    Shortcut { sequence: "Ctrl+N"; onActivated: connSheet.openFor({}) }
    Shortcut { sequence: "Ctrl+O"; onActivated: openDialog.open() }
    Shortcut { sequence: "Ctrl+W"; onActivated: win.close() }
    Shortcut { sequence: "Ctrl+T"; enabled: win.open; onActivated: { win.page = "query"; queryPage.focusEditor(); } }
    Shortcut { sequence: "Ctrl+1"; enabled: win.open && Vault.tableName !== ""; onActivated: win.page = "data" }
    Shortcut { sequence: "Ctrl+2"; enabled: win.open && Vault.tableName !== ""; onActivated: win.page = "structure" }
    Shortcut { sequence: "Ctrl+3"; enabled: win.open; onActivated: win.page = "query" }
    Shortcut { sequence: "Ctrl+S"; enabled: win.open && Vault.table.changeCount > 0; onActivated: changes.openPreview() }
    Shortcut { sequence: "F5"; enabled: win.open; onActivated: { if (win.page === "query") queryPage.runCurrent(); else { Vault.reloadTable(); Vault.refresh(); } } }
    Shortcut { sequence: "Ctrl+F"; enabled: win.open; onActivated: { if (win.page === "data" && Vault.tableName) filterInput.forceActiveFocus(); else searchInput.forceActiveFocus(); } }
    Shortcut { sequence: "Ctrl+Shift+A"; enabled: win.open && Vault.table.editable && win.page === "data"; onActivated: dataGrid.addRow() }
    Shortcut {
        sequence: "Esc"
        enabled: !!win.detail || !!win.confirm || connSheet.shown || changes.shown || passSheet.shown
        onActivated: { win.detail = null; win.confirm = null; connSheet.shown = false; if (!changes.saving) changes.shown = false; passSheet.shown = false; }
    }

    Connections {
        target: Vault
        function onMessage(text) { win.toast(text); }
        function onCommitted(ok, message) { if (ok || !changes.shown) win.toast(message); }
        function onPasswordNeeded(id, message) { passSheet.ask(id, message); }
        function onStateChanged() { if (Vault.state === "open") { win.page = Vault.tableName ? win.page : "data"; } }
    }

    // ——— Okno ———
    function updateEffects() {
        WindowEffects.setBlur(win, Qt.rect(m, m, frame.width, frame.height), r);
        WindowEffects.setInputRegion(win, Qt.rect(Math.max(0, m - 6), Math.max(0, m - 6), frame.width + (maxed ? 0 : 12), frame.height + (maxed ? 0 : 12)));
    }
    Component.onCompleted: effectsTimer.restart()
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

        // ——— Bez połączenia: ekran startowy ———
        StartPage {
            anchors.fill: parent
            visible: !win.open
            radius: win.r
            onNewConnection: connSheet.openFor({})
            onOpenFile: openDialog.open()
            onNewFile: newDialog.open()
            onConnectionMenu: (c, x, y) => win.showConnectionMenu(c, x, y)
        }

        // ——— Pasek boczny ———
        Item {
            id: side
            visible: win.open
            width: 248; height: parent.height
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }

            // Połączenie
            HoverButton {
                id: connHead
                x: 10; y: 14
                width: parent.width - 20; height: 52; radius: 12
                onClicked: {
                    const p = mapToItem(frame, 0, height + 4);
                    menu.ctx = {};
                    menu.openAt(p.x, p.y, [
                        { label: "Odśwież listę tabel", icon: "reload", shortcut: "F5", action: "side-refresh" },
                        { label: "Edytuj połączenie…", icon: "pencil", action: "side-edit" },
                        { separator: true },
                        { label: "Rozłącz", icon: "power", action: "side-close" }
                    ]);
                }
                Rectangle {
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    width: 32; height: 32; radius: 9
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(win.kindColor(Vault.current.kind), 1.35) }
                        GradientStop { position: 1; color: win.kindColor(Vault.current.kind) }
                    }
                    Icon { anchors.centerIn: parent; d: Icons.database; size: 16; stroke: 1.9; color: "white" }
                }
                Column {
                    x: 50; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 76
                    spacing: 1
                    Text { width: parent.width; elide: Text.ElideRight; text: Vault.current.name || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: Vault.kindName + (Vault.readOnly ? " · tylko odczyt" : "")
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                    }
                }
                Icon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.chevronDown; size: 12; stroke: 2; color: Theme.text2 }
            }

            // Baza na serwerze
            HoverButton {
                id: dbButton
                visible: Vault.databases.length > 0
                x: 10; y: connHead.y + connHead.height + 6
                width: parent.width - 20; height: 32; radius: 9
                baseColor: Theme.fill
                onClicked: {
                    const p = mapToItem(frame, 0, height + 4);
                    menu.ctx = {};
                    menu.openAt(p.x, p.y, Vault.databases.map(d => ({ label: d, icon: d === Vault.database ? "check" : "database", action: "db:" + d })));
                }
                Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: "Baza"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                Text {
                    x: 52; width: parent.width - 80; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                    text: Vault.database || "wybierz…"; color: Theme.text; font.family: "JetBrains Mono"; font.pixelSize: 12
                }
                Icon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.chevronDown; size: 12; stroke: 2; color: Theme.text2 }
            }

            // Zapytanie SQL
            Rectangle {
                id: queryNav
                x: 10; y: (dbButton.visible ? dbButton.y + dbButton.height : connHead.y + connHead.height) + 10
                width: parent.width - 20; height: 34; radius: 9
                readonly property bool active: win.page === "query"
                color: active ? Theme.accent : qnArea.containsMouse ? Theme.hover : "transparent"
                Rectangle {
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24; radius: 7
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#C4B5FD" }
                        GradientStop { position: 1; color: "#7C3AED" }
                    }
                    Icon { anchors.centerIn: parent; d: Icons.code; size: 14; stroke: 2; color: "white" }
                }
                Text { x: 42; anchors.verticalCenter: parent.verticalCenter; text: "Zapytanie SQL"; color: queryNav.active ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: queryNav.active ? Font.Medium : Font.Normal }
                Text { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: "Ctrl+T"; color: queryNav.active ? Qt.rgba(1, 1, 1, 0.7) : Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
                MouseArea { id: qnArea; anchors.fill: parent; hoverEnabled: true; onClicked: { win.page = "query"; queryPage.focusEditor(); } }
            }

            // Szukaj tabeli
            Rectangle {
                id: searchBox
                x: 10; y: queryNav.y + queryNav.height + 12
                width: parent.width - 20; height: 32; radius: 9
                color: Theme.fill
                border.width: searchInput.activeFocus ? 1.5 : 0; border.color: Theme.accent
                Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 14; color: Theme.text2 }
                TextInput {
                    id: searchInput
                    x: 32; width: parent.width - 42
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text; selectionColor: Theme.accentSoft; font.family: Theme.font; font.pixelSize: 13
                    clip: true
                    onTextChanged: win.search = text
                    Keys.onEscapePressed: text = ""
                    Keys.onReturnPressed: if (win.objectList.length) win.openTable(win.objectList[0].schema, win.objectList[0].name)
                    Text { visible: !searchInput.text; text: "Szukaj tabeli"; color: Theme.text2; font: searchInput.font }
                }
            }

            ListView {
                id: objects
                x: 10; y: searchBox.y + searchBox.height + 6
                width: parent.width - 20; height: parent.height - y - 12
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: win.objectList
                section.property: "group"
                section.delegate: Item {
                    id: sec
                    required property string section
                    width: ListView.view.width; height: 30
                    Text { x: 10; y: 12; text: sec.section.toUpperCase(); color: Theme.text2; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Medium; font.letterSpacing: 0.4 }
                }
                delegate: Rectangle {
                    id: ob
                    required property var modelData
                    readonly property bool active: win.page !== "query" && Vault.tableName === modelData.name && Vault.tableSchema === modelData.schema
                    width: ListView.view.width; height: 30; radius: 8
                    color: active ? Theme.accentSoft : obArea.containsMouse ? Theme.hover : "transparent"
                    Icon {
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        d: ob.modelData.type === "view" ? Icons.eye : Icons.sheet
                        size: 14; stroke: 1.8
                        color: ob.active ? Theme.accentText : Theme.text2
                    }
                    Text {
                        x: 32; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: ob.modelData.name
                        color: ob.active ? Theme.accentText : Theme.text
                        font.family: Theme.font; font.pixelSize: 13; font.weight: ob.active ? Font.Medium : Font.Normal
                    }
                    MouseArea {
                        id: obArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (m) => {
                            win.openTable(ob.modelData.schema, ob.modelData.name);
                        }
                        onDoubleClicked: { win.page = "query"; queryPage.text = Vault.selectSql(ob.modelData.schema, ob.modelData.name); queryPage.runAll(); }
                    }
                }
                Text {
                    visible: win.objectList.length === 0
                    x: 10; y: 14; width: parent.width - 20; wrapMode: Text.Wrap
                    text: win.search ? "Nic nie pasuje do „" + win.search + "”" : Vault.busy ? "Wczytuję…" : "Baza nie ma jeszcze tabel. Utwórz je w zapytaniu SQL (CREATE TABLE …)."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
            }
        }

        // ——— Treść ———
        GlassPane {
            id: main
            visible: win.open
            x: side.width
            width: parent.width - side.width
            height: parent.height
            topRightRadius: win.r; bottomRightRadius: win.r

            Item {
                id: topBar
                width: parent.width; height: 64
                z: 5
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }
                Column {
                    x: 28; anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(100, tabs.x - 40)
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: win.page === "query" ? "Zapytanie SQL" : Vault.tableName || (Vault.database || Vault.current.name || "")
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 20; font.weight: Font.Bold; font.letterSpacing: -0.4
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        visible: text !== ""
                        text: win.page === "query" ? (Vault.current.name || "") + (Vault.database ? " · " + Vault.database : "")
                            : Vault.tableName ? ((Vault.tableInfo.type === "view" ? "widok" : "tabela") + (Vault.tableSchema && Vault.current.kind === "postgres" ? " w " + Vault.tableSchema : "")
                                                 + (Vault.tableInfo.columns ? " · " + win.plural(Vault.tableInfo.columns.length, "kolumna", "kolumny", "kolumn") : ""))
                            : ""
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                    }
                }
                // Dane | Struktura
                Rectangle {
                    id: tabs
                    visible: win.page !== "query" && Vault.tableName !== ""
                    anchors.right: winButtons.left; anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    width: tabRow.implicitWidth + 6; height: 34; radius: 17
                    color: Theme.fill
                    Row {
                        id: tabRow
                        x: 3; anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: [["data", "Dane"], ["structure", "Struktura"]]
                            delegate: Rectangle {
                                id: tb
                                required property var modelData
                                readonly property bool active: win.page === modelData[0]
                                width: tbText.implicitWidth + 30; height: 28; radius: 14
                                color: active ? Theme.surface : "transparent"
                                Text { id: tbText; anchors.centerIn: parent; text: tb.modelData[1]; color: tb.active ? Theme.text : Theme.text2; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                                MouseArea { anchors.fill: parent; onClicked: win.page = tb.modelData[0] }
                            }
                        }
                    }
                }
                WindowButtons {
                    id: winButtons
                    window: win
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line; visible: win.page !== "query" }
            }

            // ——— Dane ———
            Item {
                id: dataPage
                y: topBar.height
                width: parent.width; height: parent.height - y
                visible: win.page === "data" && Vault.tableName !== ""

                Item {
                    id: tools
                    width: parent.width; height: 50
                    Rectangle {
                        id: filterBox
                        x: 20; anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(420, parent.width - toolRow.width - 60); height: 32; radius: 9
                        color: Theme.fill
                        border.width: filterInput.activeFocus ? 1.5 : 0; border.color: Theme.accent
                        Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.filter; size: 14; color: Vault.filter ? Theme.accentText : Theme.text2 }
                        Text { id: whereLabel; x: 32; anchors.verticalCenter: parent.verticalCenter; text: "WHERE"; color: Theme.text2; font.family: "JetBrains Mono"; font.pixelSize: 11; font.weight: Font.Medium }
                        TextInput {
                            id: filterInput
                            x: whereLabel.x + whereLabel.width + 8; width: parent.width - x - 30
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.text; selectionColor: Theme.accentSoft; font.family: "JetBrains Mono"; font.pixelSize: 12
                            clip: true
                            onAccepted: Vault.setFilter(text)
                            Keys.onEscapePressed: { text = ""; Vault.setFilter(""); dataGrid.forceActiveFocus(); }
                            Text { visible: !filterInput.text; text: "np. cena > 100 AND nazwa LIKE '%kawa%'"; color: Theme.text2; opacity: 0.7; font: filterInput.font }
                        }
                        Icon {
                            visible: Vault.filter !== ""
                            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                            d: Icons.close; size: 12; stroke: 2; color: Theme.text2
                            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: { filterInput.text = ""; Vault.setFilter(""); } }
                        }
                    }
                    Row {
                        id: toolRow
                        anchors.right: parent.right; anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            rightPadding: 8
                            text: Vault.tableLoading ? "Wczytuję…" : win.plural(Vault.table.rows, "wiersz", "wiersze", "wierszy") + (Vault.hasMore ? "+" : "")
                            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                        }
                        Pill { small: true; visible: Vault.table.editable; text: "Wiersz"; icon: "plus"; tip: "Nowy wiersz (Ctrl+Shift+A)"; onClicked: dataGrid.addRow() }
                        ToolBtn {
                            visible: Vault.table.editable
                            icon: "trash"; tip: "Usuń zaznaczony wiersz (Del)"
                            enabled: dataGrid.curRow >= 0
                            onClicked: Vault.table.toggleDelete(dataGrid.curRow)
                        }
                        ToolBtn { icon: "reload"; tip: "Odśwież (F5)"; onClicked: Vault.reloadTable() }
                        ToolBtn {
                            id: moreBtn
                            icon: "more"; tip: "Więcej"
                            onClicked: {
                                const p = mapToItem(frame, width, height + 6);
                                menu.ctx = {};
                                menu.openAt(p.x - 250, p.y, [
                                    { label: "Eksportuj do CSV…", icon: "download", action: "export:csv" },
                                    { label: "Eksportuj do JSON…", icon: "download", action: "export:json" },
                                    { separator: true },
                                    { label: "Otwórz w zapytaniu SQL", icon: "code", action: "table-sql" },
                                    { label: "Kopiuj nazwę tabeli", icon: "copy", action: "table-copy-name" }
                                ]);
                            }
                        }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                }

                // Dlaczego bez edycji
                Rectangle {
                    id: roBanner
                    visible: Vault.table.readOnlyReason !== "" && Vault.table.columns.length > 0
                    y: tools.height
                    width: parent.width; height: visible ? 30 : 0
                    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.025)
                    Row {
                        x: 20; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                        Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.lock; size: 12; stroke: 2; color: Theme.text2 }
                        Text { text: Vault.table.readOnlyReason; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                }

                DataGrid {
                    id: dataGrid
                    y: tools.height + roBanner.height
                    width: parent.width
                    height: parent.height - y - (changeBar.visible ? changeBar.height : 0)
                    model: Vault.table
                    info: Vault.tableInfo
                    order: Vault.order
                    sortable: true
                    hasMore: Vault.hasMore
                    onSortRequested: (c) => Vault.sortBy(c)
                    onNeedMore: Vault.loadMore()
                    onCellMenu: (r, c, x, y) => { const p = mapToItem(frame, x, y); win.showCellMenu("table", r, c, p.x, p.y); }
                    onOpenRow: (r) => win.showRow("table", r)
                }
                Text {
                    visible: !Vault.tableLoading && Vault.tableError !== ""
                    x: 24; y: tools.height + 24; width: parent.width - 48; wrapMode: Text.Wrap
                    text: Vault.tableError
                    color: Theme.danger; font.family: Theme.font; font.pixelSize: 13
                }
                Text {
                    visible: !Vault.tableLoading && Vault.tableError === "" && Vault.table.rows === 0 && Vault.table.columns.length > 0
                    anchors.horizontalCenter: parent.horizontalCenter; y: tools.height + 90
                    text: Vault.filter ? "Żaden wiersz nie spełnia warunku" : "Tabela jest pusta"
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                }

                // Niezapisane zmiany
                Rectangle {
                    id: changeBar
                    visible: Vault.table.changeCount > 0
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 56
                    color: Theme.dark ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.025)
                    bottomRightRadius: win.r
                    Rectangle { width: parent.width; height: 1; color: Theme.line }
                    Row {
                        x: 20; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: Theme.accent }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.plural(Vault.table.changeCount, "niezapisana zmiana", "niezapisane zmiany", "niezapisanych zmian")
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "— baza zmieni się dopiero po zapisie"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Pill { text: "Cofnij wszystkie"; icon: "undo"; onClicked: Vault.table.revertAll() }
                        Pill { text: "Podgląd i zapis…"; primary: true; tip: "Ctrl+S"; onClicked: changes.openPreview() }
                    }
                }
            }

            // ——— Struktura ———
            StructureView {
                y: topBar.height
                width: parent.width; height: parent.height - y
                visible: win.page === "structure" && Vault.tableName !== ""
                info: Vault.tableInfo
                onOpenTable: (n) => { win.openTableByName(n); win.page = "structure"; }
                onToast: (t) => win.toast(t)
            }

            // ——— Zapytanie ———
            QueryPage {
                id: queryPage
                y: topBar.height
                width: parent.width; height: parent.height - y
                visible: win.page === "query"
                onRunRequested: (sql) => win.runSql(sql)
                onExportRequested: (f) => win.askExport("result", f)
                onCellMenu: (r, c, x, y) => { const p = mapToItem(frame, x, y); win.showCellMenu("result", r, c, p.x, p.y); }
                onOpenRow: (r) => win.showRow("result", r)
            }

            // ——— Nic nie wybrano ———
            Column {
                visible: win.page !== "query" && Vault.tableName === ""
                anchors.centerIn: parent
                width: 380
                spacing: 10
                Icon { anchors.horizontalCenter: parent.horizontalCenter; d: Icons.sheet; size: 46; stroke: 1.3; color: Theme.text2; opacity: 0.55 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.plural(Vault.objects.filter(o => o.type !== "view").length, "tabela", "tabele", "tabel") + " · "
                          + win.plural(Vault.objects.filter(o => o.type === "view").length, "widok", "widoki", "widoków")
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Medium
                }
                Text {
                    width: parent.width; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                    text: "Wybierz tabelę z listy po lewej albo napisz zapytanie (Ctrl+T)."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                }
            }

            // Komunikat na dole
            Rectangle {
                id: toastBox
                property bool shown: false
                property alias text: toastText.text
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - (shown ? height + 70 : 0)
                opacity: shown ? 1 : 0
                z: 20
                width: Math.min(toastText.implicitWidth + 36, parent.width - 40); height: 40; radius: 20
                color: Theme.dark ? "#ECEEF3" : "#1E2027"
                Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutQuint } }
                Behavior on opacity { NumberAnimation { duration: 100 } }
                Text { id: toastText; anchors.centerIn: parent; width: Math.min(implicitWidth, parent.width - 36); elide: Text.ElideMiddle; color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                Timer { id: toastTimer; interval: 3200; onTriggered: toastBox.shown = false }
            }
        }

        // Łączenie / błąd połączenia
        Rectangle {
            visible: Vault.state === "connecting" || (!win.open && Vault.error !== "")
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 26
            z: 30
            width: Math.min(connMsg.implicitWidth + 60, parent.width - 60); height: Math.max(44, connMsg.implicitHeight + 24); radius: 22
            color: Vault.state === "connecting" ? (Theme.dark ? "#ECEEF3" : "#1E2027") : (Theme.dark ? "#4A1D1F" : "#FDECEC")
            Text {
                id: connMsg
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 50)
                wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                text: Vault.state === "connecting" ? "Łączę z „" + (Vault.current.name || "") + "”…" : Vault.error
                color: Vault.state === "connecting" ? (Theme.dark ? "#16181D" : "white") : Theme.danger
                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
            }
            MouseArea { anchors.fill: parent; enabled: Vault.state !== "connecting"; onClicked: Vault.clearError() }
        }

        ContextMenu {
            id: menu
            property var ctx: ({})
            onTriggered: (a) => win.runMenu(a)
        }

        ConnectionSheet { id: connSheet; radius: win.r }
        ChangesSheet { id: changes; radius: win.r }

        // Hasło (gdy nie jest zapisane w portfelu albo okazało się złe)
        Sheet {
            id: passSheet
            property string connId
            radius: win.r
            cardWidth: 420
            title: "Hasło do „" + (Vault.connection(connId).name || "") + "”"
            subtitle: "Użytkownik " + (Vault.connection(connId).user || "") + " na " + (Vault.connection(connId).host || "") + ". Hasło zostaje tylko w pamięci, do rozłączenia."
            onDismissed: shown = false
            function ask(id, message) { connId = id; passMsg.text = message; passInput.text = ""; shown = true; passInput.input.forceActiveFocus(); }
            Field { id: passInput; width: parent.width; password: true; label: "Hasło"; onAccepted: { passSheet.shown = false; Vault.open(passSheet.connId, passInput.text); } }
            Text { id: passMsg; visible: text !== ""; width: parent.width; wrapMode: Text.Wrap; color: Theme.danger; font.family: Theme.font; font.pixelSize: 12 }
            Item {
                width: parent.width; height: 34
                Row {
                    anchors.right: parent.right; spacing: 8
                    Pill { text: "Anuluj"; onClicked: passSheet.shown = false }
                    Pill { text: "Połącz"; primary: true; onClicked: { passSheet.shown = false; Vault.open(passSheet.connId, passInput.text); } }
                }
            }
        }

        // Cały wiersz (długie wartości, wiele linii) z edycją
        Sheet {
            id: rowSheet
            radius: win.r
            cardWidth: 620
            shown: !!win.detail
            title: "Wiersz " + (win.detail ? win.detail.row + 1 : "")
            subtitle: win.detail && win.detail.editable ? "Zmiany trafią do listy niezapisanych — zapis po podglądzie." : ""
            onDismissed: win.detail = null
            Flickable {
                width: parent.width
                height: Math.min(contentHeight, win.height - 260)
                contentHeight: rowCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: rowCol
                    width: parent.width
                    spacing: 10
                    Repeater {
                        id: rowRep
                        model: win.detail ? win.detail.values : []
                        delegate: Column {
                            id: rv
                            required property var modelData
                            required property int index
                            property bool nul: modelData["null"]
                            width: rowCol.width
                            spacing: 4
                            Row {
                                spacing: 8
                                Text { text: rv.modelData.name; color: Theme.text; font.family: "JetBrains Mono"; font.pixelSize: 12; font.weight: Font.DemiBold }
                                Text { text: rv.modelData.type; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
                                Text {
                                    visible: rv.modelData.editable
                                    text: rv.nul ? "ustaw wartość" : "ustaw NULL"
                                    color: nulArea.containsMouse ? Theme.accentText : Theme.text2; font.family: Theme.font; font.pixelSize: 11
                                    MouseArea { id: nulArea; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: rv.nul = !rv.nul }
                                }
                            }
                            Rectangle {
                                width: parent.width; height: Math.min(140, Math.max(32, valueEdit.implicitHeight + 14)); radius: 9
                                color: Theme.fill
                                clip: true
                                TextEdit {
                                    id: valueEdit
                                    x: 10; y: 7; width: parent.width - 20
                                    readOnly: !rv.modelData.editable || rv.nul
                                    selectByMouse: true
                                    wrapMode: TextEdit.WrapAnywhere
                                    text: rv.nul ? "NULL" : rv.modelData.value
                                    color: rv.nul ? Theme.text2 : Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                                    font.family: "JetBrains Mono"; font.pixelSize: 12; font.italic: rv.nul
                                }
                            }
                            function save() {
                                if (!rv.modelData.editable) return;
                                const g = win.detail.grid === "table" ? Vault.table : Vault.result;
                                g.setCell(win.detail.row, rv.index, rv.nul ? "" : valueEdit.text, rv.nul);
                            }
                        }
                    }
                }
            }
            Item {
                width: parent.width; height: 34
                Pill { text: "Kopiuj jako JSON"; icon: "copy"; onClicked: {
                    const o = {};
                    for (const v of win.detail.values) o[v.name] = v["null"] ? null : v.value;
                    Vault.copy(JSON.stringify(o, null, 2)); win.toast("Skopiowano wiersz jako JSON");
                } }
                Row {
                    anchors.right: parent.right; spacing: 8
                    Pill { text: win.detail && win.detail.editable ? "Anuluj" : "Zamknij"; onClicked: win.detail = null }
                    Pill {
                        visible: !!win.detail && win.detail.editable
                        text: "Zastosuj"; primary: true
                        onClicked: { for (let i = 0; i < rowRep.count; ++i) rowRep.itemAt(i).save(); win.detail = null; }
                    }
                }
            }
        }

        // Pytanie przed nieodwracalnym
        Sheet {
            radius: win.r
            cardWidth: 440
            shown: !!win.confirm
            title: win.confirm ? win.confirm.text : ""
            subtitle: win.confirm ? win.confirm.detail : ""
            onDismissed: win.confirm = null
            Item {
                width: parent.width; height: 34
                Row {
                    anchors.right: parent.right; spacing: 8
                    Pill { text: "Anuluj"; onClicked: win.confirm = null }
                    Pill { text: win.confirm ? win.confirm.button : ""; danger: true; onClicked: { const a = win.confirm.action; win.confirm = null; a(); } }
                }
            }
        }
    }

    FileDialog {
        id: openDialog
        title: "Otwórz bazę SQLite"
        nameFilters: ["Bazy SQLite (*.db *.sqlite *.sqlite3 *.db3)", "Wszystkie pliki (*)"]
        onAccepted: Vault.openFile(String(selectedFile))
    }
    FileDialog {
        id: newDialog
        title: "Nowa baza SQLite"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "db"
        nameFilters: ["Bazy SQLite (*.db *.sqlite)"]
        onAccepted: Vault.openFile(String(selectedFile), true)
    }
    FileDialog {
        id: exportDialog
        title: win.exportFormat === "json" ? "Eksport do JSON" : "Eksport do CSV"
        fileMode: FileDialog.SaveFile
        defaultSuffix: win.exportFormat
        nameFilters: win.exportFormat === "json" ? ["JSON (*.json)"] : ["CSV (*.csv)"]
        onAccepted: Vault.exportTo(win.exportWhat, String(selectedFile), win.exportFormat)
    }
}
