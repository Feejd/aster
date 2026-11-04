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
    readonly property bool line: type === "shape" && (el.shape === "line" || el.shape === "arrow" || el.shape === "doubleArrow")
    readonly property var bg: project.background
    property var projectColors: []
    Connections { target: ins.project; function onColorsChanged() { colorsTimer.restart(); } }
    Timer { id: colorsTimer; interval: 50; onTriggered: ins.projectColors = ins.project.projectColors() }
    readonly property bool softShadow: !!el.shadow && el.shadowBlur !== undefined
    readonly property bool recolor: type === "vector" && project.recolorable(el.src || "")
    readonly property var filters: [
        { id: "", label: "Brak" }, { id: "gray", label: "Czarno-białe" }, { id: "sepia", label: "Sepia" }, { id: "warm", label: "Ciepłe" },
        { id: "cool", label: "Chłodne" }, { id: "fade", label: "Wyblakłe" }, { id: "vivid", label: "Żywe" }, { id: "duotone", label: "Dwa kolory" }
    ]

    // ——— Tabela ———
    readonly property var cells: type === "table" ? (el.cells || []) : []
    readonly property int rows: cells.length
    readonly property int cols: { let n = 0; for (const r of cells) n = Math.max(n, r.length); return n; }
    function grid() { return cells.map(r => { const o = r.slice(); while (o.length < cols) o.push(""); return o; }); }
    // Zmiana liczby wierszy/kolumn — wysokość rośnie razem z wierszami, żeby nie ścisnąć tekstu
    function resizeTable(dr, dc) {
        const g = grid();
        const R = Math.max(1, rows + dr), C = Math.max(1, cols + dc);
        while (g.length < R) g.push(new Array(C).fill(""));
        g.length = R;
        for (const r of g) { while (r.length < C) r.push(""); r.length = C; }
        const p = { cells: g };
        if (dr !== 0) p.h = Math.round(el.h / rows * R);
        if (dc !== 0) p.w = Math.round(el.w / cols * C);
        set(p);
    }
    function putCell(r, c, t, done) {
        const g = grid();
        g[r][c] = t;
        set({ cells: g }, done);
    }
    // Komórki z arkusza (Calc, Excel, Arkusze Google): tabulatory między kolumnami, nowe wiersze — wiersze tabeli
    function pasteSheet() {
        const t = project.clipboardText().replace(/\r/g, "").replace(/\n+$/, "");
        if (t === "") { editor.app.toast("Schowek jest pusty — skopiuj komórki z arkusza", ""); return; }
        const g = t.split("\n").map(l => l.split("\t").map(c => c.trim()));
        const C = Math.max(...g.map(r => r.length));
        for (const r of g) while (r.length < C) r.push("");
        set({ cells: g, h: Math.round(el.h / Math.max(1, rows) * g.length) });
    }

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
        x: 16; y: 12
        text: ins.type === "many" ? "Zaznaczono: " + ins.count : ins.type === "locked" ? "Zablokowany"
            : ins.type === "code" ? (ins.el.kind === "qr" ? "Kod QR" : "Kod kreskowy") : ins.type === "chart" ? "Wykres"
            : ins.type === "draw" ? "Rysunek" : ins.type === "table" ? "Tabela" : ins.type === "text" ? "Tekst" : ins.type === "image" ? "Zdjęcie" : ins.type === "vector" ? (ins.recolor ? "Ikona" : "Naklejka") : ins.line ? "Linia" : ins.type === "shape" ? "Kształt" : "Strona"
        color: Theme.text
        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold; font.letterSpacing: -0.1
    }

    Flickable {
        id: scroll
        x: 16; y: 36
        width: parent.width - 32
        height: parent.height - y
        contentHeight: col.height + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: scroll.width
            spacing: 6

            // ——— Strona ———
            Section {
                collapsible: true; divider: true
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
                collapsible: true; divider: true
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
            Section {
                collapsible: true; divider: true
                visible: ins.type === "page" && ins.projectColors.length > 1
                title: "Kolory projektu"
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Kliknij kolor, żeby zmienić go na wszystkich stronach naraz."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
                }
                Flow {
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: ins.projectColors
                        delegate: ColorWell {
                            id: pcw
                            required property string modelData
                            value: modelData
                            onClicked: {
                                ins.project.commit();
                                let cur = modelData;
                                ins.editor.pickColor(pcw, modelData, false, (c, done) => {
                                    ins.project.replaceColor(cur, c, done);
                                    if (done) cur = c;
                                });
                            }
                        }
                    }
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
                collapsible: true; divider: true
                visible: ins.type === "many"
                title: "Wyrównaj do siebie"
                Row {
                    spacing: 2
                    IconToggle { icon: "alignHLeft"; onClicked: ins.editor.alignMany("left"); tip: "Do lewej" }
                    IconToggle { icon: "alignHCenter"; onClicked: ins.editor.alignMany("hcenter"); tip: "Do środka w poziomie" }
                    IconToggle { icon: "alignHRight"; onClicked: ins.editor.alignMany("right"); tip: "Do prawej" }
                    Item { width: 6; height: 1 }
                    IconToggle { icon: "alignTop"; onClicked: ins.editor.alignMany("top"); tip: "Do góry" }
                    IconToggle { icon: "alignMiddle"; onClicked: ins.editor.alignMany("vcenter"); tip: "Do środka w pionie" }
                    IconToggle { icon: "alignBottom"; onClicked: ins.editor.alignMany("bottom"); tip: "Do dołu" }
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
                collapsible: true; divider: true
                visible: ins.type === "many"
                title: "Zaznaczone"
                Row {
                    spacing: 8
                    Btn {
                        text: ins.editor.grouped ? "Rozgrupuj" : "Grupuj"
                        icon: "layers"
                        primary: !ins.editor.grouped
                        onClicked: ins.editor.grouped ? ins.editor.ungroup() : ins.editor.group()
                    }
                    Btn { text: "Duplikuj"; icon: "copy"; onClicked: ins.editor.duplicate() }
                }
                Btn { text: "Zablokuj"; icon: "lock"; onClicked: ins.editor.setLocked(true) }
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
                collapsible: true; divider: true
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
                    spacing: 8
                    ColorWell {
                        id: textWell2
                        label: ins.el.color2 ? "Przejście" : "+ przejście"
                        value: ins.el.color2 || ""
                        onClicked: ins.editor.pickColor(textWell2, value, true, (c, done) => ins.set({ color2: c === "" ? null : c }, done))
                    }
                }
                ValueSlider {
                    visible: !!ins.el.color2
                    label: "Kierunek przejścia"
                    from: 0; to: 360; step: 15
                    value: ins.el.gradientAngle === undefined ? 90 : ins.el.gradientAngle
                    suffix: "°"
                    onMoved: (v, done) => ins.set({ gradientAngle: v }, done)
                }
                // Styl liter, wyrównanie i listy — w grupach jak w edytorach tekstu
                Row {
                    spacing: 8
                    Seg {
                        IconToggle { icon: "bold"; tip: "Pogrubienie (Ctrl+B)"; on: (ins.el.weight || 400) >= 600; onClicked: ins.set({ weight: on ? 400 : 700 }) }
                        IconToggle { icon: "italic"; tip: "Kursywa (Ctrl+I)"; on: !!ins.el.italic; onClicked: ins.set({ italic: !on }) }
                        IconToggle { icon: "underline"; tip: "Podkreślenie (Ctrl+U)"; on: !!ins.el.underline; onClicked: ins.set({ underline: !on }) }
                        IconToggle { label: "AA"; tip: "WIELKIE LITERY"; on: !!ins.el.caps; onClicked: ins.set({ caps: !on }) }
                    }
                }
                Row {
                    spacing: 8
                    Seg {
                        IconToggle { icon: "alignLeft"; tip: "Wyrównaj do lewej"; on: !ins.el.align || ins.el.align === "left"; onClicked: ins.set({ align: "left" }) }
                        IconToggle { icon: "alignCenter"; tip: "Wyśrodkuj"; on: ins.el.align === "center"; onClicked: ins.set({ align: "center" }) }
                        IconToggle { icon: "alignRight"; tip: "Wyrównaj do prawej"; on: ins.el.align === "right"; onClicked: ins.set({ align: "right" }) }
                    }
                    Seg {
                        IconToggle { icon: "listBullet"; tip: "Lista punktowana"; on: ins.el.list === "bullet"; onClicked: ins.set({ list: on ? null : "bullet", align: on ? ins.el.align : "left" }) }
                        IconToggle { icon: "listNumber"; tip: "Lista numerowana"; on: ins.el.list === "number"; onClicked: ins.set({ list: on ? null : "number", align: on ? ins.el.align : "left" }) }
                    }
                }
            }
            Section {
                collapsible: true; divider: true
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
                collapsible: true; divider: true
                visible: ins.type === "text"
                title: "Efekty"
                Row {
                    spacing: 8
                    Chip { text: "Obrys"; on: (ins.el.outline || 0) > 0; onClicked: ins.set({ outline: on ? 0 : 0.05, outlineColor: ins.el.outlineColor || "#111111" }) }
                    Chip { text: "Tło"; on: !!ins.el.bg; onClicked: ins.set({ bg: on ? null : "#FFE600" }) }
                    Chip {
                        // Neon: świecenie w kolorze tekstu (miękki cień bez przesunięcia)
                        text: "Neon"
                        on: ins.softShadow && (ins.el.shadowDist || 0) === 0
                        onClicked: ins.set(on ? { shadow: null, shadowBlur: null, shadowDist: null, shadowAngle: null, shadowOpacity: null, shadowColor: null }
                                              : { shadow: true, shadowBlur: Math.round((ins.el.size || 48) * 0.45), shadowDist: 0, shadowOpacity: 0.95, shadowColor: ins.el.color || "#FF2D95" })
                    }
                    ColorWell {
                        id: textBgWell
                        visible: !!ins.el.bg
                        value: ins.el.bg || "#FFE600"
                        onClicked: ins.editor.pickColor(textBgWell, value, false, (c, done) => ins.set({ bg: c }, done))
                    }
                    ColorWell {
                        id: outlineWell
                        visible: (ins.el.outline || 0) > 0
                        value: ins.el.outlineColor || "#111111"
                        onClicked: ins.editor.pickColor(outlineWell, value, false, (c, done) => ins.set({ outlineColor: c }, done))
                    }
                }
                ValueSlider {
                    visible: !!ins.el.bg
                    label: "Zaokrąglenie tła"
                    from: 0; to: 0.6; step: 0.02
                    value: ins.el.bgRadius === undefined ? 0.2 : ins.el.bgRadius
                    shown: value * 100; suffix: "%"
                    onMoved: (v, done) => ins.set({ bgRadius: v }, done)
                }
                ValueSlider {
                    label: "Łuk"
                    from: -1; to: 1; step: 0.02
                    value: ins.el.curve || 0
                    shown: value * 100; suffix: "%"
                    onMoved: (v, done) => {
                        // Szerokość pola idzie za łukiem, środek zostaje na miejscu
                        const patch = { curve: Math.abs(v) < 0.02 ? null : v };
                        const next = Object.assign({}, ins.el, { curve: patch.curve || 0 });
                        const w = patch.curve ? ins.project.naturalWidth(next) : Math.max(ins.el.w, ins.project.naturalWidth(next));
                        patch.w = Math.round(w);
                        patch.x = Math.round((ins.el.x + ins.el.w / 2 - w / 2) * 10) / 10;
                        ins.set(patch, done);
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
                collapsible: true; divider: true
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

            // ——— Tabela ———
            Section {
                collapsible: true; divider: true
                visible: ins.type === "table"
                title: "Treść"
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Dwuklik w komórkę na stronie — pisanie (Tab przechodzi dalej). Można też wkleić komórki skopiowane z arkusza."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.25
                }
                Grid {
                    id: cellGrid
                    columns: Math.max(1, ins.cols)
                    spacing: 4
                    Repeater {
                        model: ins.type === "table" && ins.cols <= 5 && ins.rows <= 12 ? ins.rows * ins.cols : 0
                        delegate: TextBox {
                            required property int index
                            readonly property int r: Math.floor(index / ins.cols)
                            readonly property int c: index % ins.cols
                            width: (col.width - (ins.cols - 1) * 4) / ins.cols
                            text: (ins.cells[r] || [])[c] || ""
                            onEdited: (t, done) => ins.putCell(r, c, t, done)
                        }
                    }
                }
                Btn { text: "Wklej z arkusza"; icon: "copy"; onClicked: ins.pasteSheet() }
                Row {
                    spacing: 6
                    Text { width: 70; anchors.verticalCenter: parent.verticalCenter; text: "Wiersze"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                    IconToggle { icon: "minus"; enabled: ins.rows > 1; tip: "Usuń ostatni wiersz"; onClicked: ins.resizeTable(-1, 0) }
                    Text { width: 24; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignHCenter; text: ins.rows; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                    IconToggle { icon: "plus"; tip: "Dodaj wiersz"; onClicked: ins.resizeTable(1, 0) }
                }
                Row {
                    spacing: 6
                    Text { width: 70; anchors.verticalCenter: parent.verticalCenter; text: "Kolumny"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                    IconToggle { icon: "minus"; enabled: ins.cols > 1; tip: "Usuń ostatnią kolumnę"; onClicked: ins.resizeTable(0, -1) }
                    Text { width: 24; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignHCenter; text: ins.cols; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                    IconToggle { icon: "plus"; tip: "Dodaj kolumnę"; onClicked: ins.resizeTable(0, 1) }
                }
            }
            Section {
                collapsible: true; divider: true
                visible: ins.type === "table"
                title: "Wygląd tabeli"
                Flow {
                    width: parent.width
                    spacing: 6
                    Chip { text: "Nagłówek"; on: ins.el.header !== false; onClicked: ins.set({ header: on ? false : null }) }
                    Chip {
                        text: "Paski"; on: !!ins.el.stripe
                        onClicked: ins.set({ stripe: on ? null : "#F2F4F7" })
                    }
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: [{ id: "rows", label: "Linie" }, { id: "grid", label: "Siatka" }, { id: "none", label: "Bez linii" }]
                        delegate: Chip {
                            required property var modelData
                            text: modelData.label
                            on: (ins.el.lines || "rows") === modelData.id
                            onClicked: ins.set({ lines: modelData.id })
                        }
                    }
                }
                Flow {
                    width: parent.width
                    spacing: 8
                    ColorWell {
                        id: thFill
                        visible: ins.el.header !== false
                        label: "Nagłówek"
                        value: ins.el.headerFill || "#16181D"
                        onClicked: ins.editor.pickColor(thFill, value, true, (c, done) => ins.set({ headerFill: c }, done))
                    }
                    ColorWell {
                        id: thInk
                        visible: ins.el.header !== false
                        label: "Napis nagłówka"
                        value: ins.el.headerColor || "#FFFFFF"
                        onClicked: ins.editor.pickColor(thInk, value, false, (c, done) => ins.set({ headerColor: c }, done))
                    }
                    ColorWell {
                        id: tdFill
                        label: "Tło"
                        value: ins.el.fill || ""
                        onClicked: ins.editor.pickColor(tdFill, value, true, (c, done) => ins.set({ fill: c }, done))
                    }
                    ColorWell {
                        id: tdStripe
                        visible: !!ins.el.stripe
                        label: "Paski"
                        value: ins.el.stripe || ""
                        onClicked: ins.editor.pickColor(tdStripe, value, true, (c, done) => ins.set({ stripe: c === "" ? null : c }, done))
                    }
                    ColorWell {
                        id: tdInk
                        label: "Tekst"
                        value: ins.el.color || "#3D4048"
                        onClicked: ins.editor.pickColor(tdInk, value, false, (c, done) => ins.set({ color: c }, done))
                    }
                    ColorWell {
                        id: tdLine
                        visible: (ins.el.lines || "rows") !== "none"
                        label: "Linie"
                        value: ins.el.stroke || "#D9DCE3"
                        onClicked: ins.editor.pickColor(tdLine, value, false, (c, done) => ins.set({ stroke: c }, done))
                    }
                }
                Btn {
                    id: tblFont
                    text: ins.el.font || "Geist"
                    icon: "textT"
                    onClicked: ins.editor.pickFont(tblFont, ins.el.font || "Geist", (f) => ins.set({ font: f }))
                }
                Row {
                    spacing: 2
                    IconToggle { icon: "alignLeft"; on: (ins.el.align || "left") === "left"; tip: "Do lewej"; onClicked: ins.set({ align: null }) }
                    IconToggle { icon: "alignCenter"; on: ins.el.align === "center"; tip: "Do środka"; onClicked: ins.set({ align: "center" }) }
                    IconToggle { icon: "alignRight"; on: ins.el.align === "right"; tip: "Do prawej"; onClicked: ins.set({ align: "right" }) }
                }
                ValueSlider {
                    label: "Wielkość tekstu"
                    from: 6; to: Math.max(40, Math.round(Math.min(ins.project.pageWidth, ins.project.pageHeight) * 0.06)); step: 1
                    value: ins.el.size || 24
                    suffix: " px"
                    onMoved: (v, done) => ins.set({ size: v }, done)
                }
                ValueSlider {
                    visible: (ins.el.lines || "rows") !== "none"
                    label: "Grubość linii"
                    from: 0; to: 12; step: 0.5; decimals: 1
                    value: ins.el.strokeWidth === undefined ? 2 : ins.el.strokeWidth
                    suffix: " px"
                    onMoved: (v, done) => ins.set({ strokeWidth: v }, done)
                }
                ValueSlider {
                    label: "Zaokrąglenie rogów"
                    from: 0; to: Math.round(Math.min(ins.el.w || 0, ins.el.h || 0) / 4); step: 1
                    value: ins.el.radius || 0
                    suffix: " px"
                    onMoved: (v, done) => ins.set({ radius: v }, done)
                }
            }

            // ——— Rysunek ———
            Section {
                collapsible: true; divider: true
                visible: ins.type === "draw"
                title: "Pisak"
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: [{ id: "pen", label: "Pisak" }, { id: "marker", label: "Marker" }, { id: "highlighter", label: "Zakreślacz" }, { id: "neon", label: "Neon" }]
                        delegate: Chip {
                            required property var modelData
                            text: modelData.label
                            on: (ins.el.pen || "pen") === modelData.id
                            onClicked: ins.set({ pen: modelData.id })
                        }
                    }
                }
                ColorWell {
                    id: drawStroke
                    label: "Kolor"
                    value: ins.el.stroke || "#16181D"
                    onClicked: ins.editor.pickColor(drawStroke, value, false, (c, done) => ins.set({ stroke: c }, done))
                }
                ValueSlider {
                    label: "Grubość"
                    from: 1; to: Math.max(20, Math.round(Math.min(ins.project.pageWidth, ins.project.pageHeight) * 0.08)); step: 1
                    value: ins.el.strokeWidth || 8
                    suffix: " px"
                    onMoved: (v, done) => ins.set({ strokeWidth: v }, done)
                }
            }

            // ——— Zdjęcie ———
            Section {
                collapsible: true; divider: true
                visible: ins.type === "image"
                title: "Kształt zdjęcia"
                Grid {
                    columns: 5
                    spacing: 4
                    Repeater {
                        model: [{ id: "", shape: "rect" }, { id: "ellipse", shape: "ellipse" }, { id: "arch", mask: "arch" }, { id: "leaf", mask: "leaf" },
                                { id: "blob", mask: "blob" }, { id: "hexagon", mask: "hexagon" }, { id: "heart", shape: "heart" }, { id: "star", shape: "star" },
                                { id: "triangle", shape: "triangle" }]
                        delegate: IconToggle {
                            id: mk
                            required property var modelData
                            width: (col.width - 16) / 5; height: width
                            on: (ins.el.mask || "") === modelData.id
                            onClicked: ins.set({ mask: modelData.id === "" ? null : modelData.id })
                            ArtView {
                                anchors.centerIn: parent
                                width: parent.width * 0.56; height: width
                                element: ({ type: "shape", shape: mk.modelData.shape || mk.modelData.mask, w: 100, h: 100, fill: Theme.dark ? "#C9CDD6" : "#5C6170", radius: 0 })
                                opacity: mk.on ? 1 : 0.75
                            }
                        }
                    }
                }
                ValueSlider {
                    visible: !ins.el.mask
                    label: "Zaokrąglenie rogów"
                    from: 0; to: Math.round(Math.min(ins.el.w || 0, ins.el.h || 0) / 2); step: 1
                    value: ins.el.radius || 0
                    suffix: " px"
                    onMoved: (v, done) => ins.set({ radius: v }, done)
                }
                Row {
                    spacing: 8
                    ColorWell {
                        id: frameWell
                        label: ins.el.stroke ? "Obramowanie" : "+ obramowanie"
                        value: ins.el.stroke || ""
                        onClicked: ins.editor.pickColor(frameWell, value, true, (c, done) => {
                            const p = { stroke: c === "" ? null : c };
                            if (c !== "" && !(ins.el.strokeWidth > 0)) p.strokeWidth = Math.max(2, Math.round(Math.min(ins.el.w, ins.el.h) * 0.03));
                            ins.set(p, done);
                        })
                    }
                }
                ValueSlider {
                    visible: !!ins.el.stroke
                    label: "Grubość obramowania"
                    from: 1; to: Math.max(10, Math.round(Math.min(ins.el.w || 0, ins.el.h || 0) * 0.15)); step: 1
                    value: ins.el.strokeWidth || 0
                    suffix: " px"
                    onMoved: (v, done) => ins.set({ strokeWidth: v }, done)
                }
                Text {
                    visible: !!ins.el.credit
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Licencja wymaga podpisu autora: " + (ins.el.credit || "")
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.25
                }
                Btn {
                    visible: !!ins.el.credit
                    text: "Dodaj podpis na grafice"
                    icon: "textT"
                    onClicked: ins.editor.addCredit(ins.id_)
                }
                Row {
                    spacing: 8
                    Btn { text: ins.el.src ? "Zamień…" : "Wybierz…"; icon: "image"; onClicked: ins.editor.chooseImage("replace") }
                    Btn { visible: !!ins.el.src; text: "Jako tło"; onClicked: ins.editor.imageToBackground(ins.id_) }
                }
            }
            // Narzędzia AI — małe modele na komputerze, pobierane przy pierwszym użyciu
            Section {
                collapsible: true; divider: true
                visible: ins.type === "image" && !!ins.el.src && Magic.available
                title: "Magia AI"
                Btn {
                    width: parent.width
                    primary: true
                    icon: "sparkles"
                    text: "Usuń tło"
                    enabled: !Magic.busy
                    onClicked: Magic.removeBackground(ins.project, ins.id_)
                }
                Btn {
                    width: parent.width
                    icon: "brush"
                    text: "Gumka i wyodrębnianie"
                    enabled: !Magic.busy
                    onClicked: ins.editor.startMagic()
                }
                // Rozmycie tła: siła zapamiętana w elemencie, dopóki zdjęcie jest wynikiem rozmycia
                Text {
                    text: "Rozmyj tło (jak portret w telefonie)"
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    readonly property real level: ins.el.bgBlurOut && ins.el.bgBlurOut === ins.el.src ? (ins.el.bgBlur || 0) : 0
                    Repeater {
                        model: [{ v: 0, label: "Ostre" }, { v: 0.35, label: "Lekko" }, { v: 0.7, label: "Mocno" }, { v: 1, label: "Bardzo" }]
                        delegate: Chip {
                            required property var modelData
                            width: (col.width - 18) / 4
                            text: modelData.label
                            on: Math.abs(parent.level - modelData.v) < 0.01
                            enabled: !Magic.busy
                            onClicked: if (!on) Magic.blurBackground(ins.project, ins.id_, modelData.v)
                        }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    readonly property int mb: ins.id_ !== "" && !Magic.busy ? Magic.downloadMB("background") + Magic.downloadMB("object") + Magic.downloadMB("erase") : 0
                    text: "Usuwa albo rozmywa tło, usuwa niechciane rzeczy ze zdjęcia albo wycina obiekt jako osobny element. Działa na tym komputerze — zdjęcia nigdzie nie wychodzą."
                          + (mb > 0 ? " Za pierwszym razem pobierze modele (do " + mb + " MB)." : "")
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; lineHeight: 1.2
                }
            }
            Section {
                collapsible: true; divider: true
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
                collapsible: true; divider: true
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
                                element: ins.type === "image" ? { type: "image", src: ins.el.src, w: 100, h: 100, radius: 10, duo1: ins.el.duo1, duo2: ins.el.duo2,
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
                collapsible: true; divider: true
                visible: ins.type === "image" && !!ins.el.src
                title: "Poprawki"
                Row {
                    visible: ins.el.filter === "duotone"
                    spacing: 8
                    ColorWell {
                        id: duoWell1
                        label: "Cienie"
                        value: ins.el.duo1 || "#1E2A78"
                        onClicked: ins.editor.pickColor(duoWell1, value, false, (c, done) => ins.set({ duo1: c }, done))
                    }
                    ColorWell {
                        id: duoWell2
                        label: "Światła"
                        value: ins.el.duo2 || "#FFB3C7"
                        onClicked: ins.editor.pickColor(duoWell2, value, false, (c, done) => ins.set({ duo2: c }, done))
                    }
                }
                Btn {
                    width: parent.width
                    icon: "sparkles"
                    text: "Popraw automatycznie"
                    tip: "Dobiera jasność, kontrast i nasycenie do tego zdjęcia"
                    onClicked: {
                        const p = ins.project.autoEnhance(ins.el.src || "");
                        for (const k in p) if (Math.abs(p[k]) < 0.01) p[k] = null;
                        ins.set(p);
                    }
                }
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
                ValueSlider {
                    label: "Rozmycie"
                    from: 0; to: 1; step: 0.02
                    value: ins.el.blur || 0
                    shown: value * 100
                    onMoved: (v, done) => ins.set({ blur: v < 0.01 ? null : v }, done)
                }
                ValueSlider {
                    label: "Winieta (ciemne brzegi)"
                    from: 0; to: 1; step: 0.02
                    value: ins.el.vignette || 0
                    shown: value * 100
                    onMoved: (v, done) => ins.set({ vignette: v < 0.01 ? null : v }, done)
                }
                Btn {
                    visible: !!(ins.el.brightness || ins.el.contrast || ins.el.saturation || ins.el.filter || ins.el.blur || ins.el.vignette)
                    text: "Przywróć oryginał"
                    onClicked: ins.set({ brightness: null, contrast: null, saturation: null, filter: null, blur: null, vignette: null })
                }
            }
            Section {
                collapsible: true; divider: true
                visible: ins.type === "image" && !!ins.el.src
                title: Magic.available ? "Jednolite tło (bez AI)" : "Tło zdjęcia"
                Chip {
                    text: ins.el.removeBg ? "Tło usunięte" : "Usuń jednolite tło"
                    on: !!ins.el.removeBg
                    onClicked: ins.set({ removeBg: on ? null : true, bgTolerance: on ? null : 0.25 })
                }
                ValueSlider {
                    visible: !!ins.el.removeBg
                    label: "Czułość"
                    from: 0.03; to: 0.8; step: 0.01
                    value: ins.el.bgTolerance === undefined ? 0.25 : ins.el.bgTolerance
                    shown: value * 100
                    onMoved: (v, done) => ins.set({ bgTolerance: v }, done)
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Działa na zdjęciach z jednolitym tłem (np. przedmiot na białym). Większa czułość usuwa więcej."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; lineHeight: 1.2
                }
            }

            // ——— Kod QR i kreskowy ———
            Section {
                collapsible: true; divider: true
                visible: ins.type === "code"
                title: "Rodzaj"
                Flow {
                    width: parent.width
                    spacing: 6
                    Chip { text: "Link / tekst"; on: ins.el.kind === "qr" && ins.el.qrType !== "wifi"; onClicked: ins.set({ kind: "qr", qrType: null, h: ins.el.w }) }
                    Chip { text: "Wi-Fi"; on: ins.el.qrType === "wifi"; onClicked: ins.set({ kind: "qr", qrType: "wifi", ssid: ins.el.ssid || "", pass: ins.el.pass || "", h: ins.el.w }) }
                    Chip { text: "Kod kreskowy"; on: ins.el.kind === "code128"; onClicked: ins.set({ kind: "code128", qrType: null, h: Math.round(ins.el.w * 0.35) }) }
                    Chip { text: "EAN-13"; on: ins.el.kind === "ean13"; onClicked: ins.set({ kind: "ean13", qrType: null, data: /^\d{12,13}$/.test(ins.el.data || "") ? ins.el.data : "590123412345", h: Math.round(ins.el.w * 0.45) }) }
                }
                TextBox {
                    visible: ins.el.qrType !== "wifi"
                    label: ins.el.kind === "qr" ? "Adres strony albo tekst" : ins.el.kind === "ean13" ? "12 albo 13 cyfr" : "Treść kodu"
                    text: ins.el.data || ""
                    placeholder: "https://…"
                    onEdited: (t, done) => ins.set({ data: t }, done)
                }
                TextBox {
                    visible: ins.el.qrType === "wifi"
                    label: "Nazwa sieci"
                    text: ins.el.ssid || ""
                    onEdited: (t, done) => ins.set({ ssid: t }, done)
                }
                TextBox {
                    visible: ins.el.qrType === "wifi"
                    label: "Hasło (puste — sieć bez hasła)"
                    text: ins.el.pass || ""
                    secret: true
                    onEdited: (t, done) => ins.set({ pass: t }, done)
                }
                Text {
                    visible: ins.el.qrType === "wifi"
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Goście zeskanują kod aparatem telefonu i połączą się bez przepisywania hasła."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.25
                }
                Row {
                    spacing: 8
                    ColorWell {
                        id: codeWell
                        label: "Kod"
                        value: ins.el.color || "#000000"
                        onClicked: ins.editor.pickColor(codeWell, value, false, (c, done) => ins.set({ color: c }, done))
                    }
                    ColorWell {
                        id: codeBgWell
                        label: "Tło"
                        value: ins.el.bg === undefined ? "#FFFFFF" : ins.el.bg
                        onClicked: ins.editor.pickColor(codeBgWell, value, true, (c, done) => ins.set({ bg: c }, done))
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Ciemny kod na jasnym tle skanuje się najpewniej."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                }
            }

            // ——— Wykres ———
            Section {
                collapsible: true; divider: true
                visible: ins.type === "chart"
                title: "Rodzaj wykresu"
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: [{ id: "column", label: "Słupki" }, { id: "bar", label: "Poziome" }, { id: "line", label: "Linia" }, { id: "pie", label: "Koło" }, { id: "donut", label: "Pierścień" }]
                        delegate: Chip {
                            required property var modelData
                            text: modelData.label
                            on: (ins.el.chart || "column") === modelData.id
                            onClicked: ins.set({ chart: modelData.id })
                        }
                    }
                }
            }
            Section {
                collapsible: true; divider: true
                visible: ins.type === "chart"
                title: "Dane"
                Repeater {
                    model: ins.type === "chart" ? (ins.el.data || []).length : 0
                    delegate: Row {
                        id: drow
                        required property int index
                        readonly property var item: (ins.el.data || [])[index] || ({})
                        spacing: 6
                        function put(patch, done) {
                            const list = (ins.el.data || []).map(o => Object.assign({}, o));
                            Object.assign(list[drow.index], patch);
                            ins.set({ data: list }, done);
                        }
                        ColorWell {
                            id: dWell
                            value: drow.item.color || ["#5B7CFA", "#FF7A59", "#22B07D", "#FFB300", "#E53961", "#7E57C2", "#00ACC1", "#8D6E63"][drow.index % 8]
                            onClicked: ins.editor.pickColor(dWell, value, false, (c, done) => drow.put({ color: c }, done))
                        }
                        TextBox { width: 110; text: drow.item.label || ""; placeholder: "Podpis"; onEdited: (t, done) => drow.put({ label: t }, done) }
                        TextBox {
                            width: 62; numeric: true
                            text: drow.item.value === undefined ? "" : String(drow.item.value)
                            onEdited: (t, done) => { const v = Number(t.replace(",", ".")); if (!isNaN(v)) drow.put({ value: v }, done); }
                        }
                        IconToggle {
                            icon: "trash"
                            onClicked: ins.set({ data: (ins.el.data || []).filter((o, i) => i !== drow.index) })
                        }
                    }
                }
                Row {
                    spacing: 8
                    Btn { text: "Dodaj wiersz"; icon: "plus"; onClicked: ins.set({ data: (ins.el.data || []).concat([{ label: "Nowy", value: 10 }]) }) }
                    Chip { text: "Wartości"; on: ins.el.values !== false; onClicked: ins.set({ values: on ? false : null }) }
                }
                Row {
                    spacing: 8
                    ColorWell {
                        id: chartInk
                        label: "Napisy"
                        value: ins.el.color || "#3D4048"
                        onClicked: ins.editor.pickColor(chartInk, value, false, (c, done) => ins.set({ color: c }, done))
                    }
                }
                ValueSlider {
                    label: "Wielkość napisów"
                    from: 6; to: Math.max(40, Math.round(Math.min(ins.project.pageWidth, ins.project.pageHeight) * 0.06)); step: 1
                    value: ins.el.size || 24
                    suffix: " px"
                    onMoved: (v, done) => ins.set({ size: v }, done)
                }
            }

            // ——— Ikona, naklejka ———
            Section {
                collapsible: true; divider: true
                visible: ins.type === "vector"
                title: ins.recolor ? "Kolor" : "Naklejka"
                Row {
                    spacing: 8
                    ColorWell {
                        id: vecWell
                        visible: ins.recolor
                        label: "Kolor"
                        value: ins.el.color || "#16181D"
                        onClicked: ins.editor.pickColor(vecWell, value, false, (c, done) => ins.set({ color: c }, done))
                    }
                    Btn { text: "Odbij"; icon: "mirror"; onClicked: ins.set({ flipX: ins.el.flipX ? null : true }) }
                }
                Text {
                    visible: !ins.recolor
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Naklejki są wielokolorowe — ich kolorów nie da się zmienić. Jednokolorowe znajdziesz wśród ikon."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.25
                }
            }

            // ——— Wspólne ———
            Section {
                collapsible: true; divider: true
                visible: ins.type !== "page" && ins.type !== "many" && ins.type !== "locked" && !ins.line
                title: "Cień"
                Row {
                    spacing: 8
                    Chip {
                        text: ins.softShadow ? "Włączony" : "Dodaj cień"
                        on: ins.softShadow
                        onClicked: ins.set(on ? { shadow: null, shadowBlur: null, shadowDist: null, shadowAngle: null, shadowOpacity: null }
                                              : { shadow: true, shadowBlur: Math.round(Math.max(6, Math.min(ins.el.w, ins.el.h) * 0.06)),
                                                  shadowDist: Math.round(Math.max(4, Math.min(ins.el.w, ins.el.h) * 0.04)), shadowAngle: 160, shadowOpacity: 0.35 })
                    }
                    ColorWell {
                        id: shadowWell
                        visible: ins.softShadow
                        value: ins.el.shadowColor || "#000000"
                        onClicked: ins.editor.pickColor(shadowWell, value, false, (c, done) => ins.set({ shadowColor: c }, done))
                    }
                }
                ValueSlider {
                    visible: ins.softShadow
                    label: "Rozmycie"
                    from: 0; to: Math.max(40, Math.round(Math.min(ins.project.pageWidth, ins.project.pageHeight) * 0.08)); step: 1
                    value: ins.el.shadowBlur || 0
                    suffix: " px"
                    onMoved: (v, done) => ins.set({ shadowBlur: v }, done)
                }
                ValueSlider {
                    visible: ins.softShadow
                    label: "Odległość"
                    from: 0; to: Math.max(30, Math.round(Math.min(ins.project.pageWidth, ins.project.pageHeight) * 0.05)); step: 1
                    value: ins.el.shadowDist || 0
                    suffix: " px"
                    onMoved: (v, done) => ins.set({ shadowDist: v }, done)
                }
                ValueSlider {
                    visible: ins.softShadow
                    label: "Kierunek"
                    from: 0; to: 360; step: 5
                    value: ins.el.shadowAngle === undefined ? 135 : ins.el.shadowAngle
                    suffix: "°"
                    onMoved: (v, done) => ins.set({ shadowAngle: v }, done)
                }
                ValueSlider {
                    visible: ins.softShadow
                    label: "Siła"
                    from: 0.05; to: 1; step: 0.01
                    value: ins.el.shadowOpacity === undefined ? 0.35 : ins.el.shadowOpacity
                    shown: value * 100; suffix: "%"
                    onMoved: (v, done) => ins.set({ shadowOpacity: v }, done)
                }
            }
            Section {
                collapsible: true; divider: true
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
                collapsible: true; divider: true
                visible: ins.type !== "page" && ins.type !== "many" && ins.type !== "locked"
                title: "Na stronie"
                Row {
                    spacing: 2
                    IconToggle { icon: "alignHLeft"; onClicked: ins.alignTo("left"); tip: "Do lewej krawędzi strony" }
                    IconToggle { icon: "alignHCenter"; onClicked: ins.alignTo("hcenter"); tip: "Na środek strony w poziomie" }
                    IconToggle { icon: "alignHRight"; onClicked: ins.alignTo("right"); tip: "Do prawej krawędzi strony" }
                    Item { width: 6; height: 1 }
                    IconToggle { icon: "alignTop"; onClicked: ins.alignTo("top"); tip: "Do górnej krawędzi strony" }
                    IconToggle { icon: "alignMiddle"; onClicked: ins.alignTo("vcenter"); tip: "Na środek strony w pionie" }
                    IconToggle { icon: "alignBottom"; onClicked: ins.alignTo("bottom"); tip: "Do dolnej krawędzi strony" }
                }
                Row {
                    spacing: 2
                    IconToggle { icon: "bringFront"; tip: "Na wierzch (Ctrl+Shift+])"; onClicked: ins.project.arrange(ins.id_, "front") }
                    IconToggle { icon: "layerUp"; tip: "Do przodu (Ctrl+])"; onClicked: ins.project.arrange(ins.id_, "up") }
                    IconToggle { icon: "layerDown"; tip: "Do tyłu (Ctrl+[)"; onClicked: ins.project.arrange(ins.id_, "down") }
                    IconToggle { icon: "sendBack"; tip: "Na spód (Ctrl+Shift+[)"; onClicked: ins.project.arrange(ins.id_, "back") }
                    Item { width: 6; height: 1 }
                    IconToggle { icon: "copy"; onClicked: ins.editor.duplicate(); tip: "Duplikuj (Ctrl+D)" }
                    IconToggle { icon: "lock"; onClicked: ins.editor.setLocked(true); tip: "Zablokuj" }
                    IconToggle { icon: "trash"; onClicked: ins.editor.remove(); tip: "Usuń (Delete)" }
                }
            }
        }
    }

    // Grupa przycisków na wspólnym tle
    component Seg: Rectangle {
        default property alias buttons: segRow.children
        width: segRow.implicitWidth + 4; height: 36
        radius: 10
        color: Theme.fill
        Row { id: segRow; anchors.centerIn: parent; spacing: 0 }
    }
}
