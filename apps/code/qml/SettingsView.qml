pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Ustawienia Aster Code (Ctrl+,) nad edytorem: pole szukania i sekcje Edytor, Pliki, Git, Serwery języków.
// Każda zmiana działa od razu i zapisuje się sama (prefs to Settings z Main.qml); Esc albo × zamyka.
Rectangle {
    id: sv
    property bool shown: false
    property var prefs
    property var servers: []
    signal closed()

    visible: shown
    color: Theme.dark ? "#090A0D" : "#FFFFFF"
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: (w) => w.accepted = false }

    function open() {
        shown = true;
        servers = Lsp.servers();
        search.text = "";
        Qt.callLater(() => search.forceActiveFocus());
        flick.contentY = 0;
    }
    function close() { shown = false; closed(); }
    function searchFor(t) { search.text = t; }
    Connections {
        target: Lsp
        function onServersChanged() { if (sv.shown) sv.servers = Lsp.servers(); }
    }

    // Czcionki o stałej szerokości, które są w systemie (bieżąca zawsze na liście)
    readonly property var fonts: {
        const have = Qt.fontFamilies();
        const want = ["JetBrains Mono", "Fira Code", "Source Code Pro", "Cascadia Code", "Hack", "Noto Sans Mono", "DejaVu Sans Mono", "Liberation Mono"];
        const out = want.filter(f => have.indexOf(f) >= 0);
        if (prefs && out.indexOf(prefs.fontFamily) < 0) out.unshift(prefs.fontFamily);
        return out;
    }

    // Opis wszystkich ustawień: sekcja, klucz w prefs, rodzaj kontrolki
    readonly property var items: [
        { section: "Edytor", key: "fontSize", label: "Rozmiar tekstu", desc: "Także Ctrl+kółko myszy i Ctrl+= / Ctrl+−", type: "size" },
        { section: "Edytor", key: "fontFamily", label: "Czcionka", desc: "Czcionki o stałej szerokości znaków zainstalowane w systemie", type: "font" },
        { section: "Edytor", key: "wrap", label: "Zawijaj długie wiersze", desc: "Zamiast przewijania w bok (Alt+Z)", type: "bool" },
        { section: "Edytor", key: "minimap", label: "Minimapa", desc: "Podgląd całego pliku po prawej stronie", type: "bool" },
        { section: "Edytor", key: "autoClose", label: "Domykaj nawiasy i cudzysłowy", desc: "Po wpisaniu ( [ { \" ' ` wstawia od razu znak zamykający", type: "bool" },
        { section: "Edytor", key: "autoComplete", label: "Podpowiedzi przy pisaniu", desc: "Lista podpowiedzi otwiera się sama; Ctrl+Spacja działa zawsze", type: "bool" },
        { section: "Edytor", key: "defaultIndent", label: "Wcięcie w nowych plikach", desc: "W istniejących plikach wcięcie rozpoznaje się samo", type: "choice",
          options: [["2", "2 spacje"], ["4", "4 spacje"], ["tab", "Tabulator"]] },
        { section: "Pliki", key: "autoSave", label: "Zapisuj samoczynnie", desc: "Bez Ctrl+S — po chwili od ostatniej zmiany albo po przejściu do innej karty lub okna", type: "choice",
          options: [["off", "Nie"], ["delay", "Po chwili"], ["focus", "Przy zmianie okna"]] },
        { section: "Pliki", key: "formatOnSave", label: "Formatuj przy zapisie", desc: "Serwer języka porządkuje wcięcia i odstępy (jak Shift+Alt+F)", type: "bool" },
        { section: "Pliki", key: "trimTrailing", label: "Usuwaj spacje na końcach wierszy", desc: "Przy zapisie", type: "bool" },
        { section: "Pliki", key: "finalNewline", label: "Pusty wiersz na końcu pliku", desc: "Przy zapisie dopisuje znak końca wiersza, jeśli go brakuje", type: "bool" },
        { section: "Uruchamianie", key: "previewAuto", label: "Otwieraj podgląd strony sam", desc: "Gdy uruchomiony serwer poda swój adres (np. http://localhost:5173)", type: "bool" },
        { section: "Uruchamianie", key: "previewOnSave", label: "Odświeżaj podgląd po zapisie", desc: "Strona w podglądzie przeładowuje się po Ctrl+S", type: "bool" },
        { section: "Git", key: "diffSideBySide", label: "Różnice obok siebie", desc: "Stara wersja po lewej, nowa po prawej (także przycisk w podglądzie różnic)", type: "bool" },
        { section: "Git", key: "blame", label: "Autor wiersza", desc: "Kto i kiedy zmienił wiersz z kursorem — szary dopisek za jego końcem", type: "bool" },
        { section: "Git", key: "autoFetch", label: "Sprawdzaj serwer co 5 minut", desc: "Pokazuje, ile nowych zmian czeka do pobrania", type: "bool" },
        { section: "Serwery języków", key: "lsp", label: "Serwery języków", desc: "Podpowiedzi, błędy, przejście do definicji, zmiana nazwy", type: "bool" },
        { section: "Serwery języków", key: "", label: "Zainstalowane serwery", desc: "", type: "servers" }
    ]
    readonly property var rows: {
        const q = search.text.trim().toLowerCase();
        const out = [];
        let last = "";
        for (const it of items) {
            const hay = (it.section + " " + it.label + " " + it.desc + (it.type === "servers" ? " " + servers.map(s => s.name + " " + s.languages).join(" ") : "")).toLowerCase();
            if (q && hay.indexOf(q) < 0) continue;
            if (it.section !== last) { out.push({ type: "section", label: it.section }); last = it.section; }
            out.push(it);
        }
        return out;
    }

    // ——— Nagłówek ———
    Item {
        id: header
        width: parent.width; height: 58
        Text {
            x: col.x; anchors.verticalCenter: parent.verticalCenter
            text: "Ustawienia"; color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
        }
        Rectangle {
            id: searchBox
            anchors.right: closeBtn.left; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(320, parent.width - 220); height: 34; radius: 9
            color: Theme.fill
            border.width: search.activeFocus ? 1.5 : 0; border.color: Theme.accent
            Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 15; color: Theme.text2 }
            TextInput {
                id: search
                x: 32; width: parent.width - 40
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                font.family: Theme.font; font.pixelSize: 13
                clip: true
                Keys.onEscapePressed: { if (text) text = ""; else sv.close(); }
                Text { anchors.verticalCenter: parent.verticalCenter; visible: !search.text; text: "Szukaj w ustawieniach"; color: Theme.text2; font: search.font }
            }
        }
        HoverButton {
            id: closeBtn
            anchors.right: parent.right; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; radius: 8
            onClicked: sv.close()
            Icon { anchors.centerIn: parent; d: Icons.close; size: 13; stroke: 2; color: Theme.text2 }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
    }

    Flickable {
        id: flick
        y: header.height
        width: parent.width; height: parent.height - y
        contentHeight: col.height + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            x: Math.max(24, (parent.width - width) / 2); y: 8
            width: Math.min(760, flick.width - 48)
            Repeater {
                model: sv.rows
                delegate: Loader {
                    id: rowLoader
                    required property var modelData
                    width: col.width
                    sourceComponent: modelData.type === "section" ? sectionRow : modelData.type === "servers" ? serversRow : settingRow
                    onLoaded: item.it = modelData
                }
            }
            Text {
                visible: sv.rows.length === 0
                topPadding: 40
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: "Nic nie pasuje do „" + search.text + "”"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
            }
        }
    }

    // ——— Wiersze ———
    Component {
        id: sectionRow
        Item {
            id: secRow
            property var it
            height: 52
            Text {
                anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                text: secRow.it ? secRow.it.label.toUpperCase() : ""
                color: Theme.accentText; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.6
            }
        }
    }
    Component {
        id: settingRow
        Item {
            id: sr
            property var it: ({})
            readonly property var value: sv.prefs && it.key ? sv.prefs[it.key] : undefined
            function set(v) { sv.prefs[it.key] = v; }
            height: Math.max(58, texts.implicitHeight + 22)
            Rectangle { anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 2; radius: 10; color: hov.hovered ? Theme.hover : "transparent" }
            HoverHandler { id: hov }
            Column {
                id: texts
                x: 14; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 28 - control.width - 16
                spacing: 3
                Text { width: parent.width; wrapMode: Text.Wrap; text: sr.it.label || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                Text { width: parent.width; wrapMode: Text.Wrap; visible: !!sr.it.desc; text: sr.it.desc || ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
            }
            Item {
                id: control
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                width: childrenRect.width; height: childrenRect.height
                // Przełącznik
                Rectangle {
                    visible: sr.it.type === "bool"
                    width: 40; height: 24; radius: 12
                    color: sr.value === true ? Theme.accent : Theme.fill
                    border.width: sr.value === true ? 0 : 1; border.color: Theme.edge
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Rectangle {
                        x: sr.value === true ? parent.width - width - 3 : 3; anchors.verticalCenter: parent.verticalCenter
                        width: 18; height: 18; radius: 9
                        color: "white"
                        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sr.set(!sr.value) }
                }
                // Wybór jednej z kilku
                Row {
                    visible: sr.it.type === "choice" || sr.it.type === "font"
                    spacing: 4
                    Repeater {
                        model: sr.it.type === "choice" ? sr.it.options : sr.it.type === "font" ? sv.fonts.map(f => [f, f]) : []
                        delegate: HoverButton {
                            id: opt
                            required property var modelData
                            readonly property bool on: sr.value === modelData[0]
                            width: optText.implicitWidth + 22; height: 30; radius: 8
                            baseColor: on ? Theme.accentSoft : Theme.fill
                            onClicked: sr.set(modelData[0])
                            Text {
                                id: optText
                                anchors.centerIn: parent
                                text: opt.modelData[1]
                                color: opt.on ? Theme.accentText : Theme.text
                                font.family: sr.it.type === "font" ? opt.modelData[0] : Theme.font
                                font.pixelSize: 12; font.weight: opt.on ? Font.DemiBold : Font.Normal
                            }
                        }
                    }
                }
                // Rozmiar: − wartość +
                Row {
                    visible: sr.it.type === "size"
                    spacing: 4
                    HoverButton {
                        width: 30; height: 30; radius: 8; baseColor: Theme.fill
                        onClicked: sr.set(Math.max(9, sr.value - 0.5))
                        Text { anchors.centerIn: parent; text: "−"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15 }
                    }
                    Text {
                        width: 52; height: 30; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        text: sr.it.type === "size" ? String(sr.value).replace(".", ",") + " pt" : ""
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.features: { "tnum": 1 }
                    }
                    HoverButton {
                        width: 30; height: 30; radius: 8; baseColor: Theme.fill
                        onClicked: sr.set(Math.min(28, sr.value + 0.5))
                        Text { anchors.centerIn: parent; text: "+"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15 }
                    }
                }
            }
        }
    }
    // Lista serwerów języków: stan i polecenie instalacji
    Component {
        id: serversRow
        Column {
            property var it
            spacing: 2
            opacity: sv.prefs && sv.prefs.lsp ? 1 : 0.5
            Repeater {
                model: sv.servers
                delegate: Item {
                    id: srv
                    required property var modelData
                    width: parent.width; height: 50
                    Rectangle { anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 2; radius: 10; color: Theme.fill; opacity: 0.6 }
                    Rectangle {
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        width: 8; height: 8; radius: 4
                        color: srv.modelData.running ? (Theme.dark ? "#3FB950" : "#1A7F37") : srv.modelData.failed ? Theme.danger
                             : srv.modelData.available ? Theme.accent : Theme.text2
                        opacity: srv.modelData.available || srv.modelData.running ? 1 : 0.4
                    }
                    Column {
                        x: 34; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 34 - action.width - 24
                        spacing: 2
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: srv.modelData.name + "  ·  " + (srv.modelData.running ? "działa" : srv.modelData.failed ? "przestał działać"
                                                                  : srv.modelData.available ? "zainstalowany" : "nie zainstalowany")
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: srv.modelData.languages + (srv.modelData.available ? "" : "  ·  " + srv.modelData.package)
                            color: Theme.text2; font.family: srv.modelData.available ? Theme.font : "JetBrains Mono"; font.pixelSize: 11
                        }
                    }
                    HoverButton {
                        id: action
                        visible: !srv.modelData.available
                        anchors.right: parent.right; anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: actText.implicitWidth + 20; height: 28; radius: 8
                        baseColor: Theme.surface
                        onClicked: { Project.copyText(srv.modelData.package); Project.message("Polecenie w schowku — wklej je w terminalu (Ctrl+`)"); }
                        Text { id: actText; anchors.centerIn: parent; text: "Kopiuj polecenie"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                    }
                }
            }
        }
    }
}
