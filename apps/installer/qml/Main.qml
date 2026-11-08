pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Aster.Ui
import Aster.Installer

// Instalator Aster: na cały ekran, od razu po starcie z pendrive’a (bez trybu „wypróbuj”). Kroki po lewej:
// język, klawiatura, internet, strefa czasowa, dysk, konto, wygląd, podsumowanie — potem instalacja z postępem
// i ponowne uruchomienie prosto do gotowego pulpitu.
Window {
    id: win
    width: 1280
    height: 800
    visible: true
    visibility: Installer.preview ? Window.Windowed : Window.FullScreen
    color: "black"
    title: "Instalacja Aster"

    readonly property bool shaders: GraphicsInfo.api !== GraphicsInfo.Software && GraphicsInfo.api !== GraphicsInfo.Unknown

    // ——— Wybory ———
    QtObject {
        id: s
        property string locale: "pl_PL.UTF-8"
        property string keyboard: "pl"
        property string timezone: "Europe/Warsaw"
        property string disk
        property bool eraseOk: false
        property string fullName
        property string username
        property bool usernameEdited: false
        property string password
        property string password2
        property string hostname
        property bool hostnameEdited: false
        property bool autologin: false
        property bool dark: false
        property string accent: "#3456E8"
        property string wallpaper: "aura"
        property bool autoUpdates: true

        onFullNameChanged: if (!usernameEdited) username = Installer.usernameFor(fullName)
        onUsernameChanged: if (!hostnameEdited) hostname = Installer.hostnameFor(username)
    }
    function find(list, key, value) { return list.find(x => x[key] === value) || null; }
    readonly property var kb: find(Installer.keyboards, "id", s.keyboard)
    readonly property var lang: find(Installer.languages, "id", s.locale)
    readonly property var zone: find(Installer.timezones, "id", s.timezone)
    readonly property var diskInfo: find(Installer.disks, "path", s.disk)

    // ——— Kroki ———
    readonly property var steps: [
        { id: "welcome", title: "Język", icon: "globe" },
        { id: "keyboard", title: "Klawiatura", icon: "keyboard" },
        { id: "network", title: "Internet", icon: "wifi" },
        { id: "time", title: "Strefa czasowa", icon: "clock" },
        { id: "disk", title: "Dysk", icon: "drive" },
        { id: "account", title: "Konto", icon: "user" },
        { id: "look", title: "Wygląd", icon: "sparkle" },
        { id: "summary", title: "Podsumowanie", icon: "check" }
    ]
    property int step: 0
    property int reached: 0
    readonly property string stepId: steps[step].id
    readonly property bool installing: Installer.state !== "idle"
    function go(i) { step = Math.max(0, Math.min(steps.length - 1, i)); reached = Math.max(reached, step); }

    // Czy można iść dalej z danego kroku
    readonly property string usernameError: {
        if (s.username === "") return "";
        if (!/^[a-z][a-z0-9_-]{0,31}$/.test(s.username)) return "Małe litery bez polskich znaków, cyfry, „-” i „_”; na początku litera";
        if (["root", "bin", "daemon", "adm", "sync", "nobody", "sddm", "liveuser"].indexOf(s.username) >= 0) return "Ta nazwa jest zajęta przez system";
        return "";
    }
    readonly property string passwordError: s.password !== "" && s.password.length < 6 ? "Co najmniej 6 znaków"
        : s.password2 !== "" && s.password !== s.password2 ? "Hasła się różnią" : ""
    readonly property bool hostnameOk: /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/.test(s.hostname)
    function canLeave(id) {
        if (id === "disk") return s.disk !== "" && s.eraseOk;
        if (id === "account") return s.fullName.trim() !== "" && s.username !== "" && usernameError === ""
                                     && s.password.length >= 6 && s.password === s.password2 && hostnameOk;
        return true;
    }

    function startInstall() {
        Installer.install({
            disk: s.disk, locale: s.locale, layout: kb.layout, variant: kb.variant, keymap: kb.keymap,
            timezone: s.timezone, hostname: s.hostname, username: s.username, fullName: s.fullName.trim(),
            password: s.password, autologin: s.autologin, dark: s.dark, accent: s.accent,
            wallpaper: s.wallpaper, autoUpdates: s.autoUpdates
        });
    }

    // Wybór języka podpowiada klawiaturę i strefę czasową
    function pickLanguage(l) {
        s.locale = l.id;
        s.keyboard = l.keyboard;
        s.timezone = l.timezone;
        Installer.setKeyboard(win.kb.layout, win.kb.variant);
    }

    // Do testów (ASTER_OPEN): krok:N | name | install | fail
    function testOpen(what) {
        if (what.startsWith("step:")) go(Number(what.substring(5)));
        else if (what === "name") { s.fullName = "Dominik Nowak"; s.password = "tajnehaslo"; s.password2 = "tajnehaslo"; }
        else if (what === "disk") { s.disk = Installer.disks[0].path; s.eraseOk = true; }
        else if (what === "dark") s.dark = true;
        else if (what === "install") startInstall();
    }

    // ——— Tło: tapeta Aster, rozmyta ———
    Image {
        id: wall
        anchors.fill: parent
        source: "file://" + Config.dataDir + "/wallpapers/" + s.wallpaper + (s.dark ? "-dark.jpg" : "-light.jpg")
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 1920
        asynchronous: true
        visible: !win.shaders
    }
    // Rozmycie liczone raz i trzymane jako tekstura — bez tego każda klatka animacji (pasek postępu)
    // liczy je od nowa, a bez karty graficznej (maszyna wirtualna) robi to procesor
    Item {
        anchors.fill: parent
        visible: win.shaders
        layer.enabled: true
        MultiEffect {
            anchors.fill: parent
            source: wall
            blurEnabled: true
            blur: 1
            blurMax: 64
            saturation: 0.15
        }
    }
    // Przyciemnienie (mocniejsze na ekranie instalacji — biały tekst na jasnej tapecie)
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, win.installing ? 0.5 : (s.dark ? 0.35 : 0.12))
        Behavior on color { ColorAnimation { duration: 240 } }
    }

    // Wyłączanie (prawy górny róg)
    Row {
        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 22
        spacing: 8
        visible: Installer.state !== "installing"
        RoundBtn { icon: "rotate"; tip: "Uruchom ponownie"; onClicked: Installer.reboot() }
        RoundBtn { icon: "power"; tip: "Wyłącz komputer"; onClicked: Installer.powerOff() }
    }

    // ——— Karta z krokami ———
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 1060)
        height: Math.min(parent.height - 80, 700)
        radius: 28
        color: Theme.pane
        border.width: 1; border.color: Theme.line
        visible: !win.installing
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        // Lewa kolumna: znak Aster i kroki
        Rectangle {
            id: rail
            width: 270; height: parent.height
            topLeftRadius: card.radius; bottomLeftRadius: card.radius
            color: Theme.fill
            Row {
                x: 26; y: 28
                spacing: 12
                Rectangle {
                    width: 34; height: 34; radius: 10
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(s.accent, 1.3) }
                        GradientStop { position: 1; color: s.accent }
                    }
                    Icon { anchors.centerIn: parent; d: Icons.aster; size: 20; stroke: 2.4; color: "white" }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Aster"
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 24; font.weight: Font.Bold; font.letterSpacing: -0.5
                }
            }
            Column {
                x: 16; y: 96
                width: parent.width - 32
                spacing: 4
                Repeater {
                    model: win.steps
                    delegate: HoverButton {
                        id: stepRow
                        required property var modelData
                        required property int index
                        readonly property bool current: index === win.step
                        readonly property bool done: index < win.reached || (index < win.step)
                        width: parent.width; height: 44; radius: 12
                        enabled: index <= win.reached
                        baseColor: current ? Theme.accentSoft : "transparent"
                        color: current ? baseColor : hovered ? Theme.hover : baseColor
                        onClicked: win.go(index)
                        Rectangle {
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            width: 26; height: 26; radius: 13
                            color: stepRow.current ? Theme.accent : stepRow.done ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22) : "transparent"
                            border.width: stepRow.current || stepRow.done ? 0 : 1.5
                            border.color: Theme.line
                            Icon {
                                anchors.centerIn: parent
                                visible: stepRow.done && !stepRow.current
                                d: Icons.check; size: 14; stroke: 2.4; color: Theme.accentText
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !stepRow.done || stepRow.current
                                text: stepRow.index + 1
                                color: stepRow.current ? "white" : Theme.text2
                                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Bold
                            }
                        }
                        Text {
                            x: 48; anchors.verticalCenter: parent.verticalCenter
                            text: stepRow.modelData.title
                            color: stepRow.enabled ? Theme.text : Theme.text2
                            font.family: Theme.font; font.pixelSize: 14; font.weight: stepRow.current ? Font.DemiBold : Font.Normal
                        }
                    }
                }
            }
            Text {
                x: 26; anchors.bottom: parent.bottom; anchors.bottomMargin: 24
                width: parent.width - 52
                wrapMode: Text.WordWrap
                text: "Aster 1.0 · na bazie Fedory"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
            }
        }

        // Prawa część: treść kroku i przyciski
        Item {
            id: pane
            x: rail.width + 44; y: 40
            width: parent.width - rail.width - 88
            height: parent.height - 40 - footer.height - 52

            Loader {
                id: page
                anchors.fill: parent
                clip: true
                sourceComponent: ({ welcome: welcomePage, keyboard: keyboardPage, network: networkPage, time: timePage,
                                    disk: diskPage, account: accountPage, look: lookPage, summary: summaryPage })[win.stepId]
                onLoaded: { item.opacity = 0; item.x = 24; fadeIn.restart(); }
                ParallelAnimation {
                    id: fadeIn
                    NumberAnimation { target: page.item; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutCubic }
                    NumberAnimation { target: page.item; property: "x"; to: 0; duration: 190; easing.type: Easing.OutCubic }
                }
            }
        }

        Item {
            id: footer
            x: pane.x; anchors.bottom: parent.bottom; anchors.bottomMargin: 28
            width: pane.width; height: 46
            Btn {
                visible: win.step > 0
                text: "Wstecz"; icon: "back"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: win.go(win.step - 1)
            }
            Btn {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                primary: true
                height: 46
                enabled: win.canLeave(win.stepId)
                text: win.stepId === "summary" ? "Zainstaluj Aster" : win.stepId === "network" && !Installer.online ? "Pomiń" : "Dalej"
                icon: win.stepId === "summary" ? "download" : ""
                iconRight: win.stepId !== "summary" ? "forward" : ""
                onClicked: win.stepId === "summary" ? win.startInstall() : win.go(win.step + 1)
            }
        }
    }

    // ——— Instalacja, koniec, błąd ———
    Item {
        anchors.fill: parent
        visible: win.installing
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 240 } }

        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width - 80, 620)
            spacing: 22

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120; height: 120
                // Znak Aster na kole postępu
                Canvas {
                    id: ring
                    anchors.fill: parent
                    property real p: Installer.progress
                    onPChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d");
                        c.reset();
                        c.lineWidth = 6; c.lineCap = "round";
                        c.strokeStyle = Qt.rgba(1, 1, 1, 0.14);
                        c.beginPath(); c.arc(60, 60, 54, 0, 2 * Math.PI); c.stroke();
                        c.strokeStyle = Installer.state === "failed" ? "#F87171" : Theme.accent;
                        c.beginPath(); c.arc(60, 60, 54, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * p); c.stroke();
                    }
                }
                Icon {
                    anchors.centerIn: parent
                    visible: Installer.state === "installing"
                    d: Icons.aster
                    size: 44; stroke: 2.4; color: "white"
                    // Obraca się razem z postępem, nie w kółko — ciągła animacja zajmowała procesor potrzebny instalacji
                    rotation: Installer.progress * 720
                    Behavior on rotation { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                }
                Icon {
                    anchors.centerIn: parent
                    visible: Installer.state !== "installing"
                    d: Installer.state === "done" ? Icons.check : Icons.close
                    size: 44; stroke: 2.6; color: "white"
                }
            }

            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter
                text: Installer.state === "done" ? "Aster jest zainstalowany"
                    : Installer.state === "failed" ? "Instalacja się nie udała"
                    : "Instaluję Aster…"
                color: "white"; font.family: Theme.font; font.pixelSize: 34; font.weight: Font.Bold; font.letterSpacing: -0.6
            }
            Text {
                width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: Installer.state === "done" ? "Wyjmij pendrive’a i uruchom komputer ponownie. Po chwili zobaczysz swój nowy pulpit."
                    : Installer.state === "failed" ? Installer.error
                    : Installer.stage + "  " + Math.round(Installer.progress * 100) + "%"
                color: Qt.rgba(1, 1, 1, 0.75); font.family: Theme.font; font.pixelSize: 16; lineHeight: 1.25
            }

            // Pasek postępu
            Rectangle {
                visible: Installer.state === "installing"
                anchors.horizontalCenter: parent.horizontalCenter
                width: 420; height: 6; radius: 3
                color: Qt.rgba(1, 1, 1, 0.14)
                Rectangle {
                    width: parent.width * Installer.progress; height: parent.height; radius: 3
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                }
            }

            // Podpowiedzi w trakcie
            Rectangle {
                id: tipBox
                visible: Installer.state === "installing"
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width; height: tipCol.implicitHeight + 36
                radius: 20
                color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
                property int tip: 0
                readonly property var tips: [
                    { icon: "search", t: "Szukaj wszystkiego", s: "Naciśnij klawisz Windows i zacznij pisać — programy, pliki i ustawienia w jednym miejscu." },
                    { icon: "sparkle", t: "Emoji pod Win+.", s: "Tak jak w Windows: panel emoji, symboli i kaomoji wstawia znak tam, gdzie piszesz." },
                    { icon: "phone", t: "Twój telefon na komputerze", s: "Program Telefon pokaże powiadomienia, wyśle pliki i znajdzie telefon pod poduszką." },
                    { icon: "bag", t: "Sklep z programami", s: "Przeglądarki, komunikatory, gry i narzędzia — instalujesz jednym kliknięciem." },
                    { icon: "shield", t: "Aktualizacje bez strachu", s: "System aktualizuje się w całości i zawsze możesz wrócić do poprzedniej wersji." }
                ]
                Timer { interval: 7000; repeat: true; running: Installer.state === "installing"; onTriggered: tipBox.tip = (tipBox.tip + 1) % tipBox.tips.length }
                Row {
                    id: tipRow
                    x: 20; y: 18
                    spacing: 16
                    Rectangle {
                        width: 44; height: 44; radius: 13
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)
                        Icon { anchors.centerIn: parent; d: Icons[tipBox.tips[tipBox.tip].icon]; size: 22; stroke: 1.9; color: "white" }
                    }
                    Column {
                        id: tipCol
                        width: tipBox.width - 100
                        spacing: 4
                        Text { text: tipBox.tips[tipBox.tip].t; color: "white"; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Text { width: parent.width; wrapMode: Text.WordWrap; text: tipBox.tips[tipBox.tip].s; color: Qt.rgba(1, 1, 1, 0.7); font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.2 }
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                visible: Installer.state !== "installing"
                Btn { visible: Installer.state === "failed"; text: logView.visible ? "Ukryj szczegóły" : "Szczegóły"; onClicked: logView.visible = !logView.visible }
                Btn { visible: Installer.state === "failed"; text: "Wróć do ustawień"; onClicked: Installer.state === "failed" && win.backToSummary() }
                Btn { primary: true; height: 46; text: Installer.state === "done" ? "Uruchom ponownie" : "Wyłącz komputer"; icon: Installer.state === "done" ? "rotate" : "power"
                      onClicked: Installer.state === "done" ? Installer.reboot() : Installer.powerOff() }
            }

            Rectangle {
                id: logView
                visible: false
                width: parent.width; height: 220
                radius: 14
                color: Qt.rgba(0, 0, 0, 0.45)
                Flickable {
                    anchors.fill: parent; anchors.margins: 12
                    contentHeight: logText.implicitHeight
                    clip: true
                    Text {
                        id: logText
                        width: parent.width
                        wrapMode: Text.WrapAnywhere
                        text: logView.visible ? Installer.log : ""   // ukryty log nie jest przeliczany
                        color: Qt.rgba(1, 1, 1, 0.8); font.family: "JetBrains Mono"; font.pixelSize: 11
                    }
                }
            }
        }
    }
    function backToSummary() { Installer.reset(); go(steps.length - 1); }

    // ——— Strony ———
    Component {
        id: welcomePage
        PageBase {
            title: "Witaj w Aster"
            subtitle: "Zainstalujmy system na tym komputerze. Zajmie to kilka minut — najpierw kilka pytań."
            ListView {
                width: parent.width; height: parent.height - 110
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: Installer.languages
                delegate: Choice {
                    required property var modelData
                    title: modelData.native
                    subtitle: modelData.native !== modelData.name ? modelData.name : ""
                    selected: s.locale === modelData.id
                    onClicked: win.pickLanguage(modelData)
                }
            }
        }
    }

    Component {
        id: keyboardPage
        PageBase {
            title: "Klawiatura"
            subtitle: "Układ klawiszy. „Polska (programisty)” to zwykła polska klawiatura — ogonki z prawym Alt."
            ListView {
                width: parent.width; height: parent.height - 190
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: Installer.keyboards
                delegate: Choice {
                    required property var modelData
                    title: modelData.name
                    selected: s.keyboard === modelData.id
                    onClicked: { s.keyboard = modelData.id; Installer.setKeyboard(modelData.layout, modelData.variant); }
                }
            }
            Field { width: parent.width; label: "Wypróbuj"; placeholder: "Napisz coś, np. zażółć gęślą jaźń" }
        }
    }

    Component {
        id: networkPage
        PageBase {
            id: np
            title: "Internet"
            subtitle: "Do instalacji internet nie jest potrzebny — połączysz się teraz albo później. Sieć zapamiętam w nowym systemie."
            property string opened
            property string message
            Connections {
                target: Installer
                function onWifiResult(ok, message) { np.message = message; if (ok) np.opened = ""; }
            }
            Rectangle {
                visible: Installer.wired
                width: parent.width; height: 54; radius: 14
                color: Theme.accentSoft
                Row {
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.ethernet; size: 20; stroke: 1.9; color: Theme.accentText }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Połączono kablem — wszystko gotowe"; color: Theme.accentText; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                }
            }
            Item {
                width: parent.width; height: 28
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Sieci Wi‑Fi"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                Btn { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; height: 28; text: Installer.scanning ? "Szukam…" : "Odśwież"; icon: "reload"; enabled: !Installer.scanning; onClicked: Installer.scanWifi() }
            }
            ListView {
                width: parent.width; height: parent.height - y
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: Installer.networks
                delegate: Column {
                    id: net
                    required property var modelData
                    width: ListView.view.width
                    spacing: 6
                    Choice {
                        width: parent.width
                        title: net.modelData.ssid
                        subtitle: net.modelData.active ? "Połączono" : net.modelData.secure ? "Zabezpieczona" : "Otwarta"
                        icon: "wifi"
                        selected: net.modelData.active
                        trailingIcon: net.modelData.secure ? "lock" : ""
                        onClicked: {
                            np.message = "";
                            if (net.modelData.active) return;
                            if (net.modelData.secure) np.opened = np.opened === net.modelData.ssid ? "" : net.modelData.ssid;
                            else Installer.connectWifi(net.modelData.ssid, "");
                        }
                    }
                    Row {
                        visible: np.opened === net.modelData.ssid
                        x: 12; spacing: 8
                        Field {
                            id: pw
                            width: net.width - 140
                            password: true
                            placeholder: "Hasło do sieci"
                            onAccepted: Installer.connectWifi(net.modelData.ssid, text)
                            Component.onCompleted: if (visible) forceActiveFocus()
                        }
                        Btn { anchors.bottom: pw.bottom; height: 42; primary: true; text: "Połącz"; enabled: pw.text.length >= 8; onClicked: Installer.connectWifi(net.modelData.ssid, pw.text) }
                    }
                    Text {
                        visible: np.opened === net.modelData.ssid && np.message !== ""
                        x: 14; text: np.message; color: Theme.danger; font.family: Theme.font; font.pixelSize: 12
                    }
                }
            }
        }
    }

    Component {
        id: timePage
        PageBase {
            id: tp
            title: "Strefa czasowa"
            subtitle: "Zegar ustawi się sam z internetu — tu wybierasz tylko, gdzie jesteś."
            property string query
            Row {
                spacing: 18
                Text {
                    text: Installer.timeIn(s.timezone)
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 40; font.weight: Font.Light
                    font.features: { "tnum": 1 }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: win.zone ? win.zone.city : s.timezone; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                    Text { text: win.zone ? win.zone.region + " · " + win.zone.offset : ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                }
            }
            Field { width: parent.width; placeholder: "Szukaj miasta, np. Warszawa"; icon: "search"; onTextChanged: tp.query = text.toLowerCase() }
            ListView {
                id: zones
                width: parent.width; height: parent.height - y
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: Installer.timezones.filter(z => tp.query === "" || z.city.toLowerCase().indexOf(tp.query) >= 0
                                                       || z.id.toLowerCase().indexOf(tp.query) >= 0)
                Component.onCompleted: {
                    const i = model.findIndex(z => z.id === s.timezone);
                    if (i >= 0) positionViewAtIndex(i, ListView.Center);
                }
                delegate: Choice {
                    required property var modelData
                    width: ListView.view.width
                    compact: true
                    title: modelData.city
                    subtitle: modelData.region
                    trailing: modelData.offset
                    selected: s.timezone === modelData.id
                    onClicked: s.timezone = modelData.id
                }
            }
        }
    }

    Component {
        id: diskPage
        PageBase {
            title: "Gdzie zainstalować?"
            subtitle: "Aster zajmie cały wybrany dysk."
            Column {
                width: parent.width
                spacing: 8
                Repeater {
                    model: Installer.disks
                    delegate: Choice {
                        required property var modelData
                        width: parent.width
                        icon: modelData.kind === "usb" ? "download" : "drive"
                        title: modelData.name
                        subtitle: (modelData.kind === "ssd" ? "Dysk SSD" : modelData.kind === "hdd" ? "Dysk twardy" : "Dysk USB")
                                  + " · " + modelData.path.replace("/dev/", "")
                                  + (modelData.windows ? " · jest na nim Windows" : modelData.partitions > 0 ? " · są na nim dane" : " · pusty")
                        trailing: modelData.sizeText
                        selected: s.disk === modelData.path
                        onClicked: { s.disk = modelData.path; s.eraseOk = false; }
                    }
                }
                Text {
                    visible: Installer.disks.length === 0
                    width: parent.width; wrapMode: Text.WordWrap
                    text: "Nie znaleziono dysku, na którym zmieści się Aster (potrzeba co najmniej 20 GB)."
                    color: Theme.danger; font.family: Theme.font; font.pixelSize: 14
                }
            }
            Rectangle {
                visible: s.disk !== ""
                width: parent.width; height: warnCol.implicitHeight + 32
                radius: 16
                color: Qt.rgba(0.9, 0.25, 0.25, Theme.dark ? 0.16 : 0.08)
                border.width: 1; border.color: Qt.rgba(0.9, 0.25, 0.25, 0.35)
                Column {
                    id: warnCol
                    x: 18; y: 16; width: parent.width - 36
                    spacing: 12
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: "Wszystko na dysku „" + (win.diskInfo ? win.diskInfo.name : "") + "” zostanie usunięte"
                              + (win.diskInfo && win.diskInfo.windows ? " — także Windows i Twoje pliki z Windows." : " — także pliki, które są na nim teraz.")
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    Check {
                        text: "Rozumiem, możesz wymazać ten dysk"
                        checked: s.eraseOk
                        onToggled: s.eraseOk = !s.eraseOk
                    }
                }
            }
        }
    }

    Component {
        id: accountPage
        PageBase {
            title: "Twoje konto"
            subtitle: "Tym hasłem zalogujesz się i potwierdzisz zmiany w systemie."
            Row {
                spacing: 18
                width: parent.width
                Rectangle {
                    width: 72; height: 72; radius: 36
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(s.accent, 1.35) }
                        GradientStop { position: 1; color: s.accent }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: s.fullName.trim().split(/\s+/).filter(w => w).slice(0, 2).map(w => w[0].toUpperCase()).join("") || "?"
                        color: "white"; font.family: Theme.font; font.pixelSize: 26; font.weight: Font.DemiBold
                    }
                }
                Field {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 90
                    label: "Imię i nazwisko"
                    placeholder: "np. Jan Kowalski"
                    text: s.fullName
                    onTextChanged: s.fullName = text
                    Component.onCompleted: forceActiveFocus()
                }
            }
            Row {
                width: parent.width; spacing: 14
                Field {
                    width: (parent.width - 14) / 2
                    label: "Nazwa użytkownika"
                    text: s.username
                    error: win.usernameError
                    onEdited: { s.usernameEdited = true; s.username = text; }
                }
                Field {
                    width: (parent.width - 14) / 2
                    label: "Nazwa komputera"
                    text: s.hostname
                    error: s.hostname !== "" && !win.hostnameOk ? "Małe litery, cyfry i „-”" : ""
                    onEdited: { s.hostnameEdited = true; s.hostname = text; }
                }
            }
            Row {
                width: parent.width; spacing: 14
                Field {
                    width: (parent.width - 14) / 2
                    label: "Hasło"; password: true
                    text: s.password
                    onTextChanged: s.password = text
                    error: s.password !== "" && s.password.length < 6 ? "Co najmniej 6 znaków" : ""
                }
                Field {
                    width: (parent.width - 14) / 2
                    label: "Powtórz hasło"; password: true
                    text: s.password2
                    onTextChanged: s.password2 = text
                    error: s.password2 !== "" && s.password !== s.password2 ? "Hasła się różnią" : ""
                }
            }
            Toggle {
                width: parent.width
                title: "Loguj automatycznie"
                subtitle: "Bez wpisywania hasła po włączeniu komputera. Wygodne w domu, ale każdy zobaczy Twoje pliki."
                checked: s.autologin
                onToggled: s.autologin = !s.autologin
            }
        }
    }

    Component {
        id: lookPage
        PageBase {
            title: "Wygląd"
            subtitle: "Zmienisz to później w Ustawieniach → Wygląd."
            Row {
                spacing: 14
                Repeater {
                    model: [{ dark: false, name: "Jasny" }, { dark: true, name: "Ciemny" }]
                    delegate: Item {
                        id: mode
                        required property var modelData
                        width: 220; height: 168
                        readonly property bool on: s.dark === modelData.dark
                        Rectangle {
                            width: parent.width; height: 132; radius: 16
                            color: "transparent"
                            border.width: mode.on ? 3 : 1
                            border.color: mode.on ? s.accent : Theme.line
                            clip: true
                            Image {
                                anchors.fill: parent; anchors.margins: mode.on ? 3 : 1
                                source: "file://" + Config.dataDir + "/wallpapers/" + s.wallpaper + (mode.modelData.dark ? "-dark.jpg" : "-light.jpg")
                                sourceSize.width: 440
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                            // Okienko w środku: jasne albo ciemne
                            Rectangle {
                                anchors.centerIn: parent
                                width: 120; height: 72; radius: 10
                                color: mode.modelData.dark ? "#22252E" : "#F7F8FB"
                                Rectangle { x: 10; y: 12; width: 54; height: 8; radius: 4; color: mode.modelData.dark ? "#4A4F5E" : "#D7DBE4" }
                                Rectangle { x: 10; y: 28; width: 90; height: 6; radius: 3; color: mode.modelData.dark ? "#3A3E4B" : "#E6E9EF" }
                                Rectangle { x: 10; y: 50; width: 40; height: 12; radius: 6; color: s.accent }
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter; y: 142
                            text: mode.modelData.name
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: mode.on ? Font.DemiBold : Font.Normal
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: s.dark = mode.modelData.dark }
                    }
                }
            }
            Text { text: "Kolor akcentu"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
            Row {
                spacing: 10
                Repeater {
                    model: ["#3456E8", "#7C3AED", "#DB2777", "#DC2626", "#EA580C", "#CA8A04", "#16A34A", "#4B5563"]
                    delegate: Rectangle {
                        id: sw
                        required property string modelData
                        width: 34; height: 34; radius: 17
                        color: modelData
                        border.width: s.accent === modelData ? 3 : 0
                        border.color: Theme.pane
                        Rectangle {
                            anchors.fill: parent; anchors.margins: -3; radius: width / 2
                            color: "transparent"; border.width: 2; border.color: sw.modelData
                            visible: s.accent === sw.modelData
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: s.accent = sw.modelData }
                    }
                }
            }
            Text { text: "Tapeta"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
            Row {
                spacing: 10
                Repeater {
                    model: ["aura", "bloom", "jezioro", "szczyty"]
                    delegate: Rectangle {
                        id: wp
                        required property string modelData
                        width: 104; height: 64; radius: 12
                        color: Theme.fill
                        border.width: s.wallpaper === modelData ? 3 : 0
                        border.color: s.accent
                        clip: true
                        Image {
                            anchors.fill: parent; anchors.margins: s.wallpaper === wp.modelData ? 3 : 0
                            source: "file://" + Config.dataDir + "/wallpapers/" + wp.modelData + (s.dark ? "-dark.jpg" : "-light.jpg")
                            sourceSize.width: 208
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: s.wallpaper = wp.modelData }
                    }
                }
            }
            Toggle {
                width: parent.width
                title: "Aktualizuj Aster automatycznie"
                subtitle: "Nowa wersja pobiera się w tle i włącza po ponownym uruchomieniu. Zawsze można wrócić do poprzedniej."
                checked: s.autoUpdates
                onToggled: s.autoUpdates = !s.autoUpdates
            }
        }
    }

    Component {
        id: summaryPage
        PageBase {
            title: "Wszystko gotowe"
            subtitle: "Sprawdź jeszcze raz. Po kliknięciu „Zainstaluj Aster” dysk zostanie wymazany."
            Column {
                width: parent.width
                spacing: 2
                Repeater {
                    model: [
                        { k: "Język", v: win.lang ? win.lang.native : "", step: 0 },
                        { k: "Klawiatura", v: win.kb ? win.kb.name : "", step: 1 },
                        { k: "Internet", v: Installer.wired ? "Kabel" : (Installer.networks.find(n => n.active) || { ssid: "Bez połączenia" }).ssid, step: 2 },
                        { k: "Strefa czasowa", v: win.zone ? win.zone.city + " (" + win.zone.offset + ")" : s.timezone, step: 3 },
                        { k: "Dysk", v: win.diskInfo ? win.diskInfo.name + ", " + win.diskInfo.sizeText + " — zostanie wymazany" : "", step: 4, warn: true },
                        { k: "Konto", v: s.fullName.trim() + " (" + s.username + ")" + (s.autologin ? ", logowanie automatyczne" : ""), step: 5 },
                        { k: "Komputer", v: s.hostname, step: 5 },
                        { k: "Wygląd", v: (s.dark ? "Ciemny" : "Jasny") + ", tapeta „" + s.wallpaper + "”" + (s.autoUpdates ? ", aktualizacje automatyczne" : ""), step: 6 }
                    ]
                    delegate: Item {
                        id: sumRow
                        required property var modelData
                        width: parent.width; height: 46
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                        Text { anchors.verticalCenter: parent.verticalCenter; width: 150; text: sumRow.modelData.k; color: Theme.text2; font.family: Theme.font; font.pixelSize: 14 }
                        Text {
                            x: 150; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 150 - 80; elide: Text.ElideRight
                            text: sumRow.modelData.v
                            color: sumRow.modelData.warn ? Theme.danger : Theme.text
                            font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium
                        }
                        Text {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            text: "Zmień"
                            color: Theme.accentText; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                            MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: win.go(sumRow.modelData.step) }
                        }
                    }
                }
            }
        }
    }

    // ——— Elementy ———
    component PageBase: Column {
        id: pb
        property string title
        property string subtitle
        width: parent ? parent.width : 0
        height: parent ? parent.height : 0
        spacing: 18
        Column {
            width: parent.width
            spacing: 8
            Text {
                text: pb.title
                color: Theme.text; font.family: Theme.font; font.pixelSize: 30; font.weight: Font.Bold; font.letterSpacing: -0.6
            }
            Text {
                width: parent.width; wrapMode: Text.WordWrap
                text: pb.subtitle
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 15; lineHeight: 1.25
            }
        }
    }

    // Wiersz do wyboru (język, sieć, dysk…)
    component Choice: HoverButton {
        id: ch
        property string title
        property string subtitle
        property string icon
        property string trailing
        property string trailingIcon
        property bool selected: false
        property bool compact: false
        width: parent ? parent.width : 0
        height: compact ? 44 : (subtitle !== "" ? 58 : 48)
        radius: 12
        baseColor: selected ? Theme.accentSoft : "transparent"
        color: selected ? baseColor : hovered ? Theme.hover : baseColor
        border.width: selected ? 1.5 : 0
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
        Icon {
            id: chIcon
            visible: ch.icon !== ""
            x: 14; anchors.verticalCenter: parent.verticalCenter
            d: Icons[ch.icon] || ""; size: 20; stroke: 1.8
            color: ch.selected ? Theme.accentText : Theme.text2
        }
        Column {
            x: ch.icon !== "" ? 46 : 16; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 120
            spacing: 2
            Text {
                width: parent.width; elide: Text.ElideRight
                text: ch.title
                color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: ch.selected ? Font.DemiBold : Font.Medium
            }
            Text {
                visible: ch.subtitle !== ""
                width: parent.width; elide: Text.ElideRight
                text: ch.subtitle
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Text { visible: ch.trailing !== ""; anchors.verticalCenter: parent.verticalCenter; text: ch.trailing; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; font.features: { "tnum": 1 } }
            Icon { visible: ch.trailingIcon !== ""; anchors.verticalCenter: parent.verticalCenter; d: Icons[ch.trailingIcon] || ""; size: 15; stroke: 1.9; color: Theme.text2 }
            Rectangle {
                visible: ch.selected
                anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22; radius: 11
                color: Theme.accent
                Icon { anchors.centerIn: parent; d: Icons.check; size: 13; stroke: 2.6; color: "white" }
            }
        }
    }

    component Field: Column {
        id: fld
        property string label
        property string placeholder
        property string error
        property string icon
        property bool password: false
        property alias text: input.text
        signal accepted()
        signal edited()
        function forceActiveFocus() { input.forceActiveFocus(); }
        spacing: 6
        Text { visible: fld.label !== ""; text: fld.label; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
        Rectangle {
            width: parent.width; height: 42; radius: 11
            color: Theme.fill
            border.width: input.activeFocus ? 2 : 1
            border.color: fld.error !== "" ? Theme.danger : input.activeFocus ? Theme.accent : Theme.line
            Icon { id: fIcon; visible: fld.icon !== ""; x: 12; anchors.verticalCenter: parent.verticalCenter; d: Icons[fld.icon] || ""; size: 16; stroke: 2; color: Theme.text2 }
            TextInput {
                id: input
                x: fld.icon !== "" ? 38 : 14; width: parent.width - x - (fld.password ? 44 : 14)
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; selectionColor: Theme.accent; selectedTextColor: "white"
                font.family: Theme.font; font.pixelSize: 15
                clip: true
                echoMode: fld.password && !eye.shown ? TextInput.Password : TextInput.Normal
                onAccepted: fld.accepted()
                onTextEdited: fld.edited()
                Text {
                    visible: input.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: fld.placeholder
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 15
                }
            }
            HoverButton {
                id: eye
                property bool shown: false
                visible: fld.password
                anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                width: 32; height: 32; radius: 16
                baseColor: "transparent"
                color: hovered ? Theme.hover : baseColor
                onClicked: shown = !shown
                Icon { anchors.centerIn: parent; d: Icons.eye; size: 16; stroke: 1.9; color: eye.shown ? Theme.accentText : Theme.text2 }
            }
        }
        Text { visible: fld.error !== ""; text: fld.error; color: Theme.danger; font.family: Theme.font; font.pixelSize: 12 }
    }

    component Toggle: Item {
        id: tg
        property string title
        property string subtitle
        property bool checked: false
        signal toggled()
        height: Math.max(48, tgCol.implicitHeight + 8)
        Column {
            id: tgCol
            width: parent.width - 70
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Text { text: tg.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Medium }
            Text { width: parent.width; wrapMode: Text.WordWrap; text: tg.subtitle; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2 }
        }
        Rectangle {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: 46; height: 28; radius: 14
            color: tg.checked ? Theme.accent : Theme.fill
            border.width: tg.checked ? 0 : 1; border.color: Theme.line
            Behavior on color { ColorAnimation { duration: 90 } }
            Rectangle {
                x: tg.checked ? parent.width - width - 3 : 3; anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22; radius: 11; color: "white"
                Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tg.toggled() }
    }

    component Check: Row {
        id: cb
        property string text
        property bool checked: false
        signal toggled()
        spacing: 10
        Rectangle {
            width: 22; height: 22; radius: 6
            color: cb.checked ? Theme.danger : "transparent"
            border.width: cb.checked ? 0 : 1.5; border.color: Theme.text2
            Icon { anchors.centerIn: parent; visible: cb.checked; d: Icons.check; size: 14; stroke: 2.6; color: "white" }
        }
        Text { anchors.verticalCenter: parent.verticalCenter; text: cb.text; color: Theme.text; font.family: Theme.font; font.pixelSize: 14 }
        TapHandler { onTapped: cb.toggled() }
    }

    component Btn: HoverButton {
        id: btn
        property string text
        property string icon
        property string iconRight
        property bool primary: false
        width: btnRow.implicitWidth + 34; height: 40; radius: height / 2
        baseColor: primary ? Theme.accent : Theme.fill
        color: !enabled ? baseColor : primary ? (hovered ? Qt.lighter(Theme.accent, 1.12) : baseColor) : (hovered ? Theme.hover : baseColor)
        opacity: enabled ? 1 : 0.4
        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 8
            Icon { visible: btn.icon !== ""; anchors.verticalCenter: parent.verticalCenter; d: Icons[btn.icon] || ""; size: 16; stroke: 2; color: btn.primary ? "white" : Theme.text }
            Text { anchors.verticalCenter: parent.verticalCenter; text: btn.text; color: btn.primary ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
            Icon { visible: btn.iconRight !== ""; anchors.verticalCenter: parent.verticalCenter; d: Icons[btn.iconRight] || ""; size: 16; stroke: 2; color: btn.primary ? "white" : Theme.text }
        }
    }

    component RoundBtn: HoverButton {
        id: rb
        property string icon
        property string tip
        width: 40; height: 40; radius: 20
        baseColor: Qt.rgba(0, 0, 0, 0.3)
        color: hovered ? Qt.rgba(0, 0, 0, 0.45) : baseColor
        Icon { anchors.centerIn: parent; d: Icons[rb.icon] || ""; size: 18; stroke: 2; color: "white" }
    }
}
