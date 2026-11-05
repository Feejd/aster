pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Store
import "Catalog.js" as Catalog
import "Facts.js" as Facts

// Twój komputer: aktualizacje, wszystkie programy z realnymi rozmiarami, porządki.
// Od tego, co zainstalowane, do tego, co można bezpiecznie zwolnić.
Item {
    id: page
    property var window
    readonly property alias flick: flickable

    Component.onCompleted: { Flatpak.refresh(); Flatpak.refreshUsage(); }
    Connections { target: Flatpak; function onInstalledChanged() { Flatpak.refreshUsage(); } }

    readonly property var apps: Flatpak.installedApps.slice().sort((a, b) => b.size - a.size)
    readonly property real appsSize: apps.reduce((s, a) => s + a.size, 0)
    readonly property var webList: Object.keys(Flatpak.webApps)
    readonly property var getList: Object.keys(Flatpak.getApps)
    readonly property int updateCount: Flatpak.updates.length + Flatpak.getUpdates.length

    // Biblioteki, których nie używa już żaden program (bez dodatków typu GL i Locale)
    readonly property var unused: {
        const used = {};
        apps.forEach(a => { used[a.runtime] = true; });
        return Object.keys(Flatpak.runtimes).filter(k => /\.(Platform|Sdk)\//.test(k) && !used[k]);
    }
    readonly property real unusedSize: unused.reduce((s, k) => s + (Flatpak.runtimes[k] || 0), 0)
    readonly property real runtimesSize: Object.keys(Flatpak.runtimes).reduce((s, k) => s + Flatpak.runtimes[k], 0)

    // Nieużywane od 3 miesięcy
    readonly property var sleeping: {
        const limit = Date.now() - 90 * 86400000;
        return apps.filter(a => { const u = Flatpak.usage[a.id]; return u && u.lastUsed > 0 && u.lastUsed < limit; });
    }
    function usageText(a) {
        const u = Flatpak.usage[a.id];
        const bits = [Facts.size(a.size)];
        if (u && u.data > 1e6) bits.push(Facts.size(u.data) + " Twoich danych");
        if (u && u.lastUsed > 0) bits.push("ostatnio " + Facts.ago(u.lastUsed / 1000));
        return bits.join(" · ");
    }

    Flickable {
        id: flickable
        anchors.fill: parent
        contentHeight: col.height + 70
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: col
            width: Math.min(page.width - 2 * Ui.gutter, Ui.maxWidth)
            x: (page.width - width) / 2
            y: 30
            spacing: 30

            Column {
                width: parent.width
                spacing: 12
                Txt { text: "Twój komputer"; font.pixelSize: 34; font.weight: Font.Bold; font.letterSpacing: -1 }
                Txt {
                    color: Theme.text2; font.pixelSize: 15
                    text: (page.apps.length ? "Programy i biblioteki zajmują " + Facts.size(page.appsSize + page.runtimesSize) + ". " : "") + "Wolne: " + Facts.size(Flatpak.diskFree) + "."
                }
            }

            // Aktualizacje
            Column {
                width: parent.width
                spacing: 8
                Row {
                    width: parent.width
                    Txt {
                        width: parent.width - updBtn.width
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Aktualizacje"
                        font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.5
                    }
                    Btn {
                        id: updBtn
                        visible: page.updateCount > 0
                        primary: true
                        text: Flatpak.progress["*"] !== undefined ? "Aktualizuję…" : "Zaktualizuj wszystko"
                        onClicked: {
                            if (Flatpak.updates.length) Flatpak.updateAll();
                            Flatpak.getUpdates.forEach(id => Flatpak.updateGet("get:" + id));
                        }
                    }
                }
                Txt {
                    visible: page.updateCount === 0
                    color: Theme.text2; font.pixelSize: 14
                    text: "Wszystko jest aktualne."
                }
                Repeater {
                    model: Flatpak.updateInfo
                    delegate: ProgramRow {
                        required property var modelData
                        ref: Store.refOf(modelData.id)
                        title: Store.nameOf(modelData.id)
                        detail: (modelData.version ? "Wersja " + modelData.version : "Nowa wersja") + (modelData.size ? " · pobierze " + Facts.size(modelData.size) : "")
                        actionText: Flatpak.progress[modelData.id] !== undefined ? "Trwa…" : "Zaktualizuj"
                        onAction: Flatpak.update(modelData.id)
                    }
                }
                Repeater {
                    model: Flatpak.getUpdates
                    delegate: ProgramRow {
                        required property string modelData
                        ref: "get:" + modelData
                        title: Store.nameOf("get:" + modelData)
                        detail: "Nowa wersja od producenta"
                        actionText: Flatpak.progress["get:" + modelData] !== undefined ? "Trwa…" : "Zaktualizuj"
                        onAction: Flatpak.updateGet("get:" + modelData)
                    }
                }
                Txt { width: parent.width; color: Theme.text2; font.pixelSize: 13; wrapMode: Text.Wrap; text: "System aktualizuje się osobno, z Ustawień. Aplikacje webowe są zawsze aktualne." }
            }

            // Porządki
            Column {
                visible: page.unused.length > 0 || page.sleeping.length > 0
                width: parent.width
                spacing: 8
                Txt { text: "Porządki"; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.5 }
                Rectangle {
                    visible: page.unused.length > 0
                    width: parent.width; height: 68; radius: 12
                    color: Theme.fill
                    Column {
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 180
                        Txt { text: "Biblioteki po usuniętych programach"; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Txt { width: parent.width; elide: Text.ElideRight; text: "Żaden program ich nie używa. Wróci około " + Facts.size(page.unusedSize) + "."; color: Theme.text2; font.pixelSize: 13 }
                    }
                    Btn { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: "Posprzątaj"; onClicked: Flatpak.pruneRuntimes() }
                }
                Txt { visible: page.sleeping.length > 0; topPadding: 6; text: "Nie używasz od ponad 3 miesięcy"; color: Theme.text2; font.pixelSize: 12; font.weight: Font.DemiBold }
                Repeater {
                    model: page.sleeping
                    delegate: ProgramRow {
                        required property var modelData
                        ref: Store.refOf(modelData.id)
                        title: Store.nameOf(modelData.id)
                        detail: page.usageText(modelData)
                        actionText: "Usuń"
                        actionDanger: true
                        onAction: Store.requestRemoval(modelData.id)
                    }
                }
            }

            // Programy
            Column {
                width: parent.width
                spacing: 8
                Txt { text: "Programy (" + (page.apps.length + page.webList.length + page.getList.length) + ")"; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.5 }
                Txt { visible: page.apps.length + page.webList.length + page.getList.length === 0; text: "Nie ma tu jeszcze żadnych programów ze Sklepu."; color: Theme.text2; font.pixelSize: 14 }
                Repeater {
                    model: page.apps
                    delegate: ProgramRow {
                        required property var modelData
                        ref: Store.refOf(modelData.id)
                        title: Store.nameOf(modelData.id)
                        detail: page.usageText(modelData)
                        actionText: "Usuń"
                        actionDanger: true
                        extraText: modelData.installation === "user" && modelData.origin === "flathub" ? "Poprzednia wersja" : ""
                        onAction: Store.requestRemoval(modelData.id)
                        onExtra: Flatpak.rollback(modelData.id)
                    }
                }
                Repeater {
                    model: page.getList
                    delegate: ProgramRow {
                        required property string modelData
                        readonly property var entry: Flatpak.getApps[modelData]
                        ref: "get:" + modelData
                        title: entry ? entry.name : modelData
                        detail: entry ? (entry.cli ? "W terminalu" : Facts.size(entry.size)) + " · od producenta" : ""
                        actionText: "Usuń"
                        actionDanger: true
                        onAction: Flatpak.removeGet("get:" + modelData)
                    }
                }
                Repeater {
                    model: page.webList
                    delegate: ProgramRow {
                        required property string modelData
                        readonly property string key: Object.keys(Catalog.web).find(k => Catalog.web[k].url === modelData) || ""
                        ref: key ? "web:" + key : ""
                        title: key ? Catalog.web[key].name : modelData
                        detail: "Aplikacja webowa · prawie nic na dysku"
                        actionText: "Usuń"
                        actionDanger: true
                        onAction: Flatpak.removeWebApp(key ? "web:" + key : modelData, Flatpak.webApps[modelData])
                    }
                }
            }
        }
    }

    component ProgramRow: Item {
        id: pr
        property string ref
        property string title
        property string detail
        property string actionText
        property bool actionDanger: false
        property string extraText: ""
        signal action()
        signal extra()
        width: col.width
        height: 66
        AppGlyph { id: pg; ref: pr.ref; size: 44; anchors.verticalCenter: parent.verticalCenter; visible: pr.ref !== "" }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; enabled: pr.ref !== ""; onClicked: Store.openApp(pr.ref) }
        Column {
            anchors.left: pg.right; anchors.leftMargin: 14
            anchors.right: actions.left; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Txt { width: parent.width; text: pr.title; elide: Text.ElideRight; font.pixelSize: 15; font.weight: Font.DemiBold }
            Txt { width: parent.width; text: pr.detail; elide: Text.ElideRight; color: Theme.text2; font.pixelSize: 13 }
        }
        Row {
            id: actions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Btn { visible: pr.extraText !== ""; text: pr.extraText; height: 32; onClicked: pr.extra() }
            Btn { text: pr.actionText; danger: pr.actionDanger; height: 32; onClicked: pr.action() }
        }
        Rectangle { anchors.bottom: parent.bottom; anchors.left: pg.left; anchors.right: parent.right; height: 1; color: Theme.line }
    }
}
