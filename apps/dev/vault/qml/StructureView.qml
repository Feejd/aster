pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Vault

// Struktura tabeli: kolumny (typ, NULL, domyślna wartość, klucz), indeksy, klucze obce (klik — tabela docelowa)
// i definicja SQL do skopiowania
Flickable {
    id: sv
    property var info: ({})
    signal openTable(string name)
    signal toast(string text)

    contentHeight: col.implicitHeight + 40
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    readonly property var columns: info.columns || []
    readonly property var indexes: info.indexes || []
    readonly property var fks: info.foreignKeys || []

    function fkFor(name) {
        for (let i = 0; i < fks.length; ++i)
            if (fks[i].columns.split(", ").indexOf(name) >= 0) return fks[i];
        return null;
    }

    Column {
        id: col
        x: 28; y: 44
        width: sv.width - 56
        spacing: 46

        Section {
            title: "Kolumny"
            count: sv.columns.length
            Repeater {
                model: [["Nazwa", 0.28], ["Typ", 0.24], ["NULL", 0.1], ["Domyślnie", 0.38]]
                delegate: Text {
                    required property var modelData
                    required property int index
                    x: [0, 0.28, 0.52, 0.62][index] * (col.width - 24) + 12
                    y: 8
                    text: modelData[0]; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium
                }
            }
            Column {
                y: 32; width: parent.width
                Repeater {
                    model: sv.columns
                    delegate: Rectangle {
                        id: cr
                        required property var modelData
                        required property int index
                        readonly property var fk: sv.fkFor(modelData.name)
                        width: parent.width; height: 34
                        color: index % 2 ? "transparent" : (Theme.dark ? Qt.rgba(1, 1, 1, 0.025) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.02))
                        readonly property real w: width - 24
                        Row {
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            width: cr.w * 0.28 - 8
                            Icon { visible: cr.modelData.pk; anchors.verticalCenter: parent.verticalCenter; d: Icons.key; size: 12; stroke: 2; color: "#E0A100" }
                            Icon { visible: !!cr.fk; anchors.verticalCenter: parent.verticalCenter; d: Icons.link; size: 12; stroke: 2; color: Theme.accentText }
                            Text {
                                width: parent.width - (cr.modelData.pk ? 18 : 0) - (cr.fk ? 18 : 0); elide: Text.ElideRight
                                text: cr.modelData.name; color: Theme.text; font.family: "JetBrains Mono"; font.pixelSize: 12; font.weight: cr.modelData.pk ? Font.DemiBold : Font.Normal
                            }
                        }
                        Text { x: 12 + cr.w * 0.28; anchors.verticalCenter: parent.verticalCenter; width: cr.w * 0.24 - 8; elide: Text.ElideRight; text: cr.modelData.type; color: Theme.accentText; font.family: "JetBrains Mono"; font.pixelSize: 12 }
                        Text { x: 12 + cr.w * 0.52; anchors.verticalCenter: parent.verticalCenter; text: cr.modelData.nullable ? "tak" : "nie"; color: cr.modelData.nullable ? Theme.text2 : Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                        Text {
                            x: 12 + cr.w * 0.62; anchors.verticalCenter: parent.verticalCenter; width: cr.w * 0.38; elide: Text.ElideRight
                            text: cr.fk ? "→ " + cr.fk.refTable + " (" + cr.fk.refColumns + ")" + (cr.modelData["default"] ? " · " + cr.modelData["default"] : "") : (cr.modelData["default"] || "—")
                            color: cr.fk ? Theme.accentText : Theme.text2; font.family: "JetBrains Mono"; font.pixelSize: 12
                        }
                    }
                }
            }
            height: 32 + sv.columns.length * 34 + 6
        }

        Section {
            title: "Indeksy"
            count: sv.indexes.length
            visible: sv.indexes.length > 0
            height: 8 + sv.indexes.length * 34 + 6
            Column {
                y: 6; width: parent.width
                Repeater {
                    model: sv.indexes
                    delegate: Item {
                        id: ir
                        required property var modelData
                        width: parent.width; height: 34
                        Text { x: 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.4; elide: Text.ElideRight; text: ir.modelData.name; color: Theme.text; font.family: "JetBrains Mono"; font.pixelSize: 12 }
                        Text { x: parent.width * 0.4 + 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width * 0.4; elide: Text.ElideRight; text: "(" + ir.modelData.columns + ")"; color: Theme.text2; font.family: "JetBrains Mono"; font.pixelSize: 12 }
                        Row {
                            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Badge { visible: ir.modelData.primary; text: "klucz główny"; tint: "#E0A100" }
                            Badge { visible: ir.modelData.unique && !ir.modelData.primary; text: "unikalny"; tint: Theme.accent }
                        }
                    }
                }
            }
        }

        Section {
            title: "Klucze obce"
            count: sv.fks.length
            visible: sv.fks.length > 0
            height: 8 + sv.fks.length * 34 + 6
            Column {
                y: 6; width: parent.width
                Repeater {
                    model: sv.fks
                    delegate: Rectangle {
                        id: fr
                        required property var modelData
                        width: parent.width; height: 34; radius: 8
                        color: frArea.containsMouse ? Theme.hover : "transparent"
                        Text {
                            x: 12; anchors.verticalCenter: parent.verticalCenter
                            text: "(" + fr.modelData.columns + ")  →  " + fr.modelData.refTable + " (" + fr.modelData.refColumns + ")"
                            color: Theme.text; font.family: "JetBrains Mono"; font.pixelSize: 12
                        }
                        Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: "Otwórz tabelę"; color: Theme.accentText; font.family: Theme.font; font.pixelSize: 12; visible: frArea.containsMouse }
                        MouseArea { id: frArea; anchors.fill: parent; hoverEnabled: true; onClicked: sv.openTable(fr.modelData.refTable) }
                    }
                }
            }
        }

        Section {
            title: "Definicja"
            visible: (sv.info.ddl || "") !== ""
            height: ddl.implicitHeight + 28
            TextEdit {
                id: ddl
                x: 14; y: 12; width: parent.width - 28 - 80
                readOnly: true; selectByMouse: true
                wrapMode: TextEdit.Wrap
                text: sv.info.ddl || ""
                color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                font.family: "JetBrains Mono"; font.pixelSize: 12
                SqlHighlighter { document: ddl.textDocument; dark: Theme.dark }
            }
            Pill {
                anchors.right: parent.right; anchors.rightMargin: 10; y: 8
                small: true; text: "Kopiuj"; icon: "copy"
                onClicked: { Vault.copy(sv.info.ddl); sv.toast("Skopiowano definicję"); }
            }
        }
    }

    component Section: Rectangle {
        id: sec
        property string title
        property int count: -1
        default property alias body: inner.data
        width: col.width
        radius: 10
        color: "transparent"
        border.width: 1; border.color: Theme.line
        // Tytuł nad ramką
        Row {
            y: -22; x: 4
            spacing: 8
            Text { text: sec.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text { visible: sec.count >= 0; text: sec.count; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        }
        Item { id: inner; anchors.fill: parent }
    }
    component Badge: Rectangle {
        id: bd
        property string text
        property color tint
        width: bdText.implicitWidth + 14; height: 20; radius: 10
        color: Qt.rgba(tint.r, tint.g, tint.b, Theme.dark ? 0.25 : 0.14)
        Text { id: bdText; anchors.centerIn: parent; text: bd.text; color: Theme.dark ? Qt.lighter(bd.tint, 1.4) : Qt.darker(bd.tint, 1.2); font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Medium }
    }
}
