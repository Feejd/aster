pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Dialogs
import QtQuick.Pdf
import Aster.Ui
import Aster.Pdf

// Podgląd PDF Aster (zamiast Okulara): strony jedna pod drugą, miniatury albo spis treści z boku,
// szukanie (Ctrl+F), zaznaczanie i kopiowanie tekstu, powiększenie, obrót, drukowanie, właściwości.
// Bez pliku — ekran z ostatnimi dokumentami; dokument otwiera się na stronie, na której skończono czytać.
Window {
    id: win
    property string startFile
    property string path: ""

    width: 1040 + 2 * m
    height: 760 + 2 * m
    minimumWidth: 560 + 2 * m
    minimumHeight: 420 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: path ? docTitle + " — Podgląd PDF" : "Podgląd PDF"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 24
    readonly property bool ready: doc.status === PdfDocument.Ready
    readonly property string fileName: path.substring(path.lastIndexOf("/") + 1)
    // Tytuł z metadanych bywa śmieciem („Microsoft Word - dok1.docx”) — wtedy nazwa pliku
    readonly property string docTitle: ready && doc.title && doc.title.length > 2 && !/\.(docx?|odt|pptx?|xlsx?|tex|dvi)$/i.test(doc.title) ? doc.title : fileName.replace(/\.pdf$/i, "")
    property bool sideOpen: false
    property string sideMode: "thumbs"           // thumbs | outline
    property bool needPassword: false
    property bool wrongPassword: false
    property bool propsOpen: false
    property int restorePage: 0
    property int outlineCount: 0                 // pozycje spisu treści (model drzewa nie daje wiązania)

    PdfDocument {
        id: doc
        source: win.path ? "file://" + win.path : ""
        onPasswordRequired: { win.needPassword = true; passField.forceActiveFocus(); }
        onStatusChanged: {
            if (status === PdfDocument.Ready) {
                win.needPassword = false;
                if (win.restorePage > 0) {
                    const p = Math.min(win.restorePage, pageCount - 1);
                    Qt.callLater(() => { view.goTo(p); win.toast("Otwarto na stronie " + (p + 1) + ", na której skończono czytać"); });
                }
                win.restorePage = 0;
                Qt.callLater(() => {
                    win.outlineCount = bookmarks.rowCount();
                    if (win.outlineCount > 0 && win.width > 900) { win.sideMode = "outline"; win.sideOpen = true; }
                });
            } else if (status === PdfDocument.Error && !win.needPassword && win.path) {
                win.toast("Nie można otworzyć tego pliku jako dokumentu PDF");
            }
        }
    }
    PdfBookmarkModel { id: bookmarks; document: doc }

    function open(p) {
        if (!p) return;
        p = Pdf.toPath(p);
        if (path) Pdf.remember(path, view.currentPage);
        searchField.text = "";
        doc.password = "";
        needPassword = false;
        wrongPassword = false;
        sideOpen = false;
        outlineCount = 0;
        view.fitMode = "width";
        view.pageRotation = 0;
        restorePage = Pdf.lastPage(p);
        path = p;
        Pdf.remember(p, restorePage);
    }
    function closeDocument() {
        if (path) Pdf.remember(path, view.currentPage);
        path = "";
    }
    onClosing: if (path) Pdf.remember(path, view.currentPage)
    Timer { interval: 1500; running: win.ready; repeat: true; onTriggered: if (win.path) Pdf.remember(win.path, view.currentPage) }
    Component.onCompleted: { effectsTimer.restart(); if (startFile) open(startFile); }

    function toast(text) { toastBox.text = text; toastBox.shown = true; toastTimer.restart(); }
    Connections { target: Pdf; function onMessage(text) { win.toast(text); } }

    FileDialog {
        id: fileDialog
        title: "Otwórz dokument PDF"
        nameFilters: ["Dokumenty PDF (*.pdf *.PDF)", "Wszystkie pliki (*)"]
        onAccepted: win.open(String(selectedFile))
    }

    // ——— Menu ———
    function showMenu() {
        const p = moreBtn.mapToItem(frame, moreBtn.width, moreBtn.height + 6);
        menu.openAt(p.x - 250, p.y, [
            { label: "Otwórz…", icon: "folder", shortcut: "Ctrl+O", action: "open" },
            { label: "Drukuj…", icon: "printer", shortcut: "Ctrl+P", action: "print", enabled: win.ready },
            { label: "Pokaż w folderze", icon: "folder", action: "folder", enabled: !!win.path },
            { separator: true },
            { label: "Obróć w lewo", icon: "rotateLeft", shortcut: "Ctrl+Shift+R", action: "rotl", enabled: win.ready },
            { label: "Obróć w prawo", icon: "rotate", shortcut: "Ctrl+R", action: "rotr", enabled: win.ready },
            { label: win.visibility === Window.FullScreen ? "Zakończ pełny ekran" : "Pełny ekran", icon: "fullscreen", shortcut: "F11", action: "full" },
            { separator: true },
            { label: "Właściwości dokumentu", icon: "info", shortcut: "Ctrl+D", action: "props", enabled: win.ready },
            { label: "Zamknij dokument", icon: "close", action: "close", enabled: !!win.path }
        ]);
    }
    function showZoomMenu() {
        const p = zoomLabel.mapToItem(frame, 0, zoomLabel.height + 6);
        menu.openAt(p.x - 60, p.y, [
            { label: "Dopasuj do szerokości", icon: view.fitMode === "width" ? "check" : "", shortcut: "Ctrl+0", action: "fitw" },
            { label: "Cała strona", icon: view.fitMode === "page" ? "check" : "", action: "fitp" },
            { separator: true },
            { label: "50%", action: "z:0.5" }, { label: "100%", shortcut: "Ctrl+1", action: "z:1" },
            { label: "150%", action: "z:1.5" }, { label: "200%", action: "z:2" }, { label: "400%", action: "z:4" }
        ]);
    }
    function runMenu(a) {
        if (a === "open") fileDialog.open();
        else if (a === "print") Pdf.print(path, doc.password);
        else if (a === "folder") Pdf.showInFolder(path);
        else if (a === "rotl") view.pageRotation = (view.pageRotation + 270) % 360;
        else if (a === "rotr") view.pageRotation = (view.pageRotation + 90) % 360;
        else if (a === "full") { if (win.visibility === Window.FullScreen) win.showNormal(); else win.showFullScreen(); }
        else if (a === "props") propsOpen = true;
        else if (a === "close") closeDocument();
        else if (a === "fitw") { view.fitMode = "width"; view.applyFit(); }
        else if (a === "fitp") { view.fitMode = "page"; view.applyFit(); }
        else if (a.startsWith("z:")) { view.fitMode = ""; view.setScale(Number(a.slice(2))); }
    }
    function openSearch() {
        if (!ready) return;
        searchBox.shown = true;
        searchField.forceActiveFocus();
        searchField.selectAll();
    }
    function closeSearch() { searchBox.shown = false; searchField.text = ""; view.forceActiveFocus(); }

    // Do testów (ASTER_OPEN): find:tekst | thumbs | outline | menu | zoom | props | page:N
    function testOpen(what) {
        if (what.startsWith("find:")) { openSearch(); searchField.text = what.slice(5); }
        else if (what === "thumbs") { sideMode = "thumbs"; sideOpen = true; }
        else if (what === "outline") { sideMode = "outline"; sideOpen = true; }
        else if (what === "menu") showMenu();
        else if (what === "zoom") showZoomMenu();
        else if (what === "props") propsOpen = true;
        else if (what.startsWith("page:")) view.goTo(Number(what.slice(5)) - 1);
    }

    // ——— Skróty ———
    Shortcut { sequence: "Ctrl+O"; onActivated: fileDialog.open() }
    Shortcut { sequence: "Ctrl+F"; onActivated: win.openSearch() }
    Shortcut { sequence: "F3"; enabled: !!searchField.text; onActivated: view.search.currentResult++ }
    Shortcut { sequence: "Shift+F3"; enabled: !!searchField.text; onActivated: view.search.currentResult-- }
    Shortcut { sequence: "Ctrl+P"; enabled: win.ready; onActivated: Pdf.print(win.path, doc.password) }
    Shortcut { sequence: "Ctrl+D"; enabled: win.ready; onActivated: win.propsOpen = true }
    Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: view.zoomBy(1.2) }
    Shortcut { sequence: "Ctrl+-"; onActivated: view.zoomBy(1 / 1.2) }
    Shortcut { sequence: "Ctrl+0"; onActivated: { view.fitMode = "width"; view.applyFit(); } }
    Shortcut { sequence: "Ctrl+1"; onActivated: { view.fitMode = ""; view.setScale(1); } }
    Shortcut { sequence: "Ctrl+R"; enabled: win.ready; onActivated: view.pageRotation = (view.pageRotation + 90) % 360 }
    Shortcut { sequence: "Ctrl+Shift+R"; enabled: win.ready; onActivated: view.pageRotation = (view.pageRotation + 270) % 360 }
    Shortcut { sequence: "Ctrl+C"; enabled: view.selectedText !== ""; onActivated: if (view.copySelection()) win.toast("Skopiowano tekst") }
    Shortcut { sequence: "Ctrl+A"; enabled: win.ready && !searchField.activeFocus; onActivated: view.selectAll() }
    Shortcut { sequence: "F9"; enabled: win.ready; onActivated: win.sideOpen = !win.sideOpen }
    Shortcut { sequence: "F11"; onActivated: { if (win.visibility === Window.FullScreen) win.showNormal(); else win.showFullScreen(); } }
    Shortcut { sequences: ["PgDown", "Space"]; enabled: win.ready && !searchField.activeFocus && !pageField.activeFocus; onActivated: view.goTo(view.currentPage + 1) }
    Shortcut { sequences: ["PgUp", "Shift+Space"]; enabled: win.ready && !searchField.activeFocus && !pageField.activeFocus; onActivated: view.goTo(Math.max(0, view.currentPage - 1)) }
    Shortcut { sequence: "Ctrl+Home"; enabled: win.ready; onActivated: view.goTo(0) }
    Shortcut { sequence: "Ctrl+End"; enabled: win.ready; onActivated: view.goTo(doc.pageCount - 1) }
    Shortcut { sequence: "Ctrl+G"; enabled: win.ready; onActivated: { pageField.forceActiveFocus(); pageField.selectAll(); } }
    Shortcut { sequence: "Ctrl+W"; onActivated: win.close() }
    Shortcut { sequence: "Esc"; enabled: win.propsOpen || searchBox.shown || win.visibility === Window.FullScreen
        onActivated: { if (win.propsOpen) win.propsOpen = false; else if (searchBox.shown) win.closeSearch(); else win.showNormal(); } }

    // ——— Okno ———
    function updateEffects() {
        WindowEffects.setBlur(win, Qt.rect(m, m, frame.width, frame.height), r);
        WindowEffects.setInputRegion(win, Qt.rect(Math.max(0, m - 6), Math.max(0, m - 6), frame.width + (maxed ? 0 : 12), frame.height + (maxed ? 0 : 12)));
    }
    onWidthChanged: effectsTimer.restart()
    onHeightChanged: effectsTimer.restart()
    onMaxedChanged: effectsTimer.restart()
    Timer { id: effectsTimer; interval: 16; onTriggered: win.updateEffects() }

    WindowShadow { window: win; frame: frame; radius: win.r; visible: !win.maxed }
    ResizeHandles { window: win; frame: frame; margin: win.m }

    Rectangle {
        id: frame
        x: win.m; y: win.m
        width: win.width - 2 * win.m
        height: win.height - 2 * win.m
        radius: win.r
        color: Theme.windowGlass
        border.width: win.maxed ? 0 : 1
        border.color: Theme.edge
        WindowSheen { window: win; radius: win.r }
        clip: true

        // Plik upuszczony na okno — otwórz
        DropArea {
            anchors.fill: parent
            onEntered: (drag) => drag.accept(Qt.CopyAction)
            onDropped: (drop) => { if (drop.hasUrls) win.open(String(drop.urls[0])); }
        }

        // ——— Pasek u góry ———
        Item {
            id: top
            width: parent.width; height: 58
            z: 5
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
            TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }

            Row {
                id: leftGroup
                x: 14; anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                ToolBtn { visible: win.ready; anchors.verticalCenter: parent.verticalCenter; icon: "sidebar"; onClicked: win.sideOpen = !win.sideOpen }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: win.ready ? 0 : 8
                    Text {
                        width: Math.min(implicitWidth, top.width - rightGroup.width - winButtons.width - 140)
                        elide: Text.ElideMiddle
                        text: win.path ? win.docTitle : "Podgląd PDF"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    }
                    // „Strona [3] z 24” — numer da się wpisać
                    Row {
                        visible: win.ready
                        spacing: 4
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Strona"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(22, pageField.contentWidth + 10); height: 18; radius: 5
                            color: pageField.activeFocus ? Theme.fill : "transparent"
                            border.width: pageField.activeFocus ? 1 : 0; border.color: Theme.accent
                            TextInput {
                                id: pageField
                                anchors.fill: parent
                                horizontalAlignment: TextInput.AlignHCenter
                                verticalAlignment: TextInput.AlignVCenter
                                text: activeFocus ? text : String(view.currentPage + 1)
                                validator: IntValidator { bottom: 1; top: Math.max(1, doc.pageCount) }
                                color: Theme.text; selectionColor: Theme.accentSoft
                                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                                font.features: { "tnum": 1 }
                                onAccepted: { view.goTo(Number(text) - 1); view.forceActiveFocus(); }
                                Keys.onEscapePressed: view.forceActiveFocus()
                            }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "z " + doc.pageCount; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                    }
                }
            }

            Row {
                id: rightGroup
                anchors.right: winButtons.left; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                // Szukaj w dokumencie
                Rectangle {
                    id: searchBox
                    property bool shown: false
                    visible: shown
                    anchors.verticalCenter: parent.verticalCenter
                    width: 270; height: 32; radius: 10
                    color: Theme.fill
                    border.width: searchField.activeFocus ? 1.5 : 0
                    border.color: Theme.accent
                    Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 14; color: Theme.text2 }
                    TextInput {
                        id: searchField
                        x: 30; width: parent.width - 30 - searchTools.width - 6
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.text; selectionColor: Theme.accentSoft
                        font.family: Theme.font; font.pixelSize: 13
                        clip: true
                        onTextChanged: view.search.searchString = text
                        Keys.onReturnPressed: (e) => { if (e.modifiers & Qt.ShiftModifier) view.search.currentResult--; else view.search.currentResult++; }
                        Keys.onEnterPressed: view.search.currentResult++
                        Keys.onEscapePressed: win.closeSearch()
                        Text { visible: !searchField.text; text: "Szukaj w dokumencie"; color: Theme.text2; font: searchField.font }
                    }
                    Row {
                        id: searchTools
                        anchors.right: parent.right; anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !!searchField.text
                            rightPadding: 4
                            text: view.search.count === 0 ? "Brak" : (view.search.currentResult + 1) + " z " + view.search.count
                            color: view.search.count === 0 ? Theme.danger : Theme.text2
                            font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 }
                        }
                        SmallBtn { icon: "up"; onClicked: view.search.currentResult-- }
                        SmallBtn { icon: "chevronDown"; onClicked: view.search.currentResult++ }
                    }
                }
                ToolBtn { visible: win.ready && !searchBox.shown; anchors.verticalCenter: parent.verticalCenter; icon: "search"; onClicked: win.openSearch() }
                Item { width: 6; height: 1 }
                // Powiększenie: −  [120%]  +
                Rectangle {
                    visible: win.ready
                    anchors.verticalCenter: parent.verticalCenter
                    width: zoomRow.width + 4; height: 32; radius: 10
                    color: Theme.fill
                    Row {
                        id: zoomRow
                        x: 2; anchors.verticalCenter: parent.verticalCenter
                        SmallBtn { icon: "minus"; onClicked: view.zoomBy(1 / 1.2) }
                        HoverButton {
                            id: zoomLabel
                            width: 54; height: 28; radius: 7
                            onClicked: win.showZoomMenu()
                            Text {
                                anchors.centerIn: parent
                                text: view.percent + "%"
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium; font.features: { "tnum": 1 }
                            }
                        }
                        SmallBtn { icon: "plus"; onClicked: view.zoomBy(1.2) }
                    }
                }
                Item { width: 6; height: 1 }
                ToolBtn { visible: win.ready; anchors.verticalCenter: parent.verticalCenter; icon: "printer"; onClicked: Pdf.print(win.path, doc.password) }
                ToolBtn { id: moreBtn; anchors.verticalCenter: parent.verticalCenter; icon: "more"; onClicked: win.showMenu() }
            }
            WindowButtons {
                id: winButtons
                window: win
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ——— Pasek boczny: miniatury albo spis treści ———
        Item {
            id: side
            visible: win.sideOpen && win.ready
            y: top.height
            width: visible ? 210 : 0; height: parent.height - y

            Rectangle {
                x: 12; y: 2
                visible: win.outlineCount > 0
                width: parent.width - 24; height: 30; radius: 9
                color: Theme.fill
                Row {
                    x: 2; anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: [["thumbs", "Strony"], ["outline", "Spis treści"]]
                        delegate: Rectangle {
                            id: seg
                            required property var modelData
                            readonly property bool on: win.sideMode === modelData[0]
                            width: (side.width - 28) / 2; height: 26; radius: 7
                            color: on ? Theme.surface : "transparent"
                            Text { anchors.centerIn: parent; text: seg.modelData[1]; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: seg.on ? Font.Medium : Font.Normal }
                            MouseArea { anchors.fill: parent; onClicked: win.sideMode = seg.modelData[0] }
                        }
                    }
                }
            }

            ListView {
                id: thumbs
                visible: win.sideMode === "thumbs" || win.outlineCount === 0
                y: win.outlineCount > 0 ? 42 : 4
                width: parent.width; height: parent.height - y
                clip: true
                model: win.ready ? doc.pageCount : 0
                spacing: 6
                topMargin: 6; bottomMargin: 12
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: view.currentPage
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: Item {
                    id: th
                    required property int index
                    readonly property size pts: doc.pagePointSize(index)
                    readonly property bool current: index === view.currentPage
                    width: thumbs.width
                    height: thImg.height + 30
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: thImg.width + 8; height: thImg.height + 8; radius: 6
                        color: th.current ? Theme.accentSoft : (thArea.containsMouse ? Theme.hover : "transparent")
                        border.width: th.current ? 2 : 0; border.color: Theme.accent
                        Rectangle {
                            id: thPaper
                            anchors.centerIn: parent
                            width: thImg.width; height: thImg.height
                            color: "white"
                            border.width: 1; border.color: Theme.line
                        }
                    }
                    PdfPageImage {
                        id: thImg
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 4
                        document: doc
                        currentFrame: th.index
                        asynchronous: true
                        width: Math.min(130, 130 * th.pts.width / Math.max(1, th.pts.height) * 1.3)
                        height: width * th.pts.height / Math.max(1, th.pts.width)
                        sourceSize.width: width * 2
                        sourceSize.height: 0
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: thImg.height + 12
                        text: th.index + 1
                        color: th.current ? Theme.accentText : Theme.text2
                        font.family: Theme.font; font.pixelSize: 11; font.weight: th.current ? Font.DemiBold : Font.Normal
                    }
                    MouseArea { id: thArea; anchors.fill: parent; hoverEnabled: true; onClicked: view.goTo(th.index) }
                }
            }

            TreeView {
                id: outline
                visible: win.sideMode === "outline" && win.outlineCount > 0
                y: 42
                x: 6
                width: parent.width - 12; height: parent.height - y
                clip: true
                model: bookmarks
                boundsBehavior: Flickable.StopAtBounds
                delegate: Item {
                    id: bm
                    required property TreeView treeView
                    required property bool expanded
                    required property bool hasChildren
                    required property int depth
                    required property int row
                    required property var model
                    implicitWidth: outline.width
                    implicitHeight: Math.max(30, bmText.implicitHeight + 12)
                    readonly property bool current: bm.model.page === view.currentPage
                    Rectangle {
                        anchors.fill: parent; anchors.topMargin: 1; anchors.bottomMargin: 1
                        radius: 7
                        color: bmArea.containsMouse ? Theme.hover : "transparent"
                    }
                    Icon {
                        visible: bm.hasChildren
                        x: 4 + bm.depth * 12
                        y: 9
                        d: Icons.chevronRight; size: 11; stroke: 2.2; color: Theme.text2
                        rotation: bm.expanded ? 90 : 0
                        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: bm.treeView.toggleExpanded(bm.row) }
                    }
                    Text {
                        id: bmText
                        x: 20 + bm.depth * 12
                        width: parent.width - x - 30
                        anchors.verticalCenter: parent.verticalCenter
                        text: bm.model.title
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 12; font.weight: bm.depth === 0 ? Font.Medium : Font.Normal
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: bm.model.page + 1
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 11; font.features: { "tnum": 1 }
                    }
                    MouseArea {
                        id: bmArea
                        anchors.fill: parent; anchors.leftMargin: 16 + bm.depth * 12
                        hoverEnabled: true
                        onClicked: view.goTo(bm.model.page, bm.model.location.y)
                    }
                }
            }
        }

        // ——— Strony ———
        Item {
            id: content
            x: side.width
            y: top.height
            width: parent.width - x; height: parent.height - y
            visible: !!win.path
            Rectangle {
                anchors.fill: parent
                topLeftRadius: side.visible ? 14 : 0
                bottomRightRadius: win.r; bottomLeftRadius: side.visible ? 0 : win.r
                color: Theme.dark ? "#121317" : "#E6E8EC"
                clip: true
                PageView {
                    id: view
                    anchors.fill: parent
                    document: doc
                    visible: win.ready
                    focus: true
                    onLinkToUrl: (url) => Qt.openUrlExternally(url)
                }
            }

            // Hasło do zabezpieczonego dokumentu
            Rectangle {
                visible: win.needPassword
                anchors.centerIn: parent
                width: 360; height: passCol.implicitHeight + 44; radius: 20
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                Column {
                    id: passCol
                    x: 24; y: 22; width: parent.width - 48
                    spacing: 10
                    Rectangle {
                        width: 48; height: 48; radius: 14
                        gradient: Gradient {
                            GradientStop { position: 0; color: "#FF9AAE" }
                            GradientStop { position: 1; color: "#DC2550" }
                        }
                        Icon { anchors.centerIn: parent; d: Icons.lock; size: 22; stroke: 2; color: "white" }
                    }
                    Text { text: "Dokument jest chroniony hasłem"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold }
                    Text { width: parent.width; wrapMode: Text.Wrap; text: "Wpisz hasło do tego pliku — np. podane przez bank albo urząd."; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                    Rectangle {
                        width: parent.width; height: 38; radius: 19
                        color: Theme.fill
                        border.width: passField.activeFocus ? 1.5 : 0; border.color: Theme.accent
                        TextInput {
                            id: passField
                            anchors.fill: parent; anchors.leftMargin: 16; anchors.rightMargin: 16
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            passwordCharacter: "●"
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 14
                            onAccepted: { win.wrongPassword = true; doc.password = text; text = ""; }
                        }
                    }
                    Text { visible: win.wrongPassword; text: "Hasło jest nieprawidłowe"; color: Theme.danger; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                }
            }
        }

        // ——— Ekran startowy: ostatnie dokumenty ———
        Item {
            visible: !win.path
            y: top.height
            width: parent.width; height: parent.height - y
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(20, parent.height * 0.12)
                width: Math.min(560, parent.width - 48)
                spacing: 0
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 72; height: 72; radius: 22
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#FF9AAE" }
                        GradientStop { position: 1; color: "#DC2550" }
                    }
                    Icon { anchors.centerIn: parent; d: Icons.doc; size: 34; stroke: 1.8; color: "white" }
                }
                Item { width: 1; height: 16 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Podgląd PDF"; color: Theme.text; font.family: Theme.font; font.pixelSize: 24; font.weight: Font.Bold; font.letterSpacing: -0.4 }
                Item { width: 1; height: 6 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Otwórz dokument albo przeciągnij go na to okno"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                Item { width: 1; height: 18 }
                HoverButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: openRow.implicitWidth + 36; height: 38; radius: 19
                    baseColor: Theme.accent
                    color: hovered ? Qt.darker(Theme.accent, 1.1) : baseColor
                    onClicked: fileDialog.open()
                    Row {
                        id: openRow
                        anchors.centerIn: parent
                        spacing: 8
                        Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.folder; size: 15; stroke: 2; color: "white" }
                        Text { text: "Otwórz plik…"; color: "white"; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                    }
                }
                Item { width: 1; height: 34 }
                Text { visible: Pdf.recent.length > 0; text: "Ostatnio otwierane"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; bottomPadding: 8; leftPadding: 4 }
                Repeater {
                    model: Pdf.recent.slice(0, 7)
                    delegate: HoverButton {
                        id: rc
                        required property var modelData
                        width: parent.width; height: 54; radius: 12
                        onClicked: win.open(rc.modelData.path)
                        Rectangle {
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            width: 32; height: 38; radius: 5
                            color: "white"
                            border.width: 1; border.color: Theme.line
                            Rectangle { x: 5; y: 6; width: 22; height: 3; radius: 1.5; color: "#DC2550" }
                            Column {
                                x: 5; y: 13; spacing: 3
                                Repeater { model: 4; delegate: Rectangle { required property int index; width: index === 3 ? 12 : 22; height: 2; radius: 1; color: "#C9CDD5" } }
                            }
                        }
                        Column {
                            x: 54; width: parent.width - 64
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text { width: parent.width; elide: Text.ElideMiddle; text: rc.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                            Text {
                                width: parent.width; elide: Text.ElideMiddle
                                text: rc.modelData.when + (rc.modelData.page > 0 ? " · strona " + (rc.modelData.page + 1) : "") + " · " + rc.modelData.folder
                                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                            }
                        }
                    }
                }
            }
        }

        // ——— Właściwości dokumentu ———
        Item {
            anchors.fill: parent
            visible: win.propsOpen
            z: 150
            Rectangle { anchors.fill: parent; radius: win.r; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.25) }
            MouseArea { anchors.fill: parent; onClicked: win.propsOpen = false }
            Rectangle {
                id: props
                readonly property var info: win.propsOpen ? Pdf.fileInfo(win.path) : ({})
                readonly property size first: win.ready ? doc.pagePointSize(0) : Qt.size(0, 0)
                function paper() {
                    const w = first.width * 25.4 / 72, h = first.height * 25.4 / 72;
                    const a = Math.min(w, h), b = Math.max(w, h);
                    const name = Math.abs(a - 210) < 3 && Math.abs(b - 297) < 3 ? "A4" : Math.abs(a - 148) < 3 && Math.abs(b - 210) < 3 ? "A5"
                               : Math.abs(a - 216) < 3 && Math.abs(b - 279) < 3 ? "Letter" : "";
                    return (name ? name + " · " : "") + Math.round(w) + " × " + Math.round(h) + " mm";
                }
                function when(d) { return d && !isNaN(d) ? Pdf.date(d) : ""; }
                anchors.centerIn: parent
                width: 460; height: propsCol.implicitHeight + 44; radius: 22
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                MouseArea { anchors.fill: parent }
                Column {
                    id: propsCol
                    x: 24; y: 22; width: parent.width - 48
                    Text { width: parent.width; wrapMode: Text.Wrap; text: win.docTitle; color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold; bottomPadding: 14 }
                    Repeater {
                        model: [
                            ["Autor", doc.author], ["Temat", doc.subject], ["Słowa kluczowe", doc.keywords],
                            ["Strony", String(doc.pageCount)], ["Rozmiar strony", props.paper()],
                            ["Utworzono", props.when(doc.creationDate)], ["Zmieniono", props.when(doc.modificationDate)],
                            ["Utworzony w", doc.creator], ["Zapisany przez", doc.producer],
                            ["Rozmiar pliku", props.info.size], ["Plik", win.path]
                        ].filter(r => !!r[1])
                        delegate: Item {
                            id: pr
                            required property var modelData
                            width: propsCol.width; height: Math.max(30, prValue.implicitHeight + 12)
                            Rectangle { width: parent.width; height: 1; color: Theme.line }
                            Text { y: 8; text: pr.modelData[0]; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                            TextEdit {
                                id: prValue
                                x: 140; y: 8; width: parent.width - 140
                                readOnly: true; selectByMouse: true
                                wrapMode: TextEdit.WrapAnywhere
                                text: pr.modelData[1]
                                color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                                font.family: Theme.font; font.pixelSize: 13
                            }
                        }
                    }
                    Item { width: 1; height: 16 }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        HoverButton {
                            width: showText.implicitWidth + 30; height: 34; radius: 17
                            baseColor: Theme.fill
                            onClicked: Pdf.showInFolder(win.path)
                            Text { id: showText; anchors.centerIn: parent; text: "Pokaż w folderze"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                        }
                        HoverButton {
                            width: okText.implicitWidth + 30; height: 34; radius: 17
                            baseColor: Theme.accent
                            color: hovered ? Qt.darker(Theme.accent, 1.1) : baseColor
                            onClicked: win.propsOpen = false
                            Text { id: okText; anchors.centerIn: parent; text: "Zamknij"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                        }
                    }
                }
            }
        }

        // Komunikat na dole
        Rectangle {
            id: toastBox
            property bool shown: false
            property alias text: toastText.text
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - (shown ? height + 22 : 0)
            opacity: shown ? 1 : 0
            z: 300
            width: toastText.implicitWidth + 36; height: 40; radius: 20
            color: Theme.dark ? "#ECEEF3" : "#1E2027"
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Text { id: toastText; anchors.centerIn: parent; color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
            Timer { id: toastTimer; interval: 3500; onTriggered: toastBox.shown = false }
        }

        ContextMenu {
            id: menu
            onTriggered: (a) => win.runMenu(a)
        }
    }

    component SmallBtn: HoverButton {
        id: sb
        property string icon
        width: 28; height: 28; radius: 7
        Icon { anchors.centerIn: parent; d: Icons[sb.icon] || ""; size: 15; color: Theme.text }
    }
}
