pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import Aster.Shell
import Aster.Ui

// „Horyzont”: górny pasek z trzech pływających wysp (warstwa „top”, z rezerwacją miejsca).
//  lewa    — znak Aster (otwiera Start) i nazwa aktywnego programu z tytułem okna, jak menu w macOS
//  środek  — dynamiczna wyspa: godzina; gdy gra muzyka — okładka i korektor; po najechaniu — data.
//            Powiadomienie (od każdego programu, także aplikacji webowych) rozlewa wyspę w kartę:
//            klik otwiera program, krzyżyk zamyka, kursor nad kartą wstrzymuje jej zniknięcie.
//            Asystent (Super+Spacja albo klik w wyspę): wyspa rozlewa się w pole pytania, krótka odpowiedź
//            zostaje w wyspie i znika jak powiadomienie; dłuższa rozmowa przechodzi do panelu z prawej.
//  prawa   — wyszukiwanie, stan sieci, dźwięku i baterii: otwiera centrum sterowania
Window {
    id: hz
    color: "transparent"
    title: "Horyzont"
    visible: false
    width: Screen.width
    height: 220
    readonly property int shotX: 0
    readonly property int shotY: 0

    readonly property int reserved: 46
    readonly property int barY: 7
    readonly property int barH: 32
    property bool controlOpen: false
    property bool primary: true                // powiadomienia tylko na głównym ekranie
    property bool assistantOpen: false         // panel asystenta otwarty (Shell)
    signal startRequested()
    signal controlRequested()
    signal assistantPanelRequested(bool show)

    Component.onCompleted: {
        Platform.makeLayer(hz, "top", 1 | 4 | 8, hz.reserved, "none", "aster-horizon");
        visible = true;
        hz.updateRegion();
    }

    property date now: new Date()
    Timer { interval: 1000; repeat: true; running: true; onTriggered: hz.now = new Date() }
    readonly property var loc: Qt.locale("pl_PL")

    // ——— Aktywny program ———
    TaskManager.TasksModel {
        id: tasks
        filterByVirtualDesktop: true
        filterByActivity: false
        filterByScreen: false
        groupMode: TaskManager.TasksModel.GroupDisabled
    }
    readonly property bool hasActive: !Platform.preview && tasks.activeTask.valid
    readonly property string appName: Platform.preview ? "Przeglądarka"
                                     : hasActive ? (tasks.data(tasks.activeTask, TaskManager.AbstractTasksModel.AppName) || "") : "Aster"
    readonly property string windowTitle: Platform.preview ? "Nowa karta"
                                         : hasActive ? (tasks.data(tasks.activeTask, Qt.DisplayRole) || "") : ""

    // ——— Kolejka powiadomień: na raz widać jedno, kolejne czekają ———
    property var queue: []
    property var current: null
    Connections {
        target: Platform
        enabled: hz.primary
        function onNotificationPosted(n) {
            if (Config.doNotDisturb) return;      // „Nie przeszkadzać”: bez karty, plakietki w doku zostają
            hz.queue = hz.queue.concat([n]);
            if (!hz.current) hz.next();
        }
        function onNotificationClosed(id) {
            hz.queue = hz.queue.filter(q => q.id !== id);
            if (hz.current && hz.current.id === id) hz.next();
        }
    }
    function next() {
        if (queue.length) {
            current = queue[0];
            queue = queue.slice(1);
            showTimer.restart();
        } else {
            current = null;
        }
    }
    Timer {
        id: showTimer
        interval: Platform.env("ASTER_SHOT_NOTIFY") !== "" ? 60000 : 5500
        onTriggered: if (islandHover.hovered) restart(); else hz.next()
    }

    // ——— Asystent w wyspie ———
    property bool asking: false
    readonly property bool answerShown: asking && Assistant.count > 0
    readonly property int askW: Math.max(360, Math.min(580, hz.width - 2 * Math.max(left.width, right.width) - 40))
    // Odpowiedź za długa na wyspę: lista kroków, kod, tabela albo po prostu dużo tekstu
    readonly property bool longAnswer: {
        const a = Assistant.lastAnswer;
        return a.length > 260 || a.indexOf("```") >= 0 || a.indexOf("|---") >= 0 || a.split("\n").length > 4;
    }
    function openAsk() {
        dismissTimer.stop();
        if (!asking) {
            Assistant.newConversation();
            Assistant.refreshStatus();
            askField.text = "";
            asking = true;
            Platform.setKeyboard(hz, "exclusive");
            hz.requestActivate();
        }
        askField.forceActiveFocus();
    }
    function closeAsk() {
        if (!asking) return;
        asking = false;
        dismissTimer.stop();
        askField.focus = false;
        Platform.setKeyboard(hz, "none");
    }
    function toggleAsk() {
        if (hz.assistantOpen) hz.assistantPanelRequested(false);
        else if (asking) closeAsk();
        else openAsk();
    }
    function submitAsk() {
        const t = askField.text.trim();
        if (t === "") return;
        askField.text = "";
        dismissTimer.stop();
        Assistant.ask(t, Assistant.exchanges > 0 ? "panel" : "wyspa");
    }
    // Do testów (ASTER_SHOT_ASK): wpisuje pytanie i wysyła je jak użytkownik
    function askNow(text) { openAsk(); askField.text = text; submitAsk(); }
    Connections {
        target: Assistant
        enabled: hz.asking
        function onChanged() {
            if (Assistant.exchanges > 1 || hz.longAnswer) {
                hz.closeAsk();
                hz.assistantPanelRequested(true);
            }
        }
        function onAnswered() { dismissTimer.restart(); }
    }
    // Krótka odpowiedź znika po chwili (kursor nad wyspą albo pisanie wstrzymują)
    Timer {
        id: dismissTimer
        interval: Platform.env("ASTER_SHOT_ASK") !== "" ? 60000 : 12000
        onTriggered: if (islandHover.hovered || askField.text !== "") restart(); else hz.closeAsk()
    }

    // ——— Lewa wyspa ———
    Island {
        id: left
        x: 10; y: hz.barY
        width: leftRow.width + 12
        height: hz.barH
        radius: height / 2
        onWidthChanged: hz.updateRegion()
        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Row {
            id: leftRow
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Rectangle {
                id: mark
                width: 26; height: 26; radius: 13
                anchors.verticalCenter: parent.verticalCenter
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.35) }
                    GradientStop { position: 1; color: Theme.accent }
                }
                scale: markArea.pressed ? 0.88 : (markArea.containsMouse ? 1.06 : 1)
                rotation: markArea.containsMouse ? 30 : 0
                Behavior on scale { SpringAnimation { spring: 5; damping: 0.3 } }
                Behavior on rotation { NumberAnimation { duration: 380; easing.type: Easing.OutBack } }
                Icon { anchors.centerIn: parent; d: Icons.aster; size: 15; stroke: 2.2; color: "white" }
                MouseArea { id: markArea; anchors.fill: parent; hoverEnabled: true; onClicked: hz.startRequested() }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: hz.appName
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold; font.letterSpacing: -0.1
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: text !== "" && text !== hz.appName
                width: Math.min(implicitWidth, 320)
                elide: Text.ElideRight
                text: hz.windowTitle
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 13
                rightPadding: 4
            }
        }
    }

    // ——— Dynamiczna wyspa ———
    readonly property bool playing: ControlCenter.playerAvailable && ControlCenter.playing
    readonly property bool noting: current !== null
    readonly property bool peek: islandHover.hovered && !noting
    Island {
        id: island
        solid: true
        readonly property var n: hz.current
        readonly property real idleW: idleRow.implicitWidth + (hz.playing ? 92 : 36)
        width: hz.asking ? hz.askW : hz.noting ? 440 : idleW
        height: hz.asking ? askCol.implicitHeight : hz.noting ? 92 : hz.barH
        radius: hz.asking ? 24 : Math.min(height / 2, 28)
        x: Math.round((hz.width - width) / 2)
        y: hz.barY
        onWidthChanged: hz.updateRegion()
        onHeightChanged: hz.updateRegion()
        // Sprężyna — wyspa „rozlewa się” jak kropla, a nie przesuwa
        Behavior on width { SpringAnimation { spring: 3.4; damping: 0.3; epsilon: 0.3 } }
        Behavior on height { SpringAnimation { spring: 3.4; damping: 0.32; epsilon: 0.3 } }

        HoverHandler { id: islandHover }
        TapHandler {
            onTapped: {
                if (hz.asking) return;
                if (island.n) { Platform.activateNotification(island.n.id); hz.next(); }
                else hz.toggleAsk();
            }
        }

        // Spoczynek: (okładka) godzina / data (korektor)
        Item {
            anchors.fill: parent
            opacity: hz.noting || hz.asking ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: hz.noting || hz.asking ? 90 : 260 } }

            Rectangle {
                id: art
                x: 6; anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22; radius: 7
                opacity: hz.playing ? 1 : 0
                scale: hz.playing ? 1 : 0.5
                Behavior on opacity { NumberAnimation { duration: 200 } }
                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                gradient: Gradient {
                    GradientStop { position: 0; color: "#FF8A65" }
                    GradientStop { position: 1; color: "#C2185B" }
                }
                Image {
                    anchors.fill: parent
                    source: ControlCenter.artUrl
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                    sourceSize: Qt.size(64, 64)
                }
                Icon { anchors.centerIn: parent; visible: ControlCenter.artUrl === ""; d: Icons.music; size: 12; stroke: 2; color: "white" }
            }
            Row {
                id: idleRow
                anchors.centerIn: parent
                spacing: 8
                Text {
                    id: dateText
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const s = hz.now.toLocaleDateString(hz.loc, "dddd, d MMMM");
                        return s.charAt(0).toUpperCase() + s.slice(1);
                    }
                    visible: hz.peek
                    color: Qt.rgba(1, 1, 1, 0.62)
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: hz.now.toLocaleTimeString(hz.loc, "HH:mm")
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
            }
            // Korektor: trzy kreski tańczą, gdy gra muzyka
            Row {
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2.5
                opacity: hz.playing ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
                Repeater {
                    model: [0.55, 1.0, 0.7, 0.85]
                    delegate: Rectangle {
                        id: bar
                        required property real modelData
                        required property int index
                        width: 2.5; radius: 1.25
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.lighter(Theme.accent, 1.5)
                        height: 4 + 10 * bar.modelData * bar.level
                        property real level: 0.5
                        SequentialAnimation on level {
                            running: hz.playing
                            loops: Animation.Infinite
                            NumberAnimation { to: 1; duration: 260 + bar.index * 70; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0.2; duration: 300 + bar.index * 50; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }
        }

        // Karta powiadomienia
        Item {
            anchors.fill: parent
            opacity: hz.noting && !hz.asking && island.height > 70 ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 180 } }

            Item {
                id: iconBox
                x: 18; anchors.verticalCenter: parent.verticalCenter
                width: 46; height: 46
                Rectangle {
                    anchors.fill: parent
                    radius: 14
                    visible: !!island.n && !island.n.image
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.4) }
                        GradientStop { position: 1; color: Theme.accent }
                    }
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: 26; height: 26
                        source: island.n ? (island.n.icon || "preferences-desktop-notification") : ""
                        color: "white"
                        isMask: true
                    }
                }
                Image {
                    anchors.fill: parent
                    visible: !!island.n && !!island.n.image
                    source: island.n && island.n.image ? island.n.image : ""
                    sourceSize: Qt.size(96, 96)
                    fillMode: Image.PreserveAspectFit
                    smooth: true; mipmap: true
                }
            }
            Column {
                anchors.left: iconBox.right; anchors.leftMargin: 14
                anchors.right: parent.right; anchors.rightMargin: 44
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Row {
                    spacing: 6
                    Text {
                        text: island.n ? island.n.appName : ""
                        visible: text !== ""
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.family: Theme.font; font.pixelSize: 11; font.letterSpacing: 0.1; font.weight: Font.Medium
                    }
                    Text {
                        text: "· teraz"
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font.family: Theme.font; font.pixelSize: 11; font.letterSpacing: 0.1
                    }
                }
                Text {
                    width: parent.width
                    text: island.n ? island.n.summary : ""
                    elide: Text.ElideRight
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: island.n ? island.n.body : ""
                    visible: text !== ""
                    textFormat: Text.StyledText
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    color: Qt.rgba(1, 1, 1, 0.74)
                    font.family: Theme.font; font.pixelSize: 13
                }
            }
            Rectangle {
                anchors.right: parent.right; anchors.rightMargin: 14
                y: 14
                width: 24; height: 24; radius: 12
                opacity: islandHover.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                color: closeArea.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.1)
                Icon { anchors.centerIn: parent; d: Icons.close; size: 10; stroke: 2.2; color: Qt.rgba(1, 1, 1, 0.8) }
                MouseArea {
                    id: closeArea; anchors.fill: parent; hoverEnabled: true
                    onClicked: { if (island.n) Platform.dismissNotification(island.n.id); hz.next(); }
                }
            }
        }
    }

    // ——— Pole pytania i krótka odpowiedź (w środku dynamicznej wyspy) ———
    Item {
        parent: island
        anchors.fill: parent
        opacity: hz.asking && island.width > hz.askW * 0.8 ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: hz.asking ? 200 : 80 } }

        Column {
            id: askCol
            x: 10
            width: parent.width - 20
            bottomPadding: hz.answerShown ? 10 : 0

            Item {
                width: parent.width
                height: 46
                // Iskra asystenta; kręci się, gdy model pisze
                Rectangle {
                    id: spark
                    width: 30; height: 30; radius: 15
                    anchors.verticalCenter: parent.verticalCenter
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(Theme.accent, 1.45) }
                        GradientStop { position: 1; color: "#7C3AED" }
                    }
                    Icon {
                        anchors.centerIn: parent; d: Icons.sparkle; size: 16; stroke: 2; color: "white"
                        RotationAnimation on rotation { running: Assistant.busy; loops: Animation.Infinite; from: 0; to: 360; duration: 1600 }
                    }
                }
                TextInput {
                    id: askField
                    anchors.left: spark.right; anchors.leftMargin: 12
                    anchors.right: keyHint.left; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: "white"
                    selectionColor: Qt.rgba(1, 1, 1, 0.25)
                    font.family: Theme.font; font.pixelSize: 15
                    clip: true
                    Keys.onReturnPressed: hz.submitAsk()
                    Keys.onEnterPressed: hz.submitAsk()
                    Keys.onEscapePressed: { if (Assistant.busy) Assistant.cancel(); hz.closeAsk(); }
                    onTextChanged: if (text !== "") dismissTimer.stop()
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !askField.text
                        text: hz.answerShown ? "Dopytaj…" : "Zapytaj o cokolwiek…"
                        color: Qt.rgba(1, 1, 1, 0.38)
                        font: askField.font
                    }
                }
                // Klawisz podpowiedzi: ↵ gdy jest co wysłać, Esc gdy pusto
                Rectangle {
                    id: keyHint
                    anchors.right: parent.right; anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: keyText.implicitWidth + 14; height: 22; radius: 7
                    color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
                    Text {
                        id: keyText
                        anchors.centerIn: parent
                        text: askField.text !== "" ? "↵" : "Esc"
                        color: Qt.rgba(1, 1, 1, 0.5)
                        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium
                    }
                }
            }

            // Odpowiedź
            Item {
                visible: hz.answerShown
                width: parent.width
                height: visible ? answerCol.implicitHeight + 10 : 0
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
                Column {
                    id: answerCol
                    x: 4; y: 10
                    width: parent.width - 8
                    spacing: 8
                    // Kropki, zanim przyjdzie pierwszy kawałek odpowiedzi
                    Row {
                        visible: Assistant.busy && Assistant.lastAnswer === ""
                        spacing: 5
                        height: 18
                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                id: dot
                                required property int index
                                width: 6; height: 6; radius: 3
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.rgba(1, 1, 1, 0.7)
                                SequentialAnimation on opacity {
                                    running: Assistant.busy; loops: Animation.Infinite
                                    PauseAnimation { duration: dot.index * 160 }
                                    NumberAnimation { from: 0.25; to: 1; duration: 320 }
                                    NumberAnimation { from: 1; to: 0.25; duration: 320 }
                                    PauseAnimation { duration: (2 - dot.index) * 160 }
                                }
                            }
                        }
                    }
                    Text {
                        visible: text !== ""
                        width: parent.width
                        text: Assistant.lastError ? Assistant.lastAnswer : Assistant.lastAnswer.replace(/\*\*/g, "")
                        wrapMode: Text.Wrap
                        maximumLineCount: 5
                        elide: Text.ElideRight
                        color: Assistant.lastError ? "#FF9C94" : Qt.rgba(1, 1, 1, 0.9)
                        font.family: Theme.font; font.pixelSize: 14
                        lineHeight: 1.12
                    }
                    // Kto odpowiedział + podpowiedź
                    Row {
                        visible: !Assistant.busy
                        spacing: 10
                        AssistantBadge { visible: !Assistant.lastError; text: Assistant.lastBadge }
                        Rectangle {
                            visible: Assistant.lastError
                            width: setText.implicitWidth + 18; height: 22; radius: 11
                            color: setArea.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.1)
                            Text { id: setText; anchors.centerIn: parent; text: "Ustawienia asystenta"; color: "white"; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
                            MouseArea { id: setArea; anchors.fill: parent; hoverEnabled: true; onClicked: { hz.closeAsk(); Assistant.openSettings(); } }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "↵ dopytaj · Esc zamknij"
                            color: Qt.rgba(1, 1, 1, 0.32)
                            font.family: Theme.font; font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }

    // ——— Prawa wyspa ———
    Island {
        id: right
        anchors.right: parent.right; anchors.rightMargin: 10
        y: hz.barY
        width: rightRow.width + 8
        height: hz.barH
        radius: height / 2
        onWidthChanged: hz.updateRegion()

        Row {
            id: rightRow
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            BarButton {
                onClicked: hz.startRequested()
                Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 15; stroke: 2; color: Theme.text }
            }
            BarButton {
                id: status
                highlighted: hz.controlOpen
                onClicked: hz.controlRequested()
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Config.doNotDisturb
                    d: Icons.moon; size: 15; stroke: 2
                    color: status.ink
                }
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    d: !ControlCenter.wifiAvailable && ControlCenter.wired ? Icons.ethernet : Icons.wifi
                    size: 16; stroke: 2
                    color: status.ink
                    opacity: ControlCenter.networkName !== "" ? 1 : 0.4
                }
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: ControlCenter.audioAvailable
                    d: ControlCenter.muted || ControlCenter.volume === 0 ? Icons.volumeOff : ControlCenter.volume < 0.5 ? Icons.volumeLow : Icons.volume
                    size: 16; stroke: 2
                    color: status.ink
                }
                // Bateria rysowana: wypełnienie odpowiada poziomowi naładowania
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: ControlCenter.batteryAvailable
                    spacing: 5
                    Text {
                        visible: Config.batteryPercent
                        anchors.verticalCenter: parent.verticalCenter
                        text: ControlCenter.battery + "%"
                        color: status.ink
                        font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                    }
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 25; height: 12
                        Rectangle {
                            width: 22; height: 12; radius: 3.5
                            color: "transparent"
                            border.width: 1.2
                            border.color: Qt.rgba(status.ink.r, status.ink.g, status.ink.b, 0.45)
                            Rectangle {
                                x: 2; y: 2
                                height: parent.height - 4; radius: 2
                                width: Math.max(2, (parent.width - 4) * ControlCenter.battery / 100)
                                color: ControlCenter.charging ? "#34C759" : ControlCenter.battery <= 20 ? "#FF453A" : status.ink
                            }
                        }
                        Rectangle { x: 23; anchors.verticalCenter: parent.verticalCenter; width: 1.6; height: 4; radius: 0.8; color: Qt.rgba(status.ink.r, status.ink.g, status.ink.b, 0.45) }
                    }
                }
            }
        }
    }

    // Przycisk na pasku: pigułka, która podświetla się pod kursorem
    component BarButton: Rectangle {
        id: bb
        default property alias content: inner.data
        property bool highlighted: false
        readonly property color ink: highlighted ? "white" : Theme.text
        signal clicked()
        width: inner.implicitWidth + 20
        height: 26
        radius: 13
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: highlighted ? Theme.accent : bbArea.containsMouse ? Theme.hover : "transparent"
        Behavior on color { ColorAnimation { duration: 140 } }
        scale: bbArea.pressed ? 0.93 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
        Row {
            id: inner
            anchors.centerIn: parent
            spacing: 10
        }
        MouseArea { id: bbArea; anchors.fill: parent; hoverEnabled: true; onClicked: bb.clicked() }
    }

    // Rozmycie i kliknięcia tylko tam, gdzie są wyspy (odświeżane w rytmie animacji)
    function updateRegion() { if (!regionTimer.running) regionTimer.start(); }
    Timer {
        id: regionTimer
        interval: 16
        onTriggered: {
            const r = [left, island, right].map(i => ({ x: i.x, y: i.y, w: i.width, h: i.height, r: i.radius }));
            Platform.setBlur(hz, r);
            Platform.setInputRegion(hz, r);
        }
    }
}
