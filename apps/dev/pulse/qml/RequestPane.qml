pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Aster.Ui
import Aster.Pulse

// Zapytanie: metoda i adres z przyciskiem „Wyślij”, a pod nimi karty Parametry, Nagłówki, Treść, Autoryzacja.
// Zmiany idą do okna sygnałem patch({…}); po otwarciu innego zapytania okno woła reload().
Item {
    id: rp
    property var req: ({})
    property bool busy: false
    property string tab: "params"
    signal patch(var changes)
    signal sendRequested()
    signal cancelRequested()
    signal methodMenu(Item anchor)
    signal importCurl(string text)

    readonly property var body: req.body || ({ mode: "none" })
    readonly property var auth: req.auth || ({ type: "none" })

    function methodColor(m) {
        return ({ GET: "#16A34A", POST: "#D97706", PUT: "#2563EB", PATCH: "#9333EA", DELETE: "#DC2626", HEAD: "#0891B2", OPTIONS: "#64748B" })[m] || "#64748B";
    }
    // Adres ⇄ parametry: w polu adresu pełny adres, w zapytaniu — adres bez części ?… i lista parametrów
    function splitUrl(full) {
        const q = full.indexOf("?");
        if (q < 0) return { base: full, params: [] };
        const params = full.slice(q + 1).split("&").filter(p => p !== "").map(p => {
            const eq = p.indexOf("=");
            return { key: eq < 0 ? p : p.slice(0, eq), value: eq < 0 ? "" : p.slice(eq + 1), enabled: true };
        });
        return { base: full.slice(0, q), params: params };
    }
    function joinUrl(base, params) {
        const on = (params || []).filter(p => p.enabled !== false && p.key !== "");
        if (on.length === 0) return base || "";
        return (base || "") + ((base || "").indexOf("?") >= 0 ? "&" : "?") + on.map(p => p.key + "=" + p.value).join("&");
    }
    function reload() {
        urlField.setText(joinUrl(req.url, req.params));
        paramsEditor.load(req.params);
        headersEditor.load(req.headers);
        formEditor.load(body.form);
        bodyEditor.setText(body.text || "");
        tokenField.setText(auth.token || "");
        userField.setText(auth.user || "");
        passField.setText(auth.password || "");
    }
    function focusUrl() { urlField.focusEnd(); }
    // Do testów: jak wpisanie adresu i zmiana wartości parametru w tabeli („nr=wartość”)
    function testTypeUrl(t) { urlField.setText(t); urlField.edited(); }
    function testParam(t) { tab = "params"; const eq = t.indexOf("="); paramsEditor.changed(Number(t.slice(0, eq)), "value", t.slice(eq + 1)); }
    function setBody(changes) { patch({ body: Object.assign({}, body, changes) }); }
    function setAuth(changes) { patch({ auth: Object.assign({}, auth, changes) }); }

    // ——— Adres ———
    Item {
        id: urlRow
        x: 20; y: 4
        width: parent.width - 40; height: 42

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: Theme.fill
            border.width: urlField.input.activeFocus ? 1.5 : 0
            border.color: Theme.accent
        }
        HoverButton {
            id: methodBtn
            x: 4; anchors.verticalCenter: parent.verticalCenter
            width: Math.max(88, methodText.implicitWidth + 42); height: 34; radius: 9
            tip: "Metoda (Ctrl+M)"
            onClicked: rp.methodMenu(methodBtn)
            Text {
                id: methodText
                x: 12; anchors.verticalCenter: parent.verticalCenter
                text: rp.req.method || "GET"
                color: rp.methodColor(rp.req.method)
                font.family: "JetBrains Mono"; font.pixelSize: 13; font.weight: Font.Bold
            }
            Icon { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; d: Icons.chevronDown; size: 13; stroke: 2; color: Theme.text2 }
        }
        Rectangle { x: methodBtn.x + methodBtn.width + 2; anchors.verticalCenter: parent.verticalCenter; width: 1; height: 20; color: Theme.line }
        Field {
            id: urlField
            x: methodBtn.x + methodBtn.width + 6
            width: sendBtn.x - x - 6
            anchors.verticalCenter: parent.verticalCenter
            height: 36
            frame: false
            mono: true
            fontSize: 13
            leftPad: 6
            placeholder: "Wpisz adres, np. {{baseUrl}}/users — albo wklej polecenie cURL"
            onEdited: {
                if (/^\s*curl\s/.test(text)) {
                    const t = text;
                    setText(rp.joinUrl(rp.req.url, rp.req.params));
                    rp.importCurl(t);
                    return;
                }
                const s = rp.splitUrl(text);
                const disabled = (rp.req.params || []).filter(p => p.enabled === false);
                const params = s.params.concat(disabled);
                rp.patch({ url: s.base, params: params });
                paramsEditor.load(params);
            }
            onAccepted: rp.sendRequested()
        }
        HoverButton {
            id: sendBtn
            anchors.right: parent.right; anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: sendRow.implicitWidth + 28; height: 34; radius: 9
            baseColor: rp.busy ? Theme.fill : Theme.accent
            color: hovered ? (rp.busy ? Theme.hover : Qt.darker(Theme.accent, 1.1)) : baseColor
            tip: rp.busy ? "Esc" : "Ctrl+Enter"
            onClicked: rp.busy ? rp.cancelRequested() : rp.sendRequested()
            Row {
                id: sendRow
                anchors.centerIn: parent
                spacing: 7
                Icon { anchors.verticalCenter: parent.verticalCenter; d: rp.busy ? Icons.stop : Icons.send; size: 15; stroke: 2; color: rp.busy ? Theme.text : "white" }
                Text { anchors.verticalCenter: parent.verticalCenter; text: rp.busy ? "Anuluj" : "Wyślij"; color: rp.busy ? Theme.text : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
            }
        }
    }
    // Adres po podstawieniu zmiennych
    Text {
        id: resolved
        readonly property string full: rp.joinUrl(rp.req.url, rp.req.params)
        x: urlRow.x + 12; y: urlRow.y + urlRow.height + 5
        width: urlRow.width - 24
        visible: full.indexOf("{{") >= 0
        height: visible ? implicitHeight : 0
        text: { Pulse.environments; return "→ " + Pulse.preview(full); }   // odświeża się też po zmianie środowiska
        elide: Text.ElideMiddle
        color: Theme.text2
        font.family: "JetBrains Mono"; font.pixelSize: 11
    }

    // ——— Karty ———
    TabBar {
        id: tabs
        x: 14; y: resolved.y + resolved.height + (resolved.visible ? 6 : 4)
        current: rp.tab
        tabs: [
            { id: "params", label: "Parametry", count: paramsEditor.count },
            { id: "headers", label: "Nagłówki", count: headersEditor.count },
            { id: "body", label: "Treść", count: rp.body.mode !== "none" ? 1 : 0 },
            { id: "auth", label: "Autoryzacja", count: rp.auth.type !== "none" ? 1 : 0 }
        ]
        onPicked: (id) => rp.tab = id
    }
    Rectangle { x: 20; y: tabs.y + tabs.height; width: parent.width - 40; height: 1; color: Theme.line }

    Item {
        id: content
        x: 20; y: tabs.y + tabs.height + 12
        width: parent.width - 40; height: parent.height - y - 8

        KeyValueEditor {
            id: paramsEditor
            anchors.fill: parent
            visible: rp.tab === "params"
            keyPlaceholder: "Parametr"
            onEdited: {
                const params = toArray();
                rp.patch({ params: params });
                urlField.setText(rp.joinUrl(rp.req.url, params));
            }
        }

        Item {
            anchors.fill: parent
            visible: rp.tab === "headers"
            KeyValueEditor {
                id: headersEditor
                width: parent.width; height: parent.height - autoHeaders.height - 6
                keyPlaceholder: "Nagłówek, np. Accept"
                onEdited: rp.patch({ headers: toArray() })
            }
            Text {
                id: autoHeaders
                anchors.bottom: parent.bottom
                width: parent.width
                wrapMode: Text.Wrap
                text: {
                    const a = [];
                    const m = rp.body.mode;
                    if (m === "json") a.push("Content-Type: application/json");
                    else if (m === "urlencoded") a.push("Content-Type: application/x-www-form-urlencoded");
                    else if (m === "form") a.push("Content-Type: multipart/form-data");
                    else if (m === "text") a.push("Content-Type: text/plain");
                    if (rp.auth.type === "bearer") a.push("Authorization: Bearer …");
                    else if (rp.auth.type === "basic") a.push("Authorization: Basic …");
                    a.push("User-Agent: AsterPulse/1.0");
                    return "Pulse dodaje sam (chyba że wpiszesz własne): " + a.join(" · ");
                }
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 11
            }
        }

        // Treść
        Item {
            anchors.fill: parent
            visible: rp.tab === "body"
            Row {
                id: modes
                spacing: 6
                Repeater {
                    model: [["none", "Brak"], ["json", "JSON"], ["text", "Tekst"], ["urlencoded", "Formularz"], ["form", "Pola i pliki"], ["file", "Plik"]]
                    delegate: Chip {
                        required property var modelData
                        text: modelData[1]
                        active: rp.body.mode === modelData[0]
                        onClicked: {
                            rp.setBody({ mode: modelData[0] });
                            if (modelData[0] === "json" && (rp.body.text || "") === "") { bodyEditor.setText("{\n  \n}"); rp.setBody({ mode: "json", text: "{\n  \n}" }); }
                        }
                    }
                }
            }
            Row {
                anchors.right: parent.right
                spacing: 6
                visible: rp.body.mode === "json"
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Pulse.jsonError(bodyEditor.text)
                    color: Theme.danger
                    font.family: Theme.font; font.pixelSize: 12
                }
                Pill {
                    small: true
                    text: "Formatuj"
                    icon: "braces"
                    enabled: Pulse.formatJson(bodyEditor.text) !== ""
                    onClicked: { const t = Pulse.formatJson(bodyEditor.text); bodyEditor.setText(t); rp.setBody({ text: t }); }
                }
            }
            CodeArea {
                id: bodyEditor
                y: modes.height + 10
                width: parent.width; height: parent.height - y
                visible: rp.body.mode === "json" || rp.body.mode === "text"
                json: rp.body.mode === "json"
                placeholder: rp.body.mode === "json" ? "{ \"name\": \"Ala\" } — możesz użyć {{zmiennych}}" : "Treść zapytania"
                onEdited: rp.setBody({ text: text })
            }
            KeyValueEditor {
                id: formEditor
                y: modes.height + 10
                width: parent.width; height: parent.height - y
                visible: rp.body.mode === "urlencoded" || rp.body.mode === "form"
                files: rp.body.mode === "form"
                keyPlaceholder: "Pole"
                onEdited: rp.setBody({ form: toArray() })
            }
            Column {
                y: modes.height + 18
                width: parent.width
                spacing: 10
                visible: rp.body.mode === "file"
                Row {
                    spacing: 10
                    Pill { text: rp.body.file ? "Zmień plik…" : "Wybierz plik…"; icon: "folder"; onClicked: bodyFile.open() }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: rp.body.file || "Nie wybrano pliku"
                        color: rp.body.file ? Theme.text : Theme.text2
                        font.family: "JetBrains Mono"; font.pixelSize: 12
                    }
                }
                Text {
                    text: "Plik idzie jako cała treść zapytania; typ (Content-Type) wynika z rozszerzenia."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
            }
            Text {
                y: modes.height + 22
                visible: rp.body.mode === "none"
                text: "To zapytanie nie wysyła treści. Wybierz JSON, formularz albo plik, np. dla POST i PUT."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
            }
            FileDialog {
                id: bodyFile
                title: "Plik do wysłania"
                onAccepted: rp.setBody({ file: Pulse.localPath(selectedFile) })
            }
        }

        // Autoryzacja
        Item {
            anchors.fill: parent
            visible: rp.tab === "auth"
            Row {
                id: authModes
                spacing: 6
                Repeater {
                    model: [["none", "Brak"], ["bearer", "Token (Bearer)"], ["basic", "Login i hasło (Basic)"]]
                    delegate: Chip {
                        required property var modelData
                        text: modelData[1]
                        active: rp.auth.type === modelData[0]
                        onClicked: rp.setAuth({ type: modelData[0] })
                    }
                }
            }
            Column {
                y: authModes.height + 16
                width: Math.min(parent.width, 520)
                spacing: 8
                visible: rp.auth.type === "bearer"
                Label { text: "Token" }
                Field {
                    id: tokenField
                    width: parent.width; mono: true
                    placeholder: "{{token}} albo wklejony token"
                    onEdited: rp.setAuth({ token: text })
                }
                Hint { text: "Wpisz {{token}}, a wartość weźmie się z wybranego środowiska — tajne zmienne są w portfelu systemu, nie w plikach projektu." }
            }
            Column {
                y: authModes.height + 16
                width: Math.min(parent.width, 520)
                spacing: 8
                visible: rp.auth.type === "basic"
                Label { text: "Login" }
                Field { id: userField; width: parent.width; mono: true; onEdited: rp.setAuth({ user: text }) }
                Label { text: "Hasło" }
                Field { id: passField; width: parent.width; mono: true; password: true; placeholder: "{{haslo}}"; onEdited: rp.setAuth({ password: text }) }
            }
            Hint {
                y: authModes.height + 22
                visible: rp.auth.type === "none"
                text: "Bez nagłówka Authorization. Możesz go też wpisać ręcznie w Nagłówkach."
            }
        }
    }

    component Chip: HoverButton {
        id: chip
        property string text
        property bool active: false
        width: chipText.implicitWidth + 24; height: 28; radius: 14
        baseColor: active ? Theme.accentSoft : Theme.fill
        border.width: active ? 1 : 0
        border.color: Theme.accentAlpha(0.5)
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.text
            color: chip.active ? Theme.accentText : Theme.text
            font.family: Theme.font; font.pixelSize: 12; font.weight: chip.active ? Font.DemiBold : Font.Normal
        }
    }
    component Label: Text { color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
    component Hint: Text { width: parent ? parent.width : 400; wrapMode: Text.Wrap; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.15 }
}
