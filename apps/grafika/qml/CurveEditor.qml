pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Grafika

// Krzywa tonów: kanały RGB / R / G / B. Klik dodaje punkt, przeciąganie przesuwa, przeciągnięcie poza pole albo dwuklik usuwa.
Column {
    id: ce
    required property Project project
    property var curves: ({})                   // { rgb: [[x, y]…], r, g, b }
    signal edited(var curves, bool done)
    property string channel: "rgb"
    spacing: 8
    width: parent ? parent.width : 200

    readonly property var points: curves[channel] || [[0, 0], [1, 1]]
    onPointsChanged: graph.requestPaint()
    Connections { target: Theme; function onDarkChanged() { graph.requestPaint(); } }

    function put(list, done) {
        const next = Object.assign({}, curves);
        const flat = list.length === 2 && list[0][0] === 0 && list[0][1] === 0 && list[1][0] === 1 && list[1][1] === 1;
        if (flat) delete next[channel]; else next[channel] = list;
        edited(Object.keys(next).length > 0 ? next : null, done);
    }

    Row {
        spacing: 4
        Repeater {
            model: [{ id: "rgb", label: "Całość" }, { id: "r", label: "R" }, { id: "g", label: "G" }, { id: "b", label: "B" }]
            delegate: Chip {
                required property var modelData
                text: modelData.label
                height: 28
                on: ce.channel === modelData.id
                onClicked: ce.channel = modelData.id
            }
        }
    }
    Rectangle {
        width: parent.width; height: width
        radius: 8
        color: Theme.fill
        Canvas {
            id: graph
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onPaint: {
                const c = getContext("2d");
                c.reset();
                const w = width, h = height;
                c.strokeStyle = Theme.dark ? "rgba(255,255,255,0.12)" : "rgba(0,0,0,0.1)";
                c.lineWidth = 1;
                c.beginPath();
                for (let i = 1; i < 4; ++i) {
                    c.moveTo(w * i / 4, 0); c.lineTo(w * i / 4, h);
                    c.moveTo(0, h * i / 4); c.lineTo(w, h * i / 4);
                }
                c.moveTo(0, h); c.lineTo(w, 0);
                c.stroke();
                const s = ce.project.curveSamples(ce.points, 129);
                c.strokeStyle = ce.channel === "r" ? "#F44336" : ce.channel === "g" ? "#22B07D" : ce.channel === "b" ? "#3B82F6" : (Theme.dark ? "#ECEEF3" : "#16181D");
                c.lineWidth = 2;
                c.beginPath();
                for (let i = 0; i < s.length; ++i) {
                    const x = i / (s.length - 1) * w, y = (1 - s[i]) * h;
                    if (i === 0) c.moveTo(x, y); else c.lineTo(x, y);
                }
                c.stroke();
                c.fillStyle = "white";
                for (const q of ce.points) {
                    c.beginPath();
                    c.arc(q[0] * w, (1 - q[1]) * h, 4.5, 0, Math.PI * 2);
                    c.fill();
                    c.stroke();
                }
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.CrossCursor
            property int drag: -1
            property var list: []
            function at(e) { return [Math.max(0, Math.min(1, e.x / width)), Math.max(0, Math.min(1, 1 - e.y / height))]; }
            function nearest(e) {
                for (let i = 0; i < ce.points.length; ++i)
                    if (Math.hypot(ce.points[i][0] * width - e.x, (1 - ce.points[i][1]) * height - e.y) < 11) return i;
                return -1;
            }
            onPressed: (e) => {
                list = ce.points.map(q => q.slice());
                drag = nearest(e);
                if (drag < 0) {
                    const p = at(e);
                    let i = 0;
                    while (i < list.length && list[i][0] < p[0]) ++i;
                    list.splice(i, 0, p);
                    drag = i;
                    ce.put(list, false);
                }
            }
            onPositionChanged: (e) => {
                if (drag < 0) return;
                const edge = drag === 0 || drag === list.length - 1;
                const p = at(e);
                // Przeciągnięcie daleko poza pole usuwa punkt środkowy
                if (!edge && (e.y < -24 || e.y > height + 24)) { list.splice(drag, 1); drag = -1; ce.put(list, false); return; }
                const lo = drag > 0 ? list[drag - 1][0] + 0.01 : 0, hi = drag < list.length - 1 ? list[drag + 1][0] - 0.01 : 1;
                list[drag] = [drag === 0 ? 0 : drag === list.length - 1 ? 1 : Math.max(lo, Math.min(hi, p[0])), p[1]];
                ce.put(list.map(q => q.slice()), false);
            }
            onReleased: { ce.put(list.map(q => [Math.round(q[0] * 1000) / 1000, Math.round(q[1] * 1000) / 1000]), true); drag = -1; }
            onDoubleClicked: (e) => {
                const i = nearest(e);
                if (i > 0 && i < ce.points.length - 1) {
                    const l = ce.points.map(q => q.slice());
                    l.splice(i, 1);
                    ce.put(l, true);
                }
            }
        }
    }
}
