import QtQuick
import QtQuick.Effects
import "Icons.js" as I

// Dolna część ekranu jako trzy pływające „wyspy” ze szkła zamiast paska na całą szerokość:
// po lewej Start i wyszukiwanie, na środku dok z aplikacjami (ikony rosną pod kursorem),
// po prawej asystent, motyw, sieć/dźwięk/bateria i zegar.
Item {
    id: bar
    property var t
    property var apps: []
    property Item backdrop
    property string panel: ""
    property bool filesOpen: false
    property bool dark: false
    property var recent: []
    property var openApps: ({})
    property string lastAdded: ""

    signal startClicked()
    signal trayClicked()
    signal appClicked(string name)
    signal darkClicked(point at)
    signal assistantClicked()
    signal openFile(string id)

    height: 84

    // Środek ikony aplikacji (we współrzędnych okna) — cel animacji minimalizacji
    function appCenter(name) {
        for (let i = 0; i < appsRep.count; i++) {
            const it = appsRep.itemAt(i);
            if (it && it.modelData.name === name) return it.mapToItem(null, it.width / 2, it.height / 2);
        }
        return Qt.point(width / 2, y);
    }

    // ——— Lewa wyspa: lupa (wyszukiwanie i Start) i ostatnio używane pliki ———
    GlassIsland {
        t: bar.t; dark: bar.dark; backdrop: bar.backdrop; baseX: bar.x; baseY: bar.y
        id: leftIsland
        x: 14
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        width: leftRow.implicitWidth + 16

        Row {
            id: leftRow
            anchors.centerIn: parent
            spacing: 4

            // Lupa: wyszukiwanie i Start w jednym
            HoverButton {
                t: bar.t
                width: 44; height: 44; radius: 14
                active: bar.panel === "start"
                onClicked: bar.startClicked()
                Icon {
                    anchors.centerIn: parent
                    d: I.search; size: 21; stroke: 2.1
                    color: bar.panel === "start" ? bar.t.accentText : bar.t.text
                    scale: bar.panel === "start" ? 1.12 : 1
                    Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack; easing.overshoot: 1.0 } }
                }
            }

            Rectangle { width: 1; height: 28; color: bar.t.line; anchors.verticalCenter: parent.verticalCenter }

            // Ostatnio używane pliki jako małe karty
            Repeater {
                model: bar.recent
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    required property int index
                    width: 98; height: 44; radius: 14
                    color: cardArea.containsMouse ? bar.t.fill : "transparent"
                    scale: cardArea.pressed ? 0.95 : 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on scale { NumberAnimation { duration: 100 } }
                    FileBadge {
                        id: cardBadge
                        x: 6
                        anchors.verticalCenter: parent.verticalCenter
                        t: bar.t
                        file: card.modelData
                        small: true
                    }
                    Column {
                        anchors.left: cardBadge.right; anchors.leftMargin: 7
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text { width: parent.width; text: card.modelData.name.replace(/\.[^.]+$/, ""); color: bar.t.text; font.pixelSize: 12; font.weight: Font.Medium; elide: Text.ElideRight }
                        Text { width: parent.width; text: card.modelData.date; color: bar.t.text2; font.pixelSize: 11; elide: Text.ElideRight }
                    }
                    // Pełna nazwa nad kartą
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: -40
                        width: tipText.implicitWidth + 18; height: 26; radius: 9
                        color: bar.dark ? Qt.rgba(0.12, 0.12, 0.15, 0.9) : Qt.rgba(1, 1, 1, 0.92)
                        opacity: cardArea.containsMouse ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        Text { id: tipText; anchors.centerIn: parent; text: card.modelData.name + "  ·  " + card.modelData.where; color: bar.t.text; font.pixelSize: 12 }
                    }
                    MouseArea { id: cardArea; anchors.fill: parent; hoverEnabled: true; onClicked: bar.openFile(card.modelData.id) }
                }
            }
        }
    }

    // ——— Środkowa wyspa: dok ———
    GlassIsland {
        t: bar.t; dark: bar.dark; backdrop: bar.backdrop; baseX: bar.x; baseY: bar.y
        id: dock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        width: dockRow.implicitWidth + 20
        Behavior on width { enabled: !dockHover.hovered; NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }

        property real pointerX: -1000

        HoverHandler {
            id: dockHover
            onPointChanged: dock.pointerX = point.position.x
            onHoveredChanged: if (!hovered) dock.pointerX = -1000
        }

        Row {
            id: dockRow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            spacing: 4
            Repeater {
                id: appsRep
                model: bar.apps
                delegate: Item {
                    id: slot
                    required property var modelData
                    readonly property bool running: bar.openApps[modelData.name] !== undefined ? bar.openApps[modelData.name] : !!modelData.running
                    readonly property bool focused: bar.openApps[modelData.name] === true
                    // Powiększenie zależne od odległości kursora (jak lupa)
                    readonly property real centerX: x + width / 2 + dockRow.x
                    readonly property real near: Math.max(0, 1 - Math.abs(dock.pointerX - centerX) / 120)
                    readonly property real mag: 1 + 0.45 * near * near
                    width: 48 * mag
                    height: 48
                    // Świeżo zainstalowana aplikacja wpada do doku z odbiciem
                    Component.onCompleted: if (modelData.name === bar.lastAdded) { tile.opacity = 0; dropIn.start(); bar.lastAdded = ""; }
                    ParallelAnimation {
                        id: dropIn
                        NumberAnimation { target: tile; property: "anchors.bottomMargin"; from: 56; to: 2; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                        NumberAnimation { target: tile; property: "opacity"; from: 0; to: 1; duration: 160 }
                    }
                    Behavior on width { NumberAnimation { duration: 90 } }

                    Rectangle {
                        id: tile
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        width: 42; height: 42
                        radius: 12
                        transformOrigin: Item.Bottom
                        scale: slotArea.pressed ? slot.mag * 0.88 : slot.mag
                        Behavior on scale { SpringAnimation { spring: 10; damping: 0.6; epsilon: 0.002 } }
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.lighter(slot.modelData.color, 1.25) }
                            GradientStop { position: 1; color: slot.modelData.color }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.25)
                        }
                        Icon { anchors.centerIn: parent; d: I[slot.modelData.icon]; size: 21; color: "white" }
                    }

                    // Podpis nad ikoną przy najechaniu
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: -44 - (slot.mag - 1) * 40
                        width: label.implicitWidth + 18; height: 26; radius: 9
                        color: bar.dark ? Qt.rgba(0.12, 0.12, 0.15, 0.9) : Qt.rgba(1, 1, 1, 0.92)
                        opacity: slotArea.containsMouse ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                        Text { id: label; anchors.centerIn: parent; text: slot.modelData.name; color: bar.t.text; font.pixelSize: 12; font.weight: Font.Medium }
                    }

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.bottom
                        anchors.topMargin: 1
                        width: slot.focused ? 14 : 4; height: 4; radius: 2
                        color: slot.focused ? bar.t.accentText : bar.t.text2
                        opacity: slot.running ? 0.9 : 0
                        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }

                    MouseArea {
                        id: slotArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: bar.appClicked(slot.modelData.name)
                    }
                }
            }
        }
    }

    // ——— Prawa wyspa: asystent, motyw, stan, zegar ———
    GlassIsland {
        t: bar.t; dark: bar.dark; backdrop: bar.backdrop; baseX: bar.x; baseY: bar.y
        id: rightIsland
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        width: rightRow.implicitWidth + 16

        Row {
            id: rightRow
            anchors.centerIn: parent
            spacing: 4

            HoverButton {
                t: bar.t
                width: 44; height: 44; radius: 14
                active: bar.panel === "assistant"
                onClicked: bar.assistantClicked()
                Icon { anchors.centerIn: parent; d: I.sparkle; size: 20; color: bar.t.accentText }
            }
            HoverButton {
                t: bar.t
                width: 44; height: 44; radius: 14
                onClicked: bar.darkClicked(mapToItem(null, width / 2, height / 2))
                Icon {
                    anchors.centerIn: parent
                    d: bar.dark ? I.sun : I.moon
                    color: bar.t.text
                    rotation: bar.dark ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
                }
            }
            HoverButton {
                t: bar.t
                width: trayRow.implicitWidth + 24; height: 44; radius: 14
                active: bar.panel === "control"
                onClicked: bar.trayClicked()
                Row {
                    id: trayRow
                    anchors.centerIn: parent
                    spacing: 12
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: I.wifi; color: bar.t.text }
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: I.volume; color: bar.t.text }
                    Item {
                        width: 18; height: 18
                        anchors.verticalCenter: parent.verticalCenter
                        Icon { d: I.battery; color: bar.t.text }
                        Rectangle { x: 3.4; y: 6.9; width: 8.6; height: 4.2; radius: 1; color: bar.t.text }
                    }
                }
            }
            HoverButton {
                id: clock
                property date now: new Date()
                t: bar.t
                width: clockCol.implicitWidth + 24; height: 44; radius: 14
                Timer { interval: 1000; running: true; repeat: true; onTriggered: clock.now = new Date() }
                Column {
                    id: clockCol
                    anchors.centerIn: parent
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatTime(clock.now, "HH:mm")
                        color: bar.t.text
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.locale("pl_PL").toString(clock.now, "ddd, d MMM")
                        color: bar.t.text2
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
