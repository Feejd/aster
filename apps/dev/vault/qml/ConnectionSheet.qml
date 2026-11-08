pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Aster.Ui
import Aster.Vault

// Nowe albo edytowane połączenie: rodzaj bazy, adres, użytkownik, hasło (do portfela albo pytanie
// przy każdym połączeniu), tylko do odczytu, dostęp dla asystenta. „Sprawdź” łączy się na próbę.
Sheet {
    id: cs
    property var conn: ({})
    property string kind: "postgres"
    property string testMessage: ""
    property bool testOk: false
    property bool testing: false
    cardWidth: 520
    title: conn.id ? "Połączenie „" + (conn.name || "") + "”" : "Nowe połączenie"
    subtitle: kind === "sqlite" ? "Plik bazy SQLite na tym komputerze." : "Hasło trafia do portfela systemu (KWallet) — nigdy do pliku."
    onDismissed: shown = false

    function openFor(c) {
        conn = c || {};
        kind = conn.kind || "postgres";
        nameField.text = conn.name || "";
        hostField.text = conn.host || "localhost";
        portField.text = conn.port ? String(conn.port) : "";
        dbField.text = conn.database || "";
        userField.text = conn.user || "";
        fileField.text = conn.file || "";
        passField.text = "";
        savePass.checked = conn.savePassword !== undefined ? conn.savePassword : true;
        readOnlyCheck.checked = !!conn.readOnly;
        agentCheck.checked = conn.agent !== undefined ? conn.agent : true;
        testMessage = "";
        testing = false;
        shown = true;
        nameField.input.forceActiveFocus();
    }
    function collect() {
        const c = { kind: kind, name: nameField.text.trim(), readOnly: readOnlyCheck.checked, agent: agentCheck.checked };
        if (conn.id) c.id = conn.id;
        if (kind === "sqlite") {
            c.file = Vault.toLocalPath(fileField.text.trim());
        } else {
            c.host = hostField.text.trim() || "localhost";
            c.port = Number(portField.text) || 0;
            c.database = dbField.text.trim();
            c.user = userField.text.trim();
            c.savePassword = savePass.checked;
            c.askPassword = !savePass.checked;
        }
        return c;
    }
    function save() {
        const id = Vault.saveConnection(collect(), passField.text);
        shown = false;
        Vault.open(id, passField.text);
    }

    Connections {
        target: Vault
        function onTested(ok, message) { cs.testing = false; cs.testOk = ok; cs.testMessage = message; }
    }

    // Rodzaj bazy
    Row {
        spacing: 6
        Repeater {
            model: Vault.drivers
            delegate: HoverButton {
                id: kb
                required property var modelData
                readonly property bool active: cs.kind === modelData.kind
                enabled: modelData.available
                opacity: enabled ? 1 : 0.4
                width: kbText.implicitWidth + 28; height: 32; radius: 16
                baseColor: active ? Theme.accent : Theme.fill
                color: active ? Theme.accent : (hovered ? Theme.hover : Theme.fill)
                onClicked: { cs.kind = modelData.kind; cs.testMessage = ""; }
                Text { id: kbText; anchors.centerIn: parent; text: kb.modelData.name; color: kb.active ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
            }
        }
    }
    Text {
        visible: Vault.drivers.some(d => !d.available)
        width: parent.width; wrapMode: Text.Wrap
        text: "Wyszarzone: brak sterownika w systemie (" + Vault.drivers.filter(d => !d.available).map(d => d.name).join(", ") + ")."
        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
    }

    Field { id: nameField; width: parent.width; label: "Nazwa"; placeholder: cs.kind === "sqlite" ? "np. Sklep (plik)" : "np. Sklep — produkcja" }

    // SQLite: plik
    Item {
        visible: cs.kind === "sqlite"
        width: parent.width; height: fileField.height
        Field { id: fileField; width: parent.width - 110; label: "Plik"; placeholder: "/home/…/baza.db"; mono: true }
        Pill { anchors.right: parent.right; anchors.bottom: parent.bottom; text: "Wybierz…"; onClicked: fileDialog.open() }
    }

    // Serwer
    Row {
        visible: cs.kind !== "sqlite"
        width: parent.width; spacing: 10
        Field { id: hostField; width: parent.width - 120; label: "Serwer"; placeholder: "localhost"; mono: true }
        Field { id: portField; width: 110; label: "Port"; placeholder: cs.kind === "mysql" ? "3306" : "5432"; mono: true }
    }
    Row {
        visible: cs.kind !== "sqlite"
        width: parent.width; spacing: 10
        Field { id: dbField; width: (parent.width - 10) / 2; label: "Baza"; placeholder: cs.kind === "mysql" ? "(wybór po połączeniu)" : "postgres"; mono: true }
        Field { id: userField; width: (parent.width - 10) / 2; label: "Użytkownik"; mono: true }
    }
    Field {
        id: passField
        visible: cs.kind !== "sqlite"
        width: parent.width; label: "Hasło"; password: true
        placeholder: cs.conn.id && cs.conn.savePassword ? "bez zmian (zapisane w portfelu)" : ""
        onAccepted: cs.save()
    }

    Column {
        width: parent.width; spacing: 2
        Check { id: savePass; visible: cs.kind !== "sqlite"; text: "Zapamiętaj hasło w portfelu"; detail: "Bez tego program zapyta o hasło przy każdym połączeniu" }
        Check { id: readOnlyCheck; text: "Tylko do odczytu"; detail: "Baza odrzuci każdą zmianę — bezpiecznie dla produkcji" }
        Check { id: agentCheck; text: "Dostęp dla asystenta i terminala"; detail: "aster-vault --query i asystent Aster mogą czytać (nigdy zmieniać)" }
    }

    Text {
        visible: cs.testMessage !== "" || cs.testing
        width: parent.width; wrapMode: Text.Wrap
        text: cs.testing ? "Łączę…" : (cs.testOk ? "✓ " : "✕ ") + cs.testMessage
        color: cs.testing ? Theme.text2 : cs.testOk ? (Theme.dark ? "#7EE8A8" : "#0E8F5A") : Theme.danger
        font.family: Theme.font; font.pixelSize: 12
    }

    Item {
        width: parent.width; height: 34
        Pill { text: "Sprawdź"; icon: "bolt"; onClicked: { cs.testing = true; cs.testMessage = ""; Vault.testConnection(cs.collect(), passField.text); } }
        Row {
            anchors.right: parent.right
            spacing: 8
            Pill { text: "Anuluj"; onClicked: cs.shown = false }
            Pill {
                text: "Zapisz i połącz"; primary: true
                enabled: cs.kind === "sqlite" ? fileField.text.trim() !== "" : true
                onClicked: cs.save()
            }
        }
    }

    FileDialog {
        id: fileDialog
        title: "Plik bazy SQLite"
        nameFilters: ["Bazy SQLite (*.db *.sqlite *.sqlite3 *.db3)", "Wszystkie pliki (*)"]
        onAccepted: {
            fileField.text = Vault.toLocalPath(String(selectedFile));
            if (!nameField.text) nameField.text = fileField.text.split("/").pop();
        }
    }

    component Check: Item {
        id: ck
        property bool checked: false
        property string text
        property string detail
        width: parent ? parent.width : 0; height: 40
        Rectangle {
            id: box
            y: 4
            width: 34; height: 20; radius: 10
            color: ck.checked ? Theme.accent : Theme.fill
            border.width: ck.checked ? 0 : 1; border.color: Theme.edge
            Behavior on color { ColorAnimation { duration: 120 } }
            Rectangle {
                width: 16; height: 16; radius: 8; y: 2
                x: ck.checked ? parent.width - width - 2 : 2
                color: "white"
                Behavior on x { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
            }
        }
        Column {
            x: 46; width: parent.width - 46
            Text { text: ck.text; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
            Text { width: parent.width; elide: Text.ElideRight; text: ck.detail; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
        }
        MouseArea { anchors.fill: parent; onClicked: ck.checked = !ck.checked }
    }
}
