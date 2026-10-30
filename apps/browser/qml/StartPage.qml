pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Browser

// Strona nowej karty: ulubione jako kafelki i ostatnio odwiedzane strony.
// Tło jest przezroczyste — widać szkło okna (rozmyty pulpit).
Item {
    id: sp
    property var favorites: []
    property var recents: []
    signal open(string url)
    signal remove(string url)

    readonly property real greetingHour: new Date().getHours()

    Flickable {
        anchors.fill: parent
        contentHeight: col.height + 80
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: col
            width: Math.min(760, sp.width - 80)
            x: (sp.width - width) / 2
            y: Math.max(40, sp.height * 0.10)
            spacing: 18

            Text {
                text: sp.greetingHour < 5 ? "Dobranoc" : sp.greetingHour < 12 ? "Dzień dobry" : sp.greetingHour < 18 ? "Miłego popołudnia" : "Dobry wieczór"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 30; font.weight: Font.DemiBold
                font.letterSpacing: -0.5
            }

            Text {
                text: "Ulubione"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Flow {
                width: col.width
                spacing: 6
                Repeater {
                    model: sp.favorites
                    delegate: Item {
                        id: fav
                        required property var modelData
                        required property int index
                        width: 104; height: 112
                        opacity: 0
                        Component.onCompleted: favIn.start()
                        NumberAnimation { id: favIn; target: fav; property: "opacity"; to: 1; duration: 180; easing.type: Easing.OutQuad }
                        Rectangle {
                            anchors.fill: parent
                            radius: 14
                            color: favArea.containsMouse ? Theme.hover : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        Rectangle {
                            id: tileBox
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 10
                            width: 64; height: 64; radius: 16
                            color: Theme.surface
                            border.width: 1; border.color: Theme.line
                            scale: favArea.pressed ? 0.94 : 1
                            Behavior on scale { NumberAnimation { duration: 100 } }
                            Image {
                                id: ico
                                anchors.centerIn: parent
                                width: 32; height: 32
                                source: Urls.favicon(fav.modelData.url)
                                sourceSize: Qt.size(64, 64)
                                asynchronous: true
                                smooth: true
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: ico.status !== Image.Ready
                                text: (fav.modelData.title || Urls.host(fav.modelData.url)).charAt(0).toUpperCase()
                                color: Theme.accentText
                                font.family: Theme.font; font.pixelSize: 26; font.weight: Font.DemiBold
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 82
                            width: parent.width - 10
                            horizontalAlignment: Text.AlignHCenter
                            text: fav.modelData.title || Urls.host(fav.modelData.url)
                            elide: Text.ElideRight
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 12
                        }
                        // Usuń z ulubionych (krzyżyk pod kursorem)
                        Rectangle {
                            x: tileBox.x + tileBox.width - 14; y: tileBox.y - 6
                            width: 20; height: 20; radius: 10
                            visible: favArea.containsMouse
                            color: Theme.surface
                            border.width: 1; border.color: Theme.line
                            Icon { anchors.centerIn: parent; d: Icons.close; size: 10; stroke: 2; color: Theme.text2 }
                            MouseArea { anchors.fill: parent; onClicked: sp.remove(fav.modelData.url) }
                            z: 2
                        }
                        MouseArea { id: favArea; anchors.fill: parent; hoverEnabled: true; onClicked: sp.open(fav.modelData.url) }
                    }
                }
            }

            Item { width: 1; height: 6; visible: sp.recents.length > 0 }
            Text {
                visible: sp.recents.length > 0
                text: "Ostatnio odwiedzane"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Grid {
                columns: 2
                visible: sp.recents.length > 0
                Repeater {
                    model: sp.recents
                    delegate: Rectangle {
                        id: rec
                        required property var modelData
                        width: col.width / 2; height: 52
                        radius: 12
                        color: recArea.containsMouse ? Theme.hover : "transparent"
                        Rectangle {
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32; radius: 9
                            color: Theme.surface
                            border.width: 1; border.color: Theme.line
                            Image {
                                anchors.centerIn: parent
                                width: 18; height: 18
                                source: Urls.favicon(rec.modelData.url)
                                sourceSize: Qt.size(36, 36)
                                asynchronous: true
                            }
                        }
                        Column {
                            x: 54; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 64
                            Text { width: parent.width; text: rec.modelData.title || Urls.host(rec.modelData.url); elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                            Text { width: parent.width; text: Urls.host(rec.modelData.url); elide: Text.ElideRight; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
                        }
                        MouseArea { id: recArea; anchors.fill: parent; hoverEnabled: true; onClicked: sp.open(rec.modelData.url) }
                    }
                }
            }
        }
    }
}
