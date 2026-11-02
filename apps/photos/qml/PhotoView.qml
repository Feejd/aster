import QtQuick
import Aster.Ui

// Jedno zdjęcie: dopasowane do okna (małych nie powiększa), kółko myszy i gest szczypania powiększają
// wokół kursora, przeciąganie przesuwa, dwuklik — 100% i z powrotem. Do czasu wczytania widać miniaturę.
Item {
    id: view
    property string source
    property string thumb
    property bool animated: false
    clip: true

    readonly property Image img: animated ? moving : still
    readonly property real iw: img && img.status === Image.Ready ? img.implicitWidth : 0
    readonly property real ih: img && img.status === Image.Ready ? img.implicitHeight : 0
    readonly property bool ready: iw > 0
    readonly property real fit: ready ? Math.min(width / iw, height / ih, 1) : 1
    property real zoom: 1
    property bool fitted: true                     // podąża za rozmiarem okna, dopóki ktoś nie powiększy
    property real px: 0
    property real py: 0
    readonly property bool zoomed: ready && zoom > fit + 0.001
    readonly property int percent: Math.round(zoom * 100)

    onFitChanged: if (fitted) { zoom = fit; px = 0; py = 0; }
    onSourceChanged: { fitted = true; px = 0; py = 0; }
    onReadyChanged: if (ready) { fitted = true; zoom = fit; }

    function clampPan() {
        const w = iw * zoom, h = ih * zoom;
        const mx = Math.max(0, (w - width) / 2), my = Math.max(0, (h - height) / 2);
        px = Math.max(-mx, Math.min(mx, px));
        py = Math.max(-my, Math.min(my, py));
    }
    // Powiększenie z punktem (mx, my) w miejscu — to, co pod kursorem, zostaje pod kursorem
    function zoomAt(z, mx, my) {
        if (!ready) return;
        z = Math.max(Math.min(fit, 0.05), Math.min(16, z));
        const k = z / zoom;
        const cx = width / 2 + px, cy = height / 2 + py;
        px = mx - (mx - cx) * k - width / 2;
        py = my - (my - cy) * k - height / 2;
        zoom = z;
        fitted = Math.abs(z - fit) < 0.001;
        clampPan();
    }
    function zoomBy(f) { zoomAt(zoom * f, width / 2, height / 2); }
    function setFit() { fitted = true; zoom = fit; px = 0; py = 0; }
    function setActual(mx, my) { zoomAt(1, mx === undefined ? width / 2 : mx, my === undefined ? height / 2 : my); }

    // Miniatura pod spodem, dopóki pełne zdjęcie się wczytuje
    Image {
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height * (sourceSize.width / Math.max(1, sourceSize.height)))
        height: width * (sourceSize.height / Math.max(1, sourceSize.width))
        visible: !view.ready && status === Image.Ready
        source: view.thumb
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    // Zwykłe zdjęcie albo animowane (GIF, WebP) — widoczne jest jedno z nich
    Image {
        id: still
        visible: !view.animated
        source: !view.animated && view.source ? "file://" + view.source : ""
        x: (view.width - width) / 2 + view.px
        y: (view.height - height) / 2 + view.py
        width: view.iw * view.zoom
        height: view.ih * view.zoom
        asynchronous: true
        autoTransform: true
        cache: false
        smooth: true
        mipmap: true
    }
    AnimatedImage {
        id: moving
        visible: view.animated
        source: view.animated && view.source ? "file://" + view.source : ""
        x: (view.width - width) / 2 + view.px
        y: (view.height - height) / 2 + view.py
        width: view.iw * view.zoom
        height: view.ih * view.zoom
        asynchronous: true
        cache: false
        smooth: true
    }

    Text {
        anchors.centerIn: parent
        visible: view.img && view.img.status === Image.Error
        text: "Nie można otworzyć tego zdjęcia"
        color: Theme.text2
        font.family: Theme.font; font.pixelSize: 15
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (e) => {
            const d = e.angleDelta.y !== 0 ? e.angleDelta.y : e.pixelDelta.y * 3;
            view.zoomAt(view.zoom * Math.pow(1.0018, d), e.x, e.y);
        }
    }
    PinchHandler {
        target: null
        property real startZoom: 1
        onActiveChanged: if (active) startZoom = view.zoom
        onActiveScaleChanged: view.zoomAt(startZoom * activeScale, centroid.position.x, centroid.position.y)
    }
    DragHandler {
        id: drag
        target: null
        enabled: view.zoomed
        cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real sx: 0
        property real sy: 0
        onActiveChanged: if (active) { sx = view.px; sy = view.py; }
        onTranslationChanged: { view.px = sx + translation.x; view.py = sy + translation.y; view.clampPan(); }
    }
    TapHandler {
        onDoubleTapped: (point) => {
            if (view.zoomed || Math.abs(view.fit - 1) < 0.01 && view.zoom > view.fit) view.setFit();
            else view.zoomAt(Math.max(1, view.fit * 2), point.position.x, point.position.y);
        }
    }
}
