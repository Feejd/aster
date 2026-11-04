pragma ComponentBehavior: Bound
import QtQuick
import QtCore
import Aster.Ui
import Aster.Store
import "Catalog.js" as Catalog

// Przesiadka z Windowsa: zaznaczasz znane nazwy, po prawej rośnie Twój zestaw z uczciwym opisem,
// co stanie się z plikami. Gdy oryginał ma wersję webową, można go po prostu zachować.
Item {
    id: page
    property var window
    readonly property alias flick: flickable

    Settings { id: memory; category: "przesiadka"; property string picked: "[]" }

    property var picked: []
    property var keepOriginal: ({})     // nazwa → true: zostaję przy oryginale
    function setRoute(names) {
        let saved = [];
        try { saved = JSON.parse(memory.picked); } catch (e) { saved = []; }
        (names || []).forEach(n => { if (saved.indexOf(n) < 0) saved.push(n); });
        picked = saved.filter(n => Catalog.windows.some(w => w.name === n));
        memory.picked = JSON.stringify(picked);
    }
    Component.onCompleted: if (!picked.length) setRoute(undefined)
    function toggle(name) {
        const list = picked.slice();
        const i = list.indexOf(name);
        if (i >= 0) list.splice(i, 1); else list.push(name);
        picked = list;
        memory.picked = JSON.stringify(list);
    }
    readonly property var groups: {
        const out = [];
        Catalog.windows.forEach(w => { if (out.indexOf(w.group) < 0) out.push(w.group); });
        return out;
    }
    readonly property var entries: picked.map(n => Catalog.windows.find(w => w.name === n))
    function target(w) { return keepOriginal[w.name] && w.keep ? w.keep : w.pick; }
    readonly property var toInstall: {
        keepOriginal;
        Flatpak.installed; Flatpak.webApps;
        const seen = {};
        return entries.map(w => target(w)).filter(r => {
            if (seen[r] || Store.isInstalled(r)) return false;
            return seen[r] = true;
        });
    }

    Flickable {
        id: flickable
        anchors.fill: parent
        contentHeight: Math.max(left.height, right.height) + 60
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Item {
            id: body
            width: Math.min(page.width - 2 * Ui.gutter, Ui.maxWidth)
            x: (page.width - width) / 2

            Column {
                id: left
                y: 30
                width: Math.round(parent.width * 0.47)
                spacing: 20
                Column {
                    width: parent.width
                    spacing: 6
                    Txt { width: parent.width; text: "Czego używasz na Windowsie?"; wrapMode: Text.Wrap; font.pixelSize: 32; font.weight: Font.Bold; font.letterSpacing: -0.9 }
                    Txt { width: parent.width; text: "Zaznacz wszystko, co pamiętasz. Niczego nie instalujemy bez Twojego kliknięcia."; wrapMode: Text.Wrap; color: Theme.text2; font.pixelSize: 15 }
                }
                Repeater {
                    model: page.groups
                    delegate: Column {
                        id: group
                        required property string modelData
                        width: left.width
                        spacing: 8
                        Txt { text: group.modelData; color: Theme.text2; font.pixelSize: 12; font.weight: Font.DemiBold }
                        Flow {
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: Catalog.windows.filter(w => w.group === group.modelData)
                                delegate: Chip {
                                    required property var modelData
                                    text: modelData.name
                                    selected: page.picked.indexOf(modelData.name) >= 0
                                    onClicked: page.toggle(modelData.name)
                                }
                            }
                        }
                    }
                }
            }

            Column {
                id: right
                x: left.width + 40
                y: 30
                width: parent.width - left.width - 40
                spacing: 14

                Row {
                    width: parent.width
                    Txt {
                        width: parent.width - allBtn.width
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Twój zestaw"
                        font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.5
                    }
                    Btn {
                        id: allBtn
                        visible: page.toInstall.length > 0
                        primary: true
                        text: "Zainstaluj " + page.toInstall.length
                        onClicked: Store.installMany(page.toInstall)
                    }
                }
                Txt {
                    visible: page.entries.length === 0
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: "Zaznacz po lewej programy, a tutaj pojawi się to, czym je zastąpić."
                    color: Theme.text2; font.pixelSize: 14
                }
                Repeater {
                    model: page.entries
                    delegate: Rectangle {
                        id: entry
                        required property var modelData
                        width: right.width
                        height: entryCol.implicitHeight + 28
                        radius: 14
                        color: Theme.fill
                        readonly property string ref: page.target(modelData)
                        readonly property var info: { Store.version; return Store.item(ref); }
                        Column {
                            id: entryCol
                            x: 14; y: 14
                            width: parent.width - 28
                            spacing: 8
                            Txt { text: "Zamiast: " + entry.modelData.name; color: Theme.text2; font.pixelSize: 12; font.weight: Font.DemiBold }
                            Item {
                                width: parent.width; height: 44
                                AppGlyph { id: eg; ref: entry.ref; size: 44 }
                                Column {
                                    anchors.left: eg.right; anchors.leftMargin: 12
                                    anchors.right: eget.left; anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    Txt { width: parent.width; text: entry.info.name; elide: Text.ElideRight; font.pixelSize: 15; font.weight: Font.DemiBold }
                                    Txt { width: parent.width; text: entry.info.summary; elide: Text.ElideRight; color: Theme.text2; font.pixelSize: 12 }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Store.openApp(entry.ref) }
                                GetButton { id: eget; ref: entry.ref; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Txt { width: parent.width; text: entry.modelData.files; wrapMode: Text.Wrap; font.pixelSize: 13; lineHeight: 1.15 }
                            Row {
                                visible: !!entry.modelData.keep
                                spacing: 6
                                Chip {
                                    text: "Zamiennik"
                                    height: 28
                                    selected: !page.keepOriginal[entry.modelData.name]
                                    onClicked: { const k = Object.assign({}, page.keepOriginal); delete k[entry.modelData.name]; page.keepOriginal = k; }
                                }
                                Chip {
                                    text: "Zostaję przy oryginale"
                                    height: 28
                                    selected: !!page.keepOriginal[entry.modelData.name]
                                    onClicked: { const k = Object.assign({}, page.keepOriginal); k[entry.modelData.name] = true; page.keepOriginal = k; }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
