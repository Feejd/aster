pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Studio

// Panel kanału: fala z zakresem i plasterkami, obwiednia, filtr, strojenie, cięcie i dopasowanie do tempa.
Item {
    id: cp
    property var colors: []
    signal closeRequested()
    signal savePreset()
    readonly property int cid: Studio.selectedChannel
    readonly property var ch: Studio.channels.find((c) => c.id === cid) || null
    readonly property var p: ch ? Studio.channelParams(cid) : ({})
    readonly property bool sampled: !!ch && (ch.kind === "sampler" || ch.kind === "drum")
    readonly property color tint: ch && colors.length ? colors[ch.color % colors.length] : Theme.accent
    function setP(k, v) { Studio.setChannelParam(cid, k, v); }

    Rectangle { anchors.fill: parent; color: Theme.windowGlass }
    Rectangle { width: parent.width; height: 1; color: Theme.line }
    Text {
        x: 16; y: 14
        text: cp.ch ? cp.ch.name : "Zaznacz kanał w racku"
        color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold
    }
    Row {
        anchors.right: parent.right; anchors.rightMargin: 14; y: 10
        spacing: 8
        Pill { height: 28; text: "Zapisz ustawienie"; visible: !!cp.ch; onClicked: cp.savePreset() }
        Pill { height: 28; text: "Rack"; icon: "grid"; onClicked: cp.closeRequested() }
    }
    Text {
        visible: !!cp.ch && !cp.sampled
        x: 16; y: 48; width: parent.width - 32
        wrapMode: Text.WordWrap
        text: cp.ch && cp.ch.kind === "vst" ? "Instrument VST3 — ustawienia są w jego oknie (dwuklik na nazwie w racku)." : "Syntezator Studia gra od razu; nuty dodaj w piano rollu."
        color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
    }

    Item {
        visible: cp.sampled
        x: 16; y: 46
        width: parent.width - 32; height: parent.height - y - 12

        // Fala i zakres
        Rectangle {
            id: wave
            width: parent.width - controls.width - 16; height: 150; radius: 10
            color: Theme.fill
            clip: true
            Waveform {
                anchors.fill: parent
                file: cp.p.wave || ""
                srcStart: 0
                srcLength: cp.p.seconds || 0
                pxPerSec: wave.width / Math.max(0.01, cp.p.seconds || 1)
                color: cp.tint
                version: Studio.sourcesVersion
            }
            // Poza zakresem przyciemnione
            Rectangle { width: wave.width * (cp.p.from || 0); height: parent.height; color: Qt.rgba(0, 0, 0, 0.3) }
            Rectangle { x: wave.width * (cp.p.to || 1); width: wave.width - x; height: parent.height; color: Qt.rgba(0, 0, 0, 0.3) }
            Repeater {
                model: cp.p.slices || []
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    x: wave.width * modelData
                    width: 1.5; height: wave.height
                    color: Theme.dark ? "white" : "#16181D"
                    Text { x: 3; y: 2; text: parent.index + 1; color: parent.color; font.family: Theme.font; font.pixelSize: 9 }
                }
            }
            MouseArea {
                anchors.fill: parent
                property string edge: ""
                function put(x) {
                    const f = Math.max(0, Math.min(1, x / wave.width));
                    if (edge) cp.setP(edge, f);
                }
                onPressed: (e) => {
                    Studio.remember();
                    const f = e.x / wave.width;
                    edge = Math.abs(f - (cp.p.from || 0)) < Math.abs(f - (cp.p.to || 1)) ? "from" : "to";
                    put(e.x);
                }
                onPositionChanged: (e) => { if (pressed) put(e.x); }
            }
        }
        // Cięcie
        Flow {
            y: wave.height + 10
            width: wave.width
            spacing: 6
            Tool { text: "Na uderzenia"; hint: "Plasterki w miejscach uderzeń"; onClicked: Studio.chopChannel(cp.cid, "onsets", 32) }
            Tool { text: "4"; onClicked: Studio.chopChannel(cp.cid, "equal", 4) }
            Tool { text: "8"; onClicked: Studio.chopChannel(cp.cid, "equal", 8) }
            Tool { text: "16"; onClicked: Studio.chopChannel(cp.cid, "equal", 16) }
            Tool { text: "Całość"; visible: (cp.p.slices || []).length > 0; onClicked: Studio.chopChannel(cp.cid, "none", 0) }
            Tool { text: "Ułóż we wzorze"; visible: (cp.p.slices || []).length > 0; hint: "Plasterki w bieżącym wzorze, po kolei"; onClicked: Studio.slicesToPattern(cp.cid) }
            Tool { text: "Do tempa"; visible: cp.p.kind === "sampler"; hint: "Długość do pełnych taktów, bez zmiany wysokości"; onClicked: Studio.stretchChannel(cp.cid, 0) }
            Tool { text: "Wstecz"; on: !!cp.p.reverse; visible: cp.p.kind === "sampler"; onClicked: cp.setP("reverse", cp.p.reverse ? 0 : 1) }
            Tool { text: "Pętla"; on: !!cp.p.loop; onClicked: cp.setP("loop", cp.p.loop ? 0 : 1) }
            Tool { text: "Do końca"; on: !!cp.p.oneShot; hint: "Gra cały dźwięk, puszczenie nuty go nie ucina"; onClicked: cp.setP("oneShot", cp.p.oneShot ? 0 : 1) }
        }
        // Obwiednia i brzmienie
        Grid {
            id: controls
            x: parent.width - width
            columns: 2
            columnSpacing: 16; rowSpacing: 8
            Param { label: "Narastanie"; key: "attack"; lo: 0.001; hi: 2; log: true; unit: "s" }
            Param { label: "Opadanie"; key: "decay"; lo: 0.005; hi: 3; log: true; unit: "s" }
            Param { label: "Podtrzymanie"; key: "sustain"; lo: 0; hi: 1; unit: "%" }
            Param { label: "Wybrzmienie"; key: "release"; lo: 0.003; hi: 3; log: true; unit: "s" }
            Param { label: "Strojenie"; key: "tune"; lo: -12; hi: 12; unit: "pt" }
            Param { label: "Podstawa"; key: "root"; lo: 24; hi: 96; unit: "note" }
            Param { label: "Filtr"; key: "cutoff"; lo: 40; hi: 20000; log: true; unit: "Hz" }
            Param { label: "Rezonans"; key: "resonance"; lo: 0.5; hi: 8; log: true; unit: "" }
            Param { label: "Ucinanie"; key: "choke"; lo: 0; hi: 4; unit: "group" }
        }
    }

    component Tool: HoverButton {
        id: tb
        property string text
        property string hint
        property bool on: false
        width: tbText.implicitWidth + 18; height: 26; radius: 8
        baseColor: on ? Theme.accentSoft : Theme.fill
        color: hovered ? Theme.hover : baseColor
        Text { id: tbText; anchors.centerIn: parent; text: tb.text; color: tb.on ? Theme.accentText : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
        Tip { shown: tb.hovered && tb.hint !== ""; text: tb.hint }
    }
    component Param: Item {
        id: pa
        property string label
        property string key
        property real lo: 0
        property real hi: 1
        property bool log: false
        property string unit
        readonly property real value: cp.p[key] !== undefined ? cp.p[key] : lo
        readonly property real frac: log ? Math.log(Math.max(lo, value) / lo) / Math.log(hi / lo) : (value - lo) / (hi - lo)
        function shown() {
            if (unit === "%") return Math.round(value * 100) + "%";
            if (unit === "s") return value < 1 ? Math.round(value * 1000) + " ms" : value.toFixed(2).replace(".", ",") + " s";
            if (unit === "Hz") return value >= 19000 ? "wył." : value < 1000 ? Math.round(value) + " Hz" : (value / 1000).toFixed(1).replace(".", ",") + " kHz";
            if (unit === "pt") return (value > 0 ? "+" : "") + value.toFixed(1).replace(".", ",");
            if (unit === "note") return ["C", "Cis", "D", "Dis", "E", "F", "Fis", "G", "Gis", "A", "B", "H"][value % 12] + (Math.floor(value / 12) - 1);
            if (unit === "group") return value > 0 ? "grupa " + value : "wył.";
            return value.toFixed(1).replace(".", ",");
        }
        width: 150; height: 36
        Text { text: pa.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
        Text { anchors.right: parent.right; text: pa.shown(); color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.features: { "tnum": 1 } }
        Item {
            id: track
            y: 18; width: parent.width; height: 16
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Theme.fill }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * pa.frac; height: 4; radius: 2; color: Theme.text2 }
            Rectangle { x: (parent.width - 12) * pa.frac; anchors.verticalCenter: parent.verticalCenter; width: 12; height: 12; radius: 6; color: "white"; border.width: 1; border.color: Theme.edge }
            MouseArea {
                anchors.fill: parent
                function put(x) {
                    const f = Math.max(0, Math.min(1, x / track.width));
                    let v = pa.log ? pa.lo * Math.pow(pa.hi / pa.lo, f) : pa.lo + (pa.hi - pa.lo) * f;
                    if (pa.unit === "note" || pa.unit === "group") v = Math.round(v);
                    cp.setP(pa.key, v);
                }
                onPressed: (e) => { Studio.remember(); put(e.x); }
                onPositionChanged: (e) => { if (pressed) put(e.x); }
            }
        }
    }
}
