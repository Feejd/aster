pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Aster.Shell
import Aster.Ui

// Menu programu na górnym pasku. Otwarte menu przykrywa ekran przezroczystą warstwą, więc klik obok je zamyka,
// a przejechanie po pasku przełącza menu jak w programach. Lepsze niż zwykłe menu w dwóch rzeczach:
// wystarczy zacząć pisać, a Super+/ od razu szuka we wszystkich poleceniach programu.
Window {
    id: mw
    property bool followsPrimary: true   // po zmianie głównego ekranu main.cpp przenosi okno
    color: "transparent"
    visible: false
    width: Screen.width
    height: Screen.height
    title: "Menu programu"

    // Pozycje na pasku podaje HorizonWindow: [{ title, x, width, items }]
    property var entries: []
    property int current: -1
    property int row: -1
    property string query: ""
    property bool searching: false
    signal windowAction(string action)

    Component.onCompleted: Platform.makeLayer(mw, "overlay", 1 | 2 | 4 | 8, -1, "exclusive", "aster-menu")

    function openAt(index) {
        GlobalMenu.refresh();
        current = index; row = -1; searching = false; query = "";
        visible = true;
        keys.forceActiveFocus();
    }
    function openSearch() {
        GlobalMenu.refresh();
        current = -1; row = 0; searching = true; query = "";
        visible = true;
        keys.forceActiveFocus();
    }
    function close() { visible = false; current = -1; searching = false; query = ""; }
    function run(item) {
        if (!item || item.separator || item.enabled === false) return;
        pending = item;
        close();
        runTimer.restart();
    }
    // Polecenie idzie po zamknięciu menu, gdy okno programu odzyska fokus
    property var pending: null
    Timer {
        id: runTimer
        interval: 140
        onTriggered: {
            const item = mw.pending;
            mw.pending = null;
            if (!item) return;
            if (item.action) mw.windowAction(item.action);
            else GlobalMenu.trigger(item.id);
        }
    }
    readonly property var currentItems: current >= 0 && current < entries.length ? entries[current].items : []
    // Wyszukiwanie: wszystkie polecenia programu, od najlepszego dopasowania
    readonly property var results: {
        const q = query.trim().toLowerCase();
        if (!searching) return [];
        const out = [];
        entries.forEach(e => (e.items || []).forEach(i => {
            if (i.separator || i.enabled === false) return;
            const t = i.text.toLowerCase();
            const hit = q === "" ? 2 : t.indexOf(q) === 0 ? 0 : t.indexOf(q) > 0 ? 1 : (e.title + " " + t).toLowerCase().indexOf(q) >= 0 ? 2 : -1;
            if (hit >= 0) out.push({ hit: hit, order: out.length, path: e.title, item: i });
        }));
        out.sort((a, b) => a.hit - b.hit || a.order - b.order);
        return out.slice(0, 9);
    }
    function step(dir) {
        const list = searching ? results : currentItems;
        if (!list.length) return;
        let r = row;
        for (let n = 0; n < list.length; ++n) {
            r = (r + dir + list.length) % list.length;
            const it = searching ? list[r].item : list[r];
            if (!it.separator && it.enabled !== false) { row = r; return; }
        }
    }

    Item {
        id: keys
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) mw.close();
            else if (e.key === Qt.Key_Down) mw.step(1);
            else if (e.key === Qt.Key_Up) mw.step(-1);
            else if (!mw.searching && e.key === Qt.Key_Left) { mw.current = (mw.current + mw.entries.length - 1) % mw.entries.length; mw.row = -1; }
            else if (!mw.searching && e.key === Qt.Key_Right) { mw.current = (mw.current + 1) % mw.entries.length; mw.row = -1; }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                if (mw.searching) { const r = mw.results[Math.max(0, mw.row)]; if (r) mw.run(r.item); }
                else if (mw.row >= 0) mw.run(mw.currentItems[mw.row]);
            } else if (e.key === Qt.Key_Backspace) {
                mw.query = mw.query.slice(0, -1);
                if (mw.query === "" && mw.current >= 0) mw.searching = false;
                mw.row = 0;
            } else if (e.text !== "" && e.text.charCodeAt(0) >= 32) {
                // Pisanie w otwartym menu od razu szuka polecenia
                mw.searching = true; mw.query += e.text; mw.row = 0;
            } else return;
            e.accepted = true;
        }
    }

    MouseArea { anchors.fill: parent; onClicked: mw.close() }

    // Pasek: te same pozycje co w HorizonWindow, przełączane samym najechaniem
    Repeater {
        model: mw.entries
        delegate: Rectangle {
            id: head
            required property var modelData
            required property int index
            x: modelData.x; y: 4
            width: modelData.width; height: 24; radius: 6
            visible: !mw.searching
            color: mw.current === index ? Theme.accent : "transparent"
            Text {
                anchors.centerIn: parent
                text: head.modelData.title
                color: mw.current === head.index ? "white" : Theme.text
                font.family: Theme.font; font.pixelSize: 13
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: if (mw.current !== head.index) { mw.current = head.index; mw.row = -1; GlobalMenu.refresh(); }
                onClicked: mw.close()
            }
        }
    }

    component Row_: Rectangle {
        id: rowItem
        property var item
        property string path: ""
        property bool chosen: false
        readonly property bool on: !!item && item.enabled !== false
        width: parent ? parent.width : 0
        height: !item ? 0 : item.separator ? 9 : 30
        radius: 6
        color: chosen && !item.separator ? Theme.accent : "transparent"
        Rectangle { visible: !!rowItem.item && !!rowItem.item.separator; anchors.centerIn: parent; width: parent.width - 16; height: 1; color: Theme.line }
        Icon {
            x: 9; anchors.verticalCenter: parent.verticalCenter
            visible: !!rowItem.item && rowItem.item.checked === true
            d: Icons.check; size: 13; stroke: 2.2
            color: rowItem.chosen ? "white" : Theme.accentText
        }
        Text {
            x: 28
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - keyText.implicitWidth - 20
            visible: !!rowItem.item && !rowItem.item.separator
            elide: Text.ElideRight
            text: rowItem.item ? (rowItem.path ? rowItem.path + "  ›  " : "") + (rowItem.item.text || "") : ""
            color: rowItem.chosen ? "white" : rowItem.on ? Theme.text : Theme.text2
            font.family: Theme.font; font.pixelSize: 13
        }
        Text {
            id: keyText
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: rowItem.item && rowItem.item.key ? rowItem.item.key : ""
            color: rowItem.chosen ? "white" : Theme.text2
            font.family: Theme.font; font.pixelSize: 12
        }
        signal hovered()
        signal chosenClick()
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            enabled: !!rowItem.item && !rowItem.item.separator
            onEntered: rowItem.hovered()
            onClicked: rowItem.chosenClick()
        }
    }

    // Rozwinięte menu
    Island {
        visible: !mw.searching && mw.current >= 0
        x: mw.current >= 0 && mw.current < mw.entries.length ? Math.min(mw.entries[mw.current].x, mw.width - width - 8) : 0
        y: 32
        width: 290
        height: list.height + 12
        radius: 10
        MouseArea { anchors.fill: parent }
        Column {
            id: list
            x: 6; y: 6
            width: parent.width - 12
            Repeater {
                model: mw.currentItems
                delegate: Row_ {
                    required property var modelData
                    required property int index
                    item: modelData
                    chosen: mw.row === index
                    onHovered: if (on) mw.row = index
                    onChosenClick: mw.run(modelData)
                }
            }
        }
    }

    // Wyszukiwanie poleceń
    Island {
        visible: mw.searching
        x: Math.round((mw.width - width) / 2)
        y: 40
        width: 540
        height: found.height + 62
        radius: 12
        MouseArea { anchors.fill: parent }
        Icon { x: 18; y: 15; d: Icons.search; size: 18; stroke: 2; color: Theme.text2 }
        Text {
            x: 48; y: 12; width: parent.width - 64
            text: mw.query !== "" ? mw.query : "Szukaj polecenia w programie"
            elide: Text.ElideLeft
            color: mw.query !== "" ? Theme.text : Theme.text2
            font.family: Theme.font; font.pixelSize: 16
        }
        Rectangle { y: 46; width: parent.width; height: 1; color: Theme.line }
        Column {
            id: found
            x: 8; y: 54
            width: parent.width - 16
            Repeater {
                model: mw.results
                delegate: Row_ {
                    required property var modelData
                    required property int index
                    item: modelData.item
                    path: modelData.path
                    chosen: mw.row === index
                    onHovered: mw.row = index
                    onChosenClick: mw.run(modelData.item)
                }
            }
            Text {
                visible: mw.results.length === 0
                leftPadding: 10; bottomPadding: 6
                text: "Ten program nie ma takiego polecenia"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
            }
        }
    }
}
