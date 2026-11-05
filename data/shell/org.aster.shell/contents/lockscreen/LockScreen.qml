pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import org.kde.plasma.private.sessions
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator

// Ekran blokady Aster (wczytuje go kscreenlocker z pakietu powłoki org.aster.shell).
// Wygląda jak ekran logowania: rozmyta tapeta, data i godzina, zdjęcie, imię i pole hasła.
// Od kscreenlocker: authenticator (PAM), kscreenlocker_userName, kscreenlocker_userImage.
Item {
    id: root
    // Właściwości i sygnały, których szuka kscreenlocker
    property bool debug: false
    property string notification
    property bool viewVisible: false
    signal clearPassword()
    signal notificationRepeated()

    implicitWidth: 1440
    implicitHeight: 900

    readonly property string font: "Geist"
    readonly property bool software: GraphicsInfo.api === GraphicsInfo.Software
    readonly property real u: Math.max(0.75, Math.min(width / 1440, height / 900))
    property string error: ""
    property string pending: ""

    onClearPassword: password.text = ""

    function unlock() {
        if (!password.text) return;
        error = "";
        if (authenticator.pamTimeout) {
            pending = password.text;
            password.enabled = false;
        } else {
            authenticator.respond(password.text);
        }
    }

    Component.onCompleted: authenticator.startAuthenticating()
    // Podtrzymanie PAM, dopóki ekran jest zablokowany (jak w Plasmie)
    Timer {
        interval: 1000; repeat: true
        running: !authenticator.unlocked
        onTriggered: authenticator.startAuthenticating()
    }

    Connections {
        target: authenticator
        function onFailed(kind) {
            if (kind != 0) return;          // odcisk palca itp. — bez komunikatu
            root.error = "Nieprawidłowe hasło";
            password.text = "";
            password.enabled = true;
            shake.restart();
            authenticator.startAuthenticating();
            password.forceActiveFocus();
        }
        function onSucceeded() {
            authenticator.stopAuthenticating();
            leave.start();
        }
        function onPromptForSecretChanged() { password.forceActiveFocus(); }
        function onPamTimeoutChanged() {
            if (!authenticator.pamTimeout && root.pending.length > 0) {
                authenticator.respond(root.pending);
                root.pending = "";
                password.enabled = true;
            }
        }
    }

    SessionManagement { id: sessions }
    Connections {
        target: sessions
        function onAboutToSuspend() { password.text = ""; }
    }
    KeyboardIndicator.KeyState { id: caps; key: Qt.Key_CapsLock }

    // ——— Tło ———
    Rectangle { anchors.fill: parent; color: "black" }
    Image {
        id: wall
        anchors.fill: parent
        source: "file:///usr/share/aster/wallpapers/grzbiety-dark.jpg"
        fillMode: Image.PreserveAspectCrop
        visible: root.software
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        visible: !root.software
        blurEnabled: true
        blurMax: 64
        blur: 0.85
        saturation: 0.15
        autoPaddingEnabled: false
    }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, root.software ? 0.42 : 0.28) }

    MouseArea { anchors.fill: parent; onPressed: password.forceActiveFocus() }

    Item {
        id: content
        anchors.fill: parent

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.09
            spacing: 2 * root.u
            Text {
                id: dateText
                anchors.horizontalCenter: parent.horizontalCenter
                color: Qt.rgba(1, 1, 1, 0.88)
                font.family: root.font; font.pixelSize: 20 * root.u; font.weight: Font.DemiBold
            }
            Text {
                id: timeText
                anchors.horizontalCenter: parent.horizontalCenter
                color: Qt.rgba(1, 1, 1, 0.92)
                font.family: root.font; font.pixelSize: 112 * root.u; font.weight: Font.DemiBold
                font.letterSpacing: -3 * root.u
            }
            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: {
                    const now = new Date();
                    const pl = Qt.locale("pl_PL");
                    timeText.text = now.toLocaleTimeString(pl, "H:mm");
                    dateText.text = now.toLocaleDateString(pl, "dddd, d MMMM");
                }
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.6
            spacing: 14 * root.u

            // Zdjęcie użytkownika albo inicjał na gradiencie Aster
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 96 * root.u; height: width
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    visible: photo.status !== Image.Ready
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#93A8FF" }
                        GradientStop { position: 1; color: "#4B3FD6" }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: (kscreenlocker_userName || "?").charAt(0).toUpperCase()
                        color: "white"
                        font.family: root.font; font.pixelSize: parent.width * 0.42; font.weight: Font.DemiBold
                    }
                }
                Image {
                    id: photo
                    anchors.fill: parent
                    source: kscreenlocker_userImage ? "file://" + kscreenlocker_userImage.split("/").map(encodeURIComponent).join("/") : ""
                    sourceSize: Qt.size(width * 2, height * 2)
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: photo
                    visible: photo.status === Image.Ready
                    maskEnabled: true
                    maskSource: photoMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
                Item {
                    id: photoMask
                    anchors.fill: parent
                    layer.enabled: true
                    visible: false
                    Rectangle { anchors.fill: parent; radius: width / 2; color: "black" }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2; border.color: Qt.rgba(1, 1, 1, 0.35)
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: kscreenlocker_userName
                color: "white"
                font.family: root.font; font.pixelSize: 18 * root.u; font.weight: Font.DemiBold
            }

            Item {
                id: fieldBox
                anchors.horizontalCenter: parent.horizontalCenter
                width: 250 * root.u; height: 40 * root.u
                SequentialAnimation {
                    id: shake
                    NumberAnimation { target: fieldBox; property: "anchors.horizontalCenterOffset"; to: -14; duration: 50 }
                    NumberAnimation { target: fieldBox; property: "anchors.horizontalCenterOffset"; to: 12; duration: 60 }
                    NumberAnimation { target: fieldBox; property: "anchors.horizontalCenterOffset"; to: -8; duration: 60 }
                    NumberAnimation { target: fieldBox; property: "anchors.horizontalCenterOffset"; to: 5; duration: 60 }
                    NumberAnimation { target: fieldBox; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50 }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, password.activeFocus ? 0.22 : 0.16)
                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.28)
                }
                TextInput {
                    id: password
                    anchors.left: parent.left; anchors.leftMargin: 18 * root.u
                    anchors.right: go.left; anchors.rightMargin: 6 * root.u
                    anchors.verticalCenter: parent.verticalCenter
                    focus: true
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    color: "white"
                    selectionColor: Qt.rgba(1, 1, 1, 0.3)
                    font.family: root.font; font.pixelSize: 15 * root.u; font.letterSpacing: 2 * root.u
                    clip: true
                    onTextEdited: root.error = ""
                    Keys.onReturnPressed: root.unlock()
                    Keys.onEnterPressed: root.unlock()
                    Keys.onEscapePressed: text = ""
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !password.text
                        text: "Hasło"
                        color: Qt.rgba(1, 1, 1, 0.6)
                        font.family: root.font; font.pixelSize: 15 * root.u
                    }
                }
                Rectangle {
                    id: go
                    anchors.right: parent.right; anchors.rightMargin: 4 * root.u
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32 * root.u; height: width; radius: width / 2
                    visible: password.text.length > 0 || !password.enabled
                    color: goArea.containsMouse ? Qt.rgba(1, 1, 1, 0.34) : Qt.rgba(1, 1, 1, 0.22)
                    Glyph { anchors.centerIn: parent; path: "M5 12h14M13 6l6 6-6 6"; size: parent.width * 0.5; stroke: 2.2 }
                    MouseArea { id: goArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.unlock() }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                height: 18 * root.u
                text: root.error || (caps.locked ? "Caps Lock jest włączony" : "")
                color: root.error ? "#FFB4AE" : Qt.rgba(1, 1, 1, 0.7)
                font.family: root.font; font.pixelSize: 13 * root.u; font.weight: Font.Medium
            }
        }

        // Uśpij (na ekranie blokady tylko to — wyłączanie wymaga odblokowania)
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 36 * root.u
            spacing: 8 * root.u
            visible: sessions.canSuspend
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 46 * root.u; height: width; radius: width / 2
                color: sleepArea.containsMouse ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(1, 1, 1, 0.16)
                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.22)
                Glyph { anchors.centerIn: parent; path: "M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"; size: 20 * root.u }
                MouseArea { id: sleepArea; anchors.fill: parent; hoverEnabled: true; onClicked: sessions.suspend() }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Uśpij"
                color: Qt.rgba(1, 1, 1, 0.78)
                font.family: root.font; font.pixelSize: 12 * root.u; font.weight: Font.Medium
            }
        }
    }

    // Po odblokowaniu ekran gaśnie, a pod nim jest pulpit
    SequentialAnimation {
        id: leave
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: 220; easing.type: Easing.InQuad }
        ScriptAction { script: Qt.quit() }
    }

    component Glyph: Item {
        id: g
        property string path
        property real size: 18
        property real stroke: 1.9
        width: size; height: size
        Shape {
            width: 24; height: 24
            scale: g.size / 24
            transformOrigin: Item.TopLeft
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "white"
                strokeWidth: g.stroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: g.path }
            }
        }
    }
}
