import QtQuick

// Jeden plik albo folder w oknie Plików — jako kafelek (siatka) albo wiersz (lista).
// Obsługuje kliknięcia, przeciąganie, upuszczanie na folder i zmianę nazwy w miejscu.
Item {
    id: fi
    property var t
    property var file
    property bool listMode: false
    property bool selected: false
    property bool cut: false
    property bool renaming: false
    property bool showWhere: false
    property Item coordRoot
    property int enterDelay: -1

    transform: Translate { id: shift }
    Component.onCompleted: if (enterDelay >= 0) { opacity = 0; shift.y = 8; enterAnim.start(); }
    SequentialAnimation {
        id: enterAnim
        PauseAnimation { duration: Math.max(0, fi.enterDelay) }
        ParallelAnimation {
            NumberAnimation { target: fi; property: "opacity"; to: 1; duration: 110; easing.type: Easing.OutQuad }
            NumberAnimation { target: shift; property: "y"; to: 0; duration: 220; easing.type: Easing.OutQuint }
        }
    }

    readonly property bool dropTarget: drop.containsDrag

    signal clicked(int modifiers, int button, real wx, real wy)
    signal doubleClicked()
    signal dragStarted()
    signal dragMoved(real wx, real wy)
    signal dragEnded()
    signal droppedOn()
    signal renameCommitted(string name)
    signal renameCancelled()

    onRenamingChanged: {
        if (renaming) {
            nameEdit.text = file.name;
            nameEdit.forceActiveFocus();
            const dot = file.dir ? -1 : file.name.lastIndexOf(".");
            nameEdit.select(0, dot > 0 ? dot : file.name.length);
        }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        anchors.margins: fi.listMode ? 0 : 4
        radius: fi.listMode ? 7 : 10
        color: fi.dropTarget ? Qt.rgba(52 / 255, 86 / 255, 232 / 255, 0.30)
             : fi.selected ? fi.t.accentSoft
             : (area.containsMouse ? fi.t.hover : "transparent")
        border.width: fi.dropTarget ? 2 : (fi.selected && !fi.listMode ? 1 : 0)
        border.color: fi.dropTarget ? fi.t.accent : Qt.rgba(52 / 255, 86 / 255, 232 / 255, 0.4)
        opacity: fi.cut ? 0.5 : 1
        Behavior on color { ColorAnimation { duration: 90 } }
    }

    // Siatka
    Column {
        visible: !fi.listMode
        anchors.horizontalCenter: parent.horizontalCenter
        y: 14
        width: parent.width - 16
        spacing: 6
        opacity: fi.cut ? 0.5 : 1
        FileBadge { anchors.horizontalCenter: parent.horizontalCenter; t: fi.t; file: fi.file }
        Text {
            visible: !fi.renaming
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: fi.file ? fi.file.name : ""
            color: fi.t.text
            font.pixelSize: 13; font.weight: Font.Medium
            wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
        }
        Text {
            visible: !fi.renaming
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: fi.file ? (fi.showWhere ? fi.file.where : fi.file.when) : ""
            color: fi.t.text2
            font.pixelSize: 11
            elide: Text.ElideMiddle
        }
    }

    // Lista
    Item {
        visible: fi.listMode
        anchors.fill: parent
        opacity: fi.cut ? 0.5 : 1
        FileBadge { id: smallBadge; x: 12; anchors.verticalCenter: parent.verticalCenter; t: fi.t; file: fi.file; small: true; scale: 0.8 }
        Text {
            visible: !fi.renaming
            x: 50; width: parent.width - 50 - 400
            anchors.verticalCenter: parent.verticalCenter
            text: fi.file ? fi.file.name : ""
            color: fi.t.text; font.pixelSize: 13
            elide: Text.ElideRight
        }
        Text { x: parent.width - 390; width: 160; anchors.verticalCenter: parent.verticalCenter; text: fi.file ? (fi.showWhere ? fi.file.where : fi.file.date) : ""; color: fi.t.text2; font.pixelSize: 12; elide: Text.ElideRight }
        Text { x: parent.width - 220; width: 130; anchors.verticalCenter: parent.verticalCenter; text: fi.file ? fi.file.kind : ""; color: fi.t.text2; font.pixelSize: 12; elide: Text.ElideRight }
        Text { x: parent.width - 90; width: 78; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; text: fi.file ? fi.file.sizeText : ""; color: fi.t.text2; font.pixelSize: 12 }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        property point pressPos
        property bool dragging: false
        property bool wasDrag: false

        onPressed: (m) => { pressPos = Qt.point(m.x, m.y); wasDrag = false; }
        onPositionChanged: (m) => {
            if (!(pressed && (m.buttons & Qt.LeftButton)) || fi.renaming) return;
            if (!dragging && Math.hypot(m.x - pressPos.x, m.y - pressPos.y) > 6) {
                dragging = true;
                wasDrag = true;
                fi.dragStarted();
            }
            if (dragging) {
                const p = mapToItem(fi.coordRoot, m.x, m.y);
                fi.dragMoved(p.x, p.y);
            }
        }
        onReleased: {
            if (dragging) {
                dragging = false;
                fi.dragEnded();
            }
        }
        onClicked: (m) => {
            if (wasDrag) return;
            const p = mapToItem(fi.coordRoot, m.x, m.y);
            fi.clicked(m.modifiers, m.button, p.x, p.y);
        }
        onDoubleClicked: (m) => { if (m.button === Qt.LeftButton) fi.doubleClicked() }
    }

    DropArea {
        id: drop
        anchors.fill: parent
        keys: ["aster-files"]
        enabled: !!(fi.file && fi.file.dir) && !fi.selected
        onDropped: fi.droppedOn()
    }

    // Pole zmiany nazwy
    Rectangle {
        visible: fi.renaming
        x: fi.listMode ? 46 : 8
        y: fi.listMode ? (parent.height - height) / 2 : 84
        width: fi.listMode ? parent.width - 46 - 410 : parent.width - 16
        height: fi.listMode ? 26 : Math.max(26, nameEdit.contentHeight + 8)
        radius: 6
        color: fi.t.surface
        border.width: 1.5
        border.color: fi.t.accent
        TextInput {
            id: nameEdit
            anchors.fill: parent
            anchors.margins: 4
            color: fi.t.text
            font.pixelSize: 13
            horizontalAlignment: fi.listMode ? TextInput.AlignLeft : TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            wrapMode: fi.listMode ? TextInput.NoWrap : TextInput.Wrap
            selectByMouse: true
            selectionColor: fi.t.accentSoft
            selectedTextColor: fi.t.text
            Keys.onReturnPressed: fi.renameCommitted(text)
            Keys.onEnterPressed: fi.renameCommitted(text)
            Keys.onEscapePressed: fi.renameCancelled()
            onActiveFocusChanged: if (!activeFocus && fi.renaming) fi.renameCommitted(text)
        }
    }
}
