pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.milou as Milou
import Aster.Shell
import Aster.Ui

// Start = wyszukiwarka. Puste pole: przypięte aplikacje i ostatnie pliki.
// Po wpisaniu tekstu: wyniki z KRunnera (aplikacje, pliki, ustawienia, kalkulator…).
// Okno-warstwa przykrywa cały ekran nad dokiem: klik obok panelu zamyka Start.
Window {
    id: start
    color: "transparent"
    visible: false
    width: Screen.width
    height: Screen.height - 84
    title: "Start"

    property bool open: false
    readonly property var pinned: [
        "org.aster.files", "org.mozilla.firefox", "org.kde.kate", "org.kde.konsole",
        "org.kde.discover", "systemsettings", "org.kde.okular", "org.kde.gwenview",
        "org.kde.elisa", "org.kde.spectacle", "org.kde.kcalc", "org.kde.ark"
    ]
    readonly property var pinnedApps: pinned.map(id => Object.assign({ id: id }, Platform.appInfo(id))).filter(a => a.valid)
    property var recents: []

    Component.onCompleted: Platform.makeLayer(start, "overlay", 1 | 2 | 4 | 8, 0, "exclusive", "aster-start")

    function toggle() { if (open) close(); else show(); }
    function show() {
        recents = Platform.recentFiles(6);
        field.text = "";
        hideTimer.stop();
        visible = true;
        open = true;
        field.forceActiveFocus();
        blurTimer.restart();
    }
    function close() {
        if (!open) return;
        open = false;
        hideTimer.restart();
    }
    Timer { id: hideTimer; interval: 110; onTriggered: start.visible = false }

    function launch(id) { Platform.launchApp(id); close(); }
    function runResult(i) {
        if (i >= 0 && i < list.count && results.run(results.index(i, 0))) close();
    }

    // „dziś, 08:16” / „wczoraj, 10:40” / „13 paź”
    function when(d) {
        const loc = Qt.locale("pl_PL");
        const now = new Date();
        const day = 24 * 3600 * 1000;
        const a = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        const b = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const diff = Math.round((b - a) / day);
        if (diff === 0) return "dziś, " + d.toLocaleTimeString(loc, "HH:mm");
        if (diff === 1) return "wczoraj, " + d.toLocaleTimeString(loc, "HH:mm");
        return d.toLocaleDateString(loc, "d MMM");
    }

    Milou.ResultsModel {
        id: results
        queryString: field.text.trim()
        limit: 24
    }

    // Klik obok panelu
    MouseArea { anchors.fill: parent; onClicked: start.close() }

    // ——— Panel ———
    Item {
        id: panel
        x: 16
        y: start.height - height - 12
        width: 680
        height: Math.min(640, start.height - 70)

        // Wejście: sprężyste wyrośnięcie od lewego dolnego rogu (jak w prototypie), wyjście: szybkie zgaśnięcie
        property real s: 0.92
        property real offset: 14
        property real reveal: 0
        opacity: 0
        transform: [
            Scale { origin.x: 0; origin.y: panel.height; xScale: panel.s; yScale: panel.s },
            Translate { y: panel.offset }
        ]
        states: State {
            name: "shown"; when: start.open
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
        // Postęp wejścia i-tego elementu (kaskada)
        function stagger(i) { return Math.max(0, Math.min(1, (reveal - i * 0.022) / 0.40)); }

        MouseArea { anchors.fill: parent }   // kliknięcia w panel nie zamykają Startu

        RectangularShadow {
            anchors.fill: parent
            radius: 22; blur: 70; offset.y: 24
            color: Theme.shadow
        }
        Rectangle {
            anchors.fill: parent
            radius: 22
            color: Theme.glass
            border.width: 1; border.color: Theme.edge
            Rectangle {
                anchors.fill: parent; anchors.margins: 1
                radius: 21
                color: "transparent"
                border.width: 1; border.color: Theme.rim
            }
        }

        // ——— Pole wyszukiwania ———
        Rectangle {
            id: searchBox
            x: 22; y: 22
            width: panel.width - 44; height: 48
            radius: 12
            color: Theme.surface
            border.width: field.activeFocus ? 1.5 : 1
            border.color: field.activeFocus ? Theme.accent : Theme.line
            Rectangle {
                anchors.fill: parent; anchors.margins: -4
                radius: 15
                color: "transparent"
                border.width: 4; border.color: Qt.rgba(52 / 255, 86 / 255, 232 / 255, 0.14)
                visible: field.activeFocus
            }
            Kirigami.Icon {
                x: 14; anchors.verticalCenter: parent.verticalCenter
                width: 20; height: 20
                source: "search"
                color: field.activeFocus ? Theme.accentText : Theme.text2
                isMask: true
            }
            TextInput {
                id: field
                anchors.left: parent.left; anchors.leftMargin: 46
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16
                selectionColor: Theme.accentSoft
                selectedTextColor: Theme.text
                clip: true
                onTextChanged: list.currentIndex = 0
                Keys.onEscapePressed: start.close()
                Keys.onDownPressed: if (list.visible) list.currentIndex = Math.min(list.count - 1, list.currentIndex + 1)
                Keys.onUpPressed: if (list.visible) list.currentIndex = Math.max(0, list.currentIndex - 1)
                Keys.onReturnPressed: start.runResult(list.currentIndex)
                Keys.onEnterPressed: start.runResult(list.currentIndex)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !field.text
                    text: "Aplikacje, pliki, ustawienia — wpisz, czego szukasz"
                    color: Theme.text2
                    font: field.font
                }
            }
        }

        // ——— Pusty Start: przypięte i ostatnie ———
        Column {
            id: home
            x: 22
            y: searchBox.y + searchBox.height + 18
            width: panel.width - 44
            spacing: 14
            visible: field.text.trim() === ""

            Text { text: "Przypięte"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold }
            Grid {
                columns: 6
                columnSpacing: 0
                rowSpacing: 4
                Repeater {
                    model: start.pinnedApps
                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property real k: panel.stagger(index)
                        width: home.width / 6; height: 96
                        radius: 14
                        color: tileArea.containsMouse ? Theme.hover : "transparent"
                        opacity: k
                        transform: Translate { y: (1 - tile.k) * 12 }
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Kirigami.Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 12
                            width: 48; height: 48
                            source: tile.modelData.icon
                            scale: tileArea.pressed ? 0.92 : 1
                            Behavior on scale { NumberAnimation { duration: 100 } }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 68
                            width: parent.width - 8
                            horizontalAlignment: Text.AlignHCenter
                            text: tile.modelData.name
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        MouseArea { id: tileArea; anchors.fill: parent; hoverEnabled: true; onClicked: start.launch(tile.modelData.id) }
                    }
                }
            }

            Item { width: 1; height: 4 }
            Text {
                visible: start.recents.length > 0
                text: "Ostatnie"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
            }
            Grid {
                columns: 2
                Repeater {
                    model: start.recents
                    delegate: Rectangle {
                        id: rec
                        required property var modelData
                        required property int index
                        readonly property real k: panel.stagger(12 + index)
                        width: home.width / 2; height: 56
                        radius: 12
                        color: recArea.containsMouse ? Theme.hover : "transparent"
                        opacity: k
                        transform: Translate { y: (1 - rec.k) * 12 }
                        Kirigami.Icon {
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32
                            source: rec.modelData.icon
                        }
                        Column {
                            x: 54; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 64
                            Text { width: parent.width; text: rec.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideMiddle }
                            Text { text: start.when(rec.modelData.modified); color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
                        }
                        MouseArea {
                            id: recArea; anchors.fill: parent; hoverEnabled: true
                            onClicked: { Platform.openUrl(rec.modelData.url); start.close(); }
                        }
                    }
                }
            }
        }

        // ——— Wyniki wyszukiwania ———
        ListView {
            id: list
            x: 14
            y: searchBox.y + searchBox.height + 12
            width: panel.width - 28
            height: footer.y - y - 8
            visible: !home.visible
            clip: true
            model: results
            currentIndex: 0
            boundsBehavior: Flickable.StopAtBounds
            highlightMoveDuration: 0
            section.property: "category"
            section.delegate: Text {
                required property string section
                leftPadding: 10; topPadding: 10; bottomPadding: 4
                text: section
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
            }
            delegate: Rectangle {
                id: res
                required property int index
                required property var model
                width: list.width; height: 52
                radius: 12
                color: ListView.isCurrentItem ? Theme.accentSoft : (resArea.containsMouse ? Theme.hover : "transparent")
                Kirigami.Icon {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30
                    source: res.model.decoration
                }
                Column {
                    x: 54; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 66
                    Text { width: parent.width; text: res.model.display || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium; elide: Text.ElideRight }
                    Text { width: parent.width; visible: text !== ""; text: res.model.subtext || ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; elide: Text.ElideMiddle }
                }
                MouseArea {
                    id: resArea; anchors.fill: parent; hoverEnabled: true
                    onClicked: start.runResult(res.index)
                }
            }
            Text {
                anchors.centerIn: parent
                visible: list.count === 0 && !results.querying
                text: "Nic nie znaleziono"
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 14
            }
        }

        // ——— Stopka: użytkownik, blokada, wyłączanie ———
        Item {
            id: footer
            x: 0; y: panel.height - height
            width: panel.width; height: 64
            Rectangle { width: parent.width; height: 1; color: Theme.line }
            Rectangle {
                x: 22; anchors.verticalCenter: parent.verticalCenter
                width: 34; height: 34; radius: 17
                color: Theme.accent
                Text {
                    anchors.centerIn: parent
                    text: Platform.userName.charAt(0).toUpperCase()
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                }
            }
            Text {
                x: 66; anchors.verticalCenter: parent.verticalCenter
                text: Platform.userName
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                FooterButton { icon: "system-lock-screen"; onClicked: { start.close(); Platform.lockScreen(); } }
                FooterButton { icon: "system-shutdown"; onClicked: { start.close(); Platform.shutdownPrompt(); } }
            }
        }
    }

    component FooterButton: Rectangle {
        id: fb
        property string icon
        signal clicked()
        width: 40; height: 40; radius: 12
        color: fbArea.containsMouse ? Theme.hover : "transparent"
        scale: fbArea.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
        Kirigami.Icon {
            anchors.centerIn: parent
            width: 20; height: 20
            source: fb.icon
            color: Theme.text
            isMask: true
        }
        MouseArea { id: fbArea; anchors.fill: parent; hoverEnabled: true; onClicked: fb.clicked() }
    }

    Timer {
        id: blurTimer
        interval: 20
        onTriggered: Platform.setBlur(start, [{ x: panel.x, y: panel.y, w: panel.width, h: panel.height, r: 22 }])
    }
}
