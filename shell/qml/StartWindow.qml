pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.milou as Milou
import Aster.Shell
import Aster.Ui

// Start: jeden spokojny panel nad dokiem. U góry wyszukiwarka, niżej przypięte programy i ostatnie pliki,
// a „Wszystkie programy” pokazują całą listę z filtrami kategorii. Na dole konto, blokada i zasilanie.
// Po wpisaniu tekstu panel pokazuje wyniki z KRunnera (programy, pliki, ustawienia, kalkulator…).
// Okno-warstwa przykrywa cały ekran nad dokiem: klik obok panelu zamyka Start.
Window {
    id: start
    property bool followsPrimary: true   // po zmianie głównego ekranu main.cpp przenosi okno
    color: "transparent"
    visible: false
    width: Screen.width
    // Okno wypełnia miejsce między górnym paskiem a dokiem (ich rezerwacje)
    height: Screen.height - 32 - 84
    readonly property int shotY: 32
    title: "Start"

    property bool open: false
    property string category: "ulubione"
    readonly property var pinned: [
        "org.aster.files", "org.aster.browser", "org.aster.webapps", "org.aster.editor", "org.aster.terminal",
        "org.aster.store", "org.aster.settings", "org.aster.photos", "org.aster.video", "org.aster.music",
        "org.aster.camera", "org.aster.pdf", "org.aster.calculator"
    ]
    readonly property var pinnedApps: pinned.map(id => Object.assign({ id: id }, Platform.appInfo(id))).filter(a => a.valid)
    property var recents: []
    
    // Kategorie; puste (poza Ulubionymi i Wszystkimi) są ukrywane
    readonly property var allCategories: [
        { id: "ulubione", name: "Ulubione", icon: "star", colors: ["#FFD166", "#F59E0B"] },
        { id: "wszystkie", name: "Wszystkie", icon: "apps", colors: ["#8EA2FF", "#5B5BD6"] },
        { id: "internet", name: "Internet", icon: "globe", colors: ["#4FD1C5", "#3B82F6"] },
        { id: "biuro", name: "Biuro", icon: "doc", colors: ["#60A5FA", "#2563EB"] },
        { id: "grafika", name: "Grafika", icon: "image", colors: ["#F9A8D4", "#C026D3"] },
        { id: "multimedia", name: "Multimedia", icon: "music", colors: ["#FF8A8A", "#E11D48"] },
        { id: "gry", name: "Gry", icon: "game", colors: ["#86EFAC", "#16A34A"] },
        { id: "programowanie", name: "Narzędzia developera", icon: "code", colors: ["#71717A", "#27272A"] },
        { id: "edukacja", name: "Edukacja", icon: "book", colors: ["#FDBA74", "#EA580C"] },
        { id: "narzedzia", name: "Narzędzia", icon: "tool", colors: ["#94A3B8", "#475569"] },
        { id: "system", name: "System", icon: "sliders", colors: ["#A3A9B5", "#4B5262"] },
        { id: "inne", name: "Inne", icon: "folder", colors: ["#67E8F9", "#0891B2"] }
    ]
    readonly property var categories: allCategories.filter(c => c.id === "ulubione" || c.id === "wszystkie"
                                                                || Platform.applications.some(a => a.category === c.id))
    readonly property var currentCategory: categories.find(c => c.id === category) || categories[0]
    readonly property var categoryApps: category === "ulubione" ? pinnedApps
                                       : category === "wszystkie" ? Platform.applications
                                       : Platform.applications.filter(a => a.category === category)

    Component.onCompleted: Platform.makeLayer(start, "overlay", 1 | 2 | 4 | 8, 0, "exclusive", "aster-start")

    function toggle() { if (open) close(); else show(); }
    function show() {
        recents = Platform.recentFiles(4);
        category = "ulubione";
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
    function selectCategory(id) {
        if (id === category) return;
        category = id;
        switchAnim.restart();
    }
    function stepCategory(d) {
        const i = categories.findIndex(c => c.id === category);
        selectCategory(categories[Math.max(0, Math.min(categories.length - 1, i + d))].id);
    }

    // „dziś, 08:16” / „wczoraj, 10:40” / „13 paź”
    function when(d) {
        const loc = Qt.locale("pl_PL");
        const now = new Date();
        const a = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        const b = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const diff = Math.round((b - a) / 86400000);
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
        x: Math.round((start.width - width) / 2)
        y: start.height - height - 94           // warstwa zajmuje cały ekran, a panel stoi nad dokiem
        width: Math.min(720, start.width - 36)
        height: Math.min(590, start.height - 140)

        // Wejście: sprężyste wyrośnięcie znad środka doku (spod przycisku Start), wyjście: szybkie zgaśnięcie
        property real s: 0.92
        property real offset: 14
        property real reveal: 0
        opacity: 0
        transform: [
            Scale { origin.x: panel.width / 2; origin.y: panel.height; xScale: panel.s; yScale: panel.s },
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

        Island { anchors.fill: parent; radius: 30 }

        Item {
            id: main
            width: parent.width; height: parent.height - footer.height

            // Pole wyszukiwania
            Rectangle {
                id: searchBox
                x: 20; y: 18
                width: main.width - 40; height: 46
                radius: 23
                color: field.activeFocus ? Theme.surface : Theme.fill
                border.width: 1
                border.color: field.activeFocus ? Theme.accent : "transparent"
                Behavior on color { ColorAnimation { duration: 140 } }
                Icon {
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    d: Icons.search; size: 18
                    color: field.activeFocus ? Theme.accentText : Theme.text2
                }
                TextInput {
                    id: field
                    anchors.left: parent.left; anchors.leftMargin: 46
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 15
                    selectionColor: Theme.accentSoft
                    selectedTextColor: Theme.text
                    clip: true
                    onTextChanged: list.currentIndex = 0
                    Keys.onEscapePressed: { if (text) text = ""; else start.close(); }
                    // Bez tekstu strzałki przechodzą między kategoriami, z tekstem — między wynikami
                    Keys.onDownPressed: { if (text) list.currentIndex = Math.min(list.count - 1, list.currentIndex + 1); else start.stepCategory(1); }
                    Keys.onUpPressed: { if (text) list.currentIndex = Math.max(0, list.currentIndex - 1); else start.stepCategory(-1); }
                    Keys.onReturnPressed: start.runResult(list.currentIndex)
                    Keys.onEnterPressed: start.runResult(list.currentIndex)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !field.text
                        text: "Szukaj programów, plików i ustawień"
                        color: Theme.text2
                        font: field.font
                    }
                }
            }

            // ——— Programy wybranej kategorii ———
            Item {
                id: browse
                x: 0; y: searchBox.y + searchBox.height + 12
                width: main.width; height: main.height - y
                visible: field.text.trim() === ""
                clip: true

                // Zmiana kategorii: zawartość wjeżdża z prawej
                property real shift: 0
                ParallelAnimation {
                    id: switchAnim
                    NumberAnimation { target: browse; property: "shift"; from: 18; to: 0; duration: 220; easing.type: Easing.OutQuint }
                    NumberAnimation { target: catContent; property: "opacity"; from: 0; to: 1; duration: 140; easing.type: Easing.OutQuad }
                }

                Flickable {
                    id: catContent
                    x: 20 + browse.shift
                    width: browse.width - 40; height: browse.height
                    contentHeight: catColumn.height + 16
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    Column {
                        id: catColumn
                        width: parent.width
                        spacing: 8

                        Item {
                            width: parent.width; height: 30
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: start.category === "ulubione" ? "Przypięte" : "Wszystkie programy"
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                            }
                            Rectangle {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                width: allText.implicitWidth + 20; height: 28; radius: 14
                                color: allArea.containsMouse ? Theme.hover : "transparent"
                                Text {
                                    id: allText
                                    anchors.centerIn: parent
                                    text: start.category === "ulubione" ? "Wszystkie programy" : "Przypięte"
                                    color: Theme.text2
                                    font.family: Theme.font; font.pixelSize: 13
                                }
                                MouseArea {
                                    id: allArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: { start.selectCategory(start.category === "ulubione" ? "wszystkie" : "ulubione"); field.forceActiveFocus(); }
                                }
                            }
                        }

                        // Filtry kategorii
                        Flow {
                            width: parent.width
                            spacing: 6
                            visible: start.category !== "ulubione"
                            Repeater {
                                model: start.categories.filter(c => c.id !== "ulubione")
                                delegate: Rectangle {
                                    id: chip
                                    required property var modelData
                                    readonly property bool active: start.category === modelData.id
                                    width: chipText.implicitWidth + 24; height: 30; radius: 15
                                    color: active ? Theme.accent : chipArea.containsMouse ? Theme.hover : Theme.fill
                                    Text {
                                        id: chipText
                                        anchors.centerIn: parent
                                        text: chip.modelData.name
                                        color: chip.active ? "white" : Theme.text
                                        font.family: Theme.font; font.pixelSize: 12
                                    }
                                    MouseArea {
                                        id: chipArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: { start.selectCategory(chip.modelData.id); field.forceActiveFocus(); }
                                    }
                                }
                            }
                        }

                        Grid {
                            columns: 6
                            Repeater {
                                model: start.category === "ulubione" ? start.categoryApps.slice(0, 12) : start.categoryApps
                                delegate: Item {
                                    id: tile
                                    required property var modelData
                                    required property int index
                                    readonly property real k: panel.stagger(3 + Math.min(index, 14))
                                    width: catColumn.width / 6; height: 88
                                    opacity: k
                                    transform: Translate { y: (1 - tile.k) * 10 }
                                    Rectangle {
                                        anchors.fill: parent; anchors.margins: 2
                                        radius: 18
                                        color: Theme.hover
                                        opacity: tileArea.containsMouse ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 120 } }
                                    }
                                    AppIcon {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 9
                                        size: 46
                                        desktopId: tile.modelData.id
                                        source: tile.modelData.icon
                                        scale: tileArea.pressed ? 0.92 : 1
                                        Behavior on scale { NumberAnimation { duration: 120 } }
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 62
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

                        // Ostatnie pliki
                        Rectangle { width: parent.width; height: 1; color: Theme.line; visible: recentsTitle.visible }
                        Text {
                            id: recentsTitle
                            topPadding: 4
                            visible: start.category === "ulubione" && start.recents.length > 0
                            text: "Ostatnie"
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        }
                        Column {
                            width: parent.width
                            visible: recentsTitle.visible
                            Repeater {
                                model: start.category === "ulubione" ? start.recents : []
                                delegate: Rectangle {
                                    id: rec
                                    required property var modelData
                                    width: catColumn.width; height: 40
                                    radius: 8
                                    color: recArea.containsMouse ? Theme.hover : "transparent"
                                    Kirigami.Icon {
                                        x: 8; anchors.verticalCenter: parent.verticalCenter
                                        width: 24; height: 24
                                        source: rec.modelData.icon
                                    }
                                    Text {
                                        x: 42; anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - x - dateLabel.implicitWidth - 20
                                        text: rec.modelData.name
                                        elide: Text.ElideMiddle
                                        color: Theme.text
                                        font.family: Theme.font; font.pixelSize: 13
                                    }
                                    Text {
                                        id: dateLabel
                                        anchors.right: parent.right; anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: start.when(rec.modelData.modified)
                                        color: Theme.text2
                                        font.family: Theme.font; font.pixelSize: 12
                                    }
                                    MouseArea {
                                        id: recArea; anchors.fill: parent; hoverEnabled: true
                                        onClicked: { Platform.openUrl(rec.modelData.url); start.close(); }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ——— Wyniki wyszukiwania ———
            ListView {
                id: list
                x: 16
                y: searchBox.y + searchBox.height + 12
                width: main.width - 32
                height: main.height - y - 14
                visible: !browse.visible
                clip: true
                model: results
                currentIndex: 0
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                section.property: "category"
                section.delegate: Text {
                    required property string section
                    leftPadding: 12; topPadding: 12; bottomPadding: 4
                    text: section
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                }
                delegate: Rectangle {
                    id: res
                    required property int index
                    required property var model
                    readonly property bool current: ListView.isCurrentItem
                    width: list.width; height: 48
                    radius: 8
                    color: current ? Theme.accent : (resArea.containsMouse ? Theme.hover : "transparent")
                    Kirigami.Icon {
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        width: 32; height: 32
                        source: res.model.decoration
                    }
                    Column {
                        x: 56; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 68
                        spacing: 1
                        Text { width: parent.width; text: res.model.display || ""; color: res.current ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium; elide: Text.ElideRight }
                        Text { width: parent.width; visible: text !== ""; text: res.model.subtext || ""; color: res.current ? Qt.rgba(1, 1, 1, 0.75) : Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.letterSpacing: 0.1; elide: Text.ElideMiddle }
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
        }

        // Konto, blokada, wyłączanie
        Rectangle {
            id: footer
            anchors.bottom: parent.bottom
            width: parent.width; height: 54
            bottomLeftRadius: 30; bottomRightRadius: 30
            color: Theme.windowGlass
            Rectangle { width: parent.width; height: 1; color: Theme.line }
            Rectangle {
                id: avatar
                x: 20; anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30; radius: 15
                color: Theme.accent
                Text {
                    anchors.centerIn: parent
                    text: Platform.userName.charAt(0).toUpperCase()
                    color: "white"
                    font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                }
            }
            Text {
                anchors.left: avatar.right; anchors.leftMargin: 10
                anchors.right: footerButtons.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: Platform.userName
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
            }
            Row {
                id: footerButtons
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                FooterButton { icon: "lock"; tip: "Zablokuj"; onClicked: { start.close(); Platform.lockScreen(); } }
                FooterButton { icon: "power"; tip: "Wyłącz"; onClicked: { start.close(); Platform.shutdownPrompt(); } }
            }
        }
    }

    component FooterButton: Rectangle {
        id: fb
        property string icon
        property string tip
        signal clicked()
        width: 36; height: 36; radius: 18
        color: fbArea.containsMouse ? Theme.hover : Theme.fill
        scale: fbArea.pressed ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
        Icon { anchors.centerIn: parent; d: Icons[fb.icon] || ""; size: 17; color: Theme.text2 }
        MouseArea { id: fbArea; anchors.fill: parent; hoverEnabled: true; onClicked: fb.clicked() }
        // Podpis nad przyciskiem
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: -height - 8
            width: tipText.implicitWidth + 16; height: 24; radius: 12
            color: Qt.rgba(0.08, 0.08, 0.1, 0.92)
            opacity: fbArea.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            Text { id: tipText; anchors.centerIn: parent; text: fb.tip; color: "white"; font.family: Theme.font; font.pixelSize: 11; font.letterSpacing: 0.1; font.weight: Font.Medium }
        }
    }

    Timer {
        id: blurTimer
        interval: 20
        onTriggered: Platform.setBlur(start, [{ x: panel.x, y: panel.y, w: panel.width, h: panel.height, r: 16 }])
    }
}
