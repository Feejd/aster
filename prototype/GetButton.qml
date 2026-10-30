import QtQuick
import QtQuick.Shapes

// Przycisk w stylu sklepu: „Pobierz” → pierścień postępu → „Otwórz”
Item {
    id: gb
    property var t
    property real progress: -1        // -1 nie zainstalowano, 0..1 pobieranie, 1 zainstalowano
    property bool big: false
    property bool onDark: false             // na kolorowym tle: biały przycisk
    property string getLabel: "POBIERZ"
    signal getClicked()
    signal openClicked()

    readonly property bool loading: progress >= 0 && progress < 1
    readonly property bool installed: progress >= 1

    width: loading ? height : label.implicitWidth + (big ? 40 : 28)
    height: big ? 34 : 28
    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        visible: !gb.loading
        clip: true
        color: gb.onDark ? Qt.rgba(1, 1, 1, 0.92) : (gb.big ? gb.t.accent : gb.t.fill)
        scale: area.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        Text {
            id: label
            anchors.centerIn: parent
            text: gb.installed ? "OTWÓRZ" : gb.getLabel
            color: gb.onDark ? gb.t.accent : (gb.big ? "white" : gb.t.accentText)
            font.pixelSize: gb.big ? 14 : 13
            font.weight: Font.Bold
            font.letterSpacing: 0.3
        }
    }

    // Pierścień postępu
    Item {
        anchors.fill: parent
        visible: gb.loading
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: gb.t.line; strokeWidth: 2.5; fillColor: "transparent"
                PathAngleArc { centerX: gb.height / 2; centerY: gb.height / 2; radiusX: gb.height / 2 - 2; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: gb.t.accent; strokeWidth: 2.5; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc { centerX: gb.height / 2; centerY: gb.height / 2; radiusX: gb.height / 2 - 2; radiusY: radiusX; startAngle: -90; sweepAngle: 360 * Math.max(0.02, gb.progress) }
            }
        }
        Rectangle { anchors.centerIn: parent; width: gb.height * 0.28; height: width; radius: 2; color: gb.t.accent }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -4
        onClicked: {
            if (gb.installed) gb.openClicked();
            else if (!gb.loading) gb.getClicked();
        }
    }
}
