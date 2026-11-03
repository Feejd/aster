pragma ComponentBehavior: Bound
import QtQuick
import QtCore
import Aster.Ui
import Aster.Grafika

// Wybór czcionki: zainstalowane w systemie i ponad tysiąc darmowych z Google Fonts (z polskimi znakami).
// Każda nazwa napisana swoją czcionką; czcionka z internetu pobiera się po kliknięciu i od razu działa.
Popover {
    id: fp
    property var callback: null
    property string value
    property string source: "local"            // local | web
    property string category: ""
    property string installing: ""
    property int previews: 0                    // rośnie, gdy dojdzie podgląd — odświeża nazwy
    cardWidth: 340
    cardHeight: 540

    readonly property var categories: [
        { id: "", label: "Wszystkie" }, { id: "sans-serif", label: "Bez szeryfów" }, { id: "serif", label: "Szeryfowe" },
        { id: "display", label: "Ozdobne" }, { id: "handwriting", label: "Odręczne" }, { id: "monospace", label: "Maszynowe" }
    ]
    readonly property string query: search.text.trim().toLowerCase()
    // Ulubione czcionki — w ustawieniach programu, na górze listy zainstalowanych
    Settings { id: saved; category: "Grafika"; property string favoriteFonts: "[]" }
    property var favorites: { try { return JSON.parse(saved.favoriteFonts); } catch (e) { return []; } }
    function toggleFavorite(f) {
        saved.favoriteFonts = JSON.stringify(favorites.indexOf(f) >= 0 ? favorites.filter(x => x !== f) : favorites.concat([f]));
    }
    readonly property var localList: {
        const all = query === "" ? Library.fonts : Library.fonts.filter(f => f.toLowerCase().indexOf(query) >= 0);
        const fav = favorites.filter(f => all.indexOf(f) >= 0);
        return fav.concat(all.filter(f => fav.indexOf(f) < 0));
    }
    readonly property var webList: Online.fontCatalog.filter(f => (category === "" || f.category === category)
                                                               && (query === "" || f.family.toLowerCase().indexOf(query) >= 0))

    function open(item, family, fn) {
        callback = fn;
        value = family;
        installing = "";
        search.text = "";
        openAt(item, "left");
        search.focusInput();
        if (source === "web") Online.loadFontCatalog();
        const j = localList.indexOf(family);
        if (source === "local" && j >= 0) localView.positionViewAtIndex(j, ListView.Center);
    }
    function choose(family) {
        if (Library.fonts.indexOf(family) >= 0) {
            if (callback) callback(family);
            close();
            return;
        }
        installing = family;
        Online.installFont(family);
    }
    onSourceChanged: if (source === "web") Online.loadFontCatalog()

    Connections {
        target: Online
        function onFontPreviewReady() { fp.previews += 1; }
        function onFontInstalled(family) {
            Library.reloadFonts();
            if (family !== fp.installing) return;
            fp.installing = "";
            if (fp.shown && fp.callback) fp.callback(family);
            fp.close();
        }
        function onFontFailed(family) {
            if (family === fp.installing) fp.installing = "";
            fp.failed = family;
        }
    }
    property string failed: ""

    Column {
        width: parent.width
        spacing: 10
        SearchField {
            id: search
            delay: 150
            placeholder: "Szukaj czcionki"
            Keys.onEscapePressed: fp.close()
        }
        Row {
            spacing: 6
            Chip { text: "Na komputerze"; height: 30; on: fp.source === "local"; onClicked: fp.source = "local" }
            Chip { text: "Więcej z internetu"; height: 30; on: fp.source === "web"; onClicked: fp.source = "web" }
        }
        Flow {
            visible: fp.source === "web"
            width: parent.width
            spacing: 4
            Repeater {
                model: fp.categories
                delegate: Chip {
                    required property var modelData
                    height: 26
                    text: modelData.label
                    on: fp.category === modelData.id
                    onClicked: fp.category = modelData.id
                }
            }
        }
    }

    // Zainstalowane
    ListView {
        id: localView
        visible: fp.source === "local"
        y: 92
        width: parent.width; height: fp.cardHeight - 32 - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: fp.localList
        delegate: HoverButton {
            id: row
            required property string modelData
            width: localView.width; height: 40; radius: 8
            baseColor: modelData === fp.value ? Theme.accentSoft : "transparent"
            color: modelData === fp.value ? baseColor : hovered ? Theme.hover : baseColor
            onClicked: fp.choose(row.modelData)
            Text {
                x: 10; width: parent.width - 50
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: row.modelData
                color: Theme.text
                font.family: row.modelData; font.pixelSize: 18
            }
            HoverButton {
                readonly property bool fav: fp.favorites.indexOf(row.modelData) >= 0
                anchors.right: parent.right; anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30; radius: 15
                visible: fav || row.hovered || hovered
                onClicked: fp.toggleFavorite(row.modelData)
                Icon { anchors.centerIn: parent; d: Icons.star; size: 14; stroke: 2; color: parent.fav ? "#FFB400" : Theme.text2 }
            }
        }
    }

    // Z internetu
    Text {
        visible: fp.source === "web" && fp.webList.length === 0
        y: 160; width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: Online.catalogFailed ? "Nie udało się pobrać listy czcionek. Sprawdź połączenie z internetem."
            : Online.fontCatalog.length === 0 ? "Wczytuję listę czcionek…" : "Nie ma takiej czcionki."
        color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
    }
    ListView {
        id: webView
        visible: fp.source === "web"
        y: 160
        width: parent.width; height: fp.cardHeight - 32 - y - 34
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: 200
        model: fp.webList
        delegate: HoverButton {
            id: wrow
            required property var modelData
            readonly property string family: modelData.family
            readonly property bool installed: Library.fonts.indexOf(family) >= 0
            readonly property bool ready: fp.previews >= 0 && (installed || Online.hasPreview(family))
            width: webView.width; height: 46; radius: 8
            baseColor: family === fp.value ? Theme.accentSoft : "transparent"
            color: family === fp.value ? baseColor : hovered ? Theme.hover : baseColor
            enabled: fp.installing === "" || fp.installing === family
            onClicked: fp.choose(family)
            Component.onCompleted: Online.previewFont(family)
            Text {
                x: 10; width: parent.width - 60
                y: 5
                elide: Text.ElideRight
                text: wrow.family
                color: Theme.text
                font.family: wrow.ready ? wrow.family : Theme.font
                font.pixelSize: 19
            }
            Text {
                x: 10; y: 29
                text: fp.installing === wrow.family ? "Pobieranie…" : fp.failed === wrow.family ? "Nie udało się pobrać — spróbuj jeszcze raz"
                    : (fp.categories.find(c => c.id === wrow.modelData.category) || { label: "" }).label
                      + (wrow.modelData.rank < 1000 ? " · polecana" : "")
                color: fp.failed === wrow.family ? "#E5484D" : Theme.text2
                font.family: Theme.font; font.pixelSize: 11
            }
            Icon {
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                d: wrow.installed ? Icons.check : Icons.download
                size: 15; stroke: 2
                color: wrow.installed ? Theme.accentText : Theme.text2
                opacity: wrow.installed || wrow.hovered ? 1 : 0.5
            }
        }
    }
    Text {
        visible: fp.source === "web" && fp.webList.length > 0
        y: webView.y + webView.height + 6
        width: parent.width
        text: "Google Fonts — darmowe, także do użytku komercyjnego. Pobrane zapisują się w projekcie."
        wrapMode: Text.WordWrap
        color: Theme.text2; font.family: Theme.font; font.pixelSize: 10
    }
}
