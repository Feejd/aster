pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Settings

// Asystent: kto odpowiada (model lokalny albo chmura — z wyraźną informacją, gdzie są serwery),
// model, klucz API w portfelu systemu, gdzie asystent jest dostępny, historia rozmów.
Page {
    id: ap
    readonly property var st: Assistant.status
    readonly property var cur: Assistant.providers.find(p => p.id === ap.st.provider) || null
    readonly property bool cloud: !!ap.cur && ap.cur.needsKey
    property string pending: ""          // dostawca w chmurze czekający na zgodę
    readonly property var pendingInfo: Assistant.providers.find(p => p.id === ap.pending) || null
    Component.onCompleted: Assistant.refresh()

    function pick(id) {
        const p = Assistant.providers.find(x => x.id === id);
        if (!p || id === ap.st.provider) return;
        if (p.needsKey) { ap.pending = id; consent.open(); }
        else Assistant.setProvider(id);
    }
    function host(url) { return url ? url.replace(/^https?:\/\//, "").split("/")[0] : ""; }
    function where(p) {
        if (!p) return "";
        if (!p.needsKey) return "Na tym komputerze";
        return "Chmura · serwery: " + p.region;
    }
    function privacy() {
        if (!ap.cur) return "";
        if (!ap.cloud)
            return "Pytania i odpowiedzi nie opuszczają komputera. Potrzebny jest działający serwer modelu — llama-server albo Ollama"
                 + " (pobieranie modelu prosto z Ustawień pojawi się wkrótce). Każda odpowiedź ma znaczek „Na tym komputerze”.";
        let t = "Pytania i to, co do nich dołączysz (np. wynik polecenia w terminalu), trafiają na serwery " + ap.cur.name
              + " — " + ap.cur.region + ". Każda odpowiedź ma znaczek „Chmura: " + ap.cur.name + "”.";
        if (ap.cur.id === "deepseek")
            t += " To serwery poza ochroną RODO — nie wysyłaj tam danych osobowych ani poufnych.";
        else if (ap.cur.region.indexOf("UE") < 0)
            t += " To serwery poza Unią Europejską.";
        return t;
    }

    Sheet {
        id: consent
        title: ap.pendingInfo ? "Wysyłać pytania do " + ap.pendingInfo.name + "?" : ""
        subtitle: ap.pendingInfo
                  ? "Pytania, odpowiedzi i to, co do nich dołączysz, będą wysyłane na serwery " + ap.pendingInfo.name + " (" + ap.pendingInfo.region + ")."
                    + (ap.pendingInfo.id === "deepseek" ? " Serwery DeepSeek są w Chinach, poza ochroną RODO." : "")
                    + " Bez zgody asystent korzysta tylko z modelu na tym komputerze."
                  : ""
        acceptText: "Zgadzam się"
        onAccepted: {
            Assistant.setProvider(ap.pending);
            if (ap.pendingInfo && !ap.pendingInfo.hasKey) { keyField.text = ""; keySheet.open(); }
        }
    }
    Sheet {
        id: keySheet
        readonly property var p: ap.pendingInfo && ap.pendingInfo.needsKey ? ap.pendingInfo : ap.cur
        title: "Klucz API " + (keySheet.p ? keySheet.p.name : "")
        subtitle: keySheet.p ? "Klucz założysz na " + ap.host(keySheet.p.keyUrl) + ". Trafi do portfela systemu (KWallet), nie do plików." : ""
        acceptEnabled: keyField.text.trim().length > 8
        Field { id: keyField; placeholder: "Wklej klucz"; password: true; onSubmitted: if (keySheet.acceptEnabled) { keySheet.accepted(); keySheet.close(); } }
        onAccepted: { Assistant.setApiKey(keySheet.p.id, keyField.text.trim()); keyField.text = ""; ap.pending = ""; }
    }

    Section {
        visible: !Assistant.available
        SettingRow {
            title: "Usługa asystenta nie odpowiada"
            subtitle: "aster-assistant nie jest zainstalowany albo nie działa"
            icon: "warning"; colors: ["#FCA5A5", "#DC2626"]
            TextButton { anchors.verticalCenter: parent.verticalCenter; text: "Spróbuj ponownie"; onClicked: Assistant.refresh() }
        }
    }

    Section {
        visible: Assistant.available
        title: "Kto odpowiada"
        footer: ap.privacy()
        SettingRow {
            title: "Dostawca"
            subtitle: ap.where(ap.cur)
            icon: "sparkle"; colors: ["#C4B5FD", "#6D28D9"]
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                maxWidth: 280
                model: Assistant.providers.map(p => ({ label: p.name, value: p.id, detail: ap.where(p) }))
                value: ap.st.provider
                onPicked: v => ap.pick(v)
            }
        }
        SettingRow {
            title: "Model"
            subtitle: ap.cur && ap.cur.models.length ? "Np. " + ap.cur.models.join(", ") : "Dowolna nazwa — llama-server jej nie sprawdza"
            InlineField {
                anchors.verticalCenter: parent.verticalCenter
                text: ap.cur ? ap.cur.model : ""
                placeholder: ap.cur ? ap.cur.defaultModel : ""
                onCommitted: t => Assistant.setModel(ap.cur.id, t)
            }
        }
        SettingRow {
            visible: !!ap.cur && ap.cur.editableUrl
            title: "Adres serwera"
            subtitle: "Zgodny z OpenAI, zakończony na /v1"
            InlineField {
                anchors.verticalCenter: parent.verticalCenter
                width: 240
                text: ap.cur ? ap.cur.url : ""
                placeholder: ap.cur ? ap.cur.baseUrl : ""
                onCommitted: t => Assistant.setBaseUrl(ap.cur.id, t)
            }
        }
        SettingRow {
            visible: ap.cloud
            title: "Klucz API"
            subtitle: ap.cur && ap.cur.hasKey ? "Zapisany w portfelu systemu" : "Brak — założysz go na " + ap.host(ap.cur ? ap.cur.keyUrl : "")
            icon: "lock"; colors: ap.cur && ap.cur.hasKey ? ["#86EFAC", "#16A34A"] : ["#FCD34D", "#D97706"]
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                TextButton {
                    visible: !!ap.cur && ap.cur.hasKey
                    text: "Usuń"
                    onClicked: Assistant.setApiKey(ap.cur.id, "")
                }
                TextButton {
                    primary: !ap.cur || !ap.cur.hasKey
                    busy: Assistant.busy
                    text: ap.cur && ap.cur.hasKey ? "Zmień" : "Dodaj klucz"
                    onClicked: { ap.pending = ""; keyField.text = ""; keySheet.open(); }
                }
            }
        }
    }

    Section {
        visible: Assistant.available
        title: "Gdzie go znajdziesz"
        SettingRow {
            title: "Górny pasek"
            subtitle: "Krótkie pytanie w wyspie; dłuższa rozmowa otwiera panel z prawej"
            icon: "aster"; colors: ["#7C9BFF", "#3456E8"]
            value: "Super + Spacja"
        }
        SettingRow {
            title: "Terminal"
            subtitle: "aster \"pytanie\" · aster — rozmowa · polecenie | aster \"co tu nie tak?\""
            icon: "terminal"; colors: ["#52525B", "#18181B"]
            value: "aster, ai"
        }
    }

    Section {
        visible: Assistant.available
        title: "Historia"
        footer: "Rozmowy są zapisywane tylko na tym komputerze (~/.local/share/aster/asystent). Asystent nie wysyła żadnej telemetrii."
        SettingRow {
            title: "Zapamiętuj rozmowy"
            subtitle: "Do powrotu w panelu asystenta"
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: ap.st.history !== false; onToggled: on => Assistant.setHistory(on) }
        }
        SettingRow {
            title: "Wyczyść historię rozmów"
            subtitle: Assistant.conversations === 0 ? "Brak zapisanych rozmów"
                    : Assistant.conversations === 1 ? "1 rozmowa"
                    : Assistant.conversations + (Assistant.conversations % 10 >= 2 && Assistant.conversations % 10 <= 4
                                                && (Assistant.conversations % 100 < 12 || Assistant.conversations % 100 > 14) ? " rozmowy" : " rozmów")
            TextButton { anchors.verticalCenter: parent.verticalCenter; text: "Wyczyść"; enabled: Assistant.conversations > 0; onClicked: Assistant.clearHistory() }
        }
    }

    // Pole w wierszu: zapisuje po Enter albo po wyjściu z pola
    component InlineField: Rectangle {
        id: inf
        property alias text: input.text
        property string placeholder
        signal committed(string text)
        width: 200; height: 30; radius: 9
        color: Theme.fill
        border.width: input.activeFocus ? 1.5 : 0
        border.color: Theme.accent
        TextInput {
            id: input
            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text; selectionColor: Theme.accentSoft
            font.family: Theme.font; font.pixelSize: 13
            clip: true
            onEditingFinished: inf.committed(text.trim())
            Text { anchors.verticalCenter: parent.verticalCenter; visible: !input.text; text: inf.placeholder; color: Theme.text2; font: input.font }
        }
    }
}
