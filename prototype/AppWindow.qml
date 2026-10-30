import QtQuick
import QtQuick.Effects
import "Icons.js" as I

// Wspólna ramka okna aplikacji: szkło, cień, przeciąganie za górny pasek,
// maksymalizacja, okrągłe przyciski i „zasysanie” do ikony na pasku przy minimalizacji.
// Treść okna rysuje własny układ; górne 52 px służy do przeciągania.
Item {
    id: win
    property var t
    property Item backdrop
    property bool open: true
    property bool maximized: false
    property rect normalGeometry: Qt.rect(200, 80, 900, 600)
    property rect maxGeometry: Qt.rect(0, 0, 1440, 844)
    property point minimizeTarget: Qt.point(560, 900)
    property real sidebarWidth: 0          // szerokość przezroczystego paska bocznego (reszta to jaśniejszy panel)
    default property alias content: body.data

    signal closeRequested()
    signal minimizeRequested()
    signal activated()

    x: maximized ? maxGeometry.x : normalGeometry.x
    y: maximized ? maxGeometry.y : normalGeometry.y
    width: maximized ? maxGeometry.width : normalGeometry.width
    height: maximized ? maxGeometry.height : normalGeometry.height
    Behavior on x { enabled: !titleDrag.active; SpringAnimation { spring: 9; damping: 0.72; epsilon: 0.5 } }
    Behavior on y { enabled: !titleDrag.active; SpringAnimation { spring: 9; damping: 0.72; epsilon: 0.5 } }
    Behavior on width { SpringAnimation { spring: 9; damping: 0.72; epsilon: 0.5 } }
    Behavior on height { SpringAnimation { spring: 9; damping: 0.72; epsilon: 0.5 } }

    property real gx: 1
    property real gy: 1
    property real gp: 0
    visible: opacity > 0.01
    transform: [
        Scale { origin.x: win.width / 2; origin.y: win.height; xScale: win.gx; yScale: win.gy },
        Translate {
            x: win.gp * (win.minimizeTarget.x - (win.x + win.width / 2))
            y: win.gp * (win.minimizeTarget.y - (win.y + win.height))
        }
    ]
    states: State {
        name: "closed"
        when: !win.open
        PropertyChanges { win.gx: 0.1; win.gy: 0.03; win.gp: 1; win.opacity: 0 }
    }
    transitions: [
        Transition {
            to: "closed"
            ParallelAnimation {
                NumberAnimation { target: win; property: "gy"; duration: 150; easing.type: Easing.InCubic }
                NumberAnimation { target: win; property: "gx"; duration: 200; easing.type: Easing.InQuart }
                NumberAnimation { target: win; property: "gp"; duration: 200; easing.type: Easing.InQuad }
                SequentialAnimation {
                    PauseAnimation { duration: 170 }
                    NumberAnimation { target: win; property: "opacity"; duration: 90 }
                }
            }
        },
        Transition {
            from: "closed"
            ParallelAnimation {
                NumberAnimation { target: win; property: "gy"; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 0.6 }
                NumberAnimation { target: win; property: "gx"; duration: 250; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
                NumberAnimation { target: win; property: "gp"; duration: 190; easing.type: Easing.OutCubic }
                NumberAnimation { target: win; property: "opacity"; duration: 90 }
            }
        }
    ]


    // ——— Przeciąganie; dociągnięcie do górnej krawędzi = pełny ekran (jak w macOS) ———
    property bool snapArmed: false
    property rect dragStart
    property rect preDrag
    function beginDrag(p) {
        win.activated();
        if (win.maximized) {
            // okno „odkleja się” od pełnego ekranu tak, żeby pasek tytułu został pod kursorem
            const ratio = (p.x - win.x) / Math.max(1, win.width);
            const nw = win.normalGeometry.width, nh = win.normalGeometry.height;
            win.normalGeometry = Qt.rect(p.x - ratio * nw, Math.max(0, p.y - 24), nw, nh);
            win.maximized = false;
        }
        dragStart = win.normalGeometry;
        preDrag = win.normalGeometry;
    }
    function moveDrag(p, tr) {
        win.normalGeometry = Qt.rect(dragStart.x + tr.x, Math.max(0, dragStart.y + tr.y), dragStart.width, dragStart.height);
        snapArmed = p.y < 10;
    }
    function endDrag() {
        if (snapArmed) {
            win.normalGeometry = preDrag;
            win.maximized = true;
        }
        snapArmed = false;
    }
    SnapPreview {
        parent: win.parent
        z: win.z - 0.5
        t: win.t
        geo: win.maxGeometry
        on: win.snapArmed
    }

    TapHandler { gesturePolicy: TapHandler.DragThreshold; onPressedChanged: if (pressed) win.activated() }

    RectangularShadow {
        anchors.fill: parent
        radius: win.maximized ? 0 : 18
        blur: 60
        offset.y: 24
        color: win.t.shadow
    }
    Glass {
        anchors.fill: parent
        backdrop: win.backdrop
        sx: win.x
        sy: win.y
        radius: win.maximized ? 0 : 18
        tint: win.t.windowGlass
        edge: win.t.edge
        rim: win.t.rim
    }
    Rectangle {
        x: win.sidebarWidth
        width: parent.width - win.sidebarWidth
        height: parent.height
        color: win.t.pane
        topRightRadius: win.maximized ? 0 : 18
        bottomRightRadius: win.maximized ? 0 : 18
        topLeftRadius: win.sidebarWidth > 0 ? 0 : (win.maximized ? 0 : 18)
        bottomLeftRadius: win.sidebarWidth > 0 ? 0 : (win.maximized ? 0 : 18)
    }

    Item {
        id: titleZone
        width: parent.width; height: 52
        DragHandler {
            id: titleDrag
            target: null
            onActiveChanged: if (active) win.beginDrag(centroid.scenePosition); else win.endDrag()
            onTranslationChanged: if (active) win.moveDrag(centroid.scenePosition, translation)
        }
        TapHandler { onDoubleTapped: win.maximized = !win.maximized }
    }

    Item { id: body; anchors.fill: parent }

    Row {
        anchors.right: parent.right; anchors.rightMargin: 16
        y: 12
        spacing: 8
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
                color: wcArea.containsMouse ? modelData.hover : win.t.fill
                scale: wcArea.pressed ? 0.9 : 1
                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on scale { NumberAnimation { duration: 100 } }
                Icon { anchors.centerIn: parent; d: I[wc.modelData.icon]; size: 13; stroke: 2; color: wcArea.containsMouse ? "white" : win.t.text2 }
                MouseArea {
                    id: wcArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (wc.modelData.act === "min") win.minimizeRequested();
                        else if (wc.modelData.act === "max") win.maximized = !win.maximized;
                        else win.closeRequested();
                    }
                }
            }
        }
    }
}
