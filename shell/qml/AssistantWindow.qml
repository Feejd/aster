pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Aster.Shell
import Aster.Ui

// Panel asystenta z prawej (warstwa jak centrum sterowania): rozmowa z historią, kopiowanie odpowiedzi,
// „Nowa rozmowa” i lista zapisanych rozmów. Otwiera się sam, gdy rozmowa w wyspie robi się dłuższa,
// albo Super+Spacja / klik w wyspę, gdy już coś w nim jest. Klik obok panelu albo Esc zamyka.
// Każda odpowiedź ma znaczek: „Na tym komputerze” albo „Chmura: <dostawca>”.
Window {
    id: aw
    color: "transparent"
    visible: false
    width: Screen.width
    height: Screen.height - 46 - 84
    readonly property int shotY: 46
    title: "Asystent"

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
        if (t === "" || Assistant.busy) return;
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

    Timer { id: hideTimer; interval: 110; onTriggered: aw.visible = false }

    MouseArea { anchors.fill: parent; onClicked: aw.close() }
    Shortcut { sequence: "Escape"; onActivated: { if (aw.showHistory) aw.showHistory = false; else aw.close(); } }

    Item {
        id: panel
        width: 420
        height: aw.height - 8
        x: aw.width - width - 10
        y: 4
        onHeightChanged: blurTimer.restart()

        // Wejście: wysuwa się z prawej i lekko rośnie
        property real offset: 24
        property real s: 0.97
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
                    NumberAnimation { target: panel; property: "offset"; duration: 260; easing.type: Easing.OutQuint }
                    NumberAnimation { target: panel; property: "s"; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 0.7 }
                    NumberAnimation { target: panel; property: "opacity"; duration: 90 }
                }
            },
            Transition {
                from: "shown"
                ParallelAnimation {
                    NumberAnimation { target: panel; property: "offset"; to: 16; duration: 100; easing.type: Easing.InCubic }
                    NumberAnimation { target: panel; property: "opacity"; duration: 100 }
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
            Rectangle {
                id: hSpark
                width: 32; height: 32; radius: 16
                anchors.verticalCenter: parent.verticalCenter
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.45) }
                    GradientStop { position: 1; color: "#7C3AED" }
                }
                Icon {
                    anchors.centerIn: parent; d: Icons.sparkle; size: 17; stroke: 2; color: "white"
                    RotationAnimation on rotation { running: Assistant.busy; loops: Animation.Infinite; from: 0; to: 360; duration: 1600 }
                }
            }
            Column {
                anchors.left: hSpark.right; anchors.leftMargin: 10
                anchors.right: buttons.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    text: aw.showHistory ? "Historia rozmów" : "Asystent"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: Assistant.available ? (Assistant.status.badge + " · " + Assistant.status.model) : "Usługa asystenta nie odpowiada"
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
            height: composer.y - y - 6
            clip: true
            spacing: 14
            topMargin: 14; bottomMargin: 10
            boundsBehavior: Flickable.StopAtBounds
            model: Assistant.messages
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
                readonly property bool mine: role === "user"
                width: ListView.view.width
                height: mine ? bubble.height : answer.height

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
                    visible: !msg.mine
                    width: parent.width
                    spacing: 8
                    HoverHandler { id: answerHover }
                    Row {
                        visible: msg.pending && msg.text === ""
                        spacing: 5; height: 20
                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                id: dot
                                required property int index
                                width: 6; height: 6; radius: 3
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.text2
                                SequentialAnimation on opacity {
                                    running: msg.pending; loops: Animation.Infinite
                                    PauseAnimation { duration: dot.index * 160 }
                                    NumberAnimation { from: 0.25; to: 1; duration: 320 }
                                    NumberAnimation { from: 1; to: 0.25; duration: 320 }
                                    PauseAnimation { duration: (2 - dot.index) * 160 }
                                }
                            }
                        }
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
                        visible: !msg.pending
                        spacing: 6
                        height: 24
                        AssistantBadge { anchors.verticalCenter: parent.verticalCenter; onDark: false; text: msg.error ? "" : msg.badge }
                        Rectangle {
                            visible: msg.error
                            anchors.verticalCenter: parent.verticalCenter
                            width: setText.implicitWidth + 18; height: 22; radius: 11
                            color: setArea.containsMouse ? Theme.hover : Theme.fill
                            Text { id: setText; anchors.centerIn: parent; text: "Ustawienia asystenta"; color: Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
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
            y: 150
            width: parent.width - 64
            spacing: 10
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
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
                model: ["Jak spakować folder do zip?", "Co robi polecenie chmod +x?", "Przetłumacz na angielski: dzień dobry, jak się masz?"]
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

        // ——— Pole pytania ———
        Rectangle {
            id: composer
            x: 12
            width: parent.width - 24
            height: Math.min(input.contentHeight, 120) + 24
            y: parent.height - height - 34
            radius: 20
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.85)
            border.width: 1
            border.color: input.activeFocus ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6) : Theme.line
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
                        text: Assistant.count > 0 ? "Dopytaj…" : "Zapytaj o cokolwiek…"
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
