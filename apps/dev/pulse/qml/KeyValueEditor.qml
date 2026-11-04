pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Aster.Ui
import Aster.Pulse

// Tabela klucz–wartość (parametry, nagłówki, pola formularza, zmienne środowiska). Ostatni wiersz jest
// zawsze pusty — pisanie w nim dodaje następny. files — pola mogą być plikami; secrets — zmienne tajne.
Item {
    id: kv
    property string keyPlaceholder: "Klucz"
    property string valuePlaceholder: "Wartość"
    property bool files: false
    property bool secrets: false
    property bool toggles: true          // pole wyboru „włączone”
    property var suggestions: []         // podpowiedzi nazw (np. nagłówków)
    signal edited()

    readonly property int count: {
        let n = 0;
        for (let i = 0; i < rows.count; ++i) if (rows.get(i).key !== "" || rows.get(i).value !== "") ++n;
        return n;
    }

    function load(list) {
        rows.clear();
        for (const r of (list || []))
            rows.append({ key: r.key || "", value: r.value || "", on: r.enabled !== false,
                          type: r.type || "text", secret: !!r.secret, reveal: false });
        rows.append({ key: "", value: "", on: true, type: "text", secret: false, reveal: false });
    }
    function toArray() {
        const out = [];
        for (let i = 0; i < rows.count; ++i) {
            const r = rows.get(i);
            if (r.key === "" && r.value === "") continue;
            const o = { key: r.key, value: r.value, enabled: r.on };
            if (kv.files) o.type = r.type;
            if (kv.secrets) o.secret = r.secret;
            out.push(o);
        }
        return out;
    }
    function changed(i, role, value) {
        rows.setProperty(i, role, value);
        if (i === rows.count - 1 && (rows.get(i).key !== "" || rows.get(i).value !== ""))
            rows.append({ key: "", value: "", on: true, type: "text", secret: false, reveal: false });
        kv.edited();
    }

    ListModel { id: rows }
    Component.onCompleted: if (rows.count === 0) load([])

    FileDialog {
        id: fileDialog
        property int row: -1
        title: "Wybierz plik do wysłania"
        onAccepted: kv.changed(row, "value", Pulse.localPath(selectedFile))
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.implicitHeight + 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: flick.width
            spacing: 6
            Repeater {
                model: rows
                delegate: Item {
                    id: row
                    required property int index
                    required property string key
                    required property string value
                    required property bool on
                    required property string type
                    required property bool secret
                    required property bool reveal
                    readonly property bool last: index === rows.count - 1
                    readonly property real extra: (kv.files ? 76 : 0) + (kv.secrets ? 68 : 0) + 32
                    width: col.width
                    height: 32
                    opacity: row.on || row.last ? 1 : 0.5

                    // Włączone
                    Rectangle {
                        id: check
                        visible: kv.toggles
                        anchors.verticalCenter: parent.verticalCenter
                        width: 18; height: 18; radius: 5
                        color: row.on && !row.last ? Theme.accent : "transparent"
                        border.width: row.on && !row.last ? 0 : 1.5
                        border.color: Theme.text2
                        opacity: row.last ? 0.35 : 1
                        Icon { anchors.centerIn: parent; visible: row.on && !row.last; d: Icons.check; size: 12; stroke: 2.4; color: "white" }
                        MouseArea { anchors.fill: parent; anchors.margins: -6; enabled: !row.last; onClicked: kv.changed(row.index, "on", !row.on) }
                    }
                    Field {
                        id: keyField
                        x: kv.toggles ? 28 : 0
                        width: (row.width - x - row.extra - 6) * 0.4
                        height: 32
                        text: row.key
                        placeholder: kv.keyPlaceholder
                        mono: true; fontSize: 12
                        vars: !kv.secrets
                        onEdited: kv.changed(row.index, "key", text)
                    }
                    Field {
                        id: valueField
                        x: keyField.x + keyField.width + 6
                        width: row.width - x - row.extra
                        height: 32
                        text: row.value
                        placeholder: row.type === "file" ? "Ścieżka do pliku" : kv.valuePlaceholder
                        mono: true; fontSize: 12
                        vars: !kv.secrets
                        password: row.secret && !row.reveal
                        onEdited: kv.changed(row.index, "value", text)
                    }
                    Row {
                        x: valueField.x + valueField.width + 6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        // Tekst / plik (formularz multipart)
                        HoverButton {
                            visible: kv.files
                            width: 72; height: 30; radius: 8
                            baseColor: Theme.fill
                            onClicked: {
                                if (row.type === "file") { kv.changed(row.index, "type", "text"); return; }
                                kv.changed(row.index, "type", "file");
                                fileDialog.row = row.index;
                                fileDialog.open();
                            }
                            Row {
                                anchors.centerIn: parent
                                spacing: 4
                                Icon { anchors.verticalCenter: parent.verticalCenter; d: row.type === "file" ? Icons.doc : Icons.textT; size: 13; color: Theme.text2 }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: row.type === "file" ? "Plik" : "Tekst"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                            }
                        }
                        // Tajna (do portfela) i podgląd wartości
                        ToolBtn {
                            visible: kv.secrets
                            enabled: row.secret
                            opacity: row.secret ? 1 : 0
                            width: 32; height: 30
                            icon: row.reveal ? "eyeOff" : "eye"
                            tip: row.reveal ? "Ukryj wartość" : "Pokaż wartość"
                            onClicked: rows.setProperty(row.index, "reveal", !row.reveal)
                        }
                        HoverButton {
                            visible: kv.secrets
                            width: 32; height: 30
                            baseColor: row.secret ? Theme.accentSoft : "transparent"
                            tip: row.secret ? "Tajna — wartość w portfelu systemu, nie w pliku" : "Jawna — wartość w pliku projektu; kliknij, by ukryć w portfelu"
                            onClicked: kv.changed(row.index, "secret", !row.secret)
                            Icon { anchors.centerIn: parent; d: row.secret ? Icons.lock : Icons.unlock; size: 16; color: row.secret ? Theme.accentText : Theme.text2 }
                        }
                        ToolBtn {
                            width: 28; height: 30
                            icon: "close"
                            tip: "Usuń"
                            opacity: row.last ? 0 : 0.7
                            enabled: !row.last
                            onClicked: { rows.remove(row.index); kv.edited(); }
                        }
                    }
                }
            }
        }
    }
}
