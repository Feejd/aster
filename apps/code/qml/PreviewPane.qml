pragma ComponentBehavior: Bound
import QtQuick
import QtWebEngine
import Aster.Ui
import Aster.Code

// Podgląd strony obok edytora (jak Simple Browser w VS Code): adres serwera deweloperskiego otwiera się
// sam, gdy zadanie go zgłosi; po zapisie pliku strona się przeładowuje. Przełącznik telefon / komputer
// (szerokość 390 px i przeglądarka telefonu), konsola przeglądarki z błędami i komunikatami console.log.
Rectangle {
    id: pv
    property bool shown: false
    property string url
    property bool phone: false
    property bool consoleOpen: false
    property var messages: []          // [{ level: 0 info | 1 ostrzeżenie | 2 błąd, text, source }]
    readonly property int errorCount: messages.filter(m => m.level === 2).length
    signal closed()

    visible: shown
    color: Theme.dark ? "#101114" : "#F3F4F6"

    function open(u) {
        if (u) url = u;
        shown = true;
        if (u && view.url.toString() !== u) { messages = []; view.url = u; }
    }
    function close() { shown = false; closed(); }
    function reload() { if (shown && view.url.toString()) reloadTimer.restart(); }
    // Zapis kilku plików naraz — jedno przeładowanie
    Timer { id: reloadTimer; interval: 350; onTriggered: view.reload() }

    readonly property string mobileAgent: "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36"
    property string desktopAgent: ""
    onPhoneChanged: {
        if (!desktopAgent) desktopAgent = view.profile.httpUserAgent;
        view.profile.httpUserAgent = phone ? mobileAgent : desktopAgent;
        view.reload();
    }

    // ——— Pasek ———
    Rectangle {
        id: bar
        width: parent.width; height: 44
        color: Theme.surface
        Row {
            id: navBtns
            x: 8; anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Btn { icon: "back"; enabled: view.canGoBack; onClicked: view.goBack() }
            Btn { icon: "forward"; enabled: view.canGoForward; onClicked: view.goForward() }
            Btn { icon: view.loading ? "close" : "reload"; onClicked: view.loading ? view.stop() : view.reload() }
        }
        Rectangle {
            anchors.left: navBtns.right; anchors.leftMargin: 6
            anchors.right: rightBtns.left; anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            height: 30; radius: 8
            color: Theme.fill
            border.width: addr.activeFocus ? 1.5 : 0; border.color: Theme.accent
            Rectangle {
                visible: view.loading
                anchors.bottom: parent.bottom; x: 4
                width: (parent.width - 8) * view.loadProgress / 100; height: 2; radius: 1
                color: Theme.accent
            }
            TextInput {
                id: addr
                x: 10; width: parent.width - 20
                anchors.verticalCenter: parent.verticalCenter
                text: view.url.toString()
                color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                font.family: Theme.font; font.pixelSize: 12
                clip: true
                selectByMouse: true
                onAccepted: { const t = text.trim(); view.url = /^[a-z]+:\/\//.test(t) ? t : "http://" + t; view.forceActiveFocus(); }
            }
        }
        Row {
            id: rightBtns
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Btn { icon: pv.phone ? "monitor" : "phone"; on: pv.phone; onClicked: pv.phone = !pv.phone }
            Btn {
                icon: "terminal"; on: pv.consoleOpen
                onClicked: pv.consoleOpen = !pv.consoleOpen
                Rectangle {
                    visible: pv.errorCount > 0
                    anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 1
                    width: Math.max(14, ec.implicitWidth + 6); height: 14; radius: 7
                    color: Theme.danger
                    Text { id: ec; anchors.centerIn: parent; text: pv.errorCount; color: "white"; font.family: Theme.font; font.pixelSize: 9; font.weight: Font.Bold }
                }
            }
            Btn { icon: "external"; onClicked: Qt.openUrlExternally(view.url) }
            Btn { icon: "close"; onClicked: pv.close() }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
    }

    // ——— Strona ———
    Item {
        id: stage
        y: bar.height
        width: parent.width
        height: parent.height - bar.height - (pv.consoleOpen ? consoleBox.height : 0)
        clip: true
        // Telefon: ekran 390×844 (pomniejszony, gdy się nie mieści) w ramce
        Rectangle {
            id: frame
            readonly property real s: pv.phone ? Math.min(1, (stage.width - 32) / 414, (stage.height - 32) / 868) : 1
            anchors.centerIn: parent
            width: pv.phone ? 414 : stage.width
            height: pv.phone ? 868 : stage.height
            scale: s
            radius: pv.phone ? 44 : 0
            color: pv.phone ? (Theme.dark ? "#2A2C33" : "#1E2128") : "transparent"
            WebEngineView {
                id: view
                anchors.fill: parent
                anchors.margins: pv.phone ? 12 : 0
                onJavaScriptConsoleMessage: (level, message, lineNumber, sourceID) => {
                    const src = String(sourceID).replace(/^https?:\/\/[^/]+/, "");
                    pv.messages = pv.messages.concat([{ level: level, text: message, source: src ? src + ":" + lineNumber : "" }]).slice(-500);
                }
                onLoadingChanged: (info) => {
                    if (info.status === WebEngineView.LoadStartedStatus) pv.messages = [];
                    else if (info.status === WebEngineView.LoadFailedStatus)
                        pv.messages = pv.messages.concat([{ level: 2, text: "Nie udało się wczytać strony: " + info.errorString, source: "" }]);
                }
                onNewWindowRequested: (req) => Qt.openUrlExternally(req.requestedUrl)
            }
            // Zaokrąglone rogi ekranu telefonu
            Rectangle {
                visible: pv.phone
                anchors.fill: view
                color: "transparent"
                radius: 34
                border.width: 0
            }
        }
        Column {
            visible: !view.url.toString()
            anchors.centerIn: parent
            spacing: 8
            Icon { anchors.horizontalCenter: parent.horizontalCenter; d: Icons.globe; size: 30; stroke: 1.5; color: Theme.text2; opacity: 0.6 }
            Text {
                horizontalAlignment: Text.AlignHCenter
                text: "Uruchom serwer (przycisk ▶ albo Ctrl+F5) —\npodgląd otworzy się sam. Albo wpisz adres u góry."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
            }
        }
    }

    // ——— Konsola ———
    Rectangle {
        id: consoleBox
        visible: pv.consoleOpen
        anchors.bottom: parent.bottom
        width: parent.width; height: Math.max(120, parent.height * 0.32)
        color: Theme.surface
        Rectangle { width: parent.width; height: 1; color: Theme.line }
        Text {
            id: ctitle
            x: 12; y: 8
            text: "KONSOLA · " + pv.messages.length
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4
        }
        HoverButton {
            anchors.right: parent.right; anchors.rightMargin: 8; y: 3
            width: 24; height: 24; radius: 6
            onClicked: pv.messages = []
            Icon { anchors.centerIn: parent; d: Icons.trash; size: 12; color: Theme.text2 }
        }
        ListView {
            id: clist
            x: 8; y: ctitle.y + ctitle.height + 6
            width: parent.width - 16; height: parent.height - y - 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: pv.messages
            onCountChanged: Qt.callLater(clist.positionViewAtEnd)
            delegate: Rectangle {
                id: msg
                required property var modelData
                width: ListView.view.width; height: mt.implicitHeight + 8
                radius: 5
                color: modelData.level === 2 ? Qt.rgba(0.9, 0.28, 0.3, Theme.dark ? 0.14 : 0.08)
                     : modelData.level === 1 ? Qt.rgba(0.85, 0.6, 0.1, Theme.dark ? 0.14 : 0.08) : "transparent"
                Text {
                    id: mt
                    x: 6; y: 4
                    width: parent.width - 12 - srcText.implicitWidth - 10
                    wrapMode: Text.WrapAnywhere
                    text: msg.modelData.text
                    color: msg.modelData.level === 2 ? Theme.danger : msg.modelData.level === 1 ? (Theme.dark ? "#E3B341" : "#9A6700") : Theme.text
                    font.family: "JetBrains Mono"; font.pixelSize: 12
                }
                Text {
                    id: srcText
                    anchors.right: parent.right; anchors.rightMargin: 6; y: 4
                    text: msg.modelData.source
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                }
            }
        }
    }

    component Btn: HoverButton {
        id: b
        property string icon
        property bool on: false
        width: 30; height: 30; radius: 8
        baseColor: on ? Theme.accentSoft : "transparent"
        opacity: enabled ? 1 : 0.35
        Icon { anchors.centerIn: parent; d: Icons[b.icon] || ""; size: 15; color: b.on ? Theme.accentText : Theme.text2 }
    }
}
