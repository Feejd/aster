pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Store
import "Catalog.js" as Catalog
import "Facts.js" as Facts
import "Find.js" as Find

// Pierwszy ekran to pytanie, nie baner: „Chcę…”. Pod nim zadania, wybór tygodnia z uczciwym werdyktem,
// przesiadka z Windowsa i to, co akurat zyskuje, przesiane przez nasz filtr jakości.
Item {
    id: page
    property var window
    readonly property alias flick: flickable

    property var trending: []
    readonly property var local: field.text.trim() ? Find.local(field.text) : null
    function focusSearch() { field.forceActiveFocus(); }

    // Wybór tygodnia: program z pełnym werdyktem, zmienia się co tydzień
    readonly property string weekly: {
        const withVerdict = Object.keys(Catalog.apps).filter(k => !!Catalog.apps[k].good);
        return withVerdict[Math.floor(Date.now() / (7 * 86400000)) % withVerdict.length];
    }

    Component.onCompleted: {
        Net.get(Store.api + "collection/trending?page=1&per_page=30&locale=pl", 6 * 3600, (d) => {
            if (!d) return;
            const fresh = d.hits.filter(h => Facts.worthShowing(h, Flatpak.arch, true) && !Catalog.apps[h.app_id]).slice(0, 6);
            fresh.forEach(h => Store.fromHit(h));
            page.trending = fresh.map(h => h.app_id);
        });
    }

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

            // ——— Zadania ———
            Grid {
                id: grid
                width: parent.width
                columns: width > 980 ? 4 : 3
                spacing: 12
                Repeater {
                    model: Catalog.tasks
                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        width: (grid.width - (grid.columns - 1) * 12) / grid.columns
                        height: 124; radius: 16
                        color: Ui.tile(modelData.hue, tileArea.containsMouse)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Txt {
                            x: 16; y: 14
                            width: parent.width - 32
                            text: tile.modelData.title
                            wrapMode: Text.Wrap; maximumLineCount: 2
                            color: Ui.ink(tile.modelData.hue)
                            font.pixelSize: 17; font.weight: Font.DemiBold; font.letterSpacing: -0.2
                        }
                        Row {
                            x: 16
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 13
                            spacing: -7
                            Repeater {
                                model: tile.modelData.picks.slice(0, 3)
                                delegate: Item {
                                    id: mini
                                    required property var modelData
                                    width: 34; height: 34
                                    Rectangle { anchors.fill: parent; radius: 10; color: tile.color }
                                    AppGlyph { anchors.centerIn: parent; ref: mini.modelData.ref; size: 30 }
                                }
                            }
                        }
                        MouseArea { id: tileArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.window.go("task", tile.modelData.id) }
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
                            model: ["Word", "Excel", "Photoshop", "Outlook", "Premiere Pro", "Spotify", "WhatsApp", "Steam", "WinRAR / 7-Zip", "Chrome", "AutoCAD"]
                            delegate: Chip {
                                required property string modelData
                                text: modelData
                                onClicked: page.window.tab("switch", [modelData])
                            }
                        }
                    }
                }
            }

            // ——— Wybór tygodnia ———
            Column {
                id: pickCol
                width: parent.width
                spacing: 16
                readonly property var info: { Store.version; return Store.item(page.weekly); }
                Txt { text: "Wybór tygodnia"; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.5 }
                Row {
                    width: parent.width
                    spacing: 18
                    AppGlyph { ref: page.weekly; size: 72 }
                    Column {
                        width: parent.width - 72 - 18 - weeklyGet.width - 18
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Txt { width: parent.width; text: pickCol.info.name; elide: Text.ElideRight; font.pixelSize: 20; font.weight: Font.DemiBold }
                        Txt { width: parent.width; text: pickCol.info.summary; wrapMode: Text.Wrap; color: Theme.text2; font.pixelSize: 14 }
                    }
                    GetButton { id: weeklyGet; ref: page.weekly; anchors.verticalCenter: parent.verticalCenter }
                }
                Row {
                    width: parent.width
                    spacing: 24
                    Verdict { width: (parent.width - 24) / 2; title: "Co dobre"; tone: "ok"; lines: (pickCol.info.meta || {}).good || [] }
                    Verdict { width: (parent.width - 24) / 2; title: "Co słabe"; tone: "warn"; lines: (pickCol.info.meta || {}).bad || [] }
                }
            }

            // ——— Aster ———
            Column {
                width: parent.width
                spacing: 12
                Txt { text: "Zrobione przez nas"; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.5 }
                Grid {
                    id: asterGrid
                    width: parent.width
                    columns: 3
                    columnSpacing: 28
                    Repeater {
                        model: ["aster:montaz", "aster:grafika", "aster:studio"]
                        delegate: AppRow {
                            required property string modelData
                            width: (asterGrid.width - 56) / 3
                            ref: modelData
                            tag: " "
                            separator: false
                        }
                    }
                }
            }

            // ——— Zyskuje ———
            Column {
                visible: page.trending.length > 0
                width: parent.width
                spacing: 4
                Txt { text: "Zyskuje w tym tygodniu"; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.5 }
                Txt { text: "Spoza naszego katalogu: tylko potwierdzeni wydawcy, ale opinii jeszcze nie mamy."; color: Theme.text2; font.pixelSize: 14; bottomPadding: 6 }
                Grid {
                    id: trendGrid
                    width: parent.width
                    columns: 2
                    columnSpacing: 32
                    Repeater {
                        model: page.trending
                        delegate: AppRow {
                            required property string modelData
                            required property int index
                            width: (trendGrid.width - 32) / 2
                            ref: modelData
                            separator: index < page.trending.length - 2
                        }
                    }
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

    component Verdict: Column {
        id: vd
        property string title
        property string tone
        property var lines: []
        spacing: 5
        Txt { text: vd.title; color: Ui.tone(vd.tone); font.pixelSize: 13; font.weight: Font.DemiBold }
        Repeater {
            model: vd.lines
            delegate: Txt {
                required property string modelData
                width: vd.width
                text: modelData
                wrapMode: Text.Wrap
                font.pixelSize: 14
            }
        }
    }
}
