pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui

// Podpowiedzi w edytorze SQL: tabele, kolumny (z tabel w zapytaniu i po „skrót.”), słowa kluczowe.
// Strzałki — wybór, Enter/Tab — wstaw, Esc — zamknij.
Rectangle {
    id: pop
    property var items: []
    property int current: 0
    property string prefix: ""
    signal accepted(var item)

    visible: false
    width: 340
    height: Math.min(listView.contentHeight, 8 * 26) + 8
    radius: 10
    color: Theme.surface
    border.width: 1; border.color: Theme.edge
    z: 50

    function show(list, pre) {
        items = list;
        prefix = pre;
        current = 0;
        visible = items.length > 0 && !(items.length === 1 && items[0].insert.toLowerCase() === pre.toLowerCase());
        listView.positionViewAtBeginning();
    }
    function hide() { visible = false; items = []; }
    function move(d) {
        if (!items.length) return;
        current = Math.max(0, Math.min(items.length - 1, current + d));
        listView.positionViewAtIndex(current, ListView.Contain);
    }
    function accept() { if (visible && items[current]) { const it = items[current]; hide(); accepted(it); } }
    function kindInfo(k) {
        if (k === "table") return ["T", "#F59E0B"];
        if (k === "column") return ["c", "#3B82F6"];
        return ["k", "#A855F7"];
    }

    ListView {
        id: listView
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
                Text { anchors.centerIn: parent; text: row.kind[0]; color: row.kind[1]; font.family: "JetBrains Mono"; font.pixelSize: 11; font.weight: Font.Bold }
            }
            Text {
                id: lbl
                x: 32; anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - 40)
                elide: Text.ElideRight
                text: row.modelData.label
                color: Theme.text; font.family: "JetBrains Mono"; font.pixelSize: 12
            }
            Text {
                anchors.left: lbl.right; anchors.leftMargin: 10
                anchors.right: parent.right; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                text: row.modelData.detail || ""
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
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
