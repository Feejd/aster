pragma ComponentBehavior: Bound
import QtQuick

// Przyciski okna Aster: minimalizuj, maksymalizuj, zamknij.
// W aktywnym oknie to kolorowe kropki z połyskiem (żółta, zielona, czerwona), w oknie w tle — szare.
// Po najechaniu na grupę pokazują znaki, a przycisk pod kursorem rośnie i dostaje poświatę.
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
            { icon: "minimize", act: "min", top: "#FFD15C", bottom: "#F5A623" },
            { icon: "maximize", act: "max", top: "#5EDB8A", bottom: "#21B35A" },
            { icon: "close", act: "close", top: "#FF7A72", bottom: "#EE3B32" }
        ]
        delegate: Item {
            id: wc
            required property var modelData
            width: 28; height: 28
            readonly property bool hot: wcArea.containsMouse

            // Poświata w kolorze przycisku
            Rectangle {
                anchors.centerIn: parent
                width: 26; height: 26; radius: 13
                color: wc.modelData.bottom
                opacity: wc.hot ? 0.28 : 0
                scale: wc.hot ? 1 : 0.6
                Behavior on opacity { NumberAnimation { duration: 160 } }
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
            }
            Rectangle {
                id: dot
                anchors.centerIn: parent
                width: 16; height: 16; radius: 8
                scale: wcArea.pressed ? 0.85 : wc.hot ? 1.18 : 1
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                gradient: Gradient {
                    GradientStop { position: 0; color: wb.lit ? wc.modelData.top : wb.idleColor }
                    GradientStop { position: 1; color: wb.lit ? wc.modelData.bottom : wb.idleColor }
                }
                border.width: 1
                border.color: wb.lit ? Qt.darker(wc.modelData.bottom, 1.25) : Qt.rgba(0, 0, 0, Theme.dark ? 0.2 : 0.08)
                // połysk
                Rectangle {
                    x: 3; y: 1.5
                    width: parent.width - 6; height: parent.height * 0.45; radius: height / 2
                    visible: wb.lit
                    color: Qt.rgba(1, 1, 1, 0.35)
                }
                Icon {
                    anchors.centerIn: parent
                    d: Icons[wc.modelData.icon]; size: 10; stroke: 2.4
                    color: wb.lit ? Qt.rgba(0, 0, 0, 0.55) : wb.idleIconColor
                    opacity: groupHover.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
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
