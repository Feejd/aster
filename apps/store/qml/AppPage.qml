pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Aster.Ui
import Aster.Store

// Strona aplikacji (wsuwa się z prawej): nagłówek z ikoną i przyciskiem, liczby, zrzuty ekranu,
// opis i „Co nowego”. Dane prosto z Flathub.
Rectangle {
    id: page
    property string appId
    property var app: null              // appstream
    property var sum: null              // rozmiar
    property var stats: null            // instalacje
    signal back()
    signal message(string text)

    color: Theme.dark ? "#1E1E22" : "#FFFFFF"

    function load(id) {
        appId = id;
        app = null; sum = null; stats = null;
        flick.contentY = 0;
        const base = "https://flathub.org/api/v2/";
        fetch(base + "appstream/" + id + "?locale=pl", (d) => { if (page.appId === id) page.app = d; });
        fetch(base + "summary/" + id, (d) => { if (page.appId === id) page.sum = d; });
        fetch(base + "stats/" + id, (d) => { if (page.appId === id) page.stats = d; });
    }
    function fetch(url, cb) {
        const x = new XMLHttpRequest();
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            try { cb(x.status === 200 ? JSON.parse(x.responseText) : null); } catch (e) { cb(null); }
        };
        x.open("GET", url);
        x.send();
    }
    // Zrzut w rozsądnym rozmiarze (ok. 750 px szerokości)
    function shot(s) {
        const sizes = (s.sizes || []).slice().sort((a, b) => parseInt(a.width) - parseInt(b.width));
        const pick = sizes.find(z => parseInt(z.width) >= 700) || sizes[sizes.length - 1];
        return pick ? pick.src : "";
    }
    // Opis z Flathub (HTML) → to, co umie Text.StyledText
    function cleanHtml(h) {
        return (h || "").replace(/\s+/g, " ").replace(/<\/p>\s*<p>/g, "</p><br><p>").replace(/<ul>/g, "<br>").replace(/<\/ul>/g, "")
                        .replace(/<li>/g, "  •  ").replace(/<\/li>/g, "<br>").replace(/<code>|<\/code>/g, "");
    }
    readonly property bool installed: Flatpak.installed.indexOf(appId) >= 0
    readonly property var release: app && app.releases && app.releases.length ? app.releases[0] : null

    MouseArea { anchors.fill: parent }    // nic nie przechodzi do strony pod spodem

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.height + 60
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: col
            x: 36; y: 18
            width: page.width - 72
            spacing: 22

            // Wróć
            Rectangle {
                width: backRow.implicitWidth + 20; height: 32; radius: 9
                color: backArea.containsMouse ? Theme.hover : "transparent"
                Row {
                    id: backRow
                    anchors.centerIn: parent
                    spacing: 4
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.back; size: 16; color: Theme.accentText }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Wróć"; color: Theme.accentText; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                }
                MouseArea { id: backArea; anchors.fill: parent; hoverEnabled: true; onClicked: page.back() }
            }

            // Nagłówek
            Row {
                spacing: 24
                Image {
                    width: 128; height: 128
                    source: page.app ? page.app.icon : ""
                    sourceSize: Qt.size(256, 256)
                    smooth: true; mipmap: true
                    Rectangle { anchors.fill: parent; radius: 28; color: Theme.fill; visible: parent.status !== Image.Ready }
                }
                Column {
                    width: col.width - 152
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Text {
                        width: parent.width
                        text: page.app ? page.app.name : " "
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 30; font.weight: Font.Bold
                        font.letterSpacing: -0.4
                    }
                    Text {
                        width: parent.width
                        text: page.app ? (page.app.summary || "") : ""
                        elide: Text.ElideRight
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 15
                    }
                    Text {
                        text: page.app ? (page.app.developer_name || "") : ""
                        color: Theme.accentText
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                    }
                    Item { width: 1; height: 6 }
                    Row {
                        spacing: 10
                        GetButton { appId: page.appId; big: true }
                        HoverButton {
                            visible: page.installed
                            width: rmText.implicitWidth + 28; height: 36; radius: 18
                            baseColor: Theme.fill
                            onClicked: Flatpak.uninstall(page.appId)
                            Text { id: rmText; anchors.centerIn: parent; text: "Usuń"; color: Theme.danger; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                        }
                    }
                }
            }

            // Liczby
            Rectangle {
                width: col.width; height: 76; radius: 16
                color: Theme.fill
                Row {
                    anchors.fill: parent
                    Repeater {
                        model: [
                            { label: "POBRANIA", value: page.stats ? Curated.count(page.stats.installs_total) : "—" },
                            { label: "ROZMIAR", value: page.sum ? Curated.size(page.sum.download_size) : "—" },
                            { label: "LICENCJA", value: page.app ? (page.app.is_free_license ? "Wolna" : "Własnościowa") : "—" },
                            { label: "WERSJA", value: page.release ? (page.release.version || "—") : "—" }
                        ]
                        delegate: Item {
                            id: stat
                            required property var modelData
                            required property int index
                            width: col.width / 4; height: 76
                            Rectangle { visible: stat.index > 0; width: 1; height: 36; anchors.verticalCenter: parent.verticalCenter; color: Theme.line }
                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: stat.modelData.label; color: Theme.text2; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.6 }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: stat.modelData.value; color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold; elide: Text.ElideRight; width: Math.min(implicitWidth, col.width / 4 - 20) }
                            }
                        }
                    }
                }
            }

            // Zrzuty ekranu
            ListView {
                width: col.width
                height: 340
                visible: !!page.app && (page.app.screenshots || []).length > 0
                orientation: ListView.Horizontal
                spacing: 16
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: page.app ? (page.app.screenshots || []) : []
                delegate: Item {
                    id: shotItem
                    required property var modelData
                    width: Math.round(340 * 16 / 9); height: 340
                    Rectangle { anchors.fill: parent; radius: 16; color: Theme.fill }
                    Image {
                        id: shotImg
                        anchors.fill: parent
                        source: page.shot(shotItem.modelData)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        visible: false
                    }
                    Rectangle { id: shotMask; anchors.fill: parent; radius: 16; visible: false; layer.enabled: true }
                    MultiEffect {
                        anchors.fill: parent
                        source: shotImg
                        maskEnabled: true
                        maskSource: shotMask
                        visible: GraphicsInfo.api !== GraphicsInfo.Software
                    }
                    Image {
                        anchors.fill: parent
                        visible: GraphicsInfo.api === GraphicsInfo.Software
                        source: shotImg.source
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                }
            }

            // Opis
            Text {
                width: col.width
                visible: !!page.app
                text: page.app ? page.cleanHtml(page.app.description) : ""
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                color: Theme.text
                lineHeight: 1.35
                font.family: Theme.font; font.pixelSize: 14
            }

            // Co nowego
            Column {
                width: col.width
                visible: !!page.release
                spacing: 8
                Text { text: "Co nowego"; color: Theme.text; font.family: Theme.font; font.pixelSize: 20; font.weight: Font.Bold }
                Text {
                    text: page.release ? "Wersja " + (page.release.version || "") + (page.release.timestamp ? " · " + new Date(page.release.timestamp * 1000).toLocaleDateString(Qt.locale("pl_PL"), "d MMMM yyyy") : "") : ""
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                }
                Text {
                    width: parent.width
                    text: page.release ? page.cleanHtml(page.release.description || "") : ""
                    visible: text !== ""
                    textFormat: Text.StyledText
                    wrapMode: Text.Wrap
                    color: Theme.text
                    lineHeight: 1.3
                    font.family: Theme.font; font.pixelSize: 13
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !page.app
        text: "Wczytuję…"
        color: Theme.text2
        font.family: Theme.font; font.pixelSize: 14
    }
}
