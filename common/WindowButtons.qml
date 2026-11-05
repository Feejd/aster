pragma ComponentBehavior: Bound
import QtQuick

// Przyciski okna Aster: minimalizuj, maksymalizuj, zamknij.
// Spokojne znaki bez tła; po najechaniu tło, a zamknięcie czerwienieje. W oknie w tle znaki są przygaszone.
Row {
    id: wb
    required property Window window
    // Kolory w spoczynku w oknie w tle — na kolorowym pasku (np. aplikacji webowej) podajemy jaśniejsze/ciemniejsze
    property color idleColor: Theme.fill
    property color idleIconColor: Theme.text2
    spacing: 2
    readonly property bool maxed: window.visibility === Window.Maximized || window.visibility === Window.FullScreen
    readonly property bool lit: window.active || WindowEffects.preview || groupHover.hovered

    HoverHandler { id: groupHover }

    Repeater {
        model: [
            { icon: "minimize", act: "min" },
            { icon: "maximize", act: "max" },
            { icon: "close", act: "close" }
        ]
        delegate: Rectangle {
            id: wc
            required property var modelData
            readonly property bool closing: modelData.act === "close"
            width: 34; height: 30; radius: 6
            color: !wcArea.containsMouse ? "transparent" : closing ? "#D93B40" : Theme.hover
            Icon {
                anchors.centerIn: parent
                d: Icons[wc.modelData.icon]; size: 13; stroke: 2
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
