import QtQuick
import Aster.Ui

// Wykres z ostatniej minuty: najnowsza wartość po prawej, pole pod linią w kolorze zasobu.
// values2 — druga linia (sieć: wysyłanie), rysowana przerywaną kreską.
Canvas {
    id: g
    property var values: []
    property var values2: []
    property real max: 100
    property color color: "#5B8CFF"
    property color color2: "#FFD08A"
    property int count: 60
    property bool grid: true
    property real lineWidth: 1.6

    onValuesChanged: requestPaint()
    onValues2Changed: requestPaint()
    onMaxChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    readonly property bool dark: Theme.dark
    onDarkChanged: requestPaint()

    function series(ctx, list, col, fill, dashed) {
        if (!list || list.length < 2) return;
        const step = width / (count - 1);
        const n = list.length;
        const top = Math.max(max, 0.0001);
        const pt = i => [width - (n - 1 - i) * step, height - Math.min(1, Math.max(0, list[i] / top)) * (height - lineWidth) - lineWidth / 2];
        ctx.beginPath();
        for (let i = 0; i < n; ++i) {
            const p = pt(i);
            if (i === 0) ctx.moveTo(p[0], p[1]); else ctx.lineTo(p[0], p[1]);
        }
        if (fill) {
            ctx.save();
            ctx.lineTo(width, height);
            ctx.lineTo(pt(0)[0], height);
            ctx.closePath();
            const grad = ctx.createLinearGradient(0, 0, 0, height);
            grad.addColorStop(0, Qt.rgba(col.r, col.g, col.b, dark ? 0.34 : 0.26));
            grad.addColorStop(1, Qt.rgba(col.r, col.g, col.b, 0.03));
            ctx.fillStyle = grad;
            ctx.fill();
            ctx.restore();
            ctx.beginPath();
            for (let i = 0; i < n; ++i) {
                const p = pt(i);
                if (i === 0) ctx.moveTo(p[0], p[1]); else ctx.lineTo(p[0], p[1]);
            }
        }
        ctx.setLineDash(dashed ? [4, 3] : []);
        ctx.lineWidth = lineWidth;
        ctx.lineJoin = "round";
        ctx.strokeStyle = col;
        ctx.stroke();
        ctx.setLineDash([]);
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        if (grid) {
            ctx.strokeStyle = Theme.line;
            ctx.lineWidth = 1;
            ctx.beginPath();
            for (let i = 1; i < 4; ++i) {
                const y = Math.round(height * i / 4) + 0.5;
                ctx.moveTo(0, y); ctx.lineTo(width, y);
            }
            for (let i = 1; i < 6; ++i) {
                const x = Math.round(width * i / 6) + 0.5;
                ctx.moveTo(x, 0); ctx.lineTo(x, height);
            }
            ctx.stroke();
        }
        series(ctx, values, color, true, false);
        series(ctx, values2, color2, false, true);
    }
}
