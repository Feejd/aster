pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Dialogs
import Aster.Ui
import Aster.Grafika

// Ekran startowy: nowy projekt w gotowym rozmiarze, własne projekty (zapisane same), szablony z kategoriami
Item {
    id: sp
    property var app                // Main: newProject, fromTemplate, openProject, presets
    property real radius: 12
    property string category: ""
    property string group: ""                  // rozmiary: "" | social | print | screen
    property string query: ""                  // wyszukiwanie szablonów i projektów
    property bool allProjects: false
    readonly property var groups: [
        { id: "", label: "Wszystkie" }, { id: "social", label: "Media społecznościowe" },
        { id: "print", label: "Do druku" }, { id: "screen", label: "Prezentacje i wideo" }
    ]
    readonly property var groupColors: ({ social: ["#FF7A8A", "#8A5CF6"], print: ["#2BB3A3", "#2F7DE1"], screen: ["#FFB547", "#F2545B"] })
    function matches(t) { return query === "" || t.toLowerCase().indexOf(query.toLowerCase()) >= 0; }
    readonly property var foundProjects: Library.projects.filter(p => matches(p.name))
    readonly property var foundTemplates: Library.templates.filter(t => (query !== "" || category === "" || t.category === category)
                                                                       && (matches(t.name) || matches(t.category || "")))

    readonly property var categories: {
        const out = [];
        for (const t of Library.templates) if (t.category && out.indexOf(t.category) < 0) out.push(t.category);
        return out;
    }

    function openCustom() { customPop.openAt(customCard, "below"); widthField.value = 1200; heightField.value = 800; }

    FileDialog {
        id: openDialog
        title: "Otwórz projekt"
        nameFilters: ["Projekty graficzne (*.grafika)", "Wszystkie pliki (*)"]
        onAccepted: sp.app.openProject(Library.toPath(String(selectedFile)))
    }


    // ——— Pasek tytułu ———
    Item {
        id: topBar
        width: parent.width; height: 64
        DragHandler { target: null; onActiveChanged: if (active) sp.Window.window.startSystemMove() }
        TapHandler { onDoubleTapped: { const w = sp.Window.window; if (w.visibility === Window.Maximized) w.showNormal(); else w.showMaximized(); } }
        Row {
            x: 24; anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            AppIcon { anchors.verticalCenter: parent.verticalCenter; desktopId: "org.aster.grafika"; size: 30 }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Aster Pixel"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 20; font.weight: Font.Bold; font.letterSpacing: -0.4
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            SearchField {
                id: search
                color: Theme.surface
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(340, sp.width - 520)
                visible: width > 160
                delay: 200
                placeholder: "Szukaj szablonów i projektów"
                onSearch: (t) => sp.query = t
            }
            Btn { anchors.verticalCenter: parent.verticalCenter; height: 40; baseColor: Theme.surface; text: "Otwórz plik…"; icon: "folder"; onClicked: openDialog.open() }
            WindowButtons { anchors.verticalCenter: parent.verticalCenter; window: sp.app }
        }
    }

    Flickable {
        id: scroll
        y: topBar.height
        width: parent.width
        height: parent.height - y
        contentHeight: content.height + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            x: 32
            width: scroll.width - 64
            spacing: 18

            Column {
                spacing: 6
                Text {
                    text: "Co dziś tworzysz?"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 36; font.weight: Font.Bold; font.letterSpacing: -1.2
                    font.variableAxes: { "opsz": 32 }
                }
                Text {
                    text: "Wybierz rozmiar albo gotowy szablon. Projekty zapisują się same — możesz w każdej chwili wrócić."
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: 14
                }
            }

            // ——— Rozmiary ———
            Flow {
                visible: sp.query === ""
                width: parent.width
                spacing: 6
                Repeater {
                    model: sp.groups
                    delegate: GChip {
                        required property var modelData
                        height: 30
                        text: modelData.label
                        on: sp.group === modelData.id
                        onClicked: sp.group = modelData.id
                    }
                }
            }
            Flow {
                visible: sp.query === ""
                width: parent.width
                spacing: 12
                Repeater {
                    model: sp.app ? sp.app.presets.filter(p => sp.group === "" || p.group === sp.group) : []
                    delegate: SizeCard {
                        required property var modelData
                        title: modelData.name
                        hint: modelData.hint
                        pw: modelData.w
                        ph: modelData.h
                        icon: modelData.icon
                        colors: sp.groupColors[modelData.group]
                        dims: modelData.print ? modelData.print.width + " × " + modelData.print.height + " mm" : modelData.w + " × " + modelData.h + " px"
                        onClicked: sp.app.newProject(modelData)
                    }
                }
                SizeCard {
                    id: customCard
                    title: "Własny rozmiar"
                    hint: "Dowolne wymiary"
                    pw: 0; ph: 0
                    onClicked: sp.openCustom()
                }
            }

            // ——— Własne projekty ———
            Item { width: 1; height: 8; visible: sp.foundProjects.length > 0 }
            Item {
                visible: sp.foundProjects.length > 0
                width: parent.width; height: 28
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: sp.query !== "" ? "Projekty" : "Ostatnie projekty"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 19; font.weight: Font.Bold; font.letterSpacing: -0.3
                }
                Btn {
                    readonly property int perRow: Math.max(1, Math.floor((content.width + 14) / 210))
                    visible: sp.query === "" && sp.foundProjects.length > perRow
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    height: 30
                    text: sp.allProjects ? "Pokaż mniej" : "Wszystkie (" + sp.foundProjects.length + ")"
                    onClicked: sp.allProjects = !sp.allProjects
                }
            }
            Flow {
                id: projFlow
                visible: sp.foundProjects.length > 0
                width: parent.width
                spacing: 14
                readonly property int perRow: Math.max(1, Math.floor((width + 14) / 210))
                Repeater {
                    model: sp.query !== "" || sp.allProjects ? sp.foundProjects : sp.foundProjects.slice(0, projFlow.perRow)
                    delegate: Card {
                        id: projCard
                        required property var modelData
                        title: modelData.name
                        subtitle: modelData.when
                        source: "image://thumb/p/" + encodeURIComponent(modelData.path) + "?" + modelData.stamp
                        hasMenu: true
                        onClicked: sp.app.openProject(modelData.path)
                        onMenu: (x, y) => {
                            menu.path = projCard.modelData.path;
                            const p = projCard.mapToItem(sp, x, y);
                            menu.openAt(p.x, p.y, [
                                { label: "Otwórz", icon: "folder", action: "open" },
                                { label: "Pokaż w folderze", icon: "search", action: "show" },
                                { separator: true },
                                { label: "Przenieś do kosza", icon: "trash", action: "trash", danger: true }
                            ]);
                        }
                    }
                }
            }

            // ——— Szablony ———
            Item { width: 1; height: 8 }
            Text {
                text: sp.query !== "" ? (sp.foundTemplates.length > 0 ? "Szablony" : "Nic nie znalazłem — spróbuj innego słowa, np. „urodziny”, „menu”, „CV”.") : "Zacznij od szablonu"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 19; font.weight: Font.Bold; font.letterSpacing: -0.3
            }
            Flow {
                visible: sp.query === ""
                width: parent.width
                spacing: 6
                GChip { text: "Wszystkie"; on: sp.category === ""; onClicked: sp.category = "" }
                Repeater {
                    model: sp.categories
                    delegate: GChip {
                        required property string modelData
                        text: modelData
                        on: sp.category === modelData
                        onClicked: sp.category = modelData
                    }
                }
            }
            Flow {
                width: parent.width
                spacing: 14
                Repeater {
                    model: sp.foundTemplates
                    delegate: Card {
                        required property var modelData
                        title: modelData.name
                        subtitle: modelData.category
                        source: "image://thumb/t/" + encodeURIComponent(modelData.file)
                        onClicked: sp.app.fromTemplate(modelData.file)
                    }
                }
            }
        }
    }

    ContextMenu {
        id: menu
        property string path
        onTriggered: (a) => {
            if (a === "open") sp.app.openProject(path);
            else if (a === "show") Library.showInFolder(path);
            else if (a === "trash") { if (Library.trash(path)) sp.app.toast("Projekt jest w koszu", ""); }
        }
    }

    // ——— Własny rozmiar ———
    Popover {
        id: customPop
        cardWidth: 300
        Column {
            width: parent.width
            spacing: 12
            Text { text: "Własny rozmiar"; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold }
            Row {
                spacing: 10
                Column {
                    spacing: 4
                    Text { text: "Szerokość (px)"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                    NumField { id: widthField; width: 124; step: 10; from: 16; to: 10000; onEdited: (v) => value = v }
                }
                Column {
                    spacing: 4
                    Text { text: "Wysokość (px)"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                    NumField { id: heightField; width: 124; step: 10; from: 16; to: 10000; onEdited: (v) => value = v }
                }
            }
            Btn {
                width: parent.width
                primary: true
                text: "Utwórz"
                onClicked: { customPop.close(); sp.app.newCustom(widthField.value, heightField.value); }
            }
        }
    }

    // ——— Elementy ———
    // Pigułka na tle okna: biała, jak w Plikach
    component GChip: Chip { baseColor: on ? Theme.accent : Theme.surface }

    // Kafelek rozmiaru: prostokąt w proporcjach strony, nazwa i wymiary
    component SizeCard: HoverButton {
        id: sc
        property string title
        property string hint
        property string icon
        property string dims
        property var colors: ["#9AA3B5", "#5B6478"]
        property real pw
        property real ph
        width: 162; height: 168
        radius: 22
        baseColor: Theme.surface
        color: hovered ? (Theme.dark ? Theme.fill : "#FAFAFB") : baseColor
        Item {
            id: shapeBox
            x: 16; y: 14
            width: parent.width - 32; height: 74
            readonly property real k: sc.pw > 0 ? Math.min(width / sc.pw, height / sc.ph) : 0
            Rectangle {
                anchors.centerIn: parent
                width: sc.pw > 0 ? Math.max(18, sc.pw * shapeBox.k) : 50
                height: sc.pw > 0 ? Math.max(18, sc.ph * shapeBox.k) : 50
                radius: 10
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0; color: sc.pw > 0 ? sc.colors[0] : Theme.accentSoft }
                    GradientStop { position: 1; color: sc.pw > 0 ? sc.colors[1] : Theme.accentSoft }
                }
                border.width: sc.pw > 0 ? 0 : 1.5
                border.color: Theme.accent
                scale: sc.hovered ? 1.06 : 1
                Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                Icon {
                    anchors.centerIn: parent
                    d: Icons[sc.pw > 0 ? sc.icon : "plus"] || ""
                    size: Math.min(22, Math.min(parent.width, parent.height) * 0.5); stroke: 2
                    color: sc.pw > 0 ? "white" : Theme.accentText
                }
            }
        }
        Column {
            x: 14; y: 98
            width: parent.width - 28
            spacing: 3
            Text { width: parent.width; elide: Text.ElideRight; text: sc.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text { width: parent.width; elide: Text.ElideRight; text: sc.hint; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
            Text {
                visible: sc.dims !== ""
                text: sc.dims
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.features: { "tnum": 1 }
            }
        }
    }

    // Kafelek z miniaturą (projekt albo szablon)
    component Card: HoverButton {
        id: card
        property string title
        property string subtitle
        property string source
        property bool hasMenu: false
        signal menu(real x, real y)
        width: 196; height: 244
        radius: 22
        baseColor: Theme.surface
        color: hovered ? (Theme.dark ? Theme.fill : "#FAFAFB") : baseColor
        Rectangle {
            x: 8; y: 8
            width: parent.width - 16; height: 176
            radius: 16
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.04) : "#F4F5F7"
            Image {
                anchors.fill: parent
                anchors.margins: 12
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                source: card.source
                sourceSize.width: 360; sourceSize.height: 360
            }
        }
        Column {
            x: 16; y: 194
            width: parent.width - 32
            spacing: 2
            Text { width: parent.width; elide: Text.ElideRight; text: card.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text { width: parent.width; elide: Text.ElideRight; text: card.subtitle; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: (e) => card.menu(e.x, e.y)
        }
        // Menu także bez prawego przycisku — „…” po najechaniu (tylko projekty)
        HoverButton {
            visible: card.hasMenu && (card.hovered || hovered)
            x: parent.width - width - 8; y: 8
            width: 30; height: 30; radius: 15
            baseColor: Theme.surface
            tip: "Więcej"
            onClicked: card.menu(x, y + height)
            Icon { anchors.centerIn: parent; d: Icons.more; size: 15; stroke: 2; color: Theme.text }
        }
    }
}
