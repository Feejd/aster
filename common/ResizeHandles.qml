pragma ComponentBehavior: Bound
import QtQuick

// Uchwyty zmiany rozmiaru okna bez ramki: krawędzie i rogi wokół `frame` (przesuniętej o `margin`)
Item {
    id: rh
    required property Window window
    required property Item frame
    property int margin: 0
    property int grip: 8
    anchors.fill: parent
    visible: rh.window.visibility !== Window.Maximized && rh.window.visibility !== Window.FullScreen

    Repeater {
        model: [
            { e: Qt.LeftEdge, x: 0, y: 1, w: 0, h: 1, c: Qt.SizeHorCursor },
            { e: Qt.RightEdge, x: 2, y: 1, w: 0, h: 1, c: Qt.SizeHorCursor },
            { e: Qt.TopEdge, x: 1, y: 0, w: 1, h: 0, c: Qt.SizeVerCursor },
            { e: Qt.BottomEdge, x: 1, y: 2, w: 1, h: 0, c: Qt.SizeVerCursor },
            { e: Qt.TopEdge | Qt.LeftEdge, x: 0, y: 0, w: 0, h: 0, c: Qt.SizeFDiagCursor },
            { e: Qt.TopEdge | Qt.RightEdge, x: 2, y: 0, w: 0, h: 0, c: Qt.SizeBDiagCursor },
            { e: Qt.BottomEdge | Qt.LeftEdge, x: 0, y: 2, w: 0, h: 0, c: Qt.SizeBDiagCursor },
            { e: Qt.BottomEdge | Qt.RightEdge, x: 2, y: 2, w: 0, h: 0, c: Qt.SizeFDiagCursor }
        ]
        delegate: MouseArea {
            required property var modelData
            x: modelData.x === 0 ? rh.margin - rh.grip : modelData.x === 1 ? rh.margin + rh.grip : rh.margin + rh.frame.width - rh.grip
            y: modelData.y === 0 ? rh.margin - rh.grip : modelData.y === 1 ? rh.margin + rh.grip : rh.margin + rh.frame.height - rh.grip
            width: modelData.w ? rh.frame.width - 2 * rh.grip : 2 * rh.grip
            height: modelData.h ? rh.frame.height - 2 * rh.grip : 2 * rh.grip
            cursorShape: modelData.c
            onPressed: rh.window.startSystemResize(modelData.e)
        }
    }
}
