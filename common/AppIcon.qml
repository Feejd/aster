import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

// Ikona programu w jednym kształcie dla całego systemu — „squircle” (superelipsa).
// Estetyka „Fala”: kafelek z ukośnym gradientem dwóch pokrewnych barw, a na nim
// wygięty arkusz z cienką świetlną krawędzią — ten sam motyw co na tapecie Aura.
// Znak jest biały z miękkim cieniem; w ciemnym motywie kafelek staje się barwionym,
// ciemnym szkłem, a znak i krawędź świecą kolorem programu (jak neon).
//  • programy Aster i podstawowe programy systemu: własny kafelek ze znakiem (spójny zestaw),
//  • aplikacje webowe Aster: ich kafelek (już ma kształt) wycięty w squircle,
//  • reszta: oryginalna ikona na neutralnym kafelku z falą, więc wszystko ma ten sam obrys.
Item {
    id: ai
    property string desktopId: ""          // np. "org.aster.files"
    property var source                    // ikona z systemu (nazwa albo QIcon)
    property real size: 52
    width: size
    height: size

    // Zestaw ikon Aster: [barwa jasna (światło), barwa głęboka (cień), znak z Icons.js]
    readonly property var designs: ({
        "aster-start": ["#93A8FF", "#4B3FD6", "aster"],
        "aster-trash": ["#E4E8EF", "#9AA2B2", "trash"],
        "org.aster.files": ["#74CCFF", "#2457E6", "folder"],
        "org.aster.browser": ["#6EF0D6", "#2A62E8", "globe"],
        "org.aster.webapps": ["#E6A4FF", "#7330E0", "webapp"],
        "org.aster.store": ["#86EFC0", "#0B8C74", "bag"],
        "org.aster.settings": ["#D9DEE7", "#545C6E", "gear"],
        "systemsettings": ["#D9DEE7", "#545C6E", "sliders"],
        "kdesystemsettings": ["#D9DEE7", "#545C6E", "sliders"],
        "org.aster.terminal": ["#8B93A8", "#141621", "prompt"],
        "org.aster.calculator": ["#FFE394", "#F08A0A", "grid"],
        "org.aster.editor": ["#FFCB73", "#EF6420", "pencil"],
        "org.aster.code": ["#8FD3FF", "#4338CA", "code"],
        "org.aster.pulse": ["#FFB38A", "#E0336E", "pulse"],
        "org.aster.pdf": ["#FF9AAE", "#DC2550", "doc"],
        "org.aster.photos": ["#FFB0DC", "#B23DE0", "image"],
        "org.aster.video": ["#9DB8FF", "#3A36D8", "film"],
        "org.aster.music": ["#FFA394", "#E2283E", "music"],
        "org.aster.camera": ["#B9C2D3", "#2B303C", "camera"],
        "org.aster.montaz": ["#FFB08A", "#D9306A", "clapper"],
        "org.kde.kamoso": ["#B9C2D3", "#2B303C", "camera"],
        "org.aster.scanner": ["#A5F3FC", "#0E7490", "scanner"],
        "org.kde.skanlite": ["#A5F3FC", "#0E7490", "scanner"],
        "org.kde.skanpage": ["#A5F3FC", "#0E7490", "scanner"],
        "org.aster.grafika": ["#7DF0E8", "#6A3DF0", "palette"],
        "org.aster.phone": ["#86EFAC", "#15803D", "phone"],
        "org.kde.kdeconnect.app": ["#86EFAC", "#15803D", "phone"],
        "org.aster.tasks": ["#7EE8A8", "#0E8F5A", "activity"],
        "org.kde.plasma-systemmonitor": ["#7EE8A8", "#0E8F5A", "activity"],
        "org.kde.konsole": ["#8B93A8", "#141621", "prompt"],
        "org.kde.kate": ["#FFCB73", "#EF6420", "pencil"],
        "org.kde.discover": ["#86EFC0", "#0B8C74", "bag"],
        "org.kde.okular": ["#FF9AAE", "#DC2550", "doc"],
        "org.kde.gwenview": ["#FFB0DC", "#B23DE0", "image"],
        "org.kde.elisa": ["#FFA394", "#E2283E", "music"],
        "org.kde.dragonplayer": ["#9DB8FF", "#3A36D8", "film"],
        "org.kde.haruna": ["#9DB8FF", "#3A36D8", "film"],
        "org.kde.spectacle": ["#A6E0FF", "#5A55EE", "screenshot"],
        "org.kde.kcalc": ["#FFE394", "#F08A0A", "grid"],
        "org.kde.ark": ["#EBCD9E", "#9A6838", "drive"],
        "org.kde.dolphin": ["#74CCFF", "#2457E6", "folder"],
        "org.mozilla.firefox": ["#FFCB73", "#E8550C", "globe"],
        "firefox": ["#FFCB73", "#E8550C", "globe"]
    })
    readonly property var design: designs[desktopId] || null
    readonly property bool webapp: desktopId.indexOf("aster-webapp-") === 0
    readonly property bool dark: Theme.dark

    // Barwy kafelka; bez projektu — neutralny podkład pod oryginalną ikoną
    readonly property color hi: design ? design[0] : (dark ? "#4A4C56" : "#FFFFFF")
    readonly property color lo: design ? design[1] : (dark ? "#24252C" : "#DDE1E8")
    function alpha(c, o) { return Qt.rgba(c.r, c.g, c.b, o); }

    // ——— Geometria ———
    // Obrys squircle (|x|^5 + |y|^5 = 1) jako łamana — gładki przy każdym rozmiarze
    readonly property real inset: 0.5
    readonly property real half: size / 2 - inset
    function squircle(steps) {
        const pts = [];
        const c = size / 2;
        for (let i = 0; i <= steps; ++i) {
            const t = (i / steps) * Math.PI * 2;
            const ct = Math.cos(t), st = Math.sin(t);
            pts.push(Qt.point(c + half * Math.sign(ct) * Math.pow(Math.abs(ct), 0.4),
                              c + half * Math.sign(st) * Math.pow(Math.abs(st), 0.4)));
        }
        return pts;
    }
    // Górna i dolna krawędź squircle nad danym x
    function edgeY(x, bottom) {
        const u = Math.min(1, Math.abs((x - size / 2) / half));
        const v = Math.pow(1 - Math.pow(u, 5), 0.2);
        return size / 2 + (bottom ? 1 : -1) * half * v;
    }
    // Krzywa arkusza: z lewego dołu łagodnym „S” do prawej połowy wysokości
    function wave(x) {
        const t = x / size;
        return size * (0.97 - 0.42 * t * t * (3 - 2 * t));
    }
    // Arkusz = część squircle pod krzywą
    function sheet(steps) {
        const pts = [];
        const x0 = size / 2 - half, w = 2 * half;
        for (let i = 0; i <= steps; ++i) {
            const x = x0 + w * i / steps;
            pts.push(Qt.point(x, Math.min(Math.max(wave(x), edgeY(x, false)), edgeY(x, true))));
        }
        for (let i = steps; i >= 0; --i) {
            const x = x0 + w * i / steps;
            pts.push(Qt.point(x, edgeY(x, true)));
        }
        return pts;
    }
    // Świetlna krawędź arkusza (tylko wewnątrz kafelka)
    function crest(steps) {
        const pts = [];
        const x0 = size / 2 - half, w = 2 * half;
        for (let i = 0; i <= steps; ++i) {
            const x = x0 + w * i / steps, y = wave(x);
            if (y > edgeY(x, false) + 1.5 && y < edgeY(x, true) - 1.5)
                pts.push(Qt.point(x, y));
        }
        return pts;
    }
    // Górna połowa obrysu — jasny rant, na który pada światło
    function rim(steps) {
        const pts = [];
        const c = size / 2, r = half - 0.8;
        for (let i = 0; i <= steps; ++i) {
            const t = Math.PI * (1.08 + 0.84 * i / steps);
            const ct = Math.cos(t), st = Math.sin(t);
            pts.push(Qt.point(c + r * Math.sign(ct) * Math.pow(Math.abs(ct), 0.4),
                              c + r * Math.sign(st) * Math.pow(Math.abs(st), 0.4)));
        }
        return pts;
    }
    readonly property var outline: squircle(96)
    readonly property var sheetPath: sheet(48)
    readonly property var crestPath: crest(48)
    readonly property var rimPath: rim(40)

    // ——— Kafelek ———
    Shape {
        anchors.fill: parent
        visible: !ai.webapp
        preferredRendererType: Shape.CurveRenderer

        // Tło: ukośnie od światła (lewa góra) do cienia (prawy dół);
        // w ciemnym motywie — przyciemnione, barwione szkło
        ShapePath {
            strokeColor: ai.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.07)
            strokeWidth: 1
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: ai.size; y2: ai.size
                GradientStop { position: 0; color: ai.dark ? Qt.tint("#15161D", ai.alpha(ai.hi, ai.design ? 0.58 : 0)) : ai.hi }
                GradientStop { position: 1; color: ai.dark ? Qt.tint("#0A0B0F", ai.alpha(ai.lo, ai.design ? 0.55 : 0)) : ai.lo }
            }
            PathPolyline { path: ai.outline }
        }
        // Połysk u góry
        ShapePath {
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: ai.size * 0.6
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, ai.dark ? 0.10 : (ai.design ? 0.30 : 0.6)) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
            }
            PathPolyline { path: ai.outline }
        }
        // Arkusz fali: osobna, głębsza warstwa materiału
        ShapePath {
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: ai.size; y1: ai.size * 0.45; x2: ai.size * 0.3; y2: ai.size
                GradientStop { position: 0; color: ai.dark ? Qt.tint("#191A22", ai.alpha(ai.hi, ai.design ? 0.40 : 0)) : Qt.tint(ai.lo, ai.alpha(ai.hi, 0.15)) }
                GradientStop { position: 1; color: ai.dark ? Qt.tint("#08090C", ai.alpha(ai.lo, ai.design ? 0.45 : 0)) : Qt.darker(ai.lo, ai.design ? 1.35 : 1.08) }
            }
            PathPolyline { path: ai.sheetPath }
        }
        // Świetlna krawędź arkusza
        ShapePath {
            strokeColor: ai.dark ? ai.alpha(Qt.lighter(ai.hi, 1.1), ai.design ? 0.85 : 0.35) : Qt.rgba(1, 1, 1, ai.design ? 0.9 : 1)
            strokeWidth: Math.max(1.2, ai.size / 44)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathPolyline { path: ai.crestPath }
        }
        // Jasny rant u góry
        ShapePath {
            strokeColor: ai.dark ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.55)
            strokeWidth: 1
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathPolyline { path: ai.rimPath }
        }
    }

    // ——— Znak ———
    // Cień (jasny motyw) albo poświata (ciemny) pod znakiem
    Icon {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: ai.dark ? 0 : ai.size / 60
        visible: !!ai.design
        d: glyph.d
        size: glyph.size
        stroke: ai.dark ? 5.5 : 2.6
        color: ai.dark ? ai.hi : Qt.darker(ai.lo, 1.5)
        opacity: ai.dark ? 0.22 : 0.35
    }
    Icon {
        id: glyph
        anchors.centerIn: parent
        visible: !!ai.design
        d: ai.design ? (Icons[ai.design[2]] || "") : ""
        size: ai.size * 0.5
        stroke: 2.4
        color: ai.dark ? Qt.tint("white", ai.alpha(ai.hi, 0.35)) : "white"
    }

    // Oryginalna ikona programu na podkładzie
    Kirigami.Icon {
        anchors.centerIn: parent
        visible: !ai.design && !ai.webapp
        width: ai.size * 0.66
        height: width
        source: ai.source
    }

    // Aplikacja webowa: jej kafelek przycięty do squircle
    Item {
        id: webTile
        anchors.fill: parent
        visible: ai.webapp
        layer.enabled: ai.webapp
        layer.samples: 4
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.rgba(0, 0, 0, 0.08)
                strokeWidth: 1
                fillItem: webImage
                PathPolyline { path: ai.outline }
            }
        }
        Kirigami.Icon {
            id: webImage
            visible: false
            width: ai.size; height: ai.size
            source: ai.source
            layer.enabled: true
        }
    }
}
