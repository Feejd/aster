pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Grafika

// Właściwości zaznaczonego elementu (tekst, kształt, zdjęcie), kilku zaznaczonych (wyrównanie), a bez zaznaczenia — strony i tła
Item {
    id: ins
    required property Project project
    required property Stage stage
    property var editor                     // EditorPage: wybór koloru i czcionki, menu, okna plików

    readonly property var el: stage.current
    readonly property string id_: el.id || ""
    readonly property int count: stage.selection.length
    readonly property string type: count > 1 ? "many" : id_ !== "" ? (el.locked ? "locked" : el.type) : "page"
    readonly property bool line: type === "shape" && (el.shape === "line" || el.shape === "arrow")
    readonly property var bg: project.background
    readonly property var filters: [
        { id: "", label: "Brak" }, { id: "gray", label: "Czarno-białe" }, { id: "sepia", label: "Sepia" }, { id: "warm", label: "Ciepłe" },
        { id: "cool", label: "Chłodne" }, { id: "fade", label: "Wyblakłe" }, { id: "vivid", label: "Żywe" }
    ]

    function set(patch, done) { project.change(id_, patch, done === undefined ? true : done); }
    function setBg(patch, done) { project.setBackground(Object.assign({}, bg, patch), done === undefined ? true : done); }
    function alignTo(how) {
        const r = (el.rotation || 0) * Math.PI / 180;
        const aw = Math.abs(el.w * Math.cos(r)) + Math.abs(el.h * Math.sin(r));
        const ah = Math.abs(el.w * Math.sin(r)) + Math.abs(el.h * Math.cos(r));
        const W = project.pageWidth, H = project.pageHeight;
        const p = {};
        if (how === "left") p.x = aw / 2 - el.w / 2;
        else if (how === "hcenter") p.x = (W - el.w) / 2;
        else if (how === "right") p.x = W - aw / 2 - el.w / 2;
        else if (how === "top") p.y = ah / 2 - el.h / 2;
        else if (how === "vcenter") p.y = (H - el.h) / 2;
        else if (how === "bottom") p.y = H - ah / 2 - el.h / 2;
        for (const k in p) p[k] = Math.round(p[k] * 10) / 10;
        set(p);
    }

    Text {
        x: 18; y: 16
        text: ins.type === "many" ? "Zaznaczono: " + ins.count : ins.type === "locked" ? "Zablokowany"
            : ins.type === "text" ? "Tekst" : ins.type === "image" ? "Zdjęcie" : ins.line ? "Linia" : ins.type === "shape" ? "Kształt" : "Strona"
        color: Theme.text
        font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold; font.letterSpacing: -0.2
    }

    Flickable {
        id: scroll
        x: 18; y: 50
        width: parent.width - 36
        height: parent.height - y
        contentHeight: col.height + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: scroll.width
            spacing: 18

            // ——— Strona ———
            Section {
                visible: ins.type === "page"
                title: "Rozmiar"
                Row {
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(ins.project.pageWidth) + " × " + Math.round(ins.project.pageHeight) + " px"
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.features: { "tnum": 1 }
                    }
                    Btn { id: sizeBtn; text: "Zmień"; height: 30; onClicked: ins.editor.showSizeMenu(sizeBtn) }
                }
            }
            Section {
                visible: ins.type === "page"
                title: "Tło"
                Flow {
                    width: parent.width
                    spacing: 6
                    Chip { text: "Kolor"; on: ins.bg.type === "color" || !ins.bg.type; onClicked: ins.setBg({ type: "color" }) }
                    Chip { text: "Przejście"; on: ins.bg.type === "gradient"; onClicked: ins.setBg({ type: "gradient", color2: ins.bg.color2 || "#5B7CFA", angle: ins.bg.angle === undefined ? 180 : ins.bg.angle }) }
                    Chip { text: "Okrągłe"; on: ins.bg.type === "radial"; onClicked: ins.setBg({ type: "radial", color2: ins.bg.color2 || "#5B7CFA" }) }
                    Chip { text: "Zdjęcie"; on: ins.bg.type === "image"; onClicked: ins.editor.chooseImage("background") }
                }
                Row {
                    spacing: 8
                    ColorWell {
                        id: bgWell
                        label: ins.bg.type === "gradient" || ins.bg.type === "radial" ? "Pierwszy" : "Kolor"
                        value: ins.bg.color || "#ffffff"
                        onClicked: ins.editor.pickColor(bgWell, value, false, (c, done) => ins.setBg({ color: c }, done))
                    }
                    ColorWell {
                        id: bgWell2
                        visible: ins.bg.type === "gradient" || ins.bg.type === "radial"
                        label: "Drugi"
                        value: ins.bg.color2 || "#000000"
                        onClicked: ins.editor.pickColor(bgWell2, value, false, (c, done) => ins.setBg({ color2: c }, done))
                    }
                }
                ValueSlider {
                    visible: ins.bg.type === "gradient"
                    label: "Kierunek"
                    from: 0; to: 360; step: 15
                    value: ins.bg.angle === undefined ? 180 : ins.bg.angle
                    suffix: "°"
                    onMoved: (v, done) => ins.setBg({ angle: v }, done)
                }
                ValueSlider {
                    visible: ins.bg.type === "image"
                    label: "Widoczność zdjęcia"
                    from: 0; to: 1; step: 0.01
                    value: ins.bg.imageOpacity === undefined ? 1 : ins.bg.imageOpacity
                    shown: value * 100; suffix: "%"
                    onMoved: (v, done) => ins.setBg({ imageOpacity: v }, done)
                }
                Btn {
                    visible: ins.bg.type === "image"
                    text: "Usuń zdjęcie tła"
                    onClicked: ins.setBg({ type: "color", src: null })
                }
            }
            Text {
                visible: ins.type === "page"
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Kliknij element na stronie, żeby go zmienić. Dwuklik na tekście — pisanie. Przeciągaj z Shiftem, żeby zachować proporcje."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.25
            }

            // ——— Kilka elementów ———
            Section {
                visible: ins.type === "many"
                title: "Wyrównaj do siebie"
                Row {
                    spacing: 2
                    IconToggle { icon: "alignHLeft"; onClicked: ins.editor.alignMany("left") }
                    IconToggle { icon: "alignHCenter"; onClicked: ins.editor.alignMany("hcenter") }
                    IconToggle { icon: "alignHRight"; onClicked: ins.editor.alignMany("right") }
                    Item { width: 6; height: 1 }
                    IconToggle { icon: "alignTop"; onClicked: ins.editor.alignMany("top") }
                    IconToggle { icon: "alignMiddle"; onClicked: ins.editor.alignMany("vcenter") }
                    IconToggle { icon: "alignBottom"; onClicked: ins.editor.alignMany("bottom") }
                }
                Row {
                    visible: ins.count > 2
                    spacing: 8
                    Btn { text: "Równo w poziomie"; icon: "distributeH"; height: 32; onClicked: ins.editor.alignMany("spreadH") }
                }
                Row {
                    visible: ins.count > 2
                    spacing: 8
                    Btn { text: "Równo w pionie"; icon: "distributeV"; height: 32; onClicked: ins.editor.alignMany("spreadV") }
                }
            }
            Section {
                visible: ins.type === "many"
                title: "Zaznaczone"
                Row {
                    spacing: 8
                    Btn { text: "Duplikuj"; icon: "copy"; onClicked: ins.editor.duplicate() }
                    Btn { text: "Zablokuj"; icon: "lock"; onClicked: ins.editor.setLocked(true) }
                }
                Btn { text: "Usuń zaznaczone"; icon: "trash"; onClicked: ins.editor.remove() }
            }
            Text {
                visible: ins.type === "many"
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Przeciągnij jeden z zaznaczonych, żeby przesunąć wszystkie. Shift+klik dodaje albo odejmuje element."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.25
            }

            // ——— Zablokowany ———
            Text {
                visible: ins.type === "locked"
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Tego elementu nie da się przypadkiem przesunąć ani zmienić. Odblokuj go, żeby wprowadzić zmiany."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.25
            }
            Btn {
                visible: ins.type === "locked"
                text: "Odblokuj"
                icon: "unlock"
                primary: true
                onClicked: ins.editor.setLocked(false)
            }

            // ——— Tekst ———
            Section {
                visible: ins.type === "text"
                title: "Czcionka"
                HoverButton {
                    id: fontBtn
                    width: parent.width; height: 38; radius: 10
                    baseColor: Theme.fill
                    color: hovered ? Theme.hover : baseColor
                    onClicked: ins.editor.pickFont(fontBtn, ins.el.font || "Geist", f => ins.set({ font: f }))
                    Text {
                        x: 12; width: parent.width - 40
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: ins.el.font || "Geist"
                        color: Theme.text
                        font.family: ins.el.font || "Geist"; font.pixelSize: 15
                    }
                    Icon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.chevronDown; size: 14; stroke: 2; color: Theme.text2 }
                }
                Row {
                    spacing: 8
                    NumField {
                        width: 128
                        value: Math.round(ins.el.size || 48)
                        step: Math.max(1, Math.round((ins.el.size || 48) / 12))
                        from: 4; to: 4000
                        onEdited: (v) => ins.set({ size: v })
                    }
                    ColorWell {
                        id: textWell
                        value: ins.el.color || "#000000"
                        label: "Kolor"
                        onClicked: ins.editor.pickColor(textWell, value, false, (c, done) => ins.set({ color: c }, done))
                    }
                }
                Row {
                    spacing: 2
                    IconToggle { icon: "bold"; on: (ins.el.weight || 400) >= 600; onClicked: ins.set({ weight: on ? 400 : 700 }) }
                    IconToggle { icon: "italic"; on: !!ins.el.italic; onClicked: ins.set({ italic: !on }) }
                    IconToggle { icon: "underline"; on: !!ins.el.underline; onClicked: ins.set({ underline: !on }) }
                    IconToggle { label: "AA"; on: !!ins.el.caps; onClicked: ins.set({ caps: !on }) }
                    Item { width: 8; height: 1 }
                    IconToggle { icon: "alignLeft"; on: !ins.el.align || ins.el.align === "left"; onClicked: ins.set({ align: "left" }) }
                    IconToggle { icon: "alignCenter"; on: ins.el.align === "center"; onClicked: ins.set({ align: "center" }) }
                    IconToggle { icon: "alignRight"; on: ins.el.align === "right"; onClicked: ins.set({ align: "right" }) }
                }
            }
            Section {
                visible: ins.type === "text"
                title: "Odstępy"
                ValueSlider {
                    label: "Między literami"
                    from: -0.1; to: 0.5; step: 0.005
                    value: ins.el.spacing || 0
                    shown: value * 100
                    onMoved: (v, done) => ins.set({ spacing: v }, done)
                }
                ValueSlider {
                    label: "Między wierszami"
                    from: 0.7; to: 2.5; step: 0.05
                    value: ins.el.lineHeight || 1.2
                    decimals: 2
                    onMoved: (v, done) => ins.set({ lineHeight: v }, done)
                }
            }
            Section {
                visible: ins.type === "text"
                title: "Efekty"
                Row {
                    spacing: 8
                    Chip { text: "Obrys"; on: (ins.el.outline || 0) > 0; onClicked: ins.set({ outline: on ? 0 : 0.05, outlineColor: ins.el.outlineColor || "#111111" }) }
                    Chip { text: "Cień"; on: !!ins.el.shadow; onClicked: ins.set({ shadow: !on }) }
                    ColorWell {
                        id: outlineWell
                        visible: (ins.el.outline || 0) > 0
                        value: ins.el.outlineColor || "#111111"
                        onClicked: ins.editor.pickColor(outlineWell, value, false, (c, done) => ins.set({ outlineColor: c }, done))
                    }
                }
                ValueSlider {
                    visible: (ins.el.outline || 0) > 0
                    label: "Grubość obrysu"
                    from: 0.01; to: 0.15; step: 0.005
                    value: ins.el.outline || 0
                    shown: value * 100
                    onMoved: (v, done) => ins.set({ outline: v }, done)
                }
            }

            // ——— Kształt ———
            Section {
                visible: ins.type === "shape"
                title: ins.line ? "Linia" : "Kolory"
                Flow {
                    width: parent.width
                    spacing: 8
                    ColorWell {
                        id: fillWell
                        visible: !ins.line
                        label: "Wypełnienie"
                        value: ins.el.fill || ""
                        onClicked: ins.editor.pickColor(fillWell, value, true, (c, done) => ins.set({ fill: c }, done))
                    }
                    ColorWell {
                        id: fill2Well
                        visible: !ins.line && !!ins.el.fill
                        label: ins.el.fill2 ? "Przejście" : "+ przejście"
                        value: ins.el.fill2 || ""
                        onClicked: ins.editor.pickColor(fill2Well, value, true, (c, done) => ins.set({ fill2: c }, done))
                    }
                    ColorWell {
                        id: strokeWell
                        label: ins.line ? "Kolor" : "Obrys"
                        value: ins.el.stroke || ""
                        onClicked: ins.editor.pickColor(strokeWell, value, !ins.line, (c, done) => {
                            const p = { stroke: c };
                            if (c !== "" && !(ins.el.strokeWidth > 0)) p.strokeWidth = Math.max(2, Math.round(Math.min(ins.el.w, ins.el.h) * 0.03));
                            ins.set(p, done);
                        })
                    }
                }
                Row {
                    visible: !ins.line && !!ins.el.fill && !!ins.el.fill2
                    spacing: 6
                    Chip { text: "Liniowe"; on: ins.el.gradient !== "radial"; onClicked: ins.set({ gradient: null }) }
                    Chip { text: "Okrągłe"; on: ins.el.gradient === "radial"; onClicked: ins.set({ gradient: "radial" }) }
                }
                ValueSlider {
                    visible: !ins.line && !!ins.el.fill && !!ins.el.fill2 && ins.el.gradient !== "radial"
                    label: "Kierunek przejścia"
                    from: 0; to: 360; step: 15
                    value: ins.el.gradientAngle === undefined ? 180 : ins.el.gradientAngle
                    suffix: "°"
                    onMoved: (v, done) => ins.set({ gradientAngle: v }, done)
                }
                ValueSlider {
                    visible: ins.line || !!ins.el.stroke
                    label: ins.line ? "Grubość" : "Grubość obrysu"
                    from: ins.line ? 1 : 0; to: Math.max(40, Math.round(Math.min(ins.project.pageWidth, ins.project.pageHeight) * 0.05)); step: 1
                    value: ins.el.strokeWidth || 0
                    suffix: " px"
                    onMoved: (v, done) => {
                        const p = { strokeWidth: v };
                        if (ins.line) p.h = Math.max(24, v * 4);
                        ins.set(p, done);
                    }
                }
                ValueSlider {
                    visible: ins.el.shape === "rect"
                    label: "Zaokrąglenie rogów"
                    from: 0; to: Math.round(Math.min(ins.el.w || 0, ins.el.h || 0) / 2); step: 1
                    value: ins.el.radius || 0
                    suffix: " px"
                    onMoved: (v, done) => ins.set({ radius: v }, done)
                }
                Chip {
                    visible: ins.line || !!ins.el.stroke
                    text: "Przerywana"
                    on: !!ins.el.dash
                    onClicked: ins.set({ dash: !on })
                }
            }

            // ——— Zdjęcie ———
            Section {
                visible: ins.type === "image"
                title: "Kształt zdjęcia"
                Row {
                    spacing: 6
                    Chip { text: "Prostokąt"; on: ins.el.mask !== "ellipse"; onClicked: ins.set({ mask: null }) }
                    Chip { text: "Koło"; on: ins.el.mask === "ellipse"; onClicked: ins.set({ mask: "ellipse" }) }
                }
                ValueSlider {
                    visible: ins.el.mask !== "ellipse"
                    label: "Zaokrąglenie rogów"
                    from: 0; to: Math.round(Math.min(ins.el.w || 0, ins.el.h || 0) / 2); step: 1
                    value: ins.el.radius || 0
                    suffix: " px"
                    onMoved: (v, done) => ins.set({ radius: v }, done)
                }
                Row {
                    spacing: 8
                    Btn { text: ins.el.src ? "Zamień…" : "Wybierz…"; icon: "image"; onClicked: ins.editor.chooseImage("replace") }
                    Btn { visible: !!ins.el.src; text: "Jako tło"; onClicked: ins.editor.imageToBackground(ins.id_) }
                }
            }
            Section {
                visible: ins.type === "image" && !!ins.el.src
                title: "Kadr"
                Row {
                    spacing: 8
                    Btn {
                        text: ins.stage.cropping === ins.id_ ? "Gotowe" : "Kadruj"
                        icon: ins.stage.cropping === ins.id_ ? "check" : "crop"
                        primary: ins.stage.cropping === ins.id_
                        onClicked: ins.stage.cropping = ins.stage.cropping === ins.id_ ? "" : ins.id_
                    }
                    Btn { text: "Odbij"; icon: "mirror"; onClicked: ins.set({ flipX: ins.el.flipX ? null : true }) }
                }
                ValueSlider {
                    label: "Powiększenie"
                    from: 1; to: 5; step: 0.05
                    value: ins.el.zoom || 1
                    shown: value * 100; suffix: "%"
                    onMoved: (v, done) => ins.set({ zoom: v > 1.001 ? v : null }, done)
                }
            }
            Section {
                visible: ins.type === "image" && !!ins.el.src
                title: "Filtr"
                Grid {
                    columns: 4
                    spacing: 6
                    Repeater {
                        model: ins.filters
                        delegate: HoverButton {
                            id: ft
                            required property var modelData
                            readonly property bool on: (ins.el.filter || "") === modelData.id
                            width: (col.width - 18) / 4; height: width + 18
                            radius: 8
                            baseColor: on ? Theme.accentSoft : "transparent"
                            color: on ? baseColor : hovered ? Theme.hover : baseColor
                            onClicked: ins.set({ filter: modelData.id === "" ? null : modelData.id })
                            ArtView {
                                x: 3; y: 3
                                width: parent.width - 6; height: width
                                project: ins.project
                                element: ins.type === "image" ? { type: "image", src: ins.el.src, w: 100, h: 100, radius: 10,
                                                                    focusX: ins.el.focusX, focusY: ins.el.focusY, filter: ft.modelData.id } : ({})
                            }
                            Text {
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: ft.modelData.label
                                color: ft.on ? Theme.accentText : Theme.text2
                                font.family: Theme.font; font.pixelSize: 10
                            }
                        }
                    }
                }
            }
            Section {
                visible: ins.type === "image" && !!ins.el.src
                title: "Poprawki"
                ValueSlider {
                    label: "Jasność"
                    from: -1; to: 1; step: 0.02
                    value: ins.el.brightness || 0
                    shown: value * 100
                    onMoved: (v, done) => ins.set({ brightness: Math.abs(v) < 0.001 ? null : v }, done)
                }
                ValueSlider {
                    label: "Kontrast"
                    from: -1; to: 1; step: 0.02
                    value: ins.el.contrast || 0
                    shown: value * 100
                    onMoved: (v, done) => ins.set({ contrast: Math.abs(v) < 0.001 ? null : v }, done)
                }
                ValueSlider {
                    label: "Nasycenie"
                    from: -1; to: 1; step: 0.02
                    value: ins.el.saturation || 0
                    shown: value * 100
                    onMoved: (v, done) => ins.set({ saturation: Math.abs(v) < 0.001 ? null : v }, done)
                }
                Btn {
                    visible: !!(ins.el.brightness || ins.el.contrast || ins.el.saturation || ins.el.filter)
                    text: "Przywróć oryginał"
                    onClicked: ins.set({ brightness: null, contrast: null, saturation: null, filter: null })
                }
            }

            // ——— Wspólne ———
            Section {
                visible: ins.type !== "page" && ins.type !== "many" && ins.type !== "locked"
                title: "Wygląd"
                ValueSlider {
                    label: "Przezroczystość"
                    from: 0; to: 1; step: 0.01
                    value: 1 - (ins.el.opacity === undefined ? 1 : ins.el.opacity)
                    shown: value * 100; suffix: "%"
                    onMoved: (v, done) => ins.set({ opacity: Math.round((1 - v) * 100) / 100 }, done)
                }
                ValueSlider {
                    label: "Obrót"
                    from: -180; to: 180; step: 1
                    value: ins.el.rotation || 0
                    suffix: "°"
                    onMoved: (v, done) => ins.set({ rotation: v }, done)
                }
            }
            Section {
                visible: ins.type !== "page" && ins.type !== "many" && ins.type !== "locked"
                title: "Na stronie"
                Row {
                    spacing: 2
                    IconToggle { icon: "alignHLeft"; onClicked: ins.alignTo("left") }
                    IconToggle { icon: "alignHCenter"; onClicked: ins.alignTo("hcenter") }
                    IconToggle { icon: "alignHRight"; onClicked: ins.alignTo("right") }
                    Item { width: 6; height: 1 }
                    IconToggle { icon: "alignTop"; onClicked: ins.alignTo("top") }
                    IconToggle { icon: "alignMiddle"; onClicked: ins.alignTo("vcenter") }
                    IconToggle { icon: "alignBottom"; onClicked: ins.alignTo("bottom") }
                }
                Row {
                    spacing: 2
                    IconToggle { icon: "bringFront"; onClicked: ins.project.arrange(ins.id_, "front") }
                    IconToggle { icon: "layerUp"; onClicked: ins.project.arrange(ins.id_, "up") }
                    IconToggle { icon: "layerDown"; onClicked: ins.project.arrange(ins.id_, "down") }
                    IconToggle { icon: "sendBack"; onClicked: ins.project.arrange(ins.id_, "back") }
                    Item { width: 6; height: 1 }
                    IconToggle { icon: "copy"; onClicked: ins.editor.duplicate() }
                    IconToggle { icon: "lock"; onClicked: ins.editor.setLocked(true) }
                    IconToggle { icon: "trash"; onClicked: ins.editor.remove() }
                }
            }
        }
    }
}
