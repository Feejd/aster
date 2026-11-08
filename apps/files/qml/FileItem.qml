import QtQuick
import Aster.Ui
import Aster.Files

// Jeden plik albo folder — jako kafelek (siatka) albo wiersz (lista).
// Kliknięcia, przeciąganie, upuszczanie na folder i zmiana nazwy w miejscu.
Item {
    id: fi
    property var file                 // dane z FolderModel (name, url, isDir, iconName, isImage, localPath…)
    property string dateText
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
            NumberAnimation { target: shift; property: "y"; to: 0; duration: 130; easing.type: Easing.OutQuint }
        }
    }

    readonly property bool dropTarget: drop.containsDrag

    signal clicked(int modifiers, int button, real wx, real wy)
    signal doubleClicked()
    signal dragStarted()
    signal dragMoved(real wx, real wy)
    signal dragEnded()
    signal droppedOn(var drop)
    signal renameCommitted(string name)
    signal renameCancelled()

    onRenamingChanged: {
        if (renaming) {
            nameEdit.text = file.name;
            nameEdit.forceActiveFocus();
            const dot = file.isDir ? -1 : file.name.lastIndexOf(".");
            nameEdit.select(0, dot > 0 ? dot : file.name.length);
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: fi.listMode ? 0 : 4
        radius: fi.listMode ? 7 : 10
        color: fi.dropTarget ? Theme.accentSoft
             : fi.selected ? Theme.accentSoft
             : (area.containsMouse ? Theme.hover : "transparent")
        border.width: fi.dropTarget ? 2 : (fi.selected && !fi.listMode ? 1 : 0)
        border.color: fi.dropTarget ? Theme.accent : Theme.accentAlpha(0.4)
        Behavior on color { ColorAnimation { duration: 90 } }
    }

    // Ikona: miniatura zdjęcia, folder w kolorze akcentu albo karta z rozszerzeniem w kolorze typu
    // (komponent wewnętrzny nie widzi identyfikatorów pliku — dane dostaje przez `file`)
    component Badge: Item {
        id: badge
        property var file
        property real size: 64
        readonly property string ext: {
            if (!file || file.isDir) return "";
            const n = file.name, i = n.lastIndexOf(".");
            return i > 0 && n.length - i <= 5 ? n.slice(i + 1).toUpperCase() : "";
        }
        width: size; height: size
        Image {
            id: thumb
            anchors.fill: parent
            visible: !!badge.file && badge.file.isImage && status === Image.Ready
            source: badge.file && badge.file.isImage ? "file://" + badge.file.localPath : ""
            sourceSize.width: badge.size * 2
            sourceSize.height: badge.size * 2
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
        }
        Rectangle {
            visible: !!badge.file && badge.file.isDir
            anchors.centerIn: parent
            width: badge.size * 0.94; height: badge.size * 0.72
            radius: badge.size * 0.13
            color: Qt.alpha(Theme.accent, Theme.dark ? 0.3 : 0.16)
            Icon { anchors.centerIn: parent; d: Icons.folder; size: badge.size * 0.36; color: Theme.accentText }
        }
        Rectangle {
            readonly property color tint: FileKinds.tint(badge.ext)
            visible: !!badge.file && !badge.file.isDir && !thumb.visible
            anchors.centerIn: parent
            width: badge.size * 0.78; height: badge.size * 0.97
            radius: badge.size * 0.13
            color: Qt.alpha(tint, Theme.dark ? 0.28 : 0.16)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: badge.size * 0.12
                visible: badge.size >= 40
                text: badge.ext
                color: Theme.dark ? Qt.lighter(parent.tint, 1.9) : parent.tint
                font.family: Theme.font; font.pixelSize: Math.round(badge.size * 0.17); font.weight: Font.Bold
            }
        }
    }

    // Siatka
    Column {
        visible: !fi.listMode
        anchors.horizontalCenter: parent.horizontalCenter
        y: 14
        width: parent.width - 16
        spacing: 6
        opacity: fi.cut ? 0.5 : 1
        Badge { anchors.horizontalCenter: parent.horizontalCenter; size: 64; file: fi.file }
        Text {
            visible: !fi.renaming
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: fi.file ? fi.file.name : ""
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
            wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
        }
        Text {
            visible: !fi.renaming
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: fi.file ? (fi.showWhere ? fi.file.where : fi.dateText) : ""
            color: Theme.text2
            font.family: Theme.font; font.pixelSize: 11; font.letterSpacing: 0.1
            elide: Text.ElideMiddle
        }
    }

    // Lista
    Item {
        visible: fi.listMode
        anchors.fill: parent
        opacity: fi.cut ? 0.5 : 1
        Badge { x: 14; anchors.verticalCenter: parent.verticalCenter; size: 26; file: fi.file }
        Text {
            visible: !fi.renaming
            x: 50; width: parent.width - 50 - 400
            anchors.verticalCenter: parent.verticalCenter
            text: fi.file ? fi.file.name : ""
            color: Theme.text; font.family: Theme.font; font.pixelSize: 13
            elide: Text.ElideRight
        }
        Text { x: parent.width - 390; width: 160; anchors.verticalCenter: parent.verticalCenter; text: fi.file ? (fi.showWhere ? fi.file.where : fi.dateText) : ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; elide: Text.ElideMiddle }
        Text { x: parent.width - 220; width: 130; anchors.verticalCenter: parent.verticalCenter; text: fi.file ? fi.file.kind : ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; elide: Text.ElideRight }
        Text { x: parent.width - 90; width: 78; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; text: fi.file ? fi.file.sizeText : ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
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
        keys: ["aster-files", "text/uri-list"]
        enabled: !!(fi.file && fi.file.isDir) && !fi.selected
        onDropped: (d) => fi.droppedOn(d)
    }

    // Pole zmiany nazwy
    Rectangle {
        visible: fi.renaming
        x: fi.listMode ? 46 : 8
        y: fi.listMode ? (parent.height - height) / 2 : 84
        width: fi.listMode ? parent.width - 46 - 410 : parent.width - 16
        height: fi.listMode ? 26 : Math.max(26, nameEdit.contentHeight + 8)
        radius: 6
        color: Theme.surface
        border.width: 1.5
        border.color: Theme.accent
        TextInput {
            id: nameEdit
            anchors.fill: parent
            anchors.margins: 4
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 13
            horizontalAlignment: fi.listMode ? TextInput.AlignLeft : TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            wrapMode: fi.listMode ? TextInput.NoWrap : TextInput.Wrap
            selectByMouse: true
            selectionColor: Theme.accentSoft
            selectedTextColor: Theme.text
            Keys.onReturnPressed: fi.renameCommitted(text)
            Keys.onEnterPressed: fi.renameCommitted(text)
            Keys.onEscapePressed: fi.renameCancelled()
            onActiveFocusChanged: if (!activeFocus && fi.renaming) fi.renameCommitted(text)
        }
    }
}
