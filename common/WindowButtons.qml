pragma ComponentBehavior: Bound
import QtQuick

// Okrągłe przyciski okna Aster: minimalizuj, maksymalizuj, zamknij (kolor pojawia się pod kursorem)
Row {
    id: wb
    required property Window window
    spacing: 8
    readonly property bool maxed: window.visibility === Window.Maximized || window.visibility === Window.FullScreen

    Repeater {
        model: [
            { icon: "minimize", act: "min", hover: "#F2B33D" },
            { icon: "maximize", act: "max", hover: "#34C27A" },
            { icon: "close", act: "close", hover: "#F0524F" }
        ]
        delegate: Rectangle {
            id: wc
            required property var modelData
            width: 28; height: 28; radius: 14
            color: wcArea.containsMouse ? modelData.hover : Theme.fill
            scale: wcArea.pressed ? 0.9 : 1
            Behavior on color { ColorAnimation { duration: 140 } }
            Behavior on scale { NumberAnimation { duration: 100 } }
            Icon { anchors.centerIn: parent; d: Icons[wc.modelData.icon]; size: 13; stroke: 2; color: wcArea.containsMouse ? "white" : Theme.text2 }
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
