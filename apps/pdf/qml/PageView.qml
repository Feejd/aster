pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Pdf
import Aster.Ui

// Strony dokumentu jedna pod drugą: białe kartki z cieniem na szarym tle, zaznaczanie tekstu myszą,
// klikalne linki, podświetlone wyniki szukania. Powiększenie (Ctrl+kółko, gest) trzyma miejsce pod kursorem;
// strony renderują się ostro dopiero chwilę po skończeniu powiększania.
Item {
    id: pv
    required property PdfDocument document
    property real zoom: 1                           // piksele na punkt PDF
    property real renderedScale: 1
    property string fitMode: "width"                // width | page | "" (ręcznie)
    property int pageRotation: 0                    // 0, 90, 180, 270
    property real hOffset: 0
    property int currentPage: 0
    property int selectionPage: -1
    property string selectedText: ""
    readonly property alias search: searchModel
    readonly property real pad: 24
    readonly property bool rot90: pageRotation % 180 !== 0
    readonly property real maxW: (rot90 ? document.maxPageHeight : document.maxPageWidth) || 612
    readonly property real maxH: (rot90 ? document.maxPageWidth : document.maxPageHeight) || 792
    readonly property real fitWidthScale: Math.max(0.1, Math.min(1.75, (width - 2 * pad - 12) / maxW))
    readonly property real fitPageScale: Math.max(0.1, Math.min(fitWidthScale, (height - 2 * pad) / maxH))
    readonly property int percent: Math.round(zoom * 100)
    readonly property real contentW: maxW * zoom + 2 * pad
    signal linkToUrl(string url)

    function applyFit() {
        if (fitMode === "width") setScale(fitWidthScale);
        else if (fitMode === "page") setScale(fitPageScale);
    }
    onFitWidthScaleChanged: if (fitMode === "width") setScale(fitWidthScale)
    onFitPageScaleChanged: if (fitMode === "page") setScale(fitPageScale)
    onPageRotationChanged: Qt.callLater(applyFit)

    // Powiększenie z miejscem (y od góry widoku) zostającym w miejscu
    function setScale(s, anchorY) {
        s = Math.max(0.1, Math.min(8, s));
        if (Math.abs(s - zoom) < 0.0005) return;
        if (anchorY === undefined) anchorY = list.height / 3;
        const p = Math.max(0, list.indexAt(list.width / 2, list.contentY + anchorY));
        const item = list.itemAtIndex(p);
        const off = item ? (list.contentY + anchorY - item.y) / zoom : 0;
        zoom = s;
        renderTimer.restart();
        clampH();
        list.forceLayout();
        list.positionViewAtIndex(p, ListView.Beginning);
        list.contentY += off * s - anchorY;
    }
    function zoomBy(f, anchorY) { fitMode = ""; setScale(zoom * f, anchorY); }
    function clampH() { hOffset = Math.max(0, Math.min(Math.max(0, contentW - list.width), hOffset)); }
    onWidthChanged: clampH()
    Timer { id: renderTimer; interval: 180; onTriggered: pv.renderedScale = pv.zoom }

    function goTo(page, yPoints) {
        if (page < 0 || page >= list.count) return;
        list.positionViewAtIndex(page, ListView.Beginning);
        if (yPoints !== undefined && yPoints > 0) list.contentY += yPoints * zoom - 16;
        else list.contentY -= 12;
        currentPage = page;
    }
    // Zaznaczenia stron, które są teraz w pamięci (strona → PdfSelection)
    property var selections: ({})
    function copySelection() {
        const sel = selections[selectionPage];
        if (sel) sel.copyToClipboard();
        return !!sel && selectedText !== "";
    }
    function selectAll() {
        const sel = selections[currentPage];
        if (!sel) return;
        selectionPage = currentPage;
        sel.selectAll();
    }

    PdfSearchModel {
        id: searchModel
        document: pv.document
        onCurrentResultChanged: {
            const link = currentResultLink;
            if (link && link.valid && link.rectangles.length > 0) {
                const r = link.rectangles[0];
                const item = list.itemAtIndex(link.page);
                // Wynik już widać — bez skakania
                if (item) {
                    const top = item.y + r.y * pv.zoom, bottom = top + r.height * pv.zoom;
                    if (top > list.contentY + 40 && bottom < list.contentY + list.height - 40) return;
                }
                pv.goTo(link.page, Math.max(0, r.y - 120));
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.dark ? "#121317" : "#E6E8EC"
    }

    ListView {
        id: list
        anchors.fill: parent
        model: pv.document.status === PdfDocument.Ready ? pv.document.pageCount : 0
        spacing: 18
        topMargin: pv.pad; bottomMargin: pv.pad
        cacheBuffer: Math.max(800, height)
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        onContentYChanged: {
            const i = indexAt(width / 2, contentY + height / 3);
            if (i >= 0) pv.currentPage = i;
        }

        delegate: Item {
            id: pageItem
            required property int index
            readonly property size pts: pv.document.pagePointSize(index)
            readonly property real pw: (pv.rot90 ? pts.height : pts.width) * pv.zoom
            readonly property real ph: (pv.rot90 ? pts.width : pts.height) * pv.zoom
            Component.onCompleted: pv.selections[index] = sel
            Component.onDestruction: if (pv.selections[index] === sel) delete pv.selections[index]
            width: list.width
            height: ph

            RectangularShadow {
                anchors.fill: paper
                blur: 18; offset.y: 4
                color: Theme.dark ? Qt.rgba(0, 0, 0, 0.6) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.16)
            }
            Rectangle {
                id: paper
                x: Math.max(pv.pad, (list.width - pageItem.pw) / 2) - pv.hOffset
                width: pageItem.pw; height: pageItem.ph
                color: "white"

                // Treść strony w układzie punktów PDF × skala; obrót wokół środka kartki
                Item {
                    id: content
                    anchors.centerIn: parent
                    width: pageItem.pts.width * pv.zoom
                    height: pageItem.pts.height * pv.zoom
                    rotation: pv.pageRotation

                    PdfPageImage {
                        id: image
                        anchors.fill: parent
                        document: pv.document
                        currentFrame: pageItem.index
                        asynchronous: true
                        cache: false
                        sourceSize.width: pageItem.pts.width * pv.renderedScale * Screen.devicePixelRatio
                        sourceSize.height: 0
                        fillMode: Image.Stretch
                        smooth: true
                    }

                    Shape {
                        anchors.fill: parent
                        visible: image.status === Image.Ready
                        ShapePath {
                            strokeWidth: -1
                            fillColor: Qt.rgba(1, 0.78, 0.1, 0.38)
                            scale: Qt.size(pv.zoom, pv.zoom)
                            PathMultiline {
                                paths: { searchModel.searchString; searchModel.count; return searchModel.boundingPolygonsOnPage(pageItem.index); }
                            }
                        }
                        ShapePath {
                            strokeWidth: -1
                            fillColor: Theme.accentAlpha(0.3)
                            scale: Qt.size(pv.zoom, pv.zoom)
                            PathMultiline { paths: sel.geometry }
                        }
                        ShapePath {
                            strokeWidth: searchModel.currentPage === pageItem.index ? 2 : 0
                            strokeColor: "#F08A0A"
                            fillColor: "transparent"
                            scale: Qt.size(pv.zoom, pv.zoom)
                            PathMultiline { paths: searchModel.currentPage === pageItem.index ? searchModel.currentResultBoundingPolygons : [] }
                        }
                    }

                    // Zaznaczanie tekstu myszą
                    DragHandler {
                        id: textDrag
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.Stylus
                        target: null
                        cursorShape: Qt.IBeamCursor
                        onActiveChanged: if (active) pv.selectionPage = pageItem.index
                    }
                    TapHandler {
                        id: click
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.Stylus
                        onTapped: { sel.clear(); pv.selectionPage = pageItem.index; }
                    }
                    HoverHandler { cursorShape: Qt.IBeamCursor }
                    PdfSelection {
                        id: sel
                        anchors.fill: parent
                        document: pv.document
                        page: pageItem.index
                        renderScale: pv.zoom
                        from: textDrag.centroid.pressPosition
                        to: textDrag.centroid.position
                        hold: !textDrag.active && !click.pressed
                        onTextChanged: if (pv.selectionPage === pageItem.index) pv.selectedText = text
                    }

                    // Linki: w dokumencie — skok do miejsca, do stron — przeglądarka
                    Repeater {
                        model: PdfLinkModel { document: pv.document; page: pageItem.index }
                        delegate: MouseArea {
                            id: link
                            required property rect rectangle
                            required property url url
                            required property int page
                            required property point location
                            x: rectangle.x * pv.zoom; y: rectangle.y * pv.zoom
                            width: rectangle.width * pv.zoom; height: rectangle.height * pv.zoom
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: {
                                if (link.page >= 0) pv.goTo(link.page, link.location.y);
                                else pv.linkToUrl(link.url.toString());
                            }
                        }
                    }
                }
            }
        }

        // Ctrl+kółko — powiększenie; poziome przewijanie szerokich (powiększonych) stron
        WheelHandler {
            acceptedModifiers: Qt.ControlModifier
            onWheel: (e) => pv.zoomBy(Math.pow(1.0015, e.angleDelta.y), e.y)
        }
        WheelHandler {
            orientation: Qt.Horizontal
            enabled: pv.contentW > list.width
            onWheel: (e) => { pv.hOffset -= (e.pixelDelta.x !== 0 ? e.pixelDelta.x : e.angleDelta.x / 2); pv.clampH(); }
        }
        PinchHandler {
            target: null
            property real start: 1
            onActiveChanged: if (active) start = pv.zoom
            onActiveScaleChanged: { pv.fitMode = ""; pv.setScale(start * activeScale, centroid.position.y); }
        }
    }

    // Suwaki: pionowy z numerem strony podczas przewijania, poziomy przy szerokich stronach
    Rectangle {
        id: vbar
        visible: list.contentHeight > list.height
        anchors.right: parent.right; anchors.rightMargin: 3
        y: list.visibleArea.yPosition * list.height
        width: barArea.containsMouse || barArea.pressed ? 8 : 5; radius: width / 2
        height: Math.max(30, list.visibleArea.heightRatio * list.height)
        color: Theme.text2
        opacity: list.moving || barArea.containsMouse || barArea.pressed ? 0.55 : 0.2
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on width { NumberAnimation { duration: 120 } }
        MouseArea {
            id: barArea
            anchors.fill: parent; anchors.margins: -4
            hoverEnabled: true
            property real startY: 0
            property real startContent: 0
            onPressed: (e) => { startY = mapToItem(pv, e.x, e.y).y; startContent = list.contentY; }
            onPositionChanged: (e) => {
                if (!pressed) return;
                const dy = mapToItem(pv, e.x, e.y).y - startY;
                list.contentY = Math.max(list.originY - list.topMargin, Math.min(list.contentHeight - list.height + list.originY + list.bottomMargin,
                                         startContent + dy / list.height * list.contentHeight));
            }
        }
    }
    Rectangle {
        visible: list.moving || barArea.pressed
        anchors.right: vbar.left; anchors.rightMargin: 8
        y: Math.max(4, Math.min(parent.height - height - 4, vbar.y + vbar.height / 2 - height / 2))
        width: pageTip.implicitWidth + 20; height: 26; radius: 13
        color: Theme.surface
        border.width: 1; border.color: Theme.edge
        Text { id: pageTip; anchors.centerIn: parent; text: (pv.currentPage + 1) + " / " + list.count; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium; font.features: { "tnum": 1 } }
    }
    Rectangle {
        visible: pv.contentW > list.width
        anchors.bottom: parent.bottom; anchors.bottomMargin: 3
        x: pv.hOffset / pv.contentW * list.width
        height: 5; radius: 2.5
        width: Math.max(30, list.width / pv.contentW * list.width)
        color: Theme.text2
        opacity: 0.3
    }
}
