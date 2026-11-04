pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Store
import "Catalog.js" as Catalog
import "Find.js" as Find

// Pierwszy ekran: „Chcę…”, a pod nim wyłącznie to, co ludzie znają i czego szukają:
// najpopularniejsze programy, AI, gry, zadania i przesiadka z Windowsa.
Item {
    id: page
    property var window
    readonly property alias flick: flickable

    readonly property var local: field.text.trim() ? Find.local(field.text) : null
    function focusSearch() { field.forceActiveFocus(); }

    Flickable {
        id: flickable
        anchors.fill: parent
        contentHeight: col.height + 70
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: col
            width: Math.min(page.width - 2 * Ui.gutter, Ui.maxWidth)
            x: (page.width - width) / 2
            y: 34
            spacing: 34

            // ——— Chcę… ———
            Column {
                width: parent.width
                spacing: 12
                Row {
                    width: parent.width
                    spacing: 14
                    Txt {
                        id: want
                        text: "Chcę"
                        font.pixelSize: 46; font.weight: Font.Bold; font.letterSpacing: -1.4
                    }
                    TextInput {
                        id: field
                        width: parent.width - want.width - 14
                        anchors.baseline: want.baseline
                        color: Theme.accentText
                        font.family: Theme.font; font.pixelSize: 46; font.weight: Font.Bold; font.letterSpacing: -1.4
                        selectionColor: Theme.accentSoft
                        selectedTextColor: Theme.text
                        clip: true
                        focus: true
                        Keys.onReturnPressed: page.window.search(text)
                        Keys.onEnterPressed: page.window.search(text)
                        Keys.onEscapePressed: text = ""
                        Txt {
                            visible: !field.text
                            text: hints.current
                            color: Theme.text2
                            opacity: 0.5
                            font: field.font
                        }
                        Timer {
                            id: hints
                            property int i: 0
                            readonly property var list: ["zmontować film z wakacji", "otworzyć plik .psd", "zastąpić Worda", "zagrać w Wiedźmina", "wysłać zdjęcia z telefonu", "nauczyć się angielskiego"]
                            readonly property string current: list[i]
                            interval: 3400; repeat: true
                            running: !field.text && flickable.contentY < 120
                            onTriggered: i = (i + 1) % list.length
                        }
                    }
                }
                Rectangle { width: parent.width; height: 2; radius: 1; color: field.activeFocus ? Theme.accent : Theme.line; Behavior on color { ColorAnimation { duration: 120 } } }

                // Podpowiedzi natychmiast, z własnego katalogu
                Column {
                    visible: !!page.local
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: page.local ? page.local.tasks : []
                        delegate: Suggest {
                            required property var modelData
                            label: modelData.title
                            hint: "przewodnik"
                            onClicked: page.window.go("task", modelData.id)
                        }
                    }
                    Repeater {
                        model: page.local ? page.local.windows : []
                        delegate: Suggest {
                            required property var modelData
                            label: "Zamiast: " + modelData.name
                            hint: "z Windowsa"
                            onClicked: page.window.tab("switch", [modelData.name])
                        }
                    }
                    Repeater {
                        model: page.local ? page.local.refs.slice(0, 4) : []
                        delegate: Suggest {
                            required property var modelData
                            label: { Store.version; return Store.item(modelData).name; }
                            hint: "program"
                            onClicked: Store.openApp(modelData)
                        }
                    }
                    Suggest {
                        label: "Szukaj wszędzie: " + field.text
                        hint: "Enter"
                        onClicked: page.window.search(field.text)
                    }
                }
            }

            Txt {
                visible: !Net.online
                text: "Bez internetu pokazujemy ostatnio zapisany katalog. Instalowanie wróci razem z siecią."
                color: Theme.text2; font.pixelSize: 13
            }

            Shelf { title: "Najczęściej instalowane"; refs: Catalog.top }
            Shelf { title: "Sztuczna inteligencja"; refs: Catalog.homeAi; more: "ai" }
            Shelf { title: "Gry"; refs: Catalog.homeGames; more: "gry" }

            // ——— Zadania ———
            Column {
                width: parent.width
                spacing: 12
                Txt { text: "Nie wiesz, czego szukasz?"; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.5 }
                Flow {
                    width: parent.width
                    spacing: 7
                    Repeater {
                        model: Catalog.tasks
                        delegate: Chip {
                            required property var modelData
                            text: modelData.title
                            onClicked: page.window.go("task", modelData.id)
                        }
                    }
                }
            }

            // ——— Z Windowsa ———
            Rectangle {
                width: parent.width
                height: winCol.implicitHeight + 40
                radius: 18
                color: Theme.fill
                Column {
                    id: winCol
                    x: 24; y: 20
                    width: parent.width - 48
                    spacing: 14
                    Row {
                        width: parent.width
                        Column {
                            width: parent.width - goWin.width
                            spacing: 3
                            Txt { text: "Czego używasz na Windowsie?"; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.5 }
                            Txt { text: "Zaznacz, a powiemy, czym to zastąpić i co stanie się z Twoimi plikami."; color: Theme.text2; font.pixelSize: 14 }
                        }
                        Btn { id: goWin; text: "Ułóż mój zestaw"; primary: true; anchors.verticalCenter: parent.verticalCenter; onClicked: page.window.tab("switch") }
                    }
                    Flow {
                        width: parent.width
                        spacing: 7
                        Repeater {
                            model: ["Word", "Excel", "Photoshop", "Outlook", "Premiere Pro", "WhatsApp", "WinRAR / 7-Zip", "AutoCAD"]
                            delegate: Chip {
                                required property string modelData
                                text: modelData
                                onClicked: page.window.tab("switch", [modelData])
                            }
                        }
                    }
                }
            }

            Shelf { title: "Zrobione przez nas"; refs: ["aster:montaz", "aster:grafika", "aster:studio", "aster:code", "aster:pulse", "aster:vault"] }
        }
    }

    component Shelf: Column {
        id: shelf
        property string title
        property var refs: []
        property string more: ""
        width: col.width
        spacing: 12
        readonly property int cols: width > 980 ? 6 : 4
        Item {
            width: parent.width; height: shelfTitle.height
            Txt { id: shelfTitle; text: shelf.title; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.5 }
            Txt {
                visible: shelf.more !== ""
                anchors.right: parent.right; anchors.baseline: shelfTitle.baseline
                text: "Zobacz wszystko"
                color: Theme.accentText; font.pixelSize: 14; font.weight: Font.Medium
                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: page.window.tab("list", { cat: shelf.more }) }
            }
        }
        Grid {
            id: shelfGrid
            width: parent.width
            columns: shelf.cols
            spacing: 10
            Repeater {
                model: shelf.refs
                delegate: AppCard {
                    required property string modelData
                    width: (shelfGrid.width - (shelf.cols - 1) * 10) / shelf.cols
                    ref: modelData
                }
            }
        }
    }

    component Suggest: Rectangle {
        id: sg
        property string label
        property string hint
        signal clicked()
        width: parent ? parent.width : 300
        height: 40; radius: 9
        color: sgArea.containsMouse ? Theme.hover : "transparent"
        Txt { x: 10; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 120; text: sg.label; elide: Text.ElideRight; font.pixelSize: 15 }
        Txt { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: sg.hint; color: Theme.text2; font.pixelSize: 12 }
        MouseArea { id: sgArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sg.clicked() }
    }
}
