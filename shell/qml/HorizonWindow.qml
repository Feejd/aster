pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import Aster.Shell
import Aster.Ui

// „Horyzont”: szklana wyspa u góry ekranu z datą i godziną.
// Powiadomienia (od każdego programu, także aplikacji webowych) wysuwają się pod nią jako karta:
// klik otwiera program, krzyżyk zamyka, kursor nad kartą wstrzymuje jej zniknięcie.
Window {
    id: hz
    color: "transparent"
    title: "Horyzont"
    visible: false
    width: 480
    height: 190

    Component.onCompleted: {
        Platform.makeLayer(hz, "top", 1, 0, "none", "aster-horizon");
        visible = true;
        regionTimer.start();
    }

    property date now: new Date()
    Timer { interval: 1000; repeat: true; running: true; onTriggered: hz.now = new Date() }

    // ——— Kolejka powiadomień: na raz widać jedno, kolejne czekają ———
    property var queue: []
    property var current: null
    Connections {
        target: Platform
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
        regionTimer.restart();
    }
    Timer { id: showTimer; interval: 5500; onTriggered: if (cardHover.hovered) restart(); else hz.next() }

    // Czarna pigułka (jak „Dynamic Island”): data i mała kropka Aster; rozszerza się, gdy przychodzi powiadomienie
    Island {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        y: 10
        solid: true
        width: (hz.current ? 200 : 0) + pillRow.implicitWidth + 36
        height: 36
        radius: 18
        Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
        onWidthChanged: regionTimer.restart()

        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 10
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 8; height: 8; radius: 4
                color: hz.current ? "#34D399" : Theme.accent
                Behavior on color { ColorAnimation { duration: 200 } }
            }
            Text {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                text: hz.now.toLocaleDateString(Qt.locale("pl_PL"), "dddd, d MMMM")
                color: "white"
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }
    }

    // ——— Karta powiadomienia ———
    Island {
        id: card
        solid: true
        readonly property var n: hz.current
        anchors.horizontalCenter: parent.horizontalCenter
        width: 440
        height: 92
        radius: 22
        y: n ? pill.y + pill.height + 10 : pill.y
        opacity: n ? 1 : 0
        scale: n ? 1 : 0.9
        visible: opacity > 0.01
        Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }

        HoverHandler { id: cardHover }
        TapHandler {
            onTapped: if (card.n) { Platform.activateNotification(card.n.id); hz.next(); }
        }

        Item {
            id: iconBox
            x: 16; anchors.verticalCenter: parent.verticalCenter
            width: 48; height: 48
            Image {
                anchors.fill: parent
                visible: !!card.n && !!card.n.image
                source: card.n && card.n.image ? card.n.image : ""
                sourceSize: Qt.size(96, 96)
                fillMode: Image.PreserveAspectFit
                smooth: true; mipmap: true
            }
            Kirigami.Icon {
                anchors.fill: parent
                visible: !!card.n && !card.n.image
                source: card.n ? (card.n.icon || "preferences-desktop-notification") : ""
            }
        }
        Column {
            anchors.left: iconBox.right; anchors.leftMargin: 14
            anchors.right: closeBtn.left; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                width: parent.width
                text: card.n ? card.n.appName : ""
                visible: text !== ""
                elide: Text.ElideRight
                color: Qt.rgba(1, 1, 1, 0.6)
                font.family: Theme.font; font.pixelSize: 11; font.letterSpacing: 0.1; font.weight: Font.Medium
            }
            Text {
                width: parent.width
                text: card.n ? card.n.summary : ""
                elide: Text.ElideRight
                color: "white"
                font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium
            }
            Text {
                width: parent.width
                text: card.n ? card.n.body : ""
                visible: text !== ""
                textFormat: Text.StyledText
                maximumLineCount: 2
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                color: Qt.rgba(1, 1, 1, 0.72)
                font.family: Theme.font; font.pixelSize: 12
            }
        }
        Rectangle {
            id: closeBtn
            anchors.right: parent.right; anchors.rightMargin: 12
            y: 12
            width: 24; height: 24; radius: 12
            visible: cardHover.hovered
            color: closeArea.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
            Icon { anchors.centerIn: parent; d: Icons.close; size: 11; stroke: 2; color: Qt.rgba(1, 1, 1, 0.7) }
            MouseArea {
                id: closeArea; anchors.fill: parent; hoverEnabled: true
                onClicked: { if (card.n) Platform.dismissNotification(card.n.id); hz.next(); }
            }
        }
        // Pasek czasu do zniknięcia
        Rectangle {
            anchors.bottom: parent.bottom; anchors.bottomMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            height: 3; radius: 1.5
            color: Theme.accent
            opacity: 0.5
            width: 60
            visible: !!card.n
        }
    }

    // Rozmycie i kliknięcia tylko tam, gdzie coś jest
    Timer {
        id: regionTimer
        interval: 30
        onTriggered: {
            const r = [{ x: pill.x, y: pill.y, w: pill.width, h: pill.height, r: pill.radius }];
            if (hz.current) r.push({ x: card.x, y: pill.y + pill.height + 10, w: card.width, h: card.height, r: card.radius });
            Platform.setBlur(hz, r);
            Platform.setInputRegion(hz, r);
        }
    }
}
