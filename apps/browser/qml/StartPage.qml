pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Browser

// Strona nowej karty: powitanie, duże pole wyszukiwania, ulubione i najczęściej odwiedzane strony.
// W oknie prywatnym zamiast listy odwiedzanych — krótko, co tryb prywatny robi, a czego nie.
Item {
    id: sp
    property bool privateMode: false
    signal open(string url, bool background)

    readonly property int hour: new Date().getHours()
    readonly property var topSites: { Browser.historyRevision; return privateMode ? [] : Browser.topSites(8); }

    Flickable {
        anchors.fill: parent
        contentHeight: col.height + 80
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: col
            width: Math.min(780, sp.width - 80)
            x: (sp.width - width) / 2
            y: Math.max(36, sp.height * 0.12)
            spacing: 22

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: sp.privateMode ? "Okno prywatne"
                      : sp.hour < 5 ? "Dobranoc" : sp.hour < 12 ? "Dzień dobry" : sp.hour < 18 ? "Miłego popołudnia" : "Dobry wieczór"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 34; font.weight: Font.DemiBold; font.letterSpacing: -1
            }

            // Duże pole wyszukiwania
            Rectangle {
                width: parent.width; height: 54
                radius: 27
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.045)
                border.width: query.activeFocus ? 2 : 1
                border.color: query.activeFocus ? Theme.accent : Theme.line
                Behavior on border.color { ColorAnimation { duration: 120 } }
                Icon { x: 20; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 19; color: Theme.text2 }
                TextInput {
                    id: query
                    x: 52; width: parent.width - 72
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text
                    selectionColor: Theme.accentSoft
                    font.family: Theme.font; font.pixelSize: 16
                    clip: true
                    Keys.onReturnPressed: if (text.trim()) sp.open(Browser.fixup(text), false)
                    Keys.onEnterPressed: if (text.trim()) sp.open(Browser.fixup(text), false)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !query.text
                        text: "Szukaj w " + Browser.searchName + " albo wpisz adres"
                        color: Theme.text2; font: query.font
                    }
                }
            }

            // ——— Ulubione ———
            Column {
                width: parent.width
                spacing: 8
                visible: Browser.bookmarks.length > 0
                Text { text: "Ulubione"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold; leftPadding: 4 }
                Flow {
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: Browser.bookmarks
                        delegate: SiteTile {
                            removable: true
                            onRemove: Browser.removeBookmark(url)
                        }
                    }
                }
            }

            // ——— Często odwiedzane ———
            Column {
                width: parent.width
                spacing: 8
                visible: sp.topSites.length > 0
                Text { text: "Często odwiedzane"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold; leftPadding: 4 }
                Flow {
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: sp.topSites
                        delegate: SiteTile {}
                    }
                }
            }

            // ——— Tryb prywatny ———
            Rectangle {
                visible: sp.privateMode
                width: parent.width
                height: privCol.implicitHeight + 40
                radius: 20
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.04)
                border.width: 1; border.color: Theme.line
                Column {
                    id: privCol
                    x: 22; y: 20
                    width: parent.width - 44
                    spacing: 10
                    Text {
                        width: parent.width; wrapMode: Text.Wrap
                        text: "Po zamknięciu tego okna przeglądarka zapomni odwiedzone strony, ciasteczka, dane logowania na stronach i wpisy w formularzach."
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 14; lineHeight: 1.2
                    }
                    Text {
                        width: parent.width; wrapMode: Text.Wrap
                        text: "Pobrane pliki i dodane ulubione zostaną. Tryb prywatny nie ukrywa Cię przed stronami, pracodawcą ani dostawcą internetu."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.2
                    }
                }
            }
        }
    }

    // Kafelek witryny: ikona na zaokrąglonym kwadracie i nazwa pod spodem
    component SiteTile: Item {
        id: tile
        required property var modelData
        readonly property string url: modelData.url
        readonly property string title: modelData.title || Urls.host(modelData.url)
        property bool removable: false
        signal remove()
        width: 108; height: 108

        Rectangle {
            anchors.fill: parent
            radius: 16
            color: area.containsMouse ? Theme.hover : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Rectangle {
            id: box
            anchors.horizontalCenter: parent.horizontalCenter
            y: 12
            width: 58; height: 58; radius: 18
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.07) : "white"
            border.width: 1; border.color: Theme.line
            scale: area.pressed ? 0.94 : 1
            Behavior on scale { NumberAnimation { duration: 100 } }
            Image {
                id: ico
                anchors.centerIn: parent
                width: 28; height: 28
                source: Urls.favicon(tile.url)
                sourceSize: Qt.size(64, 64)
                asynchronous: true
                smooth: true
            }
            Text {
                anchors.centerIn: parent
                visible: ico.status !== Image.Ready
                text: tile.title.charAt(0).toUpperCase()
                color: Theme.accentText
                font.family: Theme.font; font.pixelSize: 24; font.weight: Font.DemiBold
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 80
            width: parent.width - 12
            horizontalAlignment: Text.AlignHCenter
            text: tile.title
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 12
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: (m) => sp.open(tile.url, m.button === Qt.MiddleButton || (m.modifiers & Qt.ControlModifier))
        }
        // Usuń z ulubionych
        Rectangle {
            x: box.x + box.width - 14; y: box.y - 6
            width: 22; height: 22; radius: 11
            visible: tile.removable && (area.containsMouse || rmArea.containsMouse)
            color: Theme.surface
            border.width: 1; border.color: Theme.line
            Icon { anchors.centerIn: parent; d: Icons.close; size: 10; stroke: 2; color: Theme.text2 }
            MouseArea { id: rmArea; anchors.fill: parent; hoverEnabled: true; onClicked: tile.remove() }
        }
    }
}
