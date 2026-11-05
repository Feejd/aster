pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Aster.Ui
import Aster.Terminal

// Okno Terminala Aster.
//  • pasek okna: karty (jak w Terminalu Windows) z nazwą folderu albo działającego programu, „+”, szukaj, menu,
//  • terminal leży na głębokim panelu w kolorze schematu; przewijanie historii z cienkim suwakiem,
//  • Ctrl+C kopiuje, gdy coś jest zaznaczone (inaczej przerywa program), Ctrl+V wkleja — jak w Windows.
Window {
    id: win
    property string startDir
    property var startCommand: []

    width: 940 + 2 * m
    height: 600 + 2 * m
    minimumWidth: 440 + 2 * m
    minimumHeight: 260 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: cur ? cur.longTitle : "Terminal"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 12
    property bool wasMaximized: false

    // Kolory schematu (Aster idzie za jasnym/ciemnym motywem systemu)
    readonly property var colors: Terminal.colors(Terminal.scheme, Theme.dark)
    readonly property color paneColor: Terminal.scheme === "aster" ? Theme.paneGlass : colors.background
    readonly property color termText: colors.foreground
    readonly property bool paneDark: colors.dark

    // ——— Karty ———
    ListModel { id: tabs }
    property int current: 0
    property int tabsRevision: 0
    property int uidSeq: 0
    readonly property var cur: { tabsRevision; return pages.count > 0 ? pages.itemAt(Math.max(0, Math.min(current, pages.count - 1))) : null; }
    property var confirm: null                         // { text, detail, action }
    property bool settingsOpen: false

    function tabAt(i) { return pages.itemAt(i); }
    function activate(i) {
        if (i < 0 || i >= tabs.count) return;
        current = i;
        tabs.setProperty(i, "activity", false);
        tabs.setProperty(i, "bell", false);
        Qt.callLater(focusTerm);
    }
    function focusTerm() { if (cur && !settingsOpen && !findBar.shown) cur.view.forceActiveFocus(); }
    function newTab(dir, command) {
        const d = dir !== undefined && dir !== null ? dir
                : (Terminal.newTabHere && cur ? cur.view.currentDirectory : "");
        const at = tabs.count ? current + 1 : 0;
        tabs.insert(at, { uid: ++uidSeq, dir: d, command: JSON.stringify(command || []), title: Terminal.folderName(d), busy: false, activity: false, bell: false });
        tabsRevision++;
        current = at;
        Qt.callLater(focusTerm);
    }
    function closeTab(i, force) {
        if (i < 0 || i >= tabs.count) return;
        const page = tabAt(i);
        if (!force && Terminal.confirmClose && page && page.busy) {
            confirm = { text: "Zamknąć kartę?", detail: "Działa w niej „" + page.view.program + "”. Zamknięcie przerwie ten program.",
                        button: "Zamknij kartę", action: () => win.closeTab(i, true) };
            return;
        }
        if (tabs.count === 1) { forceClose = true; win.close(); return; }
        tabs.remove(i);
        tabsRevision++;
        if (current > i || current >= tabs.count) current = Math.max(0, current - 1);
        Qt.callLater(focusTerm);
    }
    function closeOthers(i) {
        const keep = tabs.get(i).uid;
        for (let k = tabs.count - 1; k >= 0; --k) if (tabs.get(k).uid !== keep) tabs.remove(k);
        tabsRevision++;
        current = 0;
        Qt.callLater(focusTerm);
    }
    function moveTab(from, to) {
        if (from === to || to < 0 || to >= tabs.count) return;
        const wasCurrent = current === from;
        tabs.move(from, to, 1);
        tabsRevision++;
        if (wasCurrent) current = to;
        else if (from < current && to >= current) current--;
        else if (from > current && to <= current) current++;
    }
    function zoom(d) {
        Terminal.fontSize = d === 0 ? 14 : Math.max(8, Math.min(40, Terminal.fontSize + d));
        toast.show("Rozmiar tekstu: " + Math.round(Terminal.fontSize / 14 * 100) + "%");
    }
    function toggleFullScreen() {
        if (visibility === Window.FullScreen) { if (wasMaximized) showMaximized(); else showNormal(); }
        else { wasMaximized = visibility === Window.Maximized; showFullScreen(); }
    }
    function busyTabs() {
        const out = [];
        for (let i = 0; i < tabs.count; ++i) { const p = tabAt(i); if (p && p.busy) out.push(p.view.program); }
        return out;
    }

    // Zamknięcie okna z działającymi programami — najpierw pytanie
    property bool forceClose: false
    onClosing: (close) => {
        const busy = busyTabs();
        if (!forceClose && Terminal.confirmClose && busy.length) {
            close.accepted = false;
            confirm = { text: "Zamknąć okno?", detail: (busy.length === 1 ? "Działa jeszcze „" + busy[0] + "”." : "Działają jeszcze: " + busy.join(", ") + ".") + " Zamknięcie przerwie te programy.",
                        button: "Zamknij okno", action: () => { win.forceClose = true; win.close(); } };
        }
    }

    Component.onCompleted: newTab(startDir, startCommand)
    function testFind(text) { findBar.openBar(); findField.text = text; }

    // ——— Skróty (Ctrl+Shift — reszta klawiszy należy do programów w terminalu) ———
    Shortcut { sequence: "Ctrl+Shift+T"; onActivated: win.newTab() }
    Shortcut { sequence: "Ctrl+Shift+N"; onActivated: Terminal.openWindow(win.cur ? win.cur.view.currentDirectory : "") }
    Shortcut { sequence: "Ctrl+Shift+W"; onActivated: win.closeTab(win.current) }
    Shortcut { sequence: "Ctrl+Shift+Q"; onActivated: win.close() }
    Shortcut { sequences: ["Ctrl+Tab", "Ctrl+PgDown"]; onActivated: win.activate((win.current + 1) % tabs.count) }
    Shortcut { sequences: ["Ctrl+Shift+Tab", "Ctrl+PgUp"]; onActivated: win.activate((win.current - 1 + tabs.count) % tabs.count) }
    Shortcut { sequence: "Ctrl+Shift+PgUp"; onActivated: win.moveTab(win.current, win.current - 1) }
    Shortcut { sequence: "Ctrl+Shift+PgDown"; onActivated: win.moveTab(win.current, win.current + 1) }
    Shortcut { sequence: "Ctrl+Shift+F"; onActivated: findBar.openBar() }
    Shortcut { sequence: "Ctrl+Shift+A"; onActivated: if (win.cur) win.cur.view.selectAll() }
    Shortcut { sequence: "Ctrl+Shift+K"; onActivated: if (win.cur) win.cur.view.clear() }
    Shortcut { sequence: "Ctrl+Shift+O"; onActivated: if (win.cur) Qt.openUrlExternally("file://" + win.cur.view.currentDirectory) }
    Shortcut { sequence: "Ctrl+Shift+P"; onActivated: win.settingsOpen = true }
    Shortcut { sequences: ["Ctrl+=", "Ctrl++", "Ctrl+Shift+="]; onActivated: win.zoom(1) }
    Shortcut { sequence: "Ctrl+-"; onActivated: win.zoom(-1) }
    Shortcut { sequence: "Ctrl+0"; onActivated: win.zoom(0) }
    Shortcut { sequence: "F11"; onActivated: win.toggleFullScreen() }
    Instantiator {
        model: 9
        delegate: Shortcut {
            required property int index
            sequence: "Alt+" + (index + 1)
            onActivated: win.activate(index === 8 ? tabs.count - 1 : Math.min(index, tabs.count - 1))
        }
    }

    // ——— Okno: rozmycie i obszar kliknięć ———
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

        // ——— Pasek okna z kartami ———
        Item {
            id: toolbar
            width: parent.width; height: 50

            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
            TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }

            Flickable {
                id: tabFlick
                x: 12
                width: Math.min(tabRow.width, rightGroup.x - x - 46)
                height: parent.height
                contentWidth: tabRow.width
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentWidth > width
                clip: true
                Row {
                    id: tabRow
                    height: parent.height
                    spacing: 4
                    readonly property real tabWidth: Math.max(120, Math.min(220, (rightGroup.x - 12 - 46 - (tabs.count - 1) * 4) / Math.max(1, tabs.count)))
                    Repeater {
                        model: tabs
                        delegate: TabButton {}
                    }
                }
                function reveal() {
                    const x = win.current * (tabRow.tabWidth + 4);
                    if (x < contentX) contentX = x;
                    else if (x + tabRow.tabWidth > contentX + width) contentX = x + tabRow.tabWidth - width;
                }
                Connections { target: win; function onCurrentChanged() { tabFlick.reveal(); } }
            }
            ToolBtn {
                anchors.left: tabFlick.right; anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                icon: "plus"
                onClicked: win.newTab()
            }

            Row {
                id: rightGroup
                anchors.right: winButtons.left; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                ToolBtn { icon: "search"; onClicked: findBar.shown ? findBar.closeBar() : findBar.openBar() }
                ToolBtn { id: menuButton; icon: "more"; onClicked: win.showMainMenu() }
            }

            WindowButtons {
                id: winButtons
                window: win
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ——— Panel terminala ———
        Rectangle {
            id: pane
            y: toolbar.height
            width: parent.width
            height: parent.height - y
            bottomLeftRadius: win.r; bottomRightRadius: win.r
            color: win.paneColor
            Behavior on color { ColorAnimation { duration: 200 } }
            Rectangle { width: parent.width; height: 1; color: Theme.line }

            Repeater {
                id: pages
                model: tabs
                delegate: TermPage {}
            }

            // Mignięcie zamiast dźwięku (sygnał BEL)
            Rectangle {
                id: flash
                anchors.fill: parent
                bottomLeftRadius: win.r; bottomRightRadius: win.r
                color: win.paneDark ? "white" : "black"
                opacity: 0
                NumberAnimation on opacity { id: flashAnim; running: false; from: 0.12; to: 0; duration: 260; easing.type: Easing.OutQuad }
            }

            // Pliki upuszczone na terminal wpisują się jako ścieżki
            DropArea {
                anchors.fill: parent
                onEntered: (drag) => drag.accept(Qt.CopyAction)
                onDropped: (drop) => {
                    if (!win.cur || !drop.hasUrls) return;
                    win.cur.view.sendText(Terminal.quotePaths(drop.urls) + " ");
                    win.cur.view.forceActiveFocus();
                }
            }

            // ——— Szukaj w historii (Ctrl+Shift+F) ———
            Rectangle {
                id: findBar
                property bool shown: false
                function openBar() {
                    if (!win.cur) return;
                    shown = true;
                    findField.forceActiveFocus();
                    findField.selectAll();
                    if (findField.text) win.cur.view.search(findField.text);
                }
                function closeBar() {
                    shown = false;
                    if (win.cur) win.cur.view.endSearch();
                    win.focusTerm();
                }
                anchors.right: parent.right; anchors.rightMargin: 14
                y: shown ? 12 : -height - 4
                visible: shown || y > -height
                Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
                z: 10
                width: 360; height: 44; radius: 22
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                Icon { x: 15; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 15; color: Theme.text2 }
                TextInput {
                    id: findField
                    x: 40; width: parent.width - 40 - findTools.width - 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                    font.family: Theme.font; font.pixelSize: 13
                    clip: true
                    onTextChanged: if (win.cur) { if (text) win.cur.view.search(text); else win.cur.view.endSearch(); }
                    Keys.onReturnPressed: (e) => { if (win.cur) win.cur.view.searchNext(!(e.modifiers & Qt.ShiftModifier)); }
                    Keys.onEnterPressed: (e) => { if (win.cur) win.cur.view.searchNext(!(e.modifiers & Qt.ShiftModifier)); }
                    Keys.onEscapePressed: findBar.closeBar()
                    Keys.onUpPressed: if (win.cur) win.cur.view.searchNext(true)
                    Keys.onDownPressed: if (win.cur) win.cur.view.searchNext(false)
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: !findField.text; text: "Szukaj w terminalu"; color: Theme.text2; font: findField.font }
                }
                Row {
                    id: findTools
                    anchors.right: parent.right; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        rightPadding: 6
                        visible: !!findField.text && !!win.cur
                        text: !win.cur ? "" : win.cur.view.matchCount === 0 ? "Brak"
                              : (win.cur.view.matchIndex + 1) + " z " + win.cur.view.matchCount + (win.cur.view.matchCount >= 5000 ? "+" : "")
                        color: win.cur && win.cur.view.matchCount === 0 ? Theme.danger : Theme.text2
                        font.family: Theme.font; font.pixelSize: 12
                        font.features: { "tnum": 1 }
                    }
                    FindBtn { icon: "up"; onClicked: if (win.cur) win.cur.view.searchNext(true) }
                    FindBtn { icon: "chevronDown"; onClicked: if (win.cur) win.cur.view.searchNext(false) }
                    FindBtn { icon: "close"; onClicked: findBar.closeBar() }
                }
            }

            // Komunikat na dole panelu
            Rectangle {
                id: toast
                property string text
                function show(t) { text = t; shown = true; toastTimer.restart(); }
                property bool shown: false
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - (shown ? height + 18 : -4)
                Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
                visible: y < parent.height
                z: 10
                width: toastText.implicitWidth + 36; height: 38; radius: 19
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                Text { id: toastText; anchors.centerIn: parent; text: toast.text; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                Timer { id: toastTimer; interval: 1800; onTriggered: toast.shown = false }
            }
        }

        ContextMenu {
            id: menu
            property string kind
            property string link
            onTriggered: (a) => win.runMenuAction(a)
            onShownChanged: if (!shown) win.focusTerm()
        }

        // ——— Pytanie przed zamknięciem ———
        Item {
            anchors.fill: parent
            visible: !!win.confirm
            z: 200
            Rectangle { anchors.fill: parent; radius: win.r; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.25) }
            MouseArea { anchors.fill: parent; onClicked: win.confirm = null }
            Keys.onEscapePressed: win.confirm = null
            Rectangle {
                anchors.centerIn: parent
                width: 380; height: dlgCol.implicitHeight + 40
                radius: 22
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                MouseArea { anchors.fill: parent }
                Column {
                    id: dlgCol
                    x: 22; y: 20; width: parent.width - 44
                    spacing: 8
                    Text { text: win.confirm ? win.confirm.text : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold }
                    Text { width: parent.width; wrapMode: Text.Wrap; text: win.confirm ? win.confirm.detail : ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.15 }
                    Item { width: 1; height: 10 }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Pill { text: "Anuluj"; onClicked: { win.confirm = null; win.focusTerm(); } }
                        Pill {
                            text: win.confirm ? win.confirm.button : ""
                            danger: true
                            onClicked: { const a = win.confirm.action; win.confirm = null; a(); }
                        }
                    }
                }
            }
        }

        // ——— Ustawienia ———
        Loader {
            anchors.fill: parent
            z: 150
            active: win.settingsOpen
            sourceComponent: SettingsSheet {
                radius: win.r
                onCloseRequested: { win.settingsOpen = false; win.focusTerm(); }
            }
        }
    }

    // ——— Strona karty: terminal z suwakiem i komunikatem o zakończeniu ———
    component TermPage: Item {
        id: page
        required property int index
        required property string dir
        required property string command                // JSON: ListModel zamieniłby tablicę w model
        readonly property var commandList: JSON.parse(command)
        readonly property alias view: term
        readonly property bool busy: term.program !== ""
        readonly property string title: term.program !== "" ? term.program : Terminal.folderName(term.currentDirectory)
        readonly property string longTitle: (term.program !== "" ? term.program + " — " : "") + Terminal.prettyPath(term.currentDirectory)
        property bool exited: false
        property string lastProgram: ""
        property real programStart: 0
        anchors.fill: parent
        visible: index === win.current

        onTitleChanged: tabs.setProperty(index, "title", title)
        onBusyChanged: tabs.setProperty(index, "busy", busy)

        TerminalView {
            id: term
            anchors.fill: parent
            anchors.leftMargin: 14; anchors.rightMargin: 12
            anchors.topMargin: 10; anchors.bottomMargin: 8
            workingDirectory: page.dir
            command: page.commandList
            focus: page.index === win.current
            fontFamily: Terminal.fontFamily
            fontSize: Terminal.fontSize
            lineHeight: Terminal.lineHeight
            foreground: win.colors.foreground
            background: win.colors.background
            colorPalette: win.colors.palette
            cursorColor: win.colors.cursor !== "" ? win.colors.cursor : (win.paneDark ? Qt.lighter(Theme.accent, 1.35) : Theme.accent)
            selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, win.paneDark ? 0.42 : 0.24)
            matchColor: "#F5C542"
            cursorStyle: Terminal.cursorStyle
            cursorBlinking: Terminal.cursorBlink
            historyLimit: Terminal.historyLines
            copyOnSelect: Terminal.copyOnSelect

            onActivity: if (page.index !== win.current) tabs.setProperty(page.index, "activity", true)
            onBell: {
                if (Terminal.visualBell && page.index === win.current) flashAnim.restart();
                if (page.index !== win.current) tabs.setProperty(page.index, "bell", true);
                if (!win.active) win.alert(0);
            }
            onProgramChanged: {
                // Długie polecenie skończyło się, gdy okno było w tle — powiadomienie
                if (program !== "") { page.lastProgram = program; page.programStart = Date.now(); return; }
                const took = Date.now() - page.programStart;
                if (page.lastProgram && took > 10000 && Terminal.notifyDone && (!win.active || page.index !== win.current))
                    Terminal.notify("Zakończono: " + page.lastProgram, "Trwało " + win.duration(took) + " · " + Terminal.prettyPath(currentDirectory));
                page.lastProgram = "";
            }
            onFinished: (code) => {
                // Powłoka zamknięta (exit, Ctrl+D) — karta znika; polecenie z błędem zostaje, żeby dało się przeczytać komunikat
                if (page.commandList.length === 0 || code === 0) win.closeTab(page.index, true);
                else page.exited = true;
            }
            onContextMenuRequested: (x, y, link) => win.showViewMenu(term.mapToItem(frame, x, y), link)
            onLinkActivated: (url) => Qt.openUrlExternally(url)
            onZoomRequested: (d) => win.zoom(d)
            onCopied: toast.show("Skopiowano")
        }

        // Suwak historii: pojawia się przy przewijaniu i po najechaniu na prawą krawędź
        Item {
            id: scrollArea
            anchors.right: parent.right
            y: 6; width: 14; height: parent.height - 12
            visible: term.scrollMax > 0
            property bool show: false
            readonly property real thumbH: Math.max(36, height * term.rows / (term.rows + term.scrollMax))
            Connections { target: term; function onScrollChanged() { scrollArea.show = true; hideTimer.restart(); } }
            Timer { id: hideTimer; interval: 1100; onTriggered: scrollArea.show = false }
            HoverHandler { id: scrollHover }
            Rectangle {
                x: scrollHover.hovered || thumbDrag.pressed ? 3 : 6
                width: scrollHover.hovered || thumbDrag.pressed ? 8 : 4
                height: scrollArea.thumbH
                y: (scrollArea.height - height) * (1 - term.scrollValue / Math.max(1, term.scrollMax))
                radius: width / 2
                color: win.paneDark ? Qt.rgba(1, 1, 1, 0.38) : Qt.rgba(0, 0, 0, 0.32)
                opacity: scrollArea.show || scrollHover.hovered || thumbDrag.pressed ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                Behavior on width { NumberAnimation { duration: 120 } }
                Behavior on x { NumberAnimation { duration: 120 } }
            }
            MouseArea {
                id: thumbDrag
                anchors.fill: parent
                function apply(my) {
                    const f = Math.max(0, Math.min(1, (my - scrollArea.thumbH / 2) / Math.max(1, scrollArea.height - scrollArea.thumbH)));
                    term.scrollTo(Math.round((1 - f) * term.scrollMax));
                }
                onPressed: (e) => apply(e.y)
                onPositionChanged: (e) => { if (pressed) apply(e.y); }
                onReleased: win.focusTerm()
            }
        }

        // Przewinięte w górę — przycisk powrotu na dół
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 24
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16
            width: downRow.implicitWidth + 26; height: 34; radius: 17
            color: Theme.surface
            border.width: 1; border.color: Theme.edge
            opacity: term.scrollValue > 0 ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Row {
                id: downRow
                anchors.centerIn: parent
                spacing: 6
                Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.arrowDown; size: 14; color: Theme.text }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Na dół"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { term.scrollToBottom(); win.focusTerm(); } }
        }

        // Podpowiedź przy linku
        Rectangle {
            visible: term.hoveredLink !== "" && term.scrollValue === 0 && !page.exited
            anchors.left: parent.left; anchors.leftMargin: 12
            anchors.bottom: parent.bottom; anchors.bottomMargin: 10
            width: Math.min(parent.width - 24, linkText.implicitWidth + 24); height: 28; radius: 14
            color: Theme.surface
            border.width: 1; border.color: Theme.edge
            Text {
                id: linkText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 24)
                elide: Text.ElideMiddle
                text: "Ctrl + kliknięcie otwiera " + term.hoveredLink
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
        }

        // Program uruchomiony z -e zakończył się błędem
        Rectangle {
            visible: page.exited
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 18
            width: exitRow.implicitWidth + 32; height: 52; radius: 26
            color: Theme.surface
            border.width: 1; border.color: Theme.edge
            Row {
                id: exitRow
                anchors.centerIn: parent
                spacing: 12
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Program zakończył się z kodem " + term.exitCode
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                }
                Pill { anchors.verticalCenter: parent.verticalCenter; text: "Uruchom ponownie"; onClicked: { page.exited = false; term.restart(); term.forceActiveFocus(); } }
                Pill { anchors.verticalCenter: parent.verticalCenter; text: "Zamknij"; onClicked: win.closeTab(page.index, true) }
            }
        }
    }

    function duration(ms) {
        const s = Math.round(ms / 1000);
        if (s < 60) return s + " s";
        const m = Math.floor(s / 60);
        if (m < 60) return m + " min " + (s % 60) + " s";
        return Math.floor(m / 60) + " godz. " + (m % 60) + " min";
    }

    // ——— Karta na pasku ———
    component TabButton: Item {
        id: tb
        required property int index
        required property string title
        required property bool busy
        required property bool activity
        required property bool bell
        readonly property bool active: index === win.current
        width: tabRow.tabWidth; height: tabRow.height

        Rectangle {
            id: tabBg
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 34; radius: 12
            color: tb.active ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.11) : Qt.rgba(1, 1, 1, 0.85))
                             : (tabArea.containsMouse ? Theme.hover : "transparent")
            border.width: tb.active && !Theme.dark ? 1 : 0
            border.color: Theme.edge
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        // Znak: >_ albo pulsująca kropka, gdy coś działa
        Item {
            id: glyph
            x: 12; anchors.verticalCenter: parent.verticalCenter
            width: 16; height: 16
            Icon { anchors.centerIn: parent; visible: !tb.busy; d: Icons.prompt; size: 15; stroke: 2; color: tb.active ? Theme.accentText : Theme.text2 }
            Rectangle {
                anchors.centerIn: parent
                visible: tb.busy
                width: 8; height: 8; radius: 4
                color: Theme.accent
                SequentialAnimation on opacity {
                    running: tb.busy; loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
        }
        Text {
            anchors.left: glyph.right; anchors.leftMargin: 8
            anchors.right: closeBtn.visible ? closeBtn.left : parent.right; anchors.rightMargin: closeBtn.visible ? 4 : 12
            anchors.verticalCenter: parent.verticalCenter
            text: tb.title
            elide: Text.ElideMiddle
            color: tb.active ? Theme.text : Theme.text2
            font.family: Theme.font; font.pixelSize: 13
            font.weight: tb.active ? Font.Medium : Font.Normal
        }
        // Coś się wydarzyło w karcie w tle
        Rectangle {
            visible: !tb.active && (tb.activity || tb.bell) && !closeBtn.visible
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 7; height: 7; radius: 3.5
            color: tb.bell ? "#F5A623" : Theme.accent
        }
        MouseArea {
            id: tabArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            property real pressX: 0
            property bool moved: false
            onPressed: (e) => {
                pressX = e.x; moved = false;
                if (e.button === Qt.LeftButton) win.activate(tb.index);
            }
            onPositionChanged: (e) => {
                if (!(e.buttons & Qt.LeftButton)) return;
                if (!moved && Math.abs(e.x - pressX) < 8) return;
                moved = true;
                const px = tb.mapToItem(tabRow, e.x, 0).x;
                const to = Math.max(0, Math.min(tabs.count - 1, Math.floor(px / (tabRow.tabWidth + 4))));
                if (to !== tb.index) win.moveTab(tb.index, to);
            }
            onClicked: (e) => {
                if (e.button === Qt.MiddleButton) win.closeTab(tb.index);
                else if (e.button === Qt.RightButton) win.showTabMenu(tb.index, tb.mapToItem(frame, e.x, e.y));
            }
        }
        Rectangle {
            id: closeBtn
            anchors.right: parent.right; anchors.rightMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            width: 22; height: 22; radius: 11
            visible: tabs.count > 1 && (tb.active || tabArea.containsMouse || closeArea.containsMouse)
            color: closeArea.containsMouse ? Theme.hover : "transparent"
            Icon { anchors.centerIn: parent; d: Icons.close; size: 11; stroke: 2; color: Theme.text2 }
            MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; onClicked: win.closeTab(tb.index) }
        }
    }

    component FindBtn: HoverButton {
        property string icon
        width: 30; height: 30; radius: 15
        Icon { anchors.centerIn: parent; d: Icons[parent.icon] || ""; size: 14; stroke: 2; color: Theme.text2 }
    }

    component Pill: HoverButton {
        id: pill
        property string text
        property bool danger: false
        width: pillText.implicitWidth + 30; height: 34; radius: 17
        baseColor: danger ? "#E5484D" : Theme.fill
        color: hovered ? (danger ? "#D93B40" : Theme.hover) : baseColor
        Text { id: pillText; anchors.centerIn: parent; text: pill.text; color: pill.danger ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
    }

    // ——— Menu ———
    function showMainMenu() {
        menu.kind = "main";
        const p = menuButton.mapToItem(frame, menuButton.width, menuButton.height + 6);
        menu.openAt(p.x - 250, p.y, [
            { label: "Nowa karta", icon: "plus", shortcut: "Ctrl+Shift+T", action: "newTab" },
            { label: "Nowe okno", icon: "desktop", shortcut: "Ctrl+Shift+N", action: "newWindow" },
            { separator: true },
            { label: "Szukaj", icon: "search", shortcut: "Ctrl+Shift+F", action: "find" },
            { label: "Wyczyść", icon: "trash", shortcut: "Ctrl+Shift+K", action: "clear" },
            { label: "Otwórz folder w Plikach", icon: "folder", shortcut: "Ctrl+Shift+O", action: "files" },
            { separator: true },
            { label: "Powiększ tekst", icon: "plus", shortcut: "Ctrl++", action: "zoomIn" },
            { label: "Pomniejsz tekst", icon: "minimize", shortcut: "Ctrl+−", action: "zoomOut" },
            { label: win.visibility === Window.FullScreen ? "Zakończ pełny ekran" : "Pełny ekran", icon: "fullscreen", shortcut: "F11", action: "fullscreen" },
            { separator: true },
            { label: "Ustawienia", icon: "gear", shortcut: "Ctrl+Shift+P", action: "settings" }
        ]);
    }
    function showViewMenu(p, link) {
        menu.kind = "view";
        menu.link = link;
        const v = cur.view;
        const items = [];
        if (link) {
            items.push({ label: "Otwórz link", icon: "globe", action: "openLink" });
            items.push({ label: "Kopiuj adres linku", icon: "copy", action: "copyLink" });
            items.push({ separator: true });
        }
        items.push({ label: "Kopiuj", icon: "copy", shortcut: "Ctrl+C", action: "copy", enabled: v.hasSelection });
        items.push({ label: "Wklej", icon: "paste", shortcut: "Ctrl+V", action: "paste" });
        items.push({ label: "Zaznacz wszystko", icon: "check", shortcut: "Ctrl+Shift+A", action: "selectAll" });
        items.push({ separator: true });
        items.push({ label: "Szukaj", icon: "search", shortcut: "Ctrl+Shift+F", action: "find" });
        items.push({ label: "Wyczyść", icon: "trash", shortcut: "Ctrl+Shift+K", action: "clear" });
        items.push({ label: "Otwórz folder w Plikach", icon: "folder", action: "files" });
        items.push({ separator: true });
        items.push({ label: "Nowa karta", icon: "plus", shortcut: "Ctrl+Shift+T", action: "newTab" });
        items.push({ label: "Ustawienia", icon: "gear", action: "settings" });
        menu.openAt(p.x, p.y, items);
    }
    property int menuTab: -1
    function showTabMenu(i, p) {
        menu.kind = "tab";
        menuTab = i;
        menu.openAt(p.x, p.y, [
            { label: "Nowa karta", icon: "plus", shortcut: "Ctrl+Shift+T", action: "newTab" },
            { label: "Duplikuj kartę", icon: "copy", action: "duplicate" },
            { separator: true },
            { label: "Zamknij", icon: "close", shortcut: "Ctrl+Shift+W", action: "tabClose" },
            { label: "Zamknij pozostałe karty", icon: "close", action: "tabCloseOthers", enabled: tabs.count > 1 }
        ]);
    }
    function runMenuAction(a) {
        const v = cur ? cur.view : null;
        if (a === "newTab") newTab();
        else if (a === "newWindow") Terminal.openWindow(v ? v.currentDirectory : "");
        else if (a === "find") findBar.openBar();
        else if (a === "clear" && v) v.clear();
        else if (a === "files" && v) Qt.openUrlExternally("file://" + v.currentDirectory);
        else if (a === "zoomIn") zoom(1);
        else if (a === "zoomOut") zoom(-1);
        else if (a === "fullscreen") toggleFullScreen();
        else if (a === "settings") settingsOpen = true;
        else if (a === "openLink") Qt.openUrlExternally(menu.link);
        else if (a === "copyLink") { clip.text = menu.link; clip.selectAll(); clip.copy(); toast.show("Skopiowano adres"); }
        else if (a === "copy" && v) v.copy();
        else if (a === "paste" && v) v.paste();
        else if (a === "selectAll" && v) v.selectAll();
        else if (a === "duplicate") { const p = tabAt(menuTab); newTab(p ? p.view.currentDirectory : ""); }
        else if (a === "tabClose") closeTab(menuTab);
        else if (a === "tabCloseOthers") closeOthers(menuTab);
    }
    TextEdit { id: clip; visible: false }
}
