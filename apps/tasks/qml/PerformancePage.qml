pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Tasks

// Wydajność: po lewej zasoby z małymi wykresami (procesor, pamięć, dyski, sieć),
// po prawej wybrany zasób — duży wykres z ostatniej minuty i liczby pod nim.
Item {
    id: perf
    property string selected: "cpu"
    property bool perCore: false
    readonly property var res: Monitor.resources.find(r => r.id === selected) || Monitor.resources[0] || null

    // Lista zasobów
    Flickable {
        id: list
        x: 14; y: 4
        width: 252; height: parent.height - y - 14
        contentHeight: listCol.height
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Column {
            id: listCol
            width: parent.width
            spacing: 4
            Repeater {
                model: Monitor.resources
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    readonly property bool active: perf.res && perf.res.id === modelData.id
                    width: listCol.width; height: 66
                    radius: 12
                    color: active ? Theme.accentSoft : (cardArea.containsMouse ? Theme.hover : "transparent")
                    Rectangle {
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        width: 74; height: 46; radius: 7
                        color: Theme.fill
                        clip: true
                        Graph {
                            anchors.fill: parent; anchors.margins: 1
                            values: card.modelData.history
                            values2: card.modelData.history2 || []
                            max: card.modelData.max
                            color: card.modelData.color
                            color2: card.modelData.color2 || card.modelData.color
                            grid: false
                            lineWidth: 1.2
                        }
                    }
                    Column {
                        x: 94; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 10
                        spacing: 3
                        Text { width: parent.width; elide: Text.ElideRight; text: card.modelData.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text { width: parent.width; elide: Text.ElideRight; text: card.modelData.subtitle; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 } }
                    }
                    MouseArea { id: cardArea; anchors.fill: parent; hoverEnabled: true; onClicked: perf.selected = card.modelData.id }
                }
            }
        }
    }

    // Wybrany zasób
    Flickable {
        id: detail
        x: list.x + list.width + 22
        width: parent.width - x - 26
        height: parent.height
        contentHeight: body.height + 24
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Column {
            id: body
            width: parent.width
            spacing: 0
            visible: !!perf.res

            Item {
                width: parent.width; height: 40
                Text {
                    id: resTitle
                    anchors.verticalCenter: parent.verticalCenter
                    text: perf.res ? perf.res.title : ""
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 24; font.weight: Font.Bold; font.letterSpacing: -0.4
                }
                Text {
                    anchors.right: parent.right
                    anchors.left: resTitle.right; anchors.leftMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                    text: perf.res ? perf.res.device : ""
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: 14
                }
            }
            Item { width: 1; height: 10 }
            Item {
                width: parent.width; height: 20
                Text { anchors.bottom: parent.bottom; text: perf.res ? perf.res.caption : ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                Row {
                    anchors.right: parent.right; anchors.bottom: parent.bottom
                    spacing: 14
                    // Legenda sieci: pobieranie (linia ciągła) i wysyłanie (przerywana)
                    Repeater {
                        model: perf.res && perf.res.legend ? [[perf.res.legend, perf.res.color], [perf.res.legend2, perf.res.color2]] : []
                        delegate: Row {
                            id: lg
                            required property var modelData
                            spacing: 6
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 14; height: 3; radius: 1.5; color: lg.modelData[1] }
                            Text { text: lg.modelData[0]; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                        }
                    }
                    Text {
                        text: !perf.res ? "" : perf.res.kind === "net" ? Monitor.bits(perf.res.max) : "100%"
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                    }
                }
            }
            Item { width: 1; height: 6 }

            // Wykres (dla procesora — też osobno każdy rdzeń)
            Rectangle {
                id: chart
                width: parent.width
                height: Math.max(180, Math.min(320, perf.height * 0.42))
                radius: 12
                color: "transparent"
                border.width: 1
                border.color: Theme.line
                clip: true
                Graph {
                    anchors.fill: parent; anchors.margins: 1
                    visible: !(perf.perCore && perf.res && perf.res.kind === "cpu")
                    values: perf.res ? perf.res.history : []
                    values2: perf.res && perf.res.history2 ? perf.res.history2 : []
                    max: perf.res ? perf.res.max : 100
                    color: perf.res ? perf.res.color : "#5B8CFF"
                    color2: perf.res && perf.res.color2 ? perf.res.color2 : color
                    lineWidth: 2
                }
                Grid {
                    id: coreGrid
                    visible: perf.perCore && perf.res && perf.res.kind === "cpu"
                    anchors.fill: parent; anchors.margins: 8
                    readonly property int n: Monitor.cores.length
                    // Liczba kolumn, przy której wykresy rdzeni są największe (przy proporcji ok. 1,8 : 1)
                    columns: {
                        let best = 1, score = -1;
                        for (let c = 1; c <= Math.max(1, n); ++c) {
                            const s = Math.min(width / c / 1.8, height / Math.ceil(n / c));
                            if (s > score + 0.5) { score = s; best = c; }
                        }
                        return best;
                    }
                    readonly property int rowsNeeded: Math.ceil(n / columns)
                    spacing: 6
                    Repeater {
                        model: coreGrid.visible ? Monitor.cores : []
                        delegate: Rectangle {
                            id: coreCell
                            required property var modelData
                            width: (coreGrid.width - (coreGrid.columns - 1) * coreGrid.spacing) / coreGrid.columns
                            height: (coreGrid.height - (coreGrid.rowsNeeded - 1) * coreGrid.spacing) / coreGrid.rowsNeeded
                            radius: 6
                            color: "transparent"
                            border.width: 1; border.color: Theme.line
                            clip: true
                            Graph {
                                anchors.fill: parent; anchors.margins: 1
                                values: coreCell.modelData.history
                                color: "#5B8CFF"
                                grid: false
                                lineWidth: 1.2
                            }
                        }
                    }
                }
            }
            Item {
                width: parent.width; height: 24
                Text { anchors.bottom: parent.bottom; text: "60 sekund"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                Text { anchors.right: parent.right; anchors.bottom: parent.bottom; text: "0"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
            }

            // Procesor: wykres całości albo każdego rdzenia
            Item {
                width: parent.width; height: perf.res && perf.res.kind === "cpu" ? 46 : 18
                Rectangle {
                    visible: perf.res && perf.res.kind === "cpu"
                    anchors.bottom: parent.bottom
                    width: segRow.width + 6; height: 32; radius: 10
                    color: Theme.fill
                    Row {
                        id: segRow
                        x: 3; anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: [["Całość", false], ["Każdy rdzeń", true]]
                            delegate: Rectangle {
                                id: seg
                                required property var modelData
                                readonly property bool on: perf.perCore === modelData[1]
                                width: segText.implicitWidth + 26; height: 26; radius: 8
                                color: on ? Theme.surface : "transparent"
                                Text { id: segText; anchors.centerIn: parent; text: seg.modelData[0]; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: seg.on ? Font.Medium : Font.Normal }
                                MouseArea { anchors.fill: parent; onClicked: perf.perCore = seg.modelData[1] }
                            }
                        }
                    }
                }
            }
            Item { width: 1; height: 18 }

            // Liczby
            Flow {
                width: parent.width
                spacing: 0
                Repeater {
                    model: perf.res ? perf.res.stats : []
                    delegate: Item {
                        id: st
                        required property var modelData
                        required property int index
                        width: Math.max(150, Math.floor(body.width / Math.max(1, Math.floor(body.width / 170))))
                        height: 62
                        Column {
                            spacing: 3
                            Text { text: st.modelData.label; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                            Text {
                                width: st.width - 12
                                elide: Text.ElideRight
                                text: st.modelData.value
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: st.index < 2 ? 22 : 16; font.weight: Font.DemiBold
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }
            }
        }
    }
}
