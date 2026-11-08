import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

// Ikona programu w jednym kształcie dla całego systemu: zaokrąglony kwadrat w kolorze programu z białym znakiem.
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
        "aster-start": ["#93A8FF", "#3456E8", "aster"],
        "aster-trash": ["#E4E8EF", "#7C7F88", "trash"],
        "org.aster.files": ["#74CCFF", "#2E6BE6", "folder"],
        "org.aster.browser": ["#6EF0D6", "#0E8FB8", "globe"],
        "org.aster.webapps": ["#E6A4FF", "#7A3FE0", "webapp"],
        "org.aster.store": ["#86EFC0", "#12966E", "bag"],
        "org.aster.settings": ["#D9DEE7", "#5A5D66", "gear"],
        "systemsettings": ["#D9DEE7", "#5A5D66", "sliders"],
        "kdesystemsettings": ["#D9DEE7", "#5A5D66", "sliders"],
        "org.aster.terminal": ["#8B93A8", "#3F424C", "prompt"],
        "org.aster.calculator": ["#FFE394", "#E8890C", "grid"],
        "org.aster.editor": ["#FFCB73", "#EC6A1E", "pencil"],
        "org.aster.code": ["#8FD3FF", "#4A45C8", "code"],
        "org.aster.vault": ["#FDE68A", "#B4700C", "database"],
        "org.aster.pulse": ["#FFB38A", "#E0336E", "pulse"],
        "org.aster.launch": ["#FFB27A", "#E5366F", "rocket"],
        "org.aster.pdf": ["#FF9AAE", "#DC2F4A", "doc"],
        "org.aster.photos": ["#FFB0DC", "#C13FB0", "image"],
        "org.aster.video": ["#9DB8FF", "#4A3FD8", "film"],
        "org.aster.music": ["#FFA394", "#E23A3A", "music"],
        "org.aster.camera": ["#B9C2D3", "#3A3D46", "camera"],
        "org.aster.montaz": ["#FFB08A", "#D93E6A", "clapper"],
        "org.kde.kamoso": ["#B9C2D3", "#3A3D46", "camera"],
        "org.aster.scanner": ["#A5F3FC", "#0E7490", "scanner"],
        "org.kde.skanlite": ["#A5F3FC", "#0E7490", "scanner"],
        "org.kde.skanpage": ["#A5F3FC", "#0E7490", "scanner"],
        "org.aster.grafika": ["#7DF0E8", "#1FA8A0", "palette"],
        "org.aster.studio": ["#D3B8FF", "#6D28D9", "mic"],
        "org.aster.phone": ["#86EFAC", "#15803D", "phone"],
        "org.kde.kdeconnect.app": ["#86EFAC", "#15803D", "phone"],
        "org.aster.tasks": ["#7EE8A8", "#0E8F5A", "activity"],
        "org.kde.plasma-systemmonitor": ["#7EE8A8", "#0E8F5A", "activity"],
        "org.kde.konsole": ["#8B93A8", "#3F424C", "prompt"],
        "org.kde.kate": ["#FFCB73", "#EC6A1E", "pencil"],
        "org.kde.discover": ["#86EFC0", "#12966E", "bag"],
        "org.kde.okular": ["#FF9AAE", "#DC2F4A", "doc"],
        "org.kde.gwenview": ["#FFB0DC", "#C13FB0", "image"],
        "org.kde.elisa": ["#FFA394", "#E23A3A", "music"],
        "org.kde.dragonplayer": ["#9DB8FF", "#4A3FD8", "film"],
        "org.kde.haruna": ["#9DB8FF", "#4A3FD8", "film"],
        "org.kde.spectacle": ["#A6E0FF", "#5A55EE", "screenshot"],
        "org.kde.kcalc": ["#FFE394", "#E8890C", "grid"],
        "org.kde.ark": ["#EBCD9E", "#9A6838", "drive"],
        "org.kde.dolphin": ["#74CCFF", "#2E6BE6", "folder"],
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

    readonly property real corner: size * 0.3

    // Kafelek: zaokrąglony kwadrat w kolorze programu, u góry odrobinę jaśniejszy (światło z góry),
    // z cienką jasną krawędzią od środka — bez połysku i odbić
    Rectangle {
        anchors.fill: parent
        visible: !ai.webapp
        radius: ai.corner
        gradient: Gradient {
            GradientStop { position: 0; color: ai.design ? Qt.lighter(ai.lo, 1.28) : ai.dark ? "#34353B" : "#FFFFFF" }
            GradientStop { position: 1; color: ai.design ? ai.lo : ai.dark ? "#26272C" : "#E6E7EA" }
        }
    }
    Rectangle {
        anchors.fill: parent
        visible: !ai.webapp
        radius: ai.corner
        color: "transparent"
        border.width: Math.max(1, ai.size / 56)
        border.color: ai.design ? Qt.rgba(1, 1, 1, 0.16) : ai.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.07)
    }

    // Znak: cienka biała linia, jedna grubość w całym zestawie
    Icon {
        id: glyph
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
        width: ai.size * 0.66
        height: width
        source: ai.source
    }

    // Aplikacja webowa: jej kafelek przycięty do tego samego kwadratu
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
                PathRectangle { width: ai.size; height: ai.size; radius: ai.corner }
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
