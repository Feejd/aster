import QtQuick
import QtQuick.Shapes
import Aster.Ui
import Aster.Store

// Przycisk jak w sklepie: POBIERZ → kółko postępu → OTWÓRZ.
// onDark: wersja na kolorowym tle (biała pigułka).
Item {
    id: gb
    property string appId
    property bool big: false
    property bool onDark: false

    readonly property bool installed: Flatpak.installed.indexOf(appId) >= 0
    readonly property var prog: Flatpak.progress[appId]
    readonly property bool busy: prog !== undefined
    readonly property real fraction: busy && prog >= 0 ? prog : 0

    implicitWidth: busy ? height : label.implicitWidth + (big ? 40 : 30)
    implicitHeight: big ? 36 : 30
    width: implicitWidth
    height: implicitHeight
    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        visible: !gb.busy
        color: gb.onDark ? Qt.rgba(1, 1, 1, area.containsMouse ? 1 : 0.92)
             : gb.installed ? (area.containsMouse ? Qt.darker(Theme.fill, 1.4) : Theme.fill)
             : (area.containsMouse ? Qt.rgba(52 / 255, 86 / 255, 232 / 255, 0.2) : Theme.accentSoft)
        scale: area.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        Text {
            id: label
            anchors.centerIn: parent
            text: gb.installed ? "OTWÓRZ" : "POBIERZ"
            color: gb.onDark ? "#16181D" : (gb.installed ? Theme.text : Theme.accentText)
            font.family: Theme.font
            font.pixelSize: gb.big ? 14 : 12
            font.weight: Font.Bold
            font.letterSpacing: 0.3
        }
    }

    // Kółko: w kolejce kręci się, przy instalacji wypełnia według postępu
    Item {
        anchors.fill: parent
        visible: gb.busy
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: gb.onDark ? Qt.rgba(1, 1, 1, 0.3) : Theme.line
                strokeWidth: 3; fillColor: "transparent"
                PathAngleArc { centerX: gb.height / 2; centerY: gb.height / 2; radiusX: gb.height / 2 - 2; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: gb.onDark ? "white" : Theme.accent
                strokeWidth: 3; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: gb.height / 2; centerY: gb.height / 2; radiusX: gb.height / 2 - 2; radiusY: radiusX
                    startAngle: -90
                    sweepAngle: gb.prog >= 0 ? Math.max(8, 360 * gb.fraction) : 80
                }
            }
            RotationAnimation on rotation { running: gb.busy && gb.prog < 0; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
        }
        Rectangle {
            anchors.centerIn: parent
            width: gb.height * 0.28; height: width; radius: 2
            color: gb.onDark ? "white" : Theme.accent
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: !gb.busy && Flatpak.available
        onClicked: gb.installed ? Flatpak.launch(gb.appId) : Flatpak.install(gb.appId)
    }
}
