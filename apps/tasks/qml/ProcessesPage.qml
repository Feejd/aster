pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Tasks

// Procesy jak w Menedżerze zadań Windows: działy, programy z rozwijaną listą procesów,
// kolumny z sumami u góry (klik — sortowanie) i komórki podbarwione według obciążenia.
Item {
    id: page
    property string selected: ""
    signal menuRequested(string key, real x, real y)
    signal detailsRequested(string key)
    signal endRequested(string key, bool force)

    readonly property ProcessModel model: Monitor.processes
    readonly property real cpuW: 96
    readonly property real memW: 112
    readonly property real diskW: 104
    readonly property real rightPad: 18

    function select(key) { selected = key; list.forceActiveFocus(); }
    function focusList() { list.forceActiveFocus(); }
    function move(d) {
        let i = model.indexOf(selected);
        for (let step = 0; step < 400; ++step) {
            i += d;
            const k = model.keyAt(i);
            if (k === "") return;
            if (!k.startsWith("h:")) { selected = k; list.positionViewAtIndex(i, ListView.Contain); return; }
        }
    }
    // Zaznaczony proces zniknął — zaznaczenie przechodzi na nic
    Connections {
        target: page.model
        function onUpdated() { if (page.selected && page.model.indexOf(page.selected) < 0) page.selected = ""; }
    }

    // ——— Nagłówki kolumn z sumami ———
    Item {
        id: head
        width: parent.width; height: 54
        HeadCell {
            x: 0; width: parent.width - page.cpuW - page.memW - page.diskW - page.rightPad
            key: "name"; label: "Nazwa"; alignLeft: true
        }
        HeadCell {
            x: parent.width - page.rightPad - page.diskW - page.memW - page.cpuW; width: page.cpuW
            key: "cpu"; label: "Procesor"; total: Monitor.percent(Monitor.cpu)
        }
        HeadCell {
            x: parent.width - page.rightPad - page.diskW - page.memW; width: page.memW
            key: "mem"; label: "Pamięć"; total: Monitor.percent(Monitor.memPercent)
        }
        HeadCell {
            x: parent.width - page.rightPad - page.diskW; width: page.diskW
            key: "disk"; label: "Dysk"; total: Monitor.percent(Monitor.diskPercent)
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
    }

    ListView {
        id: list
        y: head.height
        width: parent.width; height: parent.height - y
        clip: true
        model: page.model
        boundsBehavior: Flickable.StopAtBounds
        focus: true
        keyNavigationEnabled: false
        Keys.onUpPressed: page.move(-1)
        Keys.onDownPressed: page.move(1)
        Keys.onDeletePressed: if (page.selected) page.endRequested(page.selected, false)
        Keys.onReturnPressed: if (page.selected) page.detailsRequested(page.selected)
        Keys.onEnterPressed: if (page.selected) page.detailsRequested(page.selected)
        Keys.onRightPressed: if (page.selected.startsWith("g:")) { if (!page.model.info(page.selected).expanded) page.model.toggle(page.selected); }
        Keys.onLeftPressed: if (page.selected.startsWith("g:")) { if (page.model.info(page.selected).expanded) page.model.toggle(page.selected); }
        delegate: ProcRow {}

        // Cienki suwak
        Rectangle {
            visible: list.contentHeight > list.height
            anchors.right: parent.right; anchors.rightMargin: 3
            y: list.visibleArea.yPosition * list.height
            width: 5; radius: 2.5
            height: Math.max(30, list.visibleArea.heightRatio * list.height)
            color: Theme.text2
            opacity: list.moving || barArea.containsMouse ? 0.5 : 0.18
            Behavior on opacity { NumberAnimation { duration: 200 } }
            MouseArea { id: barArea; anchors.fill: parent; hoverEnabled: true }
        }
    }

    Text {
        visible: list.count === 0 && page.model.filter !== ""
        anchors.centerIn: list
        text: "Brak procesów pasujących do „" + page.model.filter + "”"
        color: Theme.text2; font.family: Theme.font; font.pixelSize: 14
    }

    component HeadCell: Item {
        id: hc
        property string key
        property string label
        property string total
        property bool alignLeft: false
        readonly property bool sorted: page.model.sortKey === key
        height: head.height
        Rectangle { anchors.fill: parent; anchors.margins: 3; radius: 8; color: hcArea.containsMouse ? Theme.hover : "transparent" }
        Column {
            anchors.right: hc.alignLeft ? undefined : parent.right; anchors.rightMargin: 12
            anchors.left: hc.alignLeft ? parent.left : undefined; anchors.leftMargin: 22
            anchors.bottom: parent.bottom; anchors.bottomMargin: 8
            spacing: 0
            Text {
                visible: !hc.alignLeft
                anchors.right: parent.right
                text: hc.total
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
            Row {
                anchors.right: hc.alignLeft ? undefined : parent.right
                spacing: 4
                Icon {
                    visible: hc.sorted && !hc.alignLeft
                    anchors.verticalCenter: parent.verticalCenter
                    d: page.model.sortDescending ? Icons.chevronDown : Icons.up
                    size: 11; stroke: 2.2; color: Theme.accentText
                }
                Text {
                    text: hc.label
                    color: hc.sorted ? Theme.accentText : Theme.text2
                    font.family: Theme.font; font.pixelSize: 12; font.weight: hc.sorted ? Font.DemiBold : Font.Medium
                }
                Icon {
                    visible: hc.sorted && hc.alignLeft
                    anchors.verticalCenter: parent.verticalCenter
                    d: page.model.sortDescending ? Icons.chevronDown : Icons.up
                    size: 11; stroke: 2.2; color: Theme.accentText
                }
            }
        }
        MouseArea {
            id: hcArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (hc.sorted) page.model.sortDescending = !page.model.sortDescending;
                else page.model.sortKey = hc.key;
            }
        }
    }

    // Wiersz: dział, program albo proces
    component ProcRow: Item {
        id: row
        required property int index
        required property int kind
        required property string key
        required property int depth
        required property int pid
        required property string name
        required property string iconName
        required property string desktopId
        required property real cpu
        required property real mem
        required property real disk
        required property int count
        required property bool expanded
        required property bool system
        readonly property bool header: kind === 0
        readonly property bool isGroup: kind === 1
        readonly property bool chosen: page.selected === key
        width: list.width
        height: header ? 40 : 34

        // Podbarwienie komórek według obciążenia (jak w Windows)
        function heat(v) { return Qt.rgba(1, 0.69, 0.13, Math.min(0.55, 0.05 + v * 0.5) * (Theme.dark ? 0.75 : 1)); }
        Repeater {
            model: row.header ? [] : [
                [page.cpuW + page.memW + page.diskW, page.cpuW, Math.min(1, row.cpu / 40)],
                [page.memW + page.diskW, page.memW, Math.min(1, row.mem / Math.max(1, Monitor.memTotal * 0.12))],
                [page.diskW, page.diskW, Math.min(1, row.disk / (12 * 1024 * 1024))]
            ]
            delegate: Rectangle {
                required property var modelData
                x: row.width - page.rightPad - modelData[0]
                width: modelData[1] - 1; height: row.height - 1
                color: row.heat(modelData[2])
            }
        }
        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 6; anchors.rightMargin: 6
            radius: 8
            color: row.chosen ? Theme.accentSoft : (rowArea.containsMouse && !row.header ? Theme.hover : "transparent")
            border.width: row.chosen && list.activeFocus ? 1 : 0
            border.color: Theme.accentAlpha(0.6)
        }

        // Strzałka rozwijania
        Item {
            id: chevron
            visible: row.header || (row.isGroup && row.count > 1)
            x: row.header ? 14 : 12
            width: 22; height: row.height
            Icon {
                anchors.centerIn: parent
                d: Icons.chevronRight; size: 12; stroke: 2.2
                color: Theme.text2
                rotation: row.expanded ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: 140 } }
            }
            MouseArea { anchors.fill: parent; onClicked: page.model.toggle(row.key) }
        }

        // Ikona
        Item {
            id: glyph
            visible: !row.header
            x: row.depth > 0 ? 62 : 36
            anchors.verticalCenter: parent.verticalCenter
            width: row.depth > 0 ? 18 : 22; height: width
            AppIcon {
                visible: row.isGroup
                anchors.centerIn: parent
                size: 22
                desktopId: row.desktopId
                source: row.iconName
            }
            Rectangle {
                visible: !row.isGroup
                anchors.fill: parent
                radius: width * 0.3
                color: Theme.fill
                Icon {
                    anchors.centerIn: parent
                    d: row.system ? Icons.gear : (row.depth > 0 ? Icons.prompt : Icons.apps)
                    size: parent.width * 0.6; stroke: 2
                    color: Theme.text2
                }
            }
        }

        Text {
            id: label
            x: row.header ? 40 : glyph.x + glyph.width + 10
            width: row.width - x - page.cpuW - page.memW - page.diskW - page.rightPad - 12
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: row.header ? 3 : 0
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: row.name + (row.header || (row.isGroup && row.count > 1) ? " (" + row.count + ")" : "")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: row.header ? 13 : 13
            font.weight: row.header ? Font.DemiBold : (row.isGroup ? Font.Medium : Font.Normal)
        }

        // Liczby
        Repeater {
            model: row.header ? [] : [
                [page.cpuW + page.memW + page.diskW, page.cpuW, Monitor.percent(row.cpu)],
                [page.memW + page.diskW, page.memW, Monitor.bytes(row.mem)],
                [page.diskW, page.diskW, Monitor.rate(row.disk)]
            ]
            delegate: Text {
                required property var modelData
                x: row.width - page.rightPad - modelData[0]
                width: modelData[1] - 12
                y: (row.height - height) / 2
                horizontalAlignment: Text.AlignRight
                text: modelData[2]
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 13
                font.weight: row.isGroup ? Font.Medium : Font.Normal
                font.features: { "tnum": 1 }
            }
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            anchors.leftMargin: row.header ? 0 : chevron.x + chevron.width
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (e) => {
                if (row.header) { page.model.toggle(row.key); return; }
                page.select(row.key);
                if (e.button === Qt.RightButton) {
                    const p = mapToItem(page, e.x, e.y);
                    page.menuRequested(row.key, p.x, p.y);
                }
            }
            onDoubleClicked: {
                if (row.header) return;
                if (row.isGroup && row.count > 1) page.model.toggle(row.key);
                else page.detailsRequested(row.key);
            }
        }
    }
}
