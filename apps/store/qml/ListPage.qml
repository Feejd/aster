pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Store
import "Catalog.js" as Catalog
import "Facts.js" as Facts
import "Find.js" as Find

// Katalog i wyniki wyszukiwania. Najpierw to, co znamy i za co ręczymy, potem wyraźnie oddzielona reszta.
// Wyszukiwanie: lokalnie od razu, potem programy spoza katalogu, a gdy jest Aster Intelligence, także jej propozycja.
Item {
    id: page
    property var window
    readonly property alias flick: flickable

    property string query: ""
    property string cat: ""
    property var found: null
    property var others: []
    property bool loading: false
    property var ai: null               // {why, refs, badge}
    property string aiAsked: ""

    function setRoute(arg) {
        arg = arg || {};
        cat = arg.cat || "";
        query = arg.q || "";
        others = [];
        ai = null;
        found = query ? Find.local(query) : null;
        flickable.contentY = 0;
        if (query) {
            searchOutside(found.flathub);
            aiAsked = "";
            if (arg.ask) Qt.callLater(askAssistant);
        } else if (cat) {
            const c = Catalog.categories.find(x => x.id === cat);
            loading = true;
            Net.get(Store.api + "collection/category/" + c.flathub + "?page=1&per_page=40&locale=pl", 6 * 3600, (d) => {
                loading = false;
                if (page.cat === cat) page.takeHits(d, []);
            });
        }
    }
    function takeHits(d, known) {
        if (!d) return;
        const skip = known.slice();
        const hits = d.hits.filter(h => Facts.worthShowing(h, Flatpak.arch) && !Catalog.apps[h.app_id] && skip.indexOf(h.app_id) < 0).slice(0, 24);
        hits.forEach(h => Store.fromHit(h));
        others = hits.map(h => h.app_id);
    }
    function searchOutside(terms) {
        loading = true;
        const q = query;
        Net.post(Store.api + "search?locale=pl", { query: terms, filters: [] }, 6 * 3600, (d) => {
            loading = false;
            if (page.query === q) page.takeHits(d, found ? found.refs : []);
        });
    }
    function askAssistant() {
        aiAsked = query;
        Intelligence.ask(query, Find.assistantPrompt(query), Find.catalogForAssistant());
    }
    Connections {
        target: Intelligence
        function onAnswered(question, text, badge) {
            if (question !== page.query) return;
            const r = Find.parseAssistant(text);
            if (!r) { Store.toast("Asystent nie podał odpowiedzi, którą da się pokazać"); return; }
            page.ai = Object.assign(r, { badge: badge });
            if (r.search) page.searchOutside(r.search);
        }
        function onFailed(question, message) {
            if (question === page.query) Store.toast("Asystent: " + message);
        }
    }

    readonly property var catRefs: {
        if (!cat) return [];
        const a = Object.keys(Catalog.aster).filter(k => Catalog.aster[k].cat === cat).map(k => "aster:" + k);
        const p = Object.keys(Catalog.apps).filter(k => Catalog.apps[k].cat === cat);
        const w = Object.keys(Catalog.web).filter(k => Catalog.web[k].cat === cat).map(k => "web:" + k);
        return a.concat(p, w);
    }
    readonly property int cols: page.width > 1000 ? 2 : 1

    Flickable {
        id: flickable
        anchors.fill: parent
        contentHeight: col.height + 80
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: col
            width: Math.min(page.width - 2 * Ui.gutter, Ui.maxWidth)
            x: (page.width - width) / 2
            y: 30
            spacing: 26

            Column {
                width: parent.width
                spacing: 14
                Txt {
                    width: parent.width
                    text: page.query ? "Chcę " + page.query : "Katalog"
                    wrapMode: Text.Wrap
                    font.pixelSize: 34; font.weight: Font.Bold; font.letterSpacing: -1
                }
                Flow {
                    visible: !page.query
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: Catalog.categories
                        delegate: Chip {
                            required property var modelData
                            text: modelData.name
                            selected: page.cat === modelData.id
                            onClicked: page.setRoute({ cat: modelData.id })
                        }
                    }
                }
            }

            // Zadania pasujące do zapytania
            Flow {
                visible: !!page.found && page.found.tasks.length > 0
                width: parent.width
                spacing: 10
                Repeater {
                    model: page.found ? page.found.tasks : []
                    delegate: Rectangle {
                        id: mini
                        required property var modelData
                        width: miniCol.implicitWidth + 36; height: 74; radius: 14
                        color: Ui.tile(modelData.hue, miniArea.containsMouse)
                        Column {
                            id: miniCol
                            anchors.verticalCenter: parent.verticalCenter
                            x: 18
                            Txt { text: "Przewodnik"; color: Ui.ink(mini.modelData.hue); opacity: 0.75; font.pixelSize: 12; font.weight: Font.Medium }
                            Txt { text: mini.modelData.title; color: Ui.ink(mini.modelData.hue); font.pixelSize: 18; font.weight: Font.DemiBold; font.letterSpacing: -0.2 }
                        }
                        MouseArea { id: miniArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.window.go("task", mini.modelData.id) }
                    }
                }
            }

            // Zamienniki programów z Windowsa
            Column {
                visible: !!page.found && page.found.windows.length > 0
                width: parent.width
                spacing: 8
                Repeater {
                    model: page.found ? page.found.windows : []
                    delegate: Column {
                        id: sw
                        required property var modelData
                        width: col.width
                        spacing: 0
                        AppRow { width: col.width; ref: sw.modelData.pick; tag: "Zamiast: " + sw.modelData.name; note: sw.modelData.files; separator: false }
                    }
                }
            }

            // Aster Intelligence
            Rectangle {
                visible: Intelligence.available && !!page.query
                width: parent.width
                height: aiCol.implicitHeight + 28
                radius: 14
                color: Theme.accentSoft
                Column {
                    id: aiCol
                    x: 16; y: 14
                    width: parent.width - 32
                    spacing: 8
                    Row {
                        width: parent.width
                        spacing: 10
                        Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.sparkle; size: 18; color: Theme.accentText }
                        Txt {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 180
                            wrapMode: Text.Wrap
                            text: page.ai ? page.ai.why : Intelligence.busy ? "Aster Intelligence szuka…" : "Nie to? Aster Intelligence zrozumie Twój opis."
                            font.pixelSize: 14
                        }
                    }
                    Btn {
                        visible: !page.ai && !Intelligence.busy
                        text: "Zapytaj"
                        onClicked: page.askAssistant()
                    }
                    Repeater {
                        model: page.ai ? page.ai.refs : []
                        delegate: AppRow { required property string modelData; width: aiCol.width; ref: modelData; separator: false }
                    }
                    Txt { visible: !!page.ai; text: page.ai ? page.ai.badge : ""; color: Theme.text2; font.pixelSize: 11 }
                }
            }

            // Nasz katalog
            Column {
                readonly property var refs: page.query ? (page.found ? page.found.refs : []) : page.catRefs
                id: ours
                visible: refs.length > 0
                width: parent.width
                spacing: 2
                Txt { text: page.query ? "Z katalogu Aster" : "Polecamy"; font.pixelSize: 20; font.weight: Font.Bold; font.letterSpacing: -0.4; bottomPadding: 6 }
                Grid {
                    id: oursGrid
                    width: parent.width
                    columns: page.cols
                    columnSpacing: 36
                    Repeater {
                        model: ours.refs
                        delegate: AppRow {
                            required property string modelData
                            width: (oursGrid.width - (page.cols - 1) * 36) / page.cols
                            ref: modelData
                        }
                    }
                }
            }

            // Reszta świata
            Column {
                visible: page.others.length > 0
                width: parent.width
                spacing: 2
                Txt { text: "Spoza katalogu"; font.pixelSize: 20; font.weight: Font.Bold; font.letterSpacing: -0.4 }
                Txt { width: parent.width; text: "Tych programów nie sprawdzaliśmy. Odrzuciliśmy tylko porzucone i te bez wersji na Twój komputer."; wrapMode: Text.Wrap; color: Theme.text2; font.pixelSize: 14; bottomPadding: 6 }
                Grid {
                    id: othersGrid
                    width: parent.width
                    columns: page.cols
                    columnSpacing: 36
                    Repeater {
                        model: page.others
                        delegate: AppRow {
                            required property string modelData
                            width: (othersGrid.width - (page.cols - 1) * 36) / page.cols
                            ref: modelData
                        }
                    }
                }
            }

            Txt { visible: page.loading; text: "Wczytuję…"; color: Theme.text2 }
            Txt {
                visible: !page.loading && !!page.query && page.others.length === 0 && page.found && page.found.refs.length === 0 && page.found.tasks.length === 0
                width: parent.width
                text: Net.online ? "Nic nie znaleźliśmy. Spróbuj opisać to, co chcesz zrobić, innymi słowami." : "Nic w katalogu, a bez internetu nie sprawdzimy reszty."
                wrapMode: Text.Wrap
                color: Theme.text2; font.pixelSize: 15
            }
        }
    }
}
