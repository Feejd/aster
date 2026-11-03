pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Grafika

// Panel po lewej: Szablony, Tekst, Kształty, Zdjęcia, Tło — kliknięcie dodaje element na środek strony;
// Warstwy — lista elementów od wierzchu: zaznaczanie, ukrywanie, blokowanie i kolejność (przeciąganie)
Item {
    id: sp
    required property Project project
    property var editor                      // EditorPage (dodawanie elementów, okna wyboru plików)
    property string tab: "templates"
    property var photos: []

    readonly property real base: Math.min(project.pageWidth, project.pageHeight)
    readonly property var tabs: [
        { id: "templates", label: "Szablony", icon: "layout" },
        { id: "text", label: "Tekst", icon: "textT" },
        { id: "shapes", label: "Kształty", icon: "shapes" },
        { id: "photos", label: "Zdjęcia", icon: "image" },
        { id: "background", label: "Tło", icon: "palette" },
        { id: "layers", label: "Warstwy", icon: "layers" }
    ]
    onTabChanged: {
        if (tab === "photos") photos = Library.photos();
        if (tab === "layers") refreshLayers();
    }

    // ——— Warstwy ———
    property var layers: []                  // od wierzchu
    function refreshLayers() { layers = project.document().elements.slice().reverse(); }
    Timer { id: layersLater; interval: 0; onTriggered: sp.refreshLayers() }
    Connections {
        target: sp.project
        enabled: sp.tab === "layers"
        function onChanged() { layersLater.restart(); }
        function onReset() { layersLater.restart(); }
        function onDataChanged() { layersLater.restart(); }
    }
    readonly property var shapeNames: ({ rect: "Prostokąt", ellipse: "Koło", triangle: "Trójkąt", star: "Gwiazda", heart: "Serce", line: "Linia", arrow: "Strzałka" })
    function layerName(o) {
        if (o.type === "text") return (o.text || "").replace(/\s+/g, " ").trim() || "Tekst";
        if (o.type === "image") return o.src ? "Zdjęcie" : "Miejsce na zdjęcie";
        return shapeNames[o.shape] || "Kształt";
    }

    // Gotowe style tekstu: wielkość w częściach krótszego boku strony
    readonly property var textStyles: [
        { label: "Nagłówek", font: "Geist", size: 0.09, weight: 800, color: "#16181D", preview: 26 },
        { label: "Podtytuł", font: "Geist", size: 0.055, weight: 600, color: "#3D4048", preview: 19 },
        { label: "Zwykły tekst", font: "Geist", size: 0.034, weight: 400, color: "#3D4048", preview: 14, lineHeight: 1.35 },
        { label: "PROMOCJA", font: "Inter Display", size: 0.12, weight: 900, color: "#E53935", caps: true, spacing: 0.01, preview: 28 },
        { label: "Zaproszenie", font: "Z003", size: 0.12, weight: 400, color: "#8B5E3C", preview: 30 },
        { label: "Elegancki", font: "Noto Serif", size: 0.075, weight: 400, italic: true, color: "#2B2B2B", preview: 24 },
        { label: "Z OBRYSEM", font: "Inter", size: 0.11, weight: 900, color: "#FFE600", caps: true, outline: 0.06, outlineColor: "#111111", preview: 26 },
        { label: "O D S T Ę P Y", text: "Odstępy", font: "URW Gothic", size: 0.045, weight: 400, color: "#16181D", caps: true, spacing: 0.3, preview: 16 },
        { label: "„Cytat”", text: "„Prosto, pięknie, po swojemu.”", font: "Noto Serif", size: 0.05, weight: 400, italic: true, color: "#3D4048", lineHeight: 1.3, preview: 18 }
    ]
    readonly property var shapes: [
        { shape: "rect", label: "Prostokąt", fill: "#5B7CFA" },
        { shape: "rect", label: "Zaokrąglony", fill: "#5B7CFA", radius: 0.18 },
        { shape: "ellipse", label: "Koło", fill: "#FF7A59" },
        { shape: "triangle", label: "Trójkąt", fill: "#22B07D" },
        { shape: "star", label: "Gwiazda", fill: "#FFB300" },
        { shape: "heart", label: "Serce", fill: "#E53961" },
        { shape: "rect", label: "Ramka", fill: "", stroke: "#16181D", strokeWidth: 0.02, radius: 0.0 },
        { shape: "ellipse", label: "Okrąg", fill: "", stroke: "#16181D", strokeWidth: 0.02 },
        { shape: "line", label: "Linia", stroke: "#16181D", strokeWidth: 0.008 },
        { shape: "line", label: "Przerywana", stroke: "#16181D", strokeWidth: 0.008, dash: true },
        { shape: "arrow", label: "Strzałka", stroke: "#16181D", strokeWidth: 0.01 }
    ]
    readonly property var solidColors: [
        "#FFFFFF", "#F5F1EA", "#FFF4E0", "#FDE2E4", "#E3F2FD", "#E8F5E9",
        "#16181D", "#2B2D42", "#1A237E", "#004D40", "#4A148C", "#B71C1C",
        "#FFB300", "#FF7043", "#E53961", "#7E57C2", "#1E88E5", "#22B07D"
    ]
    readonly property var gradients: [
        { color: "#FF9A8B", color2: "#FF6A88", angle: 135 },
        { color: "#A18CD1", color2: "#FBC2EB", angle: 180 },
        { color: "#84FAB0", color2: "#8FD3F4", angle: 120 },
        { color: "#FAD961", color2: "#F76B1C", angle: 160 },
        { color: "#2B5876", color2: "#4E4376", angle: 135 },
        { color: "#0F2027", color2: "#2C5364", angle: 180 },
        { color: "#FFDEE9", color2: "#B5FFFC", angle: 180 },
        { color: "#C9D6FF", color2: "#E2E2E2", angle: 135 },
        { color: "#F6D365", color2: "#FDA085", angle: 135 },
        { color: "#43E97B", color2: "#38F9D7", angle: 135 },
        { color: "#4FACFE", color2: "#00F2FE", angle: 90 },
        { color: "#30CFD0", color2: "#330867", angle: 180 },
        { color: "#FFFFFF", color2: "#DDE3EE", angle: 0, type: "radial" },
        { color: "#3A3F58", color2: "#0B0C12", angle: 0, type: "radial" },
        { color: "#FFE29F", color2: "#FF719A", angle: 0, type: "radial" }
    ]

    function addTextStyle(s) {
        const el = {
            type: "text", text: s.text || s.label.replace(/„|”/g, ""), font: s.font, size: Math.round(base * s.size), weight: s.weight,
            color: s.color, align: "center", lineHeight: s.lineHeight || 1.15
        };
        for (const k of ["italic", "caps", "spacing", "outline", "outlineColor"]) if (s[k] !== undefined) el[k] = s[k];
        el.w = Math.min(project.pageWidth * 0.86, project.naturalWidth(el) + el.size * 0.2);
        editor.addElement(el);
    }
    function addShape(s) {
        const line = s.shape === "line" || s.shape === "arrow";
        const side = Math.round(base * 0.36);
        const el = { type: "shape", shape: s.shape, fill: s.fill || "", w: line ? side * 1.4 : side, h: side };
        if (s.radius) el.radius = Math.round(side * s.radius);
        if (s.stroke) { el.stroke = s.stroke; el.strokeWidth = Math.max(2, Math.round(base * s.strokeWidth)); }
        if (s.dash) el.dash = true;
        if (line) el.h = Math.max(24, el.strokeWidth * 4);
        editor.addElement(el);
    }

    // ——— Pasek kart ———
    Column {
        id: rail
        width: 72
        y: 8
        spacing: 4
        Repeater {
            model: sp.tabs
            delegate: HoverButton {
                id: tabBtn
                required property var modelData
                readonly property bool on: sp.tab === modelData.id
                x: 8; width: 56; height: 58; radius: 12
                baseColor: on ? Theme.accentSoft : "transparent"
                color: on ? baseColor : hovered ? Theme.hover : baseColor
                onClicked: sp.tab = modelData.id
                Column {
                    anchors.centerIn: parent
                    spacing: 4
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; d: Icons[tabBtn.modelData.icon]; size: 20; stroke: 1.8; color: tabBtn.on ? Theme.accentText : Theme.text }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tabBtn.modelData.label
                        color: tabBtn.on ? Theme.accentText : Theme.text2
                        font.family: Theme.font; font.pixelSize: 11; font.weight: tabBtn.on ? Font.DemiBold : Font.Medium
                    }
                }
            }
        }
    }

    // ——— Zawartość karty ———
    Item {
        id: body
        x: rail.width
        width: parent.width - rail.width
        height: parent.height

        Text {
            x: 12; y: 14
            text: { for (const t of sp.tabs) if (t.id === sp.tab) return t.label; return ""; }
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold; font.letterSpacing: -0.2
        }

        Flickable {
            id: scroll
            x: 12; y: 50
            width: parent.width - 24
            height: parent.height - y
            contentHeight: pages.height + 20
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Item {
                id: pages
                width: scroll.width
                height: sp.tab === "templates" ? templatesCol.height : sp.tab === "text" ? textCol.height
                      : sp.tab === "shapes" ? shapesGrid.height : sp.tab === "photos" ? photosCol.height
                      : sp.tab === "layers" ? layersCol.height : bgCol.height

                // Szablony
                Column {
                    id: templatesCol
                    visible: sp.tab === "templates"
                    width: parent.width
                    spacing: 10
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Kliknij szablon, żeby zastąpić nim stronę. Ctrl+Z przywraca poprzednią."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
                    }
                    Flow {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: Library.templates
                            delegate: HoverButton {
                                id: tpl
                                required property var modelData
                                width: (pages.width - 8) / 2
                                height: width * 1.05 + 22
                                radius: 10
                                onClicked: sp.editor.applyTemplate(modelData.file)
                                Image {
                                    x: 4; y: 4
                                    width: parent.width - 8; height: parent.width * 1.05 - 8
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    source: "image://thumb/t/" + encodeURIComponent(tpl.modelData.file)
                                    sourceSize.width: 260; sourceSize.height: 260
                                }
                                Text {
                                    x: 4; width: parent.width - 8
                                    anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: tpl.modelData.name
                                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                                }
                            }
                        }
                    }
                }

                // Tekst
                Column {
                    id: textCol
                    visible: sp.tab === "text"
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: sp.textStyles
                        delegate: HoverButton {
                            id: ts
                            required property var modelData
                            required property int index
                            width: textCol.width
                            height: Math.max(52, label.implicitHeight + 24)
                            radius: 12
                            baseColor: Theme.fill
                            onClicked: sp.addTextStyle(modelData)
                            Text {
                                id: label
                                anchors.centerIn: parent
                                width: parent.width - 20
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: ts.modelData.label
                                color: ts.modelData.outline ? ts.modelData.color : (Theme.dark && ts.modelData.color.toLowerCase() < "#555555" ? Theme.text : ts.modelData.color)
                                style: ts.modelData.outline ? Text.Outline : Text.Normal
                                styleColor: ts.modelData.outlineColor || "transparent"
                                font.family: ts.modelData.font
                                font.pixelSize: ts.modelData.preview
                                font.weight: ts.modelData.weight
                                font.italic: !!ts.modelData.italic
                                font.capitalization: ts.modelData.caps ? Font.AllUppercase : Font.MixedCase
                                font.letterSpacing: (ts.modelData.spacing || 0) * ts.modelData.preview
                            }
                        }
                    }
                }

                // Kształty
                Grid {
                    id: shapesGrid
                    visible: sp.tab === "shapes"
                    columns: 3
                    spacing: 8
                    Repeater {
                        model: sp.shapes
                        delegate: HoverButton {
                            id: sh
                            required property var modelData
                            readonly property bool line: modelData.shape === "line" || modelData.shape === "arrow"
                            width: (pages.width - 16) / 3
                            height: width + 16
                            radius: 12
                            baseColor: Theme.fill
                            onClicked: sp.addShape(modelData)
                            ArtView {
                                x: 14; y: sh.line ? (sh.width - 18) / 2 : 12
                                width: sh.width - 28
                                height: sh.line ? 18 : sh.width - 28
                                element: ({
                                    type: "shape", shape: sh.modelData.shape, w: 100, h: sh.line ? 18 : 100,
                                    fill: sh.modelData.fill ? sh.modelData.fill : "",
                                    stroke: sh.modelData.stroke ? (Theme.dark ? "#ECEEF3" : sh.modelData.stroke) : "",
                                    strokeWidth: sh.modelData.stroke ? (sh.line ? 6 : 6) : 0,
                                    radius: sh.modelData.radius ? 18 : 0, dash: !!sh.modelData.dash
                                })
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                                text: sh.modelData.label
                                color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                            }
                        }
                    }
                }

                // Zdjęcia
                Column {
                    id: photosCol
                    visible: sp.tab === "photos"
                    width: parent.width
                    spacing: 12
                    Btn {
                        width: parent.width
                        primary: true
                        icon: "upload"
                        text: "Dodaj zdjęcie z dysku"
                        onClicked: sp.editor.chooseImage("element")
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Możesz też przeciągnąć zdjęcie z Plików prosto na okno albo wkleić je Ctrl+V."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
                    }
                    Text {
                        visible: sp.project.images.length > 0
                        text: "W tym projekcie"
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: sp.project.images
                            delegate: HoverButton {
                                id: used
                                required property string modelData
                                width: (pages.width - 12) / 3; height: width
                                radius: 8
                                onClicked: sp.editor.addImageKey(modelData)
                                ArtView {
                                    anchors.fill: parent; anchors.margins: 2
                                    project: sp.project
                                    element: ({ type: "image", src: used.modelData, w: 100, h: 100, radius: 8 })
                                }
                            }
                        }
                    }
                    Text {
                        visible: sp.photos.length > 0
                        text: "Ostatnie z folderu Obrazy"
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: sp.photos
                            delegate: HoverButton {
                                id: ph
                                required property string modelData
                                width: (pages.width - 12) / 3; height: width
                                radius: 8
                                onClicked: sp.editor.addImageFile(modelData)
                                Image {
                                    anchors.fill: parent; anchors.margins: 2
                                    source: ph.modelData
                                    sourceSize.width: 180; sourceSize.height: 180
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    clip: true
                                }
                            }
                        }
                    }
                }

                // Warstwy
                Column {
                    id: layersCol
                    visible: sp.tab === "layers"
                    width: parent.width
                    spacing: 10
                    readonly property real rowH: 46
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: sp.layers.length === 0 ? "Na stronie nie ma jeszcze elementów." : "Na górze listy jest to, co leży na wierzchu. Przeciągnij wiersz, żeby zmienić kolejność."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
                    }
                    Item {
                        id: layerList
                        width: parent.width
                        height: sp.layers.length * layersCol.rowH
                        property int dragFrom: -1
                        property int dragTo: -1
                        property real dragY: 0

                        // Miejsce, w które trafi przeciągany wiersz
                        Rectangle {
                            visible: layerList.dragFrom >= 0 && layerList.dragTo !== layerList.dragFrom
                            y: (layerList.dragTo > layerList.dragFrom ? layerList.dragTo + 1 : layerList.dragTo) * layersCol.rowH - 1
                            width: parent.width; height: 2; radius: 1
                            color: Theme.accent
                            z: 3
                        }
                        Repeater {
                            model: sp.layers
                            delegate: Rectangle {
                                id: row
                                required property var modelData
                                required property int index
                                readonly property bool picked: sp.editor.many.indexOf(modelData.id) >= 0
                                readonly property bool dragged: layerList.dragFrom === index
                                y: dragged ? layerList.dragY : index * layersCol.rowH
                                z: dragged ? 2 : 0
                                width: layerList.width; height: layersCol.rowH - 4
                                radius: 10
                                color: picked ? Theme.accentSoft : rowMa.containsMouse || dragged ? Theme.hover : "transparent"
                                opacity: modelData.hidden ? 0.5 : 1

                                Rectangle {
                                    id: thumb
                                    x: 6; anchors.verticalCenter: parent.verticalCenter
                                    width: 34; height: 34; radius: 7
                                    color: sp.project.background.color || "#ffffff"     // biały tekst widać na tle strony
                                    border.width: 1; border.color: Theme.line
                                    clip: true
                                    ArtView {
                                        readonly property real k: Math.min(30 / Math.max(1, row.modelData.w), 30 / Math.max(1, row.modelData.h))
                                        anchors.centerIn: parent
                                        width: Math.max(2, row.modelData.w * k); height: Math.max(2, row.modelData.h * k)
                                        rotation: row.modelData.rotation || 0
                                        project: sp.project
                                        element: row.modelData
                                    }
                                }
                                Text {
                                    anchors.left: thumb.right; anchors.leftMargin: 10
                                    anchors.right: tools.left; anchors.rightMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    text: sp.layerName(row.modelData)
                                    color: row.picked ? Theme.accentText : Theme.text
                                    font.family: row.modelData.type === "text" ? (row.modelData.font || Theme.font) : Theme.font
                                    font.pixelSize: 13
                                }
                                MouseArea {
                                    id: rowMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: pressed && layerList.dragFrom >= 0 ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                    property real startY
                                    property real grab
                                    onPressed: (e) => {
                                        startY = mapToItem(layerList, e.x, e.y).y;
                                        grab = e.y;
                                    }
                                    onPositionChanged: (e) => {
                                        if (!pressed) return;
                                        const y = mapToItem(layerList, e.x, e.y).y;
                                        if (layerList.dragFrom < 0 && Math.abs(y - startY) < 6) return;
                                        layerList.dragFrom = row.index;
                                        layerList.dragY = Math.max(0, Math.min(layerList.height - layersCol.rowH, y - grab));
                                        layerList.dragTo = Math.max(0, Math.min(sp.layers.length - 1, Math.round(layerList.dragY / layersCol.rowH)));
                                    }
                                    onReleased: (e) => {
                                        if (layerList.dragFrom >= 0) {
                                            const to = layerList.dragTo;
                                            layerList.dragFrom = -1;
                                            if (to !== row.index) sp.project.moveTo(row.modelData.id, sp.layers.length - 1 - to);
                                            sp.refreshLayers();
                                        } else {
                                            sp.editor.selectLayer(row.modelData.id, e.modifiers & Qt.ShiftModifier);
                                        }
                                    }
                                }
                                Row {
                                    id: tools
                                    anchors.right: parent.right; anchors.rightMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    IconToggle {
                                        width: 28; height: 28
                                        icon: row.modelData.locked ? "lock" : "unlock"
                                        on: !!row.modelData.locked
                                        opacity: row.modelData.locked || rowMa.containsMouse || hovered ? 1 : 0.35
                                        onClicked: sp.project.change(row.modelData.id, { locked: row.modelData.locked ? null : true })
                                    }
                                    IconToggle {
                                        width: 28; height: 28
                                        icon: row.modelData.hidden ? "eyeOff" : "eye"
                                        opacity: row.modelData.hidden || rowMa.containsMouse || hovered ? 1 : 0.35
                                        onClicked: sp.editor.setHidden(row.modelData.id, !row.modelData.hidden)
                                    }
                                }
                            }
                        }
                    }
                }

                // Tło
                Column {
                    id: bgCol
                    visible: sp.tab === "background"
                    width: parent.width
                    spacing: 12
                    Section {
                        title: "Kolor"
                        Grid {
                            columns: 6
                            spacing: 8
                            Repeater {
                                model: sp.solidColors
                                delegate: Rectangle {
                                    id: solid
                                    required property string modelData
                                    width: (pages.width - 40) / 6; height: width; radius: width / 2
                                    color: modelData
                                    border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.14)
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: sp.project.setBackground({ type: "color", color: solid.modelData })
                                    }
                                }
                            }
                        }
                    }
                    Section {
                        title: "Przejście kolorów"
                        Grid {
                            columns: 3
                            spacing: 8
                            Repeater {
                                model: sp.gradients
                                delegate: HoverButton {
                                    id: grad
                                    required property var modelData
                                    width: (pages.width - 16) / 3; height: width * 0.72
                                    radius: 10
                                    onClicked: sp.project.setBackground({ type: grad.modelData.type || "gradient", color: grad.modelData.color, color2: grad.modelData.color2, angle: grad.modelData.angle })
                                    ArtView {
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        element: ({ kind: "background", w: 100, h: 72, type: grad.modelData.type || "gradient",
                                                    color: grad.modelData.color, color2: grad.modelData.color2, angle: grad.modelData.angle })
                                    }
                                }
                            }
                        }
                    }
                    Section {
                        title: "Zdjęcie"
                        Btn {
                            width: parent.width
                            icon: "image"
                            text: "Zdjęcie jako tło…"
                            onClicked: sp.editor.chooseImage("background")
                        }
                    }
                }
            }
        }
    }
}
