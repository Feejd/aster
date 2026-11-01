pragma ComponentBehavior: Bound
import QtCore
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQml.Models
import QtWebEngine
import Aster.Ui
import Aster.WebApps

// Okno aplikacji webowej. Ma wyglądać jak zwykły program, nie jak przeglądarka:
//  • pasek tytułu w kolorze aplikacji (z manifestu albo theme-color strony), bez paska adresu
//  • ekran powitalny z ikoną, póki strona się wczytuje; ładny ekran „brak internetu”
//  • linki do innych stron otwierają się w przeglądarce, logowanie (Google, Microsoft…) zostaje w oknie
//  • powiadomienia systemowe, liczba nieprzeczytanych na ikonie w doku, własny profil (osobne logowanie)
//  • cienkie, nienachalne paski przewijania i zapamiętany rozmiar okna
Window {
    id: win
    required property var app
    required property Runtime runtime

    width: store.w + 2 * m
    height: store.h + 2 * m
    minimumWidth: 420 + 2 * m
    minimumHeight: 360 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: app.name

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed || pageFullScreen ? 0 : 26
    readonly property real r: maxed || pageFullScreen ? 0 : 14
    property bool pageFullScreen: false
    readonly property bool debug: Qt.application.arguments.indexOf("--debug") >= 0

    // ——— Natywna nakładka (Adapters.js) — aplikacja jak zrobiona przez twórcę serwisu ———
    readonly property var adapter: Adapters.find(hostOf(app.url))
    readonly property string currentUrl: web.url.toString()
    readonly property color brand: adapter ? adapter.accent : Theme.accent
    // Tożsamość ze strony: logo, menu (sekcje, ikony, awatary kanałów), czcionki
    property string pageLogo: ""
    property var pageSections: []
    property var pageFontUrls: []
    property var bodyFonts: []
    property int fontsVersion: 0
    function firstFont(list) {
        fontsVersion;
        const fams = Qt.fontFamilies();
        for (const f of (list || []))
            if (fams.indexOf(f) >= 0) return f;
        return Theme.font;
    }
    readonly property string uiFont: adapter ? firstFont((adapter.fonts ? adapter.fonts.body : []).concat(bodyFonts)) : Theme.font
    readonly property string titleFont: adapter && adapter.fonts ? firstFont(adapter.fonts.title) : uiFont
    Instantiator {
        model: win.pageFontUrls
        delegate: FontLoader {
            required property string modelData
            source: modelData
            onStatusChanged: if (status === FontLoader.Ready) win.fontsVersion++
        }
    }
    readonly property var adapterNav: {
        if (!adapter) return [];
        if (pageSections.length) {
            const out = [];
            pageSections.forEach(s => {
                if (s.title) out.push({ section: true, label: s.title });
                s.items.forEach(it => out.push({ id: it.id, label: it.label, icon: it.icon, img: it.img, active: it.active, fromPage: true }));
            });
            return out;
        }
        const active = Adapters.activeUrl(adapter, currentUrl);
        const out = [];
        adapter.nav.forEach(s => {
            if (s.section) out.push({ section: true, label: s.section });
            s.items.forEach(it => out.push({ id: it.url, label: it.label, iconName: it.icon, active: it.url === active }));
        });
        return out;
    }
    readonly property string viewTitle: adapter ? (adapter.title(currentUrl, web.title || "") || Adapters.titleFor(adapter, currentUrl) || app.name) : app.name
    property string avatarSrc: ""
    // Na stronie wyników zapytanie zostaje w polu wyszukiwania (jak w natywnej aplikacji)
    onCurrentUrlChanged: {
        if (!adapter || adField.activeFocus) return;
        const mm = /[?&](?:search_query|q)=([^&]*)/.exec(currentUrl);
        adField.text = mm ? decodeURIComponent(mm[1].replace(/\+/g, " ")) : "";
    }
    Connections {
        target: Theme
        function onDarkChanged() {
            if (win.adapter && win.adapter.dark) web.runJavaScript(win.adapter.dark.replace("%d", Theme.dark ? "true" : "false"));
        }
    }
    // Do testów: --eval "<js>" wykonuje skrypt na stronie 2 s po pierwszym wczytaniu
    readonly property string evalScript: {
        const i = Qt.application.arguments.indexOf("--eval");
        return i >= 0 ? Qt.application.arguments[i + 1] : "";
    }
    Timer {
        id: evalTimer
        interval: 2000
        onTriggered: web.runJavaScript(win.evalScript, (r) => console.log("[aster] eval:", r))
    }
    function adapterGo(url) {
        web.runJavaScript("window.__aster ? window.__aster.go(" + JSON.stringify(url) + ") : location.assign(" + JSON.stringify(url) + ")");
    }

    // ——— Kolor aplikacji i czytelny tekst na nim ———
    property string pageTheme: ""
    readonly property color barColor: {
        if (adapter) return "transparent";
        const c = pageTheme || app.themeColor || "";
        if (/^#/i.test(c)) return c;
        return topbarBgCss ? cssColor(topbarBgCss) : Theme.windowGlass;
    }
    readonly property bool barTinted: !adapter && (pageTheme || app.themeColor || topbarBgCss || "") !== ""
    readonly property real barLuma: 0.299 * barColor.r + 0.587 * barColor.g + 0.114 * barColor.b
    readonly property color barText: !barTinted ? Theme.text : (barLuma > 0.62 ? "#16181D" : "white")
    readonly property color barHover: barLuma > 0.62 || !barTinted ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(1, 1, 1, 0.16)

    Settings {
        id: store
        category: "window"
        property int w: 1100
        property int h: 760
        property bool nativeNav: true       // nawigacja strony w pasku bocznym / pasku tytułu Aster
        property bool integrated: true      // górny pasek strony jest paskiem tytułu okna
        property bool systemFont: true      // czcionka systemu (Inter) w treści strony
    }

    // ——— Nawigacja strony przeniesiona do okna (z native.js) ———
    property var navSidebar: []
    property var navTop: []
    property int pageTopbar: 0
    property var navPrimary: null           // wyróżniony przycisk menu („Napisz”)
    property var navSearch: null            // pole wyszukiwania strony
    property string pageBgCss: ""
    property string sideBgCss: ""
    property string topbarBgCss: ""

    // ——— Kolory strony → kolory okna ———
    function cssColor(c) {
        const mm = /rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:[,\s/]+([\d.]+))?/.exec(c || "");
        return mm ? Qt.rgba(mm[1] / 255, mm[2] / 255, mm[3] / 255, mm[4] === undefined ? 1 : parseFloat(mm[4])) : "transparent";
    }
    function luma(c) { return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b; }
    readonly property color pageColor: pageBgCss ? cssColor(pageBgCss) : (app.backgroundColor || Theme.pane)
    readonly property bool pageDark: luma(pageColor) < 0.45
    readonly property color sideBase: sideBgCss ? cssColor(sideBgCss) : pageColor
    readonly property bool sideDark: adapter ? Theme.dark : luma(sideBase) < 0.45
    readonly property color sideFill: adapter ? "transparent" : Qt.alpha(sideBase, 0.9)
    readonly property color sideText: sideDark ? "#ECEEF3" : "#16181D"
    readonly property color sideText2: sideDark ? "#A2A9B6" : "#5B6270"
    readonly property color sideHover: sideDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.055)
    readonly property bool neutralActive: !!adapter && adapter.activeStyle === "neutral"
    readonly property color sideActive: neutralActive ? (sideDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.06)) : Qt.alpha(brand, sideDark ? 0.3 : 0.12)
    readonly property color sideActiveText: neutralActive ? sideText : (sideDark ? Qt.lighter(brand, 1.5) : brand)
    readonly property color sideLine: sideDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.07)
    readonly property bool showSidebar: !pageFullScreen && (!!adapter || (store.nativeNav && navSidebar.length >= 3))
    readonly property bool showTopnav: !adapter && store.nativeNav && !showSidebar && navTop.length >= 3 && !pageFullScreen
    readonly property bool integratedBar: !adapter && store.integrated && !showTopnav && !pageFullScreen && (pageTopbar > 0 || showSidebar)
    readonly property int sideWidth: showSidebar ? 232 : 0

    function navClick(id, fromPage) {
        if (adapter && !fromPage) { adapterGo(id); return; }
        web.runJavaScript("window.__aster && window.__aster.click('" + id + "')");
    }
    function fetchSuggestions(text) {
        const q = text.trim();
        if (!q || !adapter || !adapter.search.suggest) { suggestBox.items = []; return; }
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200 || adField.text.trim() !== q) return;
            try {
                const data = JSON.parse(xhr.responseText);
                suggestBox.items = (data[1] || []).slice(0, 8);
                suggestBox.index = -1;
            } catch (e) { suggestBox.items = []; }
        };
        xhr.open("GET", adapter.search.suggest.replace("%s", encodeURIComponent(q)));
        xhr.send();
    }
    function runAdapterSearch(text) {
        const q = (text || "").trim();
        if (!q) return;
        adField.text = q;
        suggestBox.items = [];
        adapterGo(adapter.search.url.replace("%s", encodeURIComponent(q)));
        web.forceActiveFocus();
    }
    function searchPage(text) {
        if (navSearch) web.runJavaScript("window.__aster && window.__aster.search('" + navSearch.id + "', " + JSON.stringify(text) + ")");
    }
    function submitSearch() {
        if (navSearch) web.runJavaScript("window.__aster && window.__aster.submit('" + navSearch.id + "')");
    }
    function setNativeNav(on) {
        store.nativeNav = on;
        web.runJavaScript("window.__aster && window.__aster.setEnabled(" + on + ")");
        if (!on) { navSidebar = []; navTop = []; }
    }
    // Ikona pozycji menu: SVG ze strony w kolorze Aster (data: URL)
    function svgUrl(svg, color) {
        if (!svg) return "";
        let t = svg.replace(/currentColor/g, color);
        if (!/xmlns=/.test(t)) t = t.replace("<svg", "<svg xmlns=\"http://www.w3.org/2000/svg\"");
        if (!/<svg[^>]*\sfill=/.test(t)) t = t.replace("<svg", "<svg fill=\"" + color + "\"");
        return "data:image/svg+xml;utf8," + encodeURIComponent(t);
    }
    function openMoreMenu(button) {
        const p = button.mapToItem(frame, 0, button.height + 4);
        menu.openAt(Math.max(8, p.x - 220), p.y, [
            { label: "Odśwież", icon: "reload", shortcut: "Ctrl+R", action: "reload" },
            { label: "Otwórz w przeglądarce", icon: "globe", action: "browser" },
            { label: "Kopiuj adres strony", icon: "copy", action: "copyUrl" },
            { separator: true },
            { label: "Nawigacja strony w oknie Aster", icon: store.nativeNav ? "check" : "", action: "nativeNav" },
            { label: "Pasek strony jako pasek tytułu", icon: store.integrated ? "check" : "", action: "integrated" },
            { label: "Czcionka systemu w treści", icon: store.systemFont ? "check" : "", action: "systemFont" },
            { separator: true },
            { label: "Powiększ", icon: "plus", shortcut: "Ctrl +", action: "zoomIn" },
            { label: "Pomniejsz", shortcut: "Ctrl −", action: "zoomOut" },
            { label: "Rzeczywisty rozmiar", shortcut: "Ctrl 0", action: "zoomReset" }
        ]);
    }
    onWidthChanged: if (!maxed && !pageFullScreen) store.w = width - 2 * m
    onHeightChanged: if (!maxed && !pageFullScreen) store.h = height - 2 * m

    Connections {
        target: win.runtime
        function onActivateRequested() { win.raiseWindow(); }
        function onNotificationClicked(id) {
            const n = win.notifications[id];
            if (n) n.click();
            win.raiseWindow();
        }
        function onNotificationClosed(id) { delete win.notifications[id]; }
    }
    function raiseWindow() {
        if (visibility === Window.Minimized) showNormal();
        raise();
        requestActivate();
    }

    // ——— Profil tylko tej aplikacji (logowania, ciasteczka, pamięć) ———
    WebEngineProfilePrototype {
        id: profilePrototype
        storageName: "webapp-" + win.app.id
        persistentStoragePath: win.app.profileDir
        httpCacheType: WebEngineProfile.DiskHttpCache
        persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
    }
    property WebEngineProfile profile: null
    property var notifications: ({})
    Connections {
        target: win.profile
        function onPresentNotification(notification) {
            const id = win.runtime.notify(notification.title, notification.message, win.app.icon.replace("file://", ""));
            if (!id) return;
            win.notifications[id] = notification;
            notification.closed.connect(() => win.runtime.closeNotification(id));
        }
        function onDownloadRequested(download) {
            const dir = StandardPaths.writableLocation(StandardPaths.DownloadLocation).toString().replace("file://", "");
            download.downloadDirectory = decodeURIComponent(dir);
            download.accept();
            win.toast("Pobieram „" + download.downloadFileName + "” do folderu Pobrane");
        }
    }
    Component.onCompleted: {
        profile = profilePrototype.instance();
        // Strony traktują QtWebEngine jak zwykłego Chrome (część z nich blokuje „nieznane” przeglądarki)
        profile.httpUserAgent = profile.httpUserAgent.replace(/QtWebEngine\/[\d.]+ /, "");
        web.profile = profile;
        const s = WebEngine.script();
        s.name = "aster-style";
        s.injectionPoint = WebEngineScript.DocumentReady;
        s.worldId = WebEngineScript.ApplicationWorld;
        s.runsOnSubFrames = true;
        s.sourceCode = "(function(){var st=document.createElement('style');st.textContent="
            + "'::-webkit-scrollbar{width:11px;height:11px}::-webkit-scrollbar-track{background:transparent}"
            + "::-webkit-scrollbar-thumb{background-color:rgba(127,127,127,.32);border-radius:11px;border:3px solid transparent;background-clip:content-box}"
            + "::-webkit-scrollbar-thumb:hover{background-color:rgba(127,127,127,.55)}::-webkit-scrollbar-corner{background:transparent}';"
            + "(document.head||document.documentElement).appendChild(st);})();";
        web.userScripts.insert(s);
        // Natywna nakładka: style serwisu (schowany nagłówek i menu, szkło) od pierwszej chwili wczytywania
        if (adapter) {
            const a = WebEngine.script();
            a.name = "aster-adapter";
            a.injectionPoint = WebEngineScript.DocumentCreation;
            a.worldId = WebEngineScript.MainWorld;
            a.runsOnSubFrames = false;
            a.sourceCode = "(function(){window.__asterAdapter=true;window.__asterAdapterConf="
                + JSON.stringify({ guide: adapter.guide || null, logo: adapter.logo || "" }) + ";var css=" + JSON.stringify(adapter.css) + ";"
                + "function add(){var r=document.documentElement;if(!r){return setTimeout(add,0);}"
                + "var st=document.createElement('style');st.id='aster-adapter';st.textContent=css;r.appendChild(st);"
                + (adapter.dark ? adapter.dark.replace("%d", Theme.dark ? "true" : "false").replace(/^document\.documentElement/, "r") : "")
                + "}add();})();";
            web.userScripts.insert(a);
        }
        // Przenoszenie nawigacji strony do okna i przeciąganie okna za pasek strony
        const n = WebEngine.script();
        n.name = "aster-native";
        n.sourceCode = win.runtime.resource("native.js");
        if (win.debug) console.log("[aster] native.js:", n.sourceCode.length, "znaków");
        n.injectionPoint = WebEngineScript.DocumentReady;
        n.worldId = WebEngineScript.MainWorld;
        n.runsOnSubFrames = false;
        web.userScripts.insert(n);
        web.url = app.url;
        effectsTimer.restart();
    }

    // ——— Co zostaje w oknie, a co idzie do przeglądarki ———
    readonly property var loginHosts: ["accounts.google.com", "login.microsoftonline.com", "login.live.com", "login.microsoft.com",
                                      "appleid.apple.com", "www.facebook.com", "m.facebook.com", "github.com", "auth0.com", "okta.com"]
    function hostOf(url) { const mm = /^[a-z]+:\/\/([^/:?#]+)/i.exec(url || ""); return mm ? mm[1].toLowerCase() : ""; }
    function inScope(url) {
        const h = hostOf(url);
        if (!h) return true;
        const scope = (app.scope || hostOf(app.url)).toLowerCase();
        return h === scope || h.endsWith("." + scope) || loginHosts.some(l => h === l || h.endsWith("." + l));
    }

    // ——— Liczba nieprzeczytanych z tytułu strony: „(3) WhatsApp”, „Odebrane (12) - Gmail” ———
    function updateBadge() {
        const mm = /\((\d{1,4})\+?\)/.exec(web.title || "");
        runtime.setBadge(mm ? parseInt(mm[1]) : 0);
    }

    property bool everLoaded: false
    property bool failed: false
    function toast(text) { toastText.text = text; toastTimer.restart(); }
    property real zoomShown: 0
    function zoom(d) {
        web.zoomFactor = d === 0 ? 1 : Math.max(0.3, Math.min(3, Math.round((web.zoomFactor + d) * 10) / 10));
        zoomShown = web.zoomFactor;
        zoomTimer.restart();
    }
    Timer { id: zoomTimer; interval: 1400; onTriggered: win.zoomShown = 0 }

    Shortcut { sequences: ["Ctrl+R", "F5"]; onActivated: web.reload() }
    Shortcut { sequence: "Alt+Left"; onActivated: web.goBack() }
    Shortcut { sequence: "Alt+Right"; onActivated: web.goForward() }
    Shortcut { sequences: ["Ctrl+W", "Ctrl+Q"]; onActivated: win.close() }
    Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: win.zoom(0.1) }
    Shortcut { sequence: "Ctrl+-"; onActivated: win.zoom(-0.1) }
    Shortcut { sequence: "Ctrl+0"; onActivated: win.zoom(0) }

    // ——— Okno: rozmycie i obszar kliknięć ———
    function updateEffects() {
        WindowEffects.setBlur(win, Qt.rect(m, m, frame.width, frame.height), r);
        WindowEffects.setInputRegion(win, Qt.rect(Math.max(0, m - 6), Math.max(0, m - 6), frame.width + (m ? 12 : 0), frame.height + (m ? 12 : 0)));
    }
    onMaxedChanged: effectsTimer.restart()
    onPageFullScreenChanged: effectsTimer.restart()
    Timer { id: effectsTimer; interval: 16; onTriggered: win.updateEffects() }
    Connections {
        target: win
        function onWidthChanged() { effectsTimer.restart(); }
        function onHeightChanged() { effectsTimer.restart(); }
    }

    WindowShadow { window: win; frame: frame; radius: win.r; visible: win.m > 0 }
    ResizeHandles { window: win; frame: frame; margin: win.m }

    Rectangle {
        id: frame
        x: win.m; y: win.m
        width: win.width - 2 * win.m
        height: win.height - 2 * win.m
        radius: win.r
        // Nakładki: czysta biel albo czerń, prześwitująca rozmytym pulpitem
        color: win.adapter ? (Theme.dark ? Qt.rgba(0.04, 0.04, 0.045, 0.82) : Qt.rgba(1, 1, 1, 0.84)) : Theme.windowGlass
        border.width: win.m ? 1 : 0
        border.color: Theme.edge
        WindowSheen { window: win; radius: win.r }

        // ——— Natywny pasek boczny z menu strony ———
        Item {
            id: side
            width: win.sideWidth
            height: parent.height
            visible: width > 0
            clip: true
            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
            // Tło w kolorze menu strony (lekko przezroczyste — prześwituje szkło okna)
            Rectangle {
                anchors.fill: parent
                topLeftRadius: win.r; bottomLeftRadius: win.r
                color: win.sideFill
                Behavior on color { ColorAnimation { duration: 250 } }
            }
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: win.sideLine }

            Item {
                id: sideHeader
                width: 232; height: 54
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }
                Row {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Rectangle {
                        width: web.canGoBack ? 28 : 0
                        height: 28; radius: 8
                        clip: true
                        anchors.verticalCenter: parent.verticalCenter
                        color: sideBack.containsMouse ? win.sideHover : "transparent"
                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                        Icon { anchors.centerIn: parent; d: Icons.back; size: 16; color: win.sideText }
                        MouseArea { id: sideBack; anchors.fill: parent; hoverEnabled: true; onClicked: web.goBack() }
                    }
                    // Logo serwisu prosto ze strony (np. pełne logo YouTube)
                    Image {
                        id: brandLogo
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!win.pageLogo
                        height: 22
                        width: Math.min(140, implicitWidth * height / Math.max(1, implicitHeight))
                        source: win.pageLogo ? win.svgUrl(win.pageLogo, win.sideText.toString()) : ""
                        sourceSize.height: 44
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        MouseArea { anchors.fill: parent; onClicked: win.adapterGo(win.adapter.home) }
                    }
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !win.pageLogo
                        width: 24; height: 24
                        source: win.app.icon
                        sourceSize: Qt.size(48, 48)
                        smooth: true; mipmap: true
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !win.pageLogo
                        width: 232 - 90 - (web.canGoBack ? 38 : 0)
                        elide: Text.ElideRight
                        text: win.app.name
                        color: win.sideText
                        font.family: win.uiFont; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                }
            }

            // Główny przycisk strony („Napisz”, „Nowy czat”) jako przycisk Aster
            Rectangle {
                id: primaryBtn
                x: 12; y: sideHeader.height
                width: 232 - 24
                height: win.navPrimary ? 40 : 0
                visible: height > 0
                radius: 12
                color: primaryArea.containsMouse ? Qt.darker(Theme.accent, 1.1) : Theme.accent
                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18; height: 18
                        visible: !!win.navPrimary && !!win.navPrimary.icon
                        source: win.navPrimary && win.navPrimary.icon ? win.svgUrl(win.navPrimary.icon, "#FFFFFF") : ""
                        sourceSize: Qt.size(36, 36)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.navPrimary ? win.navPrimary.label : ""
                        color: "white"
                        font.family: win.uiFont; font.pixelSize: 13; font.weight: Font.Medium
                    }
                }
                MouseArea { id: primaryArea; anchors.fill: parent; hoverEnabled: true; onClicked: win.navClick(win.navPrimary.id) }
            }

            // Wyszukiwarka strony jako pole Aster
            NativeSearch {
                id: sideSearch
                x: 12
                y: primaryBtn.y + primaryBtn.height + (primaryBtn.visible ? 10 : 0)
                width: 232 - 24
                height: win.navSearch && !win.adapter ? 34 : 0
                visible: height > 0
                dark: win.sideDark
            }

            ListView {
                id: sideList
                x: 10; y: sideSearch.y + sideSearch.height + (sideSearch.visible ? 10 : 2)
                width: 232 - 20
                height: parent.height - y - 10 - accountRow.height
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: win.adapter ? win.adapterNav : win.navSidebar
                delegate: Rectangle {
                    id: navItem
                    required property var modelData
                    required property int index
                    readonly property bool isSection: !!modelData.section
                    width: sideList.width; height: isSection ? (win.adapter ? 38 : 30) : (win.adapter ? 40 : 36)
                    radius: win.adapter ? 10 : 9
                    color: isSection ? "transparent" : (modelData.active ? win.sideActive : (navArea.containsMouse ? win.sideHover : "transparent"))
                    Behavior on color { ColorAnimation { duration: 120 } }
                    opacity: 0
                    Component.onCompleted: navIn.start()
                    NumberAnimation { id: navIn; target: navItem; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutQuad }
                    // Nagłówek grupy („Kanały”, „Etykiety”)
                    Text {
                        visible: navItem.isSection
                        x: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                        width: parent.width - 20
                        elide: Text.ElideRight
                        text: navItem.modelData.label
                        color: win.adapter ? win.sideText : win.sideText2
                        font.family: win.adapter ? win.titleFont : Theme.font
                        font.pixelSize: win.adapter ? 16 : 11
                        font.weight: win.adapter ? Font.Bold : Font.DemiBold
                        font.letterSpacing: win.adapter ? 0 : 0.3
                    }
                    Item {
                        id: navIcon
                        visible: !navItem.isSection
                        x: win.adapter ? 12 : 10; anchors.verticalCenter: parent.verticalCenter
                        width: win.adapter ? 24 : 20; height: width
                        Icon {
                            anchors.centerIn: parent
                            visible: !!navItem.modelData.iconName
                            d: navItem.modelData.iconName ? (Icons[navItem.modelData.iconName] || "") : ""
                            size: 19
                            stroke: navItem.modelData.active ? 2.1 : 1.75
                            color: navItem.modelData.active ? win.sideActiveText : win.sideText
                        }
                        Image {
                            id: navSvg
                            visible: !navItem.modelData.iconName && status === Image.Ready && !navItem.modelData.img
                            anchors.fill: parent
                            source: navItem.modelData.icon ? win.svgUrl(navItem.modelData.icon, navItem.modelData.active ? win.sideActiveText.toString() : win.sideText.toString())
                                                           : navItem.modelData.img
                            sourceSize: Qt.size(40, 40)
                            smooth: true
                        }
                        // Awatar kanału (okrągły)
                        Image {
                            id: navAvatar
                            anchors.fill: parent
                            visible: false
                            source: navItem.modelData.img || ""
                            sourceSize: Qt.size(48, 48)
                        }
                        Rectangle { id: navAvatarMask; anchors.fill: parent; radius: 10; visible: false; layer.enabled: true }
                        MultiEffect {
                            anchors.fill: parent
                            visible: !!navItem.modelData.img && navAvatar.status === Image.Ready
                            source: navAvatar
                            maskEnabled: true
                            maskSource: navAvatarMask
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            visible: !navItem.modelData.iconName && navSvg.status !== Image.Ready && !(navItem.modelData.img && navAvatar.status === Image.Ready)
                            width: 20; height: 20; radius: 6
                            color: navItem.modelData.active ? Theme.accent : win.sideHover
                            Text {
                                anchors.centerIn: parent
                                text: navItem.modelData.label.charAt(0).toUpperCase()
                                color: navItem.modelData.active ? "white" : win.sideText2
                                font.family: win.uiFont; font.pixelSize: 11; font.letterSpacing: 0.1; font.weight: Font.DemiBold
                            }
                        }
                    }
                    // Licznik („12” nieprzeczytanych)
                    Rectangle {
                        id: countPill
                        visible: !navItem.isSection && !!navItem.modelData.count
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(22, countText.implicitWidth + 12); height: 20; radius: 10
                        color: navItem.modelData.active ? Theme.accent : win.sideHover
                        Text {
                            id: countText
                            anchors.centerIn: parent
                            text: navItem.modelData.count || ""
                            color: navItem.modelData.active ? "white" : win.sideText2
                            font.family: win.uiFont; font.pixelSize: 11; font.letterSpacing: 0.1; font.weight: Font.Medium
                        }
                    }
                    Text {
                        visible: !navItem.isSection
                        anchors.left: navIcon.right; anchors.leftMargin: win.adapter ? 20 : 12
                        anchors.right: countPill.visible ? countPill.left : parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: navItem.modelData.label
                        elide: Text.ElideRight
                        color: navItem.modelData.active ? win.sideActiveText : win.sideText
                        font.family: win.uiFont; font.pixelSize: win.adapter ? 14 : 13
                        font.weight: navItem.modelData.active ? (win.adapter ? Font.Medium : Font.DemiBold) : Font.Normal
                    }
                    MouseArea {
                        id: navArea
                        anchors.fill: parent
                        enabled: !navItem.isSection
                        hoverEnabled: true
                        onClicked: {
                            // od razu zaznacz kliknięte (strona potwierdzi przy następnym odczycie)
                            if (win.adapter)
                                win.pageSections = win.pageSections.map(s => Object.assign({}, s, { items: s.items.map(x => Object.assign({}, x, { active: x.id === navItem.modelData.id })) }));
                            else
                                win.navSidebar = win.navSidebar.map(x => Object.assign({}, x, { active: x.id === navItem.modelData.id }));
                            win.navClick(navItem.modelData.id, !!navItem.modelData.fromPage);
                        }
                    }
                }
            }
        }

        // Konto (nakładka): zdjęcie z serwisu albo „Zaloguj się” na dole paska bocznego
        Item {
            id: accountRow
            parent: side
            width: 232
            height: win.adapter ? 60 : 0
            y: side.height - height
            visible: height > 0
            Rectangle { x: 14; width: parent.width - 28; height: 1; color: win.sideLine }
            Rectangle {
                x: 10; y: 10
                width: parent.width - 20; height: 42; radius: 10
                color: accArea.containsMouse ? win.sideHover : "transparent"
                Item {
                    id: accPic
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28
                    Image {
                        id: avatarImg
                        anchors.fill: parent
                        source: win.avatarSrc
                        visible: false
                        sourceSize: Qt.size(56, 56)
                    }
                    Rectangle { id: avatarMask; anchors.fill: parent; radius: 14; visible: false; layer.enabled: true }
                    MultiEffect {
                        anchors.fill: parent
                        visible: !!win.avatarSrc
                        source: avatarImg
                        maskEnabled: true
                        maskSource: avatarMask
                    }
                    Rectangle {
                        anchors.fill: parent; radius: 14
                        visible: !win.avatarSrc
                        color: Qt.alpha(win.brand, 0.15)
                        Icon { anchors.centerIn: parent; d: Icons.webapp; size: 14; color: win.sideActiveText }
                    }
                }
                Text {
                    anchors.left: accPic.right; anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.avatarSrc ? "Twoje konto" : "Zaloguj się"
                    color: win.sideText
                    font.family: win.uiFont; font.pixelSize: 13; font.weight: Font.Medium
                }
                MouseArea {
                    id: accArea; anchors.fill: parent; hoverEnabled: true
                    onClicked: {
                        if (win.avatarSrc) web.runJavaScript("(function(){var b=document.querySelector(" + JSON.stringify(win.adapter.accountClick) + ");if(b)b.click();})()");
                        else win.adapterGo(win.adapter.signIn);
                    }
                }
            }
        }
        Timer {
            running: !!win.adapter && !!win.adapter.avatar
            interval: 3000; repeat: true; triggeredOnStart: true
            onTriggered: web.runJavaScript("(function(){var i=document.querySelector(" + JSON.stringify(win.adapter.avatar) + ");return i&&i.src&&i.src.indexOf('http')===0?i.src:'';})()",
                                           (src) => win.avatarSrc = src || "")
        }

        // ——— Pasek tytułu w kolorze aplikacji ———
        Rectangle {
            id: bar
            x: win.sideWidth
            width: parent.width - x
            height: win.pageFullScreen || win.integratedBar ? 0 : (win.adapter ? 56 : (win.showTopnav ? 50 : 42))
            visible: height > 0
            topLeftRadius: win.sideWidth ? 0 : win.r; topRightRadius: win.r
            color: win.barColor
            Behavior on color { ColorAnimation { duration: 300 } }

            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
            TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }

            Row {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                // Wstecz — pojawia się tylko, gdy jest dokąd wrócić
                Rectangle {
                    width: web.canGoBack ? 30 : 0
                    height: 30; radius: 9
                    clip: true
                    anchors.verticalCenter: parent.verticalCenter
                    color: backArea.containsMouse ? win.barHover : "transparent"
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                    Icon { anchors.centerIn: parent; d: Icons.back; size: 17; color: win.barText }
                    MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; onClicked: web.goBack() }
                }
                // Dalej (nakładka)
                Rectangle {
                    width: win.adapter && web.canGoForward ? 30 : 0
                    height: 30; radius: 9
                    clip: true
                    anchors.verticalCenter: parent.verticalCenter
                    color: fwdArea.containsMouse ? win.barHover : "transparent"
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                    Icon { anchors.centerIn: parent; d: Icons.forward; size: 17; color: win.barText }
                    MouseArea { id: fwdArea; anchors.fill: parent; hoverEnabled: true; onClicked: web.goForward() }
                }
                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !win.adapter
                    width: 20; height: 20
                    source: win.app.icon
                    sourceSize: Qt.size(40, 40)
                    smooth: true; mipmap: true
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: win.adapter ? Math.max(40, Math.min(implicitWidth, adapterSearch.x - x - 26)) : implicitWidth
                    elide: Text.ElideRight
                    text: win.adapter ? win.viewTitle : win.app.name
                    color: win.barText
                    font.family: win.adapter ? win.titleFont : Theme.font
                    font.pixelSize: win.adapter ? 17 : 13
                    font.weight: win.adapter ? Font.Bold : Font.DemiBold
                }
            }

            Row {
                id: barTools
                anchors.right: winButtons.left; anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Rectangle {
                    width: zoomLabel.implicitWidth + 14; height: 24; radius: 8
                    anchors.verticalCenter: parent.verticalCenter
                    visible: win.zoomShown > 0
                    color: win.barHover
                    Text { id: zoomLabel; anchors.centerIn: parent; text: Math.round(win.zoomShown * 100) + "%"; color: win.barText; font.family: win.uiFont; font.pixelSize: 12; font.weight: Font.Medium }
                }
                BarButton { icon: web.loading ? "close" : "reload"; onClicked: if (web.loading) web.stop(); else web.reload() }
                BarButton {
                    id: moreBtn
                    icon: "more"
                    onClicked: win.openMoreMenu(moreBtn)
                }
            }
            // Zakładki strony (górna nawigacja) jako przełącznik w pasku tytułu
            Rectangle {
                anchors.centerIn: parent
                visible: win.showTopnav
                height: 34; radius: 10
                width: tabsRow.implicitWidth + 8
                color: win.barTinted ? win.barHover : Theme.fill
                Row {
                    id: tabsRow
                    anchors.centerIn: parent
                    spacing: 2
                    Repeater {
                        model: win.showTopnav ? win.navTop : []
                        delegate: Rectangle {
                            id: tabBtn
                            required property var modelData
                            width: tabLabel.implicitWidth + 26; height: 28; radius: 8
                            color: modelData.active ? Theme.surface : (tabArea.containsMouse ? win.barHover : "transparent")
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                id: tabLabel
                                anchors.centerIn: parent
                                text: tabBtn.modelData.label
                                color: tabBtn.modelData.active ? Theme.text : win.barText
                                font.family: win.uiFont; font.pixelSize: 13
                                font.weight: tabBtn.modelData.active ? Font.Medium : Font.Medium
                            }
                            MouseArea {
                                id: tabArea; anchors.fill: parent; hoverEnabled: true
                                onClicked: {
                                    win.navTop = win.navTop.map(x => Object.assign({}, x, { active: x.id === tabBtn.modelData.id }));
                                    win.navClick(tabBtn.modelData.id);
                                }
                            }
                        }
                    }
                }
            }
            // Wyszukiwarka nakładki: na środku, z podpowiedziami serwisu
            Rectangle {
                id: adapterSearch
                visible: !!win.adapter && !!win.adapter.search
                anchors.centerIn: parent
                width: Math.min(560, bar.width - 400)
                height: 40; radius: 20
                color: Theme.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.75)
                border.width: 1
                border.color: adField.activeFocus ? "#1C62B9" : (Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.14))
                Behavior on border.color { ColorAnimation { duration: 120 } }
                // Ikona lupy po lewej przy wpisywaniu (jak w YouTube)
                Icon { x: 16; anchors.verticalCenter: parent.verticalCenter; visible: adField.activeFocus; d: Icons.search; size: 16; color: Theme.text2 }
                // Przycisk szukania po prawej
                Rectangle {
                    anchors.right: parent.right
                    width: 64; height: parent.height
                    topRightRadius: 20; bottomRightRadius: 20
                    color: searchBtn.containsMouse ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.08)) : (Theme.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.035))
                    Rectangle { width: 1; height: parent.height; color: Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12) }
                    Icon { anchors.centerIn: parent; d: Icons.search; size: 19; stroke: 1.9; color: Theme.text }
                    MouseArea { id: searchBtn; anchors.fill: parent; hoverEnabled: true; onClicked: win.runAdapterSearch(adField.text) }
                }
                TextInput {
                    id: adField
                    anchors.left: parent.left; anchors.leftMargin: activeFocus ? 42 : 18
                    anchors.right: parent.right; anchors.rightMargin: 76
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    color: Theme.text
                    selectionColor: Theme.accentSoft
                    selectedTextColor: Theme.text
                    font.family: win.uiFont; font.pixelSize: 15
                    onTextEdited: suggestTimer.restart()
                    onActiveFocusChanged: if (!activeFocus) suggestBox.items = []
                    Keys.onDownPressed: suggestBox.index = Math.min(suggestBox.items.length - 1, suggestBox.index + 1)
                    Keys.onUpPressed: suggestBox.index = Math.max(-1, suggestBox.index - 1)
                    Keys.onReturnPressed: win.runAdapterSearch(suggestBox.index >= 0 ? suggestBox.items[suggestBox.index] : text)
                    Keys.onEnterPressed: win.runAdapterSearch(suggestBox.index >= 0 ? suggestBox.items[suggestBox.index] : text)
                    Keys.onEscapePressed: { if (suggestBox.items.length) suggestBox.items = []; else { text = ""; web.forceActiveFocus(); } }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !adField.text
                        text: win.adapter && win.adapter.search ? win.adapter.search.placeholder : ""
                        color: Theme.text2
                        font: adField.font
                    }
                }
                Timer {
                    id: suggestTimer
                    interval: 140
                    onTriggered: win.fetchSuggestions(adField.text)
                }
            }
            NativeSearch {
                anchors.right: barTools.left; anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 220; height: 30
                visible: !win.adapter && !!win.navSearch && !win.showSidebar && !win.showTopnav
                dark: win.barTinted && win.barText.r > 0.5
            }
            WindowButtons {
                id: winButtons
                window: win
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                scale: 0.9
                idleColor: win.barTinted ? win.barHover : Theme.fill
                idleIconColor: win.barTinted ? win.barText : Theme.text2
            }

            // Postęp wczytywania
            Rectangle {
                anchors.bottom: parent.bottom
                height: 2
                width: parent.width * web.loadProgress / 100
                color: win.barTinted ? win.barText : Theme.accent
                opacity: web.loading && win.everLoaded ? 0.7 : 0
                Behavior on width { NumberAnimation { duration: 200 } }
                Behavior on opacity { NumberAnimation { duration: 300 } }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line; visible: !win.barTinted && !win.adapter }
        }

        // ——— Prośba o kamerę / mikrofon / lokalizację ———
        Rectangle {
            id: permBar
            property var request: null
            x: win.sideWidth
            y: bar.height
            width: parent.width - x
            height: request ? 46 : 0
            visible: height > 0
            clip: true
            color: Theme.surface
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
            readonly property var names: ["", "mikrofonu", "kamery", "kamery i mikrofonu", "udostępniania ekranu", "udostępniania ekranu z dźwiękiem",
                                          "przejęcia kursora", "powiadomień", "Twojej lokalizacji", "schowka", "czcionek"]
            function answer(grant) { if (!request) return; if (grant) request.grant(); else request.deny(); request = null; }
            Text {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                text: permBar.request ? win.app.name + " prosi o dostęp do " + permBar.names[permBar.request.permissionType] : ""
                color: Theme.text; font.family: win.uiFont; font.pixelSize: 13
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                HoverButton {
                    width: noText.implicitWidth + 24; height: 30; baseColor: Theme.fill
                    onClicked: permBar.answer(false)
                    Text { id: noText; anchors.centerIn: parent; text: "Nie zezwalaj"; color: Theme.text; font.family: win.uiFont; font.pixelSize: 13 }
                }
                Rectangle {
                    width: yesText.implicitWidth + 26; height: 30; radius: 8
                    color: Theme.accent
                    Text { id: yesText; anchors.centerIn: parent; text: "Zezwól"; color: "white"; font.family: win.uiFont; font.pixelSize: 13; font.weight: Font.Medium }
                    MouseArea { anchors.fill: parent; onClicked: permBar.answer(true) }
                }
            }
        }

        // ——— Strona ———
        Item {
            id: content
            x: win.sideWidth
            y: bar.height + permBar.height
            width: parent.width - x
            height: parent.height - y
            clip: true
            layer.enabled: win.r > 0 && GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: contentMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            WebEngineView {
                id: web
                anchors.fill: parent
                backgroundColor: win.adapter && win.adapter.glass ? "transparent" : (win.pageBgCss ? win.pageColor : (win.app.backgroundColor || "white"))
                settings.fullScreenSupportEnabled: true
                settings.scrollAnimatorEnabled: true
                settings.focusOnNavigationEnabled: true

                onTitleChanged: win.updateBadge()
                onJavaScriptConsoleMessage: (level, message, line, source) => {
                    if (win.debug) console.log("[strona]", message.slice(0, 600), source + ":" + line);
                    if (message.indexOf("aster:") !== 0) return;
                    let o;
                    try { o = JSON.parse(message.slice(6)); } catch (e) { return; }
                    if (o.type === "layout") {
                        win.navSidebar = o.sidebar || [];
                        win.navTop = o.topnav || [];
                        win.pageTopbar = o.topbar || 0;
                        win.navPrimary = o.primary || null;
                        win.navSearch = o.search || null;
                        win.pageBgCss = o.pageBg || "";
                        win.sideBgCss = o.sideBg || "";
                        win.topbarBgCss = o.topbarBg || "";
                    } else if (o.type === "adapter") {
                        win.pageLogo = o.logo || "";
                        win.pageSections = o.sections || [];
                        win.bodyFonts = o.bodyFont || [];
                        if (JSON.stringify(o.fonts || []) !== JSON.stringify(win.pageFontUrls)) win.pageFontUrls = o.fonts || [];
                    } else if (o.type === "drag" && win.integratedBar) {
                        win.startSystemMove();
                    } else if (o.type === "maximize") {
                        if (win.maxed) win.showNormal(); else win.showMaximized();
                    }
                }
                onLoadingChanged: (info) => {
                    if (info.status === WebEngineView.LoadSucceededStatus) {
                        if (win.debug) explainTimer.restart();
                        if (!store.systemFont) web.runJavaScript("window.__aster && window.__aster.setFont(false)");
                        if (win.adapter && win.adapter.dark) web.runJavaScript(win.adapter.dark.replace("%d", Theme.dark ? "true" : "false"));
                        win.failed = false;
                        if (!win.everLoaded) splashOut.start();
                        if (!win.everLoaded && win.evalScript) evalTimer.start();
                        win.everLoaded = true;
                        web.runJavaScript("(function(){var m=document.querySelector('meta[name=\"theme-color\"]:not([media*=\"dark\"])')||document.querySelector('meta[name=\"theme-color\"]');return m?m.content:'';})()",
                                          (c) => { c = (c || "").trim(); if (/^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(c)) win.pageTheme = c; });
                    } else if (info.status === WebEngineView.LoadFailedStatus && info.errorCode !== -3) {
                        win.failed = true;
                        if (!win.everLoaded) splashOut.start();
                    }
                }
                onNavigationRequested: (request) => {
                    if (request.isMainFrame && request.navigationType === WebEngineNavigationRequest.LinkClickedNavigation
                            && !win.inScope(request.url.toString())) {
                        request.reject();
                        Qt.openUrlExternally(request.url);
                    }
                }
                onNewWindowRequested: (request) => {
                    const u = request.requestedUrl.toString();
                    if (!u || u === "about:blank" || request.destination === WebEngineNewWindowRequest.InNewDialog
                            || win.loginHosts.some(l => win.hostOf(u).endsWith(l))) {
                        const popup = popupComponent.createObject(null);
                        request.openIn(popup["view"]);
                    } else if (win.inScope(u)) {
                        web.url = u;
                    } else {
                        Qt.openUrlExternally(u);
                    }
                }
                onPermissionRequested: (permission) => {
                    // Powiadomienia i schowek: aplikację zainstalowano świadomie — zgoda od razu
                    // (numery typów jak w QWebEnginePermission: 7 — powiadomienia, 9 — schowek)
                    if (permission.permissionType === 7 || permission.permissionType === 9)
                        permission.grant();
                    else
                        permBar.request = permission;
                }
                onFullScreenRequested: (request) => {
                    request.accept();
                    win.pageFullScreen = request.toggleOn;
                    if (request.toggleOn) win.showFullScreen(); else win.showNormal();
                }
                onTooltipRequested: (request) => {
                    request.accepted = true;
                    if (request.type === TooltipRequest.Show && request.text) {
                        tip.text = request.text;
                        tip.x = Math.min(frame.width - tip.width - 8, content.x + request.x + 12);
                        tip.y = Math.min(frame.height - tip.height - 8, content.y + request.y + 20);
                        tipDelay.restart();
                    } else {
                        tipDelay.stop();
                        tip.shown = false;
                    }
                }
                onJavaScriptDialogRequested: (request) => {
                    request.accepted = true;
                    dlgInput.text = request.defaultText || "";
                    win.dialog = request;
                    if (request.type === JavaScriptDialogRequest.DialogTypePrompt) dlgInput.forceActiveFocus();
                }
                onContextMenuRequested: (request) => {
                    request.accepted = true;
                    win.showPageMenu(request);
                }
            }

            // Ekran powitalny: ikona na kolorze aplikacji, póki strona się wczytuje
            Rectangle {
                id: splash
                anchors.fill: parent
                color: win.app.backgroundColor || Theme.pane
                visible: opacity > 0
                Image {
                    id: splashIcon
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -24
                    width: 112; height: 112
                    source: win.app.icon
                    sourceSize: Qt.size(224, 224)
                    smooth: true; mipmap: true
                    scale: 0.85
                    Component.onCompleted: splashIn.start()
                    NumberAnimation { id: splashIn; target: splashIcon; property: "scale"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: splashIcon.bottom; anchors.topMargin: 18
                    text: win.app.name
                    color: Qt.colorEqual(splash.color, "white") || (0.299 * splash.color.r + 0.587 * splash.color.g + 0.114 * splash.color.b) > 0.6 ? "#16181D" : "white"
                    font.family: win.uiFont; font.pixelSize: 17; font.letterSpacing: -0.2; font.weight: Font.DemiBold
                    opacity: 0.85
                }
                ParallelAnimation {
                    id: splashOut
                    NumberAnimation { target: splash; property: "opacity"; to: 0; duration: 260; easing.type: Easing.OutQuad }
                    NumberAnimation { target: splashIcon; property: "scale"; to: 1.15; duration: 260; easing.type: Easing.InQuad }
                }
                Timer { running: true; interval: 9000; onTriggered: if (splash.opacity === 1) splashOut.start() }
            }

            // Brak połączenia
            Rectangle {
                anchors.fill: parent
                visible: win.failed
                color: Theme.pane
                Column {
                    anchors.centerIn: parent
                    spacing: 12
                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 72; height: 72
                        source: win.app.icon
                        sourceSize: Qt.size(144, 144)
                        opacity: 0.5
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Nie udało się połączyć"
                        color: Theme.text; font.family: win.uiFont; font.pixelSize: 19; font.letterSpacing: -0.2; font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Sprawdź połączenie z internetem — " + win.app.name + " spróbuje ponownie."
                        color: Theme.text2; font.family: win.uiFont; font.pixelSize: 13
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: retryText.implicitWidth + 32; height: 38; radius: 10
                        color: retryArea.containsMouse ? Qt.darker(Theme.accent, 1.1) : Theme.accent
                        Text { id: retryText; anchors.centerIn: parent; text: "Spróbuj ponownie"; color: "white"; font.family: win.uiFont; font.pixelSize: 13; font.weight: Font.Medium }
                        MouseArea { id: retryArea; anchors.fill: parent; hoverEnabled: true; onClicked: web.reload() }
                    }
                }
                Timer { running: win.failed; repeat: true; interval: 15000; onTriggered: web.reload() }
            }

            // Komunikat
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: toastTimer.running ? 18 : -height
                Behavior on anchors.bottomMargin { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                width: toastText.implicitWidth + 32; height: 40; radius: 20
                color: Theme.text
                Text { id: toastText; anchors.centerIn: parent; color: Theme.surface; font.family: win.uiFont; font.pixelSize: 13 }
            }
            Timer { id: toastTimer; interval: 3500 }
        }
        Rectangle {
            id: contentMask
            visible: false
            layer.enabled: true
            width: content.width; height: content.height
            bottomLeftRadius: win.r; bottomRightRadius: win.r
            color: "black"
        }

        // Przyciski okna nad paskiem strony (tryb zintegrowany)
        Rectangle {
            id: floatControls
            visible: win.integratedBar
            anchors.right: parent.right; anchors.rightMargin: 8
            y: 7
            z: 20
            height: 34; radius: 12
            width: floatRow.implicitWidth + 12
            color: win.pageDark ? Qt.rgba(0.17, 0.17, 0.2, 0.9) : Qt.rgba(1, 1, 1, 0.9)
            border.width: 1; border.color: win.pageDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08)
            Row {
                id: floatRow
                anchors.centerIn: parent
                spacing: 2
                NativeSearch {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 200; height: 28
                    visible: !!win.navSearch && !win.showSidebar
                    dark: win.pageDark
                }
                FloatButton { icon: "back"; visible: web.canGoBack && !win.showSidebar; onClicked: web.goBack() }
                FloatButton { icon: web.loading ? "close" : "reload"; onClicked: if (web.loading) web.stop(); else web.reload() }
                FloatButton { id: floatMore; icon: "more"; onClicked: win.openMoreMenu(floatMore) }
                Item { width: 4; height: 1 }
                WindowButtons {
                    window: win; anchors.verticalCenter: parent.verticalCenter; scale: 0.82; spacing: 4
                    idleColor: win.pageDark ? Qt.rgba(1, 1, 1, 0.1) : Theme.fill
                    idleIconColor: win.pageDark ? "#C9CDD6" : Theme.text2
                }
            }
        }

        // ——— Podpowiedzi wyszukiwania (nakładka) ———
        Rectangle {
            id: suggestBox
            property var items: []
            property int index: -1
            z: 70
            visible: items.length > 0 && adField.activeFocus
            x: adapterSearch.mapToItem(frame, 0, 0).x
            y: adapterSearch.mapToItem(frame, 0, 0).y + adapterSearch.height + 6
            width: adapterSearch.width
            height: sugCol.implicitHeight + 12
            radius: 14
            color: Theme.surface
            border.width: 1; border.color: Theme.edge
            layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowVerticalOffset: 10; shadowColor: Theme.shadow }
            Column {
                id: sugCol
                x: 6; y: 6
                width: parent.width - 12
                Repeater {
                    model: suggestBox.items
                    delegate: Rectangle {
                        id: sug
                        required property string modelData
                        required property int index
                        width: sugCol.width; height: 36; radius: 9
                        color: suggestBox.index === index ? Qt.alpha(win.brand, 0.12) : (sugArea.containsMouse ? Theme.hover : "transparent")
                        Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 14; color: Theme.text2 }
                        Text {
                            x: 34; width: parent.width - 44
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: sug.modelData
                            color: Theme.text
                            font.family: win.uiFont; font.pixelSize: 13
                            font.weight: suggestBox.index === sug.index ? Font.Medium : Font.Normal
                        }
                        MouseArea { id: sugArea; anchors.fill: parent; hoverEnabled: true; onClicked: win.runAdapterSearch(sug.modelData) }
                    }
                }
            }
        }

        // ——— Dymek podpowiedzi (zamiast przeglądarkowego) ———
        Rectangle {
            id: tip
            property string text
            property bool shown: false
            z: 60
            visible: opacity > 0
            opacity: shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            width: Math.min(360, tipText.implicitWidth + 20)
            height: tipText.implicitHeight + 12
            radius: 8
            color: Theme.dark ? "#2A2C33" : "#16181D"
            Text {
                id: tipText
                x: 10; y: 6
                width: Math.min(340, implicitWidth)
                text: tip.text
                wrapMode: Text.Wrap
                color: "white"
                font.family: win.uiFont; font.pixelSize: 12
            }
            Timer { id: tipDelay; interval: 450; onTriggered: tip.shown = true }
        }

        // ——— Okna strony (alert / confirm / prompt) w stylu Aster ———
        Rectangle {
            anchors.fill: parent
            z: 80
            color: Qt.rgba(0, 0, 0, 0.3)
            radius: win.r
            visible: !!win.dialog
            MouseArea { anchors.fill: parent }
            Rectangle {
                anchors.centerIn: parent
                width: 420
                height: dlgCol.implicitHeight + 48
                radius: 16
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                Column {
                    id: dlgCol
                    x: 24; y: 24
                    width: parent.width - 48
                    spacing: 12
                    Row {
                        spacing: 10
                        Image { width: 28; height: 28; source: win.app.icon; sourceSize: Qt.size(56, 56); anchors.verticalCenter: parent.verticalCenter }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: win.app.name; color: Theme.text; font.family: win.uiFont; font.pixelSize: 16; font.weight: Font.DemiBold }
                    }
                    Text {
                        width: parent.width
                        text: win.dialog ? win.dialog.message : ""
                        wrapMode: Text.Wrap
                        color: Theme.text
                        font.family: win.uiFont; font.pixelSize: 14
                    }
                    Rectangle {
                        visible: !!win.dialog && win.dialog.type === JavaScriptDialogRequest.DialogTypePrompt
                        width: parent.width; height: 38; radius: 10
                        color: Theme.fill
                        border.width: 1.5; border.color: Theme.accent
                        TextInput {
                            id: dlgInput
                            x: 12; width: parent.width - 24
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.text; font.family: win.uiFont; font.pixelSize: 14
                            clip: true
                            Keys.onReturnPressed: win.closeDialog(true)
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        HoverButton {
                            visible: !!win.dialog && win.dialog.type !== JavaScriptDialogRequest.DialogTypeAlert
                            width: 96; height: 38; radius: 10; baseColor: Theme.fill
                            onClicked: win.closeDialog(false)
                            Text { anchors.centerIn: parent; text: win.dialog && win.dialog.type === JavaScriptDialogRequest.DialogTypeBeforeUnload ? "Zostań" : "Anuluj"; color: Theme.text; font.family: win.uiFont; font.pixelSize: 13 }
                        }
                        Rectangle {
                            width: okText.implicitWidth + 32; height: 38; radius: 10
                            color: okArea.containsMouse ? Qt.darker(Theme.accent, 1.1) : Theme.accent
                            Text {
                                id: okText
                                anchors.centerIn: parent
                                text: win.dialog && win.dialog.type === JavaScriptDialogRequest.DialogTypeBeforeUnload ? "Opuść stronę" : "OK"
                                color: "white"; font.family: win.uiFont; font.pixelSize: 13; font.weight: Font.Medium
                            }
                            MouseArea { id: okArea; anchors.fill: parent; hoverEnabled: true; onClicked: win.closeDialog(true) }
                        }
                    }
                }
            }
        }

        ContextMenu {
            id: menu
            onTriggered: (a) => win.runAction(a)
        }
    }

    // ——— Menu strony ———
    property var menuRequest: null
    property var dialog: null
    function closeDialog(ok) {
        const d = dialog;
        dialog = null;
        if (!d) return;
        if (!ok) d.dialogReject();
        else if (d.type === JavaScriptDialogRequest.DialogTypePrompt) d.dialogAccept(dlgInput.text);
        else d.dialogAccept();
        web.forceActiveFocus();
    }
    function showPageMenu(request) {
        menuRequest = request;
        const p = content.mapToItem(frame, request.position.x, request.position.y);
        const items = [];
        if (request.linkUrl.toString()) {
            items.push({ label: "Otwórz link w przeglądarce", icon: "globe", action: "linkBrowser" });
            items.push({ label: "Kopiuj adres linku", icon: "copy", action: "copyLink" });
            items.push({ separator: true });
        }
        if (request.mediaType === ContextMenuRequest.MediaTypeImage) {
            items.push({ label: "Zapisz obraz", icon: "download", action: "saveImage" });
            items.push({ label: "Kopiuj obraz", icon: "copy", action: "copyImage" });
            items.push({ separator: true });
        }
        if (request.isContentEditable) {
            items.push({ label: "Wytnij", icon: "scissors", shortcut: "Ctrl+X", action: "cut" });
            items.push({ label: "Kopiuj", icon: "copy", shortcut: "Ctrl+C", action: "copy" });
            items.push({ label: "Wklej", icon: "paste", shortcut: "Ctrl+V", action: "paste" });
        } else if (request.selectedText) {
            items.push({ label: "Kopiuj", icon: "copy", shortcut: "Ctrl+C", action: "copy" });
        } else {
            items.push({ label: "Wstecz", icon: "back", action: "back", enabled: web.canGoBack });
            items.push({ label: "Odśwież", icon: "reload", action: "reload" });
        }
        if (items.length && items[items.length - 1].separator) items.pop();
        menu.openAt(p.x, p.y, items);
    }
    function runAction(a) {
        const rq = menuRequest;
        if (a === "reload") web.reload();
        else if (a === "back") web.goBack();
        else if (a === "browser") Qt.openUrlExternally(web.url);
        else if (a === "copyUrl") { copyHelper.text = web.url.toString(); copyHelper.selectAll(); copyHelper.copy(); toast("Skopiowano adres"); }
        else if (a === "nativeNav") setNativeNav(!store.nativeNav);
        else if (a === "integrated") store.integrated = !store.integrated;
        else if (a === "systemFont") { store.systemFont = !store.systemFont; web.runJavaScript("window.__aster && window.__aster.setFont(" + store.systemFont + ")"); }
        else if (a === "zoomIn") zoom(0.1);
        else if (a === "zoomOut") zoom(-0.1);
        else if (a === "zoomReset") zoom(0);
        else if (a === "linkBrowser") Qt.openUrlExternally(rq.linkUrl);
        else if (a === "copyLink") web.triggerWebAction(WebEngineView.CopyLinkToClipboard);
        else if (a === "saveImage") web.triggerWebAction(WebEngineView.DownloadImageToDisk);
        else if (a === "copyImage") web.triggerWebAction(WebEngineView.CopyImageToClipboard);
        else if (a === "cut") web.triggerWebAction(WebEngineView.Cut);
        else if (a === "copy") web.triggerWebAction(WebEngineView.Copy);
        else if (a === "paste") web.triggerWebAction(WebEngineView.Paste);
    }
    TextInput { id: copyHelper; visible: false }
    Timer {
        id: explainTimer
        interval: 4000
        onTriggered: web.runJavaScript("window.__aster ? window.__aster.explain() : 'brak __aster'", (r) => console.log("[aster] kandydaci:\n" + r))
    }

    // Pole wyszukiwania Aster połączone z polem strony
    component NativeSearch: Rectangle {
        id: ns
        property bool dark: Theme.dark
        radius: 10
        color: ns.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06)
        border.width: nsField.activeFocus ? 1.5 : 0
        border.color: Theme.accent
        clip: true
        Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 14; color: ns.dark ? "#A2A9B6" : "#5B6270" }
        TextInput {
            id: nsField
            anchors.left: parent.left; anchors.leftMargin: 32
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            color: ns.dark ? "#ECEEF3" : "#16181D"
            selectionColor: Theme.accentSoft
            font.family: win.uiFont; font.pixelSize: 13
            onTextEdited: win.searchPage(text)
            Keys.onReturnPressed: win.submitSearch()
            Keys.onEnterPressed: win.submitSearch()
            Keys.onEscapePressed: { text = ""; win.searchPage(""); web.forceActiveFocus(); }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                elide: Text.ElideRight
                visible: !nsField.text
                text: win.navSearch ? win.navSearch.placeholder : "Szukaj"
                color: ns.dark ? "#A2A9B6" : "#5B6270"
                font: nsField.font
            }
        }
    }

    component FloatButton: Rectangle {
        id: fbtn
        property string icon
        signal clicked()
        width: 28; height: 28; radius: 8
        color: fArea.containsMouse ? (win.pageDark ? Qt.rgba(1, 1, 1, 0.1) : Theme.hover) : "transparent"
        Icon { anchors.centerIn: parent; d: Icons[fbtn.icon] || ""; size: 15; color: win.pageDark ? "#C9CDD6" : Theme.text2 }
        MouseArea { id: fArea; anchors.fill: parent; hoverEnabled: true; onClicked: fbtn.clicked() }
    }

    component BarButton: Rectangle {
        id: bb
        property string icon
        signal clicked()
        width: 30; height: 30; radius: 9
        color: bbArea.containsMouse ? win.barHover : "transparent"
        Icon { anchors.centerIn: parent; d: Icons[bb.icon] || ""; size: 16; color: win.barText }
        MouseArea { id: bbArea; anchors.fill: parent; hoverEnabled: true; onClicked: bb.clicked() }
    }

    // Okienko logowania (Google, Microsoft…) — zostaje częścią aplikacji, żeby logowanie zadziałało
    Component {
        id: popupComponent
        Window {
            id: popup
            property alias view: popupView
            width: 520; height: 680
            visible: true
            title: popupView.title || win.app.name
            transientParent: win
            WebEngineView {
                id: popupView
                anchors.fill: parent
                profile: win.profile
                onWindowCloseRequested: popup.destroy()
            }
            onClosing: popup.destroy()
        }
    }
}
