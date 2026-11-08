pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Dialogs
import QtMultimedia
import QtQuick.Effects
import QtCore
import Aster.Ui
import Aster.Video

// Wideo Aster (zamiast Dragon Playera / Haruny): ekran startowy z ostatnio oglądanymi (wznawianie
// tam, gdzie przerwano) i filmami z folderu Wideo, a po otwarciu — odtwarzacz na całe okno.
Window {
    id: win
    width: 1080 + 2 * m
    height: 660 + 2 * m
    minimumWidth: 520 + 2 * m
    minimumHeight: 340 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: watching ? player.title + " — Wideo" : "Wideo"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 24
    property bool watching: false
    // Maski (zaokrąglone rogi obrazu) wymagają shaderów — nie ma ich w renderowaniu programowym
    readonly property bool shaders: GraphicsInfo.api !== GraphicsInfo.Software && GraphicsInfo.api !== GraphicsInfo.Unknown

    Settings {
        id: prefs
        property alias volume: player.volume
        property alias muted: player.muted
        property alias captions: player.captions
    }

    function open(pathOrUrl) {
        const p = Video.toPath(String(pathOrUrl));
        if (!p) return;
        watching = true;
        player.open(p);
        player.forceActiveFocus();
    }
    function home() {
        player.stop();
        watching = false;
        if (visibility === Window.FullScreen) showNormal();
        library = Video.library();
    }
    property var library: []
    Component.onCompleted: {
        effectsTimer.restart();
        if (Video.startFile) open(Video.startFile);
        else library = Video.library();
    }
    onClosing: player.saveProgress()

    // Okno dopasowuje się do proporcji filmu (o ile nie jest zmaksymalizowane)
    function fitTo(s) {
        if (maxed) return;
        const availW = Screen.desktopAvailableWidth * 0.8, availH = Screen.desktopAvailableHeight * 0.8;
        const k = Math.min(1, availW / s.width, availH / s.height);
        let w = Math.max(520, Math.round(s.width * k)), h = Math.max(300, Math.round(w * s.height / s.width));
        if (h > availH) { h = Math.round(availH); w = Math.round(h * s.width / s.height); }
        const cx = x + width / 2, cy = y + height / 2;
        width = w + 2 * m; height = h + 2 * m;
        x = Math.max(Screen.virtualX, cx - width / 2);
        y = Math.max(Screen.virtualY, cy - height / 2);
    }

    // ——— Menu (prędkość, napisy, ścieżka dźwięku, prawy przycisk) ———
    function menuHeight(items) {
        let h = 12;
        for (const i of items) h += i.separator ? 9 : 34;
        return h;
    }
    function showMenu(kind, px, py) {
        const mp = player.media;
        const items = [];
        if (kind === "speed") {
            for (const r of player.rates)
                items.push({ label: r === 1 ? "Normalna" : String(r).replace(".", ",") + "×", icon: player.rate === r ? "check" : "", action: "rate:" + r });
        } else if (kind === "audio") {
            for (let i = 0; i < mp.audioTracks.length; i++) {
                const lang = Video.language(mp.audioTracks[i].value(MediaMetaData.Language));
                items.push({ label: lang || "Ścieżka " + (i + 1), icon: mp.activeAudioTrack === i ? "check" : "", action: "audio:" + i });
            }
        } else if (kind === "captions") {
            const on = player.captions;
            items.push({ label: "Wyłączone", icon: !on || (player.cues.length === 0 && mp.activeSubtitleTrack < 0) ? "check" : "", action: "sub:off" });
            for (const f of player.subFiles)
                items.push({ label: f.split("/").pop(), icon: on && player.subFile === f ? "check" : "", action: "subfile:" + f });
            for (let i = 0; i < mp.subtitleTracks.length; i++) {
                const lang = Video.language(mp.subtitleTracks[i].value(MediaMetaData.Language));
                items.push({ label: (lang || "Napisy " + (i + 1)) + " (w filmie)", icon: on && mp.activeSubtitleTrack === i ? "check" : "", action: "subtrack:" + i });
            }
            items.push({ separator: true });
            items.push({ label: "Wczytaj z pliku…", icon: "folder", action: "sub:load" });
        } else {
            items.push({ label: player.playing ? "Wstrzymaj" : "Odtwórz", icon: player.playing ? "pause" : "play", shortcut: "Spacja", action: "toggle" });
            if (player.hasNext) items.push({ label: "Następny film", icon: "next", shortcut: "Shift+N", action: "next" });
            items.push({ separator: true });
            items.push({ label: "Otwórz plik…", icon: "folder", shortcut: "Ctrl+O", action: "open" });
            items.push({ label: "Wczytaj napisy…", icon: "captions", action: "sub:load" });
            items.push({ label: "Pokaż w folderze", icon: "folder", action: "folder" });
            items.push({ separator: true });
            items.push({ label: player.fullscreen ? "Zakończ pełny ekran" : "Pełny ekran", icon: "fullscreen", shortcut: "F", action: "fullscreen" });
            items.push({ label: "Lista filmów", icon: "grid", action: "home" });
        }
        const pt = player.mapToItem(frame, px, py);
        if (kind === "context") menu.openAt(pt.x, pt.y, items);
        else menu.openAt(pt.x - 100, pt.y - menuHeight(items) - 10, items);
    }
    function runMenu(a) {
        const mp = player.media;
        if (a.startsWith("rate:")) player.rate = Number(a.substring(5));
        else if (a.startsWith("audio:")) mp.activeAudioTrack = Number(a.substring(6));
        else if (a.startsWith("subfile:")) player.loadSubtitles(a.substring(8));
        else if (a.startsWith("subtrack:")) player.embeddedSubtitles(Number(a.substring(9)));
        else if (a === "sub:off") player.captionsOff();
        else if (a === "sub:load") subsDialog.open();
        else if (a === "toggle") player.toggle();
        else if (a === "next") player.next();
        else if (a === "open") fileDialog.open();
        else if (a === "folder") Video.showInFolder(player.path);
        else if (a === "fullscreen") { if (visibility === Window.FullScreen) showNormal(); else showFullScreen(); }
        else if (a === "home") home();
        else if (a === "forget") { Video.forget(menu.path); }
        else if (a === "play") open(menu.path);
        else if (a === "showfile") Video.showInFolder(menu.path);
        if (watching) Qt.callLater(() => player.forceActiveFocus());
    }
    function cardMenu(path, inRecent, item, x, y) {
        menu.path = path;
        const items = [{ label: "Odtwórz", icon: "play", action: "play" },
                       { label: "Pokaż w folderze", icon: "folder", action: "showfile" }];
        if (inRecent) items.push({ separator: true }, { label: "Usuń z ostatnio oglądanych", icon: "close", action: "forget" });
        const p = item.mapToItem(frame, x, y);
        menu.openAt(p.x, p.y, items);
    }

    // ——— Komunikat ———
    function toast(text, action) { toastBox.text = text; toastBox.action = action; toastBox.shown = true; toastTimer.restart(); }

    FileDialog {
        id: fileDialog
        title: "Otwórz film"
        currentFolder: "file://" + Video.videosDir()
        nameFilters: ["Filmy (*.mp4 *.mkv *.webm *.avi *.mov *.m4v *.wmv *.mpg *.mpeg *.ts *.ogv *.flv *.3gp)", "Wszystkie pliki (*)"]
        onAccepted: win.open(String(selectedFile))
    }
    FileDialog {
        id: subsDialog
        title: "Wczytaj napisy"
        currentFolder: player.path ? "file://" + player.path.substring(0, player.path.lastIndexOf("/")) : ""
        nameFilters: ["Napisy (*.srt *.vtt *.txt *.sub)", "Wszystkie pliki (*)"]
        onAccepted: player.loadSubtitles(Video.toPath(String(selectedFile)))
    }

    // Do testów (ASTER_OPEN): play:ścieżka | captions | speed | context | end | home-menu
    function testOpen(what) {
        if (what.startsWith("play:")) open(what.substring(5));
        else if (what === "captions" || what === "speed" || what === "context")
            showMenu(what, what === "context" ? 300 : player.width - 160, what === "context" ? 200 : player.height - 50);
        else if (what === "pause") { player.media.pause(); player.chromeShown = true; }
        else if (what === "end") player.seekTo(player.media.duration - 300);
        else if (what === "home-menu") cardMenu(library[0].path, false, frame, 300, 300);
    }

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
        color: win.watching ? "black" : Theme.windowGlass
        border.width: win.maxed || win.watching ? 0 : 1
        border.color: Theme.edge
        WindowSheen { window: win; radius: win.r; visible: !win.watching }

        // Zaokrąglone rogi także dla obrazu filmu (maska tylko w oknie — zmaksymalizowane nie ma rogów)
        layer.enabled: win.watching && win.r > 0 && win.shaders
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: cornerMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
        Rectangle {
            id: cornerMask
            width: frame.width; height: frame.height; radius: win.r
            visible: false
            layer.enabled: true
        }

        // ——— Ekran startowy ———
        GlassPane {
            id: homePane
            visible: !win.watching
            anchors.fill: parent
            leftLine: false
            topLeftRadius: win.r; topRightRadius: win.r; bottomLeftRadius: win.r; bottomRightRadius: win.r

            Item {
                id: topBar
                width: parent.width; height: 68
                z: 5
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }
                Row {
                    x: 26; anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    AppIcon { anchors.verticalCenter: parent.verticalCenter; desktopId: "org.aster.video"; size: 30 }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Wideo"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4
                    }
                }
                HoverButton {
                    id: openBtn
                    anchors.right: winButtons.left; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: openRow.implicitWidth + 28; height: 34; radius: 17
                    baseColor: Theme.accent
                    color: hovered ? Qt.lighter(Theme.accent, 1.12) : baseColor
                    onClicked: fileDialog.open()
                    Row {
                        id: openRow
                        anchors.centerIn: parent
                        spacing: 7
                        Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.folder; size: 15; stroke: 2; color: "white" }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Otwórz plik…"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                    }
                }
                WindowButtons {
                    id: winButtons
                    window: win
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Flickable {
                id: homeFlick
                y: topBar.height
                width: parent.width; height: parent.height - y
                contentHeight: homeCol.implicitHeight + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                readonly property int cardW: {
                    const avail = width - 52;
                    const cols = Math.max(2, Math.floor((avail + 16) / 236));
                    return Math.floor((avail - (cols - 1) * 16) / cols);
                }

                Column {
                    id: homeCol
                    x: 26
                    width: parent.width - 52
                    spacing: 14

                    SectionTitle { text: "Ostatnio oglądane"; visible: Video.recent.length > 0 }
                    ListView {
                        visible: Video.recent.length > 0
                        width: parent.width; height: homeFlick.cardW * 9 / 16 + 64
                        orientation: ListView.Horizontal
                        spacing: 16
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: Video.recent
                        delegate: VideoCard {
                            required property var modelData
                            width: homeFlick.cardW
                            path: modelData.path
                            name: modelData.name
                            thumb: modelData.thumb
                            progress: modelData.duration > 0 ? modelData.position / modelData.duration : 0
                            detail: modelData.position > 0 && modelData.duration > 0
                                    ? "Zostało " + Video.time(modelData.duration - modelData.position)
                                    : "Obejrzano " + Video.when(modelData.time)
                            inRecent: true
                        }
                    }
                    Item { width: 1; height: 6; visible: Video.recent.length > 0 }

                    SectionTitle { text: "Filmy"; visible: win.library.length > 0 }
                    Flow {
                        width: parent.width
                        spacing: 16
                        Repeater {
                            model: win.library.slice(0, 300)
                            delegate: VideoCard {
                                required property var modelData
                                width: homeFlick.cardW
                                path: modelData.path
                                name: modelData.name
                                thumb: modelData.thumb
                                detail: Video.when(modelData.modified)
                            }
                        }
                    }

                    // Pusto
                    Column {
                        visible: win.library.length === 0 && Video.recent.length === 0
                        width: parent.width
                        topPadding: Math.max(40, (homeFlick.height - 300) / 2)
                        spacing: 12
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 76; height: 76; radius: 22
                            color: Theme.fill
                            Icon { anchors.centerIn: parent; d: Icons.film; size: 36; stroke: 1.6; color: Theme.text2 }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Brak filmów"
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(parent.width, 380)
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: "Filmy z folderów Wideo i Pobrane pojawią się tutaj. Możesz też otworzyć plik albo upuścić go na to okno."
                            color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.25
                        }
                    }
                }
            }
        }

        // ——— Odtwarzacz ———
        Player {
            id: player
            anchors.fill: parent
            visible: win.watching
            window: win
            focus: win.watching
            onBackRequested: win.home()
            onVideoSize: (s) => win.fitTo(s)
            onToast: (text, action) => win.toast(text, action)
            onMenuRequested: (kind, x, y) => win.showMenu(kind, x, y)
            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_O && (e.modifiers & Qt.ControlModifier)) { fileDialog.open(); e.accepted = true; }
            }
        }

        // Upuszczony plik
        DropArea {
            anchors.fill: parent
            onDropped: (drop) => {
                const subs = drop.urls.map(u => String(u)).filter(u => /\.(srt|vtt|sub|txt)$/i.test(u));
                if (win.watching && subs.length > 0) { player.loadSubtitles(Video.toPath(subs[0])); return; }
                if (drop.urls.length > 0) win.open(drop.urls[0]);
            }
        }

        // Komunikat na dole (z „Od początku” po wznowieniu)
        Rectangle {
            id: toastBox
            property bool shown: false
            property string action
            property alias text: toastText.text
            anchors.horizontalCenter: parent.horizontalCenter
            y: shown ? 76 : -height - 10
            opacity: shown ? 1 : 0
            z: 300
            width: toastRow.implicitWidth + 36; height: 40; radius: 20
            color: Theme.dark || win.watching ? "#ECEEF3" : "#1E2027"
            Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: 100 } }
            Row {
                id: toastRow
                anchors.centerIn: parent
                spacing: 14
                Text { id: toastText; anchors.verticalCenter: parent.verticalCenter; color: Theme.dark || win.watching ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                Text {
                    visible: toastBox.action === "restart" || toastBox.action === "loadsubs"
                    anchors.verticalCenter: parent.verticalCenter
                    text: toastBox.action === "restart" ? "Od początku" : "Wczytaj z pliku…"
                    color: Qt.darker(Theme.accent, 1.2)
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            toastBox.shown = false;
                            if (toastBox.action === "restart") player.seekTo(0); else subsDialog.open();
                        }
                    }
                }
            }
            Timer { id: toastTimer; interval: 5000; onTriggered: toastBox.shown = false }
        }

        ContextMenu {
            id: menu
            property string path
            onTriggered: (a) => win.runMenu(a)
        }
    }

    component SectionTitle: Text {
        topPadding: 4
        color: Theme.text
        font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
    }

    // Karta filmu: miniatura 16:9 (z paskiem obejrzanej części), nazwa i opis
    component VideoCard: Item {
        id: card
        property string path
        property string name
        property string thumb
        property string detail
        property real progress: 0
        property bool inRecent: false
        height: width * 9 / 16 + 50

        Rectangle {
            id: shot
            width: parent.width; height: width * 9 / 16
            radius: 12
            color: Theme.dark ? "#1B1D24" : "#E4E7EE"
            // Zaokrąglone rogi miniatury (warstwa rysowana raz, nie co klatkę)
            layer.enabled: win.shaders
            layer.effect: MultiEffect { maskEnabled: true; maskSource: shotMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
            scale: cardArea.pressed ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: 100 } }
            Icon { anchors.centerIn: parent; d: Icons.film; size: 30; stroke: 1.5; color: Theme.text2; visible: img.status !== Image.Ready }
            Image {
                id: img
                anchors.fill: parent
                source: card.thumb
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: 480
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, cardArea.containsMouse ? 0.25 : 0)
                Behavior on color { ColorAnimation { duration: 120 } }
                Rectangle {
                    anchors.centerIn: parent
                    width: 48; height: 48; radius: 24
                    color: Qt.rgba(0, 0, 0, 0.5)
                    opacity: cardArea.containsMouse ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    Icon { anchors.centerIn: parent; anchors.horizontalCenterOffset: 2; d: Icons.play; size: 22; color: "white"; fill: "white" }
                }
            }
            Rectangle {
                visible: card.progress > 0.01
                anchors.bottom: parent.bottom
                width: parent.width; height: 4
                color: Qt.rgba(1, 1, 1, 0.35)
                Rectangle { width: parent.width * card.progress; height: parent.height; color: Theme.accent }
            }
        }
        Rectangle { id: shotMask; width: shot.width; height: shot.height; radius: 12; visible: false; layer.enabled: true }
        Text {
            y: shot.height + 9
            width: parent.width
            text: card.name
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
        }
        Text {
            y: shot.height + 28
            width: parent.width
            text: card.detail
            elide: Text.ElideRight
            color: Theme.text2
            font.family: Theme.font; font.pixelSize: 12
        }
        MouseArea {
            id: cardArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (e) => {
                if (e.button === Qt.RightButton) win.cardMenu(card.path, card.inRecent, card, e.x, e.y);
                else win.open(card.path);
            }
        }
    }
}
