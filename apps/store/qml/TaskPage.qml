pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Store
import "Catalog.js" as Catalog
import "Facts.js" as Facts

// Przewodnik po zadaniu: krótko, co wziąć i dlaczego, zaznaczasz programy i instalujesz zestaw.
// Rachunek za dysk liczy się na żywo z prawdziwych rozmiarów, a wspólne biblioteki tylko raz.
Item {
    id: page
    property var window
    readonly property alias flick: flickable

    property var task: null
    property var chosen: ({})
    property var bills: ({})

    function setRoute(id) {
        task = Catalog.tasks.find(t => t.id === id) || null;
        if (!task) return;
        const on = {};
        task.picks.forEach(p => { if (p.on && !Store.isInstalled(p.ref)) on[p.ref] = true; });
        chosen = on;
        task.picks.forEach(p => {
            if (Store.kindOf(p.ref) !== "app") return;
            Store.summary(p.ref, (s) => {
                if (!s) return;
                const b = Object.assign({}, page.bills);
                b[p.ref] = s;
                page.bills = b;
            });
        });
    }
    function toggle(ref) {
        const c = Object.assign({}, chosen);
        if (c[ref]) delete c[ref]; else c[ref] = true;
        chosen = c;
    }
    readonly property var selection: { Store.version; return Object.keys(chosen).filter(r => chosen[r] && !Store.isInstalled(r) && Store.canInstall(r)); }

    // Pobranie i miejsce dla całego zestawu; ta sama biblioteka liczy się raz
    readonly property var bill: {
        let download = 0, disk = 0;
        const counted = {};
        selection.forEach(r => {
            const s = bills[r];
            if (!s) return;
            const runtime = s.metadata ? s.metadata.runtime : "";
            const have = Facts.runtimeInstalled(runtime, Flatpak.runtimes) || counted[runtime];
            const b = Facts.diskBill(s, have);
            counted[runtime] = true;
            download += b.download + b.extra * 0.4;   // biblioteki są pobierane skompresowane
            disk += b.total;
        });
        return { download: download, disk: disk };
    }

    Flickable {
        id: flickable
        anchors.fill: parent
        contentHeight: col.height + 110
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: col
            width: page.width
            spacing: 0

            // Nagłówek w barwie zadania
            Rectangle {
                width: parent.width
                height: headCol.implicitHeight + 64
                color: page.task ? Ui.tile(page.task.hue) : "transparent"
                Column {
                    id: headCol
                    width: Math.min(page.width - 2 * Ui.gutter, Ui.maxWidth)
                    x: (page.width - width) / 2
                    y: 30
                    spacing: 10
                    Txt { text: "Chcę"; color: page.task ? Ui.ink(page.task.hue) : Theme.text; opacity: 0.7; font.pixelSize: 16; font.weight: Font.Medium }
                    Txt {
                        width: parent.width
                        text: page.task ? page.task.title.charAt(0).toLowerCase() + page.task.title.slice(1) : ""
                        wrapMode: Text.Wrap
                        color: page.task ? Ui.ink(page.task.hue) : Theme.text
                        font.pixelSize: 40; font.weight: Font.Bold; font.letterSpacing: -1.2
                    }
                    Txt {
                        width: Math.min(parent.width, 680)
                        text: page.task ? page.task.lede : ""
                        wrapMode: Text.Wrap
                        color: page.task ? Ui.ink(page.task.hue) : Theme.text
                        font.pixelSize: 16; lineHeight: 1.25
                    }
                }
            }

            Column {
                width: Math.min(page.width - 2 * Ui.gutter, Ui.maxWidth)
                x: (page.width - width) / 2
                topPadding: 22
                spacing: 0
                Repeater {
                    model: page.task ? page.task.picks : []
                    delegate: Item {
                        id: pick
                        required property var modelData
                        required property int index
                        width: parent ? parent.width : 400
                        height: 98
                        readonly property var info: { Store.version; return Store.item(modelData.ref); }
                        readonly property bool installed: { Flatpak.installed; Flatpak.webApps; return Store.isInstalled(modelData.ref); }
                        readonly property bool picked: !!page.chosen[modelData.ref]
                        readonly property var sum: page.bills[modelData.ref] || null

                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Store.openApp(pick.modelData.ref) }

                        // Zaznaczenie do zestawu
                        Rectangle {
                            id: box
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24; radius: 5
                            visible: !pick.installed
                            color: pick.picked ? Theme.accent : "transparent"
                            border.width: pick.picked ? 0 : 1.5
                            border.color: Theme.text2
                            Icon { anchors.centerIn: parent; visible: pick.picked; d: Icons.check; size: 15; color: "white" }
                            MouseArea { anchors.fill: parent; anchors.margins: -10; cursorShape: Qt.PointingHandCursor; onClicked: page.toggle(pick.modelData.ref) }
                        }
                        AppGlyph {
                            id: glyph
                            x: 40
                            anchors.verticalCenter: parent.verticalCenter
                            ref: pick.modelData.ref
                            size: 56
                        }
                        Column {
                            anchors.left: glyph.right; anchors.leftMargin: 16
                            anchors.right: get.left; anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Row {
                                spacing: 10
                                Txt { text: pick.info.name; font.pixelSize: 17; font.weight: Font.DemiBold; font.letterSpacing: -0.2 }
                                Txt {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pick.modelData.role
                                    color: pick.modelData.role === "Najlepszy wybór" ? Theme.accentText : Theme.text2
                                    font.pixelSize: 12; font.weight: Font.DemiBold
                                }
                            }
                            Txt { width: parent.width; text: pick.modelData.why; elide: Text.ElideRight; font.pixelSize: 14 }
                            Txt {
                                width: parent.width
                                color: Theme.text2; font.pixelSize: 12; elide: Text.ElideRight
                                text: {
                                    const m = pick.info.meta || {};
                                    const bits = [];
                                    if (pick.sum) bits.push(Facts.size(pick.sum.installed_size));
                                    else if (pick.info.kind === "web") bits.push("nic na dysku");
                                    else if (pick.info.kind === "aster") bits.push("w systemie");
                                    else if (pick.info.kind === "get") bits.push("od producenta");
                                    if (m.offline === "tak") bits.push("działa bez internetu");
                                    else if (m.offline === "nie") bits.push("wymaga internetu");
                                    if (m.account === "tak") bits.push("wymaga konta");
                                    if (m.cost === "freemium") bits.push("część płatna");
                                    return bits.join(" · ");
                                }
                            }
                        }
                        GetButton {
                            id: get
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            ref: pick.modelData.ref
                        }
                        Rectangle {
                            visible: pick.index < (page.task ? page.task.picks.length - 1 : 0)
                            anchors.bottom: parent.bottom
                            anchors.left: glyph.left; anchors.right: parent.right
                            height: 1; color: Theme.line
                        }
                    }
                }
            }
        }
    }

    // ——— Pasek zestawu ———
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width; height: 76
        color: Theme.paneGlass
        Rectangle { width: parent.width; height: 1; color: Theme.line }
        Item {
            width: Math.min(page.width - 2 * Ui.gutter, Ui.maxWidth)
            x: (page.width - width) / 2
            height: parent.height
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Txt {
                    text: page.selection.length ? "Zaznaczone: " + page.selection.length : "Zaznacz programy do zestawu"
                    font.pixelSize: 15; font.weight: Font.DemiBold
                }
                Txt {
                    visible: page.bill.disk > 0
                    text: "Zajmie około " + Facts.size(page.bill.disk) + (Flatpak.diskFree > 0 ? " z " + Facts.size(Flatpak.diskFree) + " wolnych" : "")
                    color: page.bill.disk > Flatpak.diskFree ? Theme.danger : Theme.text2
                    font.pixelSize: 13
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Btn {
                    text: "Porównaj"
                    onClicked: {
                        Store.compare = page.task.picks.slice(0, 4).map(p => p.ref);
                        page.window.go("compare");
                    }
                }
                Btn {
                    text: "Zainstaluj zestaw"
                    primary: true
                    enabled: page.selection.length > 0
                    onClicked: { Store.installMany(page.selection); page.chosen = {}; }
                }
            }
        }
    }
}
