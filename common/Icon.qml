import QtQuick
import QtQuick.Shapes

// Ikona liniowa: ścieżka SVG w siatce 24×24, skalowana do `size`
Item {
    id: ic
    property string d
    property color color: "black"
    property real size: 18
    property real stroke: 1.75
    property color fill: "transparent"     // wypełnienie (np. pełny trójkąt „odtwórz”)

    width: size
    height: size

    Shape {
        width: 24
        height: 24
        scale: ic.size / 24
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: ic.color
            strokeWidth: ic.stroke
            fillColor: ic.fill
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: ic.d }
        }
    }
}
