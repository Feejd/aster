pragma ComponentBehavior: Bound
import QtQuick
import QtCore
import Aster.Ui
import Aster.Grafika

// Panel po lewej: Szablony, Tekst, Elementy (kształty, ikony i naklejki z internetu), Zdjęcia (z dysku i darmowe
// z internetu), Tło — kliknięcie dodaje element na środek strony;
// Warstwy — lista elementów od wierzchu: zaznaczanie, ukrywanie, blokowanie i kolejność (przeciąganie)
Item {
    id: sp
    required property Project project
    property var editor                      // EditorPage (dodawanie elementów, okna wyboru plików)
    property string tab: "templates"
    property bool showRail: true             // pasek kart z lewej (w układzie z narzędziami po prawej — ukryty)
    property var photos: []

    readonly property real base: Math.min(project.pageWidth, project.pageHeight)
    readonly property var tabs: [
        { id: "templates", label: "Szablony", icon: "layout" },
        { id: "text", label: "Tekst", icon: "textT" },
        { id: "shapes", label: "Elementy", icon: "shapes" },
        { id: "photos", label: "Zdjęcia", icon: "image" },
        { id: "draw", label: "Rysuj", icon: "squiggle" },
        { id: "paint", label: "Maluj i retuszuj", icon: "brush" },
        { id: "background", label: "Tło", icon: "palette" },
        { id: "layers", label: "Warstwy", icon: "layers" }
    ]
    // ——— Rysowanie: narzędzie, kolor i grubość (część krótszego boku strony, osobno dla każdego pisaka) ———
    property string drawTool: "pen"
    property color drawColor: "#16181D"
    property var drawSizes: ({ pen: 0.006, marker: 0.016, highlighter: 0.03, neon: 0.01 })
    readonly property real drawWidth: Math.max(1, Math.round(base * (drawSizes[drawTool] || 0.01) * 10) / 10)
    property string lastTab: "select"       // karta sprzed rysowania (Gotowe / Esc wraca do niej)
    readonly property var pens: [
        { id: "pen", label: "Pisak" }, { id: "marker", label: "Marker" },
        { id: "highlighter", label: "Zakreślacz" }, { id: "neon", label: "Neon" }
    ]
    readonly property var drawColors: ["#16181D", "#FFFFFF", "#E53935", "#FF7A00", "#FFD400", "#22B07D", "#1E88E5", "#5B3BE8", "#E040FB", "#8D6E63",
                                       "#00E5FF", "#76FF03"]
    readonly property var sample: [0.04, 0.7, 0.16, 0.38, 0.3, 0.22, 0.44, 0.42, 0.56, 0.7, 0.7, 0.62, 0.82, 0.3, 0.96, 0.36]
    function setDrawSize(px) {
        const m = Object.assign({}, drawSizes);
        m[drawTool] = px / base;
        drawSizes = m;
    }
    property string prevTab: "select"

    // ——— Malowanie i retusz: ustawienia osobno dla każdego narzędzia, rozmiar w częściach krótszego boku strony ———
    property string paintTool: "brush"
    property color paintColor: "#16181D"
    property var paintSizes: ({ brush: 0.03, eraser: 0.05, heal: 0.03, clone: 0.04, dodge: 0.08, burn: 0.08, smudge: 0.05, blur: 0.06 })
    property var paintPower: ({ brush: 1, eraser: 1, clone: 1, dodge: 0.5, burn: 0.5, smudge: 0.7, blur: 1 })
    property real paintHardness: 0.7
    property real fillTolerance: 0.15
    readonly property real paintSize: Math.max(1, Math.round(base * (paintSizes[paintTool] || 0.04)))
    readonly property real paintStrength: paintPower[paintTool] === undefined ? 1 : paintPower[paintTool]
    readonly property bool paintHasSize: paintTool !== "fill" && paintTool !== "pick"
    readonly property bool paintHasColor: paintTool === "brush" || paintTool === "fill"
    readonly property var paintTools: [
        { id: "brush", label: "Pędzel", icon: "brush", key: "B", hint: "Maluje kolorem. Bez zaznaczonego zdjęcia tworzy nową warstwę do malowania." },
        { id: "eraser", label: "Gumka", icon: "eraser", key: "E", hint: "Ściera piksele warstwy do przezroczystości." },
        { id: "fill", label: "Wypełnij", icon: "droplet", key: "G", hint: "Klik wypełnia kolorem podobny obszar." },
        { id: "pick", label: "Pipeta", icon: "pipette", key: "I", hint: "Klik pobiera kolor ze strony do pędzla." },
        { id: "heal", label: "Korektor AI", icon: "sparkles", key: "J", hint: "Zamaluj plamkę, kabel albo przechodnia — zniknie, a tło uzupełni się samo." },
        { id: "clone", label: "Stempel", icon: "stamp", key: "S", hint: "Alt+klik wskazuje źródło, potem pędzel kopiuje stamtąd piksele." },
        { id: "dodge", label: "Rozjaśnij", icon: "neon", key: "", hint: "Rozjaśnia malowane miejsca." },
        { id: "burn", label: "Ściemnij", icon: "moon", key: "", hint: "Ściemnia malowane miejsca." },
        { id: "smudge", label: "Rozmaż", icon: "squiggle", key: "", hint: "Ciągnie piksele jak palec po mokrej farbie." },
        { id: "blur", label: "Rozmyj", icon: "circleHalf", key: "", hint: "Zmiękcza malowane miejsca." }
    ]
    readonly property string paintHint: { for (const t of paintTools) if (t.id === paintTool) return t.hint; return ""; }
    function setPaintSize(px) { const m = Object.assign({}, paintSizes); m[paintTool] = px / base; paintSizes = m; }
    function setPaintPower(v) { const m = Object.assign({}, paintPower); m[paintTool] = v; paintPower = m; }
    onTabChanged: {
        if (tab !== "draw" && tab !== "paint") prevTab = tab; else lastTab = prevTab;
        if (tab === "photos") photos = Library.photos();
        if (tab === "layers") refreshLayers();
    }

    // Kolaże: prostokąty [x, y, w, h] w częściach strony
    readonly property var collages: [
        { rects: [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1]] },
        { rects: [[0, 0, 1, 0.5], [0, 0.5, 1, 0.5]] },
        { rects: [[0, 0, 0.5, 0.5], [0.5, 0, 0.5, 0.5], [0, 0.5, 0.5, 0.5], [0.5, 0.5, 0.5, 0.5]] },
        { rects: [[0, 0, 0.62, 1], [0.62, 0, 0.38, 0.5], [0.62, 0.5, 0.38, 0.5]] },
        { rects: [[0, 0, 1, 0.6], [0, 0.6, 0.5, 0.4], [0.5, 0.6, 0.5, 0.4]] },
        { rects: [[0, 0, 0.333, 1], [0.333, 0, 0.334, 1], [0.667, 0, 0.333, 1]] },
        { rects: [[0, 0, 0.5, 0.333], [0.5, 0, 0.5, 0.333], [0, 0.333, 0.5, 0.334], [0.5, 0.333, 0.5, 0.334], [0, 0.667, 0.5, 0.333], [0.5, 0.667, 0.5, 0.333]] },
        { rects: [[0, 0, 0.333, 0.333], [0.333, 0, 0.334, 0.333], [0.667, 0, 0.333, 0.333], [0, 0.333, 0.333, 0.334], [0.333, 0.333, 0.334, 0.334],
                  [0.667, 0.333, 0.333, 0.334], [0, 0.667, 0.333, 0.333], [0.333, 0.667, 0.334, 0.333], [0.667, 0.667, 0.333, 0.333]] },
        { rects: [[0.08, 0.08, 0.84, 0.62]] }
    ]

    // ——— Z internetu ———
    property string gQuery: ""
    property var icons: []
    property var stickers: []
    property int gLoading: 0
    property bool gFailed: false
    property string pQuery: ""
    property var webPhotos: []
    property int pPage: 1
    property bool pMore: false
    property bool pLoading: false
    property bool pFailed: false
    readonly property var graphicIdeas: ["serce", "gwiazda", "kwiat", "liść", "kawa", "prezent", "tort", "balon", "konfetti", "korona",
                                         "strzałka", "telefon", "poczta", "lokalizacja", "muzyka", "słońce", "uśmiech", "ptaszek"]
    readonly property var photoIdeas: ["natura", "góry", "morze", "kwiaty", "kawa", "jedzenie", "miasto", "praca", "zima", "lato", "tekstura", "tło"]
    readonly property string iconTint: Theme.dark ? "ECEEF3" : "16181D"

    function searchGraphics(q) {
        gQuery = q; icons = []; stickers = []; gFailed = false;
        if (q === "") { gLoading = 0; return; }
        gLoading = 2;
        Online.searchGraphics(q, "icons", "#" + iconTint);
        Online.searchGraphics(q, "stickers");
    }
    function searchPhotos(q) {
        pQuery = q; webPhotos = []; pPage = 1; pMore = false; pFailed = false;
        pLoading = q !== "";
        if (q !== "") Online.searchPhotos(q, 1);
    }
    function morePhotos() {
        pPage += 1;
        pLoading = true;
        Online.searchPhotos(pQuery, pPage);
    }
    Connections {
        target: Online
        function onGraphicsFound(q, kind, results) {
            if (q !== sp.gQuery) return;
            if (kind === "icons") sp.icons = results; else sp.stickers = results;
            sp.gLoading = Math.max(0, sp.gLoading - 1);
        }
        function onPhotosFound(q, page, results, more) {
            if (q !== sp.pQuery || page !== sp.pPage) return;
            sp.webPhotos = sp.webPhotos.concat(results);
            sp.pMore = more;
            sp.pLoading = false;
        }
        function onSearchFailed(what) {
            if (what === "photos") { sp.pLoading = false; sp.pFailed = true; }
            else { sp.gLoading = Math.max(0, sp.gLoading - 1); sp.gFailed = true; }
        }
    }

    // ——— Szablony: kategorie, „Pasujące” — w proporcjach bieżącej strony ———
    property string tplCategory: "fit"
    readonly property var tplCategories: {
        const out = [];
        for (const t of Library.templates) if (t.category && out.indexOf(t.category) < 0) out.push(t.category);
        return out;
    }
    readonly property var tplList: Library.templates.filter(t => tplCategory === "" ? true
        : tplCategory === "fit" ? Math.abs(t.width / t.height - project.pageWidth / project.pageHeight) < 0.02
        : t.category === tplCategory)
    onTplListChanged: if (tplCategory === "fit" && tplList.length === 0) tplCategory = ""

    // ——— Warstwy ———
    property var layers: []                  // od wierzchu
    function refreshLayers() { if (!project) return; layers = project.document().elements.slice().reverse(); }
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
        if (o.type === "image") return o.pixel ? "Warstwa pikselowa" : o.src ? "Zdjęcie" : "Miejsce na zdjęcie";
        if (o.type === "adjust") return "Korekcja";
        if (o.type === "draw") return o.pen === "highlighter" ? "Zakreślenie" : "Rysunek";
        if (o.type === "vector") return "Grafika";
        if (o.type === "code") return o.kind === "qr" ? "Kod QR" : "Kod kreskowy";
        if (o.type === "chart") return "Wykres";
        if (o.type === "table") return "Tabela";
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
    // Style z czcionkami z Google Fonts — czcionka pobiera się przy pierwszym kliknięciu
    readonly property var webStyles: [
        { label: "WIELKIE OTWARCIE", font: "Bebas Neue", size: 0.13, weight: 400, color: "#16181D", spacing: 0.02, preview: 30 },
        { label: "NOWOŚĆ", font: "Montserrat", size: 0.1, weight: 800, color: "#16181D", caps: true, spacing: 0.04, preview: 24 },
        { label: "Wakacje!", font: "Pacifico", size: 0.1, weight: 400, color: "#FF6A3D", preview: 26 },
        { label: "Zaproszenie ślubne", font: "Great Vibes", size: 0.1, weight: 400, color: "#8B5E3C", preview: 28 },
        { label: "Elegancko", font: "Playfair Display", size: 0.09, weight: 500, italic: true, color: "#2B2B2B", preview: 26 },
        { label: "Festiwal", font: "Abril Fatface", size: 0.11, weight: 400, color: "#B71C1C", preview: 28 },
        { label: "Super okazja!", font: "Permanent Marker", size: 0.08, weight: 400, color: "#16181D", preview: 22 },
        { label: "Notatka odręczna", font: "Caveat", size: 0.07, weight: 500, color: "#1E3A8A", preview: 24 },
        { label: "JUBILEUSZ", font: "Cinzel", size: 0.08, weight: 600, color: "#8B6B1F", spacing: 0.08, preview: 22 },
        { label: "MEGA PROMO", font: "Archivo Black", size: 0.1, weight: 400, color: "#E53935", preview: 24 },
        { label: "Tekst na luzie", font: "Comfortaa", size: 0.06, weight: 700, color: "#3D4048", preview: 20 },
        { label: "Nagłówek nowoczesny", font: "Space Grotesk", size: 0.07, weight: 700, color: "#16181D", preview: 20 }
    ]
    property var pendingStyle: null
    property string installingFont: ""
    function addWebStyle(s) {
        if (Library.fonts.indexOf(s.font) >= 0) { addTextStyle(s); return; }
        pendingStyle = s;
        installingFont = s.font;
        Online.installFont(s.font);
    }
    Connections {
        target: Online
        function onFontInstalled(family) {
            Library.reloadFonts();
            if (sp.pendingStyle && sp.pendingStyle.font === family) {
                const s = sp.pendingStyle;
                sp.pendingStyle = null;
                sp.installingFont = "";
                sp.addTextStyle(s);
            }
        }
        function onFontFailed(family) {
            if (family !== sp.installingFont) return;
            sp.pendingStyle = null;
            sp.installingFont = "";
            sp.editor.app.toast("Nie udało się pobrać czcionki — sprawdź połączenie z internetem", "");
        }
        function onFontPreviewReady() { sp.previews += 1; }
    }
    property int previews: 0

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
        { shape: "arrow", label: "Strzałka", stroke: "#16181D", strokeWidth: 0.01 },
        { shape: "doubleArrow", label: "W obie strony", stroke: "#16181D", strokeWidth: 0.01 },
        { shape: "bubble", label: "Dymek", fill: "#FFFFFF", stroke: "#16181D", strokeWidth: 0.008 },
        { shape: "burst", label: "Plakietka", fill: "#FFD23F" },
        { shape: "ribbon", label: "Wstążka", fill: "#E53935", wide: 0.3 },
        { shape: "arrowBlock", label: "Strzałka pełna", fill: "#5B7CFA", wide: 0.6 },
        { shape: "pentagon", label: "Pięciokąt", fill: "#22B07D" },
        { shape: "octagon", label: "Ośmiokąt", fill: "#E53935" },
        { shape: "cross", label: "Plus", fill: "#7E57C2" }
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

    // Kolor podglądu stylu czytelny na tle panelu (ciemny tekst w trybie ciemnym — jasny, i odwrotnie)
    function readable(c) {
        const q = Qt.color(c || "#16181D");
        const lum = 0.2126 * q.r + 0.7152 * q.g + 0.0722 * q.b;
        // Szare — kolor tekstu; barwne zostają, tylko jaśniejsze
        if (Theme.dark) return lum < 0.45 && (lum < 0.15 || q.hslSaturation < 0.3) ? Theme.text : lum < 0.45 ? Qt.lighter(q, 1.6) : c;
        return lum > 0.85 ? "#16181D" : c;
    }

    // Moje elementy — pliki w ~/.local/share/aster-grafika/elements
    property var saved: []
    Connections { target: sp.project; function onSavedElementsChanged() { sp.saved = sp.project.savedElements(); } }
    Component.onCompleted: { saved = project.savedElements(); if (tab === "layers") refreshLayers(); }

    // Moje style tekstu — zapisane w ustawieniach programu, wspólne dla wszystkich projektów.
    // Wielkość pamiętana względem krótszego boku strony, żeby pasowała też do innego formatu.
    Settings { id: mine; category: "Grafika"; property string textStyles: "[]" }
    readonly property var myStyles: { try { return JSON.parse(mine.textStyles); } catch (e) { return []; } }
    readonly property var selText: {
        const id = editor ? editor.sel : "";
        const el = id !== "" ? project.get(id) : ({});
        return el.type === "text" ? el : null;
    }
    function saveTextStyle() {
        const el = editor.sel !== "" ? project.get(editor.sel) : null;
        if (!el || el.type !== "text") return;
        const st = { type: "text" };
        for (const k in el) if (editor.styleSkip.indexOf(k) < 0) st[k] = el[k];
        st.rel = Math.round(el.size / base * 10000) / 10000;
        delete st.size;
        st.sample = (el.text || "Tekst").split("\n")[0].trim().substring(0, 28) || "Tekst";
        const same = JSON.stringify(Object.assign({}, st, { sample: "" }));
        const list = myStyles.filter(o => JSON.stringify(Object.assign({}, o, { sample: "" })) !== same);
        mine.textStyles = JSON.stringify([st].concat(list).slice(0, 24));
        editor.app.toast("Zapisano styl — znajdziesz go w zakładce Tekst w każdym projekcie", "");
    }
    function removeTextStyle(i) {
        const list = myStyles.slice();
        list.splice(i, 1);
        mine.textStyles = JSON.stringify(list);
    }
    // Kliknięcie stylu: zaznaczone teksty dostają ten wygląd, a bez zaznaczenia — nowy tekst
    function useTextStyle(st) {
        const look = Object.assign({}, st, { size: Math.max(4, Math.round(st.rel * base)) });
        delete look.rel;
        delete look.sample;
        if (editor.many.some(id => project.get(id).type === "text")) { editor.applyStyle(look); return; }
        const el = Object.assign({}, look, { text: st.sample });
        if (Library.fonts.indexOf(el.font) < 0) el.font = "Geist";
        el.w = Math.min(project.pageWidth * 0.86, project.naturalWidth(el) + el.size * 0.2);
        editor.addElement(el);
    }

    function addTextStyle(s) {
        const el = {
            type: "text", text: s.text || s.label.replace(/„|”/g, ""), font: s.font, size: Math.round(base * s.size), weight: s.weight,
            color: s.color, align: "center", lineHeight: s.lineHeight || 1.15
        };
        for (const k of ["italic", "caps", "spacing", "outline", "outlineColor"]) if (s[k] !== undefined) el[k] = s[k];
        el.w = Math.min(project.pageWidth * 0.86, project.naturalWidth(el) + el.size * 0.2);
        editor.addElement(el);
    }
    // Kody QR i kreskowe, wykresy
    readonly property var sampleData: [{ label: "Pon", value: 12 }, { label: "Wt", value: 19 }, { label: "Śr", value: 15 }, { label: "Czw", value: 24 }, { label: "Pt", value: 30 }]
    readonly property var extras: [
        { label: "Kod QR", preview: { type: "code", kind: "qr", data: "https://aster.local" },
          el: { type: "code", kind: "qr", data: "https://twojastrona.pl", color: "#16181D", bg: "#FFFFFF", side: 0.3 } },
        { label: "Wi-Fi", preview: { type: "code", kind: "qr", qrType: "wifi", ssid: "Aster", pass: "aster" },
          el: { type: "code", kind: "qr", qrType: "wifi", ssid: "Nazwa sieci", pass: "hasło", color: "#16181D", bg: "#FFFFFF", side: 0.3 } },
        { label: "Kod kreskowy", preview: { type: "code", kind: "code128", data: "ASTER", h: 60 },
          el: { type: "code", kind: "code128", data: "ASTER-2026", color: "#16181D", bg: "#FFFFFF", side: 0.5, ratio: 0.35 } },
        { label: "Słupki", preview: { type: "chart", chart: "column", data: sp.sampleData, values: false },
          el: { type: "chart", chart: "column", data: sp.sampleData, side: 0.6, ratio: 0.6 } },
        { label: "Koło", preview: { type: "chart", chart: "donut", data: sp.sampleData.slice(0, 3), values: false, size: 0.1 },
          el: { type: "chart", chart: "donut", data: [{ label: "Tak", value: 62 }, { label: "Nie", value: 25 }, { label: "Nie wiem", value: 13 }], side: 0.6, ratio: 0.55 } },
        { label: "Linia", preview: { type: "chart", chart: "line", data: sp.sampleData, values: false },
          el: { type: "chart", chart: "line", data: sp.sampleData, side: 0.6, ratio: 0.55 } },
        { label: "Tabela", preview: { type: "table", cells: [["", "", ""], ["", "", ""], ["", "", ""], ["", "", ""]], headerFill: "#3D4048", fill: "#FFFFFF", stroke: "#C9CDD6", strokeWidth: 1.5 },
          el: { type: "table", cells: [["Nazwa", "Ilość", "Uwagi"], ["", "", ""], ["", "", ""], ["", "", ""]], headerFill: "#16181D", headerColor: "#FFFFFF",
                fill: "#FFFFFF", stroke: "#D9DCE3", color: "#3D4048", lines: "rows", side: 0.7, ratio: 0.42 } },
        { label: "Cennik", preview: { type: "table", cells: [["", ""], ["", ""], ["", ""], ["", ""]], headerFill: "#5B7CFA", fill: "#FFFFFF", stripe: "#E4EAFF", lines: "none", radius: 8 },
          el: { type: "table", cells: [["Usługa", "Cena"], ["Strzyżenie", "60 zł"], ["Koloryzacja", "180 zł"], ["Modelowanie", "50 zł"]],
                headerFill: "#5B7CFA", headerColor: "#FFFFFF", fill: "#FFFFFF", stripe: "#EEF2FF", color: "#16181D", lines: "none", radius: 0.02, side: 0.6, ratio: 0.5 } },
        { label: "Plan", preview: { type: "table", cells: [["", "", "", ""], ["", "", "", ""], ["", "", "", ""], ["", "", "", ""]], headerFill: "#22B07D", fill: "#FFFFFF", stroke: "#B9DDCB", strokeWidth: 1.5, lines: "grid" },
          el: { type: "table", cells: [["Godzina", "Poniedziałek", "Wtorek", "Środa"], ["8:00", "", "", ""], ["9:00", "", "", ""], ["10:00", "", "", ""], ["11:00", "", "", ""]],
                headerFill: "#22B07D", headerColor: "#FFFFFF", fill: "#FFFFFF", stroke: "#B9DDCB", color: "#16181D", lines: "grid", align: "center", side: 0.8, ratio: 0.5 } }
    ]
    function addExtra(x) {
        const el = Object.assign({}, x.el);
        const side = Math.round(base * el.side);
        el.w = side;
        el.h = Math.round(side * (el.ratio || 1));
        if (el.type === "chart") { el.size = Math.round(base * 0.026); el.color = "#3D4048"; }
        if (el.type === "table") {
            el.size = Math.round(base * 0.024);
            el.strokeWidth = Math.max(1, Math.round(base * 0.002));
            el.radius = Math.round(base * (el.radius || 0));
            el.cells = el.cells.map(r => r.slice());
        }
        delete el.side; delete el.ratio;
        editor.addElement(el);
    }

    function addShape(s) {
        const line = s.shape === "line" || s.shape === "arrow" || s.shape === "doubleArrow";
        const side = Math.round(base * 0.36);
        const el = { type: "shape", shape: s.shape, fill: s.fill || "", w: line || s.wide ? side * 1.4 : side, h: s.wide ? Math.round(side * 1.4 * s.wide) : side };
        if (s.radius) el.radius = Math.round(side * s.radius);
        if (s.stroke) { el.stroke = s.stroke; el.strokeWidth = Math.max(2, Math.round(base * s.strokeWidth)); }
        if (s.dash) el.dash = true;
        if (line) el.h = Math.max(24, el.strokeWidth * 4);
        editor.addElement(el);
    }

    // ——— Pasek kart ———
    Column {
        id: rail
        visible: sp.showRail
        width: sp.showRail ? 72 : 0
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
            font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold; font.letterSpacing: -0.1
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
                      : sp.tab === "shapes" ? elementsCol.height : sp.tab === "photos" ? photosCol.height
                      : sp.tab === "layers" ? layersCol.height : sp.tab === "draw" ? drawCol.height : sp.tab === "paint" ? paintCol.height : bgCol.height

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
                        spacing: 4
                        Chip { height: 26; text: "Pasujące"; on: sp.tplCategory === "fit"; onClicked: sp.tplCategory = "fit" }
                        Chip { height: 26; text: "Wszystkie"; on: sp.tplCategory === ""; onClicked: sp.tplCategory = "" }
                        Repeater {
                            model: sp.tplCategories
                            delegate: Chip {
                                required property string modelData
                                height: 26
                                text: modelData
                                on: sp.tplCategory === modelData
                                onClicked: sp.tplCategory = modelData
                            }
                        }
                    }
                    Text {
                        visible: sp.tplList.length === 0
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Nie ma szablonów w tym rozmiarze strony — wybierz „Wszystkie”."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                    }
                    Flow {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: sp.tplList
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
                                    text: tpl.modelData.name + (tpl.modelData.pages > 1 ? " · " + tpl.modelData.pages + " str." : "")
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
                    Btn {
                        width: parent.width; height: 44
                        primary: true
                        icon: "textT"
                        text: "Dodaj pole tekstowe"
                        onClicked: sp.addTextStyle(sp.textStyles[2])
                    }
                    Text {
                        topPadding: 6
                        text: "Gotowe style"
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    }
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
                                color: ts.modelData.outline ? ts.modelData.color : sp.readable(ts.modelData.color)
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
                    // Moje style
                    Item {
                        width: parent.width; height: 30
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Moje style"
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                    }
                    Text {
                        visible: sp.myStyles.length === 0
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Zaznacz tekst na stronie i zapisz jego wygląd — potem użyjesz go jednym kliknięciem w każdym projekcie."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
                    }
                    Repeater {
                        model: sp.myStyles
                        delegate: HoverButton {
                            id: my
                            required property var modelData
                            required property int index
                            readonly property real preview: Math.min(24, Math.max(13, (modelData.rel || 0.05) * 290))
                            width: textCol.width
                            height: Math.max(46, mylabel.implicitHeight + 20)
                            radius: 12
                            baseColor: Theme.fill
                            onClicked: sp.useTextStyle(modelData)
                            Rectangle {
                                visible: !!my.modelData.bg
                                anchors.centerIn: mylabel
                                width: Math.min(parent.width - 12, mylabel.contentWidth + 16); height: mylabel.contentHeight + 8
                                radius: 6
                                color: my.modelData.bg || "transparent"
                            }
                            Text {
                                id: mylabel
                                anchors.centerIn: parent
                                width: parent.width - 56
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: my.modelData.sample
                                readonly property string c: my.modelData.color || "#16181D"
                                color: my.modelData.outline || my.modelData.bg ? c : sp.readable(c)
                                style: my.modelData.outline ? Text.Outline : Text.Normal
                                styleColor: my.modelData.outlineColor || "transparent"
                                font.family: Library.fonts.indexOf(my.modelData.font) >= 0 ? my.modelData.font : Theme.font
                                font.pixelSize: my.preview
                                font.weight: my.modelData.weight || 400
                                font.variableAxes: ({ "wght": my.modelData.weight || 400 })
                                font.italic: !!my.modelData.italic
                                font.capitalization: my.modelData.caps ? Font.AllUppercase : Font.MixedCase
                                font.letterSpacing: (my.modelData.spacing || 0) * my.preview
                            }
                            HoverButton {
                                anchors.right: parent.right; anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26; height: 26; radius: 13
                                visible: my.hovered || hovered
                                onClicked: sp.removeTextStyle(my.index)
                                Icon { anchors.centerIn: parent; d: Icons.close; size: 12; stroke: 2; color: Theme.text2 }
                            }
                        }
                    }
                    Btn {
                        width: parent.width
                        icon: "plus"
                        text: "Zapisz styl zaznaczonego tekstu"
                        enabled: sp.selText !== null
                        onClicked: sp.saveTextStyle()
                    }
                    Text {
                        topPadding: 8
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Z czcionkami z internetu — pobiorą się po kliknięciu. Więcej czcionek w wyborze czcionki."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
                    }
                    Repeater {
                        model: sp.webStyles
                        delegate: HoverButton {
                            id: ws
                            required property var modelData
                            readonly property bool ready: sp.previews >= 0 && (Library.fonts.indexOf(modelData.font) >= 0 || Online.hasPreview(modelData.font))
                            width: textCol.width
                            height: Math.max(52, wlabel.implicitHeight + 24)
                            radius: 12
                            baseColor: Theme.fill
                            enabled: sp.installingFont === ""
                            onClicked: sp.addWebStyle(modelData)
                            Component.onCompleted: Online.previewFont(modelData.font, modelData.label + modelData.label.toUpperCase())
                            Text {
                                id: wlabel
                                anchors.centerIn: parent
                                width: parent.width - 20
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                text: ws.modelData.label
                                color: sp.readable(ws.modelData.color)
                                font.family: ws.ready ? ws.modelData.font : Theme.font
                                font.pixelSize: ws.modelData.preview
                                font.weight: ws.modelData.weight
                                font.italic: !!ws.modelData.italic
                                font.letterSpacing: (ws.modelData.spacing || 0) * ws.modelData.preview
                                opacity: sp.installingFont === ws.modelData.font ? 0.4 : 1
                            }
                            Text {
                                visible: sp.installingFont === ws.modelData.font
                                anchors.centerIn: parent
                                text: "Pobieranie czcionki…"
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                // Elementy: ikony i naklejki z internetu, kształty
                Column {
                    id: elementsCol
                    visible: sp.tab === "shapes"
                    width: parent.width
                    spacing: 12
                    SearchField {
                        id: gSearch
                        placeholder: "Szukaj ikon i naklejek"
                        onSearch: (t) => sp.searchGraphics(t)
                    }
                    Flow {
                        visible: sp.gQuery === ""
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: sp.graphicIdeas
                            delegate: Chip {
                                required property string modelData
                                height: 28
                                text: modelData
                                onClicked: gSearch.set(modelData)
                            }
                        }
                    }
                    Text {
                        visible: sp.gQuery !== "" && (sp.gLoading > 0 || sp.gFailed || (sp.icons.length === 0 && sp.stickers.length === 0))
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: sp.gLoading > 0 ? "Szukam…" : sp.gFailed ? "Nie udało się połączyć z biblioteką. Sprawdź internet."
                            : "Nic nie znalazłem. Spróbuj innego słowa, np. po angielsku."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                    }
                    Repeater {
                        model: [{ kind: "stickers", title: "Naklejki", list: sp.stickers }, { kind: "icons", title: "Ikony — możesz zmienić ich kolor", list: sp.icons }]
                        delegate: Column {
                            id: gsec
                            required property var modelData
                            visible: modelData.list.length > 0
                            width: elementsCol.width
                            spacing: 8
                            Text {
                                text: gsec.modelData.title
                                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            Flow {
                                width: parent.width
                                spacing: 4
                                Repeater {
                                    model: gsec.modelData.list
                                    delegate: HoverButton {
                                        id: gt
                                        required property var modelData
                                        width: (elementsCol.width - 12) / 4; height: width
                                        radius: 10
                                        onClicked: sp.editor.addGraphic(modelData.file)
                                        Image {
                                            anchors.centerIn: parent
                                            width: parent.width * (gsec.modelData.kind === "icons" ? 0.5 : 0.7); height: width
                                            source: gt.modelData.thumb
                                            sourceSize.width: 96; sourceSize.height: 96
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        visible: sp.gQuery !== "" && (sp.icons.length > 0 || sp.stickers.length > 0)
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Ikony i naklejki z Iconify — z zestawów na wolnych licencjach, do użytku bez podpisu."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; lineHeight: 1.2
                    }
                    Text {
                        text: "Moje elementy"
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                    Text {
                        visible: sp.saved.length === 0
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Logo, podpis, stopka z kontaktem — zaznacz je na stronie i zapisz, a wstawisz je jednym kliknięciem w każdym projekcie."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; lineHeight: 1.2
                    }
                    Grid {
                        visible: sp.saved.length > 0
                        columns: 3
                        spacing: 6
                        Repeater {
                            model: sp.saved
                            delegate: HoverButton {
                                id: sv
                                required property var modelData
                                width: (elementsCol.width - 12) / 3; height: width
                                radius: 10
                                baseColor: modelData.light ? "#3A3F4B" : Theme.fill
                                color: hovered ? Qt.darker(baseColor, modelData.light ? 0.85 : 1.08) : baseColor
                                onClicked: sp.editor.insertSaved(modelData.file)
                                Image {
                                    anchors.fill: parent; anchors.margins: 8
                                    source: sv.modelData.thumb
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    cache: false
                                    sourceSize.width: 160
                                }
                                HoverButton {
                                    anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 3
                                    width: 22; height: 22; radius: 11
                                    visible: sv.hovered || hovered
                                    baseColor: Theme.surface
                                    onClicked: sp.project.removeSaved(sv.modelData.file)
                                    Icon { anchors.centerIn: parent; d: Icons.close; size: 10; stroke: 2; color: Theme.text2 }
                                }
                            }
                        }
                    }
                    Btn {
                        width: parent.width
                        icon: "plus"
                        text: sp.editor && sp.editor.many.length > 1 ? "Zapisz zaznaczone jako mój element" : "Zapisz zaznaczony jako mój element"
                        enabled: !!sp.editor && sp.editor.many.length > 0
                        onClicked: sp.editor.saveElements()
                    }
                    Text {
                        topPadding: 4
                        text: "Kody, wykresy i tabele"
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                    Grid {
                        columns: 3
                        spacing: 8
                        Repeater {
                            model: sp.extras
                            delegate: HoverButton {
                                id: ex
                                required property var modelData
                                width: (elementsCol.width - 16) / 3
                                height: width + 16
                                radius: 12
                                baseColor: Theme.fill
                                onClicked: sp.addExtra(modelData)
                                ArtView {
                                    x: 12; y: 10
                                    width: ex.width - 24; height: ex.width - 24
                                    element: Object.assign({ w: 100, h: 100, size: 9, color: Theme.dark ? "#ECEEF3" : "#3D4048", bg: "" }, ex.modelData.preview)
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                                    text: ex.modelData.label
                                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                                }
                            }
                        }
                    }
                    Text {
                        text: "Kształty"
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                    Grid {
                        id: shapesGrid
                        columns: 3
                        spacing: 8
                        Repeater {
                            model: sp.shapes
                            delegate: HoverButton {
                                id: sh
                                required property var modelData
                                readonly property bool line: modelData.shape === "line" || modelData.shape === "arrow" || modelData.shape === "doubleArrow"
                                width: (pages.width - 16) / 3
                                height: width + 16
                                radius: 12
                                baseColor: Theme.fill
                                onClicked: sp.addShape(modelData)
                                ArtView {
                                    readonly property real ph: sh.line ? 18 : sh.modelData.wide ? Math.round((sh.width - 28) * Math.max(0.42, sh.modelData.wide)) : sh.width - 28
                                    x: 14; y: 12 + (sh.width - 28 - ph) / 2
                                    width: sh.width - 28
                                    height: ph
                                    element: ({
                                        type: "shape", shape: sh.modelData.shape, w: 100, h: sh.line ? 18 : sh.modelData.wide ? Math.round(100 * Math.max(0.42, sh.modelData.wide)) : 100,
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
                }

                // Zdjęcia
                Column {
                    id: photosCol
                    visible: sp.tab === "photos"
                    width: parent.width
                    spacing: 12
                    SearchField {
                        id: pSearch
                        placeholder: "Szukaj darmowych zdjęć"
                        onSearch: (t) => sp.searchPhotos(t)
                    }
                    Flow {
                        visible: sp.pQuery === ""
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: sp.photoIdeas
                            delegate: Chip {
                                required property string modelData
                                height: 28
                                text: modelData
                                onClicked: pSearch.set(modelData)
                            }
                        }
                    }
                    Text {
                        visible: sp.pQuery !== "" && (sp.pFailed || (sp.webPhotos.length === 0 && !sp.pLoading))
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: sp.pFailed ? "Nie udało się połączyć z biblioteką zdjęć. Sprawdź internet." : "Nic nie znalazłem. Spróbuj innego słowa."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                    }
                    Flow {
                        visible: sp.webPhotos.length > 0
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: sp.webPhotos
                            delegate: HoverButton {
                                id: wp
                                required property var modelData
                                readonly property bool loading: !!sp.editor.downloads[modelData.url]
                                width: (photosCol.width - 6) / 2; height: 104
                                radius: 8
                                onClicked: sp.editor.addOnlinePhoto(modelData)
                                Image {
                                    id: wpImg
                                    anchors.fill: parent; anchors.margins: 2
                                    source: wp.modelData.thumb
                                    sourceSize.width: 320
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    clip: true
                                    opacity: wp.loading ? 0.4 : 1
                                    onStatusChanged: if (status === Image.Error && source !== wp.modelData.fallback && wp.modelData.fallback) source = wp.modelData.fallback
                                }
                                Rectangle {
                                    anchors.fill: parent; anchors.margins: 2
                                    visible: wpImg.status !== Image.Ready
                                    radius: 6
                                    color: Theme.fill
                                }
                                Text {
                                    visible: wp.loading
                                    anchors.centerIn: parent
                                    text: "Pobieranie…"
                                    color: "white"; style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.5)
                                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                    Btn {
                        visible: sp.pQuery !== "" && (sp.pMore || sp.pLoading)
                        width: parent.width
                        enabled: !sp.pLoading
                        text: sp.pLoading ? "Szukam…" : "Więcej zdjęć"
                        onClicked: sp.morePhotos()
                    }
                    Text {
                        visible: sp.webPhotos.length > 0
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Zdjęcia z Wikimedia Commons na wolnych licencjach. Przy części trzeba podpisać autora — program zapamięta podpis, a w panelu zdjęcia dodasz go jednym kliknięciem."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; lineHeight: 1.2
                    }
                    Btn {
                        width: parent.width
                        primary: true
                        icon: "upload"
                        text: "Dodaj zdjęcie z dysku"
                        onClicked: sp.editor.chooseImage("element")
                    }
                    Text {
                        text: "Kolaż — puste ramki na zdjęcia"
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: sp.collages
                            delegate: HoverButton {
                                id: cl
                                required property var modelData
                                readonly property real ratio: sp.project.pageHeight / sp.project.pageWidth
                                width: (photosCol.width - 12) / 3
                                height: Math.min(width * 1.6, width * ratio)
                                radius: 8
                                baseColor: Theme.fill
                                onClicked: sp.editor.addCollage(modelData.rects)
                                Repeater {
                                    model: cl.modelData.rects
                                    delegate: Rectangle {
                                        required property var modelData
                                        x: 5 + modelData[0] * (cl.width - 10) + 1.5
                                        y: 5 + modelData[1] * (cl.height - 10) + 1.5
                                        width: modelData[2] * (cl.width - 10) - 3
                                        height: modelData[3] * (cl.height - 10) - 3
                                        radius: 3
                                        color: Theme.dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.16)
                                    }
                                }
                            }
                        }
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
                        text: sp.layers.length === 0 ? "Na stronie nie ma jeszcze elementów." : "Na górze to, co na wierzchu · przeciągnij, żeby zmienić kolejność"
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
                                    Icon { visible: row.modelData.type === "adjust"; anchors.centerIn: parent; d: Icons.sliders; size: 18; stroke: 1.9; color: "#5B6270" }
                                    ArtView {
                                        readonly property real k: Math.min(30 / Math.max(1, row.modelData.w), 30 / Math.max(1, row.modelData.h))
                                        visible: row.modelData.type !== "adjust"
                                        anchors.centerIn: parent
                                        width: Math.max(2, row.modelData.w * k); height: Math.max(2, row.modelData.h * k)
                                        rotation: row.modelData.rotation || 0
                                        project: sp.project
                                        element: row.modelData
                                    }
                                }
                                // Maska warstwy: klik — malowanie po masce
                                Rectangle {
                                    id: maskThumb
                                    visible: !!row.modelData.layerMask
                                    anchors.left: thumb.right; anchors.leftMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: visible ? 34 : 0; height: 34; radius: 7
                                    color: "#000000"
                                    border.width: sp.editor.maskEditing === row.modelData.id ? 2 : 1
                                    border.color: sp.editor.maskEditing === row.modelData.id ? Theme.accent : Theme.line
                                    clip: true
                                    opacity: row.modelData.layerMaskOff ? 0.4 : 1
                                    ArtView {
                                        anchors.fill: parent; anchors.margins: 1
                                        project: sp.project
                                        element: ({ type: "image", src: row.modelData.layerMask, w: 32, h: 32 })
                                    }
                                }
                                Text {
                                    anchors.left: maskThumb.visible ? maskThumb.right : thumb.right; anchors.leftMargin: 10
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
                                            if (maskThumb.visible && e.x >= maskThumb.x && e.x <= maskThumb.x + maskThumb.width)
                                                sp.editor.editMask(row.modelData.id);
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
                    // Tło strony — zawsze na samym spodzie; kliknięcie otwiera narzędzie Tło
                    HoverButton {
                        id: bgRow
                        width: parent.width; height: layersCol.rowH - 4
                        radius: 10
                        baseColor: sp.editor && sp.editor.side && sp.editor.side.tab === "background" ? Theme.accentSoft : "transparent"
                        onClicked: sp.editor.setTool("background")
                        Rectangle {
                            x: 6; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 32; radius: 7
                            clip: true
                            color: "transparent"
                            border.width: 1; border.color: Theme.line
                            ArtView {
                                anchors.fill: parent; anchors.margins: 1
                                project: sp.project
                                element: Object.assign({ kind: "background", w: 100, h: 100 }, sp.project.background)
                            }
                        }
                        Text {
                            x: 50; anchors.verticalCenter: parent.verticalCenter
                            text: "Tło"
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                        }
                        Icon { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; d: Icons.lock; size: 14; stroke: 1.8; color: Theme.text2; opacity: 0.5 }
                    }
                }

                // Malowanie i retusz
                Column {
                    id: paintCol
                    visible: sp.tab === "paint"
                    width: parent.width
                    spacing: 14
                    Grid {
                        columns: 2
                        spacing: 6
                        Repeater {
                            model: sp.paintTools
                            delegate: HoverButton {
                                id: pt
                                required property var modelData
                                readonly property bool on: sp.paintTool === modelData.id
                                width: (pages.width - 6) / 2; height: 36; radius: 9
                                baseColor: on ? Theme.accent : Theme.fill
                                color: on ? baseColor : hovered ? Theme.hover : baseColor
                                tip: modelData.key !== "" ? "Skrót: " + modelData.key : ""
                                onClicked: sp.paintTool = modelData.id
                                Row {
                                    x: 10; anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8
                                    Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons[pt.modelData.icon]; size: 16; stroke: 1.9; color: pt.on ? "white" : Theme.text }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: pt.modelData.label; color: pt.on ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: pt.on ? Font.DemiBold : Font.Medium }
                                }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: sp.paintHint
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.25
                    }
                    Section {
                        visible: sp.paintHasColor
                        title: "Kolor"
                        Grid {
                            columns: 6
                            spacing: 8
                            Repeater {
                                model: sp.drawColors
                                delegate: Rectangle {
                                    id: pc
                                    required property string modelData
                                    readonly property bool on: String(sp.paintColor).toUpperCase() === modelData.toUpperCase()
                                    width: (pages.width - 40) / 6; height: width; radius: width / 2
                                    color: modelData
                                    border.width: on ? 3 : 1; border.color: on ? Theme.accent : Qt.rgba(0, 0, 0, 0.14)
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sp.paintColor = pc.modelData }
                                }
                            }
                        }
                        ColorWell {
                            id: paintWell
                            label: "Inny kolor"
                            value: String(sp.paintColor)
                            onClicked: sp.editor.pickColor(paintWell, value, false, (c) => sp.paintColor = c)
                        }
                    }
                    Column {
                        width: parent.width
                        spacing: 2
                        ValueSlider {
                            visible: sp.paintHasSize
                            label: "Rozmiar"
                            from: 1; to: Math.max(40, Math.round(sp.base * 0.3)); step: 1
                            value: sp.paintSize
                            suffix: " px"
                            onMoved: (v) => sp.setPaintSize(v)
                        }
                        ValueSlider {
                            visible: sp.paintHasSize && sp.paintTool !== "heal"
                            label: "Twardość"
                            from: 0; to: 1; step: 0.01
                            value: sp.paintHardness
                            shown: value * 100; suffix: "%"
                            onMoved: (v) => sp.paintHardness = v
                        }
                        ValueSlider {
                            visible: sp.paintTool !== "heal" && sp.paintTool !== "pick" && sp.paintTool !== "fill"
                            label: sp.paintTool === "brush" || sp.paintTool === "eraser" || sp.paintTool === "clone" ? "Krycie" : "Siła"
                            from: 0.02; to: 1; step: 0.01
                            value: sp.paintStrength
                            shown: value * 100; suffix: "%"
                            onMoved: (v) => sp.setPaintPower(v)
                        }
                        ValueSlider {
                            visible: sp.paintTool === "fill"
                            label: "Tolerancja"
                            from: 0; to: 1; step: 0.01
                            value: sp.fillTolerance
                            shown: value * 100; suffix: "%"
                            onMoved: (v) => sp.fillTolerance = v
                        }
                    }
                    Btn {
                        width: parent.width
                        icon: "plus"
                        text: "Nowa warstwa do malowania"
                        onClicked: sp.editor.addPixelLayer()
                    }
                }

                // Rysowanie
                Column {
                    id: drawCol
                    visible: sp.tab === "draw"
                    width: parent.width
                    spacing: 14
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Rysuj myszą albo piórem tabletu prosto na stronie. Każda kreska to osobny element — można ją potem przesunąć, zmienić kolor albo usunąć."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.25
                    }
                    Grid {
                        columns: 2
                        spacing: 8
                        Repeater {
                            model: sp.pens
                            delegate: HoverButton {
                                id: penBtn
                                required property var modelData
                                readonly property bool on: sp.drawTool === modelData.id
                                width: (pages.width - 8) / 2; height: 78; radius: 12
                                baseColor: on ? Theme.accentSoft : Theme.fill
                                color: on ? baseColor : hovered ? Theme.hover : baseColor
                                border.width: on ? 1.5 : 0; border.color: Theme.accent
                                tip: modelData.label
                                onClicked: sp.drawTool = modelData.id
                                Rectangle {
                                    // Ciemne tło pod neonem i jasnymi kolorami, żeby było widać kreskę
                                    readonly property bool darkBg: penBtn.modelData.id === "neon"
                                    visible: darkBg
                                    x: 8; y: 8; width: parent.width - 16; height: 40; radius: 8
                                    color: "#1B1D24"
                                }
                                ArtView {
                                    x: 14; y: 12
                                    width: parent.width - 28; height: 32
                                    element: ({ type: "draw", pen: penBtn.modelData.id, stroke: String(sp.drawColor), w: 100, h: 32, points: sp.sample,
                                                strokeWidth: penBtn.modelData.id === "pen" ? 2.5 : penBtn.modelData.id === "marker" ? 6 : penBtn.modelData.id === "highlighter" ? 10 : 3.5 })
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 54
                                    text: penBtn.modelData.label
                                    color: penBtn.on ? Theme.accentText : Theme.text
                                    font.family: Theme.font; font.pixelSize: 12; font.weight: penBtn.on ? Font.DemiBold : Font.Medium
                                }
                            }
                        }
                    }
                    HoverButton {
                        id: eraserBtn
                        readonly property bool on: sp.drawTool === "eraser"
                        width: parent.width; height: 40; radius: 12
                        baseColor: on ? Theme.accentSoft : Theme.fill
                        color: on ? baseColor : hovered ? Theme.hover : baseColor
                        border.width: on ? 1.5 : 0; border.color: Theme.accent
                        onClicked: sp.drawTool = "eraser"
                        Row {
                            anchors.centerIn: parent
                            spacing: 8
                            Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.eraser; size: 17; stroke: 1.8; color: eraserBtn.on ? Theme.accentText : Theme.text }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Gumka do rysunków"; color: eraserBtn.on ? Theme.accentText : Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: eraserBtn.on ? Font.DemiBold : Font.Medium }
                        }
                    }
                    Section {
                        visible: sp.drawTool !== "eraser"
                        title: "Kolor"
                        Grid {
                            columns: 6
                            spacing: 8
                            Repeater {
                                model: sp.drawColors
                                delegate: Rectangle {
                                    id: dc
                                    required property string modelData
                                    readonly property bool on: String(sp.drawColor).toUpperCase() === modelData.toUpperCase()
                                    width: (pages.width - 40) / 6; height: width; radius: width / 2
                                    color: modelData
                                    border.width: on ? 3 : 1; border.color: on ? Theme.accent : Qt.rgba(0, 0, 0, 0.14)
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: sp.drawColor = dc.modelData
                                    }
                                }
                            }
                        }
                        ColorWell {
                            id: drawWell
                            label: "Inny kolor"
                            value: String(sp.drawColor)
                            onClicked: sp.editor.pickColor(drawWell, value, false, (c) => sp.drawColor = c)
                        }
                    }
                    ValueSlider {
                        visible: sp.drawTool !== "eraser"
                        label: "Grubość"
                        from: 1; to: Math.max(20, Math.round(sp.base * 0.08)); step: 1
                        value: sp.drawWidth
                        suffix: " px"
                        onMoved: (v) => sp.setDrawSize(v)
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
