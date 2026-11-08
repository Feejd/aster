pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Pulse

// Pasek boczny: obszar roboczy (projekt), kolekcje z zapytaniami albo historia, szukanie.
Item {
    id: sb
    property string page: "collections"           // collections | history
    property string selectedId
    property var dirty: ({})                       // id → true (niezapisane zmiany)
    property var collapsed: ({})                   // plik kolekcji → true
    signal openRequest(string file, var request)
    signal openHistory(var entry)
    signal newRequest(string file)
    signal newCollection()
    signal collectionMenu(string file, real x, real y)
    signal requestMenu(string file, var request, real x, real y)
    signal workspaceMenu(Item anchor)

    function methodColor(m) {
        return ({ GET: "#16A34A", POST: "#D97706", PUT: "#2563EB", PATCH: "#9333EA", DELETE: "#DC2626", HEAD: "#0891B2", OPTIONS: "#64748B" })[m] || "#64748B";
    }
    function focusSearch() { filter.focusEnd(); }

    // Płaska lista: nagłówki kolekcji i ich zapytania (z filtrem)
    readonly property var rows: {
        const q = filter.text.trim().toLowerCase();
        const out = [];
        for (const c of Pulse.collections) {
            const reqs = c.requests.filter(r => q === "" || r.name.toLowerCase().indexOf(q) >= 0 || (r.url || "").toLowerCase().indexOf(q) >= 0 || r.method.toLowerCase() === q);
            if (q !== "" && reqs.length === 0 && c.name.toLowerCase().indexOf(q) < 0) continue;
            out.push({ type: "collection", file: c.file, name: c.name, count: c.requests.length });
            if (sb.collapsed[c.file] && q === "") continue;
            for (const r of reqs) out.push({ type: "request", file: c.file, request: r });
        }
        return out;
    }
    // Historia pogrupowana po dniach
    readonly property var historyRows: {
        const q = filter.text.trim().toLowerCase();
        const out = [];
        const today = new Date(); today.setHours(0, 0, 0, 0);
        let lastDay = "";
        for (const h of Pulse.history) {
            if (q !== "" && (h.url || "").toLowerCase().indexOf(q) < 0 && (h.request.name || "").toLowerCase().indexOf(q) < 0) continue;
            const d = new Date(h.time);
            const day = new Date(d); day.setHours(0, 0, 0, 0);
            const diff = Math.round((today - day) / 86400000);
            const label = diff === 0 ? "Dzisiaj" : diff === 1 ? "Wczoraj" : d.toLocaleDateString(Qt.locale("pl_PL"), "d MMMM");
            if (label !== lastDay) { out.push({ type: "day", label: label }); lastDay = label; }
            out.push({ type: "entry", entry: h, clock: d.toLocaleTimeString(Qt.locale("pl_PL"), "HH:mm") });
        }
        return out;
    }

    // ——— Obszar roboczy ———
    HoverButton {
        id: wsButton
        x: 10; y: 14
        width: parent.width - 20; height: 44; radius: 11
        tip: Pulse.workspaceDir
        onClicked: sb.workspaceMenu(wsButton)
        Rectangle {
            id: logo
            x: 8; anchors.verticalCenter: parent.verticalCenter
            width: 28; height: 28; radius: 8
            gradient: Gradient {
                GradientStop { position: 0; color: "#FFB38A" }
                GradientStop { position: 1; color: "#E0336E" }
            }
            Icon { anchors.centerIn: parent; d: Icons.pulse; size: 16; stroke: 2.2; color: "white" }
        }
        Column {
            x: logo.x + logo.width + 10
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 28
            Text { width: parent.width; text: Pulse.workspaceName; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text { width: parent.width; text: Pulse.prettyPath(Pulse.workspaceDir); elide: Text.ElideMiddle; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
        }
        Icon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.chevronDown; size: 13; stroke: 2; color: Theme.text2 }
    }

    // Kolekcje | Historia
    Rectangle {
        id: seg
        x: 12; y: wsButton.y + wsButton.height + 12
        width: parent.width - 24; height: 30; radius: 9
        color: Theme.fill
        Rectangle {
            x: sb.page === "collections" ? 2 : parent.width / 2
            y: 2; width: parent.width / 2 - 2; height: parent.height - 4; radius: 7
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : "white"
            Behavior on x { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
        }
        Repeater {
            model: [["collections", "Kolekcje"], ["history", "Historia"]]
            delegate: Text {
                required property var modelData
                required property int index
                x: index * seg.width / 2; width: seg.width / 2; height: seg.height
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: modelData[1]
                color: sb.page === modelData[0] ? Theme.text : Theme.text2
                font.family: Theme.font; font.pixelSize: 12; font.weight: sb.page === modelData[0] ? Font.DemiBold : Font.Normal
                MouseArea { anchors.fill: parent; onClicked: sb.page = parent.modelData[0] }
            }
        }
    }

    Field {
        id: filter
        x: 12; y: seg.y + seg.height + 8
        width: parent.width - 24; height: 30
        vars: false
        leftPad: 30
        placeholder: sb.page === "collections" ? "Szukaj zapytania" : "Szukaj w historii"
        Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 14; color: Theme.text2 }
        Keys.onEscapePressed: setText("")
    }

    // ——— Kolekcje ———
    ListView {
        id: list
        visible: sb.page === "collections"
        x: 8; y: filter.y + filter.height + 8
        width: parent.width - 16; height: bottomBar.y - y - 4
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: sb.rows
        delegate: Loader {
            id: rowLoader
            required property var modelData
            width: list.width
            sourceComponent: modelData.type === "collection" ? collectionRow : requestRow
        }
    }
    Component {
        id: collectionRow
        Rectangle {
            id: cr
            readonly property var d: parent ? parent.modelData : ({})
            width: list.width; height: 32; radius: 8
            color: crArea.containsMouse ? Theme.hover : "transparent"
            Icon {
                x: 6; anchors.verticalCenter: parent.verticalCenter
                d: Icons.chevronRight; size: 12; stroke: 2.2; color: Theme.text2
                rotation: sb.collapsed[cr.d.file] ? 0 : 90
                Behavior on rotation { NumberAnimation { duration: 120 } }
            }
            Icon { x: 22; anchors.verticalCenter: parent.verticalCenter; d: Icons.folder; size: 15; color: Theme.text2 }
            Text {
                x: 44; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - (crArea.containsMouse ? 66 : 30)
                text: cr.d.name || ""
                elide: Text.ElideRight
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
            }
            Text {
                visible: !crArea.containsMouse
                anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                text: cr.d.count || ""
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
            }
            MouseArea {
                id: crArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (m) => {
                    if (m.button === Qt.RightButton) { const p = mapToItem(sb, m.x, m.y); sb.collectionMenu(cr.d.file, p.x, p.y); return; }
                    const c = Object.assign({}, sb.collapsed);
                    c[cr.d.file] = !c[cr.d.file];
                    sb.collapsed = c;
                }
            }
            Row {
                visible: crArea.containsMouse
                anchors.right: parent.right; anchors.rightMargin: 2; anchors.verticalCenter: parent.verticalCenter
                ToolBtn { width: 28; height: 28; icon: "plus"; tip: "Nowe zapytanie w tej kolekcji"; onClicked: sb.newRequest(cr.d.file) }
                ToolBtn {
                    width: 28; height: 28; icon: "more"; tip: "Kolekcja"
                    onClicked: { const p = mapToItem(sb, 0, height); sb.collectionMenu(cr.d.file, p.x, p.y); }
                }
            }
        }
    }
    Component {
        id: requestRow
        Rectangle {
            id: rr
            readonly property var d: parent ? parent.modelData : ({})
            readonly property var r: d.request || ({})
            readonly property bool active: r.id === sb.selectedId
            width: list.width; height: 30; radius: 8
            color: active ? Theme.accentSoft : rrArea.containsMouse ? Theme.hover : "transparent"
            Text {
                id: method
                x: 22; anchors.verticalCenter: parent.verticalCenter
                width: 46
                text: (rr.r.method || "") === "DELETE" ? "DEL" : (rr.r.method || "") === "OPTIONS" ? "OPT" : rr.r.method || ""
                color: Theme.dark ? Qt.lighter(sb.methodColor(rr.r.method), 1.35) : sb.methodColor(rr.r.method)
                font.family: "JetBrains Mono"; font.pixelSize: 10; font.weight: Font.Bold
            }
            Text {
                x: method.x + method.width
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - 22
                text: rr.r.name || ""
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 13; font.weight: rr.active ? Font.Medium : Font.Normal
            }
            Rectangle {
                visible: !!sb.dirty[rr.r.id]
                anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                width: 7; height: 7; radius: 3.5
                color: Theme.accent
            }
            MouseArea {
                id: rrArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (m) => {
                    if (m.button === Qt.RightButton) { const p = mapToItem(sb, m.x, m.y); sb.requestMenu(rr.d.file, rr.r, p.x, p.y); return; }
                    sb.openRequest(rr.d.file, rr.r);
                }
            }
        }
    }
    Column {
        visible: sb.page === "collections" && Pulse.collections.length === 0
        x: 20; y: list.y + 20; width: parent.width - 40
        spacing: 10
        Text { width: parent.width; wrapMode: Text.Wrap; text: "Nie ma jeszcze kolekcji. Kolekcja to plik JSON w folderze projektu — zapisane w niej zapytania można dodać do repozytorium."; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2 }
        Pill { small: true; text: "Nowa kolekcja"; icon: "folderPlus"; onClicked: sb.newCollection() }
    }

    // ——— Historia ———
    ListView {
        id: hist
        visible: sb.page === "history"
        x: 8; y: list.y
        width: parent.width - 16; height: list.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: sb.historyRows
        delegate: Loader {
            required property var modelData
            width: hist.width
            sourceComponent: modelData.type === "day" ? dayRow : entryRow
        }
    }
    Component {
        id: dayRow
        Text {
            readonly property var d: parent ? parent.modelData : ({})
            width: hist.width; height: 28
            leftPadding: 10; verticalAlignment: Text.AlignBottom; bottomPadding: 4
            text: d.label || ""
            color: Theme.text2
            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
        }
    }
    Component {
        id: entryRow
        Rectangle {
            id: er
            readonly property var d: parent ? parent.modelData : ({})
            readonly property var e: d.entry || ({})
            readonly property string path: (e.url || "").replace(/^https?:\/\/[^/]+/, "") || "/"
            width: hist.width; height: 44; radius: 8
            color: erArea.containsMouse ? Theme.hover : "transparent"
            Text {
                id: hm
                x: 10; y: 6
                text: (er.e.request || {}).method || ""
                color: Theme.dark ? Qt.lighter(sb.methodColor(text), 1.35) : sb.methodColor(text)
                font.family: "JetBrains Mono"; font.pixelSize: 10; font.weight: Font.Bold
            }
            Text {
                x: hm.x + hm.implicitWidth + 8; y: 4
                width: parent.width - x - 44
                text: er.path
                elide: Text.ElideMiddle
                color: Theme.text; font.family: Theme.font; font.pixelSize: 12
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 10; y: 5
                text: er.e.status ? er.e.status : "✕"
                color: !er.e.status || er.e.status >= 400 ? Theme.danger : Theme.dark ? "#7EE8A8" : "#16A34A"
                font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
            }
            Row {
                x: 10; y: 24
                spacing: 6
                Text {
                    text: er.d.clock + (er.e.environment ? " · " + er.e.environment : "") + (er.e.timeMs !== undefined && er.e.status ? " · " + er.e.timeMs + " ms" : "")
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                }
                Rectangle {
                    visible: er.e.source === "cli" || er.e.source === "dbus"
                    anchors.verticalCenter: parent.verticalCenter
                    width: srcText.implicitWidth + 10; height: 15; radius: 4
                    color: Theme.fill
                    Text { id: srcText; anchors.centerIn: parent; text: er.e.source === "dbus" ? "agent" : "terminal"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 10 }
                }
            }
            MouseArea { id: erArea; anchors.fill: parent; hoverEnabled: true; onClicked: sb.openHistory(er.e) }
        }
    }
    Text {
        visible: sb.page === "history" && Pulse.history.length === 0
        x: 20; y: list.y + 20; width: parent.width - 40
        wrapMode: Text.Wrap
        text: "Wysłane zapytania pojawią się tutaj — także te z terminala (aster-pulse run) i od asystenta."
        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
    }

    // ——— Na dole ———
    Item {
        id: bottomBar
        x: 10; y: parent.height - height - 10
        width: parent.width - 20; height: 34
        Row {
            spacing: 4
            visible: sb.page === "collections"
            HoverButton {
                width: nc.implicitWidth + 20; height: 32; radius: 9
                onClicked: sb.newCollection()
                Row {
                    id: nc
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.folderPlus; size: 15; color: Theme.text2 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Nowa kolekcja"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                }
            }
        }
        HoverButton {
            visible: sb.page === "history" && Pulse.history.length > 0
            width: ch.implicitWidth + 20; height: 32; radius: 9
            onClicked: Pulse.clearHistory()
            Row {
                id: ch
                anchors.centerIn: parent
                spacing: 6
                Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.trash; size: 15; color: Theme.text2 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Wyczyść historię"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
            }
        }
    }
}
