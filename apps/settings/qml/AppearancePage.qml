pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Aster.Ui
import Aster.Settings

// Wygląd: jasny albo ciemny (podglądy okien) i kolor akcentu — zmienia się od razu w całym systemie
Page {
    id: ap
    readonly property var accents: [
        { name: "Niebieski", color: "#3456E8" }, { name: "Fioletowy", color: "#7C3AED" },
        { name: "Różowy", color: "#DB2777" }, { name: "Czerwony", color: "#DC2626" },
        { name: "Pomarańczowy", color: "#EA580C" }, { name: "Żółty", color: "#CA8A04" },
        { name: "Zielony", color: "#16A34A" }, { name: "Grafitowy", color: "#4B5563" }
    ]

    Section {
        title: "Motyw"
        Item {
            width: parent.width; height: 196
            Row {
                anchors.centerIn: parent
                spacing: 28
                ModeCard { dark: false; label: "Jasny" }
                ModeCard { dark: true; label: "Ciemny" }
            }
        }
    }

    Section {
        title: "Kolor akcentu"
        footer: "Kolor przycisków, zaznaczeń i przełączników w całym systemie."
        Item {
            width: parent.width; height: 74
            Row {
                x: 18; anchors.verticalCenter: parent.verticalCenter
                spacing: 14
                Repeater {
                    model: ap.accents
                    delegate: Item {
                        id: sw
                        required property var modelData
                        readonly property bool chosen: Qt.colorEqual(Config.accent, modelData.color)
                        width: 30; height: 30
                        Rectangle {
                            anchors.centerIn: parent
                            width: 36; height: 36; radius: 18
                            color: "transparent"
                            border.width: 2.5
                            border.color: sw.modelData.color
                            opacity: sw.chosen ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 90 } }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 15
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.lighter(sw.modelData.color, 1.25) }
                                GradientStop { position: 1; color: sw.modelData.color }
                            }
                            scale: swArea.pressed ? 0.88 : (swArea.containsMouse ? 1.08 : 1)
                            Behavior on scale { NumberAnimation { duration: 120 } }
                        }
                        Rectangle { anchors.centerIn: parent; width: 9; height: 9; radius: 4.5; color: "white"; visible: sw.chosen }
                        MouseArea { id: swArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Config.accent = sw.modelData.color; System.run("plasma-apply-colorscheme", ["--accent-color", sw.modelData.color]); } }
                    }
                }
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: (ap.accents.find(a => Qt.colorEqual(Config.accent, a.color)) || { name: "" }).name
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
            }
        }
    }

    // Podgląd motywu: miniaturka pulpitu z oknem i dokiem
    component ModeCard: Column {
        id: mc
        property bool dark
        property string label
        readonly property bool chosen: Theme.dark === dark
        spacing: 10
        Item {
            width: 200; height: 132
            Rectangle {
                anchors.fill: parent; anchors.margins: -4
                radius: 18
                color: "transparent"
                border.width: 3
                border.color: Theme.accent
                opacity: mc.chosen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 100 } }
            }
            Rectangle {
                id: mini
                anchors.fill: parent
                radius: 14
                clip: true
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: mc.dark ? "#1D2A6B" : "#9DB4FF" }
                    GradientStop { position: 1; color: mc.dark ? "#5B2160" : "#FFC3A8" }
                }
                // okno
                Rectangle {
                    x: 22; y: 18; width: 130; height: 82; radius: 8
                    color: mc.dark ? "#2A2C33" : "#FFFFFF"
                    Rectangle { width: 38; height: parent.height; radius: 8; color: mc.dark ? "#22242A" : "#F1F2F6" }
                    Rectangle { x: 46; y: 12; width: 60; height: 7; radius: 3.5; color: mc.dark ? "#ECEEF3" : "#16181D"; opacity: 0.85 }
                    Rectangle { x: 46; y: 26; width: 72; height: 5; radius: 2.5; color: mc.dark ? "#A2A9B6" : "#5B6270"; opacity: 0.5 }
                    Rectangle { x: 46; y: 36; width: 52; height: 5; radius: 2.5; color: mc.dark ? "#A2A9B6" : "#5B6270"; opacity: 0.5 }
                    Rectangle { x: 46; y: 58; width: 34; height: 12; radius: 6; color: Theme.accent }
                    Rectangle { x: 8; y: 12; width: 22; height: 5; radius: 2.5; color: Theme.accent; opacity: 0.8 }
                    Rectangle { x: 8; y: 22; width: 18; height: 5; radius: 2.5; color: mc.dark ? "#A2A9B6" : "#5B6270"; opacity: 0.4 }
                    Rectangle { x: 8; y: 32; width: 20; height: 5; radius: 2.5; color: mc.dark ? "#A2A9B6" : "#5B6270"; opacity: 0.4 }
                }
                // dok
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 7
                    width: 74; height: 16; radius: 6
                    color: mc.dark ? Qt.rgba(0.1, 0.1, 0.12, 0.7) : Qt.rgba(1, 1, 1, 0.7)
                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        Repeater {
                            model: ["#5AB4FF", "#4FD1C5", "#C084FC", "#FDBA4D", "#A3A9B5"]
                            delegate: Rectangle { required property var modelData; width: 9; height: 9; radius: 3; color: modelData }
                        }
                    }
                }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: System.setDarkMode(mc.dark) }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: mc.label
            color: mc.chosen ? Theme.text : Theme.text2
            font.family: Theme.font; font.pixelSize: 13; font.weight: mc.chosen ? Font.DemiBold : Font.Normal
        }
    }
}
