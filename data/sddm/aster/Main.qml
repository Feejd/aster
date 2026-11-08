pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// Ekran logowania Aster (motyw SDDM): rozmyta tapeta, data i duża godzina na górze,
// niżej zdjęcie i imię użytkownika z polem hasła — jak w macOS. Przy kilku osobach
// pod kartą są małe zdjęcia pozostałych. Na dole: uśpij, uruchom ponownie, wyłącz;
// w rogu sesja i układ klawiatury (gdy jest z czego wybierać).
// SDDM podaje: sddm (logowanie, zasilanie), userModel, sessionModel, keyboard, config.
Rectangle {
    id: root
    width: 1440
    height: 900
    color: "black"

    readonly property string font: "Inter"
    readonly property color accent: config.accent || "#7C8CFF"
    readonly property bool software: GraphicsInfo.api === GraphicsInfo.Software
    readonly property real u: Math.max(0.75, Math.min(width / 1440, height / 900))

    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property bool busy: false
    property string error: ""

    // Dane wybranego użytkownika (model SDDM czytany przez niewidoczny Repeater)
    property string userName: ""
    property string userReal: ""
    property string userIcon: ""
    property bool userNeedsPassword: true
    Repeater {
        id: users
        model: userModel
        delegate: Item {
            required property int index
            required property string name
            required property string realName
            required property string icon
            required property bool needsPassword
            Component.onCompleted: if (index === root.userIndex) root.pick(index, name, realName, icon, needsPassword)
        }
    }
    Repeater { id: sessions; model: sessionModel; delegate: Item { required property string name } }
    function pick(i, name, real, icon, needs) {
        userIndex = i;
        userName = name;
        userReal = real || name;
        userIcon = icon || "";
        userNeedsPassword = needs;
        error = "";
        password.text = "";
        password.forceActiveFocus();
    }
    function login() {
        if (busy || !userName) return;
        busy = true;
        error = "";
        sddm.login(userName, password.text, sessionIndex);
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false;
            root.error = "Nieprawidłowe hasło";
            password.text = "";
            shake.restart();
            password.forceActiveFocus();
        }
        function onLoginSucceeded() { leave.start(); }
    }

    // ——— Tło: tapeta Aster rozmyta jak szkło ———
    Image {
        id: wall
        anchors.fill: parent
        source: config.background ? (config.background.indexOf("/") === 0 ? "file://" + config.background : config.background) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
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

    Item {
        id: content
        anchors.fill: parent
        opacity: 0
        Component.onCompleted: { opacity = 1; password.forceActiveFocus(); }
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

        // ——— Data i godzina ———
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

        // ——— Użytkownik i hasło ———
        Column {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            // Przy kilku osobach karta podnosi się, żeby nie wchodzić na przyciski zasilania
            y: Math.min(parent.height * 0.6, power.y - 40 * root.u - height)
            spacing: 14 * root.u

            Avatar {
                anchors.horizontalCenter: parent.horizontalCenter
                size: 96 * root.u
                name: root.userReal
                source: root.userIcon
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.userReal
                color: "white"
                font.family: root.font; font.pixelSize: 18 * root.u; font.weight: Font.DemiBold
            }

            // Pole hasła (szkło); po wpisaniu pojawia się strzałka
            Item {
                id: fieldBox
                anchors.horizontalCenter: parent.horizontalCenter
                width: 250 * root.u; height: 40 * root.u
                visible: root.userNeedsPassword
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
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.28)
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                TextInput {
                    id: password
                    anchors.left: parent.left; anchors.leftMargin: 18 * root.u
                    anchors.right: go.left; anchors.rightMargin: 6 * root.u
                    anchors.verticalCenter: parent.verticalCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    color: "white"
                    selectionColor: Qt.rgba(1, 1, 1, 0.3)
                    font.family: root.font; font.pixelSize: 15 * root.u
                    font.letterSpacing: 2 * root.u
                    clip: true
                    enabled: !root.busy
                    onTextEdited: root.error = ""
                    Keys.onReturnPressed: root.login()
                    Keys.onEnterPressed: root.login()
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !password.text
                        text: "Hasło"
                        color: Qt.rgba(1, 1, 1, 0.6)
                        font.family: root.font; font.pixelSize: 15 * root.u
                    }
                }
                // Caps Lock włączony
                Glyph {
                    anchors.right: go.left; anchors.rightMargin: 4 * root.u
                    anchors.verticalCenter: parent.verticalCenter
                    visible: keyboard.capsLock && !password.text
                    path: "M12 4l-7 7h4v5h6v-5h4zM9 19h6"
                    size: 16 * root.u
                    color: Qt.rgba(1, 1, 1, 0.75)
                }
                RoundButton {
                    id: go
                    anchors.right: parent.right; anchors.rightMargin: 4 * root.u
                    anchors.verticalCenter: parent.verticalCenter
                    size: 32 * root.u
                    visible: password.text.length > 0 || root.busy
                    path: "M5 12h14M13 6l6 6-6 6"
                    spinning: root.busy
                    onClicked: root.login()
                }
            }
            // Bez hasła — sam przycisk
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.userNeedsPassword
                width: 160 * root.u; height: 40 * root.u; radius: height / 2
                color: loginArea.containsMouse ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(1, 1, 1, 0.2)
                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.3)
                Text { anchors.centerIn: parent; text: "Zaloguj"; color: "white"; font.family: root.font; font.pixelSize: 15 * root.u; font.weight: Font.Medium }
                MouseArea { id: loginArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.login() }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                height: 18 * root.u
                text: root.error || (keyboard.capsLock && root.userNeedsPassword ? "Caps Lock jest włączony" : "")
                color: root.error ? "#FFB4AE" : Qt.rgba(1, 1, 1, 0.7)
                font.family: root.font; font.pixelSize: 13 * root.u; font.weight: Font.Medium
            }

            // Pozostali użytkownicy
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18 * root.u
                visible: users.count > 1
                Repeater {
                    model: userModel
                    delegate: Item {
                        id: other
                        required property int index
                        required property string name
                        required property string realName
                        required property string icon
                        required property bool needsPassword
                        visible: index !== root.userIndex
                        width: visible ? 64 * root.u : 0
                        height: 72 * root.u
                        opacity: otherArea.containsMouse ? 1 : 0.8
                        Avatar {
                            anchors.horizontalCenter: parent.horizontalCenter
                            size: 44 * root.u
                            name: other.realName || other.name
                            source: other.icon
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 50 * root.u
                            width: parent.width + 16 * root.u
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: (other.realName || other.name).split(" ")[0]
                            color: "white"
                            font.family: root.font; font.pixelSize: 12 * root.u
                        }
                        MouseArea {
                            id: otherArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.pick(other.index, other.name, other.realName, other.icon, other.needsPassword)
                        }
                    }
                }
            }
        }

        // ——— Zasilanie ———
        Row {
            id: power
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 36 * root.u
            spacing: 34 * root.u
            PowerButton { visible: sddm.canSuspend; label: "Uśpij"; path: "M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"; onClicked: sddm.suspend() }
            PowerButton { visible: sddm.canReboot; label: "Uruchom ponownie"; path: "M20 12a8 8 0 1 1-2.3-5.6M20 4v5h-5"; onClicked: sddm.reboot() }
            PowerButton { visible: sddm.canPowerOff; label: "Wyłącz"; path: "M12 3v9M6.3 6.3a8 8 0 1 0 11.4 0"; onClicked: sddm.powerOff() }
        }

        // ——— Sesja i klawiatura (w rogu) ———
        Row {
            anchors.right: parent.right; anchors.rightMargin: 28 * root.u
            anchors.bottom: parent.bottom; anchors.bottomMargin: 40 * root.u
            spacing: 8 * root.u
            Chip {
                visible: keyboard.layouts && keyboard.layouts.length > 1
                path: "M2 7a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2zM6 9h.01M10 9h.01M14 9h.01M18 9h.01M6 13h.01M18 13h.01M8 16h8"
                label: keyboard.layouts && keyboard.layouts[keyboard.currentLayout] ? keyboard.layouts[keyboard.currentLayout].shortName.toUpperCase() : ""
                onClicked: keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length
            }
            Chip {
                visible: sessions.count > 1
                path: "M5 4h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM8 20h8M12 16v4"
                label: sessions.count > root.sessionIndex && sessions.itemAt(root.sessionIndex) ? sessions.itemAt(root.sessionIndex).name : ""
                onClicked: root.sessionIndex = (root.sessionIndex + 1) % sessions.count
            }
        }
    }

    // Po zalogowaniu ekran gaśnie łagodnie (pulpit wyłania się z tej samej tapety)
    SequentialAnimation {
        id: leave
        NumberAnimation { target: content; property: "opacity"; to: 0; duration: 260; easing.type: Easing.InQuad }
    }

    // ——— Elementy ———
    component Glyph: Item {
        id: g
        property string path
        property real size: 18
        property color color: "white"
        property real stroke: 1.9
        width: size; height: size
        Shape {
            width: 24; height: 24
            scale: g.size / 24
            transformOrigin: Item.TopLeft
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: g.color
                strokeWidth: g.stroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: g.path }
            }
        }
    }

    component Avatar: Item {
        id: av
        property real size: 96
        property string name
        property string source
        width: size; height: size
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            gradient: Gradient {
                GradientStop { position: 0; color: "#93A8FF" }
                GradientStop { position: 1; color: "#4B3FD6" }
            }
            visible: photo.status !== Image.Ready
            Text {
                anchors.centerIn: parent
                text: (av.name || "?").charAt(0).toUpperCase()
                color: "white"
                font.family: root.font; font.pixelSize: av.size * 0.42; font.weight: Font.DemiBold
            }
        }
        Image {
            id: photo
            anchors.fill: parent
            source: av.source ? (av.source.indexOf("/") === 0 ? "file://" + av.source : av.source) : ""
            sourceSize: Qt.size(av.size * 2, av.size * 2)
            fillMode: Image.PreserveAspectCrop
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: photo
            visible: photo.status === Image.Ready
            maskEnabled: true
            maskSource: avMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
        Item {
            id: avMask
            anchors.fill: parent
            layer.enabled: true
            visible: false
            Rectangle { anchors.fill: parent; radius: width / 2; color: "black" }
        }
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: Math.max(1, av.size / 48)
            border.color: Qt.rgba(1, 1, 1, 0.35)
        }
    }

    component RoundButton: Rectangle {
        id: rb
        property real size: 32
        property string path
        property bool spinning: false
        signal clicked()
        width: size; height: size; radius: size / 2
        color: rbArea.containsMouse ? Qt.rgba(1, 1, 1, 0.34) : Qt.rgba(1, 1, 1, 0.22)
        Glyph { anchors.centerIn: parent; visible: !rb.spinning; path: rb.path; size: rb.size * 0.5; stroke: 2.2 }
        Shape {
            anchors.centerIn: parent
            width: rb.size * 0.5; height: width
            visible: rb.spinning
            preferredRendererType: Shape.CurveRenderer
            RotationAnimation on rotation { running: rb.spinning; from: 0; to: 360; duration: 800; loops: Animation.Infinite }
            ShapePath {
                strokeColor: "white"; strokeWidth: 2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: rb.size / 4; centerY: rb.size / 4; radiusX: rb.size / 4 - 1; radiusY: rb.size / 4 - 1; startAngle: 0; sweepAngle: 270 }
            }
        }
        MouseArea { id: rbArea; anchors.fill: parent; hoverEnabled: true; onClicked: rb.clicked() }
    }

    component PowerButton: Item {
        id: pb
        property string label
        property string path
        signal clicked()
        width: Math.max(56 * root.u, pbText.implicitWidth); height: 76 * root.u
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 46 * root.u; height: width; radius: width / 2
            color: pbArea.containsMouse ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(1, 1, 1, 0.16)
            border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.22)
            scale: pbArea.pressed ? 0.94 : 1
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on scale { NumberAnimation { duration: 100 } }
            Glyph { anchors.centerIn: parent; path: pb.path; size: 20 * root.u }
        }
        Text {
            id: pbText
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: pb.label
            color: Qt.rgba(1, 1, 1, pbArea.containsMouse ? 1 : 0.78)
            font.family: root.font; font.pixelSize: 12 * root.u; font.weight: Font.Medium
        }
        MouseArea { id: pbArea; anchors.fill: parent; hoverEnabled: true; onClicked: pb.clicked() }
    }

    component Chip: Rectangle {
        id: ch
        property string path
        property string label
        signal clicked()
        width: chRow.implicitWidth + 24 * root.u; height: 32 * root.u; radius: height / 2
        color: chArea.containsMouse ? Qt.rgba(1, 1, 1, 0.26) : Qt.rgba(1, 1, 1, 0.14)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.2)
        Row {
            id: chRow
            anchors.centerIn: parent
            spacing: 7 * root.u
            Glyph { anchors.verticalCenter: parent.verticalCenter; path: ch.path; size: 15 * root.u }
            Text { anchors.verticalCenter: parent.verticalCenter; text: ch.label; color: "white"; font.family: root.font; font.pixelSize: 12 * root.u; font.weight: Font.Medium }
        }
        MouseArea { id: chArea; anchors.fill: parent; hoverEnabled: true; onClicked: ch.clicked() }
    }
}
