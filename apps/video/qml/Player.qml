pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtMultimedia
import Aster.Ui
import Aster.Video

// Odtwarzanie: film na całe okno, nad nim (chowane po chwili bez ruchu myszy) tytuł u góry
// i sterowanie na dole — pasek postępu, odtwórz, ±10 s, poprzedni/następny film z folderu,
// głośność, napisy, ścieżki dźwięku, prędkość i pełny ekran. Pamięta, gdzie przerwano.
Item {
    id: player
    required property Window window
    property string path
    property var playlist: []                       // filmy z tego samego folderu
    property real volume: 0.8                       // 0–1, suwak (głośność słyszana = kwadrat)
    property bool muted: false
    property bool captions: true                    // napisy włączone (zapamiętywane)
    property real rate: 1
    property bool chromeShown: true
    signal backRequested()
    signal videoSize(size s)
    signal toast(string text, string action)
    signal menuRequested(string kind, real x, real y)

    readonly property alias media: mp
    readonly property int listIndex: playlist.indexOf(path)
    readonly property bool hasNext: listIndex >= 0 && listIndex < playlist.length - 1
    readonly property bool hasPrev: listIndex > 0
    readonly property bool fullscreen: window.visibility === Window.FullScreen
    readonly property bool playing: mp.playbackState === MediaPlayer.PlayingState
    readonly property bool ended: mp.mediaStatus === MediaPlayer.EndOfMedia
    readonly property bool chrome: chromeShown || !playing || seek.dragging || ended
    readonly property string title: path ? Video.fileName(path) : ""

    // ——— Napisy z pliku obok filmu ———
    property var subFiles: []
    property string subFile: ""
    property var cues: []
    readonly property string cueText: {
        if (!captions || cues.length === 0) return "";
        const t = mp.position;
        let lo = 0, hi = cues.length - 1;
        while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            if (cues[mid].e <= t) lo = mid + 1;
            else if (cues[mid].s > t) hi = mid - 1;
            else return cues[mid].t;
        }
        return "";
    }
    function loadSubtitles(file) {
        const fps = Number(mp.metaData.value(MediaMetaData.VideoFrameRate)) || 0;
        const list = Video.loadSubtitles(file, fps);
        if (list.length === 0) { toast("Nie udało się odczytać napisów z „" + file.split("/").pop() + "”", ""); return; }
        cues = list;
        subFile = file;
        if (subFiles.indexOf(file) < 0) subFiles = subFiles.concat([file]);
        mp.activeSubtitleTrack = -1;
        captions = true;
    }
    function captionsOff() { captions = false; mp.activeSubtitleTrack = -1; }
    function embeddedSubtitles(i) { cues = []; subFile = ""; mp.activeSubtitleTrack = i; captions = true; }

    // ——— Otwieranie ———
    property real pendingResume: 0
    property bool sized: false
    function open(p) {
        saveProgress();
        path = p;
        playlist = Video.siblings(p);
        subFiles = Video.subtitleFiles(p);
        cues = []; subFile = "";
        pendingResume = Video.resumePosition(p);
        sized = false;
        mp.source = Video.url(p);
        mp.play();
        wake();
    }
    function saveProgress() {
        if (path && mp.duration > 0) Video.remember(path, mp.position, mp.duration);
    }
    function stop() { saveProgress(); mp.stop(); mp.source = ""; path = ""; }
    function next() { if (hasNext) open(playlist[listIndex + 1]); }
    function prev() {
        if (mp.position > 5000 || !hasPrev) { seekTo(0); return; }
        open(playlist[listIndex - 1]);
    }
    function toggle() {
        if (ended) { seekTo(0); mp.play(); }
        else if (playing) mp.pause();
        else mp.play();
        flash.show(playing ? "pause" : "play");
    }
    function seekTo(ms) {
        mp.position = Math.max(0, Math.min(mp.duration, ms));
        session.seeked(mp.position);
    }
    function skip(ms) { seekTo(mp.position + ms); flash.show(ms < 0 ? "replay" : "forwardSkip", Math.abs(ms / 1000)); }
    function setVolume(v) { volume = Math.max(0, Math.min(1, v)); if (volume > 0) muted = false; }
    function wake() { chromeShown = true; hideTimer.restart(); }

    Connections {
        target: mp
        function onMediaStatusChanged() {
            if (mp.mediaStatus !== MediaPlayer.LoadedMedia && mp.mediaStatus !== MediaPlayer.BufferedMedia) return;
            if (player.pendingResume > 0) {
                const at = player.pendingResume;
                player.pendingResume = 0;
                mp.position = at;
                player.toast("Wznowiono od " + Video.time(at), "restart");
            }
            if (!player.sized) {
                player.sized = true;
                const res = mp.metaData.value(MediaMetaData.Resolution);
                if (res && res.width > 0) player.videoSize(res);
                if (player.subFiles.length > 0 && player.captions && !player.subFile) player.loadSubtitles(player.subFiles[0]);
            }
        }
        function onErrorOccurred(error, message) {
            player.toast(error === MediaPlayer.FormatError ? "Ten format filmu nie jest obsługiwany" : "Nie udało się odtworzyć filmu", "");
        }
    }
    Timer { interval: 5000; repeat: true; running: player.playing; onTriggered: player.saveProgress() }
    Timer { id: hideTimer; interval: 2600; onTriggered: player.chromeShown = false }

    // Na końcu filmu — następny z folderu po odliczaniu
    property int countdown: 0
    onEndedChanged: {
        if (!ended) { countdown = 0; return; }
        saveProgress();
        if (hasNext) countdown = 5;
    }
    Timer {
        interval: 1000; repeat: true
        running: player.countdown > 0
        onTriggered: { player.countdown--; if (player.countdown === 0) player.next(); }
    }

    MediaPlayer {
        id: mp
        audioOutput: AudioOutput { volume: player.muted ? 0 : player.volume * player.volume }
        videoOutput: vo
        playbackRate: player.rate
    }

    MediaSession {
        id: session
        name: "Wideo"
        desktopEntry: "org.aster.video"
        status: player.playing ? "Playing" : (player.path ? "Paused" : "Stopped")
        title: player.title
        length: mp.duration
        position: mp.position
        canNext: player.hasNext
        canPrevious: player.hasPrev
        volume: player.volume
        inhibit: player.playing
        inhibitReason: "Oglądanie filmu"
        onPlayRequested: mp.play()
        onPauseRequested: mp.pause()
        onPlayPauseRequested: player.toggle()
        onStopRequested: mp.pause()
        onNextRequested: player.next()
        onPreviousRequested: player.prev()
        onPositionRequested: (ms) => player.seekTo(ms)
        onVolumeRequested: (v) => player.setVolume(v)
        onRaiseRequested: player.window.requestActivate()
        onQuitRequested: player.window.close()
    }

    // ——— Obraz ———
    Rectangle { anchors.fill: parent; color: "black" }
    VideoOutput {
        id: vo
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }

    // Kursor znika razem ze sterowaniem
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: player.chrome ? Qt.ArrowCursor : Qt.BlankCursor
        onPositionChanged: player.wake()
        onClicked: (e) => {
            if (e.button === Qt.RightButton) { player.menuRequested("context", e.x, e.y); return; }
            clickTimer.restart();
        }
        onDoubleClicked: (e) => {
            if (e.button !== Qt.LeftButton) return;
            clickTimer.stop();
            if (player.fullscreen) player.window.showNormal(); else player.window.showFullScreen();
        }
        onWheel: (e) => { player.setVolume(player.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05)); volumeHint.show(); }
        Timer { id: clickTimer; interval: 230; onTriggered: player.toggle() }
    }

    // Wczytywanie
    Item {
        id: spinner
        anchors.centerIn: parent
        width: 44; height: 44
        visible: mp.mediaStatus === MediaPlayer.LoadingMedia || mp.mediaStatus === MediaPlayer.BufferingMedia || mp.mediaStatus === MediaPlayer.StalledMedia
        Rectangle {
            anchors.fill: parent; radius: 22
            color: "transparent"; border.width: 3; border.color: Qt.rgba(1, 1, 1, 0.2)
        }
        Rectangle { x: 18.5; y: -1.5; width: 7; height: 7; radius: 3.5; color: "white" }
        NumberAnimation on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: spinner.visible }
    }

    // Krótki symbol na środku po kliknięciu / skrócie (▶, ❚❚, ±10 s)
    Rectangle {
        id: flash
        property string icon
        property int seconds: 0
        function show(i, s) { icon = i; seconds = s || 0; anim.restart(); }
        anchors.centerIn: parent
        width: 76; height: 76; radius: 38
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: 0
        Icon {
            anchors.centerIn: parent
            d: Icons[flash.icon] || ""
            size: 32; stroke: 2.2; color: "white"
            fill: flash.icon === "play" ? "white" : "transparent"
        }
        Text {
            visible: flash.seconds > 0
            anchors.centerIn: parent; anchors.verticalCenterOffset: 1
            text: flash.seconds
            color: "white"; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Bold
        }
        SequentialAnimation {
            id: anim
            NumberAnimation { target: flash; property: "opacity"; to: 1; duration: 60 }
            ParallelAnimation {
                NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 310; easing.type: Easing.InQuad }
                NumberAnimation { target: flash; property: "scale"; from: 1; to: 1.35; duration: 310 }
            }
        }
    }

    // Głośność po kółku / strzałkach
    Rectangle {
        id: volumeHint
        function show() { opacity = 1; volumeTimer.restart(); }
        anchors.horizontalCenter: parent.horizontalCenter
        y: 70
        width: 190; height: 40; radius: 20
        color: Qt.rgba(0, 0, 0, 0.55)
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 110 } }
        Timer { id: volumeTimer; interval: 1100; onTriggered: volumeHint.opacity = 0 }
        Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; d: player.muted || player.volume === 0 ? Icons.volumeOff : Icons.volume; size: 18; color: "white" }
        Rectangle {
            x: 44; anchors.verticalCenter: parent.verticalCenter
            width: 100; height: 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.25)
            Rectangle { width: parent.width * (player.muted ? 0 : player.volume); height: 4; radius: 2; color: "white" }
        }
        Text {
            x: 154; anchors.verticalCenter: parent.verticalCenter
            text: player.muted ? "—" : Math.round(player.volume * 100)
            color: "white"; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
        }
    }

    // ——— Napisy ———
    Text {
        id: subs
        visible: text !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - height - (player.chrome ? bottom.height + 8 : 36)
        Behavior on y { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        width: Math.min(implicitWidth, parent.width - 80)
        text: player.cueText
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        color: "white"
        style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.85)
        font.family: Theme.font; font.weight: Font.DemiBold
        font.pixelSize: Math.max(18, Math.min(44, player.height * 0.045))
    }

    // ——— Pasek u góry ———
    Item {
        id: top
        width: parent.width; height: 64
        opacity: player.chrome ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 130 } }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.6) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
        DragHandler { target: null; enabled: !player.fullscreen; onActiveChanged: if (active) player.window.startSystemMove() }
        TapHandler { onDoubleTapped: if (player.window.visibility === Window.Maximized) player.window.showNormal(); else if (!player.fullscreen) player.window.showMaximized() }
        HoverHandler { onPointChanged: player.wake() }
        HoverButton {
            id: backBtn
            x: 14; anchors.verticalCenter: parent.verticalCenter
            width: 36; height: 36; radius: 18
            color: hovered ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
            onClicked: player.backRequested()
            Icon { anchors.centerIn: parent; d: Icons.back; size: 18; stroke: 2; color: "white" }
        }
        Text {
            anchors.left: backBtn.right; anchors.leftMargin: 10
            anchors.right: winButtons.left; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: player.title
            elide: Text.ElideMiddle
            color: "white"
            font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
        }
        WindowButtons {
            id: winButtons
            window: player.window
            visible: !player.fullscreen
            idleColor: Qt.rgba(1, 1, 1, 0.16)
            idleIconColor: "white"
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // ——— Sterowanie na dole ———
    Item {
        id: bottom
        anchors.bottom: parent.bottom
        width: parent.width; height: 104
        opacity: player.chrome ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 130 } }
        HoverHandler { onPointChanged: player.wake() }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.72) }
            }
        }

        SeekBar {
            id: seek
            x: 22; y: 26
            width: parent.width - 44
            duration: mp.duration
            position: mp.position
            onSeekRequested: (ms) => player.seekTo(ms)
        }

        Row {
            id: leftControls
            x: 14; y: 54
            spacing: 2
            CtlBtn { icon: player.playing ? "pause" : "play"; filled: !player.playing; big: true; tip: player.playing ? "Wstrzymaj (spacja)" : "Odtwórz (spacja)"; onClicked: player.toggle() }
            CtlBtn { icon: "replay"; label: "10"; tip: "10 s wstecz (J)"; onClicked: player.skip(-10000) }
            CtlBtn { icon: "forwardSkip"; label: "10"; tip: "10 s naprzód (L)"; onClicked: player.skip(10000) }
            CtlBtn { icon: "prev"; visible: player.playlist.length > 1; enabled: player.hasPrev || mp.position > 5000; tip: "Poprzedni film"; onClicked: player.prev() }
            CtlBtn { icon: "next"; visible: player.playlist.length > 1; enabled: player.hasNext; tip: "Następny film (Shift+N)"; onClicked: player.next() }
            Item { width: 6; height: 1 }
            CtlBtn {
                id: volBtn
                icon: player.muted || player.volume === 0 ? "volumeOff" : (player.volume < 0.5 ? "volumeLow" : "volume")
                tip: player.muted ? "Włącz dźwięk (M)" : "Wycisz (M)"
                onClicked: player.muted = !player.muted
            }
            Item {
                width: 92; height: 40
                Rectangle {
                    id: volTrack
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; height: 4; radius: 2
                    color: Qt.rgba(1, 1, 1, 0.25)
                    Rectangle { width: parent.width * (player.muted ? 0 : player.volume); height: 4; radius: 2; color: "white" }
                    Rectangle {
                        x: parent.width * (player.muted ? 0 : player.volume) - 6; anchors.verticalCenter: parent.verticalCenter
                        width: 12; height: 12; radius: 6; color: "white"
                        visible: volArea.containsMouse || volArea.pressed
                    }
                }
                MouseArea {
                    id: volArea
                    anchors.fill: parent
                    hoverEnabled: true
                    function set(x) { player.setVolume(x / width); }
                    onPressed: (e) => set(e.x)
                    onPositionChanged: (e) => { if (pressed) set(e.x); }
                }
            }
            Item { width: 10; height: 1 }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Video.time(mp.position) + "  /  " + Video.time(mp.duration)
                color: Qt.rgba(1, 1, 1, 0.9)
                font.family: Theme.font; font.pixelSize: 13; font.features: { "tnum": 1 }
            }
        }

        Row {
            x: parent.width - width - 14; y: 54
            spacing: 2
            CtlBtn {
                id: rateBtn
                icon: "speed"
                label: player.rate !== 1 ? String(player.rate).replace(".", ",") + "×" : ""
                labelBeside: true
                tip: "Prędkość odtwarzania"
                onClicked: { const p = mapToItem(player, 0, 0); player.menuRequested("speed", p.x, p.y); }
            }
            CtlBtn {
                icon: "audioTrack"
                visible: mp.audioTracks.length > 1
                tip: "Ścieżka dźwiękowa"
                onClicked: { const p = mapToItem(player, 0, 0); player.menuRequested("audio", p.x, p.y); }
            }
            CtlBtn {
                icon: "captions"
                active: player.captions && (player.cues.length > 0 || mp.activeSubtitleTrack >= 0)
                tip: "Napisy (C)"
                onClicked: { const p = mapToItem(player, 0, 0); player.menuRequested("captions", p.x, p.y); }
            }
            CtlBtn {
                icon: player.fullscreen ? "exitFullscreen" : "fullscreen"
                tip: player.fullscreen ? "Zakończ pełny ekran (Esc)" : "Pełny ekran (F)"
                onClicked: if (player.fullscreen) player.window.showNormal(); else player.window.showFullScreen()
            }
        }
    }

    // ——— Koniec filmu ———
    Rectangle {
        anchors.centerIn: parent
        visible: player.ended
        width: endCol.implicitWidth + 56; height: endCol.implicitHeight + 44; radius: 20
        color: Qt.rgba(0, 0, 0, 0.62)
        border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
        Column {
            id: endCol
            anchors.centerIn: parent
            spacing: 14
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: player.hasNext ? "Następny film za " + player.countdown + " s" : "Koniec filmu"
                visible: !player.hasNext || player.countdown > 0
                color: Qt.rgba(1, 1, 1, 0.7); font.family: Theme.font; font.pixelSize: 13
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: player.hasNext
                width: Math.min(implicitWidth, 420); elide: Text.ElideMiddle
                text: player.hasNext ? Video.fileName(player.playlist[player.listIndex + 1]) : ""
                color: "white"; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10
                PillBtn { text: "Obejrzyj ponownie"; icon: "replay"; onClicked: { player.countdown = 0; player.seekTo(0); mp.play(); } }
                PillBtn { visible: player.hasNext; text: "Odtwórz teraz"; icon: "play"; primary: true; onClicked: player.next() }
                PillBtn { visible: player.hasNext && player.countdown > 0; text: "Anuluj"; onClicked: player.countdown = 0 }
            }
        }
    }

    // ——— Klawiatura ———
    focus: true
    Keys.onPressed: (e) => {
        wake();
        const shift = e.modifiers & Qt.ShiftModifier;
        if (e.key === Qt.Key_Space || e.key === Qt.Key_K || e.key === Qt.Key_MediaPlay || e.key === Qt.Key_MediaTogglePlayPause) toggle();
        else if (e.key === Qt.Key_Left) skip(-5000);
        else if (e.key === Qt.Key_Right) skip(5000);
        else if (e.key === Qt.Key_J) skip(-10000);
        else if (e.key === Qt.Key_L) skip(10000);
        else if (e.key === Qt.Key_Up) { setVolume(volume + 0.05); volumeHint.show(); }
        else if (e.key === Qt.Key_Down) { setVolume(volume - 0.05); volumeHint.show(); }
        else if (e.key === Qt.Key_M) { muted = !muted; volumeHint.show(); }
        else if (e.key === Qt.Key_F || e.key === Qt.Key_F11 || (e.key === Qt.Key_Return && (e.modifiers & Qt.AltModifier))) {
            if (fullscreen) window.showNormal(); else window.showFullScreen();
        }
        else if (e.key === Qt.Key_Escape) { if (fullscreen) window.showNormal(); else return; }
        else if (e.key === Qt.Key_C && !(e.modifiers & Qt.ControlModifier)) {
            if (captions && (cues.length > 0 || mp.activeSubtitleTrack >= 0)) captionsOff();
            else if (subFile) captions = true;
            else if (subFiles.length > 0) loadSubtitles(subFiles[0]);
            else if (mp.subtitleTracks.length > 0) embeddedSubtitles(0);
            else toast("Brak napisów do tego filmu", "loadsubs");
        }
        else if ((e.key === Qt.Key_N && shift) || e.key === Qt.Key_MediaNext) next();
        else if ((e.key === Qt.Key_P && shift) || e.key === Qt.Key_MediaPrevious) prev();
        else if (e.key === Qt.Key_Greater || (e.key === Qt.Key_Period && shift)) setRate(1);
        else if (e.key === Qt.Key_Less || (e.key === Qt.Key_Comma && shift)) setRate(-1);
        else if (e.key === Qt.Key_Home) seekTo(0);
        else if (e.key === Qt.Key_End) seekTo(mp.duration - 1000);
        else if (e.key >= Qt.Key_0 && e.key <= Qt.Key_9 && !(e.modifiers & Qt.ControlModifier)) seekTo(mp.duration * (e.key - Qt.Key_0) / 10);
        else return;
        e.accepted = true;
    }
    readonly property var rates: [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
    function setRate(dir) {
        const i = rates.indexOf(rate);
        rate = rates[Math.max(0, Math.min(rates.length - 1, (i < 0 ? 3 : i) + dir))];
        toast("Prędkość " + String(rate).replace(".", ",") + "×", "");
    }

    // Przycisk sterowania: biała ikona, opcjonalnie liczba („10”) w środku albo napis obok
    component CtlBtn: HoverButton {
        id: cb
        property string icon
        property string label
        property bool labelBeside: false
        property bool filled: false
        property bool big: false
        property bool active: false
        property string tip
        width: labelBeside && label ? 44 + labelText.implicitWidth : (big ? 44 : 40); height: 40; radius: 20
        color: hovered ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
        opacity: enabled ? 1 : 0.35
        Icon {
            id: cbIcon
            x: cb.labelBeside && cb.label ? 10 : (parent.width - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            d: Icons[cb.icon] || ""
            size: cb.big ? 24 : 21; stroke: cb.big ? 2.2 : 1.9
            color: cb.active ? Qt.lighter(Theme.accent, 1.5) : "white"
            fill: cb.filled ? "white" : "transparent"
        }
        Text {
            id: labelText
            visible: cb.label !== ""
            x: cb.labelBeside ? cbIcon.x + cbIcon.width + 4 : (parent.width - width) / 2
            anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: cb.labelBeside ? 0 : 1
            text: cb.label
            color: "white"
            font.family: Theme.font; font.pixelSize: cb.labelBeside ? 13 : 8; font.weight: Font.Bold
        }
        Rectangle {
            visible: cb.active
            anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 6
            width: 14; height: 2; radius: 1; color: Qt.lighter(Theme.accent, 1.5)
        }
        Rectangle {
            visible: cb.hovered && cb.tip !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            y: -height - 8
            width: tipText.implicitWidth + 18; height: 26; radius: 7
            color: Qt.rgba(0, 0, 0, 0.75)
            Text { id: tipText; anchors.centerIn: parent; text: cb.tip; color: "white"; font.family: Theme.font; font.pixelSize: 12 }
        }
    }
    component PillBtn: HoverButton {
        id: pb
        property string text
        property string icon
        property bool primary: false
        width: pbRow.implicitWidth + 32; height: 38; radius: 19
        baseColor: primary ? "white" : Qt.rgba(1, 1, 1, 0.14)
        color: primary ? (hovered ? Qt.rgba(1, 1, 1, 0.85) : baseColor) : (hovered ? Qt.rgba(1, 1, 1, 0.24) : baseColor)
        Row {
            id: pbRow
            anchors.centerIn: parent
            spacing: 8
            Icon { visible: pb.icon !== ""; anchors.verticalCenter: parent.verticalCenter; d: Icons[pb.icon] || ""; size: 16; stroke: 2; color: pb.primary ? "#111" : "white"; fill: pb.icon === "play" ? (pb.primary ? "#111" : "white") : "transparent" }
            Text { anchors.verticalCenter: parent.verticalCenter; text: pb.text; color: pb.primary ? "#111" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
        }
    }
}
