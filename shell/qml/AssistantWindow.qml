pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Aster.Shell
import Aster.Ui

// Panel Aster Intelligence z prawej (warstwa jak centrum sterowania): rozmowa z historią, kopiowanie odpowiedzi,
// „Nowa rozmowa” i lista zapisanych rozmów. Otwiera się sam, gdy rozmowa w wyspie robi się dłuższa,
// albo Super+Spacja / klik w wyspę, gdy już coś w nim jest. Klik obok panelu albo Esc zamyka.
// Każda odpowiedź ma znaczek: „Na tym komputerze” albo „Chmura: <dostawca>”.
Window {
    id: aw
    property bool followsPrimary: true   // po zmianie głównego ekranu main.cpp przenosi okno
    color: "transparent"
    visible: false
    width: Screen.width
    height: Screen.height - 46 - 84
    readonly property int shotY: 46
    title: "Aster Intelligence"

    property bool open: false
    property bool showHistory: false
    property var historyItems: []

    Component.onCompleted: Platform.makeLayer(aw, "overlay", 1 | 2 | 4 | 8, 0, "exclusive", "aster-assistant")

    function toggle() { if (open) close(); else show(); }
    function show() {
        hideTimer.stop();
        visible = true;
        open = true;
        Assistant.refreshStatus();
        input.forceActiveFocus();
        blurTimer.restart();
        list.positionViewAtEnd();
    }
    function close() {
        if (!open) return;
        open = false;
        showHistory = false;
        hideTimer.restart();
    }
    function send() {
        const t = input.text.trim();
        if (t === "") return;
        // Nowa wiadomość zamiast odpowiedzi na pytanie o zgodę — to „nie” i dalsza rozmowa
        if (Assistant.waiting) Assistant.cancel();
        else if (Assistant.busy) return;
        input.text = "";
        showHistory = false;
        Assistant.ask(t, "panel");
    }
    // Do testów (ASTER_SHOT_ASK)
    function askNow(t) { input.text = t; send(); }
    function openHistory() {
        historyItems = Assistant.history();
        showHistory = true;
    }
    function when(ms) {
        const d = new Date(ms), now = new Date();
        const loc = Qt.locale("pl_PL");
        if (d.toDateString() === now.toDateString()) return "dziś, " + d.toLocaleTimeString(loc, "HH:mm");
        const y = new Date(now); y.setDate(now.getDate() - 1);
        if (d.toDateString() === y.toDateString()) return "wczoraj, " + d.toLocaleTimeString(loc, "HH:mm");
        return d.toLocaleDateString(loc, "d MMMM");
    }

    Timer { id: hideTimer; interval: 180; onTriggered: aw.visible = false }

    MouseArea { anchors.fill: parent; onClicked: aw.close() }
    Shortcut { sequence: "Escape"; onActivated: { if (aw.showHistory) aw.showHistory = false; else aw.close(); } }

    Item {
        id: panel
        width: 420
        height: aw.height - 8
        x: aw.width - width - 10
        y: 4
        onHeightChanged: blurTimer.restart()

        // Rozlewa się z kropli rozmowy (prawy górny róg, pod prawą wyspą) i w nią się chowa
        property real offset: 0
        property real s: 0.55
        opacity: 0
        transform: [
            Scale { origin.x: panel.width; origin.y: 0; xScale: panel.s; yScale: panel.s },
            Translate { x: panel.offset }
        ]
        states: State {
            name: "shown"; when: aw.open
            PropertyChanges { panel.offset: 0; panel.s: 1; panel.opacity: 1 }
        }
        transitions: [
            Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: panel; property: "s"; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
                    NumberAnimation { target: panel; property: "opacity"; duration: 110 }
                }
            },
            Transition {
                from: "shown"
                ParallelAnimation {
                    // chowa się z powrotem w kroplę pod prawą wyspą
                    NumberAnimation { target: panel; property: "s"; to: 0.5; duration: 170; easing.type: Easing.InCubic }
                    NumberAnimation { target: panel; property: "opacity"; duration: 170; easing.type: Easing.InQuad }
                }
            }
        ]

        MouseArea { anchors.fill: parent }

        Island { anchors.fill: parent; radius: 30 }
        Rectangle {
            anchors.fill: parent
            radius: 30
            color: Theme.dark ? Qt.rgba(0.09, 0.09, 0.11, 0.55) : Qt.rgba(1, 1, 1, 0.55)
        }

        // ——— Nagłówek ———
        Item {
            id: header
            x: 16; y: 12
            width: parent.width - 32
            height: 44
            IntelligenceOrb {
                id: hSpark
                size: 32
                busy: Assistant.busy
                anchors.verticalCenter: parent.verticalCenter
            }
            Column {
                anchors.left: hSpark.right; anchors.leftMargin: 10
                anchors.right: buttons.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    text: aw.showHistory ? "Historia rozmów" : "Aster Intelligence"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: Assistant.available ? (Assistant.status.badge + " · " + Assistant.status.model) : "Usługa nie odpowiada"
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: 11
                }
            }
            Row {
                id: buttons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                PanelButton { icon: Icons.clock; active: aw.showHistory; tip: "Historia"; onClicked: aw.showHistory ? aw.showHistory = false : aw.openHistory() }
                PanelButton { icon: Icons.plus; tip: "Nowa rozmowa"; onClicked: { Assistant.newConversation(); aw.showHistory = false; input.forceActiveFocus(); } }
                PanelButton { icon: Icons.close; tip: "Zamknij"; onClicked: aw.close() }
            }
        }
        Rectangle { x: 16; y: header.y + header.height + 8; width: parent.width - 32; height: 1; color: Theme.line }

        // ——— Rozmowa ———
        ListView {
            id: list
            visible: !aw.showHistory
            x: 16
            y: header.y + header.height + 9
            width: parent.width - 32
            height: (undoChip.visible ? undoChip.y : composer.y) - y - 6
            clip: true
            spacing: 14
            topMargin: 14; bottomMargin: 10
            boundsBehavior: Flickable.StopAtBounds
            model: Assistant.messages
            // Nowa wiadomość wjeżdża od dołu i przenika
            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 380; easing.type: Easing.OutBack }
                }
            }
            // Odpowiedź rośnie — trzymaj koniec w widoku
            onCountChanged: Qt.callLater(list.positionViewAtEnd)
            onContentHeightChanged: if (atYEnd || Assistant.busy) Qt.callLater(list.positionViewAtEnd)

            delegate: Item {
                id: msg
                required property string role
                required property string text
                required property string badge
                required property bool error
                required property bool pending
                required property string command
                required property string phase
                required property string output
                readonly property bool mine: role === "user"
                readonly property bool act: role === "action"
                width: ListView.view.width
                height: mine ? bubble.height : act ? card.height : answer.height

                // Działanie agenta: zdanie po ludzku, zgoda, a polecenie i wynik w szczegółach
                ActionCard {
                    id: card
                    visible: msg.act
                    width: parent.width
                    description: msg.text
                    command: msg.command
                    phase: msg.phase
                    output: msg.output
                }

                // Pytanie: dymek w kolorze akcentu po prawej
                Rectangle {
                    id: bubble
                    visible: msg.mine
                    anchors.right: parent.right
                    width: Math.min(q.implicitWidth + 28, parent.width * 0.82)
                    height: q.implicitHeight + 18
                    radius: 17
                    color: Theme.accent
                    Text {
                        id: q
                        x: 14; y: 9
                        width: parent.width - 28
                        text: msg.text
                        wrapMode: Text.Wrap
                        color: "white"
                        font.family: Theme.font; font.pixelSize: 14
                    }
                }

                // Odpowiedź: tekst (Markdown), znaczek i kopiowanie
                Column {
                    id: answer
                    visible: msg.role === "assistant"
                    width: parent.width
                    spacing: 8
                    HoverHandler { id: answerHover }
                    ShimmerText {
                        visible: msg.pending && msg.text === ""
                        text: Assistant.status.local ? "Myślę na tym komputerze…" : "Myślę…"
                        base: Theme.text2
                        pixelSize: 14
                    }
                    TextEdit {
                        visible: msg.text !== ""
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        text: msg.text
                        textFormat: msg.error ? TextEdit.PlainText : TextEdit.MarkdownText
                        wrapMode: TextEdit.Wrap
                        color: msg.error ? Theme.danger : Theme.text
                        selectionColor: Theme.accentSoft
                        font.family: Theme.font; font.pixelSize: 14
                        onLinkActivated: link => Qt.openUrlExternally(link)
                    }
                    Row {
                        visible: !msg.pending && (msg.badge !== "" || msg.error)
                        spacing: 6
                        height: 24
                        AssistantBadge { anchors.verticalCenter: parent.verticalCenter; onDark: false; text: msg.error ? "" : msg.badge }
                        Rectangle {
                            visible: msg.error
                            anchors.verticalCenter: parent.verticalCenter
                            width: setText.implicitWidth + 18; height: 22; radius: 11
                            color: setArea.containsMouse ? Theme.hover : Theme.fill
                            Text { id: setText; anchors.centerIn: parent; text: "Ustawienia Aster Intelligence"; color: Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
                            MouseArea { id: setArea; anchors.fill: parent; hoverEnabled: true; onClicked: { aw.close(); Assistant.openSettings(); } }
                        }
                        PanelButton {
                            visible: !msg.error
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24
                            opacity: answerHover.hovered ? 1 : 0
                            icon: copied.running ? Icons.check : Icons.copy; iconSize: 13
                            onClicked: { Assistant.copy(msg.text); copied.restart(); }
                            Timer { id: copied; interval: 1400 }
                        }
                    }
                }
            }
        }

        // Pusto: podpowiedzi pierwszych pytań
        Column {
            visible: !aw.showHistory && Assistant.count === 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: 110
            width: parent.width - 64
            spacing: 10
            IntelligenceOrb {
                anchors.horizontalCenter: parent.horizontalCenter
                size: 56
                busy: false
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                topPadding: 4
                text: "O co chcesz zapytać?"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Assistant.status.local ? "Odpowiada model na tym komputerze — nic nie wychodzi z sieci."
                    : Assistant.available ? "Pytania trafiają do: " + (Assistant.status.providerName || "") + (Assistant.status.region ? " (" + Assistant.status.region + ")." : ".")
                    : ""
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 12
                bottomPadding: 6
            }
            Repeater {
                model: ["Ile mam wolnego miejsca na dysku?", "Zrób mi prostą stronę o mnie i otwórz ją w Aster Code",
                        "Jakie okna mam otwarte? Zostaw tylko przeglądarkę", "O czym rozmawialiśmy ostatnio?"]
                delegate: Rectangle {
                    id: sug
                    required property string modelData
                    width: parent.width
                    height: sugText.implicitHeight + 18
                    radius: 14
                    color: sugArea.containsMouse ? Theme.hover : Theme.fill
                    Text {
                        id: sugText
                        x: 14; y: 9; width: parent.width - 28
                        text: sug.modelData
                        wrapMode: Text.Wrap
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 13
                    }
                    MouseArea { id: sugArea; anchors.fill: parent; hoverEnabled: true; onClicked: aw.askNow(sug.modelData) }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 6
                text: "Poprzednie rozmowy"
                color: prevArea.containsMouse ? Theme.text : (Theme.dark ? "#7DD3FC" : "#2563EB")
                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                MouseArea { id: prevArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: aw.openHistory() }
            }
        }

        // ——— Historia ———
        ListView {
            visible: aw.showHistory
            x: 10
            y: header.y + header.height + 12
            width: parent.width - 20
            height: composer.y - y - 6
            clip: true
            spacing: 2
            model: aw.historyItems
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: h
                required property var modelData
                width: ListView.view.width
                height: 50
                radius: 12
                color: hArea.containsMouse ? Theme.hover : (h.modelData.id === Assistant.conversation ? Theme.fill : "transparent")
                MouseArea {
                    id: hArea; anchors.fill: parent; hoverEnabled: true
                    onClicked: { Assistant.openConversation(h.modelData.id); aw.showHistory = false; }
                }
                Column {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 54
                    spacing: 2
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: h.modelData.title || "Rozmowa"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                    }
                    Text {
                        text: aw.when(h.modelData.updated) + " · " + h.modelData.count + " wiad."
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 11
                    }
                }
                PanelButton {
                    anchors.right: parent.right; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: hArea.containsMouse || hovered ? 1 : 0
                    icon: Icons.trash; iconSize: 14; tip: "Usuń"
                    onClicked: { Assistant.deleteConversation(h.modelData.id); aw.historyItems = aw.historyItems.filter(x => x.id !== h.modelData.id); }
                }
            }
            Text {
                visible: aw.historyItems.length === 0
                anchors.centerIn: parent
                text: Assistant.status.history === false ? "Zapisywanie rozmów jest wyłączone w Ustawieniach" : "Brak zapisanych rozmów"
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 13
            }
        }

        // Agent zmienił pliki projektu — jednym klikiem wszystko wraca (punkt powrotu sprzed zmian)
        Rectangle {
            id: undoChip
            visible: Assistant.canUndo && !aw.showHistory
            anchors.horizontalCenter: parent.horizontalCenter
            y: composer.y - height - 8
            height: 28
            width: undoRow.implicitWidth + 24
            radius: 14
            color: undoArea.containsMouse ? Theme.hover : Theme.fill
            Row {
                id: undoRow
                anchors.centerIn: parent
                spacing: 6
                Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.undo; size: 13; stroke: 2; color: Theme.text }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Cofnij zmiany w plikach"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                }
            }
            MouseArea { id: undoArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Assistant.undoChanges() }
        }

        // ——— Pole pytania ———
        Rectangle {
            id: composer
            x: 12
            width: parent.width - 24
            height: Math.min(input.contentHeight, 120) + 24
            y: parent.height - height - 34
            radius: 20
            color: Theme.dark ? Qt.rgba(0.1, 0.1, 0.12, 0.9) : Qt.rgba(1, 1, 1, 0.92)
            border.width: 1
            border.color: input.activeFocus ? (Theme.dark ? "#60A5FA" : "#3B82F6") : Theme.line
            Flickable {
                id: inputFlick
                x: 14; y: 12
                width: parent.width - 60
                height: parent.height - 24
                contentHeight: input.contentHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                TextEdit {
                    id: input
                    width: inputFlick.width
                    wrapMode: TextEdit.Wrap
                    color: Theme.text
                    selectionColor: Theme.accentSoft
                    font.family: Theme.font; font.pixelSize: 14
                    // Enter wysyła, Shift+Enter — nowy wiersz
                    Keys.onReturnPressed: event => { if (event.modifiers & Qt.ShiftModifier) event.accepted = false; else aw.send(); }
                    Keys.onEnterPressed: aw.send()
                    onCursorRectangleChanged: if (cursorRectangle.y + cursorRectangle.height > inputFlick.contentY + inputFlick.height)
                                                  inputFlick.contentY = cursorRectangle.y + cursorRectangle.height - inputFlick.height
                    Text {
                        visible: !input.text
                        text: Assistant.count > 0 ? "Dopytaj…" : "Zapytaj Aster Intelligence…"
                        color: Theme.text2
                        font: input.font
                    }
                }
            }
            // Wyślij / zatrzymaj
            Rectangle {
                anchors.right: parent.right; anchors.rightMargin: 7
                anchors.bottom: parent.bottom; anchors.bottomMargin: 7
                width: 32; height: 32; radius: 16
                readonly property bool canSend: input.text.trim() !== ""
                color: Assistant.busy ? Theme.text : (canSend ? Theme.accent : Theme.fill)
                Behavior on color { ColorAnimation { duration: 120 } }
                Icon {
                    anchors.centerIn: parent
                    d: Assistant.busy ? Icons.stop : Icons.up
                    size: Assistant.busy ? 12 : 16; stroke: 2.4
                    color: Assistant.busy ? (Theme.dark ? "#16181D" : "white") : (parent.canSend ? "white" : Theme.text2)
                }
                MouseArea { anchors.fill: parent; onClicked: Assistant.busy ? Assistant.cancel() : aw.send() }
            }
        }
        // Kto odpowiada (dla następnej wiadomości)
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - 26
            spacing: 6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Odpowiada:"
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 11
            }
            AssistantBadge { anchors.verticalCenter: parent.verticalCenter; onDark: false; text: Assistant.status.badge || ""; scale: 0.92 }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Zmień"
                color: chArea.containsMouse ? Theme.accentText : Theme.text2
                font.family: Theme.font; font.pixelSize: 11; font.underline: chArea.containsMouse
                MouseArea { id: chArea; anchors.fill: parent; hoverEnabled: true; onClicked: { aw.close(); Assistant.openSettings(); } }
            }
        }
    }

    // Karta działania: „Zainstalować Google Chrome?” [Uruchom] [Nie] · Szczegóły (polecenie, wynik, terminal)
    component ActionCard: Rectangle {
        id: ac
        property string description
        property string command
        property string phase
        property string output
        property bool details: false
        readonly property bool waiting: phase === "czeka"
        readonly property bool running: phase === "dziala"
        readonly property color tint: phase === "gotowe" ? "#34C759" : phase === "blad" ? "#FF453A"
                                    : phase === "odmowa" ? Theme.text2 : "#3B82F6"
        height: col.implicitHeight + 24
        radius: 16
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.7)
        border.width: 1
        border.color: waiting ? Qt.rgba(0.23, 0.51, 0.96, 0.6) : Theme.line
        Behavior on border.color { ColorAnimation { duration: 200 } }


        Column {
            id: col
            x: 12; y: 12
            width: parent.width - 24
            spacing: 10
            Row {
                width: parent.width
                spacing: 10
                // Stan: kula przy pytaniu i pracy, ptaszek / wykrzyknik / kreska po wszystkim
                Item {
                    width: 26; height: 26
                    IntelligenceOrb { anchors.fill: parent; size: 26; visible: ac.waiting || ac.running; busy: ac.running }
                    Rectangle {
                        anchors.fill: parent; radius: 13
                        visible: !ac.waiting && !ac.running
                        color: Qt.rgba(ac.tint.r, ac.tint.g, ac.tint.b, 0.16)
                        Icon {
                            anchors.centerIn: parent
                            d: ac.phase === "gotowe" ? Icons.check : ac.phase === "blad" ? Icons.alertCircle : Icons.minus
                            size: 13; stroke: 2.4
                            color: ac.tint
                        }
                    }
                }
                Column {
                    width: parent.width - 36
                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        width: parent.width
                        text: ac.description
                        wrapMode: Text.Wrap
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    Text {
                        text: ac.running ? "W toku…" : ac.phase === "gotowe" ? "Zrobione" : ac.phase === "blad" ? "Nie wyszło — Aster Intelligence szuka innej drogi"
                            : ac.phase === "odmowa" ? "Pominięte" : "Potrzebna twoja zgoda"
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 11
                    }
                }
            }
            Row {
                visible: ac.waiting
                spacing: 8
                Rectangle {
                    width: runText.implicitWidth + 30; height: 32; radius: 16
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: runArea.containsMouse ? "#38BDF8" : "#3B82F6" }
                        GradientStop { position: 1; color: runArea.containsMouse ? "#2563EB" : "#1D4ED8" }
                    }
                    scale: runArea.pressed ? 0.95 : 1
                    Behavior on scale { NumberAnimation { duration: 90 } }
                    Text { id: runText; anchors.centerIn: parent; text: "Tak, zrób to"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                    MouseArea { id: runArea; anchors.fill: parent; hoverEnabled: true; onClicked: Assistant.approve(true) }
                }
                Rectangle {
                    width: noText.implicitWidth + 28; height: 32; radius: 16
                    color: noArea.containsMouse ? Theme.hover : Theme.fill
                    Text { id: noText; anchors.centerIn: parent; text: "Nie"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                    MouseArea { id: noArea; anchors.fill: parent; hoverEnabled: true; onClicked: Assistant.approve(false) }
                }
            }
            Text {
                text: ac.details ? "Ukryj szczegóły" : "Pokaż szczegóły"
                color: detArea.containsMouse ? Theme.accentText : Theme.text2
                font.family: Theme.font; font.pixelSize: 11; font.underline: detArea.containsMouse
                MouseArea { id: detArea; anchors.fill: parent; hoverEnabled: true; onClicked: ac.details = !ac.details }
            }
            Rectangle {
                visible: ac.details
                width: parent.width
                height: det.implicitHeight + 16
                radius: 10
                color: Theme.dark ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(0, 0, 0, 0.05)
                Column {
                    id: det
                    x: 10; y: 8
                    width: parent.width - 20
                    spacing: 6
                    TextEdit {
                        width: parent.width
                        readOnly: true; selectByMouse: true
                        text: "$ " + ac.command
                        wrapMode: TextEdit.WrapAnywhere
                        color: Theme.text
                        font.family: "monospace"; font.pixelSize: 12
                    }
                    TextEdit {
                        visible: ac.output !== ""
                        width: parent.width
                        readOnly: true; selectByMouse: true
                        text: ac.output.split("\n").slice(-14).join("\n")
                        wrapMode: TextEdit.WrapAnywhere
                        color: Theme.text2
                        font.family: "monospace"; font.pixelSize: 11
                    }
                    Text {
                        text: "Otwórz w Terminalu"
                        color: termArea.containsMouse ? Theme.accentText : Theme.text2
                        font.family: Theme.font; font.pixelSize: 11; font.underline: termArea.containsMouse
                        MouseArea { id: termArea; anchors.fill: parent; hoverEnabled: true; onClicked: Assistant.openInTerminal(ac.command) }
                    }
                }
            }
        }
    }

    component PanelButton: HoverButton {
        id: pb
        property string icon
        property real iconSize: 15
        property bool active: false
        property string tip
        width: 30; height: 30; radius: 15
        baseColor: active ? Theme.accentSoft : "transparent"
        Icon { anchors.centerIn: parent; d: pb.icon; size: pb.iconSize; stroke: 2; color: pb.active ? Theme.accentText : Theme.text }
    }

    Timer {
        id: blurTimer
        interval: 20
        onTriggered: Platform.setBlur(aw, [{ x: panel.x, y: panel.y, w: panel.width, h: panel.height, r: 30 }])
    }
}
