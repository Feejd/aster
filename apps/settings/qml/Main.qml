pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Aster.Ui
import Aster.Settings

// Ustawienia Aster (jak Ustawienia systemowe w macOS): pasek boczny z kontem, wyszukiwarką
// i kolorowymi działami, po prawej strona wybranego działu złożona z kart z wierszami.
// Rzadziej potrzebne rzeczy otwierają odpowiedni moduł Ustawień KDE.
Window {
    id: win
    property string startPage: "general"

    width: 1000 + 2 * m
    height: 680 + 2 * m
    minimumWidth: 820 + 2 * m
    minimumHeight: 520 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: "Ustawienia"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: maxed ? 0 : 24

    property string page: startPage
    readonly property var groups: [
        [
            { id: "wifi", name: "Wi‑Fi i sieć", icon: "wifi", colors: ["#5AB4FF", "#2563EB"], keys: "internet sieć ethernet kabel hasło router" },
            { id: "bluetooth", name: "Bluetooth", icon: "bluetooth", colors: ["#60A5FA", "#1D4ED8"], keys: "słuchawki mysz klawiatura głośnik parowanie" }
        ],
        [
            { id: "notifications", name: "Powiadomienia", icon: "bell", colors: ["#FF8A8A", "#E11D48"], keys: "nie przeszkadzać skupienie dnd" },
            { id: "sound", name: "Dźwięk", icon: "volume", colors: ["#F9A8D4", "#DB2777"], keys: "głośność głośniki słuchawki mikrofon wyjście wejście" }
        ],
        [
            { id: "general", name: "Ogólne", icon: "gear", colors: ["#A3A9B5", "#4B5262"], keys: "informacje o komputerze wersja aktualizacje data czas język dysk pamięć procesor" },
            { id: "appearance", name: "Wygląd", icon: "contrast", colors: ["#52525B", "#18181B"], keys: "ciemny jasny motyw kolor akcent tryb" },
            { id: "wallpaper", name: "Tapeta", icon: "image", colors: ["#67E8F9", "#0891B2"], keys: "tło pulpit obraz" },
            { id: "desktop", name: "Pulpit i dok", icon: "desktop", colors: ["#8EA2FF", "#5B5BD6"], keys: "zegar bateria dok skróty narożniki" },
            { id: "display", name: "Ekran", icon: "sun", colors: ["#7DD3FC", "#2563EB"], keys: "nocne światło rozdzielczość skalowanie monitor jasność" }
        ]
    ]
    readonly property var all: {
        const out = [{ id: "account", name: "Konto", icon: "user", colors: ["#7C9BFF", "#8B5CF6"], keys: "użytkownik hasło zdjęcie" }];
        for (let i = 0; i < groups.length; ++i)
            for (let j = 0; j < groups[i].length; ++j)
                out.push(groups[i][j]);
        return out;
    }
    readonly property var current: all.find(p => p.id === page) || all[0]

    function go(id) {
        if (id === page) return;
        page = id;
        pageAnim.restart();
    }
    function toast(text) { toastBox.text = text; toastBox.shown = true; toastTimer.restart(); }
    Connections { target: System; function onMessage(text) { win.toast(text); } }

    // ——— Okno ———
    function updateEffects() {
        WindowEffects.setBlur(win, Qt.rect(m, m, frame.width, frame.height), r);
        WindowEffects.setInputRegion(win, Qt.rect(Math.max(0, m - 6), Math.max(0, m - 6), frame.width + (maxed ? 0 : 12), frame.height + (maxed ? 0 : 12)));
    }
    Component.onCompleted: effectsTimer.restart()
    onWidthChanged: effectsTimer.restart()
    onHeightChanged: effectsTimer.restart()
    onMaxedChanged: effectsTimer.restart()
    Timer { id: effectsTimer; interval: 16; onTriggered: win.updateEffects() }

    WindowShadow { window: win; frame: frame; radius: win.r; visible: !win.maxed }
    ResizeHandles { window: win; frame: frame; margin: win.m }

    Rectangle {
        id: frame
        x: win.m; y: win.m
        width: win.width - 2 * win.m
        height: win.height - 2 * win.m
        radius: win.r
        color: Theme.windowGlass
        border.width: win.maxed ? 0 : 1
        border.color: Theme.edge
        WindowSheen { window: win; radius: win.r }
        clip: true

        // ——— Pasek boczny ———
        Item {
            id: side
            width: 262; height: parent.height
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }

            Rectangle {
                id: searchBox
                x: 14; y: 16
                width: parent.width - 28; height: 34; radius: 10
                color: Theme.fill
                border.width: field.activeFocus ? 1.5 : 0
                border.color: Theme.accent
                Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 15; color: Theme.text2 }
                TextInput {
                    id: field
                    x: 32; width: parent.width - 42
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                    selectionColor: Theme.accentSoft
                    clip: true
                    Keys.onEscapePressed: text = ""
                    Keys.onReturnPressed: if (results.length) { win.go(results[0].id); text = ""; }
                    readonly property var results: {
                        const q = text.trim().toLowerCase();
                        return q ? win.all.filter(p => (p.name + " " + p.keys).toLowerCase().indexOf(q) >= 0) : [];
                    }
                    Text { visible: !field.text; text: "Szukaj"; color: Theme.text2; font: field.font }
                }
            }

            Flickable {
                x: 10; y: searchBox.y + searchBox.height + 12
                width: parent.width - 20; height: parent.height - y - 10
                contentHeight: navCol.height
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                Column {
                    id: navCol
                    width: parent.width
                    spacing: 2

                    // Konto
                    Rectangle {
                        visible: !field.text
                        width: parent.width; height: 62
                        radius: 12
                        color: win.page === "account" ? Theme.accentSoft : (accArea.containsMouse ? Theme.hover : "transparent")
                        Rectangle {
                            id: avatar
                            x: 8; anchors.verticalCenter: parent.verticalCenter
                            width: 44; height: 44; radius: 22
                            gradient: Gradient {
                                GradientStop { position: 0; color: "#7C9BFF" }
                                GradientStop { position: 1; color: "#8B5CF6" }
                            }
                            Text { anchors.centerIn: parent; text: System.fullName.charAt(0).toUpperCase(); color: "white"; font.family: Theme.font; font.pixelSize: 19; font.weight: Font.DemiBold }
                        }
                        Column {
                            anchors.left: avatar.right; anchors.leftMargin: 11
                            anchors.right: parent.right; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text { width: parent.width; text: System.fullName; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                            Text { text: "Konto Aster"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                        }
                        MouseArea { id: accArea; anchors.fill: parent; hoverEnabled: true; onClicked: win.go("account") }
                    }

                    Repeater {
                        model: field.text ? [field.results] : win.groups
                        delegate: Column {
                            id: grp
                            required property var modelData
                            width: navCol.width
                            spacing: 2
                            Item { width: 1; height: 10 }
                            Repeater {
                                model: grp.modelData
                                delegate: NavItem {
                                    required property var modelData
                                    item: modelData
                                }
                            }
                        }
                    }
                    Text {
                        visible: field.text !== "" && field.results.length === 0
                        topPadding: 16; leftPadding: 10
                        text: "Brak wyników"
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                    }

                    Item { width: 1; height: 10; visible: !field.text }
                    NavItem {
                        visible: !field.text
                        item: ({ id: "", name: "Więcej ustawień", icon: "sliders", colors: ["#CBD5E1", "#64748B"] })
                        external: true
                        onActivated: System.openKcm("")
                    }
                }
            }
        }

        // ——— Strona ———
        GlassPane {
            id: main
            x: side.width
            width: parent.width - side.width
            height: parent.height
            topRightRadius: win.r; bottomRightRadius: win.r

            Item {
                id: topBar
                width: parent.width; height: 64
                z: 5
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }
                Text {
                    x: 32; anchors.verticalCenter: parent.verticalCenter
                    text: win.current.name
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4
                }
                WindowButtons {
                    window: win
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Loader {
                id: pageLoader
                x: 0; y: topBar.height
                width: parent.width; height: parent.height - y
                source: Qt.resolvedUrl(win.page.charAt(0).toUpperCase() + win.page.slice(1) + "Page.qml")
                property real shift: 0
                transform: Translate { x: pageLoader.shift }
            }
            ParallelAnimation {
                id: pageAnim
                NumberAnimation { target: pageLoader; property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutQuad }
                NumberAnimation { target: pageLoader; property: "shift"; from: 14; to: 0; duration: 240; easing.type: Easing.OutQuint }
            }

            // Komunikat na dole
            Rectangle {
                id: toastBox
                property bool shown: false
                property alias text: toastText.text
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - (shown ? height + 22 : 0)
                opacity: shown ? 1 : 0
                width: toastText.implicitWidth + 36; height: 40; radius: 20
                color: Theme.dark ? "#ECEEF3" : "#1E2027"
                Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
                Behavior on opacity { NumberAnimation { duration: 160 } }
                Text { id: toastText; anchors.centerIn: parent; color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                Timer { id: toastTimer; interval: 3500; onTriggered: toastBox.shown = false }
            }
        }
    }

    // Pozycja paska bocznego: plakietka i nazwa; wybrana — w kolorze akcentu (jak w macOS)
    component NavItem: Rectangle {
        id: nav
        property var item
        property bool external: false
        signal activated()
        readonly property bool active: !external && win.page === item.id
        width: navCol.width; height: 34
        radius: 9
        color: active ? Theme.accent : (navArea.containsMouse ? Theme.hover : "transparent")
        Badge { x: 8; anchors.verticalCenter: parent.verticalCenter; size: 24; icon: nav.item.icon; colors: nav.item.colors }
        Text {
            x: 42; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 50
            text: nav.item.name
            elide: Text.ElideRight
            color: nav.active ? "white" : Theme.text
            font.family: Theme.font; font.pixelSize: 13; font.weight: nav.active ? Font.Medium : Font.Normal
        }
        Icon {
            visible: nav.external
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            d: Icons.chevronRight; size: 13; stroke: 2; color: Theme.text2
        }
        MouseArea {
            id: navArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (nav.external) { nav.activated(); return; }
                win.go(nav.item.id);
                field.text = "";
            }
        }
    }
}
