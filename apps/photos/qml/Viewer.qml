pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Aster.Ui
import Aster.Photos

// Oglądanie: zdjęcie na całe okno, u góry nazwa i narzędzia (powiększenie, obrót, kosz, informacje),
// na dole pasek miniatur z folderu, po bokach strzałki. Pokaz slajdów i pełny ekran chowają resztę.
Item {
    id: viewer
    required property var model                    // PhotoModel
    required property Window window
    property int index: 0
    property bool canGoBack: false                 // otwarte z biblioteki — strzałka „wstecz”
    property bool infoOpen: false
    property bool slideshow: false
    property bool chromeShown: true
    signal backRequested()
    signal menuRequested(real x, real y)
    signal toast(string text, bool undo)

    readonly property var photo: { model.count; return model.get(index); }
    readonly property bool hasPhoto: !!photo.path
    readonly property bool fullscreen: window.visibility === Window.FullScreen
    readonly property bool immersive: fullscreen || slideshow
    readonly property bool chrome: !immersive || chromeShown
    readonly property alias view: photoView

    function go(i) {
        if (model.count === 0) return;
        index = Math.max(0, Math.min(model.count - 1, i));
    }
    function next() { if (index < model.count - 1) go(index + 1); else if (slideshow) go(0); }
    function prev() { go(index - 1); }
    function rotate(cw) {
        if (!hasPhoto || !Photos.rotate(photo.path, cw)) return;
        model.touch(index);
        photoView.source = "";                          // wczytaj na nowo (plik ten sam, treść inna)
        photoView.source = Qt.binding(() => viewer.photo.path || "");
        if (infoOpen) info = Photos.info(photo.path);
    }
    function trash() {
        if (!hasPhoto) return;
        const name = photo.name;
        if (!Photos.trash(photo.path)) return;
        const i = index;
        model.removeAt(i);
        if (model.count === 0) { backRequested(); }
        else go(Math.min(i, model.count - 1));
        toast("„" + name + "” przeniesiono do kosza", true);
    }
    function toggleSlideshow() {
        slideshow = !slideshow;
        if (slideshow) { photoView.setFit(); wake(); }
    }
    function wake() { chromeShown = true; hideTimer.restart(); }

    property var info: ({})
    onInfoOpenChanged: if (infoOpen && hasPhoto) info = Photos.info(photo.path)
    onPhotoChanged: if (infoOpen && hasPhoto) info = Photos.info(photo.path)
    onIndexChanged: strip.positionViewAtIndex(index, ListView.Contain)
    Component.onCompleted: strip.positionViewAtIndex(index, ListView.Center)

    Timer { id: hideTimer; interval: 2200; onTriggered: if (viewer.immersive) viewer.chromeShown = false }
    Timer { interval: 4000; repeat: true; running: viewer.slideshow; onTriggered: viewer.next() }
    onImmersiveChanged: { if (immersive) wake(); else chromeShown = true; }

    // ——— Skróty ———
    focus: true
    Keys.onLeftPressed: (e) => { if (e.modifiers & Qt.AltModifier && canGoBack) backRequested(); else prev(); }
    Keys.onRightPressed: next()
    Keys.onPressed: (e) => {
        wake();
        if (e.key === Qt.Key_Home) go(0);
        else if (e.key === Qt.Key_End) go(model.count - 1);
        else if (e.key === Qt.Key_Delete) trash();
        else if (e.key === Qt.Key_Escape) {
            if (slideshow) slideshow = false;
            else if (fullscreen) window.showNormal();
            else if (infoOpen) infoOpen = false;
            else if (canGoBack) backRequested();
            else return;
        }
        else if (e.key === Qt.Key_Space && slideshow) slideshow = false;
        else if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) photoView.zoomBy(1.25);
        else if (e.key === Qt.Key_Minus) photoView.zoomBy(0.8);
        else if (e.key === Qt.Key_0) photoView.setFit();
        else if (e.key === Qt.Key_1) photoView.setActual();
        else if (e.key === Qt.Key_R && (e.modifiers & Qt.ControlModifier)) rotate(!(e.modifiers & Qt.ShiftModifier));
        else if (e.key === Qt.Key_I) infoOpen = !infoOpen;
        else if (e.key === Qt.Key_F5) toggleSlideshow();
        else if (e.key === Qt.Key_F11 || e.key === Qt.Key_F) { if (fullscreen) window.showNormal(); else window.showFullScreen(); }
        else if (e.key === Qt.Key_C && (e.modifiers & Qt.ControlModifier)) { Photos.copy(photo.path); toast("Skopiowano zdjęcie", false); }
        else return;
        e.accepted = true;
    }

    // ——— Zdjęcie ———
    Rectangle {
        anchors.fill: parent
        color: viewer.immersive ? "black" : "transparent"
    }
    PhotoView {
        id: photoView
        x: 0
        y: viewer.immersive ? 0 : top.height
        width: parent.width - (viewer.infoOpen && !viewer.immersive ? infoPane.width : 0)
        height: parent.height - y - (viewer.immersive ? 0 : stripBox.height)
        source: viewer.photo.path || ""
        thumb: viewer.photo.thumb || ""
        animated: !!viewer.photo.animated
        HoverHandler { onPointChanged: viewer.wake() }
    }

    // Strzałki po bokach (widoczne pod kursorem)
    HoverHandler { id: sideHover }
    Repeater {
        model: [[-1, "back"], [1, "forward"]]
        delegate: HoverButton {
            id: arrow
            required property var modelData
            readonly property bool can: modelData[0] < 0 ? viewer.index > 0 : viewer.index < viewer.model.count - 1
            x: modelData[0] < 0 ? photoView.x + 16 : photoView.x + photoView.width - width - 16
            y: photoView.y + (photoView.height - height) / 2
            width: 44; height: 44; radius: 22
            visible: can && viewer.chrome
            opacity: sideHover.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            baseColor: Qt.rgba(0, 0, 0, 0.42)
            color: hovered ? Qt.rgba(0, 0, 0, 0.6) : baseColor
            onClicked: arrow.modelData[0] < 0 ? viewer.prev() : viewer.next()
            Icon { anchors.centerIn: parent; d: Icons[arrow.modelData[1]]; size: 20; stroke: 2.2; color: "white" }
        }
    }

    // ——— Pasek u góry ———
    Rectangle {
        id: top
        width: parent.width; height: 58
        color: viewer.immersive ? Qt.rgba(0, 0, 0, 0.55) : "transparent"
        opacity: viewer.chrome ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        DragHandler { target: null; onActiveChanged: if (active) viewer.window.startSystemMove() }
        TapHandler { onDoubleTapped: if (viewer.window.visibility === Window.Maximized) viewer.window.showNormal(); else viewer.window.showMaximized() }
        readonly property color fg: viewer.immersive ? "white" : Theme.text
        readonly property color fg2: viewer.immersive ? Qt.rgba(1, 1, 1, 0.7) : Theme.text2

        Row {
            id: titleRow
            x: 14; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            ToolBtn { visible: viewer.canGoBack; anchors.verticalCenter: parent.verticalCenter; icon: "back"; onClicked: viewer.backRequested() }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: viewer.canGoBack ? 0 : 8
                Text {
                    width: Math.min(implicitWidth, top.width - tools.width - titleRow.x - 80)
                    elide: Text.ElideMiddle
                    text: viewer.photo.name || ""
                    color: top.fg
                    font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                }
                Text {
                    text: viewer.model.count ? (viewer.index + 1) + " z " + viewer.model.count : ""
                    color: top.fg2
                    font.family: Theme.font; font.pixelSize: 12
                    font.features: { "tnum": 1 }
                }
            }
        }

        Row {
            id: tools
            anchors.right: winButtons.visible ? winButtons.left : parent.right; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            // Powiększenie: −  100%  +
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: zoomRow.width + 4; height: 32; radius: 10
                color: viewer.immersive ? Qt.rgba(1, 1, 1, 0.12) : Theme.fill
                Row {
                    id: zoomRow
                    x: 2; anchors.verticalCenter: parent.verticalCenter
                    Tool { icon: "minus"; onClicked: photoView.zoomBy(0.8); width: 30; height: 28 }
                    HoverButton {
                        width: 52; height: 28; radius: 7
                        onClicked: photoView.zoomed ? photoView.setFit() : photoView.setActual()
                        Text {
                            anchors.centerIn: parent
                            text: photoView.percent + "%"
                            color: top.fg
                            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                        }
                    }
                    Tool { icon: "plus"; onClicked: photoView.zoomBy(1.25); width: 30; height: 28 }
                }
            }
            Item { width: 6; height: 1 }
            Tool { icon: "rotate"; onClicked: viewer.rotate(true) }
            Tool { icon: "trash"; onClicked: viewer.trash() }
            Tool { icon: "info"; on: viewer.infoOpen; onClicked: viewer.infoOpen = !viewer.infoOpen }
            Tool { icon: viewer.slideshow ? "pause" : "play"; onClicked: viewer.toggleSlideshow() }
            Tool { id: moreBtn; icon: "more"; onClicked: { const p = moreBtn.mapToItem(viewer, moreBtn.width, moreBtn.height + 6); viewer.menuRequested(p.x, p.y); } }
        }
        WindowButtons {
            id: winButtons
            visible: !viewer.immersive
            window: viewer.window
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // ——— Miniatury z folderu ———
    Item {
        id: stripBox
        anchors.bottom: parent.bottom
        width: photoView.width; height: viewer.model.count > 1 ? 76 : 14
        opacity: viewer.chrome ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Rectangle { anchors.fill: parent; color: viewer.immersive ? Qt.rgba(0, 0, 0, 0.55) : "transparent" }
        ListView {
            id: strip
            visible: viewer.model.count > 1
            anchors.fill: parent
            anchors.topMargin: 8; anchors.bottomMargin: 12
            orientation: ListView.Horizontal
            spacing: 4
            clip: true
            model: viewer.model
            boundsBehavior: Flickable.StopAtBounds
            // Bieżące zdjęcie pośrodku, o ile się da
            leftMargin: Math.max(12, (width - contentWidth) / 2)
            rightMargin: 12
            highlightRangeMode: ListView.NoHighlightRange
            delegate: Item {
                id: cell
                required property int index
                required property string thumb
                readonly property bool current: index === viewer.index
                width: current ? 64 : 42; height: 56
                Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    color: Theme.fill
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: cell.thumb
                        sourceSize: Qt.size(128, 128)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: cell.current ? 1 : (cellArea.containsMouse ? 0.9 : 0.6)
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 7
                    color: "transparent"
                    border.width: cell.current ? 2 : 0
                    border.color: viewer.immersive ? "white" : Theme.accent
                }
                MouseArea { id: cellArea; anchors.fill: parent; hoverEnabled: true; onClicked: viewer.go(cell.index) }
            }
        }
    }

    // ——— Informacje ———
    Rectangle {
        id: infoPane
        visible: viewer.infoOpen && !viewer.immersive
        anchors.right: parent.right
        y: top.height
        width: 300; height: parent.height - y
        color: "transparent"
        Rectangle { width: 1; height: parent.height; color: Theme.line }
        Flickable {
            anchors.fill: parent
            anchors.leftMargin: 22; anchors.rightMargin: 18
            contentHeight: infoCol.height + 24
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            Column {
                id: infoCol
                y: 8
                width: parent.width
                spacing: 0
                Text { text: "Informacje"; color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold }
                Item { width: 1; height: 14 }
                Repeater {
                    model: [
                        ["Zrobione", viewer.info.taken, "clock"],
                        ["Aparat", viewer.info.camera, "screenshot"],
                        ["Ustawienia", viewer.info.settings, "sliders"],
                        ["Obiektyw", viewer.info.lens, "eye"],
                        ["Wymiary", viewer.info.dimensions ? viewer.info.dimensions + "  ·  " + viewer.info.megapixels : "", "image"],
                        ["Rozmiar pliku", viewer.info.size ? viewer.info.size + "  ·  " + viewer.info.format : "", "doc"],
                        ["Zmienione", viewer.info.modified, "pencil"],
                        ["Nazwa", viewer.info.name, "doc"]
                    ].filter(r => !!r[1])
                    delegate: Item {
                        id: ir
                        required property var modelData
                        width: infoCol.width; height: irCol.height + 16
                        Icon { y: 2; d: Icons[ir.modelData[2]]; size: 16; color: Theme.text2 }
                        Column {
                            id: irCol
                            x: 28; width: parent.width - 28
                            spacing: 2
                            Text { text: ir.modelData[0]; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                            TextEdit {
                                width: parent.width
                                readOnly: true; selectByMouse: true
                                wrapMode: TextEdit.Wrap
                                text: ir.modelData[1]
                                color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                                font.family: Theme.font; font.pixelSize: 13
                            }
                        }
                    }
                }
                Item { width: 1; height: 4 }
                // Folder — klik otwiera go w Plikach
                HoverButton {
                    width: infoCol.width; height: 50; radius: 10
                    baseColor: Theme.fill
                    onClicked: Photos.showInFolder(viewer.info.path)
                    Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; d: Icons.folder; size: 18; color: Theme.accentText }
                    Column {
                        x: 40; width: parent.width - 52
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: viewer.info.folderName || ""; width: parent.width; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                        Text { text: viewer.info.folder || ""; width: parent.width; elide: Text.ElideMiddle; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
                    }
                }
            }
        }
    }

    component Tool: HoverButton {
        id: tool
        property string icon
        property bool on: false
        width: 34; height: 32
        baseColor: on ? (viewer.immersive ? Qt.rgba(1, 1, 1, 0.18) : Theme.accentSoft) : "transparent"
        color: hovered ? (viewer.immersive ? Qt.rgba(1, 1, 1, 0.16) : Theme.hover) : baseColor
        Icon { anchors.centerIn: parent; d: Icons[tool.icon] || ""; size: 17; color: tool.on && !viewer.immersive ? Theme.accentText : top.fg }
    }
}
