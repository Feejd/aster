pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Aster.Shell
import Aster.Ui

// Centrum sterowania (jak w macOS): wyrasta nad prawą wyspą doku.
// Kafelki: sieć i Bluetooth, „Nie przeszkadzać”, ciemny motyw, jasność, dźwięk, odtwarzacz
// i szybkie przyciski. Stan i działania — ControlCenter (C++). Klik obok panelu albo Esc zamyka.
Window {
    id: cc
    color: "transparent"
    visible: false
    width: Screen.width
    height: Screen.height - 96
    title: "Centrum sterowania"

    property bool open: false
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
        ControlCenter.active = false;
        hideTimer.restart();
    }
    Timer { id: hideTimer; interval: 110; onTriggered: cc.visible = false }

    // Klik obok panelu
    MouseArea { anchors.fill: parent; onClicked: cc.close() }
    Item { id: keys; focus: true; Keys.onEscapePressed: cc.close() }

    // ——— Panel ———
    Item {
        id: panel
        width: 384
        height: content.height + 2 * cc.pad
        x: cc.width - width - 18
        y: cc.height - height - 12
        onHeightChanged: blurTimer.restart()

        // Wejście: sprężyste wyrośnięcie od prawego dolnego rogu (spod prawej wyspy)
        property real s: 0.92
        property real offset: 14
        property real reveal: 0
        opacity: 0
        transform: [
            Scale { origin.x: panel.width; origin.y: panel.height; xScale: panel.s; yScale: panel.s },
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
                    NumberAnimation { target: panel; property: "offset"; to: 6; duration: 90; easing.type: Easing.InCubic }
                    NumberAnimation { target: panel; property: "opacity"; duration: 90; easing.type: Easing.InQuad }
                }
            }
        ]
        // Postęp wejścia i-tego kafelka (kaskada od dołu)
        function stagger(i) { return Math.max(0, Math.min(1, (reveal - i * 0.04) / 0.45)); }

        MouseArea { anchors.fill: parent }   // kliknięcia w panel nie zamykają centrum

        Island { anchors.fill: parent; radius: 30 }
        Rectangle {
            anchors.fill: parent
            radius: 30
            color: Theme.dark ? Qt.rgba(0.09, 0.09, 0.11, 0.38) : Qt.rgba(1, 1, 1, 0.30)
        }

        Column {
            id: content
            x: cc.pad; y: cc.pad
            width: panel.width - 2 * cc.pad
            spacing: cc.gap

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
                            onClicked: if (ControlCenter.wifiAvailable) ControlCenter.setWifi(!ControlCenter.wifiOn); else Platform.run("systemsettings", ["kcm_networkmanagement"])
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
                            onClicked: ControlCenter.setBluetooth(!ControlCenter.bluetoothOn)
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
                            on: ControlCenter.doNotDisturb
                            status: on ? "Włączone" : "Wyłączone"
                            onClicked: ControlCenter.doNotDisturb = !ControlCenter.doNotDisturb
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
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
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
                    onClicked: { cc.close(); Platform.run("systemsettings"); }
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
    }

    // ——— Elementy ———

    // Kafelek: jaśniejsza tafla na szkle panelu; `order` ustala kolejność wejścia (od dołu)
    component Tile: Rectangle {
        id: tile
        property int order: 0
        readonly property real k: panel.stagger(order)
        radius: 22
        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.55)
        border.width: 1
        border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.75)
        opacity: k
        transform: Translate { y: (1 - tile.k) * 10 }
    }

    component Caption: Text {
        x: 14; y: 11
        color: Theme.text
        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
    }

    // Okrągły przełącznik z podpisem i stanem obok
    component Toggle: Item {
        id: tg
        property string icon
        property string label
        property string status
        property bool on: false
        signal clicked()
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
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
            }
            Text { width: parent.width; text: tg.status; elide: Text.ElideRight; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
        }
        MouseArea { id: tgArea; anchors.fill: parent; onClicked: tg.clicked() }
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
        signal clicked()
        width: big ? 40 : 34; height: width; radius: width / 2
        color: mbArea.containsMouse ? Theme.hover : "transparent"
        scale: mbArea.pressed ? 0.88 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
        Icon {
            anchors.centerIn: parent
            d: Icons[mb.icon] || ""
            size: mb.big ? 22 : 18
            stroke: mb.icon === "pause" ? 3 : 1.6
            color: Theme.text
            fill: mb.icon === "pause" ? "transparent" : Theme.text
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
                    font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qt.label
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium
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
