pragma ComponentBehavior: Bound
import QtCore
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Shapes
import QtQml.Models
import QtWebEngine
import Aster.Ui
import Aster.Browser

// Przeglądarka Aster. Okno bez ramki systemowej, jak Pliki: szkło, okrągłe przyciski, cień.
//  • jeden zwarty pasek: wstecz/dalej, adres na środku (pokazuje samą domenę, pełny adres po kliknięciu),
//    gwiazdka ulubionych, pobrane, nowa karta
//  • karty pod paskiem pojawiają się dopiero przy drugiej karcie
//  • pasek okna przybiera kolor strony (meta theme-color) — strona i okno wyglądają jak jedno
Window {
    id: win
    property string startUrl

    width: 1240 + 2 * m
    height: 800 + 2 * m
    minimumWidth: 640 + 2 * m
    minimumHeight: 420 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: cur ? cur.pageTitle : "Przeglądarka"

    property bool pageFullScreen: false
    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: maxed ? 0 : 24

    property int current: 0
    readonly property var cur: pages.count > 0 ? pages.itemAt(Math.min(current, pages.count - 1)) : null
    readonly property color tint: cur && cur.themeColor.a > 0 ? cur.themeColor : "transparent"
    property var closedTabs: []                    // do Ctrl+Shift+T
    property var downloads: []
    property var pendingPermission: null
    property var menuRequest: null

    // ——— Pamięć: ulubione i historia ———
    Settings {
        id: store
        category: "browser"
        property var favorites: [
            { url: "https://www.google.com/", title: "Google" },
            { url: "https://www.youtube.com/", title: "YouTube" },
            { url: "https://pl.wikipedia.org/", title: "Wikipedia" },
            { url: "https://allegro.pl/", title: "Allegro" },
            { url: "https://mail.google.com/", title: "Gmail" },
            { url: "https://www.facebook.com/", title: "Facebook" },
            { url: "https://www.onet.pl/", title: "Onet" },
            { url: "https://maps.google.com/", title: "Mapy" }
        ]
        property var history: []
    }
    readonly property var recents: {
        const seen = {}, out = [];
        for (let i = store.history.length - 1; i >= 0 && out.length < 8; --i) {
            const h = Urls.host(store.history[i].url);
            if (seen[h] || Urls.isSearch(store.history[i].url)) continue;
            seen[h] = true;
            out.push(store.history[i]);
        }
        return out;
    }
    function remember(url, title) {
        if (url.indexOf("http") !== 0) return;
        const h = store.history.slice(-400);
        if (h.length && h[h.length - 1].url === url) h[h.length - 1] = { url: url, title: title, time: Date.now() };
        else h.push({ url: url, title: title, time: Date.now() });
        store.history = h;
    }
    function isFavorite(url) { return store.favorites.some(f => f.url === url); }
    function toggleFavorite() {
        if (!cur || cur.blank) return;
        const u = cur.pageUrl;
        if (isFavorite(u)) store.favorites = store.favorites.filter(f => f.url !== u);
        else store.favorites = store.favorites.concat([{ url: u, title: cur.view.title }]);
    }

    // ——— Profil: ciasteczka i pamięć podręczna zostają między uruchomieniami ———
    WebEngineProfilePrototype {
        id: profilePrototype
        storageName: "aster"
        httpCacheType: WebEngineProfile.DiskHttpCache
        persistentCookiesPolicy: WebEngineProfile.AllowPersistentCookies
    }
    // Profil tworzony z prototypu dopiero po starcie okna (wcześniej instance() byłoby puste)
    property WebEngineProfile profile: null
    Connections {
        target: win.profile
        function onDownloadRequested(download) {
            const dir = StandardPaths.writableLocation(StandardPaths.DownloadLocation).toString().replace("file://", "");
            download.downloadDirectory = decodeURIComponent(dir);
            download.accept();
            win.downloads = win.downloads.concat([download]);
            downloadsPopup.shown = true;
            downloadsHide.restart();
        }
    }

    // ——— Karty ———
    ListModel { id: tabs }

    function newTab(url, background) {
        tabs.append({ startUrl: url || "", title: "Nowa karta", icon: "", loading: false });
        if (!background) current = tabs.count - 1;
        if (!url && !background) Qt.callLater(focusAddress);
        return pages.itemAt(tabs.count - 1);
    }
    function closeTab(i) {
        if (i < 0 || i >= tabs.count) return;
        const page = pages.itemAt(i) as BrowserTab;
        if (page && !page.blank) closedTabs = closedTabs.concat([page.pageUrl]).slice(-20);
        if (tabs.count === 1) { win.close(); return; }
        tabs.remove(i);
        if (current > i || current >= tabs.count) current = Math.max(0, current - 1);
    }
    function reopenTab() {
        if (!closedTabs.length) return;
        const u = closedTabs[closedTabs.length - 1];
        closedTabs = closedTabs.slice(0, -1);
        newTab(u);
    }
    function go(text) {
        const url = Urls.fixup(text);
        if (!url || !cur) return;
        cur.load(url);
        suggest.close();
        cur.view.forceActiveFocus();
    }
    function focusAddress() {
        field.forceActiveFocus();
        field.selectAll();
    }

    Component.onCompleted: {
        profile = profilePrototype.instance();
        newTab(startUrl);
        effectsTimer.restart();
    }

    // ——— Skróty ———
    Shortcut { sequence: "Ctrl+T"; onActivated: win.newTab("") }
    Shortcut { sequence: "Ctrl+W"; onActivated: win.closeTab(win.current) }
    Shortcut { sequence: "Ctrl+Shift+T"; onActivated: win.reopenTab() }
    Shortcut { sequences: ["Ctrl+L", "Alt+D", "F6"]; onActivated: win.focusAddress() }
    Shortcut { sequences: ["Ctrl+R", "F5"]; onActivated: if (win.cur) win.cur.view.reload() }
    Shortcut { sequence: "Alt+Left"; onActivated: if (win.cur) win.cur.view.goBack() }
    Shortcut { sequence: "Alt+Right"; onActivated: if (win.cur) win.cur.view.goForward() }
    Shortcut { sequence: "Ctrl+Tab"; onActivated: win.current = (win.current + 1) % tabs.count }
    Shortcut { sequence: "Ctrl+Shift+Tab"; onActivated: win.current = (win.current - 1 + tabs.count) % tabs.count }
    Shortcut { sequence: "Ctrl+F"; onActivated: findBar.openBar() }
    Shortcut { sequence: "Ctrl+D"; onActivated: win.toggleFavorite() }
    Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: win.zoom(0.1) }
    Shortcut { sequence: "Ctrl+-"; onActivated: win.zoom(-0.1) }
    Shortcut { sequence: "Ctrl+0"; onActivated: win.zoom(0) }
    Shortcut { sequence: "Escape"; onActivated: { if (findBar.shown) findBar.closeBar(); else if (win.cur && win.cur.view.loading) win.cur.view.stop(); } }
    Instantiator {
        model: 9
        delegate: Shortcut {
            required property int index
            sequence: "Ctrl+" + (index + 1)
            onActivated: win.current = Math.min(index, tabs.count - 1)
        }
    }

    property real zoomShown: 0
    function zoom(d) {
        if (!cur) return;
        cur.view.zoomFactor = d === 0 ? 1 : Math.max(0.3, Math.min(3, Math.round((cur.view.zoomFactor + d) * 10) / 10));
        zoomShown = cur.view.zoomFactor;
        zoomTimer.restart();
    }
    Timer { id: zoomTimer; interval: 1400; onTriggered: win.zoomShown = 0 }

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

        // Kolor strony rozlany na pasku okna
        Rectangle {
            width: parent.width; height: chrome.height
            topLeftRadius: win.r; topRightRadius: win.r
            color: win.tint
            opacity: win.tint.a > 0 ? 0.22 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }
            Behavior on color { ColorAnimation { duration: 300 } }
        }

        // ——— Pasek okna ———
        Item {
            id: chrome
            width: parent.width
            height: win.pageFullScreen ? 0 : toolbar.height + tabStrip.height
            visible: !win.pageFullScreen
            clip: true

            Item {
                id: toolbar
                width: parent.width; height: 52

                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }

                Row {
                    id: nav
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    ToolBtn { icon: "back"; enabled: !!win.cur && win.cur.view.canGoBack; onClicked: win.cur.view.goBack() }
                    ToolBtn { icon: "forward"; enabled: !!win.cur && win.cur.view.canGoForward; onClicked: win.cur.view.goForward() }
                }

                // ——— Pasek adresu ———
                Rectangle {
                    id: address
                    width: Math.min(620, Math.max(280, toolbar.width - 2 * 230))
                    height: 36
                    anchors.centerIn: parent
                    radius: 11
                    color: field.activeFocus ? Theme.surface : Theme.fill
                    border.width: field.activeFocus ? 1.5 : 0
                    border.color: Theme.accent
                    Behavior on color { ColorAnimation { duration: 120 } }

                    // Postęp wczytywania — cienka linia przy dolnej krawędzi
                    Rectangle {
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 1
                        x: 8
                        height: 2; radius: 1
                        width: (parent.width - 16) * (win.cur ? win.cur.view.loadProgress / 100 : 0)
                        color: Theme.accent
                        opacity: win.cur && win.cur.view.loading ? 1 : 0
                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                    }

                    Icon {
                        id: siteIcon
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        d: !win.cur || win.cur.blank || field.activeFocus ? Icons.search : (win.cur.secure ? Icons.lock : Icons.globe)
                        size: 15
                        color: Theme.text2
                    }

                    // Bez fokusu: sama domena na środku (albo zapytanie wyszukiwania)
                    Text {
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 90)
                        visible: !field.activeFocus
                        elide: Text.ElideRight
                        text: !win.cur || win.cur.blank ? "Szukaj albo wpisz adres"
                              : Urls.isSearch(win.cur.pageUrl) ? Urls.searchQuery(win.cur.pageUrl)
                              : Urls.host(win.cur.pageUrl)
                        color: !win.cur || win.cur.blank ? Theme.text2 : Theme.text
                        font.family: Theme.font; font.pixelSize: 14
                        font.weight: !win.cur || win.cur.blank ? Font.Normal : Font.Medium
                        MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: win.focusAddress() }
                    }
                    MouseArea {
                        anchors.fill: parent
                        visible: !field.activeFocus
                        onClicked: win.focusAddress()
                    }

                    TextInput {
                        id: field
                        anchors.left: siteIcon.right; anchors.leftMargin: 10
                        anchors.right: addrButtons.left; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: activeFocus ? 1 : 0
                        clip: true
                        color: Theme.text
                        selectionColor: Theme.accentSoft
                        selectedTextColor: Theme.text
                        font.family: Theme.font; font.pixelSize: 14
                        selectByMouse: true
                        property bool typing: false
                        onActiveFocusChanged: {
                            if (activeFocus) {
                                text = win.cur && !win.cur.blank ? win.cur.pageUrl : "";
                                typing = false;
                                selectAll();
                            } else suggest.close();
                        }
                        onTextEdited: { typing = true; suggest.update(text); }
                        Keys.onReturnPressed: suggest.accept()
                        Keys.onEnterPressed: suggest.accept()
                        Keys.onEscapePressed: { suggest.close(); if (win.cur) win.cur.view.forceActiveFocus(); }
                        Keys.onDownPressed: suggest.move(1)
                        Keys.onUpPressed: suggest.move(-1)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !field.text
                            text: "Szukaj w Google albo wpisz adres"
                            color: Theme.text2
                            font: field.font
                        }
                    }

                    Row {
                        id: addrButtons
                        anchors.right: parent.right; anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        // Gwiazdka: dodaj / usuń z ulubionych
                        HoverButton {
                            width: 30; height: 30
                            visible: !!win.cur && !win.cur.blank && !field.activeFocus
                            onClicked: win.toggleFavorite()
                            Shape {
                                id: star
                                anchors.centerIn: parent
                                width: 24; height: 24
                                scale: 15 / 24
                                preferredRendererType: Shape.CurveRenderer
                                readonly property bool on: !!win.cur && win.isFavorite(win.cur.pageUrl)
                                ShapePath {
                                    strokeColor: star.on ? "#F2B33D" : Theme.text2
                                    fillColor: star.on ? "#F2B33D" : "transparent"
                                    strokeWidth: 1.9
                                    joinStyle: ShapePath.RoundJoin
                                    PathSvg { path: Icons.star }
                                }
                            }
                        }
                        // Zainstaluj stronę jako aplikację (otwiera menedżer Aplikacji webowych z gotowym podglądem)
                        HoverButton {
                            width: 30; height: 30
                            visible: !!win.cur && !win.cur.blank && !field.activeFocus
                            onClicked: win.installAsApp()
                            Icon { anchors.centerIn: parent; d: Icons.webapp; size: 15; color: Theme.text2 }
                        }
                        // Odśwież / zatrzymaj
                        HoverButton {
                            width: 30; height: 30
                            visible: !!win.cur && !win.cur.blank
                            onClicked: if (win.cur.view.loading) win.cur.view.stop(); else win.cur.view.reload()
                            Icon {
                                anchors.centerIn: parent
                                d: win.cur && win.cur.view.loading ? Icons.close : Icons.reload
                                size: 15; color: Theme.text2
                            }
                        }
                    }

                    // Powiększenie strony (po Ctrl +/-)
                    Rectangle {
                        anchors.right: parent.right; anchors.rightMargin: 70
                        anchors.verticalCenter: parent.verticalCenter
                        width: zoomText.implicitWidth + 16; height: 24; radius: 8
                        color: Theme.accentSoft
                        visible: win.zoomShown > 0
                        Text { id: zoomText; anchors.centerIn: parent; text: Math.round(win.zoomShown * 100) + "%"; color: Theme.accentText; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                    }
                }

                Row {
                    anchors.right: winButtons.left; anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    // Pobrane (z kółkiem postępu, gdy coś się pobiera)
                    HoverButton {
                        id: dlButton
                        width: 34; height: 32
                        visible: win.downloads.length > 0
                        onClicked: downloadsPopup.shown = !downloadsPopup.shown
                        readonly property real progress: {
                            let got = 0, total = 0;
                            for (const d of win.downloads) if (!d.isFinished && d.totalBytes > 0) { got += d.receivedBytes; total += d.totalBytes; }
                            return total > 0 ? got / total : -1;
                        }
                        Icon { anchors.centerIn: parent; d: Icons.download; size: 17; color: dlButton.progress >= 0 ? Theme.accentText : Theme.text }
                        Shape {
                            anchors.centerIn: parent
                            width: 28; height: 28
                            visible: dlButton.progress >= 0
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeColor: Theme.accent; strokeWidth: 2.2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                PathAngleArc { centerX: 14; centerY: 14; radiusX: 12; radiusY: 12; startAngle: -90; sweepAngle: 360 * Math.max(0.02, dlButton.progress) }
                            }
                        }
                    }
                    ToolBtn { icon: "plus"; onClicked: win.newTab("") }
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
                height: tabs.count > 1 ? 38 : 0
                visible: height > 0
                clip: true
                Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

                Row {
                    id: tabRow
                    x: 10
                    spacing: 4
                    readonly property real tabWidth: Math.min(240, (tabStrip.width - 20 - (tabs.count - 1) * 4) / Math.max(1, tabs.count))
                    Repeater {
                        model: tabs
                        delegate: Rectangle {
                            id: tabItem
                            required property int index
                            required property string title
                            required property string icon
                            required property bool loading
                            readonly property bool active: index === win.current
                            width: tabRow.tabWidth; height: 30
                            radius: 9
                            color: active ? Theme.surface : (tabArea.containsMouse ? Theme.hover : "transparent")
                            border.width: active ? 1 : 0
                            border.color: Theme.line
                            Behavior on color { ColorAnimation { duration: 120 } }

                            // Nowa karta „rozkłada się” od zera
                            transform: Scale { id: tabScale; origin.y: 15; yScale: 1 }
                            Component.onCompleted: { opacity = 0; tabIn.start(); }
                            ParallelAnimation {
                                id: tabIn
                                NumberAnimation { target: tabItem; property: "opacity"; to: 1; duration: 140 }
                                NumberAnimation { target: tabScale; property: "yScale"; from: 0.6; to: 1; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                            }

                            Item {
                                id: favicon
                                x: 10; anchors.verticalCenter: parent.verticalCenter
                                width: 16; height: 16
                                Image {
                                    anchors.fill: parent
                                    source: tabItem.icon
                                    visible: !!tabItem.icon && !tabItem.loading
                                    sourceSize: Qt.size(32, 32)
                                }
                                Icon {
                                    anchors.centerIn: parent
                                    visible: !tabItem.icon && !tabItem.loading
                                    d: Icons.globe; size: 14; color: Theme.text2
                                }
                                // Kręcące się kółko podczas wczytywania
                                Shape {
                                    anchors.fill: parent
                                    visible: tabItem.loading
                                    preferredRendererType: Shape.CurveRenderer
                                    RotationAnimation on rotation { running: tabItem.loading; from: 0; to: 360; duration: 800; loops: Animation.Infinite }
                                    ShapePath {
                                        strokeColor: Theme.accent; strokeWidth: 2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                                        PathAngleArc { centerX: 8; centerY: 8; radiusX: 6; radiusY: 6; startAngle: 0; sweepAngle: 260 }
                                    }
                                }
                            }
                            Text {
                                anchors.left: favicon.right; anchors.leftMargin: 8
                                anchors.right: closeBtn.left; anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                text: tabItem.title
                                elide: Text.ElideRight
                                color: tabItem.active ? Theme.text : Theme.text2
                                font.family: Theme.font; font.pixelSize: 12
                                font.weight: tabItem.active ? Font.Medium : Font.Normal
                            }
                            MouseArea {
                                id: tabArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onClicked: (m) => { if (m.button === Qt.MiddleButton) win.closeTab(tabItem.index); else win.current = tabItem.index; }
                            }
                            Rectangle {
                                id: closeBtn
                                anchors.right: parent.right; anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20; height: 20; radius: 6
                                visible: tabItem.active || tabArea.containsMouse || closeArea.containsMouse
                                color: closeArea.containsMouse ? Theme.hover : "transparent"
                                Icon { anchors.centerIn: parent; d: Icons.close; size: 11; stroke: 2; color: Theme.text2 }
                                MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; onClicked: win.closeTab(tabItem.index) }
                            }
                        }
                    }
                }
            }
        }

        // ——— Prośba strony o uprawnienie ———
        Rectangle {
            id: permBar
            y: chrome.height
            width: parent.width
            height: win.pendingPermission ? 48 : 0
            visible: height > 0
            clip: true
            color: Theme.surface
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
            readonly property var names: ({
                MediaAudioCapture: "używać mikrofonu",
                MediaVideoCapture: "używać kamery",
                MediaAudioVideoCapture: "używać kamery i mikrofonu",
                DesktopVideoCapture: "udostępniać ekran",
                DesktopAudioVideoCapture: "udostępniać ekran z dźwiękiem",
                Geolocation: "znać Twoją lokalizację",
                Notifications: "wysyłać powiadomienia",
                ClipboardReadWrite: "czytać schowek",
                MouseLock: "przejąć kursor myszy",
                LocalFontsAccess: "widzieć zainstalowane czcionki"
            })
            function answer(grant) {
                if (!win.pendingPermission) return;
                if (grant) win.pendingPermission.grant(); else win.pendingPermission.deny();
                win.pendingPermission = null;
            }
            Row {
                x: 18; anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.lock; size: 16; color: Theme.accentText }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.pendingPermission
                          ? "<b>" + Urls.host(win.pendingPermission.origin.toString()) + "</b> chce " + (permBar.names[["Unsupported", "MediaAudioCapture", "MediaVideoCapture", "MediaAudioVideoCapture", "DesktopVideoCapture", "DesktopAudioVideoCapture", "MouseLock", "Notifications", "Geolocation", "ClipboardReadWrite", "LocalFontsAccess"][win.pendingPermission.permissionType]] || "uzyskać dodatkowe uprawnienie")
                          : ""
                    textFormat: Text.StyledText
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 13
                }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                HoverButton {
                    width: denyText.implicitWidth + 24; height: 32; baseColor: Theme.fill
                    onClicked: permBar.answer(false)
                    Text { id: denyText; anchors.centerIn: parent; text: "Nie zezwalaj"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                }
                Rectangle {
                    width: allowText.implicitWidth + 26; height: 32; radius: 8
                    color: allowArea.containsMouse ? Qt.darker(Theme.accent, 1.1) : Theme.accent
                    Text { id: allowText; anchors.centerIn: parent; text: "Zezwól"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                    MouseArea { id: allowArea; anchors.fill: parent; hoverEnabled: true; onClicked: permBar.answer(true) }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        }

        // ——— Strony: pływająca karta pod paskiem okna ———
        GlassPane {
            visible: !win.pageFullScreen
            x: content.x; y: content.y
            width: content.width; height: content.height
            radius: contentMask.radius
        }
        Item {
            id: content
            x: win.pageFullScreen ? 0 : 8
            y: chrome.height + permBar.height
            width: parent.width - 2 * x
            height: parent.height - y - x
            clip: true

            // Zaokrąglone dolne rogi strony (maska), gdy okno nie jest zmaksymalizowane
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
                    anchors.fill: parent
                    visible: index === win.current
                    profile: win.profile
                    initialUrl: startUrl
                    favorites: store.favorites
                    recents: win.recents

                    onPageTitleChanged: tabs.setProperty(index, "title", pageTitle)
                    onPageIconChanged: tabs.setProperty(index, "icon", pageIcon)
                    Connections {
                        target: page.view
                        function onLoadingChanged() { tabs.setProperty(page.index, "loading", page.view.loading); }
                    }
                    onVisited: (url, title) => win.remember(url, title)
                    onRemoveFavorite: (url) => store.favorites = store.favorites.filter(f => f.url !== url)
                    onPermissionAsked: (permission) => { win.current = index; win.pendingPermission = permission; }
                    onNewWindow: (request) => {
                        const bg = request.destination === WebEngineNewWindowRequest.InNewBackgroundTab;
                        const t = win.newTab("about:blank", bg);
                        if (t) request.openIn(t.view);
                    }
                    onFullScreen: (request) => {
                        request.accept();
                        win.pageFullScreen = request.toggleOn;
                        if (request.toggleOn) win.showFullScreen(); else win.showNormal();
                    }
                    onContextMenu: (request) => win.showPageMenu(request)
                    onFindResult: (active, total) => { findBar.active = active; findBar.total = total; }
                }
            }

            // ——— Szukaj na stronie (Ctrl+F) ———
            Rectangle {
                id: findBar
                property bool shown: false
                property int active: 0
                property int total: 0
                function openBar() { shown = true; findField.forceActiveFocus(); findField.selectAll(); }
                function closeBar() { shown = false; if (win.cur) { win.cur.view.findText(""); win.cur.view.forceActiveFocus(); } }
                function find(back) { if (win.cur) win.cur.view.findText(findField.text, back ? WebEngineView.FindBackward : 0); }
                anchors.right: parent.right; anchors.rightMargin: 16
                y: shown ? 14 : -height - 10
                Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                width: 340; height: 44; radius: 14
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.6; shadowVerticalOffset: 6; shadowColor: Theme.shadow }
                Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 15; color: Theme.text2 }
                TextInput {
                    id: findField
                    x: 38; width: 170
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
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
                Row {
                    id: findNav
                    anchors.right: parent.right; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    ToolBtn { icon: "up"; width: 28; onClicked: findBar.find(true) }
                    ToolBtn { icon: "chevronDown"; width: 28; onClicked: findBar.find(false) }
                    ToolBtn { icon: "close"; width: 28; onClicked: findBar.closeBar() }
                }
            }
        }
        Rectangle {
            id: contentMask
            visible: false
            layer.enabled: true
            width: content.width; height: content.height
            radius: win.pageFullScreen ? 0 : Math.max(10, win.r - 8)
            color: "black"
        }

        // ——— Podpowiedzi pod paskiem adresu ———
        Rectangle {
            id: suggest
            property var items: []
            property int index: 0
            function update(text) {
                const t = text.trim().toLowerCase();
                if (!t) { close(); return; }
                const out = [{ kind: "go", label: text.trim(), url: Urls.fixup(text) }];
                const seen = {};
                for (let i = store.history.length - 1; i >= 0 && out.length < 7; --i) {
                    const h = store.history[i];
                    if (seen[h.url] || Urls.isSearch(h.url)) continue;
                    if (h.url.toLowerCase().indexOf(t) >= 0 || (h.title || "").toLowerCase().indexOf(t) >= 0) {
                        seen[h.url] = true;
                        out.push({ kind: "history", label: h.title || Urls.host(h.url), url: h.url });
                    }
                }
                items = out;
                index = 0;
            }
            function close() { items = []; }
            function move(d) { if (items.length) index = (index + d + items.length) % items.length; }
            function accept() {
                if (items.length && index > 0) { win.cur.load(items[index].url); close(); win.cur.view.forceActiveFocus(); }
                else win.go(field.text);
            }
            visible: items.length > 0 && field.activeFocus
            x: address.mapToItem(frame, 0, 0).x
            y: address.mapToItem(frame, 0, 0).y + address.height + 6
            width: address.width
            height: sugCol.implicitHeight + 12
            radius: 14
            color: Theme.surface
            border.width: 1; border.color: Theme.edge
            z: 50
            layer.enabled: true
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
                        radius: 9
                        color: suggest.index === index ? Theme.accentSoft : (sugArea.containsMouse ? Theme.hover : "transparent")
                        Icon {
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            d: sug.modelData.kind === "go" ? (Urls.isSearch(sug.modelData.url) ? Icons.search : Icons.globe) : Icons.undo
                            size: 15; color: Theme.text2
                        }
                        Text {
                            x: 36; width: parent.width - 46
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            textFormat: Text.StyledText
                            text: sug.modelData.kind === "go"
                                  ? (Urls.isSearch(sug.modelData.url) ? "Szukaj w Google: <b>" + sug.modelData.label + "</b>" : "Otwórz <b>" + Urls.host(sug.modelData.url) + "</b>")
                                  : sug.modelData.label + "  <font color=\"" + Theme.text2 + "\">— " + Urls.host(sug.modelData.url) + "</font>"
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 13
                        }
                        MouseArea {
                            id: sugArea; anchors.fill: parent; hoverEnabled: true
                            onClicked: { suggest.index = sug.index; suggest.accept(); }
                        }
                    }
                }
            }
        }

        // ——— Pobrane ———
        Rectangle {
            id: downloadsPopup
            property bool shown: false
            visible: opacity > 0
            opacity: shown && win.downloads.length ? 1 : 0
            scale: shown ? 1 : 0.96
            transformOrigin: Item.TopRight
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutQuint } }
            anchors.right: parent.right; anchors.rightMargin: 120
            y: 50
            width: 340
            height: dlCol.implicitHeight + 24
            radius: 16
            color: Theme.surface
            border.width: 1; border.color: Theme.edge
            z: 60
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.8; shadowVerticalOffset: 10; shadowColor: Theme.shadow }
            HoverHandler { id: dlHover; onHoveredChanged: if (hovered) downloadsHide.stop(); else downloadsHide.restart() }
            Timer { id: downloadsHide; interval: 3500; onTriggered: if (!dlHover.hovered) downloadsPopup.shown = false }
            Column {
                id: dlCol
                x: 12; y: 12
                width: parent.width - 24
                spacing: 4
                Text { text: "Pobrane"; leftPadding: 6; bottomPadding: 4; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                Repeater {
                    model: win.downloads.slice().reverse().slice(0, 6)
                    delegate: Rectangle {
                        id: dl
                        required property var modelData
                        width: dlCol.width; height: 52
                        radius: 10
                        color: dlArea.containsMouse ? Theme.hover : "transparent"
                        readonly property bool done: modelData.state === WebEngineDownloadRequest.DownloadCompleted
                        readonly property bool failed: modelData.state === WebEngineDownloadRequest.DownloadCancelled || modelData.state === WebEngineDownloadRequest.DownloadInterrupted
                        Rectangle {
                            x: 8; anchors.verticalCenter: parent.verticalCenter
                            width: 34; height: 34; radius: 9
                            color: Theme.accentSoft
                            Icon { anchors.centerIn: parent; d: dl.done ? Icons.check : Icons.download; size: 16; color: Theme.accentText }
                        }
                        Column {
                            x: 52; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 62
                            spacing: 4
                            Text { width: parent.width; text: dl.modelData.downloadFileName; elide: Text.ElideMiddle; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                            Rectangle {
                                visible: !dl.done && !dl.failed
                                width: parent.width; height: 4; radius: 2; color: Theme.line
                                Rectangle { width: parent.width * (dl.modelData.totalBytes > 0 ? dl.modelData.receivedBytes / dl.modelData.totalBytes : 0.1); height: 4; radius: 2; color: Theme.accent }
                            }
                            Text {
                                visible: dl.done || dl.failed
                                text: dl.failed ? "Przerwano" : "Gotowe — kliknij, żeby otworzyć"
                                color: dl.failed ? Theme.danger : Theme.text2
                                font.family: Theme.font; font.pixelSize: 11; font.letterSpacing: 0.1
                            }
                        }
                        MouseArea {
                            id: dlArea; anchors.fill: parent; hoverEnabled: true
                            onClicked: if (dl.done) Qt.openUrlExternally("file://" + dl.modelData.downloadDirectory + "/" + dl.modelData.downloadFileName)
                        }
                    }
                }
            }
        }

        // ——— Menu strony (prawy przycisk) ———
        ContextMenu {
            id: menu
            onTriggered: (a) => win.runMenuAction(a)
        }
    }

    function showPageMenu(request) {
        menuRequest = request;
        const p = content.mapToItem(frame, request.position.x, request.position.y);
        const items = [];
        if (request.linkUrl.toString()) {
            items.push({ label: "Otwórz link w nowej karcie", icon: "plus", action: "linkTab" });
            items.push({ label: "Kopiuj adres linku", icon: "copy", action: "copyLink" });
            items.push({ separator: true });
        }
        if (request.mediaType === ContextMenuRequest.MediaTypeImage) {
            items.push({ label: "Otwórz obraz w nowej karcie", icon: "image", action: "imageTab" });
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
            items.push({ label: "Szukaj w Google: „" + request.selectedText.slice(0, 24) + (request.selectedText.length > 24 ? "…" : "") + "”", icon: "search", action: "searchSel" });
        } else {
            items.push({ label: "Wstecz", icon: "back", shortcut: "Alt+←", action: "back", enabled: cur.view.canGoBack });
            items.push({ label: "Dalej", icon: "forward", shortcut: "Alt+→", action: "forward", enabled: cur.view.canGoForward });
            items.push({ label: "Odśwież", icon: "reload", shortcut: "Ctrl+R", action: "reload" });
            items.push({ separator: true });
            items.push({ label: isFavorite(cur.pageUrl) ? "Usuń z ulubionych" : "Dodaj do ulubionych", icon: "star", shortcut: "Ctrl+D", action: "favorite" });
            items.push({ label: "Szukaj na stronie", icon: "search", shortcut: "Ctrl+F", action: "find" });
            items.push({ label: "Zainstaluj jako aplikację…", icon: "webapp", action: "installApp" });
        }
        menu.openAt(p.x, p.y, items);
    }
    function runMenuAction(a) {
        const r = menuRequest, v = cur ? cur.view : null;
        if (!v) return;
        if (a === "linkTab") newTab(r.linkUrl.toString(), true);
        else if (a === "copyLink") v.triggerWebAction(WebEngineView.CopyLinkToClipboard);
        else if (a === "imageTab") newTab(r.mediaUrl.toString(), true);
        else if (a === "saveImage") v.triggerWebAction(WebEngineView.DownloadImageToDisk);
        else if (a === "copyImage") v.triggerWebAction(WebEngineView.CopyImageToClipboard);
        else if (a === "cut") v.triggerWebAction(WebEngineView.Cut);
        else if (a === "copy") v.triggerWebAction(WebEngineView.Copy);
        else if (a === "paste") v.triggerWebAction(WebEngineView.Paste);
        else if (a === "searchSel") newTab(Urls.searchUrl + encodeURIComponent(r.selectedText));
        else if (a === "back") v.goBack();
        else if (a === "forward") v.goForward();
        else if (a === "reload") v.reload();
        else if (a === "favorite") toggleFavorite();
        else if (a === "find") findBar.openBar();
        else if (a === "installApp") installAsApp();
    }
    function installAsApp() {
        if (cur && !cur.blank) Qt.openUrlExternally("aster-webapp:install?url=" + encodeURIComponent(cur.pageUrl));
    }
}
