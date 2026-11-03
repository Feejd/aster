pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui

// Podpowiedzi serwera języka pod kursorem (jak IntelliSense): lista filtrowana po wpisanym początku
// słowa, rodzaj jako mała plakietka, szczegóły po prawej. Strzałki, Enter/Tab — wybór, Esc — zamknij.
Rectangle {
    id: pop
    property var all: []                 // wszystkie pozycje z serwera
    property var items: []               // po filtrze
    property int current: 0
    property string prefix: ""
    property string fontFamily: "JetBrains Mono"
    signal accepted(var item)

    visible: false
    width: 460
    height: Math.min(list.contentHeight, 9 * 26) + 8
    radius: 10
    color: Theme.surface
    border.width: 1; border.color: Theme.edge
    z: 50

    function show(list, pre) {
        all = list;
        filter(pre);
    }
    function hide() { visible = false; all = []; items = []; }
    function filter(pre) {
        prefix = pre;
        const p = pre.toLowerCase();
        const starts = [], contains = [];
        for (let i = 0; i < all.length; ++i) {
            const f = String(all[i].filter || all[i].label).toLowerCase();
            if (!p || f.startsWith(p)) starts.push(all[i]);
            else if (p.length > 1 && f.indexOf(p) >= 0) contains.push(all[i]);
            if (starts.length > 80) break;
        }
        items = starts.concat(contains).slice(0, 80);
        current = 0;
        visible = items.length > 0 && !(items.length === 1 && items[0].insert === pre);
        list.positionViewAtBeginning();
    }
    function move(d) {
        if (!items.length) return;
        current = Math.max(0, Math.min(items.length - 1, current + d));
        list.positionViewAtIndex(current, ListView.Contain);
    }
    function accept() { if (visible && items[current]) { const it = items[current]; hide(); accepted(it); } }

    // Rodzaje z LSP (CompletionItemKind) → litera i kolor
    function kindInfo(k) {
        if (k === 2 || k === 3 || k === 4) return ["f", "#A855F7"];
        if (k === 5 || k === 10) return ["p", "#3B82F6"];
        if (k === 6) return ["v", "#06B6D4"];
        if (k === 7 || k === 22 || k === 8 || k === 25) return ["T", "#F59E0B"];
        if (k === 9) return ["m", "#64748B"];
        if (k === 13 || k === 20) return ["E", "#EAB308"];
        if (k === 21) return ["c", "#0EA5E9"];
        if (k === 14) return ["k", "#94A3B8"];
        if (k === 15) return ["s", "#10B981"];
        if (k === 17 || k === 19) return ["F", "#64748B"];
        return ["·", "#94A3B8"];
    }

    ListView {
        id: list
        x: 4; y: 4
        width: parent.width - 8; height: parent.height - 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: pop.items
        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property var kind: pop.kindInfo(modelData.kind)
            width: ListView.view.width; height: 26; radius: 6
            color: index === pop.current ? Theme.accentSoft : rowArea.containsMouse ? Theme.hover : "transparent"
            Rectangle {
                x: 6; anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18; radius: 5
                color: Qt.rgba(Qt.color(row.kind[1]).r, Qt.color(row.kind[1]).g, Qt.color(row.kind[1]).b, Theme.dark ? 0.28 : 0.16)
                Text { anchors.centerIn: parent; text: row.kind[0]; color: row.kind[1]; font.family: pop.fontFamily; font.pixelSize: 11; font.weight: Font.Bold }
            }
            Text {
                id: lbl
                x: 32; anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - 40)
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: {
                    const l = String(row.modelData.label), n = pop.prefix.length;
                    const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
                    return n && l.toLowerCase().startsWith(pop.prefix.toLowerCase())
                        ? "<b><font color=\"" + Theme.accentText + "\">" + esc(l.slice(0, n)) + "</font></b>" + esc(l.slice(n)) : esc(l);
                }
                color: Theme.text; font.family: pop.fontFamily; font.pixelSize: 13
            }
            Text {
                anchors.left: lbl.right; anchors.leftMargin: 10
                anchors.right: parent.right; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                visible: row.index === pop.current || rowArea.containsMouse
                text: row.modelData.detail || ""
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: { pop.current = row.index; pop.accept(); }
            }
        }
    }
}
