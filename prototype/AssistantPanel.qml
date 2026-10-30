import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "Icons.js" as I

// Asystent pod klawiszem. W prototypie rozumie kilka poleceń lokalnie (bez sieci);
// każda zmiana w systemie pokazuje kartę „było → będzie” i czeka na zgodę.
Panel {
    id: ap
    property bool dark: false
    property real volume: 0.45
    property string output: "Głośniki laptopa"
    property var files: []
    property bool thinking: false
    property string pendingQuestion: ""

    signal setDark(bool on)
    signal setOutput(string name)
    signal setVolume(real v)
    signal openFiles()
    signal closeRequested()

    width: 640
    height: 560
    originX: 0.5
    originY: 0.35

    // Świetlista obwódka: obracający się gradient zorzy; przyspiesza, gdy asystent „myśli”
    Item {
        id: glow
        property real angle: 0
        anchors.fill: parent
        anchors.margins: -1.5
        opacity: ap.thinking ? 1 : 0.7
        Behavior on opacity { NumberAnimation { duration: 180 } }
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: ring
            maskThresholdMin: 0.3
            maskSpreadAtMin: 0.3
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"
                fillGradient: ConicalGradient {
                    centerX: glow.width / 2
                    centerY: glow.height / 2
                    angle: glow.angle
                    GradientStop { position: 0.0; color: "#6F97FF" }
                    GradientStop { position: 0.25; color: "#B497FF" }
                    GradientStop { position: 0.5; color: "#FFAE85" }
                    GradientStop { position: 0.75; color: "#7DDCCB" }
                    GradientStop { position: 1.0; color: "#6F97FF" }
                }
                PathRectangle { x: 0; y: 0; width: glow.width; height: glow.height }
            }
        }
        NumberAnimation on angle {
            running: ap.visible
            from: 0; to: 360
            duration: 5200
            loops: Animation.Infinite
        }
    }
    Item {
        id: ring
        anchors.fill: glow
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.fill: parent
            radius: 19.5
            color: "transparent"
            border.width: ap.thinking ? 3 : 2
            border.color: "black"
        }
    }
    Timer {
        // Przy „myśleniu” obwódka kręci się szybciej
        interval: 16; repeat: true; running: ap.thinking
        onTriggered: glow.angle = (glow.angle + 6) % 360
    }

    onOpenChanged: if (open) input.forceActiveFocus()

    ListModel { id: msgs }

    function add(role, text, extra) {
        const m = { role: role, text: text, kind: "", title: "", fromLabel: "", toLabel: "", action: "", value: "", status: "" };
        for (const k in extra) m[k] = extra[k];
        msgs.append(m);
        list.positionViewAtEnd();
    }

    function say(text) { add("assistant", text, {}) }

    function propose(text, title, fromLabel, toLabel, action, value) {
        add("assistant", text, { kind: "change", title: title, fromLabel: fromLabel, toLabel: toLabel, action: action, value: String(value), status: "pending" });
    }

    function send(q) {
        q = q.trim();
        if (!q || thinking) return;
        add("user", q, {});
        input.text = "";
        pendingQuestion = q;
        thinking = true;
        replyTimer.restart();
    }

    Timer {
        id: replyTimer
        interval: 650
        onTriggered: {
            ap.thinking = false;
            ap.respond(ap.pendingQuestion);
        }
    }

    function respond(q) {
        const s = q.toLowerCase();
        const has = (...words) => words.some(w => s.indexOf(w) >= 0);
        const pct = (v) => Math.round(v * 100) + "%";

        if (has("słuchawk", "z laptopa", "z głośnik")) {
            if (output === "Słuchawki Bluetooth")
                return say("Dźwięk już idzie do słuchawek Bluetooth. Jeśli nic nie słychać, sprawdź głośność na samych słuchawkach.");
            return propose("Słuchawki są połączone przez Bluetooth, ale dźwięk nadal idzie do głośników laptopa. Mogę to przełączyć.",
                           "Wyjście dźwięku", output, "Słuchawki Bluetooth", "output", "Słuchawki Bluetooth");
        }
        if (has("ciemn", "noc")) {
            if (dark) return say("Tryb ciemny jest już włączony.");
            return propose("Mogę włączyć tryb ciemny w całym systemie.", "Wygląd", "Jasny", "Ciemny", "dark", "1");
        }
        if (has("jasn")) {
            if (!dark) return say("Jasny wygląd jest już włączony.");
            return propose("Mogę wrócić do jasnego wyglądu.", "Wygląd", "Ciemny", "Jasny", "dark", "0");
        }
        if (has("głośniej", "podgłoś", "zwiększ głoś", "za cicho")) {
            const v = Math.min(1, volume + 0.2);
            return propose("Mogę zrobić głośniej.", "Głośność", pct(volume), pct(v), "volume", v);
        }
        if (has("ciszej", "przycisz", "zmniejsz głoś", "za głośno")) {
            const v = Math.max(0, volume - 0.2);
            return propose("Mogę przyciszyć.", "Głośność", pct(volume), pct(v), "volume", v);
        }
        if (has("znajdź", "szukaj", "gdzie jest", "gdzie mam")) {
            const words = s.replace(/znajdź|szukaj|gdzie jest|gdzie mam|plik[iu]?|moj[aąeę]?|z zeszłego miesiąca/g, " ")
                           .split(/[^a-ząćęłńóśźż0-9]+/).filter(w => w.length > 2);
            const hits = files.filter(f => words.some(w => f.name.toLowerCase().indexOf(w.slice(0, Math.max(3, w.length - 2))) >= 0));
            if (!hits.length) return say("Nie znalazłem pasujących plików. Spróbuj innym słowem z nazwy.");
            return say("Znalazłem:\n" + hits.map(f => "•  " + f.name + "  —  " + f.where).join("\n"));
        }
        if (has("otwórz pliki", "pliki", "eksplorator")) {
            openFiles();
            return say("Otworzyłem Pliki.");
        }
        if (has("drukark", "drukuj")) {
            return say("Sprawdźmy po kolei:\n1. Czy drukarka jest włączona i w tej samej sieci Wi-Fi?\n2. W Ustawieniach › Drukarki dodasz ją jednym kliknięciem — system sam znajdzie sterownik.\n\nW prototypie nie widzę prawdziwych drukarek.");
        }
        return say("W tym prototypie umiem: przełączyć dźwięk na słuchawki, włączyć tryb ciemny albo jasny, zmienić głośność, znaleźć plik i otworzyć Pliki. Z prawdziwym modelem AI zrozumiem dowolne polecenie.");
    }

    function approveLast() {
        for (let i = msgs.count - 1; i >= 0; i--)
            if (msgs.get(i).status === "pending") return apply(i, true);
    }

    function apply(index, ok) {
        const m = msgs.get(index);
        if (!ok) {
            msgs.setProperty(index, "status", "cancelled");
            return;
        }
        if (m.action === "dark") setDark(m.value === "1");
        else if (m.action === "output") setOutput(m.value);
        else if (m.action === "volume") setVolume(Number(m.value));
        msgs.setProperty(index, "status", "done");
    }

    // Nagłówek
    Item {
        id: header
        width: parent.width; height: 64
        Rectangle {
            id: logo
            x: 18; anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 32; radius: 10
            color: ap.t.accent
            Icon { anchors.centerIn: parent; d: I.sparkle; color: "white" }
        }
        Text { anchors.left: logo.right; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: "Asystent"; color: ap.t.text; font.pixelSize: 15; font.weight: Font.DemiBold }
        Rectangle {
            anchors.right: closeBtn.left; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: hint.implicitWidth + 16; height: 24; radius: 6
            color: ap.t.fill
            Text { id: hint; anchors.centerIn: parent; text: "klawisz AI lub ⌥ A"; color: ap.t.text2; font.pixelSize: 12 }
        }
        HoverButton {
            id: closeBtn
            t: ap.t
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 32; radius: 8
            onClicked: ap.closeRequested()
            Icon { anchors.centerIn: parent; d: I.close; size: 16; color: ap.t.text }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ap.t.line }
    }

    // Powitanie, gdy rozmowa jest pusta
    Column {
        x: 22; y: header.height + 22
        width: parent.width - 44
        spacing: 14
        visible: msgs.count === 0
        Text { text: "W czym pomóc?"; color: ap.t.text; font.pixelSize: 22; font.weight: Font.Bold }
        Text {
            width: parent.width
            text: "Powiedz, co ma się stać — zrobię to albo pokażę, gdzie to jest. Zanim coś zmienię, zapytam."
            color: ap.t.text2; font.pixelSize: 14; wrapMode: Text.Wrap; lineHeight: 1.2
        }
        Flow {
            width: parent.width
            spacing: 8
            topPadding: 6
            Repeater {
                model: ["Podłączyłem słuchawki, ale dźwięk dalej leci z laptopa", "Włącz tryb ciemny", "Znajdź umowę", "Czemu drukarka nie drukuje?", "Zrób ciszej"]
                delegate: Rectangle {
                    id: chip
                    required property string modelData
                    width: chipText.implicitWidth + 26; height: 34; radius: 17
                    color: chipArea.containsMouse ? ap.t.fill : ap.t.surface
                    border.width: 1; border.color: ap.t.line
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text { id: chipText; anchors.centerIn: parent; text: chip.modelData; color: ap.t.text; font.pixelSize: 13 }
                    MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; onClicked: ap.send(chip.modelData) }
                }
            }
        }
    }

    // Rozmowa
    ListView {
        id: list
        x: 22; y: header.height + 16
        width: parent.width - 44
        height: inputBar.y - y - 10
        clip: true
        spacing: 14
        model: msgs
        visible: msgs.count > 0
        onCountChanged: Qt.callLater(positionViewAtEnd)

        footer: Item {
            width: list.width; height: ap.thinking ? 40 : 0
            Row {
                visible: ap.thinking
                y: 14
                spacing: 5
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        required property int index
                        width: 7; height: 7; radius: 4
                        color: ap.t.text2
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 150 }
                            NumberAnimation { from: 0.25; to: 1; duration: 300 }
                            NumberAnimation { from: 1; to: 0.25; duration: 300 }
                            PauseAnimation { duration: (2 - index) * 150 }
                        }
                    }
                }
            }
        }

        delegate: Item {
            id: msg
            required property int index
            required property string role
            required property string text
            required property string kind
            required property string title
            required property string fromLabel
            required property string toLabel
            required property string status
            width: list.width
            height: msg.role === "user" ? bubble.height : answer.height
            transform: Translate { id: msgShift }
            Component.onCompleted: {
                opacity = 0;
                if (role === "user") msgShift.x = 24; else msgShift.y = 16;
                msgIn.start();
            }
            ParallelAnimation {
                id: msgIn
                NumberAnimation { target: msg; property: "opacity"; to: 1; duration: 110; easing.type: Easing.OutQuad }
                NumberAnimation { target: msgShift; property: "x"; to: 0; duration: 220; easing.type: Easing.OutQuint }
                NumberAnimation { target: msgShift; property: "y"; to: 0; duration: 220; easing.type: Easing.OutQuint }
            }

            // Wiadomość użytkownika
            Rectangle {
                id: bubble
                visible: msg.role === "user"
                anchors.right: parent.right
                width: Math.min(userText.implicitWidth + 28, 440)
                height: userText.implicitHeight + 22
                radius: 16
                color: ap.t.accent
                Rectangle { anchors.right: parent.right; anchors.bottom: parent.bottom; width: 16; height: 16; radius: 4; color: ap.t.accent }
                Text {
                    id: userText
                    x: 14; y: 11
                    width: Math.min(implicitWidth, 412)
                    text: msg.text; color: "white"; font.pixelSize: 14; wrapMode: Text.Wrap
                }
            }

            // Odpowiedź asystenta
            Column {
                id: answer
                visible: msg.role === "assistant"
                width: Math.min(parent.width, 540)
                spacing: 12
                Text { width: parent.width; text: msg.text; color: ap.t.text; font.pixelSize: 14; wrapMode: Text.Wrap; lineHeight: 1.25 }

                Rectangle {
                    visible: msg.kind === "change"
                    width: parent.width
                    height: visible ? card.implicitHeight + 28 : 0
                    radius: 14
                    color: ap.t.surface
                    border.width: 1; border.color: ap.t.line
                    Column {
                        id: card
                        x: 14; y: 14
                        width: parent.width - 28
                        spacing: 12
                        Text {
                            text: msg.status === "done" ? "ZROBIONE" : (msg.status === "cancelled" ? "ANULOWANE" : "ZMIANA W SYSTEMIE — POTRZEBNA ZGODA")
                            color: msg.status === "done" ? (ap.dark ? "#86D9AC" : "#166A3F") : ap.t.text2
                            font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4
                        }
                        Row {
                            spacing: 12
                            Column {
                                spacing: 2
                                Text { text: msg.title; color: ap.t.text2; font.pixelSize: 12 }
                                Text { text: msg.fromLabel; color: msg.status === "done" ? ap.t.text2 : ap.t.text; font.pixelSize: 14; font.weight: Font.DemiBold; font.strikeout: msg.status === "done" }
                            }
                            Icon { anchors.verticalCenter: parent.verticalCenter; d: I.arrow; color: ap.t.text2 }
                            Column {
                                spacing: 2
                                Text { text: "Nowe"; color: ap.t.text2; font.pixelSize: 12 }
                                Text { text: msg.toLabel; color: ap.t.accentText; font.pixelSize: 14; font.weight: Font.DemiBold }
                            }
                        }
                        Row {
                            visible: msg.status === "pending"
                            spacing: 8
                            Rectangle {
                                width: okRow.implicitWidth + 30; height: 38; radius: 10
                                color: okArea.containsMouse ? Qt.darker(ap.t.accent, 1.1) : ap.t.accent
                                scale: okArea.pressed ? 0.97 : 1
                                Row { id: okRow; anchors.centerIn: parent; spacing: 6
                                    Icon { anchors.verticalCenter: parent.verticalCenter; d: "M5 12l5 5 9-10"; size: 16; color: "white" }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Zatwierdź"; color: "white"; font.pixelSize: 13; font.weight: Font.DemiBold }
                                }
                                MouseArea { id: okArea; anchors.fill: parent; hoverEnabled: true; onClicked: ap.apply(msg.index, true) }
                            }
                            HoverButton {
                                t: ap.t
                                width: 90; height: 38
                                color: ap.t.fill
                                onClicked: ap.apply(msg.index, false)
                                Text { anchors.centerIn: parent; text: "Anuluj"; color: ap.t.text; font.pixelSize: 13; font.weight: Font.Medium }
                            }
                        }
                    }
                }
            }
        }
    }

    // Pole wpisywania
    Item {
        id: inputBar
        anchors.bottom: privacy.top
        width: parent.width; height: 70
        Rectangle { width: parent.width; height: 1; color: ap.t.line }
        Rectangle {
            x: 14; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 28 - 54; height: 46; radius: 12
            color: ap.t.surface
            border.width: input.activeFocus ? 1.5 : 1
            border.color: input.activeFocus ? ap.t.accent : ap.t.line
            TextInput {
                id: input
                x: 14; width: parent.width - 28
                anchors.verticalCenter: parent.verticalCenter
                color: ap.t.text; font.pixelSize: 14; clip: true
                selectionColor: ap.t.accentSoft
                Text { visible: !input.text; text: "Napisz, co ma się stać…"; color: ap.t.text2; font.pixelSize: 14 }
                Keys.onReturnPressed: ap.send(input.text)
                Keys.onEscapePressed: ap.closeRequested()
            }
        }
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 46; height: 46; radius: 12
            color: input.text ? (sendArea.containsMouse ? Qt.darker(ap.t.accent, 1.1) : ap.t.accent) : ap.t.fill
            Behavior on color { ColorAnimation { duration: 150 } }
            Icon { anchors.centerIn: parent; d: I.arrow; color: input.text ? "white" : ap.t.text2 }
            MouseArea { id: sendArea; anchors.fill: parent; hoverEnabled: true; onClicked: ap.send(input.text) }
        }
    }

    Rectangle {
        id: privacy
        anchors.bottom: parent.bottom
        width: parent.width; height: 40
        color: "transparent"
        Rectangle { width: parent.width; height: 1; color: ap.t.line }
        Row {
            x: 18; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Icon { anchors.verticalCenter: parent.verticalCenter; d: "M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"; size: 15; color: ap.t.text2 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Asystent widzi tylko to, co mu pokażesz. Zmiany w systemie zawsze wymagają Twojej zgody."; color: ap.t.text2; font.pixelSize: 12 }
        }
    }
}
