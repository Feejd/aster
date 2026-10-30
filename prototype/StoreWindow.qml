import QtQuick
import QtQuick.Shapes
import "Icons.js" as I

// Sklep z aplikacjami: Odkrywaj (karty redakcyjne, ranking), kategorie, wyszukiwanie,
// aktualizacje i strona aplikacji. „Pobierz” pokazuje postęp, a po instalacji aplikacja trafia do doku.
// Opisy, oceny i rozmiary są przykładowe.
AppWindow {
    id: st
    property var sys
    property string page: "discover"
    property var detail: null
    property var progressMap: ({})
    property int rev: 0
    readonly property string query: search.text.trim().toLowerCase()
    signal installed(var app)
    signal launched(var app)

    sidebarWidth: 220

    readonly property var catalog: [
        { name: "Spotify", sub: "Muzyka i podcasty", cat: "fun", icon: "music", color: "#1F9D55", dev: "Spotify AB", size: "180 MB", rating: "4,6", desc: "Miliony utworów i podcastów. Twórz playlisty, słuchaj offline i odkrywaj muzykę dopasowaną do Ciebie." },
        { name: "Discord", sub: "Rozmowy głosowe i czaty", cat: "fun", icon: "headphones", color: "#5865F2", dev: "Discord Inc.", size: "95 MB", rating: "4,5", desc: "Rozmawiaj ze znajomymi głosem, wideo i na czacie. Twórz serwery dla swoich społeczności." },
        { name: "Steam", sub: "Twoja biblioteka gier", cat: "play", icon: "desktop", color: "#2A475E", dev: "Valve", size: "320 MB", rating: "4,7", desc: "Tysiące gier, w tym większość tytułów z Windowsa — uruchamianych przez warstwę zgodności, bez konfigurowania." },
        { name: "GIMP", sub: "Edycja zdjęć i grafiki", cat: "create", icon: "pencil", color: "#7A6650", dev: "Zespół GIMP", size: "210 MB", rating: "4,3", desc: "Darmowy edytor zdjęć z warstwami, maskami i filtrami. Dobra alternatywa dla Photoshopa." },
        { name: "Krita", sub: "Malowanie cyfrowe", cat: "create", icon: "pencil", color: "#D9468F", dev: "Fundacja Krita", size: "260 MB", rating: "4,8", desc: "Profesjonalne pędzle, warstwy i stabilizacja linii. Ulubione narzędzie ilustratorów." },
        { name: "Blender", sub: "Grafika 3D i animacja", cat: "create", icon: "sparkle", color: "#F07A2A", dev: "Fundacja Blender", size: "380 MB", rating: "4,9", desc: "Modelowanie, rzeźbienie, animacja i montaż — kompletne studio 3D za darmo." },
        { name: "OBS Studio", sub: "Nagrywanie i streaming", cat: "create", icon: "screenshot", color: "#3A3940", dev: "Projekt OBS", size: "110 MB", rating: "4,6", desc: "Nagrywaj ekran i transmituj na żywo z wieloma scenami i źródłami." },
        { name: "VLC", sub: "Odtwarza wszystko", cat: "fun", icon: "volume", color: "#F08A24", dev: "VideoLAN", size: "60 MB", rating: "4,7", desc: "Filmy i muzyka w każdym formacie, bez instalowania dodatkowych kodeków." },
        { name: "Firefox", sub: "Szybka i prywatna przeglądarka", cat: "work", icon: "globe", color: "#FF6A3D", dev: "Mozilla", size: "90 MB", rating: "4,6", desc: "Blokuje śledzące skrypty, synchronizuje zakładki i hasła między urządzeniami." },
        { name: "Thunderbird", sub: "Poczta i kalendarz", cat: "work", icon: "mail", color: "#1F7AE0", dev: "MZLA", size: "85 MB", rating: "4,4", desc: "Wszystkie skrzynki w jednym miejscu — Gmail, Outlook i inne — z kalendarzem i kontaktami." },
        { name: "OnlyOffice", sub: "Dokumenty zgodne z Wordem", cat: "work", icon: "doc", color: "#E8613A", dev: "Ascensio System", size: "350 MB", rating: "4,5", desc: "Dokumenty, arkusze i prezentacje, które otwierają pliki Worda, Excela i PowerPointa tak, jak je zapisano." },
        { name: "Zoom", sub: "Spotkania wideo", cat: "work", icon: "eye", color: "#2D7FF9", dev: "Zoom Communications", size: "140 MB", rating: "4,2", desc: "Spotkania, webinary i czat zespołowy." },
        { name: "Signal", sub: "Prywatne wiadomości", cat: "tools", icon: "bell", color: "#3A76F0", dev: "Fundacja Signal", size: "120 MB", rating: "4,7", desc: "Szyfrowane rozmowy i połączenia, zsynchronizowane z telefonem." },
        { name: "Bitwarden", sub: "Menedżer haseł", cat: "tools", icon: "lock", color: "#175DDC", dev: "Bitwarden Inc.", size: "70 MB", rating: "4,8", desc: "Bezpiecznie przechowuj hasła i wypełniaj je jednym kliknięciem." },
        { name: "SuperTuxKart", sub: "Wyścigi gokartów", cat: "play", icon: "sun", color: "#E0A419", dev: "Zespół STK", size: "650 MB", rating: "4,6", desc: "Kolorowe wyścigi dla całej rodziny, także w trybie wieloosobowym." },
        { name: "0 A.D.", sub: "Strategia historyczna", cat: "play", icon: "drive", color: "#8A6A3A", dev: "Wildfire Games", size: "1,9 GB", rating: "4,5", desc: "Zbuduj starożytną cywilizację i poprowadź ją do zwycięstwa." }
    ]
    readonly property var categories: [
        { id: "discover", name: "Odkrywaj", icon: "sparkle" },
        { id: "work", name: "Pracuj", icon: "doc" },
        { id: "create", name: "Twórz", icon: "pencil" },
        { id: "play", name: "Graj", icon: "desktop" },
        { id: "fun", name: "Rozrywka", icon: "music" },
        { id: "tools", name: "Narzędzia", icon: "sliders" },
        { id: "updates", name: "Aktualizacje", icon: "download" }
    ]
    function app(name) { return catalog.find(a => a.name === name) }
    function prog(name) { rev; return progressMap[name] === undefined ? -1 : progressMap[name] }
    function startInstall(a) {
        progressMap[a.name] = 0;
        rev++;
    }
    function openApp(a) { st.launched(a) }

    Timer {
        interval: 40; repeat: true
        running: { st.rev; return Object.keys(st.progressMap).some(k => st.progressMap[k] >= 0 && st.progressMap[k] < 1); }
        onTriggered: {
            for (const k in st.progressMap) {
                const v = st.progressMap[k];
                if (v >= 0 && v < 1) {
                    st.progressMap[k] = Math.min(1, v + 0.028 + Math.random() * 0.02);
                    if (st.progressMap[k] >= 1) st.installed(st.app(k));
                }
            }
            st.rev++;
        }
    }

    // ——— Pasek boczny ———
    Column {
        x: 14; y: 18
        width: 220 - 28
        spacing: 2
        Rectangle {
            width: parent.width; height: 34; radius: 10
            color: st.t.fill
            border.width: search.activeFocus ? 1.5 : 0
            border.color: st.t.accent
            Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: I.search; size: 15; color: st.t.text2 }
            TextInput {
                id: search
                x: 32; width: parent.width - 42
                anchors.verticalCenter: parent.verticalCenter
                color: st.t.text; font.pixelSize: 13; clip: true
                onTextChanged: st.detail = null
                Keys.onEscapePressed: text = ""
                Text { visible: !search.text; text: "Szukaj"; color: st.t.text2; font.pixelSize: 13 }
            }
        }
        Item { width: 1; height: 12 }
        Repeater {
            model: st.categories
            delegate: Rectangle {
                id: navItem
                required property var modelData
                readonly property bool active: !st.query && st.page === modelData.id
                width: parent.width; height: 38; radius: 10
                color: active ? st.t.accentSoft : (navArea.containsMouse ? st.t.hover : "transparent")
                Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: I[navItem.modelData.icon]; color: navItem.active ? st.t.accentText : st.t.text }
                Text { x: 38; anchors.verticalCenter: parent.verticalCenter; text: navItem.modelData.name; color: st.t.text; font.pixelSize: 14; font.weight: navItem.active ? Font.DemiBold : Font.Normal }
                Rectangle {
                    visible: navItem.modelData.id === "updates"
                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20; radius: 10; color: st.t.accent
                    Text { anchors.centerIn: parent; text: "2"; color: "white"; font.pixelSize: 11; font.weight: Font.Bold }
                }
                MouseArea { id: navArea; anchors.fill: parent; hoverEnabled: true; onClicked: { search.text = ""; st.detail = null; st.page = navItem.modelData.id; flick.contentY = 0; } }
            }
        }
    }

    // ——— Treść ———
    Item {
        id: contentArea
        x: 220; width: st.width - 220; height: st.height
        clip: true

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.topMargin: 14
            contentHeight: pageLoader.item ? pageLoader.item.implicitHeight + 70 : 0
            boundsBehavior: Flickable.StopAtBounds
            opacity: st.detail ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Loader {
                id: pageLoader
                x: 32; y: 16
                width: flick.width - 64
                sourceComponent: st.query ? searchPage : (st.page === "discover" ? discoverPage : (st.page === "updates" ? updatesPage : categoryPage))
                onLoaded: { item.opacity = 0; pageIn.restart(); }
                NumberAnimation { id: pageIn; target: pageLoader.item; property: "opacity"; to: 1; duration: 160 }
            }
        }

        // Strona aplikacji wjeżdża z prawej
        Flickable {
            id: detailFlick
            anchors.fill: parent
            anchors.topMargin: 14
            visible: x < width
            x: st.detail ? 0 : width
            Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutQuint } }
            contentHeight: detailCol.implicitHeight + 70
            boundsBehavior: Flickable.StopAtBounds
            Loader { id: detailCol; x: 32; y: 8; width: detailFlick.width - 64; active: !!st.detail; sourceComponent: detailPage }
        }
    }

    // ——— Elementy wspólne ———
    component SectionHeader: Item {
        property string title
        property string link: ""
        signal linkClicked()
        width: parent ? parent.width : 400; height: 40
        Text { anchors.bottom: parent.bottom; anchors.bottomMargin: 6; text: parent.title; color: st.t.text; font.pixelSize: 21; font.weight: Font.Bold }
        Text {
            visible: !!parent.link
            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
            text: parent.link; color: st.t.accentText; font.pixelSize: 14
            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: parent.parent.linkClicked() }
        }
    }

    component AppRow: Item {
        id: ar
        property var a
        property int rank: 0
        property bool line: true
        width: 240; height: 72
        Text { visible: ar.rank > 0; x: 0; anchors.verticalCenter: parent.verticalCenter; text: ar.rank; color: st.t.text; font.pixelSize: 16; font.weight: Font.Bold; width: 22 }
        AppTile { id: arTile; x: ar.rank > 0 ? 24 : 0; anchors.verticalCenter: parent.verticalCenter; app: ar.a; size: 52 }
        Column {
            anchors.left: arTile.right; anchors.leftMargin: 12
            anchors.right: arGet.left; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text { width: parent.width; text: ar.a.name; color: st.t.text; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight }
            Text { width: parent.width; text: ar.a.sub; color: st.t.text2; font.pixelSize: 12; elide: Text.ElideRight }
        }
        GetButton {
            id: arGet
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            t: st.t
            progress: st.prog(ar.a.name)
            onGetClicked: st.startInstall(ar.a)
            onOpenClicked: st.openApp(ar.a)
        }
        Rectangle { visible: ar.line; anchors.bottom: parent.bottom; x: arTile.x + 64; width: parent.width - x; height: 1; color: st.t.line }
        MouseArea { anchors.fill: parent; anchors.rightMargin: arGet.width + 8; cursorShape: Qt.PointingHandCursor; onClicked: st.detail = ar.a }
    }

    component FeatureCard: Rectangle {
        id: fc
        property var a
        property string kicker
        property string headline
        property var colors: ["#555", "#222"]
        height: 230; radius: 22
        clip: true
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: fc.colors[0] }
            GradientStop { position: 1; color: fc.colors[1] }
        }
        // Dekoracja: duży, półprzezroczysty symbol aplikacji
        Icon { x: parent.width - 170; y: -20; d: I[fc.a.icon] || ""; size: 210; stroke: 1.2; color: Qt.rgba(1, 1, 1, 0.16) }
        Text { x: 22; y: 20; text: fc.kicker; color: Qt.rgba(1, 1, 1, 0.75); font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 0.8 }
        Text { x: 22; y: 40; width: parent.width - 44; text: fc.headline; color: "white"; font.pixelSize: 24; font.weight: Font.Bold; wrapMode: Text.Wrap; lineHeight: 1.05 }
        Rectangle {
            anchors.bottom: parent.bottom; width: parent.width; height: 76
            color: Qt.rgba(0, 0, 0, 0.16)
            AppTile { id: fcTile; x: 18; anchors.verticalCenter: parent.verticalCenter; app: fc.a; size: 48 }
            Column {
                anchors.left: fcTile.right; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                Text { text: fc.a.name; color: "white"; font.pixelSize: 15; font.weight: Font.DemiBold }
                Text { text: fc.a.sub; color: Qt.rgba(1, 1, 1, 0.8); font.pixelSize: 12 }
            }
            GetButton {
                anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
                t: st.t; onDark: true
                progress: st.prog(fc.a.name)
                onGetClicked: st.startInstall(fc.a)
                onOpenClicked: st.openApp(fc.a)
            }
        }
        MouseArea { anchors.fill: parent; anchors.bottomMargin: 76; cursorShape: Qt.PointingHandCursor; onClicked: st.detail = fc.a }
        scale: fcHover.hovered ? 1.012 : 1
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuint } }
        HoverHandler { id: fcHover }
    }

    // ——— Odkrywaj ———
    Component {
        id: discoverPage
        Column {
            spacing: 18
            Column {
                spacing: 2
                Text { text: Qt.locale("pl_PL").toString(new Date(), "dddd, d MMMM").toUpperCase(); color: st.t.text2; font.pixelSize: 12; font.weight: Font.DemiBold; font.letterSpacing: 0.6 }
                Text { text: "Odkrywaj"; color: st.t.text; font.pixelSize: 32; font.weight: Font.Bold }
            }

            // Duża karta polecana
            Rectangle {
                id: hero
                width: parent.width; height: 300; radius: 24
                clip: true
                readonly property var a: st.app("Spotify")
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#FF7A59" }
                    GradientStop { position: 0.5; color: "#C64BD8" }
                    GradientStop { position: 1; color: "#4B5BF0" }
                }
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Qt.rgba(1, 1, 1, 0.16); strokeWidth: 2; fillColor: "transparent"
                        PathAngleArc { centerX: hero.width * 0.78; centerY: hero.height * 0.42; radiusX: 70; radiusY: 70; startAngle: 0; sweepAngle: 360 }
                    }
                    ShapePath {
                        strokeColor: Qt.rgba(1, 1, 1, 0.12); strokeWidth: 2; fillColor: "transparent"
                        PathAngleArc { centerX: hero.width * 0.78; centerY: hero.height * 0.42; radiusX: 120; radiusY: 120; startAngle: 0; sweepAngle: 360 }
                    }
                    ShapePath {
                        strokeColor: Qt.rgba(1, 1, 1, 0.08); strokeWidth: 2; fillColor: "transparent"
                        PathAngleArc { centerX: hero.width * 0.78; centerY: hero.height * 0.42; radiusX: 175; radiusY: 175; startAngle: 0; sweepAngle: 360 }
                    }
                }
                Icon { x: hero.width * 0.78 - 34; y: hero.height * 0.42 - 34; d: I.music; size: 68; stroke: 1.6; color: "white" }
                Text { x: 26; y: 26; text: "POLECAMY"; color: Qt.rgba(1, 1, 1, 0.8); font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 0.8 }
                Text { x: 26; y: 48; width: hero.width * 0.55; text: "Muzyka, która pracuje razem z Tobą"; color: "white"; font.pixelSize: 32; font.weight: Font.Bold; wrapMode: Text.Wrap; lineHeight: 1.0 }
                Text { x: 26; y: 136; width: hero.width * 0.5; text: "Playlisty do skupienia, które same dopasowują się do pory dnia."; color: Qt.rgba(1, 1, 1, 0.88); font.pixelSize: 14; wrapMode: Text.Wrap }
                Rectangle {
                    anchors.bottom: parent.bottom; width: parent.width; height: 80
                    color: Qt.rgba(0, 0, 0, 0.16)
                    AppTile { id: heroTile; x: 22; anchors.verticalCenter: parent.verticalCenter; app: hero.a; size: 52 }
                    Column {
                        anchors.left: heroTile.right; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                        Text { text: hero.a.name; color: "white"; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Text { text: hero.a.sub; color: Qt.rgba(1, 1, 1, 0.8); font.pixelSize: 12 }
                    }
                    GetButton {
                        anchors.right: parent.right; anchors.rightMargin: 22; anchors.verticalCenter: parent.verticalCenter
                        t: st.t; onDark: true
                        progress: st.prog(hero.a.name)
                        onGetClicked: st.startInstall(hero.a)
                        onOpenClicked: st.openApp(hero.a)
                    }
                }
                MouseArea { anchors.fill: parent; anchors.bottomMargin: 80; cursorShape: Qt.PointingHandCursor; onClicked: st.detail = hero.a }
            }

            Row {
                spacing: 16
                FeatureCard {
                    width: (pageLoader.width - 16) / 2
                    a: st.app("Blender"); kicker: "APLIKACJA TYGODNIA"; headline: "Twój pierwszy model 3D w jeden wieczór"
                    colors: ["#F07A2A", "#E0457B"]
                }
                FeatureCard {
                    width: (pageLoader.width - 16) / 2
                    a: st.app("SuperTuxKart"); kicker: "GRA TYGODNIA"; headline: "Wyścigi na kanapie dla całej rodziny"
                    colors: ["#E0A419", "#2FAE66"]
                }
            }

            SectionHeader { title: "Najpopularniejsze darmowe"; link: "Pokaż wszystkie"; onLinkClicked: st.page = "work" }
            Grid {
                columns: 3
                columnSpacing: 20
                Repeater {
                    model: ["Spotify", "Firefox", "Discord", "VLC", "OnlyOffice", "Steam", "GIMP", "Thunderbird", "Bitwarden"]
                    delegate: AppRow {
                        required property string modelData
                        required property int index
                        width: (pageLoader.width - 40) / 3
                        a: st.app(modelData); rank: index + 1
                        line: index < 6
                    }
                }
            }

            SectionHeader { title: "Przesiadasz się z Windowsa?" }
            Rectangle {
                width: parent.width; height: winCol.implicitHeight + 24; radius: 18
                color: st.t.fill
                Column {
                    id: winCol
                    x: 18; y: 12
                    width: parent.width - 36
                    Repeater {
                        model: [["Photoshop", "GIMP"], ["Word i Excel", "OnlyOffice"], ["Outlook", "Thunderbird"], ["Windows Media Player", "VLC"]]
                        delegate: Item {
                            id: sw2
                            required property var modelData
                            required property int index
                            width: winCol.width; height: 62
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Używałeś " + sw2.modelData[0] + "?"; color: st.t.text2; font.pixelSize: 14; width: 230; elide: Text.ElideRight }
                            Icon { x: 236; anchors.verticalCenter: parent.verticalCenter; d: I.arrow; size: 16; color: st.t.text2 }
                            AppRow { x: 268; width: parent.width - 268; height: 62; a: st.app(sw2.modelData[1]); line: false }
                            Rectangle { visible: sw2.index < 3; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: st.t.line }
                        }
                    }
                }
            }
        }
    }

    // ——— Kategoria ———
    Component {
        id: categoryPage
        Column {
            spacing: 14
            readonly property var cat: st.categories.find(c => c.id === st.page)
            Text { text: parent.cat ? parent.cat.name : ""; color: st.t.text; font.pixelSize: 32; font.weight: Font.Bold }
            Grid {
                columns: 2
                columnSpacing: 24
                Repeater {
                    model: st.catalog.filter(a => a.cat === st.page)
                    delegate: AppRow {
                        required property var modelData
                        required property int index
                        width: (pageLoader.width - 24) / 2
                        a: modelData; rank: index + 1
                    }
                }
            }
        }
    }

    // ——— Wyszukiwanie ———
    Component {
        id: searchPage
        Column {
            spacing: 14
            readonly property var hits: st.catalog.filter(a => (a.name + " " + a.sub + " " + a.desc).toLowerCase().indexOf(st.query) >= 0)
            Text { text: "Wyniki dla „" + search.text.trim() + "”"; color: st.t.text; font.pixelSize: 26; font.weight: Font.Bold }
            Text { visible: parent.hits.length === 0; text: "Nic nie znaleziono. Spróbuj nazwy programu z Windowsa, np. „Photoshop” albo „Word”."; color: st.t.text2; font.pixelSize: 14 }
            Grid {
                columns: 2
                columnSpacing: 24
                Repeater {
                    model: parent.parent.hits
                    delegate: AppRow {
                        required property var modelData
                        width: (pageLoader.width - 24) / 2
                        a: modelData
                    }
                }
            }
        }
    }

    // ——— Aktualizacje ———
    Component {
        id: updatesPage
        Column {
            spacing: 14
            Item {
                width: parent.width; height: 44
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Aktualizacje"; color: st.t.text; font.pixelSize: 32; font.weight: Font.Bold }
                GetButton {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    t: st.t; big: true; getLabel: "AKTUALIZUJ WSZYSTKO"
                    progress: Math.min(st.prog("upd:Firefox"), st.prog("upd:VLC"))
                    onGetClicked: { st.progressMap["upd:Firefox"] = 0; st.progressMap["upd:VLC"] = 0; st.rev++; }
                }
            }
            Text { text: "Aktualizacje instalują się same w tle, kiedy aplikacja jest zamknięta."; color: st.t.text2; font.pixelSize: 14 }
            Repeater {
                model: [{ n: "Firefox", v: "Wersja 132 · poprawki bezpieczeństwa i szybsze karty" }, { n: "VLC", v: "Wersja 3.0.21 · lepsza obsługa napisów" }]
                delegate: Rectangle {
                    id: upd
                    required property var modelData
                    width: parent.width; height: 86; radius: 18
                    color: st.t.fill
                    AppTile { id: updTile; x: 16; anchors.verticalCenter: parent.verticalCenter; app: st.app(upd.modelData.n); size: 54 }
                    Column {
                        anchors.left: updTile.right; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Text { text: upd.modelData.n; color: st.t.text; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Text { text: upd.modelData.v; color: st.t.text2; font.pixelSize: 13 }
                    }
                    GetButton {
                        anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
                        t: st.t; getLabel: "AKTUALIZUJ"
                        progress: st.prog("upd:" + upd.modelData.n)
                        onGetClicked: { st.progressMap["upd:" + upd.modelData.n] = 0; st.rev++; }
                    }
                }
            }
        }
    }

    // ——— Strona aplikacji ———
    Component {
        id: detailPage
        Column {
            spacing: 22
            readonly property var a: st.detail
            Rectangle {
                width: backRow.implicitWidth + 20; height: 32; radius: 16
                color: backArea.containsMouse ? st.t.fill : "transparent"
                Row {
                    id: backRow
                    anchors.centerIn: parent
                    spacing: 4
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: I.back; size: 18; color: st.t.accentText }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Wstecz"; color: st.t.accentText; font.pixelSize: 14 }
                }
                MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; onClicked: st.detail = null }
            }
            Row {
                spacing: 22
                AppTile { app: parent.parent.a; size: 128 }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Text { text: parent.parent.parent.a.name; color: st.t.text; font.pixelSize: 30; font.weight: Font.Bold }
                    Text { text: parent.parent.parent.a.sub; color: st.t.text2; font.pixelSize: 16 }
                    Text { text: parent.parent.parent.a.dev; color: st.t.accentText; font.pixelSize: 14 }
                    Item { width: 1; height: 6 }
                    GetButton {
                        t: st.t; big: true
                        progress: st.prog(parent.parent.parent.a.name)
                        onGetClicked: st.startInstall(parent.parent.parent.a)
                        onOpenClicked: st.openApp(parent.parent.parent.a)
                    }
                }
            }
            Rectangle {
                width: parent.width; height: 1; color: st.t.line
            }
            Row {
                id: facts
                width: parent.width
                readonly property var a: parent.a
                Repeater {
                    model: [
                        { k: "OCENY", v: facts.a.rating, s: "★★★★★" },
                        { k: "WIEK", v: "3+", s: "lat" },
                        { k: "KATEGORIA", v: (st.categories.find(c => c.id === facts.a.cat) || {}).name, s: "" },
                        { k: "ROZMIAR", v: facts.a.size, s: "" }
                    ]
                    delegate: Column {
                        required property var modelData
                        required property int index
                        width: facts.width / 4
                        spacing: 4
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.k; color: st.t.text2; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 0.6 }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.v; color: st.t.text; font.pixelSize: 20; font.weight: Font.Bold }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.s; color: st.t.text2; font.pixelSize: 12 }
                    }
                }
            }
            Text { text: "Podgląd"; color: st.t.text; font.pixelSize: 21; font.weight: Font.Bold }
            Row {
                spacing: 14
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        required property int index
                        width: (detailCol.width - 28) / 3; height: width * 0.62; radius: 16
                        clip: true
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.lighter(st.detail.color, 1.6 - index * 0.15) }
                            GradientStop { position: 1; color: Qt.lighter(st.detail.color, 1.05) }
                        }
                        Rectangle {
                            x: 14; y: 14; width: parent.width - 28; height: parent.height - 28; radius: 10
                            color: Qt.rgba(1, 1, 1, 0.85)
                            Rectangle { x: 10; y: 10; width: parent.width * 0.4; height: 8; radius: 4; color: st.detail.color; opacity: 0.8 }
                            Rectangle { x: 10; y: 26; width: parent.width * 0.7; height: 6; radius: 3; color: "#CBD0DA" }
                            Rectangle { x: 10; y: 38; width: parent.width * 0.55; height: 6; radius: 3; color: "#CBD0DA" }
                            Rectangle { x: 10; y: 54; width: parent.width - 20; height: parent.height - 64; radius: 6; color: Qt.lighter(st.detail.color, 1.9) }
                        }
                    }
                }
            }
            Text { width: parent.width; text: parent.a.desc; color: st.t.text; font.pixelSize: 15; wrapMode: Text.Wrap; lineHeight: 1.3 }
        }
    }
}
