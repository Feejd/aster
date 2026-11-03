pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Aster.Ui
import Aster.Studio

// Ekran startowy: „Nowy projekt” i ostatnie projekty (karty z liczbą ścieżek i tempem)
Item {
    id: start
    required property Window window
    required property real radius
    signal newRequested(string genre)
    signal openRequested()
    signal bundleRequested()
    signal menuRequested(var project, Item item, real x, real y)

    // ——— Pasek boczny ———
    Item {
        id: side
        width: 220; height: parent.height
        DragHandler { target: null; onActiveChanged: if (active) start.window.startSystemMove() }
        Column {
            x: 10; y: 58
            width: parent.width - 20
            spacing: 2
            Rectangle {
                width: parent.width; height: 34; radius: 9
                color: Theme.accent
                Rectangle {
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24; radius: 7
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#FF9F7A" }
                        GradientStop { position: 1; color: "#E5484D" }
                    }
                    Icon { anchors.centerIn: parent; d: Icons.music; size: 14; stroke: 2; color: "white" }
                }
                Text { x: 42; anchors.verticalCenter: parent.verticalCenter; text: "Projekty"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: Studio.recent.length || ""
                    color: Qt.rgba(1, 1, 1, 0.8)
                    font.family: Theme.font; font.pixelSize: 12
                }
            }
            HoverButton {
                width: parent.width; height: 32; radius: 9
                onClicked: start.openRequested()
                Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; d: Icons.folder; size: 15; color: Theme.text2 }
                Text { x: 38; anchors.verticalCenter: parent.verticalCenter; text: "Otwórz projekt…"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
            }
            HoverButton {
                width: parent.width; height: 32; radius: 9
                onClicked: start.bundleRequested()
                Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; d: Icons.archive; size: 15; color: Theme.text2 }
                Text { x: 38; anchors.verticalCenter: parent.verticalCenter; text: "Otwórz paczkę od znajomego…"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
            }
        }
        // Stan dźwięku — od razu widać, gdy coś nie działa
        Row {
            x: 20; anchors.bottom: parent.bottom; anchors.bottomMargin: 18
            spacing: 8
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: Studio.audioOk && !Studio.audioError ? "#30C26B" : "#E5484D" }
            Text {
                width: side.width - 56
                text: Studio.audioOk && !Studio.audioError ? "Dźwięk gotowy" : (Studio.audioError || "Brak dźwięku")
                wrapMode: Text.WordWrap
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 12
            }
        }
    }

    GlassPane {
        x: side.width
        width: parent.width - side.width
        height: parent.height
        topRightRadius: start.radius
        bottomRightRadius: start.radius

        Item {
            id: topBar
            width: parent.width; height: 68
            z: 5
            DragHandler { target: null; onActiveChanged: if (active) start.window.startSystemMove() }
            TapHandler { onDoubleTapped: if (start.window.visibility === Window.Maximized) start.window.showNormal(); else start.window.showMaximized() }
            Column {
                x: 28; anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text { text: "Studio"; color: Theme.text; font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4 }
                Text { text: "Nagraj, ułóż i zmiksuj swoją piosenkę"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
            }
            WindowButtons {
                window: start.window
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Flickable {
            y: topBar.height
            width: parent.width; height: parent.height - y
            contentHeight: grid.y + grid.height + 30
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Text {
                id: newLabel
                x: 28; y: 6
                text: "Zacznij"
                color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Row {
                id: starters
                x: 28; y: newLabel.y + newLabel.height + 12
                spacing: 16
                StarterCard {
                    title: "Nowy projekt"
                    hint: "Pusta piosenka z metronomem — ścieżki na wokal i gitarę"
                    icon: "plus"
                    colors: ["#FF9F7A", "#E5484D"]
                    onClicked: start.newRequested("")
                }
                StarterCard {
                    title: "Otwórz projekt"
                    hint: "Folder projektu albo plik projekt.json"
                    icon: "folder"
                    colors: ["#74CCFF", "#2457E6"]
                    onClicked: start.openRequested()
                }
            }

            Text {
                id: genreLabel
                x: 28; y: starters.y + starters.height + 30
                text: "Zacznij od gatunku"
                color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Text {
                x: 28; y: genreLabel.y + genreLabel.height + 2
                text: "Gotowy bit, 808, ścieżki na wokal z efektami i mastering — wystarczy nagrać głos"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
            Flow {
                id: genresFlow
                x: 28; y: genreLabel.y + genreLabel.height + 26
                width: parent.width - 56
                spacing: 12
                Repeater {
                    model: Studio.genres
                    delegate: HoverButton {
                        id: gcard
                        required property var modelData
                        required property int index
                        readonly property var shades: [["#8E5CFF", "#3A1C8C"], ["#5C6CFF", "#1C2A8C"], ["#FFB86B", "#C2410C"], ["#7CE0C3", "#16806A"], ["#FF6BD5", "#9D1C7A"], ["#FF9F7A", "#E5484D"]]
                        width: 138; height: 96; radius: 16
                        gradient: Gradient {
                            GradientStop { position: 0; color: gcard.shades[gcard.index % 6][0] }
                            GradientStop { position: 1; color: gcard.shades[gcard.index % 6][1] }
                        }
                        onClicked: start.newRequested(modelData.id)
                        Text { x: 14; y: 12; text: gcard.modelData.label; color: "white"; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold }
                        Text { x: 14; y: 36; text: gcard.modelData.bpm + " BPM"; color: Qt.rgba(1, 1, 1, 0.85); font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                        Row {
                            x: 14; anchors.bottom: parent.bottom; anchors.bottomMargin: 14
                            spacing: 3
                            Repeater {
                                model: 16
                                delegate: Rectangle {
                                    required property int index
                                    width: 5; height: 5 + ((index * 7 + gcard.index * 3) % 5) * 3; radius: 2
                                    anchors.bottom: parent ? parent.bottom : undefined
                                    color: Qt.rgba(1, 1, 1, index % 4 === 0 ? 0.95 : 0.55)
                                }
                            }
                        }
                        Tip { shown: gcard.hovered; text: gcard.modelData.hint }
                    }
                }
            }

            Text {
                id: recentLabel
                visible: Studio.recent.length > 0
                x: 28; y: genresFlow.y + genresFlow.height + 30
                text: "Ostatnie projekty"
                color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Flow {
                id: grid
                x: 18; y: recentLabel.y + recentLabel.height + 8
                width: parent.width - 36
                Repeater {
                    model: Studio.recent
                    delegate: Item {
                        id: tile
                        required property var modelData
                        required property int index
                        width: 200; height: 196
                        Rectangle {
                            id: art
                            x: 10; y: 6
                            width: parent.width - 20; height: 120; radius: 14
                            readonly property var shades: [["#FFB86B", "#E5484D"], ["#7CE0C3", "#1E9E7A"], ["#A39BFF", "#5B3FD9"], ["#74CCFF", "#2457E6"], ["#FF9ED2", "#C72C83"]]
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: art.shades[tile.index % 5][0] }
                                GradientStop { position: 1; color: art.shades[tile.index % 5][1] }
                            }
                            scale: tileArea.pressed ? 0.98 : 1
                            Behavior on scale { NumberAnimation { duration: 100 } }
                            // Umowne „ścieżki” z falą — miniatura projektu
                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Repeater {
                                    model: Math.max(1, Math.min(4, tile.modelData.tracks))
                                    delegate: Row {
                                        id: lane
                                        required property int index
                                        height: 17
                                        spacing: 3
                                        Repeater {
                                            model: 22
                                            delegate: Rectangle {
                                                required property int index
                                                y: (17 - height) / 2
                                                width: 3; radius: 1.5
                                                height: 3 + Math.abs(Math.sin((index + 1) * (lane.index + 2) * 0.9 + tile.index)) * 14
                                                color: Qt.rgba(1, 1, 1, 0.82)
                                            }
                                        }
                                    }
                                }
                            }
                            Rectangle { anchors.fill: parent; radius: parent.radius; color: "transparent"; border.width: 1; border.color: Theme.edge }
                        }
                        Text {
                            x: 10; y: art.y + art.height + 10
                            width: art.width
                            text: tile.modelData.name
                            elide: Text.ElideRight
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                        Text {
                            x: 10; y: art.y + art.height + 29
                            width: art.width
                            text: Studio.tracksLabel(tile.modelData.tracks) + " · " + Math.round(tile.modelData.bpm) + " BPM"
                            elide: Text.ElideRight
                            color: Theme.text2
                            font.family: Theme.font; font.pixelSize: 12
                        }
                        Text {
                            x: 10; y: art.y + art.height + 46
                            width: art.width
                            text: Studio.when(tile.modelData.modified)
                            elide: Text.ElideRight
                            color: Theme.text2
                            font.family: Theme.font; font.pixelSize: 12
                        }
                        MouseArea {
                            id: tileArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (e) => {
                                if (e.button === Qt.RightButton) start.menuRequested(tile.modelData, tile, e.x, e.y);
                                else Studio.openProject(tile.modelData.folder);
                            }
                        }
                    }
                }
            }
        }
    }

    component StarterCard: HoverButton {
        id: sc
        property string title
        property string hint
        property string icon
        property var colors
        width: 300; height: 92; radius: 16
        baseColor: Theme.fill
        Rectangle {
            x: 16; anchors.verticalCenter: parent.verticalCenter
            width: 56; height: 56; radius: 15
            gradient: Gradient {
                GradientStop { position: 0; color: sc.colors[0] }
                GradientStop { position: 1; color: sc.colors[1] }
            }
            Icon { anchors.centerIn: parent; d: Icons[sc.icon] || ""; size: 26; stroke: 2.2; color: "white" }
        }
        Column {
            x: 88; width: parent.width - 104
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text { text: sc.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
            Text { width: parent.width; text: sc.hint; wrapMode: Text.WordWrap; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        }
    }
}
