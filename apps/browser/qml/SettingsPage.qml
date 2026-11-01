pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Browser

// Ustawienia przeglądarki (aster://settings): wyszukiwarka, uruchamianie, wygląd,
// prywatność z czyszczeniem danych, pobrane i przeglądarka domyślna
Item {
    id: sp
    signal open(string url, bool background)

    Flickable {
        anchors.fill: parent
        contentHeight: col.height + 60
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: col
            width: Math.min(760, sp.width - 64)
            x: (sp.width - width) / 2
            spacing: 26

            PageHeader { title: "Ustawienia"; width: sp.width; x: -col.x }

            // ——— Przeglądarka domyślna ———
            Card {
                visible: !Browser.isDefault
                Row {
                    x: 18; height: 72
                    spacing: 14
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40; height: 40; radius: 12
                        color: Theme.accentSoft
                        Icon { anchors.centerIn: parent; d: Icons.globe; size: 20; color: Theme.accentText }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: "Przeglądarka nie jest domyślna"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Text { text: "Linki z innych programów otwierają się gdzie indziej"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                    }
                }
                PillButton {
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    primary: true
                    text: "Ustaw jako domyślną"
                    onClicked: Browser.makeDefault()
                }
                height: 72
            }

            // ——— Wyszukiwarka ———
            Section {
                title: "Wyszukiwarka"
                footer: "Używana w pasku adresu i na stronie nowej karty"
                Repeater {
                    model: Browser.searchEngines
                    delegate: Choice {
                        required property var modelData
                        required property int index
                        label: modelData.name
                        checked: Browser.searchEngine === modelData.id
                        last: index === Browser.searchEngines.length - 1
                        onPicked: Browser.searchEngine = modelData.id
                    }
                }
            }

            // ——— Uruchamianie i wygląd ———
            Section {
                title: "Uruchamianie i wygląd"
                Switch {
                    label: "Przywracaj otwarte karty"
                    detail: "Po ponownym uruchomieniu wracają okna i karty z poprzedniej sesji"
                    checked: Browser.restoreSession
                    onToggled: Browser.restoreSession = !Browser.restoreSession
                }
                Switch {
                    label: "Pasek ulubionych"
                    detail: "Ulubione strony pod paskiem adresu"
                    checked: Browser.showFavoritesBar
                    onToggled: Browser.showFavoritesBar = !Browser.showFavoritesBar
                }
                Switch {
                    label: "Ciemne strony"
                    detail: "Przyciemnia jasne strony, które nie mają własnego ciemnego wyglądu"
                    checked: Browser.forceDark
                    last: true
                    onToggled: Browser.forceDark = !Browser.forceDark
                }
            }

            // ——— Prywatność ———
            Section {
                id: privacy
                title: "Prywatność"
                Switch {
                    label: "Blokuj śledzenie i reklamy"
                    detail: "Zapytania do znanych serwerów reklam i analityki (Google Ads, Meta Pixel, Criteo, Gemius…) nie wychodzą z komputera"
                    checked: Browser.blockTrackers
                    last: true
                    onToggled: Browser.blockTrackers = !Browser.blockTrackers
                }
            }

            Section {
                title: "Wyczyść dane przeglądania"
                Item {
                    width: parent.width; height: 58
                    Text { x: 18; anchors.verticalCenter: parent.verticalCenter; text: "Zakres czasu"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Repeater {
                            model: [["Godzina", 3600000], ["Dzień", 86400000], ["Tydzień", 604800000], ["Wszystko", 0]]
                            delegate: Rectangle {
                                id: rangeBtn
                                required property var modelData
                                readonly property bool on: clear.range === modelData[1]
                                width: rangeText.implicitWidth + 24; height: 32; radius: 16
                                color: on ? Theme.accent : (rangeArea.containsMouse ? Theme.hover : Theme.fill)
                                Text { id: rangeText; anchors.centerIn: parent; text: rangeBtn.modelData[0]; color: rangeBtn.on ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                                MouseArea { id: rangeArea; anchors.fill: parent; hoverEnabled: true; onClicked: clear.range = rangeBtn.modelData[1] }
                            }
                        }
                    }
                    Rectangle { anchors.bottom: parent.bottom; x: 18; width: parent.width - 18; height: 1; color: Theme.line }
                }
                Check { id: cHistory; label: "Historia przeglądania"; checked: true }
                Check { id: cCookies; label: "Ciasteczka i dane witryn"; detail: "Wylogowuje z większości stron"; checked: false; enabled: clear.range === 0 }
                Check { id: cCache; label: "Obrazy i pliki w pamięci podręcznej"; checked: true; enabled: clear.range === 0 }
                Check { id: cDownloads; label: "Lista pobranych plików"; detail: "Same pliki zostają na dysku"; checked: false; last: true }
                Item {
                    id: clear
                    property real range: 3600000
                    property bool done: false
                    width: parent.width; height: 64
                    Text {
                        x: 18; anchors.verticalCenter: parent.verticalCenter
                        visible: clear.done
                        text: "Wyczyszczono"
                        color: Theme.accentText; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                    }
                    Timer { id: doneTimer; interval: 2500; onTriggered: clear.done = false }
                    PillButton {
                        anchors.right: parent.right; anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        primary: true
                        text: "Wyczyść dane"
                        onClicked: {
                            Browser.clearData(cHistory.checked, cCookies.checked && cCookies.enabled, cCache.checked && cCache.enabled, cDownloads.checked,
                                              clear.range > 0 ? Date.now() - clear.range : 0);
                            clear.done = true;
                            doneTimer.restart();
                        }
                    }
                }
            }

            // ——— Pobrane ———
            Section {
                title: "Pobrane"
                Item {
                    width: parent.width; height: 62
                    Column {
                        x: 18; anchors.verticalCenter: parent.verticalCenter
                        Text { text: "Zapisuj pliki w"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 }
                        Text { text: Browser.downloadDir; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    PillButton {
                        anchors.right: parent.right; anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Otwórz"
                        onClicked: Qt.openUrlExternally("file://" + Browser.downloadDir)
                    }
                }
            }

            // ——— O przeglądarce ———
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Przeglądarka Aster " + Browser.version + " · silnik Chromium " + Browser.engineVersion
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
        }
    }

    // ——— Elementy ———
    component Card: Rectangle {
        width: parent ? parent.width : 0
        radius: 16
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.03)
        border.width: 1; border.color: Theme.line
    }

    component Section: Column {
        id: sec
        property string title
        property string footer
        default property alias rows: body.data
        width: parent ? parent.width : 0
        spacing: 8
        Text { text: sec.title; leftPadding: 4; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
        Card {
            height: body.height
            Column { id: body; width: parent.width }
        }
        Text {
            visible: sec.footer !== ""
            text: sec.footer; leftPadding: 4
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
        }
    }

    component Switch: Item {
        id: sw
        property string label
        property string detail
        property bool checked
        property bool last: false
        signal toggled()
        width: parent ? parent.width : 0
        height: Math.max(58, swCol.implicitHeight + 24)
        Column {
            id: swCol
            x: 18; width: parent.width - 100
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text { text: sw.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 }
            Text { visible: sw.detail !== ""; width: parent.width; wrapMode: Text.Wrap; text: sw.detail; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.1 }
        }
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            width: 44; height: 26; radius: 13
            color: sw.checked ? Theme.accent : (Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.14))
            Behavior on color { ColorAnimation { duration: 150 } }
            Rectangle {
                x: sw.checked ? parent.width - width - 3 : 3
                anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20; radius: 10
                color: "white"
                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
        Rectangle { visible: !sw.last; anchors.bottom: parent.bottom; x: 18; width: parent.width - 18; height: 1; color: Theme.line }
    }

    component Choice: Item {
        id: ch
        property string label
        property bool checked
        property bool last: false
        signal picked()
        width: parent ? parent.width : 0
        height: 48
        Rectangle {
            x: 18; anchors.verticalCenter: parent.verticalCenter
            width: 20; height: 20; radius: 10
            color: ch.checked ? Theme.accent : "transparent"
            border.width: ch.checked ? 0 : 1.5
            border.color: Theme.text2
            Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white"; visible: ch.checked }
        }
        Text { x: 50; anchors.verticalCenter: parent.verticalCenter; text: ch.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ch.picked() }
        Rectangle { visible: !ch.last; anchors.bottom: parent.bottom; x: 50; width: parent.width - 50; height: 1; color: Theme.line }
    }

    component Check: Item {
        id: ck
        property string label
        property string detail
        property bool checked
        property bool last: false
        width: parent ? parent.width : 0
        height: detail ? 60 : 48
        opacity: enabled ? 1 : 0.4
        Rectangle {
            x: 18; anchors.verticalCenter: parent.verticalCenter
            width: 20; height: 20; radius: 6
            color: ck.checked && ck.enabled ? Theme.accent : "transparent"
            border.width: ck.checked && ck.enabled ? 0 : 1.5
            border.color: Theme.text2
            Icon { anchors.centerIn: parent; visible: ck.checked && ck.enabled; d: Icons.check; size: 13; stroke: 2.4; color: "white" }
        }
        Column {
            x: 50; anchors.verticalCenter: parent.verticalCenter
            Text { text: ck.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 }
            Text { visible: ck.detail !== ""; text: ck.detail; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ck.checked = !ck.checked }
        Rectangle { visible: !ck.last; anchors.bottom: parent.bottom; x: 50; width: parent.width - 50; height: 1; color: Theme.line }
    }
}
