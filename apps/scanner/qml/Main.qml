pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtCore
import Aster.Ui
import Aster.Scanner

// Skaner Aster (zamiast Skanlite), jak „Skanowanie” w Windows: po lewej kartka z podglądem i kadrem do przeciągnięcia,
// po prawej ustawienia (skaner, szyba/podajnik, kolor, rozdzielczość, format) i duży przycisk „Skanuj”.
// Zeskanowane strony zbierają się na dole — można je obrócić, ułożyć i zapisać razem jako jeden PDF.
Window {
    id: win
    width: 1060 + 2 * m
    height: 720 + 2 * m
    minimumWidth: 760 + 2 * m
    minimumHeight: 520 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: "Skaner"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 24

    Settings {
        id: prefs
        property string source
        property string mode
        property int dpi: 300
        property string format: "pdf"
    }

    // ——— Wybrane ustawienia (zapamiętane, o ile skaner je ma) ———
    function pick(list, wanted, fallback) {
        if (list.length === 0) return "";
        for (const x of list) if (x.value === wanted) return wanted;
        for (const x of list) if (fallback && x.value.toLowerCase() === fallback) return x.value;
        return list[0].value;
    }
    readonly property string source: pick(Scanner.sources, prefs.source, "flatbed")
    readonly property bool feeder: {
        for (const s of Scanner.sources) if (s.value === source) return s.feeder;
        return false;
    }
    readonly property string mode: pick(Scanner.modes, prefs.mode, "color")
    readonly property int dpi: {
        const list = Scanner.resolutions;
        if (list.length === 0) return prefs.dpi;
        let best = list[0];
        for (const v of list) if (Math.abs(v - prefs.dpi) < Math.abs(best - prefs.dpi)) best = v;
        return best;
    }
    readonly property bool ready: Scanner.device !== "" && !Scanner.busy
    readonly property var pages: Scanner.pages

    // Kadr w podglądzie (0..1); cała szyba, dopóki nie ma podglądu
    property rect crop: Qt.rect(0, 0, 1, 1)
    readonly property bool cropping: Scanner.preview !== "" && !feeder
    Connections {
        target: Scanner
        function onPreviewChanged() { win.crop = Qt.rect(0, 0, 1, 1); }
        function onError(message) { win.toast(message, ""); }
        function onSaved(path, count) {
            win.toast(count > 1 ? "Zapisano " + count + " pliki w folderze Skany" : "Zapisano „" + path.split("/").pop() + "”", path);
        }
    }

    function scan() {
        if (!ready) return;
        Scanner.scan(source, mode, dpi, cropping ? crop : Qt.rect(0, 0, 0, 0));
    }
    function save() { if (pages.length > 0 && !Scanner.busy) Scanner.save(prefs.format); }

    function toast(text, path) { toastBox.text = text; toastBox.path = path; toastBox.shown = true; toastTimer.restart(); }

    // ——— Menu ———
    function showMenu(kind, item, index) {
        const items = [];
        if (kind === "devices") {
            for (const d of Scanner.devices)
                items.push({ label: d.label, icon: d.name === Scanner.device ? "check" : "", action: "dev:" + d.name });
            if (items.length) items.push({ separator: true });
            items.push({ label: "Szukaj ponownie", icon: "reload", action: "refresh" });
        } else if (kind === "page") {
            menu.index = index;
            items.push({ label: "Obróć", icon: "rotate", action: "rotate" });
            if (index > 0) items.push({ label: "Przesuń w lewo", icon: "back", action: "left" });
            if (index < pages.length - 1) items.push({ label: "Przesuń w prawo", icon: "forward", action: "right" });
            items.push({ separator: true });
            items.push({ label: "Usuń stronę", icon: "trash", action: "remove", danger: true });
        }
        const p = item.mapToItem(frame, 0, kind === "page" ? 0 : item.height + 6);
        menu.openAt(kind === "page" ? p.x : p.x, kind === "page" ? p.y - (items.length * 34 + 4) : p.y, items);
    }
    function runMenu(a) {
        if (a.startsWith("dev:")) Scanner.select(a.substring(4));
        else if (a === "refresh") Scanner.refresh();
        else if (a === "rotate") Scanner.rotatePage(menu.index);
        else if (a === "left") Scanner.movePage(menu.index, menu.index - 1);
        else if (a === "right") Scanner.movePage(menu.index, menu.index + 1);
        else if (a === "remove") Scanner.removePage(menu.index);
    }

    // Do testów (ASTER_OPEN): preview | crop | scan | feeder | save | devices | page
    function testOpen(what) {
        if (what === "preview") Scanner.previewScan(source, mode);
        else if (what === "crop") crop = Qt.rect(0.12, 0.08, 0.6, 0.45);
        else if (what === "scan") scan();
        else if (what === "feeder") prefs.source = "Automatic Document Feeder";
        else if (what === "color") prefs.mode = "Color";
        else if (what === "save") saveWhenIdle.start();
        else if (what === "devices") showMenu("devices", deviceBtn, 0);
        else if (what === "page") showMenu("page", pageList.itemAtIndex(0), 0);
    }

    Timer { id: saveWhenIdle; interval: 300; repeat: true; onTriggered: if (!Scanner.busy) { stop(); win.save(); } }

    Shortcut { sequences: [StandardKey.Save]; onActivated: win.save() }

    // ——— Okno ———
    function updateEffects() {
        WindowEffects.setBlur(win, Qt.rect(m, m, frame.width, frame.height), r);
        WindowEffects.setInputRegion(win, Qt.rect(Math.max(0, m - 6), Math.max(0, m - 6), frame.width + (maxed ? 0 : 12), frame.height + (maxed ? 0 : 12)));
    }
    Component.onCompleted: effectsTimer.restart()
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

        // ——— Pasek tytułu ———
        Item {
            id: topBar
            width: parent.width; height: 64
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
            TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }
            Row {
                x: 24; anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                AppIcon { anchors.verticalCenter: parent.verticalCenter; desktopId: "org.aster.scanner"; size: 30 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Skaner"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4
                }
            }
            WindowButtons {
                window: win
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ——— Lewa część: kartka i strony ———
        Item {
            id: main
            x: 24; y: topBar.height
            width: parent.width - side.width - 48
            height: parent.height - y - 20

            // Brak skanera / szukanie
            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width - 40, 420)
                spacing: 12
                visible: Scanner.devices.length === 0
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 76; height: 76; radius: 22
                    color: Theme.fill
                    Icon {
                        anchors.centerIn: parent
                        d: Scanner.searching ? Icons.reload : Icons.scanner
                        size: 36; stroke: 1.6; color: Theme.text2
                        RotationAnimation on rotation { running: Scanner.searching; loops: Animation.Infinite; from: 0; to: 360; duration: 1100 }
                    }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Scanner.searching ? "Szukam skanerów…" : "Nie znaleziono skanera"
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: Scanner.searching ? "Skanery w sieci (Wi‑Fi) odpowiadają czasem kilka sekund."
                        : "Podłącz skaner kablem USB i go włącz. Skanery i drukarki wielofunkcyjne w tej samej sieci Wi‑Fi pojawią się same."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.25
                }
                Btn {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !Scanner.searching
                    text: "Szukaj ponownie"; icon: "reload"
                    onClicked: Scanner.refresh()
                }
            }

            // Kartka (proporcje obszaru skanera) z podglądem i kadrem
            Item {
                id: paperArea
                visible: Scanner.devices.length > 0
                width: parent.width
                height: parent.height - (win.pages.length > 0 ? strip.height + 16 : 0)
                readonly property real aspect: Scanner.area.width > 0 ? Scanner.area.width / Scanner.area.height : 0.72
                readonly property real pw: Math.min(width - 8, (height - 8) * aspect)

                Rectangle {
                    id: paper
                    anchors.centerIn: parent
                    width: paperArea.pw
                    height: width / paperArea.aspect
                    radius: 4
                    color: Theme.dark ? "#2A2D36" : "white"
                    border.width: 1
                    border.color: Theme.line

                    Image {
                        id: previewImg
                        anchors.fill: parent
                        anchors.margins: 1
                        source: Scanner.preview
                        fillMode: Image.Stretch
                        asynchronous: true
                        cache: false
                        sourceSize.width: 900
                    }

                    // Podpowiedź na pustej kartce
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 60
                        spacing: 10
                        visible: Scanner.preview === "" && !Scanner.busy
                        Icon { anchors.horizontalCenter: parent.horizontalCenter; d: win.feeder ? Icons.doc : Icons.scanner; size: 34; stroke: 1.5; color: Theme.text2 }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: win.feeder ? "Włóż kartki do podajnika i kliknij „Skanuj” — zeskanuję wszystkie po kolei."
                                             : "Połóż dokument na szybie skanera i kliknij „Podgląd”, żeby wybrać fragment — albo od razu „Skanuj”."
                            color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.25
                        }
                    }

                    // Kadr: przyciemnienie poza nim, ramka, uchwyty w rogach
                    Item {
                        id: cropLayer
                        anchors.fill: parent
                        visible: win.cropping
                        readonly property real cx: win.crop.x * width
                        readonly property real cy: win.crop.y * height
                        readonly property real cw: win.crop.width * width
                        readonly property real ch: win.crop.height * height
                        readonly property color shade: Qt.rgba(0, 0, 0, 0.45)
                        Rectangle { x: 0; y: 0; width: parent.width; height: cropLayer.cy; color: cropLayer.shade }
                        Rectangle { x: 0; y: cropLayer.cy + cropLayer.ch; width: parent.width; height: parent.height - y; color: cropLayer.shade }
                        Rectangle { x: 0; y: cropLayer.cy; width: cropLayer.cx; height: cropLayer.ch; color: cropLayer.shade }
                        Rectangle { x: cropLayer.cx + cropLayer.cw; y: cropLayer.cy; width: parent.width - x; height: cropLayer.ch; color: cropLayer.shade }
                        Rectangle {
                            x: cropLayer.cx; y: cropLayer.cy; width: cropLayer.cw; height: cropLayer.ch
                            color: "transparent"
                            border.width: 2; border.color: Theme.accent
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                property point start
                                property rect startCrop
                                onPressed: (e) => { start = mapToItem(cropLayer, e.x, e.y); startCrop = win.crop; }
                                onPositionChanged: (e) => {
                                    const p = mapToItem(cropLayer, e.x, e.y);
                                    const dx = (p.x - start.x) / cropLayer.width, dy = (p.y - start.y) / cropLayer.height;
                                    win.crop = Qt.rect(Math.max(0, Math.min(1 - startCrop.width, startCrop.x + dx)),
                                                       Math.max(0, Math.min(1 - startCrop.height, startCrop.y + dy)),
                                                       startCrop.width, startCrop.height);
                                }
                            }
                        }
                        Repeater {
                            model: ["tl", "tr", "bl", "br"]
                            delegate: Rectangle {
                                id: handle
                                required property string modelData
                                readonly property bool atLeft: modelData[1] === "l"
                                readonly property bool atTop: modelData[0] === "t"
                                x: (atLeft ? cropLayer.cx : cropLayer.cx + cropLayer.cw) - width / 2
                                y: (atTop ? cropLayer.cy : cropLayer.cy + cropLayer.ch) - height / 2
                                width: 16; height: 16; radius: 8
                                color: "white"
                                border.width: 2; border.color: Theme.accent
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -8
                                    cursorShape: handle.atLeft === handle.atTop ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                                    onPositionChanged: (e) => {
                                        const p = mapToItem(cropLayer, e.x, e.y);
                                        const nx = Math.max(0, Math.min(1, p.x / cropLayer.width));
                                        const ny = Math.max(0, Math.min(1, p.y / cropLayer.height));
                                        const c = win.crop, min = 0.04;
                                        let x0 = c.x, y0 = c.y, x1 = c.x + c.width, y1 = c.y + c.height;
                                        if (handle.atLeft) x0 = Math.min(nx, x1 - min); else x1 = Math.max(nx, x0 + min);
                                        if (handle.atTop) y0 = Math.min(ny, y1 - min); else y1 = Math.max(ny, y0 + min);
                                        win.crop = Qt.rect(x0, y0, x1 - x0, y1 - y0);
                                    }
                                }
                            }
                        }
                    }

                    // Postęp
                    Rectangle {
                        anchors.fill: parent
                        visible: Scanner.busy && Scanner.task !== "Łączenie ze skanerem…"
                        color: Qt.rgba(Theme.dark ? 0 : 1, Theme.dark ? 0 : 1, Theme.dark ? 0 : 1, 0.72)
                        Column {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 60, 260)
                            spacing: 12
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: Scanner.task
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                            }
                            Rectangle {
                                width: parent.width; height: 6; radius: 3
                                color: Theme.fill
                                Rectangle {
                                    width: parent.width * Scanner.progress; height: parent.height; radius: 3
                                    color: Theme.accent
                                    Behavior on width { NumberAnimation { duration: 150 } }
                                }
                            }
                            Btn {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: Scanner.task !== "Zapisywanie…"
                                text: "Anuluj"
                                onClicked: Scanner.cancel()
                            }
                        }
                    }
                }
            }

            // ——— Zeskanowane strony ———
            Rectangle {
                id: strip
                visible: win.pages.length > 0
                anchors.bottom: parent.bottom
                width: parent.width; height: 168
                radius: 16
                color: Theme.fill
                Text {
                    x: 16; y: 12
                    text: win.pages.length === 1 ? "1 strona" : win.pages.length + (win.pages.length % 10 >= 2 && win.pages.length % 10 <= 4 && (win.pages.length % 100 < 12 || win.pages.length % 100 > 14) ? " strony" : " stron")
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 12; y: 6
                    spacing: 8
                    Btn { text: "Wyczyść"; enabled: !Scanner.busy; onClicked: Scanner.clear() }
                    Btn {
                        primary: true
                        enabled: !Scanner.busy
                        icon: "download"
                        text: prefs.format === "pdf" ? "Zapisz PDF" : win.pages.length > 1 ? "Zapisz " + win.pages.length + " pliki " + prefs.format.toUpperCase() : "Zapisz " + prefs.format.toUpperCase()
                        onClicked: win.save()
                    }
                }
                ListView {
                    id: pageList
                    x: 16; y: 44
                    width: parent.width - 32; height: 112
                    orientation: ListView.Horizontal
                    spacing: 12
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: win.pages
                    delegate: Item {
                        id: pageItem
                        required property var modelData
                        required property int index
                        height: 112
                        width: Math.max(60, Math.round(100 * modelData.width / Math.max(1, modelData.height)))
                        Rectangle {
                            width: parent.width; height: 100
                            color: "white"
                            border.width: 1; border.color: Theme.line
                            Image {
                                anchors.fill: parent; anchors.margins: 1
                                source: pageItem.modelData.url
                                sourceSize.height: 200
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                            Rectangle {
                                anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 5
                                width: 20; height: 20; radius: 10
                                color: Qt.rgba(0, 0, 0, 0.6)
                                Text { anchors.centerIn: parent; text: pageItem.index + 1; color: "white"; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }
                            }
                            Rectangle {
                                anchors.fill: parent
                                color: Qt.rgba(0, 0, 0, pageArea.containsMouse ? 0.08 : 0)
                            }
                        }
                        MouseArea {
                            id: pageArea
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.showMenu("page", pageItem, pageItem.index)
                        }
                    }
                }
            }
        }

        // ——— Prawa część: ustawienia ———
        Rectangle {
            id: side
            anchors.right: parent.right; anchors.rightMargin: 16
            y: topBar.height
            width: 300; height: parent.height - y - 16
            radius: 18
            color: Theme.pane
            border.width: 1; border.color: Theme.line
            enabled: Scanner.devices.length > 0

            Column {
                x: 20; y: 18
                width: parent.width - 40
                spacing: 18

                Group {
                    title: "Skaner"
                    HoverButton {
                        id: deviceBtn
                        width: parent.width; height: 40; radius: 12
                        baseColor: Theme.fill
                        color: hovered ? Theme.hover : baseColor
                        enabled: !Scanner.busy
                        onClicked: win.showMenu("devices", deviceBtn, 0)
                        Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; d: Icons.scanner; size: 17; stroke: 1.8; color: Theme.text2 }
                        Text {
                            x: 38; width: parent.width - 70
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: {
                                for (const d of Scanner.devices) if (d.name === Scanner.device) return d.label;
                                return Scanner.searching ? "Szukam…" : "Wybierz skaner";
                            }
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                        }
                        Icon { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; d: Icons.chevronDown; size: 15; stroke: 2; color: Theme.text2 }
                    }
                }

                Group {
                    title: "Skąd"
                    visible: Scanner.sources.length > 1
                    Chips {
                        model: Scanner.sources
                        current: win.source
                        onPicked: (v) => prefs.source = v
                    }
                }

                Group {
                    title: "Kolor"
                    visible: Scanner.modes.length > 1
                    Chips {
                        model: Scanner.modes
                        current: win.mode
                        onPicked: (v) => prefs.mode = v
                    }
                }

                Group {
                    title: "Rozdzielczość"
                    visible: Scanner.resolutions.length > 0
                    Chips {
                        model: Scanner.resolutions.map(v => ({ value: String(v), label: String(v) }))
                        current: String(win.dpi)
                        onPicked: (v) => prefs.dpi = Number(v)
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: win.dpi <= 150 ? "Wystarczy do tekstu na ekranie i wysyłki mailem — małe pliki."
                            : win.dpi <= 300 ? "Dokumenty do druku i archiwum — dobry wybór na co dzień."
                            : "Zdjęcia i drobne szczegóły — duże pliki, skanowanie trwa dłużej."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
                    }
                }

                Group {
                    title: "Zapisz jako"
                    Chips {
                        model: [{ value: "pdf", label: "PDF" }, { value: "jpg", label: "JPG" }, { value: "png", label: "PNG" }]
                        current: prefs.format
                        onPicked: (v) => prefs.format = v
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: prefs.format === "pdf" ? "Wszystkie strony w jednym pliku, w folderze Dokumenty/Skany."
                                                     : "Każda strona osobno, w folderze Obrazy/Skany."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
                    }
                }
            }

            Column {
                anchors.bottom: parent.bottom; anchors.bottomMargin: 20
                x: 20; width: parent.width - 40
                spacing: 10
                Btn {
                    width: parent.width
                    visible: !win.feeder
                    enabled: win.ready
                    text: "Podgląd"; icon: "eye"
                    onClicked: Scanner.previewScan(win.source, win.mode)
                }
                Btn {
                    width: parent.width; height: 44
                    primary: true
                    enabled: win.ready
                    text: win.feeder ? "Skanuj wszystkie" : win.cropping && (win.crop.width < 0.999 || win.crop.height < 0.999) ? "Skanuj zaznaczenie" : "Skanuj"
                    icon: "scanner"
                    onClicked: win.scan()
                }
            }
        }

        // Komunikat (z „Otwórz” i „Pokaż w folderze” po zapisie)
        Rectangle {
            id: toastBox
            property bool shown: false
            property string path
            property alias text: toastText.text
            anchors.horizontalCenter: parent.horizontalCenter
            y: shown ? 70 : -height - 10
            opacity: shown ? 1 : 0
            z: 300
            width: Math.min(parent.width - 60, toastRow.implicitWidth + 36); height: 40; radius: 20
            color: Theme.dark ? "#ECEEF3" : "#1E2027"
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Row {
                id: toastRow
                anchors.centerIn: parent
                spacing: 14
                Text {
                    id: toastText
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, toastBox.parent.width - 300)
                    elide: Text.ElideMiddle
                    color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                }
                Repeater {
                    model: toastBox.path ? [{ t: "Otwórz", a: "open" }, { t: "Pokaż w folderze", a: "show" }] : []
                    delegate: Text {
                        id: toastLink
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.t
                        color: Theme.dark ? Qt.darker(Theme.accent, 1.2) : Qt.lighter(Theme.accent, 1.5)
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -8
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                toastBox.shown = false;
                                if (toastLink.modelData.a === "open") Scanner.open(toastBox.path); else Scanner.showInFolder(toastBox.path);
                            }
                        }
                    }
                }
            }
            Timer { id: toastTimer; interval: 7000; onTriggered: toastBox.shown = false }
        }

        ContextMenu {
            id: menu
            property int index
            onTriggered: (a) => win.runMenu(a)
        }
    }

    // ——— Elementy ———
    component Group: Column {
        id: group
        property string title
        width: parent ? parent.width : 0
        spacing: 8
        Text {
            text: group.title
            color: Theme.text2
            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
        }
    }

    // Wybór jednej z kilku wartości: [{ value, label }]
    component Chips: Flow {
        id: chips
        property var model: []
        property string current
        signal picked(string value)
        width: parent ? parent.width : 0
        spacing: 6
        Repeater {
            model: chips.model
            delegate: HoverButton {
                id: chip
                required property var modelData
                readonly property bool on: chip.modelData.value === chips.current
                width: chipText.implicitWidth + 26; height: 32; radius: 16
                baseColor: on ? Theme.accent : Theme.fill
                color: on ? baseColor : hovered ? Theme.hover : baseColor
                enabled: !Scanner.busy
                onClicked: chips.picked(chip.modelData.value)
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: chip.modelData.label
                    color: chip.on ? "white" : Theme.text
                    font.family: Theme.font; font.pixelSize: 13; font.weight: chip.on ? Font.DemiBold : Font.Normal
                }
            }
        }
    }

    component Btn: HoverButton {
        id: btn
        property string text
        property string icon
        property bool primary: false
        width: btnRow.implicitWidth + 30; height: 36; radius: height / 2
        baseColor: primary ? Theme.accent : Theme.fill
        color: !enabled ? baseColor : primary ? (hovered ? Qt.lighter(Theme.accent, 1.12) : baseColor) : (hovered ? Theme.hover : baseColor)
        opacity: enabled ? 1 : 0.45
        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 7
            Icon { visible: btn.icon !== ""; anchors.verticalCenter: parent.verticalCenter; d: Icons[btn.icon] || ""; size: 16; stroke: 2; color: btn.primary ? "white" : Theme.text }
            Text { anchors.verticalCenter: parent.verticalCenter; text: btn.text; color: btn.primary ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
        }
    }
}
