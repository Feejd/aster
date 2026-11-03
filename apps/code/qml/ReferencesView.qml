pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Odwołania do symbolu (Shift+F12) z serwera języka, pogrupowane według plików; klik otwiera miejsce.
Item {
    id: rv
    property var groups: []
    property string title
    property var collapsed: ({})
    signal openReference(string path, int line, int col, int length)

    function esc(s) { return String(s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\t/g, "  "); }
    readonly property var rows: {
        const out = [];
        for (let i = 0; i < groups.length; ++i) {
            const f = groups[i];
            const closed = !!collapsed[f.path];
            out.push({ kind: "file", path: f.path, name: f.name, dir: f.dir, count: f.items.length, closed: closed });
            if (closed) continue;
            for (let k = 0; k < f.items.length; ++k)
                out.push(Object.assign({ kind: "item", path: f.path }, f.items[k]));
        }
        return out;
    }

    Text {
        id: head
        x: 16; y: 6
        text: rv.title
        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
    }
    ListView {
        y: head.height + 10
        width: parent.width; height: parent.height - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: rv.rows
        delegate: Item {
            id: row
            required property var modelData
            width: ListView.view.width; height: modelData.kind === "file" ? 28 : 24
            Rectangle {
                anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                radius: 6
                color: rowArea.containsMouse ? Theme.hover : "transparent"
            }
            Item {
                visible: row.modelData.kind === "file"
                anchors.fill: parent
                Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; d: row.modelData.closed ? Icons.chevronRight : Icons.chevronDown; size: 12; stroke: 2; color: Theme.text2 }
                FileIcon { x: 28; anchors.verticalCenter: parent.verticalCenter; name: row.modelData.name || ""; size: 15 }
                Text {
                    id: fname
                    x: 50; anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.name || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                }
                Text {
                    anchors.left: fname.right; anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: (row.modelData.dir || "") + "  ·  " + (row.modelData.count || 0)
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                }
            }
            Row {
                visible: row.modelData.kind === "item"
                x: 50; anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text {
                    width: 36; horizontalAlignment: Text.AlignRight
                    text: (row.modelData.line || 0) + 1
                    color: Theme.text2; font.family: "JetBrains Mono"; font.pixelSize: 12
                }
                Text {
                    width: row.width - 50 - 36 - 30
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: {
                        if (row.modelData.kind !== "item") return "";
                        const t = String(row.modelData.text || ""), a = row.modelData.col, b = Math.max(a, row.modelData.endCol);
                        const lead = t.match(/^\s*/)[0].length;
                        return rv.esc(t.slice(lead, a)) + "<b><font color=\"" + Theme.accentText + "\">" + rv.esc(t.slice(a, b)) + "</font></b>" + rv.esc(t.slice(b));
                    }
                    color: Theme.text; font.family: "JetBrains Mono"; font.pixelSize: 12
                }
            }
            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (row.modelData.kind === "file") {
                        const c = Object.assign({}, rv.collapsed);
                        c[row.modelData.path] = !c[row.modelData.path];
                        rv.collapsed = c;
                    } else {
                        rv.openReference(row.modelData.path, row.modelData.line, row.modelData.col, row.modelData.endCol - row.modelData.col);
                    }
                }
            }
        }
    }
}
