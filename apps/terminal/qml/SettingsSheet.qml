pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Terminal

// Ustawienia Terminala — arkusz nad oknem: wygląd (kolory, czcionka, kursor), zachowanie i skróty
Item {
    id: sheet
    property real radius: 24
    signal closeRequested()
    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: sheet.closeRequested()
    Component.onCompleted: forceActiveFocus()

    Rectangle { anchors.fill: parent; radius: sheet.radius; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.22) }
    MouseArea { anchors.fill: parent; onClicked: sheet.closeRequested() }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(560, parent.width - 40)
        height: Math.min(parent.height - 40, 720)
        radius: 22
        color: Theme.surface
        border.width: 1; border.color: Theme.edge
        MouseArea { anchors.fill: parent }

        Text {
            x: 24; y: 20
            text: "Ustawienia"
            color: Theme.text; font.family: Theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
        }
        HoverButton {
            anchors.right: parent.right; anchors.rightMargin: 14; y: 14
            width: 34; height: 34; radius: 17
            onClicked: sheet.closeRequested()
            Icon { anchors.centerIn: parent; d: Icons.close; size: 14; stroke: 2; color: Theme.text2 }
        }

        Flickable {
            id: flick
            y: 62; width: parent.width; height: parent.height - y - 8
            contentHeight: col.height + 24
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: col
                x: 24; width: parent.width - 48
                spacing: 22

                // ——— Kolory ———
                Group {
                    title: "Kolory"
                    Flow {
                        width: parent.width
                        spacing: 10
                        Repeater {
                            model: Terminal.schemes
                            delegate: SchemeTile {}
                        }
                    }
                }

                // ——— Tekst ———
                Group {
                    title: "Tekst"
                    Row_ {
                        label: "Czcionka"
                        HoverButton {
                            width: 220; height: 34; radius: 10
                            baseColor: Theme.fill
                            onClicked: fontList.visible = !fontList.visible
                            Text {
                                x: 12; width: parent.width - 40
                                anchors.verticalCenter: parent.verticalCenter
                                text: Terminal.fontFamily; elide: Text.ElideRight
                                color: Theme.text; font.family: Terminal.fontFamily; font.pixelSize: 13
                            }
                            Icon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.chevronDown; size: 13; stroke: 2; color: Theme.text2 }
                        }
                    }
                    // Lista czcionek o stałej szerokości, każda pokazana swoim krojem
                    Rectangle {
                        id: fontList
                        visible: false
                        width: parent.width; height: Math.min(220, Terminal.fonts.length * 36 + 8)
                        radius: 12
                        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.03)
                        border.width: 1; border.color: Theme.line
                        ListView {
                            anchors.fill: parent; anchors.margins: 4
                            clip: true
                            model: Terminal.fonts
                            boundsBehavior: Flickable.StopAtBounds
                            delegate: HoverButton {
                                id: fontRow
                                required property string modelData
                                width: ListView.view.width; height: 36; radius: 8
                                baseColor: modelData === Terminal.fontFamily ? Theme.accentSoft : "transparent"
                                onClicked: { Terminal.fontFamily = modelData; fontList.visible = false; }
                                Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: fontRow.modelData; color: Theme.text; font.family: fontRow.modelData; font.pixelSize: 14 }
                                Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: "~/ $ ls -la"; color: Theme.text2; font.family: fontRow.modelData; font.pixelSize: 12 }
                            }
                        }
                    }
                    Row_ {
                        label: "Rozmiar"
                        Row {
                            spacing: 6
                            Step { icon: "minimize"; onClicked: Terminal.fontSize = Math.max(8, Terminal.fontSize - 1) }
                            Text {
                                width: 44; anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: Math.round(Terminal.fontSize)
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium
                                font.features: { "tnum": 1 }
                            }
                            Step { icon: "plus"; onClicked: Terminal.fontSize = Math.min(40, Terminal.fontSize + 1) }
                        }
                    }
                    Row_ {
                        label: "Odstęp między wierszami"
                        Segmented {
                            model: [{ label: "Ciasny", value: 1.0 }, { label: "Zwykły", value: 1.2 }, { label: "Luźny", value: 1.4 }]
                            value: Terminal.lineHeight
                            onPicked: (v) => Terminal.lineHeight = v
                        }
                    }
                }

                // ——— Kursor ———
                Group {
                    title: "Kursor"
                    Row_ {
                        label: "Kształt"
                        Segmented {
                            model: [{ label: "Kreska", value: 3 }, { label: "Blok", value: 1 }, { label: "Podkreślenie", value: 2 }]
                            value: Terminal.cursorStyle
                            onPicked: (v) => Terminal.cursorStyle = v
                        }
                    }
                    Switch { label: "Miganie"; checked: Terminal.cursorBlink; onToggled: Terminal.cursorBlink = !Terminal.cursorBlink }
                }

                // ——— Zachowanie ———
                Group {
                    title: "Zachowanie"
                    Row_ {
                        label: "Nowa karta otwiera się"
                        Segmented {
                            model: [{ label: "W tym samym folderze", value: true }, { label: "W domowym", value: false }]
                            value: Terminal.newTabHere
                            onPicked: (v) => Terminal.newTabHere = v
                        }
                    }
                    Row_ {
                        label: "Historia przewijania"
                        Segmented {
                            model: [{ label: "1 tys.", value: 1000 }, { label: "10 tys.", value: 10000 }, { label: "100 tys.", value: 100000 }, { label: "Bez limitu", value: 0 }]
                            value: Terminal.historyLines
                            onPicked: (v) => Terminal.historyLines = v
                        }
                    }
                    Switch {
                        label: "Kopiuj zaznaczony tekst od razu"
                        detail: "Bez Ctrl+C — jak w terminalach Linuksa"
                        checked: Terminal.copyOnSelect; onToggled: Terminal.copyOnSelect = !Terminal.copyOnSelect
                    }
                    Switch {
                        label: "Mignięcie zamiast dźwięku"
                        detail: "Gdy program sygnalizuje błąd albo koniec"
                        checked: Terminal.visualBell; onToggled: Terminal.visualBell = !Terminal.visualBell
                    }
                    Switch {
                        label: "Pytaj przed zamknięciem działającego programu"
                        checked: Terminal.confirmClose; onToggled: Terminal.confirmClose = !Terminal.confirmClose
                    }
                    Switch {
                        label: "Powiadom, gdy długie polecenie się skończy"
                        detail: "Gdy trwało ponad 10 sekund, a okno było w tle"
                        checked: Terminal.notifyDone; onToggled: Terminal.notifyDone = !Terminal.notifyDone
                    }
                }

                // ——— Skróty ———
                Group {
                    title: "Skróty klawiszowe"
                    Repeater {
                        model: [
                            ["Kopiuj (gdy coś jest zaznaczone)", "Ctrl+C"],
                            ["Przerwij działający program", "Ctrl+C"],
                            ["Wklej", "Ctrl+V"],
                            ["Nowa karta / zamknij kartę", "Ctrl+Shift+T / W"],
                            ["Następna / poprzednia karta", "Ctrl+Tab / Ctrl+Shift+Tab"],
                            ["Karta 1–9", "Alt+1…9"],
                            ["Nowe okno", "Ctrl+Shift+N"],
                            ["Szukaj", "Ctrl+Shift+F"],
                            ["Wyczyść", "Ctrl+Shift+K"],
                            ["Przewiń historię", "Shift+PgUp / PgDn"],
                            ["Większy / mniejszy tekst", "Ctrl++ / Ctrl+−"],
                            ["Otwórz link", "Ctrl + kliknięcie"]
                        ]
                        delegate: Item {
                            id: sc
                            required property var modelData
                            width: parent ? parent.width : 0; height: 34
                            Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: sc.modelData[0]; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                            Text { anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: sc.modelData[1]; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                        }
                    }
                }

                Item {
                    width: parent.width; height: 36
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Terminal " + Terminal.version + " · powłoka " + Terminal.shellName
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                    }
                    HoverButton {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: resetText.implicitWidth + 28; height: 34; radius: 17
                        baseColor: Theme.fill
                        onClicked: Terminal.resetSettings()
                        Text { id: resetText; anchors.centerIn: parent; text: "Przywróć domyślne"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                    }
                }
            }
        }
    }

    // ——— Elementy ———
    component Group: Column {
        id: grp
        property string title
        default property alias rows: body.data
        width: parent ? parent.width : 0
        spacing: 8
        Text { text: grp.title; leftPadding: 2; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
        Rectangle {
            width: parent.width; height: body.height + 8
            radius: 14
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.03)
            border.width: 1; border.color: Theme.line
            Column { id: body; y: 4; x: 0; width: parent.width; spacing: 0 }
        }
    }

    component Row_: Item {
        id: rw
        property string label
        default property alias control: holder.data
        width: parent ? parent.width : 0
        height: Math.max(50, holder.childrenRect.height + 16)
        Text { x: 16; anchors.verticalCenter: parent.verticalCenter; text: rw.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
        Item {
            id: holder
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width; height: childrenRect.height
        }
    }

    component Switch: Item {
        id: sw
        property string label
        property string detail
        property bool checked
        signal toggled()
        width: parent ? parent.width : 0
        height: Math.max(50, swCol.implicitHeight + 20)
        Column {
            id: swCol
            x: 16; width: parent.width - 90
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text { text: sw.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
            Text { visible: sw.detail !== ""; width: parent.width; wrapMode: Text.Wrap; text: sw.detail; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        }
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 42; height: 25; radius: 12.5
            color: sw.checked ? Theme.accent : (Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.14))
            Behavior on color { ColorAnimation { duration: 90 } }
            Rectangle {
                x: sw.checked ? parent.width - width - 3 : 3
                anchors.verticalCenter: parent.verticalCenter
                width: 19; height: 19; radius: 9.5
                color: "white"
                Behavior on x { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
    }

    component Segmented: Rectangle {
        id: seg
        property var model: []
        property var value
        signal picked(var v)
        width: segRow.width + 6; height: 34; radius: 10
        color: Theme.fill
        Row {
            id: segRow
            x: 3; anchors.verticalCenter: parent.verticalCenter
            Repeater {
                model: seg.model
                delegate: Rectangle {
                    id: opt
                    required property var modelData
                    readonly property bool on: modelData.value === seg.value
                    width: optText.implicitWidth + 22; height: 28; radius: 8
                    color: on ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : "white") : "transparent"
                    border.width: on && !Theme.dark ? 1 : 0; border.color: Theme.edge
                    Text { id: optText; anchors.centerIn: parent; text: opt.modelData.label; color: opt.on ? Theme.text : Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: opt.on ? Font.Medium : Font.Normal }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: seg.picked(opt.modelData.value) }
                }
            }
        }
    }

    component Step: HoverButton {
        property string icon
        width: 34; height: 34; radius: 17
        baseColor: Theme.fill
        Icon { anchors.centerIn: parent; d: Icons[parent.icon] || ""; size: 14; stroke: 2; color: Theme.text }
    }

    // Kafelek schematu: podgląd z kolorowym znakiem zachęty
    component SchemeTile: Item {
        id: tile
        required property var modelData
        readonly property var c: Terminal.colors(modelData.id, Theme.dark)
        readonly property bool on: Terminal.scheme === modelData.id
        width: 156; height: 116
        Rectangle {
            id: prev
            width: parent.width; height: 78
            radius: 12
            color: tile.c.background
            border.width: tile.on ? 2 : 1
            border.color: tile.on ? Theme.accent : Theme.line
            Column {
                x: 12; y: 12
                spacing: 3
                Text {
                    textFormat: Text.StyledText
                    text: "<font color='" + tile.c.palette[2] + "'>~</font> <font color='" + tile.c.palette[4] + "'>$</font> ls"
                    color: tile.c.foreground; font.family: Terminal.fontFamily; font.pixelSize: 11
                }
                Text {
                    textFormat: Text.StyledText
                    text: "<font color='" + tile.c.palette[4] + "'>Dokumenty</font> <font color='" + tile.c.palette[2] + "'>run.sh</font>"
                    color: tile.c.foreground; font.family: Terminal.fontFamily; font.pixelSize: 11
                }
                Row {
                    spacing: 3
                    topPadding: 4
                    Repeater {
                        model: [1, 2, 3, 4, 5, 6]
                        delegate: Rectangle {
                            required property int modelData
                            width: 12; height: 6; radius: 3
                            color: tile.c.palette[modelData]
                        }
                    }
                }
            }
        }
        Text {
            y: 84
            text: tile.modelData.name
            color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: tile.on ? Font.DemiBold : Font.Normal
        }
        Text {
            y: 101
            text: tile.modelData.hint
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Terminal.scheme = tile.modelData.id }
    }
}
