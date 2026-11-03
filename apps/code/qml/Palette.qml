pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Paleta u góry okna (jak w VS Code): bez przedrostka — szybkie otwieranie pliku (Ctrl+P),
// „>” — polecenia (Ctrl+Shift+P), „:” — przejście do wiersza (Ctrl+G).
Item {
    id: pal
    property bool shown: false
    property var commands: []            // [{ label, shortcut, action, icon }]
    property var recentPaths: []         // otwarte karty — pierwsze przy pustym zapytaniu
    property var items: []
    property int current: 0
    signal fileChosen(string path)
    signal commandChosen(string action)
    signal lineChosen(int line)
    signal closed()

    anchors.fill: parent
    visible: shown
    z: 450

    readonly property string mode: field.text.startsWith(">") ? "commands" : field.text.startsWith(":") ? "line" : "files"

    function open(prefix) {
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
            items = list.map(f => Object.assign({ kind: "file" }, f));
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
        close();
        if (it.kind === "file") fileChosen(it.path);
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
                d: pal.mode === "commands" ? Icons.apps : pal.mode === "line" ? Icons.arrow : Icons.search
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
                    text: "Szukaj pliku po nazwie (> polecenia, : wiersz)"
                    color: Theme.text2; font: field.font
                }
            }
        }

        Text {
            id: empty
            x: 22; y: 58
            visible: pal.mode === "line" || (list.count === 0 && field.text.length > (pal.mode === "commands" ? 1 : 0))
            text: pal.mode === "line" ? (parseInt(field.text.slice(1)) > 0 ? "Enter — przejdź do wiersza " + parseInt(field.text.slice(1)) : "Wpisz numer wiersza")
                                      : pal.mode === "commands" ? "Brak takiego polecenia" : "Brak pasujących plików"
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
                Icon {
                    visible: row.modelData.kind === "command"
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    d: Icons[row.modelData.icon] || ""; size: 16; color: Theme.text2
                }
                Row {
                    x: 36; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 36 - shortcutText.width - 16
                    spacing: 8
                    clip: true
                    Text {
                        id: nameText
                        text: row.modelData.kind === "file"
                              ? (row.modelData.html ? row.modelData.html.replace(/<b>/g, "<font color=\"" + Theme.accentText + "\"><b>").replace(/<\/b>/g, "</b></font>") : row.modelData.name)
                              : row.modelData.label
                        textFormat: row.modelData.html ? Text.StyledText : Text.PlainText
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.modelData.kind === "file"
                        width: Math.max(0, parent.width - nameText.width - 8); elide: Text.ElideLeft
                        text: row.modelData.dir || ""
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                    }
                }
                Text {
                    id: shortcutText
                    anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.kind === "command" ? row.modelData.shortcut : (row.modelData.opened ? "otwarty" : "")
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
