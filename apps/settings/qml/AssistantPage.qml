pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Settings

// Aster Intelligence: kto odpowiada (model lokalny albo chmura — z wyraźną informacją, gdzie są serwery),
// model, klucz API w portfelu systemu, gdzie asystent jest dostępny, historia rozmów.
Page {
    id: ap
    readonly property var st: Assistant.status
    readonly property var cur: Assistant.providers.find(p => p.id === ap.st.provider) || null
    readonly property bool cloud: !!ap.cur && ap.cur.needsKey
    property string pending: ""          // dostawca w chmurze czekający na zgodę
    readonly property var pendingInfo: Assistant.providers.find(p => p.id === ap.pending) || null
    Component.onCompleted: { Assistant.refresh(); Assistant.refreshLocal(); }

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
    readonly property var loc: Assistant.local
    readonly property var hw: ap.loc.hardware || ({})
    readonly property bool managed: !!ap.cur && ap.cur.id === "lokalny"
    function gb(bytes) { return (bytes / 1e9).toLocaleString(Qt.locale("pl_PL"), "f", bytes < 1e9 ? 1 : 1) + " GB"; }
    function cores(n) {
        const d = n % 10, t = n % 100;
        return n + (n === 1 ? " rdzeń" : d >= 2 && d <= 4 && (t < 12 || t > 14) ? " rdzenie" : " rdzeni");
    }
    function modelName(id) { const m = (ap.loc.models || []).find(x => x.id === id); return m ? m.name : ""; }
    function privacy() {
        if (!ap.cur) return "";
        if (!ap.cloud)
            return ap.cur.id === "lokalny"
                 ? "Pytania i odpowiedzi nie opuszczają komputera. Model włącza się dopiero, gdy o coś pytasz, i zwalnia pamięć po kwadransie"
                   + " bezczynności. Każda odpowiedź ma znaczek „Na tym komputerze”."
                 : "Pytania i odpowiedzi nie opuszczają komputera — odpowiada Ollama na tym komputerze. Każda odpowiedź ma znaczek „Na tym komputerze”.";
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
                    + " Bez zgody Aster Intelligence korzysta tylko z modelu na tym komputerze."
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
            title: "Aster Intelligence nie odpowiada"
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
            visible: !ap.managed
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

    // ——— Model na tym komputerze: dobór do sprzętu, pobieranie, wybór, usuwanie ———
    Section {
        visible: Assistant.available && ap.managed && (ap.loc.models || []).length > 0
        title: "Model na tym komputerze"
        footer: "Modele Gemma 3 (Google) pobierane z Hugging Face. Przerwane pobieranie ruszy od miejsca, w którym stanęło."
        SettingRow {
            title: "Ten komputer"
            subtitle: (ap.hw.ramGb || 0) + " GB pamięci · " + ap.cores(ap.hw.cores || 0) + " · wolne na dysku " + ap.gb(ap.hw.freeDisk || 0)
            icon: "cpu"; colors: ["#86EFAC", "#16A34A"]
            value: ap.loc.recommended ? "Polecamy: " + ap.modelName(ap.loc.recommended) : ""
        }
        Repeater {
            model: ap.loc.models || []
            delegate: SettingRow {
                id: mr
                required property var modelData
                readonly property bool downloading: Assistant.downloadId === mr.modelData.id
                readonly property real frac: Assistant.downloadTotal > 0 ? Assistant.downloadReceived / Assistant.downloadTotal : 0
                title: mr.modelData.name + (mr.modelData.recommended ? "  ·  polecany" : "")
                titleColor: Theme.text
                subtitle: mr.downloading ? "Pobieranie… " + ap.gb(Assistant.downloadReceived) + " z " + ap.gb(Assistant.downloadTotal)
                        : !mr.modelData.fits ? "Za mało pamięci — potrzeba " + mr.modelData.minRam + " GB"
                        : ap.gb(mr.modelData.size) + " · " + mr.modelData.description
                icon: "sparkle"
                colors: mr.modelData.active ? ["#F5B9EA", "#8D5CF6"] : ["#D4D4D8", "#71717A"]
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    // Pasek postępu pobierania
                    Rectangle {
                        visible: mr.downloading
                        anchors.verticalCenter: parent.verticalCenter
                        width: 120; height: 6; radius: 3
                        color: Theme.fill
                        Rectangle {
                            width: parent.width * mr.frac; height: parent.height; radius: 3
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "#8D9FFF" }
                                GradientStop { position: 1; color: "#E46FAE" }
                            }
                            Behavior on width { NumberAnimation { duration: 400 } }
                        }
                    }
                    TextButton { visible: mr.downloading; text: "Przerwij"; onClicked: Assistant.cancelDownload() }
                    Text {
                        visible: mr.modelData.active && !mr.downloading
                        anchors.verticalCenter: parent.verticalCenter
                        text: "W użyciu"
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 13
                    }
                    TextButton {
                        visible: mr.modelData.installed && !mr.modelData.active && !mr.downloading
                        text: "Używaj"; primary: true
                        onClicked: Assistant.useModel(mr.modelData.id)
                    }
                    TextButton {
                        visible: mr.modelData.installed && !mr.downloading
                        text: "Usuń"
                        onClicked: Assistant.deleteModel(mr.modelData.id)
                    }
                    TextButton {
                        visible: !mr.modelData.installed && !mr.downloading && mr.modelData.fits
                        enabled: Assistant.downloadId === ""
                        primary: mr.modelData.recommended
                        text: mr.modelData.partial > 0 ? "Wznów pobieranie" : "Pobierz"
                        onClicked: Assistant.downloadModel(mr.modelData.id)
                    }
                }
            }
        }
    }

    Section {
        visible: Assistant.available
        title: "Działanie"
        footer: ap.st.confirm === "zawsze"
                ? "Bez pytania tylko sprawdza (np. wolne miejsce, stan sieci). Każdą zmianę najpierw zatwierdzasz."
                : "Sam otwiera programy, tworzy foldery, kopiuje, zmienia głośność. Pyta przed instalacją i usuwaniem programów, usuwaniem plików, hasłem administratora, restartem i zmianami sieci."
        SettingRow {
            title: "Pytaj o zgodę"
            subtitle: "Zanim Aster Intelligence coś zrobi na komputerze"
            icon: "shield"; colors: ["#86EFAC", "#15803D"]
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                maxWidth: 260
                model: [{ label: "Tylko przy ważnych sprawach", value: "wazne" }, { label: "Przy każdej zmianie", value: "zawsze" }]
                value: ap.st.confirm || "wazne"
                onPicked: v => Assistant.setConfirm(v)
            }
        }
    }

    Section {
        visible: Assistant.available
        title: "Gdzie go znajdziesz"
        SettingRow {
            title: "Górny pasek"
            subtitle: "Krótkie pytanie w wyspie; dłuższa rozmowa otwiera panel z prawej. Przycisk obok Centrum sterowania otwiera rozmowy"
            icon: "aster"; colors: ["#7C9BFF", "#3456E8"]
            value: "Super + Spacja"
        }
        SettingRow {
            title: "Narzędzia do pisania"
            subtitle: "Zaznacz tekst w dowolnym programie — popraw błędy, przeredaguj, zmień ton, streść"
            icon: "pencil"; colors: ["#F5B9EA", "#C026D3"]
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
        footer: "Rozmowy są zapisywane tylko na tym komputerze (~/.local/share/aster/asystent). Aster Intelligence nie wysyła żadnej telemetrii."
        SettingRow {
            title: "Zapamiętuj rozmowy"
            subtitle: "Do powrotu w panelu asystenta"
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: ap.st.history !== false; onToggled: on => Assistant.setHistory(on) }
        }
        SettingRow {
            visible: ap.st.history !== false
            title: "Pamiętaj poprzednie rozmowy"
            subtitle: "Rozumie nawiązania („jak ostatnio”) i sam otwiera wcześniejszą rozmowę. Rozmowy z modelem na tym komputerze nie trafiają do chmury."
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: ap.st.memory !== false; onToggled: on => Assistant.setMemory(on) }
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
