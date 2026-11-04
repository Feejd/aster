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
            { id: "wifi", name: "Wi‑Fi i sieć", icon: "wifi", colors: ["#5AB4FF", "#2563EB"], keys: "internet sieć ethernet kabel hasło router vpn dns hotspot udostępnianie" },
            { id: "bluetooth", name: "Bluetooth", icon: "bluetooth", colors: ["#60A5FA", "#1D4ED8"], keys: "słuchawki mysz klawiatura głośnik parowanie" }
        ],
        [
            { id: "notifications", name: "Powiadomienia", icon: "bell", colors: ["#FF8A8A", "#E11D48"], keys: "nie przeszkadzać skupienie dnd programy dymki" },
            { id: "sound", name: "Dźwięk", icon: "volume", colors: ["#F9A8D4", "#DB2777"], keys: "głośność głośniki słuchawki mikrofon wyjście wejście programy" }
        ],
        [
            { id: "general", name: "Ogólne", icon: "gear", colors: ["#A3A9B5", "#4B5262"], keys: "informacje o komputerze wersja aktualizacje dysk pamięć procesor nazwa komputera" },
            { id: "storage", name: "Pamięć", icon: "drive", colors: ["#93C5FD", "#3B82F6"], keys: "dysk miejsce magazyn pliki tymczasowe kosz porządkowanie zajęte wolne pendrive foldery" },
            { id: "appearance", name: "Wygląd", icon: "contrast", colors: ["#52525B", "#18181B"], keys: "ciemny jasny motyw kolor akcent tryb" },
            { id: "wallpaper", name: "Tapeta", icon: "image", colors: ["#67E8F9", "#0891B2"], keys: "tło pulpit obraz" },
            { id: "desktop", name: "Pulpit i okna", icon: "desktop", colors: ["#8EA2FF", "#5B5BD6"], keys: "zegar widżety okna przyciąganie narożniki animacje pulpity minimalizowanie" },
            { id: "display", name: "Ekran", icon: "sun", colors: ["#7DD3FC", "#2563EB"], keys: "nocne światło rozdzielczość skalowanie monitor jasność odświeżanie obrót" },
            { id: "power", name: "Zasilanie i bateria", icon: "battery", colors: ["#86EFAC", "#16A34A"], keys: "bateria usypianie wygaszanie pokrywa oszczędzanie wydajność" }
        ],
        [
            { id: "mouse", name: "Mysz i touchpad", icon: "mouse", colors: ["#CBD5E1", "#64748B"], keys: "kursor przewijanie szybkość stukanie leworęczny" },
            { id: "keyboard", name: "Klawiatura", icon: "keyboard", colors: ["#CBD5E1", "#475569"], keys: "układ język polski programisty skróty powtarzanie num lock" },
            { id: "printers", name: "Drukarki", icon: "printer", colors: ["#94A3B8", "#475569"], keys: "drukowanie skaner strona testowa" }
        ],
        [
            { id: "datetime", name: "Data i czas", icon: "clock", colors: ["#FDBA74", "#EA580C"], keys: "godzina strefa czasowa zegar" },
            { id: "language", name: "Język i region", icon: "translate", colors: ["#7DD3FC", "#0284C7"], keys: "język formaty waluta data liczby" },
            { id: "apps", name: "Aplikacje", icon: "apps", colors: ["#C4B5FD", "#7C3AED"], keys: "domyślne przeglądarka poczta autostart uruchamiane po zalogowaniu" },
            { id: "accessibility", name: "Dostępność", icon: "access", colors: ["#60A5FA", "#1E40AF"], keys: "lupa czytnik ekranu kursor animacje lepkie klawisze" },
            { id: "assistant", name: "Aster Intelligence", icon: "sparkle", colors: ["#7DD3FC", "#2563EB"], keys: "asystent intelligence ai sztuczna inteligencja czat model chmura lokalny deepseek openai claude gemini mistral ollama klucz api terminal" },
            { id: "privacy", name: "Prywatność i bezpieczeństwo", icon: "shield", colors: ["#94A3B8", "#334155"], keys: "blokada ekranu hasło zapora historia" }
        ]
    ]
    // Działy bez miejsca na pasku bocznym (otwierane z innych stron)
    readonly property var hidden: [
        { id: "shortcuts", name: "Skróty klawiszowe", icon: "keyboard", colors: ["#A3A9B5", "#4B5262"], keys: "skróty klawisze" }
    ]
    readonly property var all: {
        const out = [{ id: "account", name: "Konto", icon: "user", colors: ["#7C9BFF", "#8B5CF6"], keys: "użytkownik hasło zdjęcie imię inne osoby konta" }];
        for (let i = 0; i < groups.length; ++i)
            for (let j = 0; j < groups[i].length; ++j)
                out.push(groups[i][j]);
        return out.concat(hidden);
    }
    readonly property string accountName: Accounts.realName || System.fullName
    readonly property var current: all.find(p => p.id === page) || all[0]

    function go(id) {
        if (id === page) return;
        page = id;
        pageAnim.restart();
    }
    function toast(text) { toastBox.text = text; toastBox.shown = true; toastTimer.restart(); }
    Connections { target: System; function onMessage(text) { win.toast(text); } }
    Connections { target: Displays; function onMessage(text) { win.toast(text); } }
    Connections { target: Accounts; function onMessage(text) { win.toast(text); } }
    Connections { target: DateTime; function onMessage(text) { win.toast(text); } }
    Connections { target: Shortcuts; function onMessage(text) { win.toast(text); } }
    Connections { target: Printers; function onMessage(text) { win.toast(text); } }
    Connections { target: Storage; function onMessage(text) { win.toast(text); } }
    Connections { target: Assistant; function onMessage(text) { win.toast(text); } }

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
                            clip: true
                            Text { anchors.centerIn: parent; visible: avatarImg.status !== Image.Ready; text: win.accountName.charAt(0).toUpperCase(); color: "white"; font.family: Theme.font; font.pixelSize: 19; font.weight: Font.DemiBold }
                            Image { id: avatarImg; anchors.fill: parent; source: Accounts.iconUrl; fillMode: Image.PreserveAspectCrop; sourceSize: Qt.size(88, 88); visible: status === Image.Ready }
                        }
                        Column {
                            anchors.left: avatar.right; anchors.leftMargin: 11
                            anchors.right: parent.right; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text { width: parent.width; text: win.accountName; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
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
                Connections {
                    target: pageLoader.item
                    ignoreUnknownSignals: true
                    function onNavigate(id) { win.go(id); }
                }
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
