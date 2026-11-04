pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Vault

// Podgląd zmian przed zapisem: każde polecenie SQL, które pójdzie do bazy (w jednej transakcji —
// błąd jednego cofa wszystkie). Zapis dopiero po „Zapisz zmiany”.
Sheet {
    id: ch
    property var items: []
    property string error: ""
    property bool saving: false
    cardWidth: 680
    title: "Zmiany w „" + Vault.tableName + "”"
    subtitle: "Te polecenia zostaną wykonane w jednej transakcji — jeśli któreś się nie uda, baza zostanie bez zmian."
    onDismissed: if (!saving) shown = false

    function openPreview() {
        items = Vault.table.preview();
        error = "";
        saving = false;
        shown = true;
    }
    Connections {
        target: Vault
        function onCommitted(ok, message) {
            ch.saving = false;
            if (ok) ch.shown = false;
            else ch.error = message;
        }
    }

    Rectangle {
        width: parent.width
        height: Math.min(list.contentHeight + 12, 320)
        radius: 12
        color: Theme.fill
        ListView {
            id: list
            x: 6; y: 6
            width: parent.width - 12; height: parent.height - 12
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: ch.items
            delegate: Item {
                id: it
                required property var modelData
                readonly property color tint: modelData.kind === "delete" ? "#E5484D" : modelData.kind === "insert" ? "#16A34A" : Theme.accent
                width: ListView.view.width; height: sql.implicitHeight + 14
                Rectangle {
                    x: 6; y: 8
                    width: kindText.implicitWidth + 12; height: 18; radius: 9
                    color: Qt.rgba(it.tint.r, it.tint.g, it.tint.b, Theme.dark ? 0.28 : 0.14)
                    Text {
                        id: kindText
                        anchors.centerIn: parent
                        text: it.modelData.kind === "delete" ? "usuń" : it.modelData.kind === "insert" ? "dodaj" : "zmień"
                        color: Theme.dark ? Qt.lighter(it.tint, 1.4) : Qt.darker(it.tint, 1.1)
                        font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold
                    }
                }
                TextEdit {
                    id: sql
                    x: 70; y: 7; width: parent.width - 80
                    readOnly: true; selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                    text: it.modelData.text
                    color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                    font.family: "JetBrains Mono"; font.pixelSize: 12
                    SqlHighlighter { document: sql.textDocument; dark: Theme.dark }
                }
            }
        }
    }

    Text {
        visible: ch.error !== ""
        width: parent.width; wrapMode: Text.Wrap
        text: ch.error
        color: Theme.danger; font.family: Theme.font; font.pixelSize: 12
    }

    Item {
        width: parent.width; height: 34
        Pill { text: "Cofnij wszystkie"; icon: "undo"; enabled: !ch.saving; onClicked: { Vault.table.revertAll(); ch.shown = false; } }
        Row {
            anchors.right: parent.right
            spacing: 8
            Pill { text: "Anuluj"; enabled: !ch.saving; onClicked: ch.shown = false }
            Pill {
                text: ch.saving ? "Zapisuję…" : "Zapisz zmiany (" + ch.items.length + ")"
                primary: true
                enabled: !ch.saving && ch.items.length > 0
                onClicked: { ch.saving = true; ch.error = ""; Vault.commitChanges(); }
            }
        }
    }
}
