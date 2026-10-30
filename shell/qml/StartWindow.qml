pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.milou as Milou
import Aster.Shell
import Aster.Ui

// Start w dwóch panelach (jak szuflada Smart Launchera):
//  lewy  — logo Aster, kategorie programów, na dole konto, blokada i wyłączanie
//  prawy — wyszukiwarka i programy wybranej kategorii („Ulubione” mają też ostatnie pliki).
// Po wpisaniu tekstu prawy panel pokazuje wyniki z KRunnera (programy, pliki, ustawienia, kalkulator…).
// Okno-warstwa przykrywa cały ekran nad dokiem: klik obok panelu zamyka Start.
Window {
    id: start
    color: "transparent"
    visible: false
    width: Screen.width
    height: Screen.height - 84
    title: "Start"

    property bool open: false
    property string category: "ulubione"
    readonly property var pinned: [
        "org.aster.files", "org.aster.browser", "org.aster.webapps", "org.kde.kate", "org.kde.konsole",
        "org.kde.discover", "systemsettings", "org.kde.okular", "org.kde.gwenview",
        "org.kde.elisa", "org.kde.spectacle", "org.kde.kcalc"
    ]
    readonly property var pinnedApps: pinned.map(id => Object.assign({ id: id }, Platform.appInfo(id))).filter(a => a.valid)
    property var recents: []

    // Kategorie; puste (poza Ulubionymi i Wszystkimi) są ukrywane
    readonly property var allCategories: [
        { id: "ulubione", name: "Ulubione", icon: "star" },
        { id: "wszystkie", name: "Wszystkie", icon: "apps" },
        { id: "internet", name: "Internet", icon: "globe" },
        { id: "biuro", name: "Biuro", icon: "doc" },
        { id: "grafika", name: "Grafika", icon: "image" },
        { id: "multimedia", name: "Multimedia", icon: "music" },
        { id: "gry", name: "Gry", icon: "game" },
        { id: "programowanie", name: "Programowanie", icon: "code" },
        { id: "edukacja", name: "Edukacja", icon: "book" },
        { id: "narzedzia", name: "Narzędzia", icon: "tool" },
        { id: "system", name: "System", icon: "sliders" },
        { id: "inne", name: "Inne", icon: "folder" }
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
        x: 16
        y: start.height - height - 12
        width: Math.min(780, start.width - 32)
        height: Math.min(600, start.height - 70)

        // Wejście: sprężyste wyrośnięcie od lewego dolnego rogu, wyjście: szybkie zgaśnięcie
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

        // ——— Lewy panel: logo, kategorie, konto ———
        Rectangle {
            id: side
            width: 220; height: parent.height
            topLeftRadius: 22; bottomLeftRadius: 22
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.035)
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }

            // Logo
            Row {
                x: 20; y: 22
                spacing: 12
                opacity: panel.stagger(0)
                Rectangle {
                    width: 40; height: 40; radius: 12
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.accent }
                        GradientStop { position: 1; color: "#8B5CF6" }
                    }
                    Icon { anchors.centerIn: parent; d: Icons.aster; size: 22; stroke: 2.4; color: "white" }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Aster"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 21; font.weight: Font.DemiBold
                    font.letterSpacing: -0.3
                }
            }

            // Kategorie
            ListView {
                id: catList
                x: 10; y: 86
                width: parent.width - 20
                height: sideFooter.y - y - 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: 2
                model: start.categories
                delegate: Rectangle {
                    id: cat
                    required property var modelData
                    required property int index
                    readonly property bool active: start.category === modelData.id
                    readonly property real k: panel.stagger(1 + index)
                    width: catList.width; height: 38
                    radius: 10
                    color: active ? Theme.accentSoft : (catArea.containsMouse ? Theme.hover : "transparent")
                    opacity: k
                    transform: Translate { x: (1 - cat.k) * -10 }
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Icon {
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        d: Icons[cat.modelData.icon] || ""
                        size: 18
                        color: cat.active ? Theme.accentText : Theme.text2
                    }
                    Text {
                        x: 42; anchors.verticalCenter: parent.verticalCenter
                        text: cat.modelData.name
                        color: cat.active ? Theme.accentText : Theme.text
                        font.family: Theme.font; font.pixelSize: 14
                        font.weight: cat.active ? Font.DemiBold : Font.Normal
                    }
                    MouseArea {
                        id: catArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { start.selectCategory(cat.modelData.id); field.text = ""; field.forceActiveFocus(); }
                    }
                }
            }

            // Konto, blokada, wyłączanie
            Item {
                id: sideFooter
                width: parent.width; height: 64
                y: parent.height - height
                Rectangle { x: 16; width: parent.width - 32; height: 1; color: Theme.line }
                Rectangle {
                    id: avatar
                    x: 18; anchors.verticalCenter: parent.verticalCenter
                    width: 32; height: 32; radius: 16
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
                    anchors.right: footerButtons.left; anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: Platform.userName
                    elide: Text.ElideRight
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                }
                Row {
                    id: footerButtons
                    anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    FooterButton { icon: "lock"; onClicked: { start.close(); Platform.lockScreen(); } }
                    FooterButton { icon: "power"; onClicked: { start.close(); Platform.shutdownPrompt(); } }
                }
            }
        }

        // ——— Prawy panel ———
        Item {
            id: main
            x: side.width; width: parent.width - side.width; height: parent.height

            // Pole wyszukiwania
            Rectangle {
                id: searchBox
                x: 22; y: 22
                width: main.width - 44; height: 44
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
                Icon {
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    d: Icons.search; size: 18
                    color: field.activeFocus ? Theme.accentText : Theme.text2
                }
                TextInput {
                    id: field
                    anchors.left: parent.left; anchors.leftMargin: 44
                    anchors.right: parent.right; anchors.rightMargin: 14
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
                x: 0; y: searchBox.y + searchBox.height + 14
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
                    x: 22 + browse.shift
                    width: browse.width - 44; height: browse.height
                    contentHeight: catColumn.height + 16
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    Column {
                        id: catColumn
                        width: parent.width
                        spacing: 10

                        Row {
                            spacing: 10
                            Text {
                                id: catTitle
                                text: start.currentCategory.name
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 19; font.weight: Font.DemiBold
                            }
                            Text {
                                anchors.baseline: catTitle.baseline
                                text: start.categoryApps.length + ""
                                visible: start.category !== "ulubione"
                                color: Theme.text2
                                font.family: Theme.font; font.pixelSize: 14
                            }
                        }

                        Grid {
                            columns: 5
                            Repeater {
                                model: start.categoryApps
                                delegate: Rectangle {
                                    id: tile
                                    required property var modelData
                                    required property int index
                                    readonly property real k: panel.stagger(3 + Math.min(index, 14))
                                    width: catColumn.width / 5; height: 100
                                    radius: 14
                                    color: tileArea.containsMouse ? Theme.hover : "transparent"
                                    opacity: k
                                    transform: Translate { y: (1 - tile.k) * 12 }
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Kirigami.Icon {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 12
                                        width: 50; height: 50
                                        source: tile.modelData.icon
                                        scale: tileArea.pressed ? 0.92 : 1
                                        Behavior on scale { NumberAnimation { duration: 100 } }
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 70
                                        width: parent.width - 10
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

                        // Ulubione: ostatnie pliki pod programami
                        Item { width: 1; height: 4; visible: recentsTitle.visible }
                        Text {
                            id: recentsTitle
                            visible: start.category === "ulubione" && start.recents.length > 0
                            text: "Ostatnie pliki"
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                        }
                        Grid {
                            columns: 2
                            visible: recentsTitle.visible
                            Repeater {
                                model: start.category === "ulubione" ? start.recents : []
                                delegate: Rectangle {
                                    id: rec
                                    required property var modelData
                                    required property int index
                                    width: catColumn.width / 2; height: 54
                                    radius: 12
                                    color: recArea.containsMouse ? Theme.hover : "transparent"
                                    Kirigami.Icon {
                                        x: 10; anchors.verticalCenter: parent.verticalCenter
                                        width: 30; height: 30
                                        source: rec.modelData.icon
                                    }
                                    Column {
                                        x: 50; anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 60
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
                }
            }

            // ——— Wyniki wyszukiwania ———
            ListView {
                id: list
                x: 14
                y: searchBox.y + searchBox.height + 10
                width: main.width - 28
                height: main.height - y - 12
                visible: !browse.visible
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
        }
    }

    component FooterButton: Rectangle {
        id: fb
        property string icon
        signal clicked()
        width: 34; height: 34; radius: 10
        color: fbArea.containsMouse ? Theme.hover : "transparent"
        scale: fbArea.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
        Icon { anchors.centerIn: parent; d: Icons[fb.icon] || ""; size: 17; color: Theme.text2 }
        MouseArea { id: fbArea; anchors.fill: parent; hoverEnabled: true; onClicked: fb.clicked() }
    }

    Timer {
        id: blurTimer
        interval: 20
        onTriggered: Platform.setBlur(start, [{ x: panel.x, y: panel.y, w: panel.width, h: panel.height, r: 22 }])
    }
}
