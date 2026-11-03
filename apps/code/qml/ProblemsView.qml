pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Problemy (Ctrl+Shift+M): błędy i ostrzeżenia z serwerów języków, pogrupowane według plików.
Item {
    id: pv
    signal openProblem(string path, int line, int col)
    property var collapsed: ({})

    function severityColor(s) { return s === 1 ? Theme.danger : s === 2 ? (Theme.dark ? "#E3B341" : "#9A6700") : Theme.accentText; }

    readonly property var rows: {
        const out = [];
        const res = Lsp.problems.concat(Tasks.problems);
        for (let i = 0; i < res.length; ++i) {
            const f = res[i];
            const closed = !!collapsed[f.path];
            out.push({ kind: "file", path: f.path, name: f.name, dir: f.dir, count: f.items.length, closed: closed });
            if (closed) continue;
            for (let k = 0; k < f.items.length; ++k)
                out.push(Object.assign({ kind: "item", path: f.path }, f.items[k]));
        }
        return out;
    }

    ListView {
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: pv.rows
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
            Item {
                visible: row.modelData.kind === "item"
                anchors.fill: parent
                Icon {
                    x: 50; anchors.verticalCenter: parent.verticalCenter
                    d: row.modelData.severity === 1 ? Icons.alertCircle : row.modelData.severity === 2 ? Icons.warning : Icons.info
                    size: 14; color: pv.severityColor(row.modelData.severity)
                }
                Text {
                    id: msg
                    x: 72; anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width - 72 - pos.implicitWidth - 30)
                    elide: Text.ElideRight
                    text: String(row.modelData.message || "").split("\n")[0]
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                }
                Text {
                    id: pos
                    anchors.left: msg.right; anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: (row.modelData.source ? row.modelData.source + "  " : "") + "[" + ((row.modelData.line || 0) + 1) + ", " + ((row.modelData.col || 0) + 1) + "]"
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
            }
            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (row.modelData.kind === "file") {
                        const c = Object.assign({}, pv.collapsed);
                        c[row.modelData.path] = !c[row.modelData.path];
                        pv.collapsed = c;
                    } else {
                        pv.openProblem(row.modelData.path, row.modelData.line, row.modelData.col);
                    }
                }
            }
        }
    }

    Column {
        visible: pv.rows.length === 0
        anchors.centerIn: parent
        spacing: 6
        Icon { anchors.horizontalCenter: parent.horizontalCenter; d: Icons.check; size: 26; stroke: 1.6; color: Theme.text2; opacity: 0.6 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Brak problemów w otwartych plikach"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
    }
}
