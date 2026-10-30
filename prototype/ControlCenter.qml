import QtQuick
import "Icons.js" as I

// Centrum sterowania: przełączniki, jasność, dźwięk, bateria
Panel {
    id: cc
    property bool dark: false
    property real volume: 0.45
    property real brightness: 0.7
    property string output: ""
    signal darkClicked(point at)
    signal volumeMoved(real v)
    signal settingsRequested()

    width: 380
    originX: 0.75
    originY: 1
    height: col.implicitHeight + 32

    ListModel {
        id: toggles
        ListElement { name: "Wi-Fi"; sub: "Sieć domowa"; icon: "wifi"; on: true }
        ListElement { name: "Bluetooth"; sub: "Słuchawki"; icon: "bluetooth"; on: true }
        ListElement { name: "Tryb ciemny"; sub: ""; icon: "moon"; on: false }
        ListElement { name: "Nie przeszkadzać"; sub: "Wyłączone"; icon: "bell"; on: false }
        ListElement { name: "Oszczędzanie"; sub: "Auto przy 20%"; icon: "saver"; on: false }
        ListElement { name: "Zrzut ekranu"; sub: "Zaznacz fragment"; icon: "screenshot"; on: false }
    }

    Column {
        id: col
        x: 16; y: 16
        width: parent.width - 32
        spacing: 14

        Grid {
            columns: 2
            spacing: 8
            width: parent.width
            Repeater {
                model: toggles
                delegate: Rectangle {
                    id: tg
                    required property int index
                    required property string name
                    required property string sub
                    required property string icon
                    required property bool on
                    readonly property bool isOn: name === "Tryb ciemny" ? cc.dark : on
                    width: (col.width - 8) / 2; height: 60
                    radius: 14
                    readonly property real k: cc.stagger(index)
                    opacity: k
                    transform: Translate { y: (1 - tg.k) * 14 }
                    color: isOn ? cc.t.accent : (ma.containsMouse ? Qt.darker(cc.t.surface, cc.dark ? 0.9 : 1.02) : cc.t.surface)
                    border.width: isOn ? 0 : 1
                    border.color: cc.t.line
                    scale: ma.pressed ? 0.97 : 1
                    Behavior on color { ColorAnimation { duration: 160 } }
                    Behavior on scale { NumberAnimation { duration: 120 } }

                    Rectangle {
                        id: ib
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        width: 36; height: 36; radius: 10
                        color: tg.isOn ? Qt.rgba(1, 1, 1, 0.18) : cc.t.fill
                        Icon { anchors.centerIn: parent; d: I[tg.icon]; color: tg.isOn ? "white" : cc.t.text }
                    }
                    Column {
                        anchors.left: ib.right; anchors.leftMargin: 10
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text { text: tg.name; color: tg.isOn ? "white" : cc.t.text; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight; width: parent.width }
                        Text {
                            text: tg.name === "Tryb ciemny" ? (cc.dark ? "Włączony" : "Wyłączony") : (tg.sub || (tg.isOn ? "Włączone" : "Wyłączone"))
                            color: tg.isOn ? Qt.rgba(1, 1, 1, 0.88) : cc.t.text2
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (tg.name === "Tryb ciemny") cc.darkClicked(tg.mapToItem(null, tg.width / 2, tg.height / 2));
                            else toggles.setProperty(tg.index, "on", !tg.on);
                        }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: sliders.implicitHeight + 28
            opacity: cc.stagger(7)
            transform: Translate { y: (1 - cc.stagger(7)) * 14 }
            radius: 14
            color: cc.t.surface
            border.width: 1
            border.color: cc.t.line
            Column {
                id: sliders
                x: 14; y: 14
                width: parent.width - 28
                spacing: 10
                Text { text: "Jasność"; color: cc.t.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                SoftSlider { t: cc.t; width: parent.width; value: cc.brightness; icon: I.sun; onMoved: (v) => cc.brightness = v }
                Text { text: "Dźwięk"; color: cc.t.text; font.pixelSize: 13; font.weight: Font.DemiBold; topPadding: 4 }
                SoftSlider { t: cc.t; width: parent.width; value: cc.volume; icon: I.volumeLow; onMoved: (v) => cc.volumeMoved(v) }
                HoverButton {
                    t: cc.t
                    width: parent.width; height: 40
                    color: cc.t.fill
                    Row {
                        anchors.left: parent.left; anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Icon { anchors.verticalCenter: parent.verticalCenter; d: I.headphones; color: cc.t.text }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Wyjście: <b>" + cc.output + "</b>"; textFormat: Text.StyledText; color: cc.t.text; font.pixelSize: 13 }
                    }
                    Icon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; d: I.forward; size: 16; color: cc.t.text2 }
                }
            }
        }

        Item {
            width: parent.width; height: 40
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Item {
                    width: 18; height: 18
                    anchors.verticalCenter: parent.verticalCenter
                    Icon { d: I.battery; color: cc.t.text }
                    Rectangle { x: 3.4; y: 6.9; width: 8.6; height: 4.2; radius: 1; color: cc.t.text }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "82%"; color: cc.t.text; font.pixelSize: 13; font.weight: Font.Medium }
            }
            Row {
                anchors.right: parent.right
                spacing: 6
                HoverButton { t: cc.t; width: 40; height: 40; color: cc.t.fill; onClicked: cc.settingsRequested(); Icon { anchors.centerIn: parent; d: I.sliders; color: cc.t.text } }
                HoverButton { t: cc.t; width: 40; height: 40; color: cc.t.fill; Icon { anchors.centerIn: parent; d: I.power; color: cc.t.text } }
            }
        }
    }
}
