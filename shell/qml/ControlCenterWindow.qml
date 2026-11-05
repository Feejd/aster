pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Aster.Shell
import Aster.Ui

// Centrum sterowania (jak w macOS): wysuwa się spod prawej wyspy górnego paska.
// Kafelki: sieć i Bluetooth, „Nie przeszkadzać”, ciemny motyw, jasność, dźwięk, odtwarzacz
// i szybkie przyciski. Stan i działania — ControlCenter (C++). Klik obok panelu albo Esc zamyka.
Window {
    id: cc
    property bool followsPrimary: true   // po zmianie głównego ekranu main.cpp przenosi okno
    color: "transparent"
    visible: false
    width: Screen.width
    height: Screen.height - 32 - 84
    readonly property int shotY: 32
    title: "Centrum sterowania"

    property bool open: false
    // Strona panelu: "" (kafelki), "wifi", "bluetooth" albo "audio"
    property string page: ""
    property string passwordFor: ""
    onPageChanged: { passwordFor = ""; blurTimer.restart(); }
    readonly property int pad: 14
    readonly property int gap: 10
    readonly property real unit: (panel.width - 2 * pad - gap) / 2

    Component.onCompleted: Platform.makeLayer(cc, "overlay", 1 | 2 | 4 | 8, 0, "exclusive", "aster-control-center")

    function toggle() { if (open) close(); else show(); }
    function show() {
        hideTimer.stop();
        visible = true;
        open = true;
        ControlCenter.active = true;
        keys.forceActiveFocus();
        blurTimer.restart();
    }
    function close() {
        if (!open) return;
        open = false;
        page = "";
        ControlCenter.active = false;
        hideTimer.restart();
    }
    Timer { id: hideTimer; interval: 110; onTriggered: cc.visible = false }
    Binding { target: Connectivity; property: "page"; value: cc.open ? cc.page : "" }
    // Urządzenie prosi o parowanie: kod musi być widoczny, nawet gdy centrum jest zamknięte
    Connections {
        target: Connectivity
        function onPairingChanged() {
            if (Connectivity.pairingKind === "") return;
            cc.page = "bluetooth";
            cc.show();
        }
    }
    function iconFor(device) {
        const icon = device.icon || "";
        if (icon.indexOf("keyboard") !== -1) return "keyboard";
        if (icon.indexOf("mouse") !== -1) return "mouse";
        if (icon.indexOf("headset") !== -1 || icon.indexOf("headphone") !== -1) return "headphones";
        if (icon.indexOf("audio") !== -1) return "speaker";
        return "bluetooth";
    }
    function chooseNetwork(n) {
        if (n.active || Connectivity.wifiConnecting !== "") return;
        if (n.enterprise) { Platform.openUrl("aster-settings:wifi"); cc.close(); }
        else if (n.saved || !n.secure) Connectivity.connectWifi(n.ssid, "");
        else cc.passwordFor = cc.passwordFor === n.ssid ? "" : n.ssid;
    }

    // Klik obok panelu
    MouseArea { anchors.fill: parent; onClicked: cc.close() }
    Item { id: keys; focus: true; Keys.onEscapePressed: { if (cc.page !== "") cc.page = ""; else cc.close(); } }

    // ——— Panel ———
    Item {
        id: panel
        width: 384
        height: (cc.page === "" ? content.height : detail.height) + 2 * cc.pad
        x: cc.width - width - 10
        y: 4
        onHeightChanged: blurTimer.restart()

        // Wejście: sprężyste wyrośnięcie od prawego górnego rogu (spod prawej wyspy paska)
        property real s: 0.92
        property real offset: -14
        property real reveal: 0
        opacity: 0
        transform: [
            Scale { origin.x: panel.width; origin.y: 0; xScale: panel.s; yScale: panel.s },
            Translate { y: panel.offset }
        ]
        states: State {
            name: "shown"; when: cc.open
            PropertyChanges { panel.s: 1; panel.offset: 0; panel.opacity: 1; panel.reveal: 1 }
        }
        transitions: [
            Transition {
                to: "shown"
                ParallelAnimation {
                    NumberAnimation { target: panel; property: "s"; duration: 230; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
                    NumberAnimation { target: panel; property: "offset"; duration: 200; easing.type: Easing.OutQuint }
                    NumberAnimation { target: panel; property: "opacity"; duration: 70; easing.type: Easing.OutQuad }
                    NumberAnimation { target: panel; property: "reveal"; from: 0; duration: 300; easing.type: Easing.OutCubic }
                }
            },
            Transition {
                from: "shown"
                ParallelAnimation {
                    NumberAnimation { target: panel; property: "s"; to: 0.96; duration: 90; easing.type: Easing.InCubic }
                    NumberAnimation { target: panel; property: "offset"; to: -6; duration: 90; easing.type: Easing.InCubic }
                    NumberAnimation { target: panel; property: "opacity"; duration: 90; easing.type: Easing.InQuad }
                }
            }
        ]
        // Postęp wejścia i-tego kafelka (kaskada od góry)
        function stagger(i) { return Math.max(0, Math.min(1, (reveal - i * 0.04) / 0.45)); }

        MouseArea { anchors.fill: parent }   // kliknięcia w panel nie zamykają centrum

        Island { anchors.fill: parent; radius: 16 }
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: "transparent"
        }

        Column {
            id: content
            visible: cc.page === ""
            x: cc.pad; y: cc.pad
            width: panel.width - 2 * cc.pad
            spacing: cc.gap

            // ——— Gotowa aktualizacja systemu ———
            Tile {
                order: 5
                visible: ControlCenter.updateReady
                width: content.width; height: 60
                Icon { x: 16; anchors.verticalCenter: parent.verticalCenter; d: Icons.download; size: 20; stroke: 2; color: Theme.accentText }
                Column {
                    x: 48
                    width: parent.width - x - updateButton.width - 18
                    anchors.verticalCenter: parent.verticalCenter
                    Text { width: parent.width; text: "Aktualizacja gotowa"; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                    Text { width: parent.width; text: "Czeka na restart"; elide: Text.ElideRight; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                }
                PanelButton {
                    id: updateButton
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Uruchom ponownie"
                    primary: true
                    onClicked: { cc.close(); ControlCenter.restartForUpdate(); }
                }
            }

            // ——— Łączność | Nie przeszkadzać + Ciemny motyw ———
            Row {
                spacing: cc.gap
                Tile {
                    order: 4
                    width: cc.unit; height: 116
                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8
                        Toggle {
                            width: parent.width
                            icon: !ControlCenter.wifiAvailable && ControlCenter.wired ? "ethernet" : "wifi"
                            label: ControlCenter.wifiAvailable ? "Wi-Fi" : "Sieć"
                            on: ControlCenter.wifiAvailable ? ControlCenter.wifiOn : ControlCenter.wired
                            status: ControlCenter.networkName !== "" ? ControlCenter.networkName
                                  : ControlCenter.wifiAvailable ? (ControlCenter.wifiOn ? "Brak połączenia" : "Wyłączone") : "Brak sieci"
                            hasDetails: ControlCenter.wifiAvailable && ControlCenter.wifiOn
                            onClicked: if (ControlCenter.wifiAvailable) ControlCenter.setWifi(!ControlCenter.wifiOn); else Platform.openUrl("aster-settings:wifi")
                            onDetails: cc.page = "wifi"
                        }
                        Toggle {
                            width: parent.width
                            icon: "bluetooth"
                            label: "Bluetooth"
                            on: ControlCenter.bluetoothOn
                            enabled: ControlCenter.bluetoothAvailable
                            status: !ControlCenter.bluetoothAvailable ? "Niedostępny"
                                  : ControlCenter.bluetoothDevice !== "" ? ControlCenter.bluetoothDevice
                                  : ControlCenter.bluetoothOn ? "Włączony" : "Wyłączony"
                            hasDetails: ControlCenter.bluetoothOn
                            onClicked: ControlCenter.setBluetooth(!ControlCenter.bluetoothOn)
                            onDetails: cc.page = "bluetooth"
                        }
                    }
                }
                Column {
                    spacing: cc.gap
                    Tile {
                        order: 4
                        width: cc.unit; height: (116 - cc.gap) / 2
                        Toggle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 12; width: parent.width - 24
                            icon: "moon"
                            label: "Nie przeszkadzać"
                            on: Config.doNotDisturb
                            status: on ? "Włączone" : "Wyłączone"
                            onClicked: Config.doNotDisturb = !Config.doNotDisturb
                        }
                    }
                    Tile {
                        order: 4
                        width: cc.unit; height: (116 - cc.gap) / 2
                        Toggle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 12; width: parent.width - 24
                            icon: "contrast"
                            label: "Ciemny motyw"
                            on: Theme.dark
                            status: on ? "Włączony" : "Wyłączony"
                            onClicked: ControlCenter.setDarkMode(!Theme.dark)
                        }
                    }
                }
            }

            // ——— Jasność ———
            Tile {
                order: 3
                visible: ControlCenter.brightnessAvailable
                width: content.width; height: 74
                Caption { text: "Ekran" }
                LevelSlider {
                    x: 12; y: 34; width: parent.width - 24
                    icon: "sun"
                    value: ControlCenter.brightness
                    onMoved: v => ControlCenter.setBrightness(v)
                }
            }

            // ——— Dźwięk ———
            Tile {
                order: 2
                visible: ControlCenter.audioAvailable
                width: content.width; height: 74
                Caption { text: "Dźwięk" }
                MediaButton {
                    anchors.right: parent.right; anchors.rightMargin: 8
                    y: 3
                    width: 30
                    icon: "chevronRight"
                    outline: true
                    onClicked: cc.page = "audio"
                }
                LevelSlider {
                    x: 12; y: 34; width: parent.width - 24
                    icon: ControlCenter.muted || ControlCenter.volume === 0 ? "volumeOff" : ControlCenter.volume < 0.5 ? "volumeLow" : "volume"
                    value: ControlCenter.muted ? 0 : ControlCenter.volume
                    onMoved: v => ControlCenter.setVolume(v)
                    onIconClicked: ControlCenter.toggleMute()
                }
            }

            // ——— Odtwarzacz ———
            Tile {
                order: 1
                width: content.width; height: 80
                // Okładka (albo kolorowy kafelek z nutą)
                Item {
                    id: cover
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    width: 56; height: 56
                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        gradient: Gradient {
                            GradientStop { position: 0; color: "#FF8A8A" }
                            GradientStop { position: 1; color: "#8B5CF6" }
                        }
                        opacity: ControlCenter.playerAvailable ? 1 : 0.35
                        Icon { anchors.centerIn: parent; d: Icons.music; size: 24; stroke: 2; color: "white" }
                    }
                    Image {
                        id: art
                        anchors.fill: parent
                        source: ControlCenter.playerAvailable ? ControlCenter.artUrl : ""
                        sourceSize: Qt.size(112, 112)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false
                    }
                    Rectangle { id: artMask; anchors.fill: parent; radius: 14; visible: false; layer.enabled: true }
                    MultiEffect {
                        anchors.fill: parent
                        source: art
                        maskEnabled: true
                        maskSource: artMask
                        visible: art.status === Image.Ready
                    }
                }
                Column {
                    anchors.left: cover.right; anchors.leftMargin: 12
                    anchors.right: controls.left; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        width: parent.width
                        text: ControlCenter.playerAvailable ? (ControlCenter.title || ControlCenter.playerName) : "Nic nie gra"
                        elide: Text.ElideRight
                        color: ControlCenter.playerAvailable ? Theme.text : Theme.text2
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: ControlCenter.playerAvailable ? (ControlCenter.artist || ControlCenter.playerName) : "Muzyka i wideo pojawią się tutaj"
                        elide: Text.ElideRight
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 12
                    }
                }
                Row {
                    id: controls
                    anchors.right: parent.right; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: ControlCenter.playerAvailable ? 1 : 0.35
                    enabled: ControlCenter.playerAvailable
                    MediaButton { icon: "prev"; onClicked: ControlCenter.previous() }
                    MediaButton { icon: ControlCenter.playing ? "pause" : "play"; big: true; onClicked: ControlCenter.playPause() }
                    MediaButton { icon: "next"; onClicked: ControlCenter.next() }
                }
            }

            // ——— Szybkie przyciski ———
            Row {
                spacing: cc.gap
                readonly property real w: (content.width - 2 * cc.gap) / 3
                QuickTile {
                    width: parent.w
                    icon: "screenshot"; label: "Zrzut ekranu"
                    onClicked: { cc.close(); Platform.run("spectacle"); }
                }
                QuickTile {
                    width: parent.w
                    icon: "sliders"; label: "Ustawienia"
                    onClicked: { cc.close(); Platform.launchApp("org.aster.settings"); }
                }
                QuickTile {
                    width: parent.w
                    visible: ControlCenter.batteryAvailable
                    icon: "battery"; label: ControlCenter.charging ? "Ładowanie" : "Bateria"
                    value: ControlCenter.battery + "%"
                    onClicked: { cc.close(); Platform.run("systemsettings", ["kcm_powerdevilprofilesconfig"]); }
                }
                QuickTile {
                    width: parent.w
                    visible: !ControlCenter.batteryAvailable
                    icon: "lock"; label: "Zablokuj"
                    onClicked: { cc.close(); Platform.lockScreen(); }
                }
            }
        }

        // ——— Listy: sieci Wi‑Fi, urządzenia Bluetooth, wyjścia dźwięku ———
        Column {
            id: detail
            visible: cc.page !== ""
            x: cc.pad; y: cc.pad
            width: panel.width - 2 * cc.pad
            spacing: cc.gap

            Item {
                width: parent.width; height: 34
                MediaButton {
                    width: 34
                    icon: "back"
                    outline: true
                    onClicked: cc.page = ""
                }
                Text {
                    anchors.centerIn: parent
                    text: cc.page === "wifi" ? "Wi-Fi" : cc.page === "bluetooth" ? "Bluetooth" : "Dźwięk"
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                }
            }

            // Parowanie: kod do przepisania albo pytanie o zgodę
            Tile {
                visible: cc.page === "bluetooth" && Connectivity.pairingKind !== ""
                opacity: 1
                width: parent.width
                height: pairingBody.height + 28
                Column {
                    id: pairingBody
                    x: 14; y: 14
                    width: parent.width - 28
                    spacing: 10
                    Text {
                        width: parent.width
                        text: Connectivity.pairingDevice
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    Row {
                        visible: Connectivity.pairingCode !== ""
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 6
                        Repeater {
                            model: Connectivity.pairingCode.split("")
                            delegate: Rectangle {
                                id: digit
                                required property string modelData
                                required property int index
                                readonly property bool typed: index < Connectivity.pairingEntered
                                width: 38; height: 48; radius: 12
                                color: typed ? Theme.accent : Theme.fill
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: digit.modelData
                                    color: digit.typed ? "white" : Theme.text
                                    font.family: Theme.font; font.pixelSize: 24; font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        text: Connectivity.pairingKind === "show" ? "Wpisz ten kod na klawiaturze i naciśnij Enter."
                            : Connectivity.pairingCode !== "" ? "Sprawdź, czy na urządzeniu widać ten sam kod."
                            : "To urządzenie chce połączyć się z komputerem."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        PanelButton { label: "Anuluj"; onClicked: Connectivity.answerPairing(false) }
                        PanelButton {
                            visible: Connectivity.pairingKind === "confirm"
                            label: "Połącz"
                            primary: true
                            onClicked: Connectivity.answerPairing(true)
                        }
                    }
                }
            }

            Text {
                visible: text !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: cc.page === "wifi" ? Connectivity.wifiError : cc.page === "bluetooth" ? Connectivity.bluetoothError : ""
                color: Theme.danger; font.family: Theme.font; font.pixelSize: 13
            }

            Flickable {
                id: listArea
                width: parent.width
                height: Math.min(contentHeight, 430)
                contentHeight: rows.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: rows
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: cc.page === "wifi" ? Connectivity.wifiNetworks : []
                        delegate: Column {
                            id: netItem
                            required property var modelData
                            readonly property bool connecting: Connectivity.wifiConnecting === modelData.ssid
                            width: rows.width
                            spacing: 4
                            ListRow {
                                width: parent.width
                                icon: "wifi"
                                signalLevel: netItem.modelData.signal
                                title: netItem.modelData.ssid
                                subtitle: netItem.connecting ? "Łączenie…" : netItem.modelData.active ? "Połączono" : netItem.modelData.saved ? "Zapisana" : ""
                                checked: netItem.modelData.active
                                locked: netItem.modelData.secure
                                action: netItem.modelData.active ? "Rozłącz" : netItem.modelData.saved ? "Zapomnij" : ""
                                onClicked: cc.chooseNetwork(netItem.modelData)
                                onActionClicked: {
                                    if (netItem.modelData.active) Connectivity.disconnectWifi(netItem.modelData.ssid);
                                    else Connectivity.forgetWifi(netItem.modelData.ssid);
                                }
                            }
                            Rectangle {
                                visible: cc.passwordFor === netItem.modelData.ssid
                                onVisibleChanged: if (visible) password.forceActiveFocus()
                                width: parent.width; height: 44; radius: 14
                                color: Theme.fill
                                TextInput {
                                    id: password
                                    x: 14
                                    width: parent.width - 28 - connectButton.width - 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    echoMode: TextInput.Password
                                    color: Theme.text; font.family: Theme.font; font.pixelSize: 14
                                    selectByMouse: true
                                    clip: true
                                    function submit() {
                                        if (text === "") return;
                                        Connectivity.connectWifi(netItem.modelData.ssid, text);
                                        clear();
                                        cc.passwordFor = "";
                                    }
                                    onAccepted: submit()
                                    Keys.onEscapePressed: cc.passwordFor = ""
                                    Text {
                                        visible: parent.text === ""
                                        text: "Hasło sieci"
                                        color: Theme.text2; font: parent.font
                                    }
                                }
                                PanelButton {
                                    id: connectButton
                                    anchors.right: parent.right; anchors.rightMargin: 7
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: "Połącz"
                                    primary: true
                                    onClicked: password.submit()
                                }
                            }
                        }
                    }

                    Repeater {
                        model: cc.page === "bluetooth" ? Connectivity.bluetoothDevices : []
                        delegate: ListRow {
                            required property var modelData
                            readonly property bool busy: Connectivity.bluetoothBusy === modelData.path
                            width: rows.width
                            icon: cc.iconFor(modelData)
                            title: modelData.name
                            subtitle: busy ? "Chwileczkę…" : modelData.connected ? "Połączono" : modelData.paired ? "Sparowano" : "Kliknij, aby sparować"
                            checked: modelData.connected
                            action: modelData.paired ? "Zapomnij" : ""
                            onClicked: Connectivity.toggleDevice(modelData.path)
                            onActionClicked: Connectivity.forgetDevice(modelData.path)
                        }
                    }

                    SectionLabel { visible: cc.page === "audio"; text: "Wyjście" }
                    Repeater {
                        model: cc.page === "audio" ? Connectivity.audioOutputs : []
                        delegate: ListRow {
                            required property var modelData
                            width: rows.width
                            icon: "volume"
                            title: modelData.name
                            checked: modelData.active
                            onClicked: Connectivity.setAudioDefault(modelData.id)
                        }
                    }
                    SectionLabel { visible: cc.page === "audio" && Connectivity.audioInputs.length > 0; text: "Wejście" }
                    Repeater {
                        model: cc.page === "audio" ? Connectivity.audioInputs : []
                        delegate: ListRow {
                            required property var modelData
                            width: rows.width
                            icon: "mic"
                            title: modelData.name
                            checked: modelData.active
                            onClicked: Connectivity.setAudioDefault(modelData.id)
                        }
                    }
                }
            }

            Text {
                visible: (cc.page === "wifi" && Connectivity.wifiNetworks.length === 0)
                      || (cc.page === "bluetooth" && Connectivity.bluetoothDevices.length === 0)
                      || (cc.page === "audio" && Connectivity.audioOutputs.length === 0)
                width: parent.width; height: 70
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                text: cc.page === "wifi" ? "Szukam sieci…"
                    : cc.page === "bluetooth" ? "Szukam urządzeń…\nWłącz w urządzeniu tryb parowania."
                    : "Nie znaleziono urządzeń dźwiękowych"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
            }
        }
    }

    component SectionLabel: Text {
        x: 8
        height: 26
        verticalAlignment: Text.AlignVCenter
        color: Theme.text2
        font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
    }

    component PanelButton: Rectangle {
        id: pb
        property string label
        property bool primary: false
        signal clicked()
        width: pbText.implicitWidth + 24; height: 30; radius: 15
        color: primary ? Theme.accent : pbArea.containsMouse ? Theme.hover : Theme.fill
        scale: pbArea.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
        Text {
            id: pbText
            anchors.centerIn: parent
            text: pb.label
            color: pb.primary ? "white" : Theme.text
            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
        }
        MouseArea { id: pbArea; anchors.fill: parent; hoverEnabled: true; onClicked: pb.clicked() }
    }

    // Wiersz listy: ikona, nazwa, stan; akcja poboczna pojawia się po najechaniu
    component ListRow: Rectangle {
        id: lr
        property string icon
        property string title
        property string subtitle
        property string action
        property bool checked: false
        property bool locked: false
        property int signalLevel: -1
        signal clicked()
        signal actionClicked()
        height: 50
        radius: 14
        color: rowHover.hovered ? Theme.hover : "transparent"
        HoverHandler { id: rowHover }
        MouseArea { anchors.fill: parent; onClicked: lr.clicked() }
        Rectangle {
            id: lrIcon
            x: 8; anchors.verticalCenter: parent.verticalCenter
            width: 34; height: 34; radius: 17
            color: lr.checked ? Theme.accent : Theme.fill
            Icon { anchors.centerIn: parent; d: Icons[lr.icon] || ""; size: 17; stroke: 2; color: lr.checked ? "white" : Theme.text }
        }
        Column {
            anchors.left: lrIcon.right; anchors.leftMargin: 10
            anchors.right: trailing.left; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            Text {
                width: parent.width
                text: lr.title
                elide: Text.ElideRight
                color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium
            }
            Text {
                visible: lr.subtitle !== ""
                width: parent.width
                text: lr.subtitle
                elide: Text.ElideRight
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
        }
        Row {
            id: trailing
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            PanelButton {
                visible: lr.action !== "" && rowHover.hovered
                anchors.verticalCenter: parent.verticalCenter
                label: lr.action
                onClicked: lr.actionClicked()
            }
            Icon {
                visible: lr.locked
                anchors.verticalCenter: parent.verticalCenter
                d: Icons.lock; size: 14; stroke: 2; color: Theme.text2
            }
            // Siła sygnału: trzy kreski
            Row {
                visible: lr.signalLevel >= 0
                height: 13
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        required property int index
                        anchors.bottom: parent.bottom
                        width: 3; height: 5 + index * 4; radius: 1.5
                        color: lr.signalLevel > index * 30 + 5 ? Theme.text : Theme.fill
                    }
                }
            }
            Icon {
                visible: lr.checked
                anchors.verticalCenter: parent.verticalCenter
                d: Icons.check; size: 16; stroke: 2.4; color: Theme.accentText
            }
        }
    }

    // ——— Elementy ———

    // Kafelek: jaśniejsza tafla na szkle panelu; `order` ustala kolejność wejścia (od dołu)
    component Tile: Rectangle {
        id: tile
        property int order: 0
        readonly property real k: panel.stagger(order)
        radius: 10
        color: Theme.fill
        opacity: k
        transform: Translate { y: (1 - tile.k) * 10 }
    }

    component Caption: Text {
        x: 14; y: 11
        color: Theme.text
        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
    }

    // Okrągły przełącznik z podpisem i stanem obok
    component Toggle: Item {
        id: tg
        property string icon
        property string label
        property string status
        property bool on: false
        // Kółko przełącza, a podpis otwiera listę sieci lub urządzeń
        property bool hasDetails: false
        signal clicked()
        signal details()
        height: 40
        opacity: enabled ? 1 : 0.45
        Rectangle {
            id: circle
            width: 36; height: 36; radius: 18
            anchors.verticalCenter: parent.verticalCenter
            color: tg.on ? Theme.accent : (Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.08))
            scale: tgArea.pressed ? 0.9 : 1
            Behavior on color { ColorAnimation { duration: 160 } }
            Behavior on scale { NumberAnimation { duration: 100 } }
            Icon { anchors.centerIn: parent; d: Icons[tg.icon] || ""; size: 18; stroke: 2; color: tg.on ? "white" : Theme.text }
        }
        Column {
            anchors.left: circle.right; anchors.leftMargin: 9
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            Text {
                width: parent.width; height: 17
                text: tg.label
                fontSizeMode: Text.HorizontalFit; minimumPixelSize: 11   // długie polskie nazwy lekko się zmniejszają
                elide: Text.ElideRight
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
            }
            Text { width: parent.width; text: tg.status; elide: Text.ElideRight; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.letterSpacing: 0.1 }
        }
        MouseArea {
            id: tgArea
            anchors.fill: parent
            onClicked: m => { if (tg.hasDetails && m.x > circle.width + 3) tg.details(); else tg.clicked(); }
        }
    }

    // Suwak jak w macOS: gruba ścieżka, biała część do wartości z gałką, ikona w środku po lewej
    component LevelSlider: Item {
        id: sl
        property string icon
        property real value: 0
        signal moved(real v)
        signal iconClicked()
        height: 28
        readonly property real fillW: height + (width - height) * value
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.09)
        }
        Rectangle {
            width: sl.fillW; height: parent.height
            radius: height / 2
            color: Theme.dark ? "#E8EAF0" : "white"
            Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
        // Gałka
        RectangularShadow {
            x: sl.fillW - sl.height; width: sl.height; height: sl.height
            radius: sl.height / 2; blur: 8; offset.y: 1
            color: Qt.rgba(0, 0, 0, 0.32)
        }
        Rectangle {
            x: sl.fillW - sl.height; width: sl.height; height: sl.height
            radius: sl.height / 2
            color: "white"
            border.width: 1
            border.color: Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.10)
        }
        Icon {
            x: 6; anchors.verticalCenter: parent.verticalCenter
            d: Icons[sl.icon] || ""; size: 16; stroke: 2
            color: "#5B6270"
        }
        MouseArea {
            id: drag
            anchors.fill: parent
            function apply(mx) { sl.moved(Math.max(0, Math.min(1, (mx - sl.height / 2) / (sl.width - sl.height)))); }
            onPressed: m => { if (m.x < sl.height - 2) return; apply(m.x); }
            onPositionChanged: m => { if (pressed && m.x >= 0) apply(m.x); }
            onClicked: m => { if (m.x < sl.height - 2) sl.iconClicked(); }
        }
    }

    component MediaButton: Rectangle {
        id: mb
        property string icon
        property bool big: false
        property bool outline: false
        signal clicked()
        width: big ? 40 : 34; height: width; radius: width / 2
        color: mbArea.containsMouse ? Theme.hover : "transparent"
        scale: mbArea.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
        Icon {
            anchors.centerIn: parent
            d: Icons[mb.icon] || ""
            size: mb.big ? 22 : 18
            stroke: mb.icon === "pause" ? 3 : mb.outline ? 2 : 1.6
            color: Theme.text
            fill: mb.icon === "pause" || mb.outline ? "transparent" : Theme.text
        }
        MouseArea { id: mbArea; anchors.fill: parent; hoverEnabled: true; onClicked: mb.clicked() }
    }

    // Mały kafelek-przycisk: ikona, podpis, opcjonalnie wartość (np. procent baterii)
    component QuickTile: Tile {
        id: qt
        property string icon
        property string label
        property string value
        signal clicked()
        order: 0
        height: 76
        scale: qtArea.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.hover
            opacity: qtArea.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
        Column {
            anchors.centerIn: parent
            spacing: 6
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 5
                Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons[qt.icon] || ""; size: 20; stroke: 1.9; color: Theme.text }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: qt.value !== ""
                    text: qt.value
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium
                    font.features: { "tnum": 1 }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qt.label
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 11; font.letterSpacing: 0.1; font.weight: Font.Medium
            }
        }
        MouseArea { id: qtArea; anchors.fill: parent; hoverEnabled: true; onClicked: qt.clicked() }
    }

    Timer {
        id: blurTimer
        interval: 20
        onTriggered: Platform.setBlur(cc, [{ x: panel.x, y: panel.y, w: panel.width, h: panel.height, r: 30 }])
    }
}
