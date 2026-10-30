import QtQuick
import "Icons.js" as I

// Ustawienia. „Wygląd” działa naprawdę (motyw, kolor akcentu, tapeta, przezroczystość, zegar),
// a „Dźwięk” steruje tym samym co centrum sterowania. Pozostałe strony to makiety.
AppWindow {
    id: sw
    property var sys                 // główne okno systemu (stan: dark, accent, wallpaperVariant…)
    property string page: "look"
    sidebarWidth: 240

    readonly property var pages: [
        { id: "look", name: "Wygląd", icon: "image", color: "#B45CF0" },
        { id: "wifi", name: "Wi-Fi", icon: "wifi", color: "#3478F6" },
        { id: "bt", name: "Bluetooth", icon: "bluetooth", color: "#2F6BF5" },
        { id: "sound", name: "Dźwięk", icon: "volume", color: "#F0524F" },
        { id: "ai", name: "Asystent", icon: "sparkle", color: "#6A5CF0" },
        { id: "updates", name: "Aktualizacje", icon: "download", color: "#2FAE66" },
        { id: "about", name: "O systemie", icon: "aster", color: "#535A68" }
    ]
    readonly property var current: pages.find(p => p.id === page)

    // ——— Pasek boczny ———
    Column {
        x: 14; y: 16
        width: 240 - 28
        spacing: 2
        Text { text: "Ustawienia"; color: sw.t.text; font.pixelSize: 20; font.weight: Font.Bold; leftPadding: 8; bottomPadding: 18; topPadding: 4 }
        Repeater {
            model: sw.pages
            delegate: Rectangle {
                id: nav
                required property var modelData
                readonly property bool active: sw.page === modelData.id
                width: parent.width; height: 40; radius: 11
                color: active ? sw.t.accentSoft : (navArea.containsMouse ? sw.t.hover : "transparent")
                Behavior on color { ColorAnimation { duration: 120 } }
                Rectangle {
                    id: navIcon
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28; radius: 8
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(nav.modelData.color, 1.25) }
                        GradientStop { position: 1; color: nav.modelData.color }
                    }
                    Icon { anchors.centerIn: parent; d: I[nav.modelData.icon]; size: 15; stroke: 2; color: "white" }
                }
                Text { anchors.left: navIcon.right; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: nav.modelData.name; color: sw.t.text; font.pixelSize: 14; font.weight: nav.active ? Font.DemiBold : Font.Normal }
                MouseArea { id: navArea; anchors.fill: parent; hoverEnabled: true; onClicked: sw.page = nav.modelData.id }
            }
        }
    }

    // ——— Strona ———
    Item {
        id: pageArea
        x: 240; y: 0
        width: sw.width - 240; height: sw.height

        Text { x: 32; y: 22; text: sw.current.name; color: sw.t.text; font.pixelSize: 26; font.weight: Font.Bold }

        Flickable {
            id: flick
            x: 32; y: 76
            width: parent.width - 64; height: parent.height - 92
            contentHeight: loader.item ? loader.item.implicitHeight + 24 : 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Loader {
                id: loader
                width: flick.width
                sourceComponent: ({ look: lookPage, wifi: wifiPage, bt: btPage, sound: soundPage, ai: aiPage, updates: updatesPage, about: aboutPage })[sw.page]
                onLoaded: { item.opacity = 0; fadeIn.restart(); flick.contentY = 0; }
                NumberAnimation { id: fadeIn; target: loader.item; property: "opacity"; to: 1; duration: 180 }
            }
        }
    }

    // ——— Wspólne elementy stron ———
    component Card: Rectangle {
        default property alias body: cardCol.data
        property string title: ""
        width: parent ? parent.width : 400
        implicitHeight: cardCol.implicitHeight + 32
        height: implicitHeight
        radius: 16
        color: sw.t.fill
        Column {
            id: cardCol
            x: 18; y: 16
            width: parent.width - 36
            spacing: 12
        }
    }
    component Label: Text { color: sw.t.text; font.pixelSize: 14; font.weight: Font.DemiBold }
    component Hint: Text { color: sw.t.text2; font.pixelSize: 13; wrapMode: Text.Wrap }
    component RowItem: Item {
        property string label
        property string detail: ""
        property alias trailing: trail.data
        width: parent.width; height: 40
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text { text: parent.parent.label; color: sw.t.text; font.pixelSize: 14 }
            Text { visible: !!parent.parent.detail; text: parent.parent.detail; color: sw.t.text2; font.pixelSize: 12 }
        }
        Item { id: trail; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: childrenRect.width; height: childrenRect.height }
    }

    // ——— Wygląd ———
    Component {
        id: lookPage
        Column {
            spacing: 16
            Card {
                Label { text: "Motyw" }
                Row {
                    spacing: 14
                    Repeater {
                        model: [{ dark: false, name: "Jasny" }, { dark: true, name: "Ciemny" }]
                        delegate: Column {
                            id: themeOpt
                            required property var modelData
                            readonly property bool selected: sw.sys.dark === modelData.dark
                            spacing: 8
                            Rectangle {
                                width: 160; height: 100; radius: 14
                                color: "transparent"
                                border.width: themeOpt.selected ? 2.5 : 1
                                border.color: themeOpt.selected ? sw.t.accent : sw.t.line
                                Wallpaper {
                                    anchors.fill: parent; anchors.margins: 4
                                    variant: sw.sys.wallpaperVariant
                                    dark: themeOpt.modelData.dark
                                    thumb: true
                                    clip: true
                                }
                                Rectangle {
                                    x: 18; y: 18; width: 90; height: 56; radius: 8
                                    color: themeOpt.modelData.dark ? Qt.rgba(0.14, 0.14, 0.17, 0.85) : Qt.rgba(1, 1, 1, 0.85)
                                    Rectangle { x: 8; y: 9; width: 40; height: 5; radius: 2.5; color: themeOpt.modelData.dark ? "#ECEEF3" : "#16181D"; opacity: 0.8 }
                                    Rectangle { x: 8; y: 20; width: 64; height: 4; radius: 2; color: themeOpt.modelData.dark ? "#A2A9B6" : "#5B6270"; opacity: 0.6 }
                                    Rectangle { x: 8; y: 36; width: 28; height: 12; radius: 6; color: sw.t.accent }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: if (!themeOpt.selected) { const p = mapToItem(null, width / 2, height / 2); sw.sys.toggleDark(p.x, p.y); }
                                }
                            }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: themeOpt.modelData.name; color: sw.t.text; font.pixelSize: 13; font.weight: themeOpt.selected ? Font.DemiBold : Font.Normal }
                        }
                    }
                }
            }
            Card {
                Label { text: "Kolor akcentu" }
                Row {
                    spacing: 12
                    Repeater {
                        model: ["#3456E8", "#7B5CF0", "#D9468F", "#F0524F", "#EE8A1F", "#2FAE66", "#139FB5"]
                        delegate: Item {
                            id: sw1
                            required property string modelData
                            readonly property bool selected: Qt.colorEqual(sw.sys.accent, modelData)
                            width: 34; height: 34
                            Rectangle {
                                anchors.centerIn: parent
                                width: 34; height: 34; radius: 17
                                color: "transparent"
                                border.width: sw1.selected ? 2.5 : 0
                                border.color: sw1.modelData
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: sw1.selected ? 24 : 28; height: width; radius: width / 2
                                color: sw1.modelData
                                Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                            }
                            MouseArea { anchors.fill: parent; onClicked: sw.sys.accent = sw1.modelData }
                        }
                    }
                }
            }
            Card {
                Label { text: "Tapeta" }
                Row {
                    spacing: 14
                    Repeater {
                        model: [{ id: "szczyty", name: "Szczyty" }, { id: "jezioro", name: "Jezioro" }, { id: "swit", name: "Fale" }, { id: "laguna", name: "Laguna" }]
                        delegate: Column {
                            id: wpOpt
                            required property var modelData
                            readonly property bool selected: sw.sys.wallpaperVariant === modelData.id
                            spacing: 8
                            Rectangle {
                                width: 128; height: 80; radius: 14
                                color: "transparent"
                                border.width: wpOpt.selected ? 2.5 : 1
                                border.color: wpOpt.selected ? sw.t.accent : sw.t.line
                                Wallpaper { anchors.fill: parent; anchors.margins: 4; variant: wpOpt.modelData.id; dark: sw.sys.dark; thumb: true; clip: true }
                                MouseArea { anchors.fill: parent; onClicked: sw.sys.wallpaperVariant = wpOpt.modelData.id }
                            }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: wpOpt.modelData.name; color: sw.t.text; font.pixelSize: 13; font.weight: wpOpt.selected ? Font.DemiBold : Font.Normal }
                        }
                    }
                }
            }
            Card {
                Label { text: "Przezroczystość" }
                Hint { width: parent.width; text: "Ile tapety prześwituje przez panele i okna." }
                SoftSlider {
                    t: sw.t
                    width: parent.width
                    icon: I.sparkle
                    value: (0.95 - sw.sys.glassLevel) / 0.45
                    onMoved: (v) => sw.sys.glassLevel = 0.95 - v * 0.45
                }
                Item {
                    width: parent.width; height: 16
                    Text { text: "Bardziej jednolite"; color: sw.t.text2; font.pixelSize: 12 }
                    Text { anchors.right: parent.right; text: "Więcej szkła"; color: sw.t.text2; font.pixelSize: 12 }
                }
            }
            Card {
                RowItem {
                    label: "Zegar na pulpicie"
                    detail: "Duża godzina i data, gdy nic nie zasłania pulpitu"
                    trailing: Toggle { t: sw.t; checked: sw.sys.showDesktopClock; onToggled: (on) => sw.sys.showDesktopClock = on }
                }
            }
        }
    }

    // ——— Wi-Fi ———
    Component {
        id: wifiPage
        Column {
            spacing: 16
            Card {
                RowItem { label: "Wi-Fi"; detail: "Połączono z: Sieć domowa"; trailing: Toggle { t: sw.t; checked: true } }
            }
            Card {
                Label { text: "Dostępne sieci" }
                Repeater {
                    model: [{ n: "Sieć domowa", s: "Połączono · zabezpieczona", on: true }, { n: "Sąsiad_5G", s: "Zabezpieczona" }, { n: "Kawiarnia", s: "Otwarta" }]
                    delegate: RowItem {
                        required property var modelData
                        label: modelData.n; detail: modelData.s
                        trailing: Icon { d: modelData.on ? I.check : I.wifi; color: modelData.on ? sw.t.accentText : sw.t.text2 }
                    }
                }
            }
        }
    }

    // ——— Bluetooth ———
    Component {
        id: btPage
        Column {
            spacing: 16
            Card { RowItem { label: "Bluetooth"; detail: "Widoczny jako: Mój komputer"; trailing: Toggle { t: sw.t; checked: true } } }
            Card {
                Label { text: "Urządzenia" }
                Repeater {
                    model: [{ n: "Słuchawki", s: "Połączone · bateria 70%" }, { n: "Myszka", s: "Połączona" }, { n: "Głośnik", s: "Niepołączony" }]
                    delegate: RowItem { required property var modelData; label: modelData.n; detail: modelData.s }
                }
            }
        }
    }

    // ——— Dźwięk ———
    Component {
        id: soundPage
        Column {
            spacing: 16
            Card {
                Label { text: "Głośność" }
                SoftSlider { t: sw.t; width: parent.width; icon: I.volumeLow; value: sw.sys.volume; onMoved: (v) => sw.sys.volume = v }
            }
            Card {
                Label { text: "Wyjście" }
                Repeater {
                    model: ["Głośniki laptopa", "Słuchawki Bluetooth"]
                    delegate: Rectangle {
                        id: outOpt
                        required property string modelData
                        readonly property bool selected: sw.sys.output === modelData
                        width: parent.width; height: 44; radius: 12
                        color: selected ? sw.t.accentSoft : (outArea.containsMouse ? sw.t.hover : "transparent")
                        Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; d: outOpt.modelData.indexOf("Słuchawki") === 0 ? I.headphones : I.volume; color: sw.t.text }
                        Text { x: 42; anchors.verticalCenter: parent.verticalCenter; text: outOpt.modelData; color: sw.t.text; font.pixelSize: 14 }
                        Icon { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; visible: outOpt.selected; d: I.check; color: sw.t.accentText }
                        MouseArea { id: outArea; anchors.fill: parent; hoverEnabled: true; onClicked: sw.sys.output = outOpt.modelData }
                    }
                }
            }
        }
    }

    // ——— Asystent ———
    Component {
        id: aiPage
        Column {
            spacing: 16
            Card {
                RowItem { label: "Asystent"; detail: "Otwierany klawiszem AI albo ⌥A"; trailing: Toggle { t: sw.t; checked: true } }
            }
            Card {
                Label { text: "Prywatność" }
                Hint { width: parent.width; text: "Asystent widzi tylko to, co mu pokażesz. Nie robi zrzutów ekranu w tle i nie zapisuje historii bez Twojej zgody. Każda zmiana w systemie wymaga kliknięcia „Zatwierdź”." }
            }
        }
    }

    // ——— Aktualizacje ———
    Component {
        id: updatesPage
        Column {
            id: up
            spacing: 16
            property int stage: 0     // 0 — aktualny, 1 — sprawdzanie, 2 — sprawdzono
            Card {
                Row {
                    spacing: 14
                    Rectangle {
                        width: 52; height: 52; radius: 26
                        color: Qt.rgba(47 / 255, 174 / 255, 102 / 255, 0.16)
                        Icon {
                            anchors.centerIn: parent
                            d: up.stage === 1 ? I.undo : I.check
                            size: 24; stroke: 2.2; color: "#2FAE66"
                            RotationAnimation on rotation { running: up.stage === 1; from: 0; to: -360; duration: 900; loops: Animation.Infinite }
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text { text: up.stage === 1 ? "Sprawdzam…" : "System jest aktualny"; color: sw.t.text; font.pixelSize: 16; font.weight: Font.DemiBold }
                        Text { text: up.stage === 2 ? "Sprawdzono przed chwilą — brak nowych wersji" : "Aktualizacje instalują się same w tle"; color: sw.t.text2; font.pixelSize: 13 }
                    }
                }
                Rectangle {
                    width: chk.implicitWidth + 32; height: 36; radius: 18
                    color: sw.t.accent
                    opacity: up.stage === 1 ? 0.5 : 1
                    Text { id: chk; anchors.centerIn: parent; text: "Sprawdź teraz"; color: "white"; font.pixelSize: 13; font.weight: Font.DemiBold }
                    MouseArea { anchors.fill: parent; enabled: up.stage !== 1; onClicked: { up.stage = 1; doneTimer.start(); } }
                    Timer { id: doneTimer; interval: 1600; onTriggered: up.stage = 2 }
                }
            }
            Card {
                Label { text: "Poprzednie wersje" }
                Hint { width: parent.width; text: "Jeśli po aktualizacji coś przestanie działać, wybierz wcześniejszą wersję — wróci po ponownym uruchomieniu." }
                RowItem {
                    label: "Aster 1.0.1"; detail: "zainstalowana 21 paź"
                    trailing: Rectangle {
                        width: rb.implicitWidth + 24; height: 32; radius: 16
                        color: sw.t.surface; border.width: 1; border.color: sw.t.line
                        Text { id: rb; anchors.centerIn: parent; text: "Przywróć"; color: sw.t.text; font.pixelSize: 13; font.weight: Font.Medium }
                    }
                }
            }
        }
    }

    // ——— O systemie ———
    Component {
        id: aboutPage
        Column {
            spacing: 16
            Card {
                Row {
                    spacing: 16
                    Rectangle {
                        width: 64; height: 64; radius: 18
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.lighter(sw.t.accent, 1.3) }
                            GradientStop { position: 1; color: sw.t.accent }
                        }
                        Icon { anchors.centerIn: parent; d: I.aster; size: 34; stroke: 2.6; color: "white" }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: "Aster"; color: sw.t.text; font.pixelSize: 24; font.weight: Font.Bold }
                        Text { text: "Wersja 1.0 · prototyp interfejsu"; color: sw.t.text2; font.pixelSize: 13 }
                    }
                }
            }
            Card {
                RowItem { label: "Nazwa urządzenia"; trailing: Text { text: "Mój komputer"; color: sw.t.text2; font.pixelSize: 14 } }
                RowItem { label: "Dysk"; trailing: Text { text: "238 GB wolne z 512 GB"; color: sw.t.text2; font.pixelSize: 14 } }
                RowItem { label: "Pulpit"; trailing: Text { text: "Aster Shell (Qt " + Qt.version + ")"; color: sw.t.text2; font.pixelSize: 14 } }
            }
        }
    }
}
