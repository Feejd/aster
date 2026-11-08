import QtQuick

// Zaokrąglone rogi karty, której treść jest przycinana prostokątnie (clip):
// w czterech narożnikach maluje kolor tła okna. Działa bez efektów GPU.
Canvas {
    id: cc
    property real radius: 24
    property color background: "white"
    onBackgroundChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const c = getContext("2d"), w = width, h = height, r = radius;
        c.reset();
        c.fillStyle = background;
        c.beginPath();
        c.rect(0, 0, w, h);
        c.moveTo(r, 0);
        c.arcTo(w, 0, w, h, r);
        c.arcTo(w, h, 0, h, r);
        c.arcTo(0, h, 0, 0, r);
        c.arcTo(0, 0, w, 0, r);
        c.closePath();
        c.fillRule = Qt.OddEvenFill;
        c.fill();
    }
}
