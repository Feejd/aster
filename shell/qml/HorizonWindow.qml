pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import Aster.Shell
import Aster.Ui

// „Horyzont”: górny pasek, jedna pełna belka (warstwa „top”, z rezerwacją miejsca).
//  lewa    — znak Aster (otwiera Start), nazwa aktywnego programu i jego menu (MenuWindow)
//  środek  — zegar na belce; gdy gra muzyka — okładka i korektor; po najechaniu — data.
//            Powiadomienie (od każdego programu, także aplikacji webowych) wysuwa się spod paska jako karta:
//            klik otwiera program, krzyżyk zamyka, kursor nad kartą wstrzymuje jej zniknięcie.
//            Aster Intelligence (Super+Spacja albo klik w wyspę): wyspa rozlewa się w pole pytania otoczone
//            tęczową poświatą; krótka odpowiedź zostaje w wyspie i znika jak powiadomienie, dłuższa rozmowa
//            przechodzi do panelu z prawej. Zaznaczony tekst (albo tekst ze schowka) — narzędzia do pisania.
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

    readonly property int reserved: 32
    readonly property int barY: 0
    readonly property int barH: 32
    property bool controlOpen: false
    property bool primary: true                // powiadomienia tylko na głównym ekranie
    property bool assistantOpen: false         // panel asystenta otwarty (Shell)
    signal startRequested()
    signal controlRequested()
    signal assistantPanelRequested(bool show)
    signal chatsRequested()                    // przycisk Aster Intelligence na pasku: panel z rozmowami
    signal askOpened()
    signal menuRequested(int index)

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

    // ——— Menu programu ———
    readonly property string activeAppId: {
        if (!hasActive) return "";
        const url = String(tasks.data(tasks.activeTask, TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon) || "");
        return url.replace(/^.*[\/:]/, "").replace(/\.desktop$/, "");
    }
    // Otwarte menu samo przejmuje fokus, więc pamiętamy program, którego dotyczy
    property bool menuOpen: false
    property string heldAppName: ""
    Connections {
        target: hz
        function onAppNameChanged() { if (hz.hasActive && !hz.menuOpen) hz.heldAppName = hz.appName; }
    }
    Binding { target: GlobalMenu; property: "appId"; value: hz.activeAppId; when: hz.primary && hz.hasActive && !hz.menuOpen }
    function windowAction(a) {
        if (!hz.hasActive) return;
        if (a === "min") tasks.requestToggleMinimized(tasks.activeTask);
        else if (a === "max") tasks.requestToggleMaximized(tasks.activeTask);
        else if (a === "close") tasks.requestClose(tasks.activeTask);
    }
    // Każdy program ma swoje menu i wspólne „Okno”; programy bez menu dostają samo „Okno”
    readonly property var menuList: {
        if (!hasActive) return [];
        return GlobalMenu.menus.concat([{ title: "Okno", items: [
            { text: "Schowaj do doku", action: "min", key: "Super+Dół" },
            { text: "Rozwiń", action: "max", key: "Super+Góra" },
            { separator: true },
            { text: "Zamknij", action: "close", key: "Alt+F4" }
        ] }]);
    }
    function menuEntries() {
        const out = [];
        const x = menuRow.mapToItem(hz.contentItem, 0, 0).x;
        for (let i = 0; i < menuRepeater.count; ++i) {
            const it = menuRepeater.itemAt(i);
            if (it) out.push({ title: it.modelData.title, x: x + it.x, width: it.width, items: it.modelData.items });
        }
        return out;
    }

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

    // ——— Aster Intelligence w wyspie ———
    property bool asking: false
    property bool useSelection: true           // zaznaczony tekst idzie z pytaniem (krzyżyk go odpina)
    readonly property bool hasSelection: useSelection && Assistant.selection !== ""
    readonly property bool toolsShown: asking && !answerShown && hasSelection
    // Narzędzia do pisania (jak w Apple Intelligence): działają na zaznaczonym tekście
    readonly property var tools: [
        { label: "Popraw błędy", icon: Icons.check, prompt: "Popraw błędy w tym tekście: pisownię, interpunkcję i gramatykę." },
        { label: "Przeredaguj", icon: Icons.pencil, prompt: "Przeredaguj ten tekst, żeby czytał się płynniej." },
        { label: "Przyjaźniej", icon: Icons.thumb, prompt: "Przepisz ten tekst w cieplejszym, przyjaznym tonie." },
        { label: "Profesjonalnie", icon: Icons.doc, prompt: "Przepisz ten tekst w uprzejmym, profesjonalnym tonie." },
        { label: "Zwięźlej", icon: Icons.minus, prompt: "Skróć ten tekst, zachowując cały sens." },
        { label: "Streść", icon: Icons.list, prompt: "Streść ten tekst w dwóch–trzech zdaniach." },
        { label: "Najważniejsze punkty", icon: Icons.sort, prompt: "Wypisz najważniejsze punkty tego tekstu jako krótką listę." }
    ]
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
            useSelection = true;
            asking = true;
            Platform.setKeyboard(hz, "exclusive");
            hz.requestActivate();
            hz.askOpened();
            selectionTimer.restart();
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
        const first = Assistant.exchanges === 0;
        Assistant.ask(t, first ? "wyspa" : "panel", first && hz.hasSelection ? Assistant.selection : "");
    }
    function runTool(tool) {
        dismissTimer.stop();
        askField.text = "";
        Assistant.ask(tool.prompt, "pisanie", Assistant.selection);
    }
    // Wayland podaje zaznaczenie dopiero oknu z klawiaturą — chwilę po otwarciu pola
    Timer { id: selectionTimer; interval: 140; onTriggered: Assistant.refreshSelection() }
    // Do testów (ASTER_SHOT_ASK): wpisuje pytanie i wysyła je jak użytkownik
    function askNow(text) { openAsk(); askField.text = text; submitAsk(); }
    Connections {
        target: Assistant
        enabled: hz.asking
        function onChanged() {
            if (Assistant.exchanges > 1 || hz.longAnswer || Assistant.acting) {
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

    // Górny pasek stanu: przezroczysty, leży wprost na tapecie (jak na telefonie)
    Rectangle {
        width: parent.width; height: hz.reserved
        color: Theme.bar
    }

    // Żywa linia na dolnej krawędzi paska: jedyny ruch w spoczynku. Powiadomienie odlicza nią swój czas,
    // a gdy Aster Intelligence pracuje, przez pasek biegnie krótki odcinek
    Rectangle {
        id: liveLine
        property real sweep: 0
        readonly property bool thinking: Assistant.busy && hz.primary
        y: hz.reserved - 2
        height: 2
        x: thinking ? (hz.width + width) * sweep - width : 0
        width: thinking ? hz.width * 0.18 : hz.noting ? hz.width * lineProgress : 0
        property real lineProgress: 0
        color: Theme.accent
        visible: thinking || hz.noting
        NumberAnimation on sweep { running: liveLine.thinking; loops: Animation.Infinite; from: 0; to: 1; duration: 1500; easing.type: Easing.InOutCubic }
        Connections {
            target: hz
            function onCurrentChanged() {
                lineAnim.stop();
                if (hz.current) { liveLine.lineProgress = 1; lineAnim.duration = showTimer.interval; lineAnim.start(); }
            }
        }
        NumberAnimation { id: lineAnim; target: liveLine; property: "lineProgress"; to: 0 }
    }

    // ——— Lewa strona paska ———
    Island {
        id: left
        flat: true
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
                width: 24; height: 24; radius: 6
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.accent
                scale: markArea.pressed ? 0.88 : (markArea.containsMouse ? 1.06 : 1)
                rotation: markArea.containsMouse ? 30 : 0
                Behavior on scale { SpringAnimation { spring: 5; damping: 0.3 } }
                Behavior on rotation { NumberAnimation { duration: 380; easing.type: Easing.OutBack } }
                Icon { anchors.centerIn: parent; d: Icons.aster; size: 15; stroke: 2.2; color: "white" }
                MouseArea { id: markArea; anchors.fill: parent; hoverEnabled: true; onClicked: hz.startRequested() }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: hz.menuOpen ? hz.heldAppName : hz.appName
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold; font.letterSpacing: -0.1
            }
            Row {
                id: menuRow
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 6
                Repeater {
                    id: menuRepeater
                    model: hz.primary ? hz.menuList : []
                    delegate: Rectangle {
                        id: menuTitle
                        required property var modelData
                        required property int index
                        width: menuLabel.implicitWidth + 18; height: 24; radius: 6
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        color: menuArea.containsMouse ? Theme.hover : "transparent"
                        Text {
                            id: menuLabel
                            anchors.centerIn: parent
                            text: menuTitle.modelData.title
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 13
                        }
                        MouseArea {
                            id: menuArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: hz.menuRequested(menuTitle.index)
                        }
                    }
                }
            }
        }
    }

    // ——— Dynamiczna wyspa ———
    // Jedyna poświata Aster Intelligence: wokół wyspy, gdy pytasz (nieruchoma; powoli krąży, gdy model myśli)
    IntelligenceGlow {
        id: islandGlow
        x: island.x; y: island.y
        width: island.width; height: island.height
        radius: island.radius
        thickness: 2
        haloWidth: 8
        haloBlur: 28
        haloStrength: 0.7
        speed: Assistant.busy ? 90 : 0
        intensity: hz.asking ? 1 : 0
        Behavior on intensity { NumberAnimation { duration: hz.asking ? 450 : 260; easing.type: Easing.OutCubic } }
    }
    readonly property bool playing: ControlCenter.playerAvailable && ControlCenter.playing
    readonly property bool noting: current !== null
    readonly property bool peek: islandHover.hovered && !noting
    Island {
        id: island
        solid: true
        // Spoczynek: sam zegar na belce. Powiadomienie i pytanie wysuwają się spod paska jako karta
        flat: !hz.asking && !hz.noting
        // Przy pytaniu cień ustępuje poświacie
        shadowStrength: hz.asking ? 0.35 : 1
        Behavior on shadowStrength { NumberAnimation { duration: 300 } }
        readonly property var n: hz.current
        readonly property real idleW: idleRow.implicitWidth + (hz.playing ? 92 : 36)
        width: hz.asking ? hz.askW : hz.noting ? 440 : idleW
        height: hz.asking ? askCol.implicitHeight : hz.noting ? 92 : 26
        radius: 14
        x: Math.round((hz.width - width) / 2)
        y: hz.asking || hz.noting ? hz.reserved + 8 : 3
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        onWidthChanged: hz.updateRegion()
        onHeightChanged: hz.updateRegion()
        onYChanged: hz.updateRegion()
        // Sprężyna — wyspa „rozlewa się” jak kropla, a nie przesuwa
        Behavior on width { SpringAnimation { spring: 3.6; damping: 0.26; epsilon: 0.3 } }
        Behavior on height { SpringAnimation { spring: 3.6; damping: 0.3; epsilon: 0.3 } }
        Behavior on radius { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

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
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: hz.now.toLocaleTimeString(hz.loc, "HH:mm")
                    color: Theme.text
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
                // Kula Aster Intelligence: kolory krążą szybciej, gdy model myśli
                IntelligenceOrb {
                    id: spark
                    size: 30
                    busy: Assistant.busy
                    anchors.verticalCenter: parent.verticalCenter
                    scale: hz.asking ? 1 : 0.4
                    Behavior on scale { SpringAnimation { spring: 4; damping: 0.28 } }
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
                        text: hz.answerShown ? "Dopytaj…"
                            : hz.hasSelection ? "Opisz zmianę albo zapytaj o ten tekst…" : "Zapytaj Aster Intelligence…"
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

            // Narzędzia do pisania: zaznaczony tekst i co z nim zrobić
            Item {
                id: toolsBox
                visible: hz.toolsShown
                width: parent.width
                height: visible ? toolsCol.implicitHeight + 14 : 0
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 220 } }
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }
                Column {
                    id: toolsCol
                    x: 4; y: 10
                    width: parent.width - 8
                    spacing: 10
                    // Podgląd tekstu, na którym narzędzia będą działać
                    Rectangle {
                        width: parent.width
                        height: 34
                        radius: 10
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.07)
                        Icon {
                            id: selIcon
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            d: Assistant.selectionSource === "schowek" ? Icons.paste : Icons.cursor
                            size: 13; stroke: 2; color: Qt.rgba(1, 1, 1, 0.5)
                        }
                        Text {
                            anchors.left: selIcon.right; anchors.leftMargin: 8
                            anchors.right: unpin.left; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: (Assistant.selectionSource === "schowek" ? "Ze schowka: " : "Zaznaczone: ")
                                  + "„" + Assistant.selection.replace(/\s+/g, " ") + "”"
                            elide: Text.ElideRight
                            color: Qt.rgba(1, 1, 1, 0.6)
                            font.family: Theme.font; font.pixelSize: 12
                        }
                        Rectangle {
                            id: unpin
                            anchors.right: parent.right; anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22; height: 22; radius: 11
                            color: unpinArea.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
                            Icon { anchors.centerIn: parent; d: Icons.close; size: 9; stroke: 2.2; color: Qt.rgba(1, 1, 1, 0.6) }
                            MouseArea { id: unpinArea; anchors.fill: parent; hoverEnabled: true; onClicked: hz.useSelection = false }
                        }
                    }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: hz.tools
                            delegate: Rectangle {
                                id: chip
                                required property var modelData
                                required property int index
                                width: chipRow.implicitWidth + 22
                                height: 28
                                radius: 14
                                color: chipArea.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                                border.width: 1
                                border.color: chipArea.containsMouse ? Qt.rgba(0.78, 0.53, 1, 0.6) : Qt.rgba(1, 1, 1, 0.08)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }
                                scale: chipArea.pressed ? 0.94 : 1
                                Behavior on scale { SpringAnimation { spring: 5; damping: 0.35 } }
                                // Wejście kaskadą: każdy kolejny przycisk chwilę później
                                opacity: 0
                                property real lift: 2
                                transform: Translate { y: chip.lift }
                                Component.onCompleted: appear.start()
                                ParallelAnimation {
                                    id: appear
                                    SequentialAnimation {
                                        PauseAnimation { duration: 40 + chip.index * 35 }
                                        ParallelAnimation {
                                            NumberAnimation { target: chip; property: "opacity"; to: 1; duration: 220 }
                                            NumberAnimation { target: chip; property: "lift"; to: 0; duration: 180; easing.type: Easing.OutCubic }
                                        }
                                    }
                                }
                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Icon { anchors.verticalCenter: parent.verticalCenter; d: chip.modelData.icon; size: 12; stroke: 2; color: Qt.rgba(1, 1, 1, 0.75) }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: chip.modelData.label
                                        color: "white"
                                        font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                                    }
                                }
                                MouseArea { id: chipArea; anchors.fill: parent; hoverEnabled: true; onClicked: hz.runTool(chip.modelData) }
                            }
                        }
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
                    // Zanim przyjdzie pierwszy kawałek odpowiedzi: połysk przebiega po napisie
                    ShimmerText {
                        visible: Assistant.busy && Assistant.lastAnswer === ""
                        text: Assistant.status.local ? "Myślę na tym komputerze…" : "Myślę…"
                        pixelSize: 14
                    }
                    Text {
                        id: answerText
                        visible: text !== ""
                        width: parent.width
                        // Odpowiedź wyłania się: przenika i lekko unosi
                        opacity: 0
                        property real lift: 3
                        transform: Translate { y: answerText.lift }
                        onVisibleChanged: if (visible) reveal.restart(); else { opacity = 0; lift = 3; }
                        ParallelAnimation {
                            id: reveal
                            NumberAnimation { target: answerText; property: "opacity"; to: 1; duration: 320; easing.type: Easing.OutCubic }
                            NumberAnimation { target: answerText; property: "lift"; to: 0; duration: 200; easing.type: Easing.OutCubic }
                        }
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
                            id: copyChip
                            visible: !Assistant.lastError && Assistant.lastAnswer !== ""
                            property bool done: false
                            width: copyRow.implicitWidth + 16; height: 22; radius: 11
                            color: copyArea.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.1)
                            Row {
                                id: copyRow
                                anchors.centerIn: parent
                                spacing: 5
                                Icon { anchors.verticalCenter: parent.verticalCenter; d: copyChip.done ? Icons.check : Icons.copy; size: 11; stroke: 2; color: "white" }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: copyChip.done ? "Skopiowano" : "Kopiuj"; color: "white"; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
                            }
                            Timer { id: copiedTimer; interval: 1600; onTriggered: copyChip.done = false }
                            MouseArea {
                                id: copyArea; anchors.fill: parent; hoverEnabled: true
                                onClicked: { Assistant.copy(Assistant.lastAnswer); copyChip.done = true; copiedTimer.restart(); }
                            }
                        }
                        Rectangle {
                            visible: Assistant.lastError
                            width: setText.implicitWidth + 18; height: 22; radius: 11
                            color: setArea.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.1)
                            Text { id: setText; anchors.centerIn: parent; text: "Ustawienia Aster Intelligence"; color: "white"; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
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
        flat: true
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
            // Aster Intelligence: otwiera panel z rozmowami (pusty — od razu z listą poprzednich)
            BarButton {
                id: aiButton
                highlighted: hz.assistantOpen
                onClicked: hz.chatsRequested()
                IntelligenceOrb {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 17
                    busy: Assistant.busy
                }
            }
        }
    }

    // ——— Kropla rozmowy ———
    // Bieżąca rozmowa z Aster Intelligence chowa się w małą kroplę tuż pod prawą wyspą (jak druga wyspa).
    // Klik rozlewa ją z powrotem w panel; gdy rozmowy nie ma (nowa / usunięta), kropli też nie ma.
    // Spokojna: pojawia się i znika łagodnie; gdy agent myśli — kręci się kula i „Myślę…”.
    readonly property bool dropShown: hz.primary && Assistant.count > 0 && !hz.assistantOpen && !hz.asking
    onDropShownChanged: hz.updateRegion()


    Island {
        id: drop
        readonly property bool thinking: Assistant.busy && !Assistant.waiting
        anchors.right: right.right
        y: hz.barY + hz.barH + 7
        height: 30
        width: Math.min(dropRow.implicitWidth + 18, 320)
        radius: height / 2
        visible: opacity > 0.01
        opacity: hz.dropShown ? 1 : 0
        shadowStrength: 0.8
        property real s: hz.dropShown ? 1 : 0.8
        transform: Scale { origin.x: drop.width - 34; origin.y: 0; xScale: drop.s; yScale: drop.s }
        Behavior on opacity { NumberAnimation { duration: hz.dropShown ? 160 : 120 } }
        Behavior on s { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        onWidthChanged: hz.updateRegion()
        onVisibleChanged: hz.updateRegion()



        Row {
            id: dropRow
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            IntelligenceOrb {
                anchors.verticalCenter: parent.verticalCenter
                size: 19
                busy: drop.thinking
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: !drop.thinking
                width: Math.min(implicitWidth, 250)
                elide: Text.ElideRight
                text: Assistant.waiting ? "Czeka na twoją zgodę" : Assistant.title
                color: Assistant.waiting ? (Theme.dark ? "#7DD3FC" : "#2563EB") : Theme.text
                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
            }
            ShimmerText {
                anchors.verticalCenter: parent.verticalCenter
                visible: drop.thinking
                text: Assistant.acting ? "Działam…" : "Myślę…"
                pixelSize: 13
                base: Theme.dark ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(0, 0, 0, 0.45)
            }
            Item { width: 2; height: 1 }
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hz.assistantPanelRequested(true)
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
            const items = [left, island, right];
            if (drop.visible) items.push(drop);
            const r = items.map(i => ({ x: i.x, y: i.y, w: i.width, h: i.height, r: i.radius }));
            Platform.setBlur(hz, r);
            Platform.setInputRegion(hz, r);
        }
    }
}
