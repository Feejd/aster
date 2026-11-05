pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Harbor

// Obrazy: ile zajmują, które są używane; usuwanie pojedynczych i sprzątanie wszystkich nieużywanych
Item {
    id: page
    signal pruneRequested()
    readonly property var s: Harbor.imageSummary
    Component.onCompleted: Harbor.refreshImages()

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + 30
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            x: 20; y: 4
            width: parent.width - 40
            spacing: 2

            // Podsumowanie
            Rectangle {
                width: parent.width; height: 92
                radius: 10
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.025)
                border.width: 1; border.color: Theme.line
                Row {
                    x: 22; anchors.verticalCenter: parent.verticalCenter
                    spacing: 36
                    Stat { label: "Obrazy"; value: String(page.s.count || 0) }
                    Stat { label: "Zajmują razem"; value: page.s.sizeText || "0 B" }
                    Stat {
                        label: "Nieużywane"
                        value: (page.s.unusedCount || 0) > 0 ? page.s.unusedCount + "  ·  " + page.s.unusedText : "brak"
                        accent: (page.s.unusedCount || 0) > 0
                    }
                }
                ActionButton {
                    anchors.right: parent.right; anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (page.s.unusedCount || 0) > 0
                    enabled: !page.s.busy
                    text: page.s.busy ? "Sprzątam…" : "Zwolnij " + (page.s.unusedText || "")
                    icon: "trash"
                    onClicked: page.pruneRequested()
                }
            }
            Item { width: 1; height: 14 }

            Text {
                visible: (page.s.count || 0) === 0
                x: 12
                text: "Nie ma pobranych obrazów. Pobiorą się same przy tworzeniu środowiska albo uruchamianiu projektu."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
            }

            Repeater {
                model: Harbor.images
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property var im: modelData
                    readonly property bool busy: Harbor.busy.indexOf(im.id) >= 0
                    width: col.width; height: 56
                    radius: 12
                    color: area.containsMouse ? Theme.hover : "transparent"
                    MouseArea { id: area; anchors.fill: parent; hoverEnabled: true }

                    Rectangle {
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        width: 36; height: 36; radius: 10
                        color: Theme.fill
                        Icon { anchors.centerIn: parent; d: Icons.disc; size: 18; color: row.im.unused ? Theme.text2 : Theme.accentText }
                    }
                    Column {
                        x: 62; anchors.verticalCenter: parent.verticalCenter
                        width: right.x - x - 12
                        spacing: 3
                        Row {
                            spacing: 8
                            Text {
                                text: row.im.name
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                            }
                            Pill { visible: !!row.im.tag; anchors.verticalCenter: parent.verticalCenter; text: row.im.tag; tint: Theme.accent }
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: (row.im.registry ? row.im.registry + "  ·  " : "") + row.im.id + "  ·  pobrany " + row.im.createdText
                            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                        }
                    }
                    Row {
                        id: right
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        Pill {
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.im.unused ? "nieużywany" : row.im.containers === 1 ? "1 kontener" : row.im.containers + (row.im.containers < 5 ? " kontenery" : " kontenerów")
                            tint: row.im.unused ? "#D97706" : "#16A34A"
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 76; horizontalAlignment: Text.AlignRight
                            text: row.im.sizeText
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium; font.features: { "tnum": 1 }
                        }
                        ToolBtn {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "trash"
                            enabled: row.im.unused && !row.busy
                            tip: row.im.unused ? "Usuń obraz" : "Używany — najpierw usuń kontenery"
                            onClicked: Harbor.removeImage(row.im.id)
                        }
                    }
                }
            }
        }
    }

    component Stat: Column {
        property string label
        property string value
        property bool accent: false
        spacing: 4
        Text { text: parent.label; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        Text {
            text: parent.value
            color: parent.accent ? (Theme.dark ? "#FBBF24" : "#B45309") : Theme.text
            font.family: Theme.font; font.pixelSize: 20; font.weight: Font.DemiBold; font.features: { "tnum": 1 }
        }
    }
}
