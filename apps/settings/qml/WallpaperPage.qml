pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Aster.Ui
import Aster.Settings

// Tapeta: duży podgląd obecnej (jasna i ciemna wersja) i wybór z tapet Aster
Page {
    id: wp
    readonly property var walls: [
        { id: "swit", name: "Świt" }, { id: "grzbiety", name: "Grzbiety" }, { id: "mgla", name: "Mgła" },
        { id: "pasma", name: "Pasma" }, { id: "papier", name: "Papier" }
    ]
    // Własne zdjęcie (ze Zdjęć: „Ustaw jako tapetę”) — pełna ścieżka zamiast nazwy tapety Aster
    readonly property bool custom: Config.wallpaper.startsWith("/")
    function src(id, mode) { return id.startsWith("/") ? "file://" + id : "file://" + Config.dataDir + "/wallpapers/" + id + "-" + mode + ".jpg"; }
    readonly property var currentWall: custom ? ({ id: Config.wallpaper, name: "Własne zdjęcie" }) : (walls.find(w => w.id === Config.wallpaper) || walls[0])

    // Obecna tapeta: lewa połowa jasna, prawa ciemna
    Item {
        id: hero
        width: parent.width; height: Math.round(width * 0.42)
        Item {
            id: pair
            anchors.fill: parent
            visible: GraphicsInfo.api === GraphicsInfo.Software
            Image {
                anchors.fill: parent
                source: wp.src(wp.currentWall.id, "light")
                sourceSize: Qt.size(1280, 800)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Item {
                x: parent.width / 2; width: parent.width / 2; height: parent.height
                clip: true
                Image {
                    x: -parent.x; width: pair.width; height: pair.height
                    source: wp.src(wp.currentWall.id, "dark")
                    sourceSize: Qt.size(1280, 800)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
        }
        Rectangle { id: heroMask; anchors.fill: parent; radius: 18; visible: false; layer.enabled: true }
        MultiEffect {
            anchors.fill: parent
            source: pair
            maskEnabled: true
            maskSource: heroMask
            visible: GraphicsInfo.api !== GraphicsInfo.Software
        }
        Column {
            x: 22; anchors.bottom: parent.bottom; anchors.bottomMargin: 18
            Text { text: wp.currentWall.name; color: "white"; font.family: Theme.font; font.pixelSize: 26; font.weight: Font.Bold; font.letterSpacing: -0.5 }
            Text { text: wp.custom ? "Ustawione w Zdjęciach" : "Jasna w dzień, ciemna przy ciemnym motywie"; color: Qt.rgba(1, 1, 1, 0.9); font.family: Theme.font; font.pixelSize: 12 }
        }
    }

    Section {
        title: "Tapety Aster"
        Item {
            width: parent.width; height: grid.height + 32
            Grid {
                id: grid
                x: 16; y: 16
                columns: 4
                spacing: 14
                Repeater {
                    model: wp.walls
                    delegate: Column {
                        id: w
                        required property var modelData
                        readonly property bool chosen: Config.wallpaper === modelData.id
                        spacing: 7
                        Item {
                            width: (grid.parent.width - 32 - 3 * 14) / 4; height: Math.round(width * 0.625)
                            Rectangle {
                                anchors.fill: parent; anchors.margins: -4
                                radius: 14
                                color: "transparent"
                                border.width: 3; border.color: Theme.accent
                                opacity: w.chosen ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 160 } }
                            }
                            Rounded {
                                anchors.fill: parent
                                radius: 10
                                source: wp.src(w.modelData.id, Theme.dark ? "dark" : "light")
                                scale: wArea.pressed ? 0.96 : 1
                                Behavior on scale { NumberAnimation { duration: 100 } }
                            }
                            MouseArea { id: wArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Config.wallpaper = w.modelData.id }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: w.modelData.name
                            color: w.chosen ? Theme.text : Theme.text2
                            font.family: Theme.font; font.pixelSize: 12; font.weight: w.chosen ? Font.Medium : Font.Normal
                        }
                    }
                }
            }
        }
    }

    // Obraz przycięty do zaokrąglonych rogów
    component Rounded: Item {
        id: rd
        property url source
        property real radius: 12
        Image {
            id: img
            anchors.fill: parent
            source: rd.source
            sourceSize: Qt.size(640, 400)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: GraphicsInfo.api === GraphicsInfo.Software
        }
        Rectangle { id: mask; anchors.fill: parent; radius: rd.radius; visible: false; layer.enabled: true }
        MultiEffect {
            anchors.fill: parent
            source: img
            maskEnabled: true
            maskSource: mask
            visible: GraphicsInfo.api !== GraphicsInfo.Software
        }
    }
}
