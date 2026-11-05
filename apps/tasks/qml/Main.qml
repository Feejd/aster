pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Aster.Ui
import Aster.Tasks

// Menedżer zadań Aster (Ctrl+Shift+Esc) — dla przesiadających się z Windows:
//  • Procesy: programy (z ich procesami), procesy w tle i systemu; „Zakończ zadanie”, szczegóły,
//  • Wydajność: procesor, pamięć, dyski i sieć z wykresami z ostatniej minuty,
//  • Porty: kto nasłuchuje na którym porcie („port 3000 zajęty”) — z możliwością zakończenia,
//  • Programy po zalogowaniu — w Ustawieniach → Aplikacje.
Window {
    id: win
    property string page: "processes"

    width: 980 + 2 * m
    height: 640 + 2 * m
    minimumWidth: 760 + 2 * m
    minimumHeight: 440 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: "Menedżer zadań"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 24

    readonly property var pages: [
        { id: "processes", name: "Procesy", icon: "list", colors: ["#7FA7FF", "#3E63DD"] },
        { id: "performance", name: "Wydajność", icon: "activity", colors: ["#7EE8A8", "#0E8F5A"] },
        { id: "ports", name: "Porty", icon: "globe", colors: ["#C4B5FD", "#7C3AED"] }
    ]
    readonly property var current: pages.find(p => p.id === page) || pages[0]
    property alias selected: procPage.selected
    property var confirm: null                  // { text, detail, button, action }
    property var details: null                  // Monitor.processes.details(key)

    function go(id) {
        if (id === page) return;
        page = id;
        pageAnim.restart();
    }
    function plural(n, one, few, many) {
        const t = n % 100, u = n % 10;
        return n + " " + (n === 1 ? one : (u >= 2 && u <= 4 && (t < 12 || t > 14)) ? few : many);
    }
    function toast(text) { toastBox.text = text; toastBox.shown = true; toastTimer.restart(); }
    Connections { target: Monitor.processes; function onMessage(text) { win.toast(text); } }

    // „Zakończ zadanie”: ważne dla sesji i cudze procesy — najpierw pytanie
    function askEnd(key, force) {
        const info = Monitor.processes.info(key);
        if (!info.key) return;
        const go = () => { Monitor.processes.end(key, force); win.details = null; };
        if (info.critical)
            confirm = { text: "Zakończyć „" + info.name + "”?",
                        detail: "To ważna część systemu. Po jej zakończeniu ekran może zgasnąć albo nastąpi wylogowanie — niezapisana praca w otwartych programach przepadnie.",
                        button: "Zakończ mimo to", action: go };
        else if (info.foreign)
            confirm = { text: "Zakończyć „" + info.name + "”?",
                        detail: "Ten proces należy do systemu, więc do jego zakończenia potrzebne jest hasło administratora.",
                        button: "Zakończ", action: go };
        else
            go();
    }
    function showDetails(key) { details = Monitor.processes.details(key); }
    Connections {
        target: Monitor
        function onUpdated() { if (win.details) win.details = Monitor.processes.details(win.details.key) || null; }
    }

    function showRowMenu(key, x, y) {
        const group = key.startsWith("g:");
        const items = [];
        if (group) {
            const info = Monitor.processes.info(key);
            if (info.count > 1) {
                items.push({ label: info.expanded ? "Zwiń" : "Rozwiń", icon: "chevronDown", action: "toggle" });
                items.push({ separator: true });
            }
        }
        items.push({ label: "Zakończ zadanie", icon: "close", shortcut: "Del", action: "end", danger: true });
        items.push({ label: "Zakończ natychmiast", icon: "bolt", action: "kill", danger: true });
        items.push({ separator: true });
        items.push({ label: "Otwórz lokalizację pliku", icon: "folder", action: "location" });
        items.push({ label: "Właściwości", icon: "info", shortcut: "Enter", action: "details" });
        menu.key = key;
        const p = procPage.mapToItem(frame, x, y);
        menu.openAt(p.x, p.y, items);
    }
    function showMainMenu() {
        const p = menuButton.mapToItem(frame, menuButton.width, menuButton.height + 6);
        const speed = Monitor.interval;
        menu.key = "";
        menu.openAt(p.x - 250, p.y, [
            { label: "Odśwież teraz", icon: "reload", shortcut: "F5", action: "refresh" },
            { label: speed === 0 ? "Wznów odświeżanie" : "Wstrzymaj odświeżanie", icon: speed === 0 ? "play" : "pause", shortcut: "Spacja", action: "pause" },
            { separator: true },
            { label: "Odświeżanie: szybko (0,5 s)", icon: speed === 500 ? "check" : "", action: "speed:500" },
            { label: "Odświeżanie: normalnie (1 s)", icon: speed === 1000 ? "check" : "", action: "speed:1000" },
            { label: "Odświeżanie: wolno (4 s)", icon: speed === 4000 ? "check" : "", action: "speed:4000" },
            { separator: true },
            { label: "Programy po zalogowaniu…", icon: "clock", action: "startup" }
        ]);
    }
    property int lastInterval: 1000
    function togglePause() {
        if (Monitor.interval === 0) Monitor.interval = lastInterval || 1000;
        else { lastInterval = Monitor.interval; Monitor.interval = 0; }
        toast(Monitor.interval === 0 ? "Odświeżanie wstrzymane" : "Odświeżanie wznowione");
    }
    function runMenuAction(a) {
        const key = menu.key;
        if (a === "toggle") Monitor.processes.toggle(key);
        else if (a === "end") askEnd(key, false);
        else if (a === "kill") askEnd(key, true);
        else if (a === "location") Monitor.processes.openLocation(key);
        else if (a === "details") showDetails(key);
        else if (a === "refresh") Monitor.refreshNow();
        else if (a === "pause") togglePause();
        else if (a.startsWith("speed:")) Monitor.interval = Number(a.slice(6));
        else if (a === "startup") Monitor.launch("aster-settings", ["apps"]);
    }

    // Do testów (ASTER_OPEN): details | menu | confirm | performance | find:tekst
    function testOpen(what) {
        const first = Monitor.processes.keyAt(1);
        if (what === "details") showDetails(first);
        else if (what === "menu") { selected = first; showRowMenu(first, 300, 120); }
        else if (what === "confirm") askEnd("p:1", false);
        else if (what === "performance") go("performance");
        else if (what === "cores") { go("performance"); perfLoader.item.perCore = true; }
        else if (what.startsWith("find:")) search.text = what.slice(5);
    }

    Shortcut { sequence: "Ctrl+F"; onActivated: { win.go("processes"); search.forceActiveFocus(); } }
    Shortcut { sequence: "F5"; onActivated: Monitor.refreshNow() }
    Shortcut { sequence: "Ctrl+1"; onActivated: win.go("processes") }
    Shortcut { sequence: "Ctrl+2"; onActivated: win.go("performance") }
    Shortcut { sequence: "Ctrl+W"; onActivated: win.close() }
    Shortcut { sequence: "Esc"; enabled: !!win.details || !!win.confirm; onActivated: { win.confirm = null; win.details = null; } }
    Shortcut { sequence: "Space"; enabled: !search.activeFocus; onActivated: win.togglePause() }

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
            width: 214; height: parent.height
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }

            Column {
                x: 10; y: 58
                width: parent.width - 20
                spacing: 2
                Repeater {
                    model: win.pages
                    delegate: NavItem {
                        required property var modelData
                        item: modelData
                    }
                }
                Item { width: 1; height: 10 }
                NavItem {
                    item: ({ id: "startup", name: "Po zalogowaniu", icon: "clock", colors: ["#FDBA74", "#EA580C"] })
                    external: true
                    onActivated: Monitor.launch("aster-settings", ["apps"])
                }
            }

            // Na dole: obciążenie w skrócie
            Column {
                x: 18; anchors.bottom: parent.bottom; anchors.bottomMargin: 18
                width: parent.width - 36
                spacing: 10
                Repeater {
                    model: [["Procesor", Monitor.cpu, "#5B8CFF"], ["Pamięć", Monitor.memPercent, "#B072FF"]]
                    delegate: Column {
                        id: mini
                        required property var modelData
                        width: parent.width
                        spacing: 5
                        Item {
                            width: parent.width; height: 15
                            Text { text: mini.modelData[0]; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                            Text { anchors.right: parent.right; text: Monitor.percent(mini.modelData[1]); color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium; font.features: { "tnum": 1 } }
                        }
                        Rectangle {
                            width: parent.width; height: 5; radius: 2.5
                            color: Theme.fill
                            Rectangle {
                                width: Math.max(height, parent.width * Math.min(1, mini.modelData[1] / 100)); height: parent.height; radius: 2.5
                                color: mini.modelData[2]
                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
                Text {
                    visible: Monitor.interval === 0
                    text: "Odświeżanie wstrzymane"
                    color: Theme.accentText; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
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
                    id: pageTitle
                    x: 28; anchors.verticalCenter: parent.verticalCenter
                    text: win.current.name
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4
                }

                Row {
                    anchors.right: winButtons.left; anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // Szukaj procesu
                    Rectangle {
                        visible: win.page === "processes" || win.page === "ports"
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(240, topBar.width - pageTitle.width - 420); height: 34; radius: 10
                        color: Theme.fill
                        border.width: search.activeFocus ? 1.5 : 0
                        border.color: Theme.accent
                        Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 15; color: Theme.text2 }
                        TextInput {
                            id: search
                            x: 32; width: parent.width - 42
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                            selectionColor: Theme.accentSoft
                            clip: true
                            onTextChanged: Monitor.processes.filter = text
                            Keys.onEscapePressed: { text = ""; win.page === "ports" ? portsLoader.item.focusList() : procPage.focusList(); }
                            Keys.onDownPressed: win.page === "ports" ? portsLoader.item.focusList() : procPage.focusList()
                            Text { visible: !search.text; text: win.page === "ports" ? "Port albo program" : "Szukaj procesu"; color: Theme.text2; font: search.font }
                        }
                    }
                    HoverButton {
                        id: endButton
                        visible: win.page === "processes"
                        anchors.verticalCenter: parent.verticalCenter
                        enabled: win.selected !== ""
                        width: endRow.implicitWidth + 26; height: 34; radius: 17
                        baseColor: enabled ? "#E5484D" : Theme.fill
                        color: hovered && enabled ? "#D93B40" : baseColor
                        opacity: enabled ? 1 : 0.6
                        onClicked: win.askEnd(win.selected, false)
                        Row {
                            id: endRow
                            anchors.centerIn: parent
                            spacing: 6
                            Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.close; size: 13; stroke: 2.2; color: endButton.enabled ? "white" : Theme.text2 }
                            Text { text: "Zakończ zadanie"; color: endButton.enabled ? "white" : Theme.text2; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                        }
                    }
                    ToolBtn {
                        visible: win.page === "processes"
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "info"
                        enabled: win.selected !== ""
                        onClicked: win.showDetails(win.selected)
                    }
                    ToolBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: Monitor.interval === 0 ? "play" : "pause"
                        onClicked: win.togglePause()
                    }
                    ToolBtn { id: menuButton; anchors.verticalCenter: parent.verticalCenter; icon: "more"; onClicked: win.showMainMenu() }
                }
                WindowButtons {
                    id: winButtons
                    window: win
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Item {
                id: pageHolder
                y: topBar.height
                width: parent.width; height: parent.height - y
                property real shift: 0
                transform: Translate { x: pageHolder.shift }
                ProcessesPage {
                    id: procPage
                    anchors.fill: parent
                    visible: win.page === "processes"
                    onMenuRequested: (key, x, y) => win.showRowMenu(key, x, y)
                    onDetailsRequested: (key) => win.showDetails(key)
                    onEndRequested: (key, force) => win.askEnd(key, force)
                }
                Loader {
                    id: perfLoader
                    anchors.fill: parent
                    active: win.page === "performance"
                    sourceComponent: PerformancePage {}
                }
                Loader {
                    id: portsLoader
                    anchors.fill: parent
                    active: win.page === "ports"
                    sourceComponent: PortsPage {
                        filter: search.text
                        onEndRequested: (key, force) => win.askEnd(key, force)
                    }
                }
            }
            ParallelAnimation {
                id: pageAnim
                NumberAnimation { target: pageHolder; property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutQuad }
                NumberAnimation { target: pageHolder; property: "shift"; from: 14; to: 0; duration: 240; easing.type: Easing.OutQuint }
            }

            // Komunikat na dole
            Rectangle {
                id: toastBox
                property bool shown: false
                property alias text: toastText.text
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - (shown ? height + 22 : 0)
                opacity: shown ? 1 : 0
                z: 20
                width: toastText.implicitWidth + 36; height: 40; radius: 20
                color: Theme.dark ? "#ECEEF3" : "#1E2027"
                Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
                Behavior on opacity { NumberAnimation { duration: 160 } }
                Text { id: toastText; anchors.centerIn: parent; color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                Timer { id: toastTimer; interval: 3000; onTriggered: toastBox.shown = false }
            }
        }

        ContextMenu {
            id: menu
            property string key
            onTriggered: (a) => win.runMenuAction(a)
        }

        // ——— Właściwości procesu ———
        Item {
            anchors.fill: parent
            visible: !!win.details
            z: 150
            Rectangle { anchors.fill: parent; radius: win.r; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.25) }
            MouseArea { anchors.fill: parent; onClicked: win.details = null }
            RectangularShadow { anchors.fill: sheet; radius: sheet.radius; blur: 40; offset.y: 14; color: Theme.shadow }
            Rectangle {
                id: sheet
                readonly property var d: win.details || ({})
                anchors.centerIn: parent
                width: 470; height: sheetCol.implicitHeight + 44
                radius: 22
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                MouseArea { anchors.fill: parent }
                Column {
                    id: sheetCol
                    x: 24; y: 22; width: parent.width - 48
                    spacing: 0
                    Row {
                        spacing: 14
                        Item {
                            width: 48; height: 48
                            AppIcon { visible: !!sheet.d.desktopId; anchors.fill: parent; size: 48; desktopId: sheet.d.desktopId || ""; source: sheet.d.iconName || "" }
                            Rectangle {
                                visible: !sheet.d.desktopId
                                anchors.fill: parent; radius: 14
                                color: Theme.fill
                                Icon { anchors.centerIn: parent; d: Icons.apps; size: 24; stroke: 1.8; color: Theme.text2 }
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Text {
                                width: sheetCol.width - 62; elide: Text.ElideRight
                                text: sheet.d.name || ""
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                            }
                            Text {
                                text: (sheet.d.process || "") + " · PID " + (sheet.d.pid || "") + (sheet.d.processes > 1 ? " · " + win.plural(sheet.d.processes, "proces", "procesy", "procesów") : "")
                                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                            }
                        }
                    }
                    Item { width: 1; height: 18 }
                    Repeater {
                        model: [
                            ["Stan", sheet.d.state],
                            ["Użytkownik", sheet.d.user],
                            ["Uruchomiono", sheet.d.started],
                            ["Procesor", Monitor.percent(sheet.d.cpu || 0)],
                            ["Pamięć", Monitor.bytes(sheet.d.mem || 0)],
                            ["Dysk", Monitor.rate(sheet.d.disk || 0)],
                            ["Wątki", String(sheet.d.threads || "")],
                            ["Plik programu", sheet.d.exe || "—"]
                        ]
                        delegate: Item {
                            id: dr
                            required property var modelData
                            width: sheetCol.width; height: Math.max(30, valueText.implicitHeight + 12)
                            Rectangle { width: parent.width; height: 1; color: Theme.line }
                            Text { y: 8; text: dr.modelData[0]; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                            TextEdit {
                                id: valueText
                                x: 130; y: 8; width: parent.width - 130
                                readOnly: true; selectByMouse: true
                                wrapMode: TextEdit.WrapAnywhere
                                text: dr.modelData[1] || ""
                                color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                                font.family: Theme.font; font.pixelSize: 13
                            }
                        }
                    }
                    Rectangle { width: parent.width; height: 1; color: Theme.line }
                    Item { width: 1; height: 12 }
                    Text { text: "Polecenie"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                    Item { width: 1; height: 6 }
                    Rectangle {
                        width: parent.width; height: Math.min(86, cmdText.implicitHeight + 16); radius: 10
                        color: Theme.fill
                        clip: true
                        TextEdit {
                            id: cmdText
                            x: 10; y: 8; width: parent.width - 20
                            readOnly: true; selectByMouse: true
                            wrapMode: TextEdit.WrapAnywhere
                            text: sheet.d.command || ""
                            color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                            font.family: "JetBrains Mono"; font.pixelSize: 12
                        }
                    }
                    Item { width: 1; height: 20 }
                    Item {
                        width: parent.width; height: 34
                        Pill { text: "Otwórz lokalizację"; onClicked: Monitor.processes.openLocation(sheet.d.key) }
                        Row {
                            anchors.right: parent.right
                            spacing: 8
                            Pill { text: "Zakończ zadanie"; danger: true; onClicked: win.askEnd(sheet.d.key, false) }
                            Pill { text: "Zamknij"; primary: true; onClicked: win.details = null }
                        }
                    }
                }
            }
        }

        // ——— Pytanie przed zakończeniem ———
        Item {
            anchors.fill: parent
            visible: !!win.confirm
            z: 200
            Rectangle { anchors.fill: parent; radius: win.r; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.25) }
            MouseArea { anchors.fill: parent; onClicked: win.confirm = null }
            RectangularShadow { anchors.fill: dlg; radius: dlg.radius; blur: 40; offset.y: 14; color: Theme.shadow }
            Rectangle {
                id: dlg
                anchors.centerIn: parent
                width: 400; height: dlgCol.implicitHeight + 44
                radius: 22
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                MouseArea { anchors.fill: parent }
                Column {
                    id: dlgCol
                    x: 24; y: 22; width: parent.width - 48
                    spacing: 8
                    Text { width: parent.width; wrapMode: Text.Wrap; text: win.confirm ? win.confirm.text : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold }
                    Text { width: parent.width; wrapMode: Text.Wrap; text: win.confirm ? win.confirm.detail : ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.15 }
                    Item { width: 1; height: 10 }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Pill { text: "Anuluj"; onClicked: win.confirm = null }
                        Pill {
                            text: win.confirm ? win.confirm.button : ""
                            danger: true
                            onClicked: { const a = win.confirm.action; win.confirm = null; a(); }
                        }
                    }
                }
            }
        }
    }

    component Pill: HoverButton {
        id: pill
        property string text
        property bool danger: false
        property bool primary: false
        width: pillText.implicitWidth + 30; height: 34; radius: 17
        baseColor: danger ? "#E5484D" : primary ? Theme.accent : Theme.fill
        color: hovered ? (danger ? "#D93B40" : primary ? Qt.darker(Theme.accent, 1.1) : Theme.hover) : baseColor
        Text { id: pillText; anchors.centerIn: parent; text: pill.text; color: pill.danger || pill.primary ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
    }

    // Pozycja paska bocznego: plakietka i nazwa; wybrana — w kolorze akcentu
    component NavItem: Rectangle {
        id: nav
        property var item
        property bool external: false
        signal activated()
        readonly property bool active: !external && win.page === item.id
        width: parent ? parent.width : 0; height: 34
        radius: 9
        color: active ? Theme.accent : (navArea.containsMouse ? Theme.hover : "transparent")
        Rectangle {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; radius: 7
            gradient: Gradient {
                GradientStop { position: 0; color: nav.item.colors[0] }
                GradientStop { position: 1; color: nav.item.colors[1] }
            }
            Icon { anchors.centerIn: parent; d: Icons[nav.item.icon] || ""; size: 14; stroke: 2; color: "white" }
        }
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
            onClicked: nav.external ? nav.activated() : win.go(nav.item.id)
        }
    }
}
