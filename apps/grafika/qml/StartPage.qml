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
    property real radius: 24
    property string category: ""

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

    GlassPane {
        anchors.fill: parent
        topLeftRadius: sp.radius; topRightRadius: sp.radius
        bottomLeftRadius: sp.radius; bottomRightRadius: sp.radius
        leftLine: false
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
                text: "Grafika"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            Btn { anchors.verticalCenter: parent.verticalCenter; text: "Otwórz plik…"; icon: "folder"; onClicked: openDialog.open() }
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
                    font.family: Theme.font; font.pixelSize: 30; font.weight: Font.Bold; font.letterSpacing: -0.6
                }
                Text {
                    text: "Wybierz rozmiar i zacznij od pustej strony albo od szablonu. Projekty zapisują się same, a darmowe zdjęcia, ikony i czcionki znajdziesz w edytorze."
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: 14
                }
            }

            // ——— Rozmiary ———
            Flow {
                width: parent.width
                spacing: 12
                Repeater {
                    model: sp.app ? sp.app.presets : []
                    delegate: SizeCard {
                        required property var modelData
                        title: modelData.name
                        hint: modelData.hint
                        pw: modelData.w
                        ph: modelData.h
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
            Item { width: 1; height: 8; visible: Library.projects.length > 0 }
            Text {
                visible: Library.projects.length > 0
                text: "Twoje projekty"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 19; font.weight: Font.Bold; font.letterSpacing: -0.3
            }
            Flow {
                visible: Library.projects.length > 0
                width: parent.width
                spacing: 14
                Repeater {
                    model: Library.projects
                    delegate: Card {
                        id: projCard
                        required property var modelData
                        title: modelData.name
                        subtitle: modelData.when
                        source: "image://thumb/p/" + encodeURIComponent(modelData.path) + "?" + modelData.stamp
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
                text: "Szablony"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 19; font.weight: Font.Bold; font.letterSpacing: -0.3
            }
            Flow {
                width: parent.width
                spacing: 6
                Chip { text: "Wszystkie"; on: sp.category === ""; onClicked: sp.category = "" }
                Repeater {
                    model: sp.categories
                    delegate: Chip {
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
                    model: Library.templates.filter(t => sp.category === "" || t.category === sp.category)
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
    // Kafelek rozmiaru: prostokąt w proporcjach strony, nazwa i wymiary
    component SizeCard: HoverButton {
        id: sc
        property string title
        property string hint
        property real pw
        property real ph
        width: 150; height: 156
        radius: 16
        baseColor: Theme.fill
        Item {
            id: shapeBox
            x: 16; y: 14
            width: parent.width - 32; height: 64
            readonly property real k: sc.pw > 0 ? Math.min(width / sc.pw, height / sc.ph) : 0
            Rectangle {
                anchors.centerIn: parent
                width: sc.pw > 0 ? Math.max(14, sc.pw * shapeBox.k) : 44
                height: sc.pw > 0 ? Math.max(14, sc.ph * shapeBox.k) : 44
                radius: 5
                color: Theme.accentSoft
                border.width: 1.5
                border.color: Theme.accent
                Icon { visible: sc.pw === 0; anchors.centerIn: parent; d: Icons.plus; size: 20; stroke: 2; color: Theme.accentText }
            }
        }
        Column {
            x: 14; y: 90
            width: parent.width - 28
            spacing: 3
            Text { width: parent.width; elide: Text.ElideRight; text: sc.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text { width: parent.width; elide: Text.ElideRight; text: sc.hint; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
            Text {
                visible: sc.pw > 0
                text: sc.pw + " × " + sc.ph
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
        signal menu(real x, real y)
        width: 196; height: 236
        radius: 16
        Rectangle {
            x: 0; y: 0
            width: parent.width; height: 184
            radius: 14
            color: Theme.fill
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
            x: 6; y: 192
            width: parent.width - 12
            spacing: 2
            Text { width: parent.width; elide: Text.ElideRight; text: card.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text { width: parent.width; elide: Text.ElideRight; text: card.subtitle; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: (e) => card.menu(e.x, e.y)
        }
    }
}
