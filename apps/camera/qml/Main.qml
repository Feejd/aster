pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtMultimedia
import QtCore
import Aster.Ui
import Aster.Camera

// Kamera Aster (zamiast Kamoso), jak „Aparat” w Windows: obraz z kamery na całe okno, po prawej
// przełącznik Zdjęcie/Film i duży spust, w rogu miniatura ostatniego ujęcia (otwiera Zdjęcia albo Wideo).
// Samowyzwalacz, siatka, lustrzane odbicie, wybór kamery i mikrofonu.
Window {
    id: win
    width: 960 + 2 * m
    height: 600 + 2 * m
    minimumWidth: 520 + 2 * m
    minimumHeight: 360 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: "Kamera"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 12
    // Maski (zaokrąglone rogi obrazu) wymagają shaderów — nie ma ich w renderowaniu programowym
    readonly property bool shaders: GraphicsInfo.api !== GraphicsInfo.Software && GraphicsInfo.api !== GraphicsInfo.Unknown

    // ——— Stan ———
    property string mode: "photo"                     // photo | video
    property int countdown: 0                         // sekundy do zdjęcia (samowyzwalacz)
    readonly property bool recording: recorder.recorderState !== MediaRecorder.StoppedState
    readonly property bool busy: recording || countdown > 0
    readonly property bool preview: Roll.previewImage !== ""     // ASTER_PREVIEW: zdjęcie zamiast kamery
    readonly property var cameras: devices.videoInputs
    readonly property bool hasCamera: cameras.length > 0 || preview
    readonly property bool live: preview || viewfinder.sourceRect.width > 0
    property string cameraError

    Settings {
        id: prefs
        property string device
        property bool mirror: true
        property bool grid: false
        property bool mic: true
        property int timer: 0
        property string mode: "photo"
    }
    Component.onCompleted: { mode = prefs.mode; effectsTimer.restart(); }
    onModeChanged: prefs.mode = mode

    // Wybrana kamera: zapamiętana, jeśli jest podłączona, inaczej domyślna
    readonly property var device: {
        for (const d of cameras)
            if (Roll.deviceKey(d) === prefs.device) return d;
        return devices.defaultVideoInput;
    }

    MediaDevices { id: devices }

    CaptureSession {
        id: session
        camera: Camera {
            id: cam
            cameraDevice: win.device
            active: win.hasCamera && !win.preview
            onCameraDeviceChanged: { win.cameraError = ""; cameraFormat = Roll.bestFormat(cameraDevice); }
            onErrorOccurred: (error, errorString) => win.cameraError = errorString || "Nie udało się uruchomić kamery."
        }
        imageCapture: ImageCapture {
            id: shooter
            onImageSaved: (id, path) => { Roll.photoSaved(path); win.flash(); }
            onErrorOccurred: (id, error, message) => win.toast("Nie udało się zapisać zdjęcia: " + message)
        }
        recorder: MediaRecorder {
            id: recorder
            mediaFormat: Roll.recordFormat
            quality: MediaRecorder.HighQuality
            onRecorderStateChanged: {
                if (recorderState === MediaRecorder.StoppedState && String(actualLocation) !== "")
                    Roll.videoSaved(actualLocation, win.videoThumb);
            }
            onErrorOccurred: (error, message) => win.toast("Nie udało się nagrać filmu: " + message)
        }
        audioInput: win.mode === "video" && prefs.mic ? mic : null
        videoOutput: viewfinder
    }
    AudioInput { id: mic }

    // ——— Działania ———
    function shutter() {
        if (!hasCamera || !live) return;
        if (countdown > 0) { cancelCountdown(); return; }
        if (mode === "video") {
            if (recording) recorder.stop(); else startRecording();
            return;
        }
        if (prefs.timer > 0) { countdown = prefs.timer; tick.restart(); return; }
        takePhoto();
    }
    function takePhoto() {
        if (preview) { flash(); return; }
        shooter.captureToFile(Roll.photoPath());
    }
    function cancelCountdown() { countdown = 0; tick.stop(); }
    Timer {
        id: tick
        interval: 1000; repeat: true
        onTriggered: {
            win.countdown--;
            if (win.countdown <= 0) { stop(); win.takePhoto(); }
        }
    }
    property string videoThumb
    function startRecording() {
        if (preview) return;
        videoThumb = "";
        const thumb = Roll.thumbPath();
        viewfinder.grabToImage(result => { if (result.saveToFile(thumb)) win.videoThumb = thumb; }, Qt.size(320, 180));
        recorder.outputLocation = Roll.fileUrl(Roll.videoPath());
        recorder.record();
    }
    function setMode(m) {
        if (busy || mode === m) return;
        mode = m;
    }
    function flash() { flashRect.opacity = 0.85; flashAnim.restart(); thumbBox.pop(); }

    function toast(text) { toastBox.text = text; toastBox.shown = true; toastTimer.restart(); }

    // ——— Menu ———
    function showMenu(kind, item) {
        const items = [];
        if (kind === "settings") {
            items.push({ label: "Siatka", icon: prefs.grid ? "check" : "", action: "grid" });
            items.push({ label: "Lustrzane odbicie podglądu", icon: prefs.mirror ? "check" : "", action: "mirror" });
            items.push({ label: "Nagrywaj dźwięk", icon: prefs.mic ? "check" : "", action: "mic" });
            items.push({ separator: true });
            items.push({ label: "Otwórz folder „Z aparatu”", icon: "folder", action: "folder" });
        } else if (kind === "timer") {
            for (const s of [0, 2, 5, 10])
                items.push({ label: s === 0 ? "Bez samowyzwalacza" : s + " s", icon: prefs.timer === s ? "check" : "", action: "timer:" + s });
        } else if (kind === "cameras") {
            for (const d of cameras)
                items.push({ label: d.description, icon: Roll.deviceKey(d) === Roll.deviceKey(device) ? "check" : "", action: "cam:" + Roll.deviceKey(d) });
        } else if (kind === "thumb") {
            items.push({ label: Roll.lastIsVideo ? "Odtwórz" : "Otwórz", icon: Roll.lastIsVideo ? "play" : "image", action: "open" });
            items.push({ label: "Pokaż w folderze", icon: "folder", action: "show" });
        }
        const p = item.mapToItem(frame, 0, item.height + 8);
        const x = kind === "thumb" ? p.x - 180 : p.x;
        const y = kind === "thumb" ? p.y - item.height - 16 - (items.length * 34 + 12) : p.y;
        menu.openAt(x, y, items);
    }
    function runMenu(a) {
        if (a === "grid") prefs.grid = !prefs.grid;
        else if (a === "mirror") prefs.mirror = !prefs.mirror;
        else if (a === "mic") prefs.mic = !prefs.mic;
        else if (a === "folder") Roll.openFolder();
        else if (a.startsWith("timer:")) prefs.timer = Number(a.substring(6));
        else if (a.startsWith("cam:")) prefs.device = a.substring(4);
        else if (a === "open") Roll.openLast();
        else if (a === "show") Roll.showLastInFolder();
        keys.forceActiveFocus();
    }
    // Następna kamera jednym kliknięciem (przy dwóch), z menu przy większej liczbie
    function nextCamera(item) {
        if (cameras.length > 2) { showMenu("cameras", item); return; }
        for (let i = 0; i < cameras.length; i++)
            if (Roll.deviceKey(cameras[i]) === Roll.deviceKey(device)) { prefs.device = Roll.deviceKey(cameras[(i + 1) % cameras.length]); return; }
    }

    // Do testów (ASTER_OPEN): video | settings | timer | countdown | thumb | error
    function testOpen(what) {
        if (what === "video") setMode("video");
        else if (what === "settings") showMenu("settings", settingsBtn);
        else if (what === "timer") showMenu("timer", timerBtn);
        else if (what === "countdown") { mode = "photo"; prefs.timer = 5; shutter(); }
        else if (what === "thumb") showMenu("thumb", thumbBox);
        else if (what === "grid") prefs.grid = true;
        else if (what === "rec") fakeRec.start();
    }
    // Podgląd nagrywania bez kamery (tylko do zrzutów ekranu)
    property int fakeDuration: 0
    Timer { id: fakeRec; interval: 1000; repeat: true; onTriggered: win.fakeDuration += 1000 }
    readonly property bool showRec: recording || fakeRec.running
    readonly property int recDuration: fakeRec.running ? fakeDuration : recorder.duration

    // ——— Okno ———
    function updateEffects() {
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
        color: "black"
        clip: true
        // Zaokrąglone rogi także dla obrazu z kamery (maska tylko w oknie — zmaksymalizowane nie ma rogów)
        layer.enabled: win.r > 0 && win.shaders
        layer.effect: MultiEffect { maskEnabled: true; maskSource: cornerMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }

        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Space || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { win.shutter(); e.accepted = true; }
                else if (e.key === Qt.Key_Escape && win.countdown > 0) { win.cancelCountdown(); e.accepted = true; }
                else if (e.key === Qt.Key_Up || e.key === Qt.Key_Down) { win.setMode(win.mode === "photo" ? "video" : "photo"); e.accepted = true; }
                else if (e.key === Qt.Key_F11) { if (win.visibility === Window.FullScreen) win.showNormal(); else win.showFullScreen(); e.accepted = true; }
            }
        }

        // ——— Obraz ———
        VideoOutput {
            id: viewfinder
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectFit
            visible: !win.preview
            transform: Scale { origin.x: viewfinder.width / 2; xScale: prefs.mirror ? -1 : 1 }
        }
        Image {
            id: previewImg
            visible: win.preview
            anchors.fill: parent
            source: Roll.previewImage
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        // Siatka (trójpodział) w obrębie obrazu
        Item {
            visible: prefs.grid && win.live && !win.cameraError
            readonly property rect area: win.preview ? Qt.rect((frame.width - previewImg.paintedWidth) / 2, (frame.height - previewImg.paintedHeight) / 2, previewImg.paintedWidth, previewImg.paintedHeight) : viewfinder.contentRect
            x: area.x; y: area.y; width: area.width; height: area.height
            Repeater {
                model: 4
                delegate: Rectangle {
                    required property int index
                    readonly property bool vertical: index < 2
                    x: vertical ? parent.width * (index + 1) / 3 : 0
                    y: vertical ? 0 : parent.height * (index - 1) / 3
                    width: vertical ? 1 : parent.width
                    height: vertical ? parent.height : 1
                    color: Qt.rgba(1, 1, 1, 0.4)
                }
            }
        }

        // Bez kamery / błąd / uruchamianie
        Column {
            anchors.centerIn: parent
            width: Math.min(parent.width - 80, 400)
            spacing: 12
            visible: !win.hasCamera || win.cameraError !== "" || !win.live
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 76; height: 76; radius: 22
                color: Qt.rgba(1, 1, 1, 0.08)
                Icon { anchors.centerIn: parent; d: Icons.camera; size: 36; stroke: 1.6; color: Qt.rgba(1, 1, 1, 0.6) }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: !win.hasCamera ? "Nie znaleziono kamery"
                    : win.cameraError ? "Kamera nie działa"
                    : "Uruchamianie kamery…"
                color: "white"; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: text !== ""
                text: !win.hasCamera ? "Podłącz kamerę internetową — pojawi się tutaj od razu."
                    : win.cameraError ? win.cameraError + "\nSprawdź, czy kamery nie używa inny program (np. wideorozmowa)."
                    : ""
                color: Qt.rgba(1, 1, 1, 0.6); font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.25
            }
        }

        // Błysk po zdjęciu
        Rectangle {
            id: flashRect
            anchors.fill: parent
            color: "white"
            opacity: 0
            NumberAnimation { id: flashAnim; target: flashRect; property: "opacity"; to: 0; duration: 380; easing.type: Easing.OutQuad }
        }

        // Odliczanie samowyzwalacza
        Text {
            id: countText
            anchors.centerIn: parent
            visible: win.countdown > 0
            text: win.countdown
            color: "white"
            style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.35)
            font.family: Theme.font; font.pixelSize: 160; font.weight: Font.Light
            onTextChanged: if (visible) { countPulse.restart(); }
            SequentialAnimation {
                id: countPulse
                NumberAnimation { target: countText; property: "scale"; from: 1.25; to: 1; duration: 300; easing.type: Easing.OutBack }
            }
        }

        // ——— Górny pasek ———
        Item {
            id: topBar
            width: parent.width; height: 68
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.45) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
            TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }
            Row {
                x: 16; anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                CtlBtn { id: settingsBtn; icon: "gear"; tip: "Ustawienia"; onClicked: win.showMenu("settings", settingsBtn) }
                CtlBtn {
                    id: timerBtn
                    visible: win.mode === "photo"
                    icon: "timer"
                    label: prefs.timer > 0 ? prefs.timer + " s" : ""
                    active: prefs.timer > 0
                    tip: "Samowyzwalacz"
                    onClicked: win.showMenu("timer", timerBtn)
                }
                CtlBtn {
                    id: micBtn
                    visible: win.mode === "video"
                    enabled: !win.recording
                    icon: prefs.mic ? "mic" : "volumeOff"
                    tip: prefs.mic ? "Dźwięk włączony" : "Bez dźwięku"
                    onClicked: prefs.mic = !prefs.mic
                }
                CtlBtn {
                    id: switchBtn
                    visible: win.cameras.length > 1
                    enabled: !win.busy
                    icon: "switchCamera"
                    tip: "Zmień kamerę"
                    onClicked: win.nextCamera(switchBtn)
                }
            }
            // Czas nagrywania
            Rectangle {
                anchors.centerIn: parent
                visible: win.showRec
                width: recRow.implicitWidth + 28; height: 32; radius: 16
                color: "#E5484D"
                Row {
                    id: recRow
                    anchors.centerIn: parent
                    spacing: 8
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8; height: 8; radius: 4; color: "white"
                        SequentialAnimation on opacity {
                            running: win.showRec; loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 600 }
                            NumberAnimation { to: 1; duration: 600 }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Roll.time(win.recDuration)
                        color: "white"; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                    }
                }
            }
            WindowButtons {
                window: win
                visible: win.visibility !== Window.FullScreen
                idleColor: Qt.rgba(1, 1, 1, 0.16)
                idleIconColor: "white"
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ——— Prawy pasek: tryb, spust, ostatnie ujęcie ———
        Item {
            id: side
            anchors.right: parent.right
            width: 112; height: parent.height
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.35) }
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 18

                // Zdjęcie / Film
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 44; height: 88; radius: 22
                    color: Qt.rgba(0, 0, 0, 0.35)
                    border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                    opacity: win.busy ? 0.4 : 1
                    Rectangle {
                        x: 3; y: win.mode === "photo" ? 3 : 41
                        width: 38; height: 44; radius: 19
                        color: Qt.rgba(1, 1, 1, 0.92)
                        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    }
                    Column {
                        y: 3
                        Repeater {
                            model: [{ m: "photo", icon: "camera", tip: "Zdjęcie" }, { m: "video", icon: "video", tip: "Film" }]
                            delegate: Item {
                                id: modeItem
                                required property var modelData
                                width: 44; height: 41
                                Icon {
                                    anchors.centerIn: parent
                                    d: Icons[modeItem.modelData.icon]
                                    size: 19; stroke: 1.9
                                    color: win.mode === modeItem.modelData.m ? "#111" : "white"
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                }
                                MouseArea {
                                    id: modeArea
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onClicked: win.setMode(modeItem.modelData.m)
                                }
                                Tip { shown: modeArea.containsMouse; text: modeItem.modelData.tip }
                            }
                        }
                    }
                }

                // Spust
                Item {
                    id: shutterBtn
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 72; height: 72
                    opacity: win.hasCamera && win.live && !win.cameraError ? 1 : 0.4
                    Rectangle {
                        anchors.fill: parent; radius: width / 2
                        color: "transparent"
                        border.width: 4; border.color: "white"
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        readonly property bool square: win.recording || win.showRec || win.countdown > 0
                        width: square ? 26 : 56; height: width
                        radius: square ? 6 : width / 2
                        color: win.mode === "video" ? "#E5484D" : "white"
                        scale: shutterArea.pressed ? 0.88 : shutterArea.containsMouse ? 0.95 : 1
                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        Behavior on radius { NumberAnimation { duration: 200 } }
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Behavior on scale { NumberAnimation { duration: 120 } }
                    }
                    MouseArea {
                        id: shutterArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.shutter()
                    }
                    Tip {
                        shown: shutterArea.containsMouse
                        text: win.countdown > 0 ? "Anuluj" : win.mode === "video" ? (win.recording ? "Zatrzymaj nagrywanie" : "Nagraj film (Spacja)") : "Zrób zdjęcie (Spacja)"
                    }
                }
                Item { width: 1; height: 88 }   // równowaga dla przełącznika — spust na środku
            }

            // Ostatnie ujęcie
            Rectangle {
                id: thumbBox
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: 24
                width: 52; height: 52; radius: 14
                color: Qt.rgba(1, 1, 1, 0.1)
                border.width: 2; border.color: Qt.rgba(1, 1, 1, 0.85)
                visible: Roll.lastPath !== "" || win.preview
                function pop() { popAnim.restart(); }
                SequentialAnimation {
                    id: popAnim
                    NumberAnimation { target: thumbBox; property: "scale"; to: 1.15; duration: 120 }
                    NumberAnimation { target: thumbBox; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack }
                }
                RoundedImage {
                    anchors.fill: parent; anchors.margins: 3
                    radius: 11
                    source: win.preview && !Roll.lastThumb ? Roll.previewImage : Roll.lastThumb
                }
                Icon {
                    visible: Roll.lastIsVideo
                    anchors.centerIn: parent; anchors.horizontalCenterOffset: 1
                    d: Icons.play; size: 18; color: "white"; fill: "white"
                }
                MouseArea {
                    id: thumbArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (e) => { if (e.button === Qt.RightButton) win.showMenu("thumb", thumbBox); else Roll.openLast(); }
                }
                Tip { shown: thumbArea.containsMouse; text: Roll.lastIsVideo ? "Ostatni film — otwórz w Wideo" : "Ostatnie zdjęcie — otwórz w Zdjęciach" }
            }
        }

        // Komunikat
        Rectangle {
            id: toastBox
            property bool shown: false
            property alias text: toastText.text
            anchors.horizontalCenter: parent.horizontalCenter
            y: shown ? 76 : -height - 10
            opacity: shown ? 1 : 0
            z: 300
            width: Math.min(parent.width - 60, toastText.implicitWidth + 36); height: 40; radius: 20
            color: "#ECEEF3"
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Text {
                id: toastText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 36)
                elide: Text.ElideRight
                color: "#16181D"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
            }
            Timer { id: toastTimer; interval: 5000; onTriggered: toastBox.shown = false }
        }

        ContextMenu {
            id: menu
            onTriggered: (a) => win.runMenu(a)
            onShownChanged: if (!shown) keys.forceActiveFocus()
        }

    }
    Rectangle {
        id: cornerMask
        width: frame.width; height: frame.height; radius: win.r
        visible: false
        layer.enabled: true
    }

    // ——— Elementy ———
    component CtlBtn: HoverButton {
        id: cb
        property string icon
        property string label
        property bool active: false
        property string tip
        width: label ? 46 + labelText.implicitWidth : 40; height: 40; radius: 20
        color: hovered ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
        opacity: enabled ? 1 : 0.35
        Icon {
            x: cb.label ? 11 : (parent.width - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            d: Icons[cb.icon] || ""
            size: 20; stroke: 1.9
            color: cb.active ? "#FFD15C" : "white"
        }
        Text {
            id: labelText
            visible: cb.label !== ""
            x: 36; anchors.verticalCenter: parent.verticalCenter
            text: cb.label
            color: cb.active ? "#FFD15C" : "white"
            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
        }
        Tip { shown: cb.hovered && cb.tip !== ""; text: cb.tip; below: true }
    }

    // Podpowiedź obok elementu (po lewej albo pod spodem)
    component Tip: Rectangle {
        id: tipBox
        property bool shown: false
        property bool below: false
        property alias text: tipText.text
        visible: opacity > 0
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        z: 100
        x: below ? 0 : -width - 12
        y: below ? parent.height + 6 : (parent.height - height) / 2
        width: tipText.implicitWidth + 20; height: 28; radius: 8
        color: Qt.rgba(0.08, 0.09, 0.11, 0.9)
        Text {
            id: tipText
            anchors.centerIn: parent
            color: "white"; font.family: Theme.font; font.pixelSize: 12
        }
    }

    // Miniatura z zaokrąglonymi rogami (maska, gdy są shadery; bez nich — zwykłe przycięcie)
    component RoundedImage: Item {
        id: ri
        property alias source: img.source
        property real radius: 10
        clip: true
        layer.enabled: win.shaders
        layer.effect: MultiEffect { maskEnabled: true; maskSource: riMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
        Rectangle { id: riMask; width: ri.width; height: ri.height; radius: ri.radius; visible: false; layer.enabled: true }
        Image {
            id: img
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize.width: 128
        }
    }
}
