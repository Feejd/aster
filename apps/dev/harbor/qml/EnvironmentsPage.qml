pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Harbor

// Środowiska: toolboxy (z rodzajem i folderem projektu) i pozostałe kontenery podmana
Item {
    id: page
    property string filter
    property string selected
    signal select(string name)
    signal menuRequested(string name, Item item, real x, real y)
    signal newRequested()
    signal removeRequested(string name)

    readonly property var matching: Harbor.containers.filter(c => {
        const f = filter.trim().toLowerCase();
        return !f || c.name.toLowerCase().includes(f) || c.image.toLowerCase().includes(f) || (c.project || "").toLowerCase().includes(f);
    })
    readonly property var toolboxes: matching.filter(c => c.toolbox)
    readonly property var others: matching.filter(c => !c.toolbox)

    function kindInfo(id) { return Harbor.kinds.find(k => k.id === id) || null; }
    function shortImage(img) {
        let s = img.replace(/^[^/]+\.[^/]+\//, "").replace(/^library\//, "");
        return s.length > 42 ? "…" + s.slice(-41) : s;
    }

    // Pusto
    Column {
        visible: Harbor.ready && Harbor.containers.length === 0
        anchors.centerIn: parent
        width: Math.min(460, parent.width - 60)
        spacing: 10
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 72; height: 72; radius: 22
            gradient: Gradient {
                GradientStop { position: 0; color: "#5EE7DF" }
                GradientStop { position: 1; color: "#2E9BEF" }
            }
            Icon { anchors.centerIn: parent; d: Icons.terminal; size: 34; stroke: 1.8; color: "white" }
        }
        Item { width: 1; height: 4 }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter
            text: "Nie masz jeszcze żadnego środowiska"
            color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
        }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: "Środowisko to osobna Fedora w toolboxie z narzędziami do języka, w którym piszesz. System zostaje czysty, a Twój folder domowy jest w środku dostępny."
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.3
        }
        Item { width: 1; height: 8 }
        ActionButton {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Utwórz środowisko"; icon: "plus"; primary: true
            onClicked: page.newRequested()
        }
    }

    Text {
        visible: Harbor.containers.length > 0 && page.matching.length === 0
        anchors.centerIn: parent
        text: "Nic nie pasuje do „" + page.filter + "”"
        color: Theme.text2; font.family: Theme.font; font.pixelSize: 14
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.implicitHeight + 30
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: page.matching.length > 0
        MouseArea { width: flick.width; height: Math.max(flick.height, col.implicitHeight); onClicked: page.select("") }

        Column {
            id: col
            x: 16; y: 2
            width: parent.width - 32
            spacing: 2

            SectionTitle { visible: page.toolboxes.length > 0; text: "Środowiska (toolbox)"; count: page.toolboxes.length; first: true }
            Repeater { model: page.toolboxes; delegate: Row_ {} }
            SectionTitle { visible: page.others.length > 0; text: "Kontenery"; count: page.others.length; first: page.toolboxes.length === 0 }
            Repeater { model: page.others; delegate: Row_ {} }
        }
    }

    component SectionTitle: Item {
        id: st
        property string text
        property int count
        property bool first: false
        width: parent ? parent.width : 0
        height: first ? 30 : 46
        Text {
            x: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
            text: st.text + "  ·  " + st.count
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; font.letterSpacing: 0.2
        }
    }

    component Row_: Rectangle {
        id: row
        required property var modelData
        readonly property var c: modelData
        readonly property var kind: page.kindInfo(c.kind)
        readonly property bool isSelected: page.selected === c.name
        readonly property bool busy: Harbor.busy.indexOf(c.name) >= 0
        width: col.width; height: 66
        radius: 12
        color: isSelected ? Theme.accentSoft : rowArea.containsMouse ? Theme.hover : "transparent"

        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (e) => {
                page.select(row.c.name);
                if (e.button === Qt.RightButton) page.menuRequested(row.c.name, row, e.x, e.y);
            }
            onDoubleClicked: Harbor.openTerminal(row.c.name)
        }

        // Ikona rodzaju z kropką stanu
        Item {
            id: tile
            x: 12; anchors.verticalCenter: parent.verticalCenter
            width: 40; height: 40
            Rectangle {
                anchors.fill: parent; radius: 12
                gradient: Gradient {
                    GradientStop { position: 0; color: row.kind ? row.kind.colors[0] : row.c.toolbox ? "#CBD5E1" : row.c.project ? "#C4B5FD" : "#7DE3F0" }
                    GradientStop { position: 1; color: row.kind ? row.kind.colors[1] : row.c.toolbox ? "#475569" : row.c.project ? "#7C3AED" : "#0E7490" }
                }
                opacity: row.c.running ? 1 : 0.55
                Icon {
                    anchors.centerIn: parent
                    d: Icons[row.kind ? row.kind.icon : row.c.toolbox ? "terminal" : row.c.project ? "layers" : "archive"] || ""
                    size: 20; stroke: 1.9; color: "white"
                }
            }
            StateDot {
                x: parent.width - 9; y: parent.height - 9
                size: 11
                running: row.c.running
                paused: row.c.state === "paused"
                busy: row.busy
            }
        }

        Column {
            x: 66; anchors.verticalCenter: parent.verticalCenter
            width: actions.x - x - 12
            spacing: 4
            Row {
                spacing: 8
                width: parent.width
                Text {
                    id: nameText
                    width: Math.min(implicitWidth, parent.width - pills.implicitWidth - 8)
                    elide: Text.ElideRight
                    text: row.c.name
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                }
                Row {
                    id: pills
                    spacing: 5
                    anchors.verticalCenter: nameText.verticalCenter
                    Pill { visible: !!row.kind; text: row.kind ? row.kind.name : ""; tint: row.kind ? row.kind.colors[1] : Theme.text2 }
                    Pill { visible: !!row.c.project; text: row.c.project + (row.c.service ? " · " + row.c.service : ""); icon: "layers"; tint: "#7C3AED" }
                }
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: (row.busy ? "Chwileczkę…" : row.c.status) + "  ·  " + page.shortImage(row.c.image)
                      + (row.c.folder ? "  ·  " + Harbor.homePath(row.c.folder) : "")
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
        }

        // Porty, zużycie i przyciski
        Row {
            id: actions
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Repeater {
                    model: (row.c.portList || []).slice(0, 2)
                    delegate: Pill {
                        required property var modelData
                        text: ":" + modelData.host
                        icon: "globe"
                        tint: Theme.accent
                        clickable: row.c.running && modelData.protocol === "tcp"
                        onClicked: Qt.openUrlExternally("http://localhost:" + modelData.host)
                    }
                }
                Item { width: 6; height: 1 }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: 74
                visible: row.c.running
                spacing: 2
                Text {
                    anchors.right: parent.right
                    text: row.c.cpu !== undefined ? row.c.cpu.toLocaleString(Qt.locale("pl_PL"), "f", 1) + "% CPU" : "— CPU"
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium; font.features: { "tnum": 1 }
                }
                Text {
                    anchors.right: parent.right
                    text: row.c.memText ? row.c.memText : "— RAM"
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 }
                }
            }
            Item { width: row.c.running ? 8 : 82; height: 1 }

            ToolBtn {
                anchors.verticalCenter: parent.verticalCenter
                enabled: !row.busy
                icon: row.c.running ? "stop" : "play"
                tip: row.c.running ? "Zatrzymaj" : "Uruchom"
                onClicked: row.c.running ? Harbor.stop(row.c.name) : Harbor.start(row.c.name)
            }
            ToolBtn {
                anchors.verticalCenter: parent.verticalCenter
                icon: "prompt"; tip: "Terminal w środku (Enter)"
                enabled: !row.busy
                onClicked: Harbor.openTerminal(row.c.name)
            }
            ToolBtn {
                anchors.verticalCenter: parent.verticalCenter
                icon: "list"; tip: "Logi na żywo (L)"
                onClicked: { page.select(row.c.name); Harbor.openLogs(row.c.name); }
            }
            ToolBtn {
                id: moreBtn
                anchors.verticalCenter: parent.verticalCenter
                icon: "more"; tip: "Więcej"
                onClicked: page.menuRequested(row.c.name, moreBtn, -216, moreBtn.height + 4)
            }
        }
    }
}
