pragma ComponentBehavior: Bound
import QtCore
import QtQuick
import QtQuick.Window
import QtQuick.Effects
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

    // ——— Kolor aplikacji i czytelny tekst na nim ———
    property string pageTheme: ""
    readonly property color barColor: {
        const c = pageTheme || app.themeColor || "";
        return /^#|^rgb/i.test(c) ? c : Theme.windowGlass;
    }
    readonly property bool barTinted: (pageTheme || app.themeColor || "") !== ""
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
    }

    // ——— Nawigacja strony przeniesiona do okna (z native.js) ———
    property var navSidebar: []
    property var navTop: []
    property int pageTopbar: 0
    readonly property bool showSidebar: store.nativeNav && navSidebar.length >= 3 && !pageFullScreen
    readonly property bool showTopnav: store.nativeNav && !showSidebar && navTop.length >= 3 && !pageFullScreen
    readonly property bool integratedBar: store.integrated && !showTopnav && !pageFullScreen && (pageTopbar > 0 || showSidebar)
    readonly property int sideWidth: showSidebar ? 232 : 0

    function navClick(id) {
        web.runJavaScript("window.__aster && window.__aster.click('" + id + "')");
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

    RectangularShadow {
        anchors.fill: frame
        visible: win.m > 0
        radius: win.r; blur: 40; offset.y: 12
        color: Theme.shadow
    }
    ResizeHandles { window: win; frame: frame; margin: win.m }

    Rectangle {
        id: frame
        x: win.m; y: win.m
        width: win.width - 2 * win.m
        height: win.height - 2 * win.m
        radius: win.r
        color: Theme.windowGlass
        border.width: win.m ? 1 : 0
        border.color: Theme.edge

        // ——— Natywny pasek boczny z menu strony ———
        Item {
            id: side
            width: win.sideWidth
            height: parent.height
            visible: width > 0
            clip: true
            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }

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
                        color: sideBack.containsMouse ? Theme.hover : "transparent"
                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                        Icon { anchors.centerIn: parent; d: Icons.back; size: 16; color: Theme.text }
                        MouseArea { id: sideBack; anchors.fill: parent; hoverEnabled: true; onClicked: web.goBack() }
                    }
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 24
                        source: win.app.icon
                        sourceSize: Qt.size(48, 48)
                        smooth: true; mipmap: true
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 232 - 90 - (web.canGoBack ? 38 : 0)
                        elide: Text.ElideRight
                        text: win.app.name
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                }
            }

            ListView {
                id: sideList
                x: 10; y: sideHeader.height + 2
                width: 232 - 20
                height: parent.height - y - 10
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: win.navSidebar
                delegate: Rectangle {
                    id: navItem
                    required property var modelData
                    required property int index
                    width: sideList.width; height: 36
                    radius: 9
                    color: modelData.active ? Theme.accentSoft : (navArea.containsMouse ? Theme.hover : "transparent")
                    Behavior on color { ColorAnimation { duration: 120 } }
                    opacity: 0
                    Component.onCompleted: navIn.start()
                    NumberAnimation { id: navIn; target: navItem; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutQuad }
                    Item {
                        id: navIcon
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        width: 20; height: 20
                        Image {
                            id: navSvg
                            anchors.fill: parent
                            source: navItem.modelData.icon ? win.svgUrl(navItem.modelData.icon, navItem.modelData.active ? Theme.accentText.toString() : Theme.text.toString())
                                                           : navItem.modelData.img
                            sourceSize: Qt.size(40, 40)
                            smooth: true
                            visible: status === Image.Ready
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            visible: navSvg.status !== Image.Ready
                            width: 20; height: 20; radius: 6
                            color: navItem.modelData.active ? Theme.accent : Theme.fill
                            Text {
                                anchors.centerIn: parent
                                text: navItem.modelData.label.charAt(0).toUpperCase()
                                color: navItem.modelData.active ? "white" : Theme.text2
                                font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold
                            }
                        }
                    }
                    Text {
                        anchors.left: navIcon.right; anchors.leftMargin: 12
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: navItem.modelData.label
                        elide: Text.ElideRight
                        color: navItem.modelData.active ? Theme.accentText : Theme.text
                        font.family: Theme.font; font.pixelSize: 13
                        font.weight: navItem.modelData.active ? Font.DemiBold : Font.Normal
                    }
                    MouseArea {
                        id: navArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            // od razu zaznacz kliknięte (strona potwierdzi przy następnym odczycie)
                            win.navSidebar = win.navSidebar.map(x => Object.assign({}, x, { active: x.id === navItem.modelData.id }));
                            win.navClick(navItem.modelData.id);
                        }
                    }
                }
            }
        }

        // ——— Pasek tytułu w kolorze aplikacji ———
        Rectangle {
            id: bar
            x: win.sideWidth
            width: parent.width - x
            height: win.pageFullScreen || win.integratedBar ? 0 : (win.showTopnav ? 50 : 42)
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
                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20
                    source: win.app.icon
                    sourceSize: Qt.size(40, 40)
                    smooth: true; mipmap: true
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.app.name
                    color: win.barText
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                }
            }

            Row {
                anchors.right: winButtons.left; anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Rectangle {
                    width: zoomLabel.implicitWidth + 14; height: 24; radius: 8
                    anchors.verticalCenter: parent.verticalCenter
                    visible: win.zoomShown > 0
                    color: win.barHover
                    Text { id: zoomLabel; anchors.centerIn: parent; text: Math.round(win.zoomShown * 100) + "%"; color: win.barText; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
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
                                font.family: Theme.font; font.pixelSize: 13
                                font.weight: tabBtn.modelData.active ? Font.DemiBold : Font.Medium
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
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line; visible: !win.barTinted }
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
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                HoverButton {
                    width: noText.implicitWidth + 24; height: 30; baseColor: Theme.fill
                    onClicked: permBar.answer(false)
                    Text { id: noText; anchors.centerIn: parent; text: "Nie zezwalaj"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                }
                Rectangle {
                    width: yesText.implicitWidth + 26; height: 30; radius: 8
                    color: Theme.accent
                    Text { id: yesText; anchors.centerIn: parent; text: "Zezwól"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
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
                backgroundColor: win.app.backgroundColor || "white"
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
                    } else if (o.type === "drag") {
                        win.startSystemMove();
                    } else if (o.type === "maximize") {
                        if (win.maxed) win.showNormal(); else win.showMaximized();
                    }
                }
                onLoadingChanged: (info) => {
                    if (info.status === WebEngineView.LoadSucceededStatus) {
                        if (win.debug) explainTimer.restart();
                        win.failed = false;
                        if (!win.everLoaded) splashOut.start();
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
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
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
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 19; font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Sprawdź połączenie z internetem — " + win.app.name + " spróbuje ponownie."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: retryText.implicitWidth + 32; height: 38; radius: 10
                        color: retryArea.containsMouse ? Qt.darker(Theme.accent, 1.1) : Theme.accent
                        Text { id: retryText; anchors.centerIn: parent; text: "Spróbuj ponownie"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
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
                Text { id: toastText; anchors.centerIn: parent; color: Theme.surface; font.family: Theme.font; font.pixelSize: 13 }
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
            color: Qt.alpha(Theme.surface, 0.9)
            border.width: 1; border.color: Theme.line
            Row {
                id: floatRow
                anchors.centerIn: parent
                spacing: 2
                FloatButton { icon: "back"; visible: web.canGoBack && !win.showSidebar; onClicked: web.goBack() }
                FloatButton { icon: web.loading ? "close" : "reload"; onClicked: if (web.loading) web.stop(); else web.reload() }
                FloatButton { id: floatMore; icon: "more"; onClicked: win.openMoreMenu(floatMore) }
                Item { width: 4; height: 1 }
                WindowButtons { window: win; anchors.verticalCenter: parent.verticalCenter; scale: 0.82; spacing: 4 }
            }
        }

        ContextMenu {
            id: menu
            onTriggered: (a) => win.runAction(a)
        }
    }

    // ——— Menu strony ———
    property var menuRequest: null
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

    component FloatButton: Rectangle {
        id: fbtn
        property string icon
        signal clicked()
        width: 28; height: 28; radius: 8
        color: fArea.containsMouse ? Theme.hover : "transparent"
        Icon { anchors.centerIn: parent; d: Icons[fbtn.icon] || ""; size: 15; color: Theme.text2 }
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
