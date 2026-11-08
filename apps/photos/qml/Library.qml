pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Photos

// Siatka zdjęć: kwadratowe kafelki bez ramek (jak w Zdjęciach Windows i macOS), u góry plakietka
// z miesiącem zdjęć, które właśnie widać. Rozmiar kafelków: Ctrl+kółko albo przyciski na pasku.
Item {
    id: lib
    required property var model                    // PhotoModel
    property int tile: 168                          // docelowy bok kafelka
    property string emptyText: "Brak zdjęć"
    property string emptyHint: ""
    signal openPhoto(int index)
    signal contextMenu(int index, real x, real y)

    readonly property int columns: Math.max(2, Math.round((grid.width - 2 * pad) / tile))
    readonly property real cell: Math.floor((grid.width - 2 * pad) / columns)
    readonly property real pad: 16

    function positionAt(i) { grid.positionViewAtIndex(i, GridView.Contain); }

    GridView {
        id: grid
        anchors.fill: parent
        leftMargin: lib.pad; rightMargin: lib.pad
        topMargin: 44; bottomMargin: 16
        cellWidth: lib.cell; cellHeight: lib.cell
        model: lib.model
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: lib.cell * 3
        delegate: Item {
            id: tileItem
            required property int index
            required property string thumb
            required property string name
            width: lib.cell; height: lib.cell
            Rectangle {
                anchors.fill: parent; anchors.margins: 2
                color: Theme.fill
                clip: true
                Image {
                    id: im
                    anchors.fill: parent
                    source: tileItem.thumb
                    sourceSize: Qt.size(lib.cell, lib.cell)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 110 } }
                    scale: tileArea.containsMouse ? 1.04 : 1
                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                }
                Rectangle { anchors.fill: parent; color: "white"; opacity: tileArea.pressed ? 0.12 : 0 }
            }
            MouseArea {
                id: tileArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (e) => {
                    if (e.button === Qt.RightButton) { const p = mapToItem(lib, e.x, e.y); lib.contextMenu(tileItem.index, p.x, p.y); }
                    else lib.openPhoto(tileItem.index);
                }
            }
        }

        // Ctrl+kółko — większe / mniejsze kafelki
        WheelHandler {
            acceptedModifiers: Qt.ControlModifier
            onWheel: (e) => lib.tile = Math.max(90, Math.min(360, lib.tile * Math.pow(1.0015, e.angleDelta.y)))
        }

        // Cienki suwak
        Rectangle {
            visible: grid.contentHeight > grid.height
            anchors.right: parent.right; anchors.rightMargin: 3
            y: grid.visibleArea.yPosition * grid.height
            width: 5; radius: 2.5
            height: Math.max(30, grid.visibleArea.heightRatio * grid.height)
            color: Theme.text2
            opacity: grid.moving ? 0.5 : 0.18
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }

    // Miesiąc zdjęć na górze widoku
    Rectangle {
        x: lib.pad + 2; y: 8
        visible: lib.model.count > 0
        width: monthText.implicitWidth + 24; height: 28; radius: 14
        color: Theme.surface
        border.width: 1; border.color: Theme.edge
        Text {
            id: monthText
            anchors.centerIn: parent
            text: { grid.contentY; lib.model.count; return lib.model.monthAt(Math.max(0, grid.indexAt(lib.pad + 4, grid.contentY + 48))); }
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
        }
    }

    Column {
        anchors.centerIn: parent
        visible: lib.model.count === 0 && !lib.model.loading
        spacing: 8
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 64; height: 64; radius: 20
            color: Theme.fill
            Icon { anchors.centerIn: parent; d: Icons.image; size: 30; stroke: 1.6; color: Theme.text2 }
        }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: lib.emptyText; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(360, lib.width - 40)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: lib.emptyHint
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
        }
    }
}
