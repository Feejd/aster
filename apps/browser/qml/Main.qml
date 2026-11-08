pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Shapes
import QtQml.Models
import QtWebEngine
import Aster.Ui
import Aster.Browser

// Okno Przeglądarki Aster (każde okno to osobna kopia tego pliku; wspólne dane są w Browser).
//  • pasek okna: wstecz/dalej/odśwież, adres na środku (sama domena, pełny adres po kliknięciu),
//    pobrane, nowa karta i menu; pod nim karty (od drugiej karty) i — opcjonalnie — pasek ulubionych,
//  • strona leży na głębokim panelu, karta aktywna łączy się z nią jak zakładka,
//  • okno prywatne ma fioletowy odcień i używa profilu, który niczego nie zapisuje.
Window {
    id: win
    property var startUrls: []
    property bool privateMode: false
    property int windowId: 0
    property var restoreTabs: []
    property int restoreCurrent: 0

    width: 1280 + 2 * m
    height: 820 + 2 * m
    minimumWidth: 560 + 2 * m
    minimumHeight: 420 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: (cur ? cur.pageTitle : "Przeglądarka") + (privateMode ? " — prywatne" : "")

    readonly property var profile: privateMode ? Browser.privateProfile : Browser.profile
    property bool pageFullScreen: false
    property bool wasMaximized: false
    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 24

    // ——— Karty ———
    ListModel { id: tabs }
    property int current: 0
    property int tabsRevision: 0                       // zmienia się przy dodaniu, usunięciu i przesunięciu karty
    property int uidSeq: 0
    readonly property var cur: { tabsRevision; return pages.count > 0 ? pages.itemAt(Math.max(0, Math.min(current, pages.count - 1))) : null; }
    readonly property color tint: cur && cur.themeColor.a > 0 ? cur.themeColor : "transparent"
    property var closedTabs: []                        // do Ctrl+Shift+T
    property var pendingPermission: null
    property var menuRequest: null
    property string menuKind: ""
    property int menuTab: -1

    function tabAt(i) { return pages.itemAt(i); }
    function activate(i) {
        if (i < 0 || i >= tabs.count) return;
        current = i;
        Qt.callLater(focusPage);
    }
    function focusPage() {
        if (!cur) return;
        if (cur.blank) focusAddress();
        else cur.view.forceActiveFocus();
    }
    function newTab(url, background, opts) {
        const o = opts || {};
        const at = o.afterCurrent && tabs.count ? Math.min(current + 1 + (o.offset || 0), tabs.count) : tabs.count;
        tabs.insert(at, { uid: ++uidSeq, startUrl: url || "", title: o.title || (url ? Urls.host(url) : "Nowa karta"), icon: "",
                          lazyLoad: !!o.lazy, fromPage: !!o.adopted, loading: false, audible: false, muted: false });
        tabsRevision++;
        if (!background) {
            current = at;
            if (!url && !o.adopted) Qt.callLater(focusAddress);
        } else if (at <= current && tabs.count > 1) current++;
        sessionTimer.restart();
        return pages.itemAt(at);
    }
    function closeTab(i) {
        if (i < 0 || i >= tabs.count) return;
        const page = tabAt(i);
        if (page && !page.blank && !privateMode) closedTabs = closedTabs.concat([{ url: page.pageUrl, at: i }]).slice(-25);
        if (tabs.count === 1) { win.close(); return; }
        tabs.remove(i);
        tabsRevision++;
        if (current > i || current >= tabs.count) current = Math.max(0, current - 1);
        Qt.callLater(focusPage);
        sessionTimer.restart();
    }
    function reopenTab() {
        if (!closedTabs.length) return;
        const t = closedTabs[closedTabs.length - 1];
        closedTabs = closedTabs.slice(0, -1);
        newTab(t.url);
    }
    function duplicateTab(i) { const p = tabAt(i); if (p) newTab(p.pageUrl, false, { afterCurrent: true }); }
    function closeOthers(i) {
        const keep = tabs.get(i).uid;
        for (let k = tabs.count - 1; k >= 0; --k) if (tabs.get(k).uid !== keep) tabs.remove(k);
        tabsRevision++;
        current = 0;
        sessionTimer.restart();
    }
    function closeRight(i) {
        for (let k = tabs.count - 1; k > i; --k) tabs.remove(k);
        tabsRevision++;
        current = Math.min(current, tabs.count - 1);
        sessionTimer.restart();
    }
    function moveTab(from, to) {
        if (from === to || to < 0 || to >= tabs.count) return;
        const wasCurrent = current === from;
        tabs.move(from, to, 1);
        tabsRevision++;
        if (wasCurrent) current = to;
        else if (from < current && to >= current) current--;
        else if (from > current && to <= current) current++;
        sessionTimer.restart();
    }
    // Strony wewnętrzne otwierają się w swojej karcie (jeśli już jest — przełącza na nią)
    function openInternal(name) {
        for (let i = 0; i < tabs.count; ++i)
            if (tabAt(i) && tabAt(i).internal === name) { activate(i); return; }
        if (cur && cur.blank) cur.load("aster://" + name);
        else newTab("aster://" + name);
    }
    // Wywoływane przez Browser, gdy inny program otwiera link
    function openUrls(urls) {
        for (const u of urls) newTab(u);
        if (!urls.length) newTab("");
    }
    function go(text) {
        const url = Browser.fixup(text);
        if (!url || !cur) return;
        cur.load(url);
        suggest.close();
        if (!Urls.internal(url)) cur.view.forceActiveFocus();
    }
    function focusAddress() {
        field.forceActiveFocus();
        field.selectAll();
    }
    function toggleFavorite() {
        if (!cur || cur.blank || cur.internal) return;
        if (Browser.isBookmarked(cur.pageUrl)) { Browser.removeBookmark(cur.pageUrl); toast.show("Usunięto z ulubionych"); }
        else { Browser.addBookmark(cur.pageUrl, cur.view.title); toast.show("Dodano do ulubionych"); }
    }
    function zoom(d) {
        if (!cur || cur.internal) return;
        const z = d === 0 ? 1 : Math.max(0.25, Math.min(5, Math.round((cur.view.zoomFactor + d) * 10) / 10));
        cur.view.zoomFactor = z;
        if (!privateMode) Browser.setZoom(cur.pageUrl, z);
        zoomShown = z;
        zoomTimer.restart();
    }
    property real zoomShown: 0
    Timer { id: zoomTimer; interval: 1600; onTriggered: win.zoomShown = 0 }

    function savePdf() {
        if (!cur || cur.blank || cur.internal) return;
        const name = (cur.view.title || Urls.host(cur.pageUrl)).replace(/[\/\\:*?"<>|]+/g, " ").trim().slice(0, 80) || "strona";
        cur.view.printToPdf(Browser.uniquePath(name + ".pdf"));
    }
    function savePage() {
        if (!cur || cur.blank || cur.internal) return;
        const name = (cur.view.title || Urls.host(cur.pageUrl)).replace(/[\/\\:*?"<>|]+/g, " ").trim().slice(0, 80) || "strona";
        cur.view.save(Browser.uniquePath(name + ".mhtml"), WebEngineDownloadRequest.MimeHtmlSaveFormat);
    }
    function installAsApp() {
        if (cur && !cur.blank && !cur.internal) Qt.openUrlExternally("aster-webapp:install?url=" + encodeURIComponent(cur.pageUrl));
    }
    function toggleWindowFullScreen() {
        if (visibility === Window.FullScreen) { if (wasMaximized) showMaximized(); else showNormal(); }
        else { wasMaximized = visibility === Window.Maximized; showFullScreen(); }
    }

    // ——— Sesja: karty zapisywane na bieżąco (po awarii też wracają) ———
    Timer { id: sessionTimer; interval: 700; onTriggered: win.saveSession() }
    function saveSession() {
        if (privateMode) return;
        const list = [];
        for (let i = 0; i < tabs.count; ++i) {
            const p = tabAt(i), t = tabs.get(i);
            if (!p) continue;
            list.push({ url: !p.started ? t.startUrl : p.blank ? "" : p.pageUrl, title: p.started ? p.pageTitle : t.title });
        }
        Browser.updateSession(windowId, list, current);
    }
    onCurrentChanged: sessionTimer.restart()

    Component.onCompleted: {
        for (const t of restoreTabs) newTab(t.url, true, { lazy: true, title: t.title });
        if (restoreTabs.length) current = Math.max(0, Math.min(restoreCurrent, tabs.count - 1));
        for (const u of startUrls) newTab(u);
        if (!tabs.count) newTab("");
        effectsTimer.restart();
        Qt.callLater(focusPage);
    }
    onClosing: {
        sessionTimer.stop();
        saveSession();
        Browser.windowClosed(win);
    }

    Connections {
        target: Browser
        function onDownloadStarted(item, window) {
            if (window !== win) return;
            downloadsPopup.open(true);
        }
    }

    // ——— Skróty ———
    Shortcut { sequence: "Ctrl+T"; onActivated: win.newTab("") }
    Shortcut { sequence: "Ctrl+N"; onActivated: Browser.openWindow([], false) }
    Shortcut { sequence: "Ctrl+Shift+N"; onActivated: Browser.openWindow([], true) }
    Shortcut { sequences: ["Ctrl+W", "Ctrl+F4"]; onActivated: win.closeTab(win.current) }
    Shortcut { sequence: "Ctrl+Shift+W"; onActivated: win.close() }
    Shortcut { sequence: "Ctrl+Shift+T"; onActivated: win.reopenTab() }
    Shortcut { sequences: ["Ctrl+L", "Alt+D", "F6", "Ctrl+K", "Ctrl+E"]; onActivated: win.focusAddress() }
    Shortcut { sequences: ["Ctrl+R", "F5"]; onActivated: if (win.cur) win.cur.reload() }
    Shortcut { sequences: ["Ctrl+Shift+R", "Shift+F5"]; onActivated: if (win.cur) win.cur.view.triggerWebAction(WebEngineView.ReloadAndBypassCache) }
    Shortcut { sequence: "Alt+Left"; onActivated: if (win.cur) win.cur.goBack() }
    Shortcut { sequence: "Alt+Right"; onActivated: if (win.cur) win.cur.view.goForward() }
    Shortcut { sequences: ["Ctrl+Tab", "Ctrl+PgDown"]; onActivated: win.activate((win.current + 1) % tabs.count) }
    Shortcut { sequences: ["Ctrl+Shift+Tab", "Ctrl+PgUp"]; onActivated: win.activate((win.current - 1 + tabs.count) % tabs.count) }
    Shortcut { sequence: "Ctrl+9"; onActivated: win.activate(tabs.count - 1) }
    Shortcut { sequence: "Ctrl+F"; onActivated: findBar.openBar() }
    Shortcut { sequence: "F3"; onActivated: if (findBar.shown) findBar.find(false); else findBar.openBar() }
    Shortcut { sequence: "Shift+F3"; onActivated: if (findBar.shown) findBar.find(true) }
    Shortcut { sequence: "Ctrl+D"; onActivated: win.toggleFavorite() }
    Shortcut { sequence: "Ctrl+H"; onActivated: win.openInternal("history") }
    Shortcut { sequence: "Ctrl+J"; onActivated: win.openInternal("downloads") }
    Shortcut { sequence: "Ctrl+Shift+B"; onActivated: Browser.showFavoritesBar = !Browser.showFavoritesBar }
    Shortcut { sequence: "Ctrl+Shift+Del"; onActivated: win.openInternal("settings") }
    Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: win.zoom(0.1) }
    Shortcut { sequence: "Ctrl+-"; onActivated: win.zoom(-0.1) }
    Shortcut { sequence: "Ctrl+0"; onActivated: win.zoom(0) }
    Shortcut { sequence: "Ctrl+S"; onActivated: win.savePage() }
    Shortcut { sequence: "Ctrl+P"; onActivated: win.savePdf() }
    Shortcut { sequence: "Ctrl+U"; onActivated: if (win.cur && !win.cur.blank && !win.cur.internal) win.newTab("view-source:" + win.cur.pageUrl, false, { afterCurrent: true }) }
    Shortcut { sequences: ["F12", "Ctrl+Shift+I"]; onActivated: if (win.cur && !win.cur.internal) win.cur.devTools = !win.cur.devTools }
    Shortcut { sequence: "F11"; onActivated: win.toggleWindowFullScreen() }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (win.pageFullScreen) win.cur.view.fullScreenCancelled();
            else if (findBar.shown) findBar.closeBar();
            else if (win.cur && win.cur.loading) win.cur.view.stop();
        }
    }
    Instantiator {
        model: 8
        delegate: Shortcut {
            required property int index
            sequence: "Ctrl+" + (index + 1)
            onActivated: win.activate(Math.min(index, tabs.count - 1))
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

        // Odcień paska: kolor strony albo fiolet okna prywatnego
        Rectangle {
            width: parent.width; height: chrome.height
            topLeftRadius: win.r; topRightRadius: win.r
            color: win.privateMode ? "#6B4FD8" : win.tint
            opacity: win.privateMode ? (Theme.dark ? 0.30 : 0.16) : (win.tint.a > 0 ? 0.16 : 0)
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on color { ColorAnimation { duration: 180 } }
        }

        // ——— Pasek okna ———
        Item {
            id: chrome
            width: parent.width
            height: win.pageFullScreen ? 0 : toolbar.height + tabStrip.height + favBar.height
            visible: !win.pageFullScreen
            clip: true

            Item {
                id: toolbar
                width: parent.width; height: 62

                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }

                Row {
                    id: nav
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Rectangle {
                        visible: win.privateMode
                        anchors.verticalCenter: parent.verticalCenter
                        width: privText.implicitWidth + 40; height: 30; radius: 15
                        color: Qt.rgba(0.42, 0.31, 0.85, Theme.dark ? 0.5 : 0.18)
                        Icon { x: 11; anchors.verticalCenter: parent.verticalCenter; d: Icons.eye; size: 14; color: Theme.dark ? "white" : "#4B33B5" }
                        Text { id: privText; x: 31; anchors.verticalCenter: parent.verticalCenter; text: "Prywatne"; color: Theme.dark ? "white" : "#4B33B5"; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                    }
                    Item { width: win.privateMode ? 6 : 0; height: 1 }
                    ToolBtn { width: 40; height: 40; radius: 20; tip: "Wstecz"; icon: "back"; enabled: !!win.cur && win.cur.canGoBack; onClicked: win.cur.goBack() }
                    ToolBtn { width: 40; height: 40; radius: 20; tip: "Dalej"; icon: "forward"; enabled: !!win.cur && !win.cur.internal && win.cur.view.canGoForward; onClicked: win.cur.view.goForward() }
                    ToolBtn {
                        width: 40; height: 40; radius: 20
                        tip: win.cur && win.cur.loading ? "Zatrzymaj" : "Odśwież"
                        icon: win.cur && win.cur.loading ? "close" : "reload"
                        enabled: !!win.cur && !win.cur.blank
                        onClicked: if (win.cur.loading) win.cur.view.stop(); else win.cur.reload()
                    }
                }

                // ——— Pasek adresu ———
                Rectangle {
                    id: address
                    readonly property real room: toolbar.width - 2 * Math.max(nav.x + nav.width, toolbar.width - rightGroup.x) - 24
                    width: Math.max(220, Math.min(760, room))
                    height: 44
                    anchors.centerIn: parent
                    radius: 22
                    color: Theme.surface
                    border.width: field.activeFocus ? 1.5 : 0
                    border.color: Theme.accent
                    Behavior on color { ColorAnimation { duration: 120 } }

                    // Postęp wczytywania — cienka linia przy dolnej krawędzi
                    Rectangle {
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 1
                        x: 14
                        height: 2; radius: 1
                        width: (parent.width - 28) * (win.cur && !win.cur.internal ? win.cur.view.loadProgress / 100 : 0)
                        color: Theme.accent
                        opacity: win.cur && win.cur.loading ? 1 : 0
                        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                    }

                    // Kłódka / tarcza: informacje o witrynie
                    HoverButton {
                        id: siteButton
                        x: 7; anchors.verticalCenter: parent.verticalCenter
                        width: siteRow.implicitWidth + 18; height: 32; radius: 16
                        enabled: !!win.cur && !win.cur.blank && !win.cur.internal && !field.activeFocus
                        onClicked: siteInfo.shown = !siteInfo.shown
                        Row {
                            id: siteRow
                            anchors.centerIn: parent
                            spacing: 5
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                d: !win.cur || win.cur.blank || field.activeFocus ? Icons.search
                                   : win.cur.internal ? Icons.aster
                                   : win.cur.secure ? Icons.lock : Icons.info
                                size: 15
                                color: win.cur && win.cur.insecure && !field.activeFocus ? Theme.danger : Theme.text2
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !!win.cur && win.cur.blocked > 0 && !field.activeFocus
                                text: win.cur ? win.cur.blocked : ""
                                color: Theme.accentText
                                font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                                font.features: { "tnum": 1 }
                            }
                        }
                    }

                    // Bez fokusu: sama domena na środku (albo zapytanie wyszukiwania)
                    Text {
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 2 * Math.max(siteButton.width, addrButtons.width) - 24)
                        visible: !field.activeFocus
                        elide: Text.ElideRight
                        text: !win.cur || win.cur.blank ? "Szukaj w " + Browser.searchName + " albo wpisz adres"
                              : win.cur.internal ? win.cur.pageTitle
                              : Browser.isSearchUrl(win.cur.pageUrl) ? Browser.searchQuery(win.cur.pageUrl)
                              : Urls.host(win.cur.pageUrl)
                        color: !win.cur || win.cur.blank ? Theme.text2 : Theme.text
                        font.family: Theme.font; font.pixelSize: 14
                        font.weight: !win.cur || win.cur.blank ? Font.Normal : Font.Medium
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.leftMargin: siteButton.width + 8
                        anchors.rightMargin: addrButtons.width + 4
                        visible: !field.activeFocus
                        cursorShape: Qt.IBeamCursor
                        onClicked: win.focusAddress()
                    }

                    TextInput {
                        id: field
                        anchors.left: parent.left; anchors.leftMargin: 42
                        anchors.right: addrButtons.left; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: activeFocus ? 1 : 0
                        clip: true
                        color: Theme.text
                        selectionColor: Theme.accentSoft
                        selectedTextColor: Theme.text
                        font.family: Theme.font; font.pixelSize: 14
                        selectByMouse: true
                        property string typed: ""
                        onActiveFocusChanged: {
                            if (activeFocus) {
                                text = win.cur && !win.cur.blank ? win.cur.pageUrl : "";
                                typed = "";
                                selectAll();
                                siteInfo.shown = false;
                            } else suggest.close();
                        }
                        onTextEdited: {
                            // Uzupełnianie w miejscu: „you” → „youtube.com” (zaznaczona końcówka), tylko przy dopisywaniu
                            const t = text.slice(0, selectionStart === selectionEnd ? text.length : selectionStart);
                            const growing = t.length > typed.length && t.indexOf(typed) === 0;
                            typed = t;
                            suggest.update(t);
                            if (growing) suggest.inlineComplete(t);
                        }
                        Keys.onReturnPressed: (e) => suggest.accept(e.modifiers)
                        Keys.onEnterPressed: (e) => suggest.accept(e.modifiers)
                        Keys.onEscapePressed: {
                            if (suggest.visible) suggest.close();
                            else if (win.cur) { win.cur.view.forceActiveFocus(); }
                        }
                        Keys.onDownPressed: suggest.move(1)
                        Keys.onUpPressed: suggest.move(-1)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !field.text
                            text: "Szukaj w " + Browser.searchName + " albo wpisz adres"
                            color: Theme.text2
                            font: field.font
                        }
                    }

                    Row {
                        id: addrButtons
                        anchors.right: parent.right; anchors.rightMargin: 5
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        readonly property bool page: !!win.cur && !win.cur.blank && !win.cur.internal && !field.activeFocus
                        // Powiększenie inne niż 100% (kliknięcie przywraca)
                        HoverButton {
                            visible: addrButtons.page && (win.zoomShown > 0 || Math.abs(win.cur.view.zoomFactor - 1) > 0.01)
                            width: zoomText.implicitWidth + 16; height: 28; radius: 14
                            baseColor: Theme.accentSoft
                            onClicked: win.zoom(0)
                            Text { id: zoomText; anchors.centerIn: parent; text: win.cur ? Math.round(win.cur.view.zoomFactor * 100) + "%" : ""; color: Theme.accentText; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                        }
                        // Zainstaluj stronę jako aplikację
                        HoverButton {
                            visible: addrButtons.page && !win.privateMode
                            width: 30; height: 30; radius: 15
                            onClicked: win.installAsApp()
                            Icon { anchors.centerIn: parent; d: Icons.webapp; size: 15; color: Theme.text2 }
                        }
                        // Gwiazdka: dodaj / usuń z ulubionych
                        HoverButton {
                            visible: addrButtons.page
                            width: 30; height: 30; radius: 15
                            onClicked: win.toggleFavorite()
                            Shape {
                                id: star
                                anchors.centerIn: parent
                                width: 24; height: 24
                                scale: 15 / 24
                                preferredRendererType: Shape.CurveRenderer
                                readonly property bool on: { Browser.bookmarks; return !!win.cur && Browser.isBookmarked(win.cur.pageUrl); }
                                ShapePath {
                                    strokeColor: star.on ? "#F2B33D" : Theme.text2
                                    fillColor: star.on ? "#F2B33D" : "transparent"
                                    strokeWidth: 1.9
                                    joinStyle: ShapePath.RoundJoin
                                    PathSvg { path: Icons.star }
                                }
                            }
                        }
                    }
                }

                Row {
                    id: rightGroup
                    anchors.right: winButtons.left; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    // Pobrane (z kółkiem postępu, gdy coś się pobiera)
                    HoverButton {
                        id: dlButton
                        width: 40; height: 40; radius: 20
                        tip: "Pobrane"
                        visible: Browser.downloads.length > 0
                        onClicked: downloadsPopup.open(!downloadsPopup.shown)
                        readonly property real progress: {
                            let got = 0, total = 0;
                            for (const d of Browser.downloads) if (d.active && d.total > 0) { got += d.received; total += d.total; }
                            return Browser.activeDownloads > 0 ? (total > 0 ? got / total : 0.05) : -1;
                        }
                        Icon { anchors.centerIn: parent; d: Icons.download; size: 17; color: dlButton.progress >= 0 ? Theme.accentText : Theme.text }
                        Shape {
                            anchors.centerIn: parent
                            width: 30; height: 30
                            visible: dlButton.progress >= 0
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeColor: Theme.accent; strokeWidth: 2.2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                PathAngleArc { centerX: 15; centerY: 15; radiusX: 13; radiusY: 13; startAngle: -90; sweepAngle: 360 * Math.max(0.03, dlButton.progress) }
                            }
                        }
                    }
                    ToolBtn { width: 40; height: 40; radius: 20; tip: "Nowa karta"; icon: "plus"; onClicked: win.newTab("") }
                    ToolBtn { id: menuButton; width: 40; height: 40; radius: 20; tip: "Menu"; icon: "more"; onClicked: win.showMainMenu() }
                }

                WindowButtons {
                    id: winButtons
                    window: win
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // ——— Karty (widoczne od drugiej karty) ———
            Item {
                id: tabStrip
                y: toolbar.height
                width: parent.width
                height: tabs.count > 1 ? 44 : 0
                visible: height > 0
                clip: true
                Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutQuint } }

                Flickable {
                    id: tabFlick
                    x: 12; width: parent.width - 24 - 44
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
                        readonly property real tabWidth: Math.max(130, Math.min(232, (tabFlick.width - (tabs.count - 1) * 4) / Math.max(1, tabs.count)))
                        Repeater {
                            model: tabs
                            delegate: TabButton {}
                        }
                    }
                    // Aktywna karta zawsze widoczna
                    function reveal() {
                        const x = win.current * (tabRow.tabWidth + 4);
                        if (x < contentX) contentX = x;
                        else if (x + tabRow.tabWidth > contentX + width) contentX = x + tabRow.tabWidth - width;
                    }
                    Connections { target: win; function onCurrentChanged() { tabFlick.reveal(); } }
                }
                ToolBtn {
                    anchors.right: parent.right; anchors.rightMargin: 10
                    y: 4; width: 36; height: 36; radius: 18
                    tip: "Nowa karta"
                    icon: "plus"
                    onClicked: win.newTab("")
                }
            }

            // ——— Pasek ulubionych ———
            Item {
                id: favBar
                y: toolbar.height + tabStrip.height
                width: parent.width
                height: Browser.showFavoritesBar && Browser.bookmarks.length ? 34 : 0
                visible: height > 0
                clip: true
                Row {
                    x: 12; height: parent.height
                    spacing: 2
                    Repeater {
                        model: Browser.bookmarks
                        delegate: HoverButton {
                            id: favChip
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(180, favLabel.implicitWidth + 40); height: 28; radius: 14
                            Image { x: 9; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; source: Urls.favicon(favChip.modelData.url); sourceSize: Qt.size(32, 32); asynchronous: true }
                            Text {
                                id: favLabel
                                x: 31; width: parent.width - 40
                                anchors.verticalCenter: parent.verticalCenter
                                text: favChip.modelData.title || Urls.host(favChip.modelData.url)
                                elide: Text.ElideRight
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onClicked: (m) => {
                                    if (m.button === Qt.MiddleButton || (m.modifiers & Qt.ControlModifier)) win.newTab(favChip.modelData.url, true, { afterCurrent: true });
                                    else if (win.cur) win.cur.load(favChip.modelData.url);
                                }
                            }
                        }
                    }
                }
            }
        }

        // ——— Prośba strony o uprawnienie ———
        Rectangle {
            id: permBar
            x: 12; y: chrome.height + 2
            width: parent.width - 24
            height: win.pendingPermission ? 50 : 0
            radius: 14
            visible: height > 0
            clip: true
            z: 5
            color: Theme.paneGlass
            border.width: 1; border.color: Theme.edge
            Behavior on height { NumberAnimation { duration: 110; easing.type: Easing.OutQuint } }
            readonly property var names: ["uzyskać dodatkowe uprawnienie", "używać mikrofonu", "używać kamery", "używać kamery i mikrofonu",
                                          "udostępniać ekran", "udostępniać ekran z dźwiękiem", "przejąć kursor myszy", "wysyłać powiadomienia",
                                          "znać Twoją lokalizację", "czytać schowek", "widzieć zainstalowane czcionki"]
            function answer(grant) {
                if (!win.pendingPermission) return;
                if (grant) win.pendingPermission.grant(); else win.pendingPermission.deny();
                win.pendingPermission = null;
            }
            Row {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.lock; size: 16; color: Theme.accentText }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.pendingPermission
                          ? "<b>" + Urls.host(win.pendingPermission.origin.toString()) + "</b> chce " + (permBar.names[win.pendingPermission.permissionType] || permBar.names[0])
                          : ""
                    textFormat: Text.StyledText
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 13
                }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                PillButton { height: 34; text: "Nie zezwalaj"; onClicked: permBar.answer(false) }
                PillButton { height: 34; text: "Zezwól"; primary: true; onClicked: permBar.answer(true) }
            }
        }

        // ——— Strony ———
        Rectangle {
            visible: !win.pageFullScreen
            x: content.x; y: content.y
            width: content.width; height: content.height
            radius: content.cardRadius
            color: Theme.surface
        }
        Item {
            id: content
            readonly property int inset: win.pageFullScreen ? 0 : 12
            readonly property real cardRadius: win.pageFullScreen ? 0 : 20
            x: inset
            y: chrome.height + (permBar.height ? permBar.height + 6 : 0)
            width: parent.width - 2 * inset
            height: parent.height - y - inset
            clip: true

            // Strona leży na karcie z zaokrąglonymi rogami (maska)
            layer.enabled: !win.pageFullScreen && GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: contentMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            Repeater {
                id: pages
                model: tabs
                delegate: BrowserTab {
                    id: page
                    required property int index
                    required property string startUrl
                    required property bool lazyLoad
                    required property bool fromPage
                    anchors.fill: parent
                    visible: index === win.current
                    profile: win.profile
                    privateMode: win.privateMode
                    initialUrl: startUrl
                    lazy: lazyLoad
                    adopted: fromPage

                    onPageTitleChanged: { if (started) { tabs.setProperty(index, "title", pageTitle); sessionTimer.restart(); } }
                    onPageIconChanged: tabs.setProperty(index, "icon", pageIcon)
                    onLoadingChanged: tabs.setProperty(index, "loading", loading)
                    onPageUrlChanged: sessionTimer.restart()
                    Connections {
                        target: page.view
                        function onRecentlyAudibleChanged() { tabs.setProperty(page.index, "audible", page.view.recentlyAudible); }
                        function onAudioMutedChanged() { tabs.setProperty(page.index, "muted", page.view.audioMuted); }
                        function onPdfPrintingFinished(path, ok) {
                            if (ok) win.toastFile("Zapisano PDF w Pobranych", path);
                            else toast.show("Nie udało się zapisać PDF");
                        }
                    }
                    onVisited: (url, title) => Browser.addVisit(url, title)
                    onPermissionAsked: (permission) => { win.activate(index); win.pendingPermission = permission; }
                    onNewWindow: (request) => {
                        const bg = request.destination === WebEngineNewWindowRequest.InNewBackgroundTab;
                        const t = win.newTab("", bg, { adopted: true, afterCurrent: true });
                        if (t) request.openIn(t.view);
                    }
                    onFullScreen: (request) => {
                        request.accept();
                        if (request.toggleOn) {
                            win.wasMaximized = win.visibility === Window.Maximized;
                            win.pageFullScreen = true;
                            win.showFullScreen();
                            fsHint.show();
                        } else {
                            win.pageFullScreen = false;
                            if (win.wasMaximized) win.showMaximized(); else win.showNormal();
                        }
                    }
                    onContextMenu: (request) => win.showPageMenu(request)
                    onFindResult: (active, total) => { findBar.active = active; findBar.total = total; }
                    onOpenRequested: (url, background) => win.newTab(url, background, { afterCurrent: true })
                    onCloseRequested: win.closeTab(index)
                }
            }

            // ——— Szukaj na stronie (Ctrl+F) ———
            Rectangle {
                id: findBar
                property bool shown: false
                property int active: 0
                property int total: 0
                function openBar() {
                    if (!win.cur || win.cur.blank || win.cur.internal) return;
                    shown = true;
                    findField.forceActiveFocus();
                    findField.selectAll();
                    if (findField.text) find(false);
                }
                function closeBar() { shown = false; if (win.cur) { win.cur.view.findText(""); win.cur.view.forceActiveFocus(); } }
                function find(back) { if (win.cur) win.cur.view.findText(findField.text, back ? WebEngineView.FindBackward : 0); }
                anchors.right: parent.right; anchors.rightMargin: 16
                y: shown ? 12 : -height - 10
                visible: y > -height
                Behavior on y { NumberAnimation { duration: 120; easing.type: Easing.OutQuint } }
                width: 360; height: 46; radius: 23
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
                layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.6; shadowVerticalOffset: 6; shadowColor: Theme.shadow }
                Icon { x: 16; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 15; color: Theme.text2 }
                TextInput {
                    id: findField
                    x: 40; width: 170
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                    selectionColor: Theme.accentSoft
                    onTextEdited: findBar.find(false)
                    Keys.onReturnPressed: (e) => findBar.find(e.modifiers & Qt.ShiftModifier)
                    Keys.onEscapePressed: findBar.closeBar()
                    Text { visible: !findField.text; text: "Szukaj na stronie"; color: Theme.text2; font: findField.font }
                }
                Text {
                    anchors.right: findNav.left; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    visible: findField.text !== ""
                    text: findBar.total ? findBar.active + " z " + findBar.total : "brak"
                    color: findBar.total ? Theme.text2 : Theme.danger; font.family: Theme.font; font.pixelSize: 12
                    font.features: { "tnum": 1 }
                }
                Row {
                    id: findNav
                    anchors.right: parent.right; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    ToolBtn { icon: "up"; width: 30; onClicked: findBar.find(true) }
                    ToolBtn { icon: "chevronDown"; width: 30; onClicked: findBar.find(false) }
                    ToolBtn { icon: "close"; width: 30; onClicked: findBar.closeBar() }
                }
            }

            // ——— Komunikat (np. „Dodano do ulubionych”) ———
            Rectangle {
                id: toast
                property string text
                property string file
                function show(t) { text = t; file = ""; shown = true; toastTimer.restart(); }
                property bool shown: false
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - (shown ? height + 22 : -10)
                visible: y < parent.height
                Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutQuint } }
                width: toastRow.implicitWidth + 28; height: 42; radius: 21
                color: Theme.dark ? "#F2F3F6" : "#17181D"
                Row {
                    id: toastRow
                    anchors.centerIn: parent
                    spacing: 14
                    Text { anchors.verticalCenter: parent.verticalCenter; text: toast.text; color: Theme.dark ? "#17181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: toast.file !== ""
                        text: "Otwórz"
                        color: Theme.dark ? Qt.darker(Theme.accent, 1.2) : Qt.lighter(Theme.accent, 1.5)
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: { Qt.openUrlExternally("file://" + toast.file); toast.shown = false; } }
                    }
                }
                Timer { id: toastTimer; interval: 3200; onTriggered: toast.shown = false }
            }

            // Pełny ekran strony: krótka podpowiedź u góry
            Rectangle {
                id: fsHint
                function show() { opacity = 1; fsTimer.restart(); }
                anchors.horizontalCenter: parent.horizontalCenter
                y: 24
                width: fsText.implicitWidth + 36; height: 44; radius: 22
                color: Qt.rgba(0.08, 0.08, 0.1, 0.88)
                opacity: 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Text { id: fsText; anchors.centerIn: parent; text: "Naciśnij Esc, aby wyjść z pełnego ekranu"; color: "white"; font.family: Theme.font; font.pixelSize: 13 }
                Timer { id: fsTimer; interval: 2600; onTriggered: fsHint.opacity = 0 }
            }
        }
        Rectangle {
            id: contentMask
            visible: false
            layer.enabled: true
            width: content.width; height: content.height
            radius: content.cardRadius
            color: "black"
        }

        // ——— Podpowiedzi pod paskiem adresu ———
        Rectangle {
            id: suggest
            property var items: []
            property var remote: []
            property string remoteFor: ""
            property int index: 0
            function close() { items = []; remote = []; index = 0; }
            function move(d) { if (items.length) index = (index + d + items.length) % items.length; }
            function update(text) {
                const t = text.trim();
                if (!t) { close(); return; }
                rebuild(t);
                if (!win.privateMode) fetchTimer.restart();
            }
            function rebuild(t) {
                const low = t.toLowerCase();
                const go = Browser.fixup(t);
                const out = [{ kind: Browser.isSearchUrl(go) ? "search" : "go", label: t, url: go }];
                const seen = {};
                seen[go] = true;
                // Otwarte karty
                for (let i = 0; i < tabs.count && out.length < 3; ++i) {
                    const p = win.tabAt(i);
                    if (!p || i === win.current || p.blank) continue;
                    if (p.pageTitle.toLowerCase().indexOf(low) >= 0 || Urls.pretty(p.pageUrl).toLowerCase().indexOf(low) >= 0)
                        out.push({ kind: "tab", label: p.pageTitle, url: p.pageUrl, tab: i });
                }
                // Ulubione
                for (const b of Browser.bookmarks) {
                    if (out.length >= 5) break;
                    if (seen[b.url]) continue;
                    if ((b.title || "").toLowerCase().indexOf(low) >= 0 || Urls.pretty(b.url).toLowerCase().indexOf(low) >= 0) {
                        seen[b.url] = true;
                        out.push({ kind: "bookmark", label: b.title || Urls.host(b.url), url: b.url });
                    }
                }
                // Historia
                for (const h of Browser.matchHistory(t, 6)) {
                    if (out.length >= 7) break;
                    if (seen[h.url]) continue;
                    seen[h.url] = true;
                    out.push({ kind: "history", label: h.title || Urls.pretty(h.url), url: h.url });
                }
                // Podpowiedzi wyszukiwarki
                if (remoteFor === t)
                    for (const s of remote) {
                        if (out.length >= 10) break;
                        if (s.toLowerCase() === low) continue;
                        out.push({ kind: "suggest", label: s, url: Browser.searchUrl(s) });
                    }
                items = out;
                index = 0;
            }
            // „you” → „youtube.com”: dopisana końcówka zostaje zaznaczona, Backspace ją usuwa
            function inlineComplete(t) {
                if (/\s/.test(t) || t.length < 2) return;
                const low = t.toLowerCase();
                for (const h of Browser.matchHistory(t, 4)) {
                    const bare = Urls.pretty(h.url);
                    const host = bare.split("/")[0];
                    if (host.toLowerCase().indexOf(low) === 0) {
                        field.text = t + host.slice(t.length);
                        field.select(t.length, field.text.length);
                        return;
                    }
                }
            }
            function accept(mods) {
                const it = items[index];
                const background = mods & Qt.AltModifier;
                close();
                if (it && it.kind === "tab") { win.activate(it.tab); return; }
                const url = it && index > 0 ? it.url : Browser.fixup(field.text);
                if (!url) return;
                if (background) { win.newTab(url, false, { afterCurrent: true }); return; }
                if (win.cur) {
                    win.cur.load(url);
                    if (!Urls.internal(url)) win.cur.view.forceActiveFocus();
                    else frame.forceActiveFocus();
                }
            }
            Timer {
                id: fetchTimer
                interval: 140
                onTriggered: {
                    const t = field.typed.trim();
                    if (!t || !field.activeFocus || /^[a-z]+:\/\//i.test(t)) return;
                    const xhr = new XMLHttpRequest();
                    xhr.onreadystatechange = () => {
                        if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return;
                        try {
                            const data = JSON.parse(xhr.responseText);
                            if (field.typed.trim() !== t) return;
                            suggest.remote = (data[1] || []).slice(0, 5).map(s => typeof s === "string" ? s : (s.phrase || ""));
                            suggest.remoteFor = t;
                            const keep = suggest.index;
                            suggest.rebuild(t);
                            suggest.index = keep;
                        } catch (e) {}
                    };
                    xhr.open("GET", Browser.suggestUrl(t));
                    xhr.send();
                }
            }
            visible: items.length > 0 && field.activeFocus
            x: address.mapToItem(frame, 0, 0).x
            y: address.mapToItem(frame, 0, 0).y + address.height + 6
            width: address.width
            height: sugCol.implicitHeight + 12
            radius: 18
            color: Theme.surface
            border.width: 1; border.color: Theme.edge
            z: 50
            layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowVerticalOffset: 10; shadowColor: Theme.shadow }
            Column {
                id: sugCol
                x: 6; y: 6
                width: parent.width - 12
                Repeater {
                    model: suggest.items
                    delegate: Rectangle {
                        id: sug
                        required property var modelData
                        required property int index
                        width: sugCol.width; height: 40
                        radius: 20
                        color: suggest.index === index ? Theme.accentSoft : (sugArea.containsMouse ? Theme.hover : "transparent")
                        readonly property string kind: modelData.kind
                        Item {
                            id: sugIcon
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 18
                            Image {
                                anchors.fill: parent
                                visible: (sug.kind === "history" || sug.kind === "bookmark" || sug.kind === "go") && status === Image.Ready
                                source: sug.kind === "history" || sug.kind === "bookmark" || sug.kind === "go" ? Urls.favicon(sug.modelData.url) : ""
                                sourceSize: Qt.size(36, 36)
                                asynchronous: true
                            }
                            Icon {
                                anchors.centerIn: parent
                                visible: !(parent.children[0].visible)
                                d: sug.kind === "search" || sug.kind === "suggest" ? Icons.search
                                   : sug.kind === "tab" ? Icons.apps
                                   : sug.kind === "bookmark" ? Icons.star
                                   : sug.kind === "history" ? Icons.clock : Icons.globe
                                size: 15; color: Theme.text2
                            }
                        }
                        Text {
                            x: 42; width: parent.width - 52 - (tag.visible ? tag.width + 8 : 0)
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            textFormat: Text.StyledText
                            text: {
                                const m = sug.modelData;
                                const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
                                if (m.kind === "search") return esc(m.label) + "  <font color=\"" + Theme.text2 + "\">— szukaj w " + Browser.searchName + "</font>";
                                if (m.kind === "go") return esc(Urls.pretty(m.url));
                                if (m.kind === "suggest") return esc(m.label);
                                return esc(m.label) + "  <font color=\"" + Theme.text2 + "\">— " + esc(Urls.pretty(m.url)) + "</font>";
                            }
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 13
                        }
                        Rectangle {
                            id: tag
                            visible: sug.kind === "tab"
                            anchors.right: parent.right; anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: tagText.implicitWidth + 16; height: 22; radius: 11
                            color: Theme.fill
                            Text { id: tagText; anchors.centerIn: parent; text: "Przejdź do karty"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
                        }
                        MouseArea {
                            id: sugArea; anchors.fill: parent; hoverEnabled: true
                            onClicked: { suggest.index = sug.index; suggest.accept(0); }
                        }
                    }
                }
            }
        }

        // ——— Informacje o witrynie (kłódka) ———
        Popup {
            id: siteInfo
            anchorItem: siteButton
            contentWidth: 320
            readonly property string host: win.cur ? Urls.host(win.cur.pageUrl) : ""
            Column {
                width: parent.width
                spacing: 12
                Text { width: parent.width; text: siteInfo.host; elide: Text.ElideMiddle; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                InfoRow {
                    icon: win.cur && win.cur.secure ? "lock" : "info"
                    tintColor: win.cur && win.cur.secure ? "#1F9D55" : Theme.danger
                    title: win.cur && win.cur.secure ? "Połączenie jest bezpieczne" : "Połączenie nie jest zabezpieczone"
                    detail: win.cur && win.cur.secure ? "Dane, które tu wysyłasz, są szyfrowane." : "Nie wpisuj tu haseł ani numerów kart."
                }
                InfoRow {
                    icon: "eye"
                    tintColor: Theme.accent
                    title: !Browser.blockTrackers ? "Blokowanie śledzenia jest wyłączone"
                           : win.cur && win.cur.blocked ? "Zablokowano " + win.cur.blocked + " " + (win.cur.blocked === 1 ? "element śledzący" : win.cur.blocked < 5 ? "elementy śledzące" : "elementów śledzących")
                           : "Nie znaleziono elementów śledzących"
                    detail: "Reklamy i analityka z zewnętrznych serwerów"
                }
                Rectangle { width: parent.width; height: 1; color: Theme.line }
                Item {
                    width: parent.width; height: 34
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Powiększenie"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        ToolBtn { icon: "minimize"; width: 32; onClicked: win.zoom(-0.1) }
                        Text {
                            width: 48; anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignHCenter
                            text: win.cur ? Math.round(win.cur.view.zoomFactor * 100) + "%" : ""
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                            MouseArea { anchors.fill: parent; onClicked: win.zoom(0) }
                        }
                        ToolBtn { icon: "plus"; width: 32; onClicked: win.zoom(0.1) }
                    }
                }
            }
        }

        // ——— Pobrane (dymek) ———
        Popup {
            id: downloadsPopup
            anchorItem: dlButton.visible ? dlButton : menuButton
            alignRight: true
            contentWidth: 380
            function open(on) {
                shown = on;
                if (on) { Qt.callLater(place); hideTimer.restart(); }
            }
            Timer { id: hideTimer; interval: 4500; onTriggered: if (!downloadsPopup.hovered) downloadsPopup.shown = false }
            Column {
                width: parent.width
                spacing: 4
                Item {
                    width: parent.width; height: 30
                    Text { anchors.verticalCenter: parent.verticalCenter; x: 4; text: "Pobrane"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Pokaż wszystkie"
                        color: Theme.accentText; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: { downloadsPopup.shown = false; win.openInternal("downloads"); } }
                    }
                }
                Repeater {
                    model: Browser.downloads.slice(0, 5)
                    delegate: DownloadRow { width: downloadsPopup.contentWidth }
                }
            }
        }

        // ——— Menu (strona, karta, główne) ———
        ContextMenu {
            id: menu
            onTriggered: (a) => win.runMenuAction(a)
        }
    }

    // ——— Karta na pasku kart ———
    component TabButton: Item {
        id: tb
        required property int index
        required property string title
        required property string icon
        required property bool loading
        required property bool audible
        required property bool muted
        readonly property bool active: index === win.current
        width: tabRow.tabWidth; height: tabStrip.height

        // Aktywna karta ma kolor panelu strony i łączy się z nim od dołu
        Rectangle {
            id: tabBg
            y: 2; width: parent.width; height: parent.height - 8
            radius: height / 2
            color: tb.active ? Theme.surface : (tabArea.containsMouse ? Theme.hover : "transparent")
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Item {
            id: favicon
            x: 13; y: tabBg.y + (tabBg.height - height) / 2
            width: 16; height: 16
            Image {
                anchors.fill: parent
                source: tb.icon
                visible: !!tb.icon && !tb.loading
                sourceSize: Qt.size(32, 32)
            }
            Icon {
                anchors.centerIn: parent
                visible: !tb.icon && !tb.loading
                d: Icons.globe; size: 14; color: Theme.text2
            }
            // Kręcące się kółko podczas wczytywania
            Shape {
                anchors.fill: parent
                visible: tb.loading
                preferredRendererType: Shape.CurveRenderer
                RotationAnimation on rotation { running: tb.loading; from: 0; to: 360; duration: 800; loops: Animation.Infinite }
                ShapePath {
                    strokeColor: Theme.accent; strokeWidth: 2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 8; centerY: 8; radiusX: 6; radiusY: 6; startAngle: 0; sweepAngle: 260 }
                }
            }
        }
        // Głośnik: karta gra dźwięk (kliknięcie wycisza)
        HoverButton {
            id: soundBtn
            anchors.left: favicon.right; anchors.leftMargin: 4
            y: tabBg.y + (tabBg.height - height) / 2
            width: visible ? 22 : 0; height: 22; radius: 6
            visible: tb.audible || tb.muted
            onClicked: { const p = win.tabAt(tb.index); if (p) p.view.audioMuted = !p.view.audioMuted; }
            Icon { anchors.centerIn: parent; d: tb.muted ? Icons.volumeOff : Icons.volume; size: 13; color: tb.muted ? Theme.text2 : Theme.accentText }
        }
        Text {
            anchors.left: soundBtn.visible ? soundBtn.right : favicon.right; anchors.leftMargin: 8
            anchors.right: closeBtn.left; anchors.rightMargin: 4
            y: tabBg.y + (tabBg.height - height) / 2
            text: tb.title
            elide: Text.ElideRight
            color: tb.active ? Theme.text : Theme.text2
            font.family: Theme.font; font.pixelSize: 13
            font.weight: tb.active ? Font.DemiBold : Font.Normal
        }
        MouseArea {
            id: tabArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            property real pressX: 0
            property bool moved: false
            onPressed: (m) => {
                pressX = m.x; moved = false;
                if (m.button === Qt.LeftButton) win.activate(tb.index);
            }
            onPositionChanged: (m) => {
                if (!(m.buttons & Qt.LeftButton)) return;
                if (!moved && Math.abs(m.x - pressX) < 8) return;
                moved = true;
                // Przeciąganie: karta zmienia miejsce, gdy kursor wejdzie na sąsiednią
                const px = tb.mapToItem(tabRow, m.x, 0).x;
                const to = Math.max(0, Math.min(tabs.count - 1, Math.floor(px / (tabRow.tabWidth + 4))));
                if (to !== tb.index) win.moveTab(tb.index, to);
            }
            onClicked: (m) => {
                if (m.button === Qt.MiddleButton) win.closeTab(tb.index);
                else if (m.button === Qt.RightButton) win.showTabMenu(tb.index, tb.mapToItem(frame, m.x, m.y));
            }
            onDoubleClicked: (m) => { if (m.button === Qt.LeftButton) win.duplicateTab(tb.index); }
        }
        Rectangle {
            id: closeBtn
            anchors.right: parent.right; anchors.rightMargin: 9
            y: tabBg.y + (tabBg.height - height) / 2
            width: 22; height: 22; radius: 11
            visible: tb.active || tabArea.containsMouse || closeArea.containsMouse
            color: closeArea.containsMouse ? Theme.hover : "transparent"
            Icon { anchors.centerIn: parent; d: Icons.close; size: 11; stroke: 2; color: Theme.text2 }
            MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; onClicked: win.closeTab(tb.index) }
        }
    }

    // Dymek pod przyciskiem paska (pobrane, informacje o witrynie)
    component Popup: Item {
        id: pop
        property Item anchorItem
        property bool alignRight: false
        property bool shown: false
        readonly property bool hovered: popHover.hovered
        property real contentWidth: 300
        default property alias body: popBody.data
        anchors.fill: parent
        z: 60
        visible: shown || box.opacity > 0
        // Miejsce liczone przy otwarciu — przycisk mógł się przesunąć albo dopiero pojawić
        onShownChanged: if (shown) place()
        function place() {
            if (!anchorItem) return;
            const at = anchorItem.mapToItem(pop, 0, anchorItem.height);
            box.x = Math.max(8, Math.min(width - box.width - 8, alignRight ? at.x + anchorItem.width - box.width : at.x));
            box.y = at.y + 8;
        }
        MouseArea { anchors.fill: parent; enabled: pop.shown; onPressed: pop.shown = false }
        Rectangle {
            id: box
            width: pop.contentWidth + 28
            height: popBody.childrenRect.height + 28
            radius: 12
            color: Theme.surface
            border.width: 1; border.color: Theme.edge
            opacity: pop.shown ? 1 : 0
            scale: pop.shown ? 1 : 0.96
            transformOrigin: pop.alignRight ? Item.TopRight : Item.TopLeft
            Behavior on opacity { NumberAnimation { duration: 90 } }
            Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutQuint } }
            layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.9; shadowVerticalOffset: 12; shadowColor: Theme.shadow }
            HoverHandler { id: popHover }
            MouseArea { anchors.fill: parent }
            Item { id: popBody; x: 14; y: 14; width: pop.contentWidth }
        }
    }

    component InfoRow: Row {
        id: ir
        property string icon
        property color tintColor
        property string title
        property string detail
        spacing: 12
        Rectangle {
            width: 34; height: 34; radius: 11
            color: Qt.rgba(ir.tintColor.r, ir.tintColor.g, ir.tintColor.b, 0.14)
            Icon { anchors.centerIn: parent; d: Icons[ir.icon] || ""; size: 16; color: ir.tintColor }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text { text: ir.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
            Text { text: ir.detail; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        }
    }

    function toastFile(text, path) {
        toast.show(text);
        toast.file = path;
    }

    // ——— Menu ———
    function showMainMenu() {
        menuKind = "main";
        const p = menuButton.mapToItem(frame, menuButton.width, menuButton.height + 6);
        const page = !!cur && !cur.blank && !cur.internal;
        const z = cur && !cur.internal ? Math.round(cur.view.zoomFactor * 100) : 100;
        menu.openAt(p.x - 250, p.y, [
            { label: "Nowa karta", icon: "plus", shortcut: "Ctrl+T", action: "newTab" },
            { label: "Nowe okno", icon: "desktop", shortcut: "Ctrl+N", action: "newWindow" },
            { label: "Nowe okno prywatne", icon: "eye", shortcut: "Ctrl+Shift+N", action: "privateWindow" },
            { separator: true },
            { label: "Historia", icon: "clock", shortcut: "Ctrl+H", action: "history" },
            { label: "Pobrane", icon: "download", shortcut: "Ctrl+J", action: "downloads" },
            { label: (Browser.showFavoritesBar ? "Ukryj" : "Pokaż") + " pasek ulubionych", icon: "star", shortcut: "Ctrl+Shift+B", action: "favBar" },
            { separator: true },
            { label: "Szukaj na stronie", icon: "search", shortcut: "Ctrl+F", action: "find", enabled: page },
            { label: "Powiększ (" + z + "%)", icon: "plus", shortcut: "Ctrl++", action: "zoomIn", enabled: page },
            { label: "Pomniejsz", icon: "minimize", shortcut: "Ctrl+−", action: "zoomOut", enabled: page },
            { label: "Zapisz jako PDF", icon: "doc", shortcut: "Ctrl+P", action: "pdf", enabled: page },
            { label: "Zapisz stronę", icon: "download", shortcut: "Ctrl+S", action: "save", enabled: page },
            { label: "Zainstaluj jako aplikację", icon: "webapp", action: "installApp", enabled: page && !privateMode },
            { label: "Narzędzia dewelopera", icon: "code", shortcut: "F12", action: "devtools", enabled: page },
            { separator: true },
            { label: "Ustawienia", icon: "gear", action: "settings" }
        ]);
    }
    function showTabMenu(i, p) {
        menuKind = "tab";
        menuTab = i;
        const t = tabAt(i);
        menu.openAt(p.x, p.y, [
            { label: "Nowa karta obok", icon: "plus", action: "tabNew" },
            { label: "Odśwież", icon: "reload", action: "tabReload" },
            { label: "Duplikuj", icon: "copy", action: "tabDuplicate" },
            { label: t && t.view.audioMuted ? "Włącz dźwięk" : "Wycisz kartę", icon: t && t.view.audioMuted ? "volume" : "volumeOff", action: "tabMute" },
            { separator: true },
            { label: "Zamknij", icon: "close", shortcut: "Ctrl+W", action: "tabClose" },
            { label: "Zamknij pozostałe karty", icon: "close", action: "tabCloseOthers", enabled: tabs.count > 1 },
            { label: "Zamknij karty po prawej", icon: "close", action: "tabCloseRight", enabled: i < tabs.count - 1 },
            { label: "Przywróć zamkniętą kartę", icon: "undo", shortcut: "Ctrl+Shift+T", action: "tabReopen", enabled: closedTabs.length > 0 }
        ]);
    }
    function showPageMenu(request) {
        menuKind = "page";
        menuRequest = request;
        const p = content.mapToItem(frame, request.position.x, request.position.y);
        const items = [];
        if (request.linkUrl.toString()) {
            items.push({ label: "Otwórz w nowej karcie", icon: "plus", action: "linkTab" });
            items.push({ label: "Otwórz w nowym oknie", icon: "desktop", action: "linkWindow" });
            if (!privateMode) items.push({ label: "Otwórz w oknie prywatnym", icon: "eye", action: "linkPrivate" });
            items.push({ label: "Zapisz link jako…", icon: "download", action: "linkSave" });
            items.push({ label: "Kopiuj adres linku", icon: "copy", action: "copyLink" });
            items.push({ separator: true });
        }
        if (request.mediaType === ContextMenuRequest.MediaTypeImage) {
            items.push({ label: "Otwórz obraz w nowej karcie", icon: "image", action: "imageTab" });
            items.push({ label: "Zapisz obraz", icon: "download", action: "saveImage" });
            items.push({ label: "Kopiuj obraz", icon: "copy", action: "copyImage" });
            items.push({ label: "Kopiuj adres obrazu", icon: "copy", action: "copyImageUrl" });
            items.push({ separator: true });
        } else if (request.mediaType === ContextMenuRequest.MediaTypeVideo || request.mediaType === ContextMenuRequest.MediaTypeAudio) {
            items.push({ label: "Zapisz plik", icon: "download", action: "saveMedia" });
            items.push({ label: "Kopiuj adres pliku", icon: "copy", action: "copyMediaUrl" });
            items.push({ separator: true });
        }
        if (request.isContentEditable) {
            items.push({ label: "Cofnij", icon: "undo", shortcut: "Ctrl+Z", action: "undo" });
            items.push({ label: "Wytnij", icon: "scissors", shortcut: "Ctrl+X", action: "cut", enabled: !!request.selectedText });
            items.push({ label: "Kopiuj", icon: "copy", shortcut: "Ctrl+C", action: "copy", enabled: !!request.selectedText });
            items.push({ label: "Wklej", icon: "paste", shortcut: "Ctrl+V", action: "paste" });
            items.push({ label: "Zaznacz wszystko", icon: "check", shortcut: "Ctrl+A", action: "selectAll" });
        } else if (request.selectedText) {
            const s = request.selectedText.trim();
            items.push({ label: "Kopiuj", icon: "copy", shortcut: "Ctrl+C", action: "copy" });
            items.push({ label: "Szukaj „" + s.slice(0, 22) + (s.length > 22 ? "…" : "") + "”", icon: "search", action: "searchSel" });
        } else if (!request.linkUrl.toString() && request.mediaType === ContextMenuRequest.MediaTypeNone) {
            items.push({ label: "Wstecz", icon: "back", shortcut: "Alt+←", action: "back", enabled: cur.view.canGoBack });
            items.push({ label: "Dalej", icon: "forward", shortcut: "Alt+→", action: "forward", enabled: cur.view.canGoForward });
            items.push({ label: "Odśwież", icon: "reload", shortcut: "Ctrl+R", action: "reload" });
            items.push({ separator: true });
            items.push({ label: Browser.isBookmarked(cur.pageUrl) ? "Usuń z ulubionych" : "Dodaj do ulubionych", icon: "star", shortcut: "Ctrl+D", action: "favorite" });
            items.push({ label: "Zapisz jako PDF", icon: "doc", shortcut: "Ctrl+P", action: "pdf" });
            items.push({ label: "Pokaż źródło strony", icon: "code", shortcut: "Ctrl+U", action: "source" });
        }
        if (items.length && items[items.length - 1].separator) items.pop();
        items.push({ separator: true });
        items.push({ label: "Zbadaj", icon: "tool", shortcut: "F12", action: "inspect" });
        menu.openAt(p.x, p.y, items);
    }
    function runMenuAction(a) {
        if (menuKind === "main") {
            if (a === "newTab") newTab("");
            else if (a === "newWindow") Browser.openWindow([], false);
            else if (a === "privateWindow") Browser.openWindow([], true);
            else if (a === "history") openInternal("history");
            else if (a === "downloads") openInternal("downloads");
            else if (a === "favBar") Browser.showFavoritesBar = !Browser.showFavoritesBar;
            else if (a === "find") findBar.openBar();
            else if (a === "zoomIn") zoom(0.1);
            else if (a === "zoomOut") zoom(-0.1);
            else if (a === "pdf") savePdf();
            else if (a === "save") savePage();
            else if (a === "installApp") installAsApp();
            else if (a === "devtools") cur.devTools = !cur.devTools;
            else if (a === "settings") openInternal("settings");
            return;
        }
        if (menuKind === "tab") {
            const i = menuTab, t = tabAt(i);
            if (a === "tabNew") { current = i; newTab("", false, { afterCurrent: true }); }
            else if (a === "tabReload" && t) t.reload();
            else if (a === "tabDuplicate") duplicateTab(i);
            else if (a === "tabMute" && t) t.view.audioMuted = !t.view.audioMuted;
            else if (a === "tabClose") closeTab(i);
            else if (a === "tabCloseOthers") closeOthers(i);
            else if (a === "tabCloseRight") closeRight(i);
            else if (a === "tabReopen") reopenTab();
            return;
        }
        const r = menuRequest, v = cur ? cur.view : null;
        if (!v || !r) return;
        if (a === "linkTab") newTab(r.linkUrl.toString(), true, { afterCurrent: true });
        else if (a === "linkWindow") Browser.openWindow([r.linkUrl.toString()], privateMode);
        else if (a === "linkPrivate") Browser.openWindow([r.linkUrl.toString()], true);
        else if (a === "linkSave") v.triggerWebAction(WebEngineView.DownloadLinkToDisk);
        else if (a === "copyLink") v.triggerWebAction(WebEngineView.CopyLinkToClipboard);
        else if (a === "imageTab") newTab(r.mediaUrl.toString(), true, { afterCurrent: true });
        else if (a === "saveImage") v.triggerWebAction(WebEngineView.DownloadImageToDisk);
        else if (a === "copyImage") v.triggerWebAction(WebEngineView.CopyImageToClipboard);
        else if (a === "copyImageUrl") v.triggerWebAction(WebEngineView.CopyImageUrlToClipboard);
        else if (a === "saveMedia") v.triggerWebAction(WebEngineView.DownloadMediaToDisk);
        else if (a === "copyMediaUrl") v.triggerWebAction(WebEngineView.CopyMediaUrlToClipboard);
        else if (a === "undo") v.triggerWebAction(WebEngineView.Undo);
        else if (a === "cut") v.triggerWebAction(WebEngineView.Cut);
        else if (a === "copy") v.triggerWebAction(WebEngineView.Copy);
        else if (a === "paste") v.triggerWebAction(WebEngineView.Paste);
        else if (a === "selectAll") v.triggerWebAction(WebEngineView.SelectAll);
        else if (a === "searchSel") newTab(Browser.searchUrl(r.selectedText.trim()), false, { afterCurrent: true });
        else if (a === "back") v.goBack();
        else if (a === "forward") v.goForward();
        else if (a === "reload") cur.reload();
        else if (a === "favorite") toggleFavorite();
        else if (a === "pdf") savePdf();
        else if (a === "source") newTab("view-source:" + cur.pageUrl, false, { afterCurrent: true });
        else if (a === "inspect") { cur.devTools = true; v.triggerWebAction(WebEngineView.InspectElement); }
    }
}
