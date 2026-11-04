pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Aster.Ui
import Aster.Store
import "Facts.js" as Facts

// Sklep Aster: nie witryna z banerami, tylko przewodnik. Strony idą w stos (wstecz wraca tam, gdzie byłeś),
// u góry pięć miejsc: Start, Gry, Katalog, Z Windowsa i Twój komputer. Kolejka instalacji jest zawsze widoczna.
Window {
    id: win
    property string openApp
    property string openRoute
    property int openScroll: 0      // do zrzutów: przewinięcie strony

    width: 1200 + 2 * m
    height: 800 + 2 * m
    minimumWidth: 820 + 2 * m
    minimumHeight: 560 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: "Sklep"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: maxed ? 0 : 24

    property var stack: [{ page: "home" }]
    readonly property var route: stack[stack.length - 1]
    readonly property string section: stack[0].page

    function saveScroll() {
        if (pageLoader.item && pageLoader.item.flick !== undefined)
            route.y = pageLoader.item.flick.contentY;
    }
    function go(page, arg) {
        saveScroll();
        // Ta sama strona: bez dublowania wpisu w historii
        if (route.page === page && JSON.stringify(route.arg) === JSON.stringify(arg)) return;
        stack = stack.concat([{ page: page, arg: arg }]);
    }
    function tab(page, arg) { saveScroll(); stack = [{ page: page, arg: arg }]; }
    function back() { if (stack.length > 1) stack = stack.slice(0, -1); }
    function search(q) {
        q = q.trim();
        if (q) go("list", { q: q });
    }

    function follow(routeText) {
        const colon = routeText.indexOf(":");
        const page = colon < 0 ? routeText : routeText.slice(0, colon);
        const rest = colon < 0 ? "" : routeText.slice(colon + 1);
        if (page === "task") go("task", rest);
        else if (page === "windows") tab("switch", rest ? rest.split(",") : undefined);
        else if (page === "catalog") tab("list", { cat: rest || "ai" });
        else if (page === "mine") tab("mine");
        else if (page === "search") search(rest);
        else if (page === "ask") go("list", { q: rest, ask: true });
        else if (page === "app") go("app", rest);
        else if (page === "remove") Store.requestRemoval(rest);
        else if (page === "install") { tab("mine"); Store.install(rest); }
        else if (page === "rollback") { tab("mine"); Flatpak.rollback(rest); }
        else if (page === "uninstall") { tab("mine"); Flatpak.uninstall(rest, false); }
        else if (page === "prune") { tab("mine"); Flatpak.pruneRuntimes(); }
        else if (page === "compare") { Store.compare = rest.split(","); go("compare"); }
    }

    Connections {
        target: Store
        function onRequestOpen(ref) { win.go("app", ref); }
        function onToast(text) { toastText.text = text; toastTimer.restart(); }
        function onRequestRemove(ref) { removeSheet.ask(ref); }
    }

    Component.onCompleted: {
        effectsTimer.restart();
        if (openApp) go("app", openApp);
        if (openRoute) follow(openRoute);
    }
    Timer { running: win.openScroll > 0; interval: 3000; onTriggered: if (pageLoader.item && pageLoader.item.flick) pageLoader.item.flick.contentY = win.openScroll }

    // ——— Okno ———
    function updateEffects() {
        WindowEffects.setBlur(win, Qt.rect(m, m, frame.width, frame.height), r);
        WindowEffects.setInputRegion(win, Qt.rect(Math.max(0, m - 6), Math.max(0, m - 6), frame.width + (maxed ? 0 : 12), frame.height + (maxed ? 0 : 12)));
    }
    onWidthChanged: effectsTimer.restart()
    onHeightChanged: effectsTimer.restart()
    onMaxedChanged: effectsTimer.restart()
    Timer { id: effectsTimer; interval: 16; onTriggered: win.updateEffects() }

    WindowShadow { window: win; frame: frame; radius: win.r; visible: !win.maxed }
    ResizeHandles { window: win; frame: frame; margin: win.m }

    Shortcut { sequences: ["Alt+Left", "Esc"]; onActivated: {
            if (removeSheet.ref) removeSheet.ref = "";
            else if (win.activeFocusItem && win.activeFocusItem.text) win.activeFocusItem.text = "";
            else win.back();
        } }
    Shortcut { sequence: "Ctrl+F"; onActivated: { if (win.route.page === "home" && pageLoader.item) pageLoader.item.focusSearch(); else quickField.forceActiveFocus(); } }

    Rectangle {
        id: frame
        x: win.m; y: win.m
        width: win.width - 2 * win.m
        height: win.height - 2 * win.m
        radius: win.r
        color: Theme.paneGlass
        border.width: win.maxed ? 0 : 1
        border.color: Theme.edge
        clip: true
        WindowSheen { window: win; radius: win.r }

        // ——— Pasek górny ———
        Item {
            id: topBar
            width: parent.width; height: 62
            z: 20
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
            TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }

            Row {
                id: tabs
                x: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                ToolBtn {
                    visible: win.stack.length > 1
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "back"
                    tip: "Wróć"
                    onClicked: win.back()
                }
                TabItem { label: "Start"; active: win.section === "home"; onClicked: win.tab("home") }
                TabItem { label: "Gry"; active: win.section === "list" && !!win.stack[0].arg && win.stack[0].arg.cat === "gry"; onClicked: win.tab("list", { cat: "gry" }) }
                TabItem { label: "Katalog"; active: win.section === "list" && !(win.stack[0].arg && win.stack[0].arg.cat === "gry"); onClicked: win.tab("list", { cat: "ai" }) }
                TabItem { label: "Z Windowsa"; active: win.section === "switch"; onClicked: win.tab("switch") }
                TabItem {
                    label: "Twój komputer"
                    active: win.section === "mine"
                    badge: Flatpak.updates.length + Flatpak.getUpdates.length
                    onClicked: win.tab("mine")
                }
            }

            Row {
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                // Krótkie szukanie, gdy duże zdanie „Chcę…” jest poza widokiem
                Rectangle {
                    visible: win.route.page !== "home" && frame.width > 980
                    anchors.verticalCenter: parent.verticalCenter
                    width: 210; height: 36; radius: 10
                    color: Theme.fill
                    border.width: quickField.activeFocus ? 1.5 : 0
                    border.color: Theme.accent
                    Txt { x: 12; anchors.verticalCenter: parent.verticalCenter; text: "Chcę"; color: Theme.text2; font.pixelSize: 13 }
                    TextInput {
                        id: quickField
                        x: 46; width: parent.width - 56
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                        selectionColor: Theme.accentSoft
                        clip: true
                        Keys.onReturnPressed: { win.search(text); focus = false; }
                        Keys.onEnterPressed: { win.search(text); focus = false; }
                    }
                }
                // Kolejka: zawsze wiadomo, co się dzieje
                Rectangle {
                    id: queuePill
                    visible: Flatpak.activity.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: queueText.implicitWidth + 26; height: 36; radius: 10
                    color: Theme.accentSoft
                    readonly property var job: Flatpak.activity.length ? Flatpak.activity[0] : null
                    Txt {
                        id: queueText
                        anchors.centerIn: parent
                        color: Theme.accentText
                        font.pixelSize: 13; font.weight: Font.Medium
                        text: {
                            const j = queuePill.job;
                            if (!j) return "";
                            const verb = { install: "Instaluję", bundle: "Instaluję", get: "Instaluję", webadd: "Dodaję", uninstall: "Usuwam", webremove: "Usuwam", getremove: "Usuwam",
                                           update: "Aktualizuję", getupdate: "Aktualizuję", rollback: "Przywracam", prune: "Sprzątam" }[j.action] || "";
                            const name = j.appId === "*" ? "wszystko" : j.appId === "porzadki" ? "" : Store.nameOf(j.appId);
                            const pct = j.value > 0 ? " " + Math.round(j.value * 100) + "%" : "";
                            const more = Flatpak.activity.length > 1 ? " + " + (Flatpak.activity.length - 1) : "";
                            return (verb + " " + name).trim() + pct + more;
                        }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.tab("mine") }
                }
                WindowButtons {
                    window: win
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        }

        // ——— Strona ———
        Loader {
            id: pageLoader
            y: topBar.height
            width: parent.width
            height: parent.height - y
            asynchronous: false
            sourceComponent: ({ home: homePage, task: taskPage, switch: switchPage, list: listPage, app: appPage, compare: comparePage, mine: minePage })[win.route.page]
            readonly property var key: win.route
            onKeyChanged: reveal.restart()
            onLoaded: {
                if (item.setRoute) item.setRoute(win.route.arg);
                const y = win.route.y || 0;
                if (y && item.flick) Qt.callLater(() => { if (pageLoader.item && pageLoader.item.flick) pageLoader.item.flick.contentY = y; });
            }
            NumberAnimation { id: reveal; target: pageLoader; property: "opacity"; from: 0.4; to: 1; duration: 130 }
        }
        Component { id: homePage; HomePage { window: win } }
        Component { id: taskPage; TaskPage { window: win } }
        Component { id: switchPage; SwitchPage { window: win } }
        Component { id: listPage; ListPage { window: win } }
        Component { id: appPage; AppPage { window: win } }
        Component { id: comparePage; ComparePage { window: win } }
        Component { id: minePage; MinePage { window: win } }

        // Wiele programów w porównaniu: droga do tabeli z każdej strony
        Rectangle {
            visible: Store.compare.length > 0 && win.route.page !== "compare"
            anchors.left: parent.left; anchors.leftMargin: 20
            anchors.bottom: parent.bottom; anchors.bottomMargin: 18
            width: cmpRow.implicitWidth + 24; height: 46; radius: 13
            color: Theme.surface
            border.width: 1; border.color: Theme.line
            z: 25
            Row {
                id: cmpRow
                anchors.centerIn: parent
                spacing: 6
                Repeater {
                    model: Store.compare
                    delegate: AppGlyph { required property string modelData; ref: modelData; size: 26; anchors.verticalCenter: parent ? parent.verticalCenter : undefined }
                }
                Item { width: 4; height: 1 }
                Txt { anchors.verticalCenter: parent.verticalCenter; text: Store.compare.length < 2 ? "Dodaj drugi program" : "Porównaj"; font.pixelSize: 13; font.weight: Font.Medium; color: Store.compare.length < 2 ? Theme.text2 : Theme.accentText }
                ToolBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "close"; tip: "Wyczyść"
                    onClicked: Store.compare = []
                }
            }
            MouseArea {
                anchors.fill: parent; anchors.rightMargin: 40
                cursorShape: Qt.PointingHandCursor
                onClicked: if (Store.compare.length >= 2) win.go("compare")
            }
        }

        // ——— Komunikat ———
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: toastTimer.running ? 22 : -height - 4
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
            z: 30
            width: Math.min(parent.width - 40, toastText.implicitWidth + 36); height: 44; radius: 12
            color: Theme.text
            Txt {
                id: toastText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 30)
                elide: Text.ElideRight
                color: Theme.surface
                font.pixelSize: 13
            }
        }
        Timer { id: toastTimer; interval: 5000 }

        // ——— Usuwanie: najpierw uczciwie, ile miejsca wróci ———
        Rectangle {
            id: removeSheet
            property string ref: ""
            property bool withData: false
            readonly property var entry: Flatpak.installedApps.find(a => a.id === ref) || null
            readonly property real dataSize: { const u = Flatpak.usage[ref]; return u ? u.data : 0; }
            readonly property real appSize: entry ? entry.size : 0
            // Biblioteki, które zostaną bez użytkownika po usunięciu tego programu
            readonly property real freedRuntime: {
                if (!entry || !entry.runtime) return 0;
                const others = Flatpak.installedApps.filter(a => a.id !== ref && a.runtime === entry.runtime);
                return others.length ? 0 : (Flatpak.runtimes[entry.runtime] || 0);
            }
            function ask(r) {
                withData = false;
                ref = r;
                Flatpak.refreshUsage();
            }
            visible: ref !== ""
            anchors.fill: parent
            z: 40
            color: Qt.rgba(0, 0, 0, 0.45)
            radius: win.r
            MouseArea { anchors.fill: parent; onClicked: removeSheet.ref = "" }
            Rectangle {
                anchors.centerIn: parent
                width: 440; height: sheetCol.implicitHeight + 48; radius: 18
                color: Theme.surface
                MouseArea { anchors.fill: parent }
                Column {
                    id: sheetCol
                    x: 24; y: 24; width: parent.width - 48
                    spacing: 12
                    Txt { width: parent.width; text: removeSheet.ref ? "Usunąć " + Store.nameOf(removeSheet.ref) + "?" : ""; wrapMode: Text.Wrap; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4 }
                    Txt {
                        width: parent.width; wrapMode: Text.Wrap; color: Theme.text2; font.pixelSize: 14; lineHeight: 1.2
                        text: {
                            const back = removeSheet.appSize + (removeSheet.withData ? removeSheet.dataSize : 0);
                            let s = "Wróci " + Facts.size(back) + " miejsca";
                            if (removeSheet.freedRuntime > 0) s += " i kolejne " + Facts.size(removeSheet.freedRuntime) + " po porządkach, bo tych bibliotek nie będzie już używał żaden program";
                            return s + ".";
                        }
                    }
                    Rectangle {
                        visible: removeSheet.dataSize > 0
                        width: parent.width; height: 48; radius: 11
                        color: Theme.fill
                        Rectangle {
                            x: 14; anchors.verticalCenter: parent.verticalCenter
                            width: 20; height: 20; radius: 6
                            color: removeSheet.withData ? Theme.accent : "transparent"
                            border.width: removeSheet.withData ? 0 : 1.5; border.color: Theme.text2
                            Icon { anchors.centerIn: parent; visible: removeSheet.withData; d: Icons.check; size: 13; color: "white" }
                        }
                        Txt { x: 44; anchors.verticalCenter: parent.verticalCenter; text: "Usuń też moje dane z programu (" + Facts.size(removeSheet.dataSize) + ")"; font.pixelSize: 13 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: removeSheet.withData = !removeSheet.withData }
                    }
                    Txt { width: parent.width; visible: removeSheet.dataSize > 0 && !removeSheet.withData; wrapMode: Text.Wrap; color: Theme.text2; font.pixelSize: 12; text: "Twoje dane zostaną. Gdy zainstalujesz program ponownie, wszystko będzie jak było." }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Btn { text: "Zostaw"; onClicked: removeSheet.ref = "" }
                        Btn {
                            text: "Usuń"; danger: true
                            onClicked: { Flatpak.uninstall(removeSheet.ref, removeSheet.withData); removeSheet.ref = ""; }
                        }
                    }
                }
            }
        }

        // Brak instalatora
        Rectangle {
            visible: !Flatpak.available
            anchors.horizontalCenter: parent.horizontalCenter
            y: 70; z: 22
            width: noFp.implicitWidth + 30; height: 34; radius: 10
            color: Theme.danger
            Txt { id: noFp; anchors.centerIn: parent; text: "Brak programu flatpak: instalowanie jest wyłączone"; color: Theme.dark ? "#16181D" : "white"; font.pixelSize: 12; font.weight: Font.Medium }
        }
    }

    component TabItem: Item {
        id: ti
        property string label
        property bool active: false
        property int badge: 0
        signal clicked()
        implicitWidth: tiRow.implicitWidth + 24
        height: 38
        Rectangle {
            anchors.fill: parent; radius: 10
            color: ti.active ? Theme.fill : (tiArea.containsMouse ? Theme.hover : "transparent")
            Behavior on color { ColorAnimation { duration: 100 } }
        }
        Row {
            id: tiRow
            anchors.centerIn: parent
            spacing: 7
            Txt { anchors.verticalCenter: parent.verticalCenter; text: ti.label; font.pixelSize: 14; font.weight: ti.active ? Font.DemiBold : Font.Normal; color: ti.active ? Theme.text : Theme.text2 }
            Rectangle {
                visible: ti.badge > 0
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(19, bText.implicitWidth + 11); height: 19; radius: 9.5
                color: Theme.accent
                Txt { id: bText; anchors.centerIn: parent; text: String(ti.badge); color: "white"; font.pixelSize: 11; font.weight: Font.DemiBold }
            }
        }
        MouseArea { id: tiArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ti.clicked() }
    }
}
