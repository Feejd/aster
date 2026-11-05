pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Aster.Shell
import Aster.Ui

// Prośba o hasło administratora (agent polkit w powłoce): przyciemniony ekran, a na środku karta —
// kto prosi i o co, zdjęcie użytkownika (przy kilku administratorach — wybór), hasło, Anuluj / Zezwól.
Window {
    id: auth
    property bool followsPrimary: true   // po zmianie głównego ekranu main.cpp przenosi okno
    color: "transparent"
    visible: false
    width: Screen.width
    height: Screen.height
    title: "Uwierzytelnianie"

    // Najpierw warstwa, potem widoczność (warstwy nie da się nadać pokazanemu już oknu)
    Component.onCompleted: {
        Platform.makeLayer(auth, "overlay", 1 | 2 | 4 | 8, -1, "exclusive", "aster-auth");
        visible = Qt.binding(() => Polkit.active);
    }
    onVisibleChanged: if (visible) { field.text = ""; enter.restart(); field.forceActiveFocus(); }

    readonly property var user: Polkit.users[Polkit.userIndex] || ({})

    // Złe hasło: pole czyści się, a karta „kręci głową”
    readonly property int attempt: Polkit.attempt
    onAttemptChanged: if (attempt > 0) { field.text = ""; shake.restart(); field.forceActiveFocus(); }

    Rectangle {
        id: dim
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.3)
        MouseArea { anchors.fill: parent }             // klik obok karty niczego nie zamyka
    }

    Item {
        id: holder
        anchors.centerIn: parent
        width: card.width; height: card.height
        SequentialAnimation {
            id: enter
            ParallelAnimation {
                NumberAnimation { target: holder; property: "scale"; from: 0.94; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                NumberAnimation { target: holder; property: "opacity"; from: 0; to: 1; duration: 160 }
            }
        }
        SequentialAnimation {
            id: shake
            NumberAnimation { target: holder; property: "anchors.horizontalCenterOffset"; to: -14; duration: 50 }
            NumberAnimation { target: holder; property: "anchors.horizontalCenterOffset"; to: 12; duration: 60 }
            NumberAnimation { target: holder; property: "anchors.horizontalCenterOffset"; to: -8; duration: 60 }
            NumberAnimation { target: holder; property: "anchors.horizontalCenterOffset"; to: 5; duration: 60 }
            NumberAnimation { target: holder; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50 }
        }

        RectangularShadow {
            anchors.fill: card
            radius: card.radius; blur: 48; offset.y: 18
            color: Theme.shadow
        }
        Rectangle {
            id: card
            width: 380
            height: col.implicitHeight + 48
            radius: 24
            color: Theme.surface
            border.width: 1; border.color: Theme.edge

            Column {
                id: col
                x: 28; y: 26
                width: parent.width - 56
                spacing: 0

                // Kłódka na gradiencie Aster
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 60; height: 60; radius: 18
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#93A8FF" }
                        GradientStop { position: 1; color: "#4B3FD6" }
                    }
                    Icon { anchors.centerIn: parent; d: Icons.lock; size: 28; stroke: 2; color: "white" }
                }
                Item { width: 1; height: 16 }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: "Potrzebne hasło administratora"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                }
                Item { width: 1; height: 6 }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: Polkit.message
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: 13
                    lineHeight: 1.15
                }
                Item { width: 1; height: Polkit.appName ? 8 : 0 }
                // Kto prosi (bez odmiany nazwy: „Prosi: Ustawienia”)
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: Polkit.appName !== ""
                    width: whoText.implicitWidth + 20; height: 24; radius: 12
                    color: Theme.fill
                    Text {
                        id: whoText
                        anchors.centerIn: parent
                        text: "Prosi: " + Polkit.appName
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                    }
                }
                Item { width: 1; height: 20 }

                // Użytkownik (przy kilku administratorach — do wyboru)
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    Repeater {
                        model: Polkit.users
                        delegate: Item {
                            id: u
                            required property int index
                            required property var modelData
                            readonly property bool chosen: index === Polkit.userIndex
                            visible: chosen || Polkit.users.length > 1
                            width: visible ? (Polkit.users.length > 1 ? 84 : 200) : 0; height: 76
                            opacity: chosen ? 1 : (uArea.containsMouse ? 0.9 : 0.55)
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 44; height: 44; radius: 22
                                border.width: u.chosen && Polkit.users.length > 1 ? 2 : 0
                                border.color: Theme.accent
                                gradient: Gradient {
                                    GradientStop { position: 0; color: "#93A8FF" }
                                    GradientStop { position: 1; color: "#4B3FD6" }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: avatar.status !== Image.Ready
                                    text: (u.modelData.realName || "?").charAt(0).toUpperCase()
                                    color: "white"; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                                }
                                Image {
                                    id: avatar
                                    anchors.fill: parent; anchors.margins: u.chosen && Polkit.users.length > 1 ? 2 : 0
                                    source: u.modelData.icon || ""
                                    sourceSize: Qt.size(88, 88)
                                    fillMode: Image.PreserveAspectCrop
                                    visible: false
                                }
                                MultiEffect {
                                    anchors.fill: avatar
                                    source: avatar
                                    visible: avatar.status === Image.Ready
                                    maskEnabled: true
                                    maskSource: avatarMask
                                }
                                Item {
                                    id: avatarMask
                                    anchors.fill: avatar
                                    layer.enabled: true
                                    visible: false
                                    Rectangle { anchors.fill: parent; radius: width / 2 }
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 52; width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: u.modelData.realName || u.modelData.name
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 12; font.weight: u.chosen ? Font.Medium : Font.Normal
                            }
                            MouseArea { id: uArea; anchors.fill: parent; hoverEnabled: true; onClicked: Polkit.selectUser(u.index) }
                        }
                    }
                }
                Item { width: 1; height: 12 }

                // Hasło
                Rectangle {
                    width: parent.width; height: 42; radius: 21
                    color: Theme.fill
                    border.width: field.activeFocus ? 1.5 : 0
                    border.color: Theme.accent
                    TextInput {
                        id: field
                        anchors.left: parent.left; anchors.leftMargin: 18
                        anchors.right: parent.right; anchors.rightMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        echoMode: Polkit.echo ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "●"
                        color: Theme.text
                        selectionColor: Theme.accentSoft
                        font.family: Theme.font; font.pixelSize: 15
                        clip: true
                        enabled: !Polkit.busy
                        Keys.onReturnPressed: auth.submit()
                        Keys.onEnterPressed: auth.submit()
                        Keys.onEscapePressed: Polkit.cancel()
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !field.text
                            text: Polkit.echo && Polkit.prompt ? Polkit.prompt.replace(/:\s*$/, "") : "Hasło"
                            color: Theme.text2
                            font.family: Theme.font; font.pixelSize: 15
                        }
                    }
                }
                Item { width: 1; height: 8 }
                Text {
                    width: parent.width; height: 18
                    horizontalAlignment: Text.AlignHCenter
                    text: Polkit.error
                    color: Theme.danger
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                Item { width: 1; height: 10 }

                Row {
                    width: parent.width
                    spacing: 10
                    Pill {
                        width: (parent.width - 10) / 2
                        text: "Anuluj"
                        onClicked: Polkit.cancel()
                    }
                    Pill {
                        width: (parent.width - 10) / 2
                        text: Polkit.busy ? "Sprawdzam…" : "Zezwól"
                        primary: true
                        enabled: field.text.length > 0 && !Polkit.busy
                        onClicked: auth.submit()
                    }
                }
            }
        }
    }

    function submit() {
        if (!field.text || Polkit.busy) return;
        Polkit.respond(field.text);
    }

    component Pill: HoverButton {
        id: pill
        property string text
        property bool primary: false
        height: 40; radius: 20
        baseColor: primary ? Theme.accent : Theme.fill
        color: hovered && enabled ? (primary ? Qt.darker(Theme.accent, 1.1) : Theme.hover) : baseColor
        opacity: enabled ? 1 : 0.5
        Text {
            anchors.centerIn: parent
            text: pill.text
            color: pill.primary ? "white" : Theme.text
            font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium
        }
    }
}
