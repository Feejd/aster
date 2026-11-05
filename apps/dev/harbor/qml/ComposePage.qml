pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Harbor

// Projekty compose: foldery z compose.yaml / docker-compose.yml — znalezione po działających kontenerach
// albo dodane ręcznie. Uruchom (up -d) i zatrzymaj (down) cały projekt, usługi ze stanem i portami.
Item {
    id: page
    signal addRequested()
    signal menuRequested(string folder, Item item, real x, real y)

    Column {
        visible: Harbor.projects.length === 0
        anchors.centerIn: parent
        width: Math.min(470, parent.width - 60)
        spacing: 10
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 72; height: 72; radius: 12
            gradient: Gradient {
                GradientStop { position: 0; color: "#C4B5FD" }
                GradientStop { position: 1; color: "#7C3AED" }
            }
            Icon { anchors.centerIn: parent; d: Icons.layers; size: 34; stroke: 1.8; color: "white" }
        }
        Item { width: 1; height: 4 }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter
            text: "Brak projektów compose"
            color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
        }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: "Projekt to folder z plikiem compose.yaml (albo docker-compose.yml), w którym opisane są usługi — np. aplikacja, baza danych i Redis. Dodaj folder, a Harbor uruchomi je wszystkie jednym kliknięciem."
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.3
        }
        Item { width: 1; height: 8 }
        ActionButton {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Dodaj folder z projektem…"; icon: "folderPlus"; primary: true
            onClicked: page.addRequested()
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + 30
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: Harbor.projects.length > 0
        Column {
            id: col
            x: 20; y: 4
            width: parent.width - 40
            spacing: 14
            Repeater {
                model: Harbor.projects
                delegate: Card {}
            }
        }
    }

    component Card: Rectangle {
        id: card
        required property var modelData
        readonly property var p: modelData
        readonly property bool anyUp: p.up > 0
        width: col.width
        height: cardCol.implicitHeight + 28
        radius: 10
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.025)
        border.width: 1; border.color: Theme.line

        Column {
            id: cardCol
            x: 16; y: 14
            width: parent.width - 32
            spacing: 10

            Item {
                width: parent.width; height: 44
                Rectangle {
                    id: ptile
                    width: 40; height: 40; radius: 12
                    anchors.verticalCenter: parent.verticalCenter
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#C4B5FD" }
                        GradientStop { position: 1; color: "#7C3AED" }
                    }
                    opacity: card.anyUp ? 1 : 0.6
                    Icon { anchors.centerIn: parent; d: Icons.layers; size: 20; stroke: 1.9; color: "white" }
                }
                Column {
                    x: 54; anchors.verticalCenter: parent.verticalCenter
                    width: btns.x - x - 12
                    spacing: 3
                    Row {
                        spacing: 8
                        Text {
                            text: card.p.name
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                        }
                        Pill {
                            anchors.verticalCenter: parent.verticalCenter
                            text: card.p.missing ? "brak pliku compose"
                                  : card.p.services.length === 0 ? "bez usług"
                                  : card.p.up === card.p.services.length ? "działa"
                                  : card.p.up > 0 ? card.p.up + " z " + card.p.services.length + " działa" : "zatrzymany"
                            tint: card.p.missing ? Theme.danger : card.p.up > 0 ? "#16A34A" : Theme.text2
                        }
                    }
                    Text {
                        width: parent.width; elide: Text.ElideMiddle
                        text: card.p.folderText + (card.p.fileName ? "  ·  " + card.p.fileName : "")
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                    }
                }
                Row {
                    id: btns
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    ActionButton {
                        visible: card.anyUp
                        enabled: !card.p.busy
                        text: card.p.busy ? "Zatrzymuję…" : "Zatrzymaj"; icon: "stop"
                        onClicked: Harbor.composeDown(card.p.folder)
                    }
                    ActionButton {
                        enabled: !card.p.missing && !card.p.busy && Harbor.taskState !== "running"
                        visible: !card.anyUp || card.p.up < card.p.services.length
                        primary: true
                        text: card.anyUp ? "Uruchom resztę" : "Uruchom"; icon: "play"
                        onClicked: Harbor.composeUp(card.p.folder)
                    }
                    ToolBtn {
                        id: more
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "more"; tip: "Więcej"
                        onClicked: page.menuRequested(card.p.folder, more, -216, more.height + 4)
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.line; visible: card.p.services.length > 0 }

            Repeater {
                model: card.p.services
                delegate: Item {
                    id: svc
                    required property var modelData
                    readonly property var s: modelData
                    width: cardCol.width; height: 36
                    StateDot { x: 15; anchors.verticalCenter: parent.verticalCenter; size: 9; running: svc.s.running; busy: card.p.busy }
                    Text {
                        id: svcName
                        x: 40; anchors.verticalCenter: parent.verticalCenter
                        width: 150; elide: Text.ElideRight
                        text: svc.s.name
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                    }
                    Text {
                        x: 196; anchors.verticalCenter: parent.verticalCenter
                        width: svcRight.x - x - 10; elide: Text.ElideRight
                        text: svc.s.state === "none" ? "nie utworzona" : (svc.s.status || "") + (svc.s.image ? "  ·  " + svc.s.image.replace(/^[^/]+\.[^/]+\//, "").replace(/^library\//, "") : "")
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                    }
                    Row {
                        id: svcRight
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Repeater {
                            model: (svc.s.ports || "").split(", ").filter(x => x).slice(0, 2)
                            delegate: Pill {
                                required property string modelData
                                y: (svcRight.height - height) / 2
                                text: ":" + modelData.split("→")[0]
                                icon: "globe"; tint: Theme.accent
                                clickable: svc.s.running
                                onClicked: Qt.openUrlExternally("http://localhost:" + modelData.split("→")[0].split("-")[0])
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: svc.s.running
                            width: 120; horizontalAlignment: Text.AlignRight
                            text: (svc.s.cpu !== undefined ? svc.s.cpu.toLocaleString(Qt.locale("pl_PL"), "f", 1) + "%" : "—") + "  ·  " + (svc.s.memText || "—")
                            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 }
                        }
                        ToolBtn {
                            anchors.verticalCenter: parent.verticalCenter
                            enabled: !!svc.s.container
                            icon: "list"; tip: "Logi"
                            onClicked: Harbor.openLogs(svc.s.container)
                        }
                        ToolBtn {
                            anchors.verticalCenter: parent.verticalCenter
                            enabled: !!svc.s.container
                            icon: "prompt"; tip: "Terminal w usłudze"
                            onClicked: Harbor.openTerminal(svc.s.container)
                        }
                    }
                }
            }
        }
    }
}
