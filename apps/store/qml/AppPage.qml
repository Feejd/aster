pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Store
import "Catalog.js" as Catalog
import "Facts.js" as Facts

// Strona programu: po lewej nasza opinia, zrzuty, opis i głosy użytkowników, po prawej karta programu
// z uczciwymi faktami i rachunkiem za dysk. Tak samo dla programów, aplikacji webowych i aplikacji Aster.
Item {
    id: page
    property var window
    readonly property alias flick: flickable

    property string ref
    property var sum: null
    property var stats: null
    property var rate: null
    property var reviewList: []
    property var bigShot: null

    function setRoute(r) {
        ref = r;
        sum = null; stats = null; rate = null; reviewList = [];
        if (kind !== "app") return;
        Store.item(r);
        Store.summary(r, (d) => { if (page.ref === r) page.sum = d; });
        Store.rating(r, (d) => { if (page.ref === r) page.rate = d; });
        Net.get(Store.api + "stats/" + r, 86400, (d) => { if (page.ref === r) page.stats = d; });
        Store.reviews(r, (d) => {
            if (page.ref !== r || !Array.isArray(d)) return;
            // Polskie opinie na górę, wyżej te, które inni uznali za pomocne
            const pl = (x) => String(x.locale || "").indexOf("pl") === 0 ? 1 : 0;
            page.reviewList = d.filter(x => x.description).sort((a, b) => pl(b) - pl(a) || (b.score || 0) - (a.score || 0)).slice(0, 4);
        });
    }

    readonly property string kind: Store.kindOf(ref)
    readonly property var info: { Store.version; return ref ? Store.item(ref) : null; }
    readonly property var appData: info ? info.app || null : null
    readonly property var meta: info ? info.meta : null
    readonly property bool installed: { Flatpak.installed; Flatpak.webApps; return !!ref && Store.isInstalled(ref); }
    readonly property bool removable: { Flatpak.installed; Flatpak.webApps; return !!ref && Store.state(ref) === "installed"; }
    readonly property bool hasRuntime: sum && sum.metadata ? Facts.runtimeInstalled(sum.metadata.runtime, Flatpak.runtimes) : false
    readonly property var bill: Facts.diskBill(sum, hasRuntime)
    readonly property var lines: {
        if (!info) return [];
        return Facts.cardLines({ kind: kind, summary: sum, app: appData, meta: meta, arch: Flatpak.arch, memoryGb: Flatpak.memoryGb });
    }
    readonly property var cardVerdict: Facts.verdict(lines)
    readonly property var ratingInfo: Facts.rating(rate)
    readonly property var release: appData && appData.releases && appData.releases.length ? appData.releases[0] : null
    readonly property var webAlternative: meta && meta.web ? "web:" + meta.web : ""
    // Gdzie jeszcze ten program występuje w przewodnikach
    readonly property var related: Catalog.tasks.filter(t => t.picks.some(p => p.ref === ref))

    readonly property bool wide: page.width > 960

    function shot(s) {
        const sizes = (s.sizes || []).slice().sort((a, b) => parseInt(a.width) - parseInt(b.width));
        const pick = sizes.find(z => parseInt(z.width) >= 620) || sizes[sizes.length - 1];
        return pick ? pick.src : "";
    }
    function bestShot(s) {
        const sizes = (s.sizes || []).slice().sort((a, b) => parseInt(b.width) - parseInt(a.width));
        return sizes.length ? sizes[0].src : "";
    }
    // Opis z Flathub (HTML) → to, co umie Text.StyledText
    function cleanHtml(h) {
        return (h || "").replace(/\s+/g, " ").replace(/<\/p>\s*<p>/g, "</p><br><p>").replace(/<ul>/g, "<br>").replace(/<\/ul>/g, "")
                        .replace(/<ol>/g, "<br>").replace(/<\/ol>/g, "")
                        .replace(/<li>/g, "  •  ").replace(/<\/li>/g, "<br>").replace(/<code>|<\/code>|<em>|<\/em>/g, "");
    }

    Flickable {
        id: flickable
        anchors.fill: parent
        contentHeight: Math.max(mainCol.height, page.wide ? side.height : 0) + 70
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Item {
            id: body
            width: Math.min(page.width - 2 * Ui.gutter, Ui.maxWidth)
            x: (page.width - width) / 2

            Column {
                id: mainCol
                y: 30
                width: page.wide ? parent.width - 340 - 40 : parent.width
                spacing: 26

                // Nagłówek
                Row {
                    width: parent.width
                    spacing: 20
                    AppGlyph { id: headIcon; ref: page.ref; size: 92 }
                    Column {
                        width: parent.width - 112
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Txt {
                            width: parent.width
                            text: page.info ? page.info.name : ""
                            wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                            font.pixelSize: 34; font.weight: Font.Bold; font.letterSpacing: -1
                        }
                        Txt {
                            width: parent.width
                            text: page.info ? page.info.summary : ""
                            wrapMode: Text.Wrap
                            color: Theme.text2
                            font.pixelSize: 16; lineHeight: 1.15
                        }
                        Txt {
                            visible: !page.meta
                            text: "Spoza katalogu Aster: nie sprawdzaliśmy tego programu"
                            color: Ui.tone("warn")
                            font.pixelSize: 13; font.weight: Font.Medium
                        }
                    }
                }

                // Na wąskim oknie karta idzie pod nagłówek
                Loader { active: !page.wide; width: parent.width; visible: active; sourceComponent: cardComponent }

                // Nasza opinia
                Rectangle {
                    visible: !!page.meta && !!page.meta.good
                    width: parent.width
                    height: visible ? opinion.implicitHeight + 36 : 0
                    radius: 16
                    color: Theme.fill
                    Column {
                        id: opinion
                        x: 18; y: 18
                        width: parent.width - 36
                        spacing: 12
                        Txt { text: "Nasza opinia"; font.pixelSize: 20; font.weight: Font.Bold; font.letterSpacing: -0.4 }
                        Row {
                            width: parent.width
                            spacing: 22
                            Repeater {
                                model: [{ t: "Co dobre", k: "good", c: "ok" }, { t: "Co słabe", k: "bad", c: "warn" }]
                                delegate: Column {
                                    id: side2
                                    required property var modelData
                                    width: (opinion.width - 22) / 2
                                    spacing: 5
                                    Txt { text: side2.modelData.t; color: Ui.tone(side2.modelData.c); font.pixelSize: 13; font.weight: Font.DemiBold }
                                    Repeater {
                                        model: page.meta ? (page.meta[side2.modelData.k] || []) : []
                                        delegate: Txt { required property string modelData; width: side2.width; text: modelData; wrapMode: Text.Wrap; font.pixelSize: 14; lineHeight: 1.1 }
                                    }
                                }
                            }
                        }
                    }
                }

                // Lżejsza wersja: jedna z rzeczy, których zwykły sklep nie powie
                Rectangle {
                    visible: !!page.webAlternative && !page.installed
                    width: parent.width
                    height: visible ? 74 : 0
                    radius: 14
                    border.width: 1; border.color: Theme.line
                    color: "transparent"
                    AppGlyph { id: altIcon; x: 14; anchors.verticalCenter: parent.verticalCenter; ref: page.webAlternative || ""; size: 42 }
                    Column {
                        anchors.left: altIcon.right; anchors.leftMargin: 12
                        anchors.right: altGet.left; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        Txt { text: "Jest lżejsza droga"; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Txt { width: parent.width; text: "To samo konto w osobnym oknie, bez programu na dysku."; elide: Text.ElideRight; color: Theme.text2; font.pixelSize: 13 }
                    }
                    GetButton { id: altGet; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; ref: page.webAlternative || "" }
                }

                // Zrzuty ekranu
                ListView {
                    id: shots
                    width: parent.width
                    height: 270
                    visible: !!page.appData && (page.appData.screenshots || []).length > 0
                    orientation: ListView.Horizontal
                    spacing: 12
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 0
                    model: page.appData ? (page.appData.screenshots || []).slice(0, 6) : []
                    delegate: Rectangle {
                        id: shotItem
                        required property var modelData
                        width: 480; height: 270
                        color: Theme.fill
                        border.width: 1; border.color: Theme.line
                        Image {
                            anchors.fill: parent
                            anchors.margins: 1
                            source: page.shot(shotItem.modelData)
                            sourceSize.width: 960
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.bigShot = page.bestShot(shotItem.modelData) }
                    }
                }

                // Zadania, do których polecamy
                Flow {
                    visible: page.related.length > 0
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: page.related
                        delegate: Chip {
                            required property var modelData
                            text: modelData.title
                            onClicked: page.window.go("task", modelData.id)
                        }
                    }
                }

                // Opis autora
                Column {
                    visible: !!page.appData
                    width: parent.width
                    spacing: 8
                    Txt { text: "Od autora"; font.pixelSize: 20; font.weight: Font.Bold; font.letterSpacing: -0.4 }
                    Txt {
                        width: parent.width
                        text: page.appData ? page.cleanHtml(page.appData.description) : ""
                        textFormat: Text.StyledText
                        wrapMode: Text.Wrap
                        lineHeight: 1.3
                    }
                }

                // Co nowego
                Column {
                    width: parent.width
                    visible: !!page.release && !!page.release.description
                    spacing: 6
                    Txt { text: "Co nowego"; font.pixelSize: 20; font.letterSpacing: -0.4; font.weight: Font.Bold }
                    Txt {
                        text: page.release ? "Wersja " + (page.release.version || "") + (page.release.timestamp ? " · " + Facts.ago(Number(page.release.timestamp)) : "") : ""
                        color: Theme.text2; font.pixelSize: 13
                    }
                    Txt {
                        width: parent.width
                        text: page.release ? page.cleanHtml(page.release.description || "") : ""
                        textFormat: Text.StyledText
                        wrapMode: Text.Wrap
                        lineHeight: 1.3
                        font.pixelSize: 13
                    }
                }

                // Głosy użytkowników
                Column {
                    visible: !!page.ratingInfo || page.reviewList.length > 0
                    width: parent.width
                    spacing: 12
                    Row {
                        spacing: 12
                        Txt { anchors.baseline: rateText.baseline; text: "Co mówią ludzie"; font.pixelSize: 20; font.weight: Font.Bold; font.letterSpacing: -0.4 }
                        Txt {
                            id: rateText
                            visible: !!page.ratingInfo
                            text: page.ratingInfo ? page.ratingInfo.percent + "% poleca · " + page.ratingInfo.total + " " + Facts.plural(page.ratingInfo.total, "ocena", "oceny", "ocen") : ""
                            color: Theme.text2; font.pixelSize: 14
                        }
                    }
                    Repeater {
                        model: page.reviewList
                        delegate: Column {
                            id: rev
                            required property var modelData
                            width: mainCol.width
                            spacing: 3
                            Row {
                                spacing: 8
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 8; height: 8; radius: 4
                                    color: Ui.tone(rev.modelData.rating >= 80 ? "ok" : rev.modelData.rating >= 60 ? "warn" : "bad")
                                }
                                Txt { text: rev.modelData.summary || ""; font.pixelSize: 14; font.weight: Font.DemiBold }
                            }
                            Txt { width: parent.width; text: rev.modelData.description; wrapMode: Text.Wrap; maximumLineCount: 5; elide: Text.ElideRight; font.pixelSize: 14; lineHeight: 1.15 }
                            Txt { text: (rev.modelData.user_display || "Anonim") + (rev.modelData.date_created ? " · " + Facts.ago(rev.modelData.date_created) : ""); color: Theme.text2; font.pixelSize: 12; bottomPadding: 6 }
                        }
                    }
                }
            }

            // Karta z prawej
            Loader {
                id: side
                visible: active
                active: page.wide
                x: parent.width - 340
                // Karta przewija się do końca, a potem jedzie razem z czytaniem
                y: 30 + Math.max(0, Math.min(flickable.contentY - Math.max(0, height + 60 - flickable.height), mainCol.height - height))
                width: 340
                sourceComponent: cardComponent
            }
        }
    }

    Component {
        id: cardComponent
        Rectangle {
            width: parent ? parent.width : 340
            height: cardCol.implicitHeight + 36
            radius: 18
            color: Theme.fill
            Column {
                id: cardCol
                x: 18; y: 18
                width: parent.width - 36
                spacing: 12
                Row {
                    spacing: 8
                    GetButton { ref: page.ref; big: true }
                    Btn {
                        visible: page.removable
                        height: 44
                        text: "Usuń"; danger: true
                        onClicked: page.kind === "web" ? Flatpak.removeWebApp(page.ref, Flatpak.webApps[page.meta.url]) : Store.requestRemoval(page.kind === "aster" ? page.meta.id : page.ref)
                    }
                }
                Txt {
                    width: parent.width
                    visible: !page.installed
                    wrapMode: Text.Wrap
                    color: Theme.text2; font.pixelSize: 13
                    text: page.kind === "web" ? "Bez hasła. Pojawi się w Starcie jak zwykły program."
                        : page.bill ? "Bez hasła. Zajmie " + (page.bill.extra > 0 ? "około " : "") + Facts.billText(page.bill) + "."
                        : "Bez hasła."
                }
                Txt {
                    width: parent.width
                    visible: !!page.bill && page.bill.extra > 0 && !page.installed
                    wrapMode: Text.Wrap
                    color: Theme.text2; font.pixelSize: 12
                    text: "Biblioteki są wspólne: następne programy ich nie pobiorą."
                }

                Rectangle { width: parent.width; height: 1; color: Theme.line }

                Row {
                    spacing: 8
                    Txt { text: "Karta programu"; font.pixelSize: 16; font.weight: Font.Bold; font.letterSpacing: -0.2 }
                    Txt {
                        anchors.baseline: parent.children[0].baseline
                        text: page.cardVerdict.text
                        color: Ui.tone(page.cardVerdict.tone)
                        font.pixelSize: 13; font.weight: Font.Medium
                    }
                }
                Column {
                    width: parent.width
                    Repeater {
                        model: page.lines
                        delegate: FactLine {
                            required property var modelData
                            tone: modelData.tone; title: modelData.title; text: modelData.text
                        }
                    }
                }

                Rectangle { visible: !!page.stats || !!page.appData; width: parent.width; height: 1; color: Theme.line }
                Txt {
                    width: parent.width
                    visible: !!page.stats
                    wrapMode: Text.Wrap
                    color: Theme.text2; font.pixelSize: 12
                    text: {
                        const bits = [];
                        if (page.stats && page.stats.installs_total) bits.push(Facts.count(page.stats.installs_total) + " instalacji");
                        if (page.info && page.info.dev) bits.push(page.info.dev);
                        return bits.join(" · ");
                    }
                }
                Btn {
                    text: Store.compare.indexOf(page.ref) >= 0 ? "W porównaniu" : "Dodaj do porównania"
                    icon: Store.compare.indexOf(page.ref) >= 0 ? "check" : "plus"
                    onClicked: Store.toggleCompare(page.ref)
                }
            }
        }
    }

    // Zrzut na całe okno
    Rectangle {
        visible: !!page.bigShot
        anchors.fill: parent
        z: 5
        color: Qt.rgba(0, 0, 0, 0.85)
        Image {
            anchors.fill: parent; anchors.margins: 30
            source: page.bigShot || ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        MouseArea { anchors.fill: parent; onClicked: page.bigShot = null }
    }
}
