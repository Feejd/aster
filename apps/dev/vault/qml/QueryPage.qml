pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Vault

// Edytor zapytań: kolorowanie, podpowiedzi nazw, Ctrl+Enter — polecenie pod kursorem, Ctrl+Shift+Enter — całość;
// wynik w siatce pod spodem, historia z prawej, eksport wyniku do CSV/JSON.
Item {
    id: qp
    property alias text: editor.text
    property bool showHistory: true
    property real split: 0.42
    signal runRequested(string sql)
    signal exportRequested(string format)
    signal cellMenu(int row, int col, real x, real y)
    signal openRow(int row)

    function focusEditor() { editor.forceActiveFocus(); }
    function cursorAfter(t) { const i = editor.text.indexOf(t); if (i >= 0) editor.cursorPosition = i + t.length; editor.forceActiveFocus(); }
    function insertText(t) {
        editor.remove(editor.selectionStart, editor.selectionEnd);
        editor.insert(editor.cursorPosition, t);
        editor.forceActiveFocus();
    }
    function runCurrent() {
        const sql = editor.selectedText !== "" ? editor.selectedText : Vault.statementAt(editor.text, editor.cursorPosition);
        if (sql.trim() !== "") qp.runRequested(sql);
    }
    function runAll() { if (editor.text.trim() !== "") qp.runRequested(editor.text); }
    function updateCompletion(force) {
        const before = editor.text.slice(0, editor.cursorPosition);
        const m = before.match(/([A-Za-z_][\w$]*\.)?([\w$]*)$/);
        const pre = m ? m[2] : "";
        if (!force && pre.length < 1 && !(m && m[1])) { completion.hide(); return; }
        const list = Vault.completions(editor.text, editor.cursorPosition);
        const r = editor.cursorRectangle;
        const p = editor.mapToItem(qp, r.x, r.y + r.height + 4);
        completion.x = Math.min(p.x - 30, qp.width - completion.width - 8);
        completion.y = p.y;
        completion.show(list, pre);
    }

    // ——— Pasek ———
    Item {
        id: bar
        width: parent.width; height: 48
        Row {
            x: 20; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Pill { text: Vault.running ? "Wykonuję…" : "Uruchom"; icon: "play"; primary: true; enabled: !Vault.running; tip: "Polecenie pod kursorem albo zaznaczenie (Ctrl+Enter)"; onClicked: qp.runCurrent() }
            Pill { text: "Wszystko"; enabled: !Vault.running; tip: "Wszystkie polecenia po kolei (Ctrl+Shift+Enter)"; onClicked: qp.runAll() }
            Rectangle {
                visible: Vault.readOnly
                anchors.verticalCenter: parent.verticalCenter
                width: roText.implicitWidth + 18; height: 26; radius: 13
                color: Theme.fill
                Row {
                    anchors.centerIn: parent; spacing: 5
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.lock; size: 12; stroke: 2; color: Theme.text2 }
                    Text { id: roText; text: "tylko odczyt"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                }
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            ToolBtn { icon: "trash"; tip: "Wyczyść edytor"; onClicked: { editor.text = ""; editor.forceActiveFocus(); } }
            ToolBtn { icon: "clock"; tip: qp.showHistory ? "Ukryj historię" : "Pokaż historię"; baseColor: qp.showHistory ? Theme.fill : "transparent"; onClicked: qp.showHistory = !qp.showHistory }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
    }

    // ——— Edytor ———
    Item {
        id: editArea
        y: bar.height
        width: parent.width - (qp.showHistory ? history.width : 0)
        height: Math.round((parent.height - bar.height) * qp.split)

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.leftMargin: 48
            contentWidth: Math.max(width, editor.implicitWidth + 20)
            contentHeight: editor.implicitHeight + 20
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            function ensureVisible(r) {
                if (contentY >= r.y) contentY = r.y;
                else if (contentY + height <= r.y + r.height + 10) contentY = r.y + r.height + 10 - height;
                if (contentX >= r.x) contentX = Math.max(0, r.x - 20);
                else if (contentX + width <= r.x + r.width + 20) contentX = r.x + r.width + 20 - width;
            }
            TextEdit {
                id: editor
                y: 10
                width: Math.max(flick.width - 16, implicitWidth)
                color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                font.family: "JetBrains Mono"; font.pixelSize: 13
                selectByMouse: true
                persistentSelection: true
                tabStopDistance: 28
                onCursorRectangleChanged: flick.ensureVisible(cursorRectangle)
                text: "SELECT 1;"
                SqlHighlighter { document: editor.textDocument; dark: Theme.dark; tables: Vault.tableNames }

                Keys.onPressed: (e) => {
                    const ctrl = e.modifiers & Qt.ControlModifier;
                    if (completion.visible) {
                        if (e.key === Qt.Key_Down) { completion.move(1); e.accepted = true; return; }
                        if (e.key === Qt.Key_Up) { completion.move(-1); e.accepted = true; return; }
                        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Tab) {
                            if (!ctrl) { completion.accept(); e.accepted = true; return; }
                        }
                        if (e.key === Qt.Key_Escape) { completion.hide(); e.accepted = true; return; }
                    }
                    if (ctrl && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) {
                        completion.hide();
                        if (e.modifiers & Qt.ShiftModifier) qp.runAll(); else qp.runCurrent();
                        e.accepted = true;
                    } else if (ctrl && e.key === Qt.Key_Space) {
                        qp.updateCompletion(true); e.accepted = true;
                    } else if (e.key === Qt.Key_Tab) {
                        editor.insert(editor.cursorPosition, "    "); e.accepted = true;
                    } else if (e.key === Qt.Key_Return && !ctrl) {
                        // Nowy wiersz z wcięciem poprzedniego
                        const before = editor.text.slice(0, editor.cursorPosition);
                        const line = before.slice(before.lastIndexOf("\n") + 1);
                        const indent = line.match(/^\s*/)[0];
                        editor.remove(editor.selectionStart, editor.selectionEnd);
                        editor.insert(editor.cursorPosition, "\n" + indent);
                        e.accepted = true;
                    }
                }
                Keys.onReleased: (e) => {
                    if (e.text.length === 1 && /[\w.$]/.test(e.text) && !(e.modifiers & Qt.ControlModifier)) qp.updateCompletion(false);
                    else if (e.key === Qt.Key_Backspace && completion.visible) qp.updateCompletion(false);
                    else if (e.text === " " || e.text === "," || e.text === "(" || e.text === ";" || e.key === Qt.Key_Left || e.key === Qt.Key_Right) completion.hide();
                }
                onActiveFocusChanged: if (!activeFocus) completion.hide()
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.IBeamCursor
            }
        }
        // Numery wierszy
        Item {
            width: 48; height: parent.height
            clip: true
            Column {
                y: 10 - flick.contentY
                width: parent.width
                Repeater {
                    model: editor.lineCount
                    delegate: Text {
                        required property int index
                        width: 38; height: editor.lineCount > 0 ? editor.contentHeight / editor.lineCount : 18
                        horizontalAlignment: Text.AlignRight
                        text: index + 1
                        color: Theme.text2; opacity: 0.6
                        font.family: "JetBrains Mono"; font.pixelSize: 11
                    }
                }
            }
        }
        // Podział z wynikami
        Rectangle {
            anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line
            MouseArea {
                anchors.fill: parent; anchors.margins: -4
                cursorShape: Qt.SplitVCursor
                onPositionChanged: (m) => {
                    if (!pressed) return;
                    const y = mapToItem(qp, 0, m.y).y - bar.height;
                    qp.split = Math.max(0.15, Math.min(0.8, y / (qp.height - bar.height)));
                }
            }
        }
    }

    // ——— Historia ———
    Rectangle {
        id: history
        visible: qp.showHistory
        x: parent.width - width; y: bar.height
        width: 280; height: parent.height - bar.height
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.02) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.018)
        Rectangle { width: 1; height: parent.height; color: Theme.line }
        Item {
            width: parent.width; height: 36
            Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: "Historia"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                visible: Vault.history.length > 0
                text: "Wyczyść"; color: clearArea.containsMouse ? Theme.accentText : Theme.text2; font.family: Theme.font; font.pixelSize: 12
                MouseArea { id: clearArea; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: Vault.clearHistory() }
            }
        }
        ListView {
            id: histList
            x: 8; y: 36
            width: parent.width - 16; height: parent.height - y - 8
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: Vault.history
            delegate: Rectangle {
                id: hr
                required property var modelData
                width: ListView.view.width; height: hcol.implicitHeight + 14
                radius: 8
                color: hArea.containsMouse ? Theme.hover : "transparent"
                Rectangle {
                    x: 8; y: 12; width: 6; height: 6; radius: 3
                    color: hr.modelData.ok ? (Theme.dark ? "#4ADE80" : "#16A34A") : Theme.danger
                }
                Column {
                    id: hcol
                    x: 22; y: 7; width: parent.width - 30
                    spacing: 3
                    Text {
                        width: parent.width
                        text: String(hr.modelData.sql).replace(/\s+/g, " ")
                        maximumLineCount: 2; wrapMode: Text.WrapAnywhere; elide: Text.ElideRight
                        color: Theme.text; font.family: "JetBrains Mono"; font.pixelSize: 11
                    }
                    Text {
                        text: String(hr.modelData.time || "").replace("T", " ").slice(5, 16) + " · " + Vault.formatMs(hr.modelData.ms || 0)
                              + (hr.modelData.ok && hr.modelData.rows ? " · " + hr.modelData.rows + " w." : "")
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 10
                    }
                }
                MouseArea {
                    id: hArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { editor.text = hr.modelData.sql; editor.forceActiveFocus(); }
                    onDoubleClicked: { editor.text = hr.modelData.sql; qp.runAll(); }
                }
            }
        }
        Text {
            visible: Vault.history.length === 0
            anchors.centerIn: parent
            width: parent.width - 40; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
            text: "Wykonane zapytania pojawią się tutaj"
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
        }
    }

    // ——— Wynik ———
    Item {
        id: resultArea
        y: editArea.y + editArea.height
        width: editArea.width; height: parent.height - y
        readonly property var run: Vault.lastRun
        Item {
            id: status
            width: parent.width; height: 40
            Row {
                x: 20; anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Rectangle {
                    visible: resultArea.run.ok !== undefined
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8; height: 8; radius: 4
                    color: resultArea.run.ok ? (Theme.dark ? "#4ADE80" : "#16A34A") : Theme.danger
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, status.width - 260)
                    elide: Text.ElideRight
                    text: Vault.running ? "Wykonuję…"
                        : resultArea.run.ok === undefined ? "Ctrl+Enter wykonuje polecenie pod kursorem"
                        : resultArea.run.ok ? (resultArea.run.messages || []).slice(-1)[0] + " · " + Vault.formatMs(resultArea.run.ms || 0)
                                              + ((resultArea.run.statements || 1) > 1 ? " · poleceń: " + resultArea.run.statements : "")
                        : resultArea.run.error
                    color: resultArea.run.ok === false ? Theme.danger : resultArea.run.ok ? Theme.text : Theme.text2
                    font.family: Theme.font; font.pixelSize: 12; font.weight: resultArea.run.ok !== undefined ? Font.Medium : Font.Normal
                }
                Text {
                    visible: !!resultArea.run.truncated
                    anchors.verticalCenter: parent.verticalCenter
                    text: "pokazano pierwsze 2000 — eksport zapisze wszystkie"
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                visible: !!resultArea.run.select && resultArea.run.ok
                Pill { small: true; text: "CSV"; icon: "download"; onClicked: qp.exportRequested("csv") }
                Pill { small: true; text: "JSON"; icon: "download"; onClicked: qp.exportRequested("json") }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        }
        DataGrid {
            id: resultGrid
            y: status.height
            width: parent.width; height: parent.height - y
            visible: Vault.result.columns.length > 0
            model: Vault.result
            onCellMenu: (r, c, x, y) => { const p = mapToItem(qp, x, y); qp.cellMenu(r, c, p.x, p.y); }
            onOpenRow: (r) => qp.openRow(r)
        }
        // Błąd z zaznaczeniem
        Text {
            visible: resultArea.run.ok === false
            x: 20; y: status.height + 16
            width: parent.width - 40; wrapMode: Text.Wrap
            text: resultArea.run.sql ? "W poleceniu:\n" + resultArea.run.sql : ""
            color: Theme.text2; font.family: "JetBrains Mono"; font.pixelSize: 12
        }
    }

    CompletionPopup {
        id: completion
        onAccepted: (item) => {
            const before = editor.text.slice(0, editor.cursorPosition);
            const pre = before.match(/[\w$]*$/)[0];
            editor.remove(editor.cursorPosition - pre.length, editor.cursorPosition);
            editor.insert(editor.cursorPosition, item.insert);
        }
    }
}
