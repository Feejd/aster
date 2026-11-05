pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Aster.Ui
import Aster.Store

// Sklep Aster: programy z Flathub. Pasek boczny (szukaj, kategorie, zainstalowane, aktualizacje),
// strona „Odkrywaj” (polecenie dnia, odpowiedniki programów z Windowsa, ranking, nowości),
// strony kategorii i wyników, strona aplikacji wsuwana z prawej.
Window {
    id: win
    property string openApp

    width: 1180 + 2 * m
    height: 780 + 2 * m
    minimumWidth: 860 + 2 * m
    minimumHeight: 560 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: "Sklep"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 12

    property string section: "discover"          // discover | kategoria Flathub | search | installed | updates
    property var popular: []
    property var fresh: []
    property var switchers: []
    property var heroApp: null
    readonly property var hero: Curated.heroOfTheDay()
    property var listApps: []                     // kategoria / wyniki
    property bool listLoading: false
    property var cache: ({})                      // appstream: id → {id, name, summary, icon}
    property int cacheVersion: 0

    readonly property string api: "https://flathub.org/api/v2/"
    function fetch(url, cb, body) {
        const x = new XMLHttpRequest();
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            try { cb(x.status === 200 ? JSON.parse(x.responseText) : null); } catch (e) { cb(null); }
        };
        x.open(body ? "POST" : "GET", url);
        if (body) x.setRequestHeader("Content-Type", "application/json");
        x.send(body ? JSON.stringify(body) : null);
    }
    // Dane jednej aplikacji (z pamięci albo z Flathub)
    function appInfo(id, cb) {
        if (cache[id]) { cb(cache[id]); return; }
        fetch(api + "appstream/" + id + "?locale=pl", (d) => {
            if (!d) return;
            const a = { id: id, name: d.name, summary: d.summary || "", icon: d.icon || "", dev: d.developer_name || "", shots: d.screenshots || [] };
            cache[id] = a;
            cacheVersion++;
            cb(a);
        });
    }

    function showSection(s) {
        section = s;
        detail.open = false;
        listApps = [];
        content.contentY = 0;
        if (s === "discover" || s === "installed" || s === "updates") return;
        if (s === "search") return;
        listLoading = true;
        fetch(api + "collection/category/" + s + "?page=1&per_page=48&locale=pl", (d) => {
            listLoading = false;
            if (win.section === s) win.listApps = d ? d.hits.map(Curated.short) : [];
        });
    }
    function search(q) {
        q = q.trim();
        if (!q) { showSection("discover"); return; }
        section = "search";
        detail.open = false;
        listLoading = true;
        listApps = [];
        fetch(api + "search?locale=pl", (d) => {
            listLoading = false;
            if (win.section === "search") win.listApps = d ? d.hits.slice(0, 48).map(Curated.short) : [];
        }, { query: q });
    }
    function openDetail(id) {
        detailPage.load(id);
        detail.open = true;
    }

    Component.onCompleted: {
        effectsTimer.restart();
        fetch(api + "collection/popular?page=1&per_page=12&locale=pl", (d) => win.popular = d ? d.hits.map(Curated.short) : []);
        fetch(api + "collection/recently-updated?page=1&per_page=12&locale=pl", (d) => win.fresh = d ? d.hits.map(Curated.short) : []);
        appInfo(hero.id, (a) => win.heroApp = a);
        Curated.switchers.forEach((s, i) => appInfo(s.id, (a) => {
            const list = win.switchers.slice();
            list[i] = Object.assign({ note: "zamiast " + s.instead }, a);
            win.switchers = list;
        }));
        if (openApp) openDetail(openApp);
    }
    // Zainstalowane / aktualizacje: dociągamy nazwy i ikony
    Connections {
        target: Flatpak
        function onInstalledChanged() { Flatpak.installed.forEach(id => win.appInfo(id, () => {})); }
        function onUpdatesChanged() { Flatpak.updates.forEach(id => win.appInfo(id, () => {})); }
        function onFinished(appId, action, ok, message) {
            const name = win.cache[appId] ? win.cache[appId].name : appId;
            if (!ok) win.toast((action === "install" ? "Nie udało się zainstalować: " : "Nie udało się: ") + name + (message ? " — " + message : ""));
            else if (action === "install") win.toast(name + " jest gotowy — znajdziesz go w Starcie");
            else if (action === "uninstall") win.toast("Usunięto: " + name);
            else win.toast("Wszystko jest aktualne");
        }
    }
    function idsToApps(ids) { cacheVersion; return ids.map(id => cache[id] || { id: id, name: id, summary: "", icon: "" }); }

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
            width: 240; height: parent.height
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }

            Rectangle {
                id: searchBox
                x: 16; y: 18
                width: parent.width - 32; height: 36; radius: 10
                color: Theme.fill
                border.width: field.activeFocus ? 1.5 : 0
                border.color: Theme.accent
                Icon { x: 11; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 15; color: Theme.text2 }
                TextInput {
                    id: field
                    x: 34; width: parent.width - 44
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                    selectionColor: Theme.accentSoft
                    clip: true
                    Keys.onReturnPressed: win.search(text)
                    Keys.onEnterPressed: win.search(text)
                    Keys.onEscapePressed: { text = ""; win.showSection("discover"); }
                    Text { visible: !field.text; text: "Szukaj programów"; color: Theme.text2; font: field.font }
                }
            }

            Column {
                id: nav
                x: 10; y: searchBox.y + searchBox.height + 14
                width: parent.width - 20
                spacing: 2
                Repeater {
                    model: Curated.categories
                    delegate: NavItem {
                        required property var modelData
                        label: modelData.name
                        icon: modelData.icon
                        active: win.section === modelData.id
                        onClicked: win.showSection(modelData.id)
                    }
                }
                Rectangle { width: parent.width; height: 1; color: Theme.line; opacity: 0.8 }
                Item { width: 1; height: 4 }
                NavItem {
                    label: "Zainstalowane"; icon: "check"
                    active: win.section === "installed"
                    onClicked: win.showSection("installed")
                }
                NavItem {
                    label: "Aktualizacje"; icon: "download"
                    badge: Flatpak.updates.length ? String(Flatpak.updates.length) : ""
                    active: win.section === "updates"
                    onClicked: win.showSection("updates")
                }
            }
        }

        // ——— Treść ———
        GlassPane {
            id: main
            x: side.width
            width: parent.width - side.width
            height: parent.height
            topRightRadius: win.r; bottomRightRadius: win.r

            Item {
                id: topBar
                width: parent.width; height: 52
                z: 20          // przyciski okna nad każdą stroną (także stroną aplikacji)
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }
                WindowButtons {
                    window: win
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Flickable {
                id: content
                anchors.fill: parent
                contentHeight: pageCol.height + 60
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                Column {
                    id: pageCol
                    x: 36; y: 14
                    width: main.width - 72
                    spacing: 26

                    // Nagłówek strony
                    Column {
                        spacing: 2
                        Text {
                            visible: win.section === "discover"
                            text: new Date().toLocaleDateString(Qt.locale("pl_PL"), "dddd, d MMMM").toUpperCase()
                            color: Theme.text2
                            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; font.letterSpacing: 0.6
                        }
                        Text {
                            text: win.section === "discover" ? "Odkrywaj"
                                : win.section === "search" ? "Wyniki: " + field.text
                                : win.section === "installed" ? "Zainstalowane"
                                : win.section === "updates" ? "Aktualizacje"
                                : (Curated.categories.find(c => c.id === win.section) || { name: "" }).name
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 34; font.weight: Font.Bold
                            font.letterSpacing: -0.9
                        }
                    }

                    // ——— Odkrywaj ———
                    // Polecenie dnia: kolorowa karta ze zrzutem ekranu aplikacji
                    Rectangle {
                        id: heroCard
                        visible: win.section === "discover"
                        width: pageCol.width; height: 320
                        radius: 24
                        clip: true
                        // zrzut ekranu przycięty do zaokrąglonych rogów karty
                        layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: heroMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0
                        }
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: win.hero.colors[1] }
                            GradientStop { position: 1; color: win.hero.colors[0] }
                        }
                        MouseArea { anchors.fill: parent; onClicked: win.openDetail(win.hero.id) }
                        RectangularShadow {
                            x: heroShot.x; y: heroShot.y
                            width: heroShot.width; height: heroShot.height
                            radius: 12; blur: 40; offset.y: 10
                            color: Qt.rgba(0, 0, 0, 0.35)
                            visible: heroShot.status === Image.Ready
                        }
                        Image {
                            id: heroShot
                            x: parent.width * 0.48; y: 46
                            width: parent.width * 0.6; height: parent.height
                            source: win.heroApp && win.heroApp.shots.length ? detailPage.shot(win.heroApp.shots[0]) : ""
                            fillMode: Image.PreserveAspectCrop
                            horizontalAlignment: Image.AlignLeft
                            verticalAlignment: Image.AlignTop
                            asynchronous: true
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                        }
                        Column {
                            x: 34; y: 34
                            width: parent.width * 0.42
                            spacing: 10
                            Text { text: win.hero.tag; color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; font.letterSpacing: 0.8 }
                            Text {
                                width: parent.width
                                text: win.hero.title
                                wrapMode: Text.Wrap
                                color: "white"
                                font.family: Theme.font; font.pixelSize: 32; font.weight: Font.Bold
                                font.letterSpacing: -0.8
                                lineHeight: 0.95
                            }
                        }
                        Row {
                            x: 34
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 28
                            spacing: 14
                            Image {
                                width: 56; height: 56
                                source: win.heroApp ? win.heroApp.icon : ""
                                sourceSize: Qt.size(112, 112)
                                smooth: true; mipmap: true
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 220
                                Text { width: parent.width; text: win.heroApp ? win.heroApp.name : ""; elide: Text.ElideRight; color: "white"; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                                Text { width: parent.width; text: win.heroApp ? win.heroApp.summary : ""; elide: Text.ElideRight; color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.font; font.pixelSize: 12 }
                            }
                            GetButton { anchors.verticalCenter: parent.verticalCenter; appId: win.hero.id; onDark: true }
                        }
                    }

                    Rectangle {
                        id: heroMask
                        width: heroCard.width; height: heroCard.height
                        radius: 24
                        visible: false
                        layer.enabled: true
                    }

                    // Przesiadasz się z Windowsa?
                    Column {
                        visible: win.section === "discover"
                        width: pageCol.width
                        spacing: 6
                        SectionTitle { title: "Przesiadasz się z Windowsa?"; subtitle: "Darmowe programy, które zastąpią te, których używałeś" }
                        Grid {
                            columns: 2
                            columnSpacing: 32
                            Repeater {
                                model: win.switchers.filter(s => !!s)
                                delegate: AppRow {
                                    required property var modelData
                                    width: (pageCol.width - 32) / 2
                                    app: modelData
                                    note: modelData.note
                                    onOpened: (id) => win.openDetail(id)
                                }
                            }
                        }
                    }

                    // Najpopularniejsze
                    Column {
                        visible: win.section === "discover"
                        width: pageCol.width
                        spacing: 6
                        SectionTitle { title: "Najpopularniejsze"; subtitle: "Najczęściej pobierane w tym miesiącu" }
                        Grid {
                            columns: 3
                            columnSpacing: 28
                            flow: Grid.TopToBottom
                            rows: 4
                            Repeater {
                                model: win.popular
                                delegate: AppRow {
                                    required property var modelData
                                    required property int index
                                    width: (pageCol.width - 56) / 3
                                    app: modelData
                                    rank: String(index + 1)
                                    separator: index % 4 !== 3
                                    onOpened: (id) => win.openDetail(id)
                                }
                            }
                        }
                    }

                    // Nowości — poziomy rząd kart
                    Column {
                        visible: win.section === "discover"
                        width: pageCol.width
                        spacing: 12
                        SectionTitle { title: "Świeżo zaktualizowane"; subtitle: "" }
                        ListView {
                            width: pageCol.width; height: 196
                            orientation: ListView.Horizontal
                            spacing: 14
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: win.fresh
                            delegate: Rectangle {
                                id: card
                                required property var modelData
                                width: 180; height: 196; radius: 18
                                color: cardArea.containsMouse ? Qt.darker(Theme.fill, 1.15) : Theme.fill
                                Behavior on color { ColorAnimation { duration: 120 } }
                                MouseArea { id: cardArea; anchors.fill: parent; hoverEnabled: true; onClicked: win.openDetail(card.modelData.id) }
                                Image {
                                    x: 18; y: 18; width: 64; height: 64
                                    source: card.modelData.icon
                                    sourceSize: Qt.size(128, 128)
                                    asynchronous: true; smooth: true; mipmap: true
                                }
                                Column {
                                    x: 18; y: 96; width: parent.width - 36
                                    spacing: 3
                                    Text { width: parent.width; text: card.modelData.name; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                                    Text { width: parent.width; text: card.modelData.summary; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                                }
                                GetButton { x: 18; anchors.bottom: parent.bottom; anchors.bottomMargin: 16; appId: card.modelData.id }
                            }
                        }
                    }

                    // ——— Kategoria / wyniki / zainstalowane / aktualizacje ———
                    Rectangle {
                        visible: win.section === "updates" && Flatpak.updates.length > 0
                        width: pageCol.width; height: 64; radius: 16
                        color: Theme.accentSoft
                        Text {
                            x: 20; anchors.verticalCenter: parent.verticalCenter
                            text: Flatpak.updates.length + (Flatpak.updates.length === 1 ? " program czeka na aktualizację" : " programów czeka na aktualizację")
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium
                        }
                        Rectangle {
                            anchors.right: parent.right; anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: updText.implicitWidth + 30; height: 36; radius: 18
                            color: Theme.accent
                            Text { id: updText; anchors.centerIn: parent; text: Flatpak.progress["*"] !== undefined ? "Aktualizuję…" : "Aktualizuj wszystko"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                            MouseArea { anchors.fill: parent; onClicked: Flatpak.updateAll() }
                        }
                    }
                    Grid {
                        visible: win.section !== "discover"
                        columns: pageCol.width > 900 ? 3 : 2
                        columnSpacing: 28
                        Repeater {
                            model: win.section === "installed" ? win.idsToApps(Flatpak.installed)
                                 : win.section === "updates" ? win.idsToApps(Flatpak.updates)
                                 : win.listApps
                            delegate: AppRow {
                                required property var modelData
                                width: (pageCol.width - (pageCol.width > 900 ? 56 : 28)) / (pageCol.width > 900 ? 3 : 2)
                                app: modelData
                                onOpened: (id) => win.openDetail(id)
                            }
                        }
                    }
                    Text {
                        visible: win.section !== "discover" && !win.listLoading
                                 && (win.section === "installed" ? Flatpak.installed.length === 0
                                     : win.section === "updates" ? Flatpak.updates.length === 0 : win.listApps.length === 0)
                        text: win.section === "installed" ? "Nie masz jeszcze programów ze Sklepu."
                            : win.section === "updates" ? "Wszystkie programy są aktualne."
                            : "Nic nie znaleziono."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 14
                    }
                    Text {
                        visible: win.listLoading
                        text: "Wczytuję…"
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 14
                    }
                }
            }

            // ——— Strona aplikacji: wsuwa się z prawej ———
            Item {
                id: detail
                property bool open: false
                z: 10
                width: parent.width; height: parent.height
                x: open ? 0 : parent.width + 20
                visible: x < parent.width
                Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutQuint } }
                AppPage {
                    id: detailPage
                    anchors.fill: parent
                    topRightRadius: win.r; bottomRightRadius: win.r
                    onBack: detail.open = false
                }
            }
        }

        // ——— Komunikat ———
        Rectangle {
            anchors.horizontalCenter: main.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: toastTimer.running ? 22 : -height
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
            width: Math.min(main.width - 40, toastText.implicitWidth + 36); height: 44; radius: 22
            color: Theme.text
            Text { id: toastText; anchors.centerIn: parent; width: Math.min(implicitWidth, parent.width - 30); elide: Text.ElideRight; color: Theme.surface; font.family: Theme.font; font.pixelSize: 13 }
        }
        Timer { id: toastTimer; interval: 4500 }

        // Brak flatpaka
        Rectangle {
            visible: !Flatpak.available
            anchors.horizontalCenter: main.horizontalCenter
            y: 14
            width: noFp.implicitWidth + 30; height: 34; radius: 17
            color: "#D93B3B"
            Text { id: noFp; anchors.centerIn: parent; text: "Brak programu flatpak — instalowanie jest wyłączone"; color: "white"; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
        }
    }
    function toast(text) { toastText.text = text; toastTimer.restart(); }

    component NavItem: Rectangle {
        id: ni
        property string label
        property string icon
        property string badge: ""
        property bool active: false
        signal clicked()
        width: parent ? parent.width : 200
        height: 36; radius: 9
        color: active ? Theme.accentSoft : (niArea.containsMouse ? Theme.hover : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }
        Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons[ni.icon] || ""; size: 17; color: ni.active ? Theme.accentText : Theme.text }
        Text { x: 38; anchors.verticalCenter: parent.verticalCenter; text: ni.label; color: ni.active ? Theme.accentText : Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: ni.active ? Font.Medium : Font.Normal }
        Rectangle {
            visible: ni.badge !== ""
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(20, bText.implicitWidth + 12); height: 20; radius: 10
            color: Theme.accent
            Text { id: bText; anchors.centerIn: parent; text: ni.badge; color: "white"; font.family: Theme.font; font.pixelSize: 11; font.letterSpacing: 0.1; font.weight: Font.DemiBold }
        }
        MouseArea { id: niArea; anchors.fill: parent; hoverEnabled: true; onClicked: ni.clicked() }
    }

    component SectionTitle: Column {
        id: st
        property string title
        property string subtitle
        spacing: 2
        bottomPadding: 6
        Rectangle { width: pageCol.width; height: 1; color: Theme.line }
        Item { width: 1; height: 10 }
        Text { text: st.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 21; font.weight: Font.Bold; font.letterSpacing: -0.4 }
        Text { visible: st.subtitle !== ""; text: st.subtitle; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
    }
}
