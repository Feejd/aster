pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Vault

// Siatka wierszy (tabela albo wynik zapytania). Klik — wybór komórki, dwuklik/Enter/F2 — edycja w miejscu,
// strzałki i Tab — ruch, Delete — usuń/przywróć wiersz, Ctrl+C — kopiuj. Zmiany tylko w modelu (podgląd przed zapisem).
FocusScope {
    id: grid
    property GridModel model
    property var info: ({})               // struktura tabeli: typy i klucze w nagłówku
    property string order: ""             // aktualne sortowanie ("kol" / "kol" DESC)
    property bool sortable: false
    property bool hasMore: false
    property int curRow: -1
    property int curCol: -1
    property var widths: []
    readonly property int rowH: 30
    readonly property int headH: 36
    readonly property int gutterW: Math.max(44, String(model ? model.rows : 0).length * 8 + 22)
    readonly property bool editing: editor.visible

    signal sortRequested(string column)
    signal needMore()
    signal cellMenu(int row, int col, real x, real y)
    signal openRow(int row)

    function resetWidths() {
        const w = [];
        if (model)
            for (let i = 0; i < model.columns.length; ++i) {
                // Nagłówek pokazuje też typ i klucz — kolumna nie może być węższa niż one
                const ci = colInfo(model.columns[i]);
                const head = ci ? Math.min(220, ci.type.length * 6.4 + (ci.pk ? 44 : 28)) : 0;
                w.push(Math.max(model.suggestedWidth(i), head));
            }
        widths = w;
        table.forceLayout();
    }
    Connections {
        target: grid.model
        function onLayoutReset() { grid.curRow = -1; grid.curCol = -1; editor.visible = false; grid.resetWidths(); }
    }
    Component.onCompleted: resetWidths()

    function colInfo(name) {
        const cols = (info && info.columns) || [];
        for (let i = 0; i < cols.length; ++i) if (cols[i].name === name) return cols[i];
        return null;
    }
    function select(r, c) {
        if (!model || model.rows === 0) return;
        curRow = Math.max(0, Math.min(model.rows - 1, r));
        curCol = Math.max(0, Math.min(model.columns.length - 1, c));
        table.positionViewAtCell(Qt.point(curCol, curRow), TableView.Contain);
        grid.forceActiveFocus();
    }
    function startEdit(initial) {
        if (curRow < 0 || !model.cellEditable(curRow, curCol)) return;
        const full = model.cell(curRow, curCol);
        if (full.indexOf("\n") >= 0 || full.length > 300) { grid.openRow(curRow); return; }
        table.positionViewAtCell(Qt.point(curCol, curRow), TableView.Contain);
        const item = table.itemAtCell(Qt.point(curCol, curRow));
        if (!item) return;
        editor.row = curRow; editor.col = curCol;
        editor.x = item.x; editor.y = item.y;
        editor.width = Math.max(item.width, 160); editor.height = item.height;
        editInput.text = initial !== undefined ? initial : (model.isNull(curRow, curCol) ? "" : full);
        editor.visible = true;
        editInput.forceActiveFocus();
        if (initial === undefined) editInput.selectAll();
    }
    function finishEdit(save) {
        if (!editor.visible) return;
        if (save) model.setCell(editor.row, editor.col, editInput.text, false);
        editor.visible = false;
        grid.forceActiveFocus();
    }
    function addRow() {
        const r = model.addRow();
        if (r >= 0) { select(r, 0); Qt.callLater(() => startEdit()); }
    }

    Keys.onPressed: (e) => {
        if (!model || editor.visible) return;
        const ctrl = e.modifiers & Qt.ControlModifier;
        if (e.key === Qt.Key_Down) { select(curRow + 1, Math.max(0, curCol)); e.accepted = true; }
        else if (e.key === Qt.Key_Up) { select(curRow - 1, Math.max(0, curCol)); e.accepted = true; }
        else if (e.key === Qt.Key_Right || (e.key === Qt.Key_Tab && !(e.modifiers & Qt.ShiftModifier))) { select(Math.max(0, curRow), curCol + 1); e.accepted = true; }
        else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab) { select(Math.max(0, curRow), curCol - 1); e.accepted = true; }
        else if (e.key === Qt.Key_PageDown) { select(curRow + Math.floor(table.height / rowH), curCol); e.accepted = true; }
        else if (e.key === Qt.Key_PageUp) { select(curRow - Math.floor(table.height / rowH), curCol); e.accepted = true; }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_F2) { startEdit(); e.accepted = true; }
        else if (e.key === Qt.Key_Delete && curRow >= 0 && model.editable) { model.toggleDelete(curRow); e.accepted = true; }
        else if (ctrl && e.key === Qt.Key_C && curRow >= 0) { Vault.copy(model.copyText(curRow, curCol, e.modifiers & Qt.ShiftModifier)); e.accepted = true; }
        else if (!ctrl && e.text.length === 1 && e.text >= " " && curRow >= 0 && model.cellEditable(curRow, curCol)) {
            // Pisanie od razu zastępuje wartość (jak w arkuszu)
            startEdit(e.text); e.accepted = true;
        }
    }

    // ——— Nagłówek ———
    Rectangle {
        id: header
        width: parent.width; height: grid.headH
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.025)
        clip: true
        z: 2
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        Row {
            x: grid.gutterW - table.contentX
            Repeater {
                model: grid.model ? grid.model.columns : []
                delegate: Item {
                    id: hc
                    required property string modelData
                    required property int index
                    readonly property var ci: grid.colInfo(modelData)
                    readonly property string dir: grid.order === '"' + modelData + '"' || grid.order === "`" + modelData + "`" ? "asc"
                                                : grid.order === '"' + modelData + '" DESC' || grid.order === "`" + modelData + "` DESC" ? "desc" : ""
                    width: grid.widths[index] || 120; height: grid.headH
                    Rectangle { anchors.fill: parent; color: hcArea.containsMouse && grid.sortable ? Theme.hover : "transparent" }
                    Row {
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 20
                        spacing: 5
                        Icon {
                            visible: !!hc.ci && hc.ci.pk
                            anchors.verticalCenter: parent.verticalCenter
                            d: Icons.key; size: 12; stroke: 2; color: "#E0A100"
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - (hc.ci && hc.ci.pk ? 17 : 0) - (hc.dir ? 16 : 0)
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: hc.modelData
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            Text {
                                visible: !!hc.ci
                                width: parent.width; elide: Text.ElideRight
                                text: hc.ci ? hc.ci.type : ""
                                color: Theme.text2; font.family: Theme.font; font.pixelSize: 10
                            }
                        }
                        Icon {
                            visible: hc.dir !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            d: Icons.chevronDown; size: 11; stroke: 2.2; color: Theme.accentText
                            rotation: hc.dir === "asc" ? 180 : 0
                        }
                    }
                    MouseArea {
                        id: hcArea
                        anchors.fill: parent; anchors.rightMargin: 6
                        hoverEnabled: true
                        onClicked: if (grid.sortable) grid.sortRequested(hc.modelData)
                    }
                    Rectangle { anchors.right: parent.right; y: 8; width: 1; height: parent.height - 16; color: Theme.line }
                    // Zmiana szerokości kolumny
                    MouseArea {
                        anchors.right: parent.right; width: 8; height: parent.height
                        cursorShape: Qt.SplitHCursor
                        property real startX: 0
                        property real startW: 0
                        onPressed: (m) => { startX = mapToItem(grid, m.x, 0).x; startW = hc.width; }
                        onPositionChanged: (m) => {
                            if (!pressed) return;
                            const w = grid.widths.slice();
                            w[hc.index] = Math.max(48, startW + mapToItem(grid, m.x, 0).x - startX);
                            grid.widths = w;
                            table.forceLayout();
                        }
                    }
                }
            }
        }
        // Róg nad numerami wierszy
        Rectangle { width: grid.gutterW; height: parent.height; color: Theme.dark ? "#0E0F13" : "#FAFBFC"; Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line } }
    }

    // ——— Numery wierszy ———
    ListView {
        id: gutter
        y: grid.headH
        width: grid.gutterW; height: parent.height - y
        interactive: false
        clip: true
        model: grid.model ? grid.model.rows : 0
        contentY: table.contentY
        delegate: Item {
            required property int index
            width: grid.gutterW; height: grid.rowH
            Text {
                anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                text: index + 1
                color: index === grid.curRow ? Theme.accentText : Theme.text2
                font.family: Theme.font; font.pixelSize: 11; font.features: { "tnum": 1 }
            }
        }
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line; z: 2 }
    }

    // ——— Komórki ———
    TableView {
        id: table
        x: grid.gutterW; y: grid.headH
        width: parent.width - x; height: parent.height - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: grid.model
        reuseItems: true
        columnWidthProvider: (c) => grid.widths[c] || 120
        rowHeightProvider: () => grid.rowH
        onContentYChanged: if (grid.hasMore && contentY + height > contentHeight - 6 * grid.rowH) grid.needMore()
        onMovementStarted: grid.finishEdit(true)

        delegate: Rectangle {
            id: cell
            required property string text
            required property bool isNull
            required property bool edited
            required property string rowState
            required property bool numeric
            required property int row
            required property int column
            readonly property bool current: row === grid.curRow && column === grid.curCol
            implicitHeight: grid.rowH
            color: rowState === "deleted" ? (Theme.dark ? Qt.rgba(0.9, 0.28, 0.3, 0.16) : Qt.rgba(0.9, 0.28, 0.3, 0.09))
                 : rowState === "new" ? (Theme.dark ? Qt.rgba(0.2, 0.75, 0.45, 0.14) : Qt.rgba(0.1, 0.65, 0.35, 0.08))
                 : edited ? Theme.accentAlpha(Theme.dark ? 0.22 : 0.12)
                 : row === grid.curRow ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.045) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.035))
                 : "transparent"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.dark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.04) }
            Rectangle {
                visible: cell.current
                anchors.fill: parent; anchors.margins: 1
                color: "transparent"; radius: 3
                border.width: 1.5; border.color: Theme.accent
            }
            Text {
                x: 10; width: parent.width - 20
                anchors.verticalCenter: parent.verticalCenter
                text: cell.text
                elide: Text.ElideRight
                horizontalAlignment: cell.numeric ? Text.AlignRight : Text.AlignLeft
                color: cell.isNull ? Theme.text2 : Theme.text
                opacity: cell.isNull ? 0.7 : 1
                font.family: Theme.font; font.pixelSize: 12
                font.italic: cell.isNull
                font.strikeout: cell.rowState === "deleted"
                font.features: cell.numeric ? { "tnum": 1 } : {}
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: (m) => { grid.finishEdit(true); grid.select(cell.row, cell.column); }
                onClicked: (m) => {
                    if (m.button === Qt.RightButton) {
                        const p = mapToItem(grid, m.x, m.y);
                        grid.cellMenu(cell.row, cell.column, p.x, p.y);
                    }
                }
                onDoubleClicked: grid.startEdit()
            }
        }

        // Edytor komórki w miejscu
        Rectangle {
            id: editor
            property int row: -1
            property int col: -1
            visible: false
            parent: table.contentItem
            z: 10
            color: Theme.surface
            border.width: 2; border.color: Theme.accent
            radius: 3
            TextInput {
                id: editInput
                x: 9; width: parent.width - 18
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                font.family: Theme.font; font.pixelSize: 12
                clip: true
                selectByMouse: true
                Keys.onReturnPressed: { grid.finishEdit(true); grid.select(grid.curRow + 1, grid.curCol); }
                Keys.onEnterPressed: { grid.finishEdit(true); grid.select(grid.curRow + 1, grid.curCol); }
                Keys.onEscapePressed: grid.finishEdit(false)
                Keys.onTabPressed: { grid.finishEdit(true); grid.select(grid.curRow, grid.curCol + 1); grid.startEdit(); }
                Keys.onBacktabPressed: { grid.finishEdit(true); grid.select(grid.curRow, grid.curCol - 1); grid.startEdit(); }
                onActiveFocusChanged: if (!activeFocus && editor.visible) grid.finishEdit(true)
            }
        }
    }

    // Paski przewijania (tylko wskaźniki z przeciąganiem)
    Rectangle {
        visible: table.contentHeight > table.height
        x: parent.width - 8; y: table.y + table.visibleArea.yPosition * table.height
        width: 5; height: Math.max(24, table.visibleArea.heightRatio * table.height); radius: 2.5
        color: Theme.text2; opacity: vArea.containsMouse || vArea.pressed ? 0.6 : 0.3
        MouseArea {
            id: vArea
            anchors.fill: parent; anchors.margins: -4
            hoverEnabled: true
            drag.target: null
            property real start: 0
            property real startY: 0
            onPressed: (m) => { start = table.contentY; startY = mapToItem(grid, 0, m.y).y; }
            onPositionChanged: (m) => {
                if (!pressed) return;
                const dy = mapToItem(grid, 0, m.y).y - startY;
                table.contentY = Math.max(0, Math.min(table.contentHeight - table.height, start + dy / table.height * table.contentHeight));
            }
        }
    }
    Rectangle {
        visible: table.contentWidth > table.width
        y: parent.height - 8; x: table.x + table.visibleArea.xPosition * table.width
        height: 5; width: Math.max(24, table.visibleArea.widthRatio * table.width); radius: 2.5
        color: Theme.text2; opacity: hArea.containsMouse || hArea.pressed ? 0.6 : 0.3
        MouseArea {
            id: hArea
            anchors.fill: parent; anchors.margins: -4
            hoverEnabled: true
            property real start: 0
            property real startX: 0
            onPressed: (m) => { start = table.contentX; startX = mapToItem(grid, m.x, 0).x; }
            onPositionChanged: (m) => {
                if (!pressed) return;
                const dx = mapToItem(grid, m.x, 0).x - startX;
                table.contentX = Math.max(0, Math.min(table.contentWidth - table.width, start + dx / table.width * table.contentWidth));
            }
        }
    }
}
