pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Harbor

// Logi na żywo wysuwane od dołu (podman logs -f). Przewija się samo, dopóki jesteś na końcu.
Item {
    id: panel
    readonly property bool open: Harbor.logName !== ""
    property bool expanded: false
    property real bottomRightRadius: 0
    property bool wrap: false
    readonly property string find: Harbor.logLines.filter

    z: 10

    Item {
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            bottomRightRadius: panel.bottomRightRadius
            color: Theme.dark ? "#0B0C10" : "#FBFBFD"
        }
        Rectangle { width: parent.width; height: 1; color: Theme.line }

        // Nagłówek
        Item {
            id: head
            width: parent.width; height: 46
            Row {
                x: 20; anchors.verticalCenter: parent.verticalCenter
                spacing: 9
                StateDot { anchors.verticalCenter: parent.verticalCenter; size: 8; running: Harbor.logLive }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Logi: " + Harbor.logName
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Harbor.logLive ? "na żywo" : "zatrzymane"
                    color: Harbor.logLive ? "#16A34A" : Theme.text2
                    font.family: Theme.font; font.pixelSize: 12
                }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 170; height: 30; radius: 9
                    color: Theme.fill
                    border.width: findInput.activeFocus ? 1.5 : 0; border.color: Theme.accent
                    Icon { x: 9; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 13; color: Theme.text2 }
                    TextInput {
                        id: findInput
                        x: 28; width: parent.width - 36
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                        clip: true
                        onTextChanged: Harbor.logLines.filter = text
                        Keys.onEscapePressed: text = ""
                        Text { visible: !findInput.text; text: "Filtruj linie"; color: Theme.text2; font: findInput.font }
                    }
                }
                Item { width: 6; height: 1 }
                ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "reload"; tip: "Wznów śledzenie"; visible: !Harbor.logLive; onClicked: Harbor.followLogs() }
                ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "alignLeft"; tip: panel.wrap ? "Bez zawijania" : "Zawijaj linie"; onClicked: panel.wrap = !panel.wrap; baseColor: panel.wrap ? Theme.fill : "transparent" }
                ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "copy"; tip: "Kopiuj wszystko"; onClicked: Harbor.copyLogs() }
                ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: panel.expanded ? "exitFullscreen" : "fullscreen"; tip: panel.expanded ? "Zmniejsz" : "Powiększ"; onClicked: panel.expanded = !panel.expanded }
                ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "close"; tip: "Zamknij (Esc)"; onClicked: { findInput.text = ""; Harbor.closeLogs(); } }
            }
        }

        ListView {
            id: list
            y: head.height
            x: 20
            width: parent.width - 40
            height: parent.height - head.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: Harbor.logLines
            property bool stick: true
            onMovementEnded: stick = atYEnd
            onCountChanged: if (stick) Qt.callLater(positionViewAtEnd)
            contentWidth: panel.wrap ? width : Math.max(width, widest + 20)
            flickableDirection: panel.wrap ? Flickable.VerticalFlick : Flickable.AutoFlickDirection
            property real widest: 0
            topMargin: 4; bottomMargin: 10
            delegate: Text {
                required property string line
                width: panel.wrap ? list.width : implicitWidth
                wrapMode: panel.wrap ? Text.WrapAnywhere : Text.NoWrap
                text: line === "" ? " " : line
                textFormat: Text.PlainText
                color: /error|fatal|exception|panic|błąd/i.test(line) ? Theme.danger
                     : /warn/i.test(line) ? (Theme.dark ? "#FBBF24" : "#B45309") : Theme.text
                font.family: "JetBrains Mono"; font.pixelSize: 12
                lineHeight: 1.15
                Component.onCompleted: if (implicitWidth > list.widest) list.widest = implicitWidth
            }
            Text {
                visible: list.count === 0
                anchors.centerIn: parent
                text: panel.find ? "Żadna linia nie pasuje" : Harbor.logLive ? "Czekam na logi…" : "Ten kontener nic nie zapisał w logach"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
            }
        }

        // Skok na koniec, gdy przewinięto w górę
        HoverButton {
            visible: !list.stick && list.count > 0
            anchors.right: parent.right; anchors.rightMargin: 20
            anchors.bottom: parent.bottom; anchors.bottomMargin: 16
            width: 36; height: 36; radius: 18
            baseColor: Theme.accent
            color: hovered ? Qt.darker(Theme.accent, 1.1) : baseColor
            Icon { anchors.centerIn: parent; d: Icons.arrowDown; size: 16; stroke: 2.2; color: "white" }
            onClicked: { list.stick = true; list.positionViewAtEnd(); }
        }
    }
}
