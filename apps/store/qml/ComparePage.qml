pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Store
import "Facts.js" as Facts

// Porównanie obok siebie: te same pytania dla każdego programu, najlepsza odpowiedź wyróżniona.
// Wiersze liczą się z tych samych danych co karta programu.
Item {
    id: page
    property var window
    readonly property alias flick: flickable

    property var sums: ({})
    property var rates: ({})
    readonly property var refs: Store.compare

    function load() {
        refs.forEach(r => {
            if (Store.kindOf(r) !== "app") return;
            Store.summary(r, (s) => { const c = Object.assign({}, page.sums); c[r] = s; page.sums = c; });
            Store.rating(r, (d) => { const c = Object.assign({}, page.rates); c[r] = d; page.rates = c; });
        });
    }
    Component.onCompleted: load()
    onRefsChanged: load()

    readonly property var rows: {
        Store.version;
        return Facts.compareRows(refs.map(r => {
            const it = Store.item(r);
            const s = sums[r] || null;
            return { kind: it.kind, meta: it.meta, app: it.app || null, summary: s, rating: rates[r] || null,
                     hasRuntime: s && s.metadata ? Facts.runtimeInstalled(s.metadata.runtime, Flatpak.runtimes) : false };
        }));
    }
    readonly property real labelW: 170
    readonly property real colW: refs.length ? (body.width - labelW) / refs.length : 200

    Flickable {
        id: flickable
        anchors.fill: parent
        contentHeight: body.height + 70
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: body
            width: Math.min(page.width - 2 * Ui.gutter, Ui.maxWidth)
            x: (page.width - width) / 2
            y: 30
            spacing: 22

            Txt { text: "Porównanie"; font.pixelSize: 34; font.weight: Font.Bold; font.letterSpacing: -1 }
            Txt { visible: page.refs.length < 2; text: "Dodaj co najmniej dwa programy."; color: Theme.text2 }

            Column {
                visible: page.refs.length >= 2
                width: parent.width

                // Głowy kolumn
                Row {
                    Item { width: page.labelW; height: 1 }
                    Repeater {
                        model: page.refs
                        delegate: Column {
                            id: head
                            required property string modelData
                            width: page.colW
                            spacing: 8
                            readonly property var info: { Store.version; return Store.item(modelData); }
                            AppGlyph { ref: head.modelData; size: 56 }
                            Txt {
                                width: parent.width - 12
                                text: head.info.name
                                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                                font.pixelSize: 16; font.weight: Font.DemiBold
                            }
                            GetButton { ref: head.modelData }
                        }
                    }
                }
                Item { width: 1; height: 16 }

                Repeater {
                    model: page.rows
                    delegate: Item {
                        id: rowItem
                        required property var modelData
                        required property int index
                        width: body.width
                        height: 54
                        Rectangle { width: parent.width; height: 1; color: Theme.line }
                        Txt { width: page.labelW - 12; anchors.verticalCenter: parent.verticalCenter; text: rowItem.modelData.label; color: Theme.text2; font.pixelSize: 13; wrapMode: Text.Wrap }
                        Row {
                            x: page.labelW
                            height: parent.height
                            Repeater {
                                model: rowItem.modelData.values
                                delegate: Item {
                                    id: cell
                                    required property string modelData
                                    required property int index
                                    width: page.colW; height: rowItem.height
                                    readonly property bool best: rowItem.modelData.best === index
                                    Txt {
                                        width: parent.width - 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: cell.modelData
                                        wrapMode: Text.Wrap
                                        color: cell.best ? Ui.tone("ok") : cell.modelData === "Nie sprawdziliśmy" ? Ui.tone("unknown") : Theme.text
                                        font.pixelSize: 14; font.weight: cell.best ? Font.DemiBold : Font.Normal
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
