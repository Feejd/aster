import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

// Ikona programu w jednym kształcie dla całego systemu — „squircle” (superelipsa), jak w macOS/iOS.
//  • programy Aster i podstawowe programy systemu: kolorowy kafelek z białym znakiem (spójny zestaw),
//  • aplikacje webowe Aster: ich kafelek (już ma kształt) wycięty w squircle,
//  • reszta: oryginalna ikona na jasnym/ciemnym podkładzie, więc wszystko ma ten sam obrys.
Item {
    id: ai
    property string desktopId: ""          // np. "org.aster.files"
    property var source                    // ikona z systemu (nazwa albo QIcon)
    property real size: 52
    width: size
    height: size

    // Zestaw ikon Aster: [kolor górny, kolor dolny, znak z Icons.js]
    readonly property var designs: ({
        "aster-start": ["#7C9BFF", "#3456E8", "aster"],
        "org.aster.files": ["#5AB4FF", "#2563EB", "folder"],
        "org.aster.browser": ["#4FD1C5", "#3B5BDB", "globe"],
        "org.aster.webapps": ["#C084FC", "#6D28D9", "webapp"],
        "org.aster.store": ["#60C8FF", "#1D6CF2", "bag"],
        "org.aster.settings": ["#C3C8D1", "#4B5262", "gear"],
        "systemsettings": ["#A3A9B5", "#4B5262", "sliders"],
        "kdesystemsettings": ["#A3A9B5", "#4B5262", "sliders"],
        "org.kde.konsole": ["#3F3F46", "#111114", "code"],
        "org.kde.kate": ["#FDBA4D", "#EA6A0C", "pencil"],
        "org.kde.discover": ["#4ADE80", "#0E9F6E", "bag"],
        "org.kde.okular": ["#FB7185", "#D61F45", "doc"],
        "org.kde.gwenview": ["#F9A8D4", "#C026D3", "image"],
        "org.kde.elisa": ["#FF8A8A", "#E11D48", "music"],
        "org.kde.spectacle": ["#7DD3FC", "#6366F1", "screenshot"],
        "org.kde.kcalc": ["#FCD34D", "#F59E0B", "grid"],
        "org.kde.ark": ["#D6B98C", "#9A6B3B", "drive"],
        "org.kde.dolphin": ["#5AB4FF", "#2563EB", "folder"],
        "org.mozilla.firefox": ["#FDBA4D", "#E8590C", "globe"],
        "firefox": ["#FDBA4D", "#E8590C", "globe"]
    })
    readonly property var design: designs[desktopId] || null
    readonly property bool webapp: desktopId.indexOf("aster-webapp-") === 0
    readonly property bool dark: Theme.dark

    // Obrys squircle (|x|^5 + |y|^5 = 1) jako łamana — gładki przy każdym rozmiarze
    function squircle(s, inset) {
        const pts = [];
        const n = 5, steps = 96, c = s / 2, r = s / 2 - inset;
        for (let i = 0; i <= steps; ++i) {
            const t = (i / steps) * Math.PI * 2;
            const ct = Math.cos(t), st = Math.sin(t);
            const x = Math.sign(ct) * Math.pow(Math.abs(ct), 2 / n);
            const y = Math.sign(st) * Math.pow(Math.abs(st), 2 / n);
            pts.push(Qt.point(c + r * x, c + r * y));
        }
        return pts;
    }
    readonly property var outline: squircle(size, 0.5)

    // Kafelek (kolor albo podkład) z połyskiem u góry
    Shape {
        anchors.fill: parent
        visible: !ai.webapp
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: ai.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
            strokeWidth: 1
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: ai.size
                GradientStop { position: 0; color: ai.design ? ai.design[0] : (ai.dark ? "#4A4B53" : "#FFFFFF") }
                GradientStop { position: 1; color: ai.design ? ai.design[1] : (ai.dark ? "#2A2B31" : "#E9EBF0") }
            }
            PathPolyline { path: ai.outline }
        }
        ShapePath {
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: ai.size * 0.55
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, ai.design ? 0.28 : 0.5) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
            }
            PathPolyline { path: ai.outline }
        }
    }

    // Znak Aster na kolorowym kafelku
    Icon {
        anchors.centerIn: parent
        visible: !!ai.design
        d: ai.design ? (Icons[ai.design[2]] || "") : ""
        size: ai.size * 0.5
        stroke: 2.1
        color: "white"
    }

    // Oryginalna ikona programu na podkładzie
    Kirigami.Icon {
        anchors.centerIn: parent
        visible: !ai.design && !ai.webapp
        width: ai.size * 0.68
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
