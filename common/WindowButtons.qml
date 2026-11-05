pragma ComponentBehavior: Bound
import QtQuick

// Przyciski okna Aster: minimalizuj, maksymalizuj, zamknij.
// Trzy kwadratowe płytki w rodzinie ikon Aster: schowaj do doku (strzałka do krawędzi), rozwiń (rogi), zamknij.
// Po najechaniu płytka ciemnieje, a zamknięcie czerwienieje. W oknie w tle płytki znikają i zostają przygaszone znaki.
Row {
    id: wb
    required property Window window
    // Kolory w spoczynku w oknie w tle — na kolorowym pasku (np. aplikacji webowej) podajemy jaśniejsze/ciemniejsze
    property color idleColor: Theme.fill
    property color idleIconColor: Theme.text2
    spacing: 4
    readonly property bool maxed: window.visibility === Window.Maximized || window.visibility === Window.FullScreen
    readonly property bool lit: window.active || WindowEffects.preview || groupHover.hovered

    HoverHandler { id: groupHover }

    Repeater {
        model: [
            { act: "min" },
            { act: "max" },
            { act: "close" }
        ]
        delegate: Rectangle {
            id: wc
            required property var modelData
            readonly property bool closing: modelData.act === "close"
            width: 28; height: 28; radius: 8
            color: wcArea.pressed ? (closing ? "#B92F34" : Theme.line)
                 : wcArea.containsMouse ? (closing ? "#D93B40" : Theme.hover) : wb.lit ? Theme.fill : "transparent"
            Behavior on color { ColorAnimation { duration: 90 } }
            Icon {
                anchors.centerIn: parent
                d: wc.modelData.act === "min" ? Icons.toDock : wc.modelData.act === "close" ? Icons.close : wb.maxed ? Icons.shrink : Icons.expand
                size: 15; stroke: 1.9
                color: wcArea.containsMouse && wc.closing ? "white" : wb.lit ? Theme.text : Theme.text2
            }
            MouseArea {
                id: wcArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (wc.modelData.act === "min") wb.window.showMinimized();
                    else if (wc.modelData.act === "max") { if (wb.maxed) wb.window.showNormal(); else wb.window.showMaximized(); }
                    else wb.window.close();
                }
            }
        }
    }
}
