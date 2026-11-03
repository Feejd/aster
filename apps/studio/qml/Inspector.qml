pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Studio

// Panel z prawej: brzmienie zaznaczonej ścieżki (gotowe ustawienia, korektor, kompresja, pogłos),
// zaznaczony klip (głośność, narastanie, wyciszanie, pętla) i pogłos całego projektu.
Item {
    id: insp
    property var colors: []
    readonly property int ti: Studio.selectedTrack
    readonly property var track: Studio.tracks[ti] || null
    readonly property var mx: Studio.mix[ti] || ({})
    // Zależność od listy ścieżek musi być użyta, inaczej kompilator QML ją pomija i klip się nie odświeża
    readonly property var cl: Studio.tracks.length >= 0 && Studio.selectedClip > 0 ? Studio.clip(Studio.selectedClip) : null
    readonly property bool hasClip: !!cl && cl.id !== undefined

    function db(v) { return (v > 0 ? "+" : v < 0 ? "−" : "") + Math.abs(v).toFixed(1) + " dB"; }
    function pct(v) { return Math.round(v * 100) + "%"; }
    function sec(v) { return v <= 0.001 ? "brak" : v.toFixed(1).replace(".", ",") + " s"; }

    Rectangle { width: 1; height: parent.height; color: Theme.line }

    Flickable {
        x: 1; width: parent.width - 1; height: parent.height
        contentHeight: col.height + 30
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            x: 18; y: 14
            width: parent.width - 36
            spacing: 10

            // ——— Ścieżka ———
            Row {
                spacing: 8
                visible: !!insp.track
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5; color: insp.track && insp.colors.length ? insp.colors[insp.track.color % insp.colors.length] : Theme.accent }
                Text {
                    width: col.width - 20
                    text: insp.track ? insp.track.name : ""
                    elide: Text.ElideRight
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold
                }
            }
            Text {
                visible: !insp.track
                width: col.width
                wrapMode: Text.WordWrap
                text: "Zaznacz ścieżkę, żeby zmienić jej brzmienie."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
            }

            Column {
                width: col.width
                spacing: 10
                visible: !!insp.track
                Caption { text: "GOTOWE BRZMIENIE" }
                Repeater {
                    model: ["", "Wokal", "Instrumenty", "Efekty"]
                    delegate: Column {
                        id: group
                        required property string modelData
                        width: col.width
                        spacing: 6
                        Text { visible: group.modelData !== ""; text: group.modelData; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
                Flow {
                    width: col.width
                    spacing: 6
                    Repeater {
                        model: Studio.presets.filter(p => p.group === group.modelData)
                        delegate: HoverButton {
                            id: chip
                            required property var modelData
                            readonly property bool on: (insp.mx.preset || "") === modelData.id || (modelData.id === "none" && !insp.mx.preset && !insp.mx.lowCut && !insp.mx.comp && !insp.mx.reverb && !insp.mx.eqLow && !insp.mx.eqMid && !insp.mx.eqHigh)
                            width: chipText.implicitWidth + 22; height: 28; radius: 14
                            baseColor: on ? Theme.accent : Theme.fill
                            color: on ? baseColor : (hovered ? Theme.hover : baseColor)
                            onClicked: Studio.applyPreset(insp.ti, modelData.id)
                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                text: chip.modelData.label
                                color: chip.on ? "white" : Theme.text
                                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                            }
                            Tip { shown: chip.hovered; text: chip.modelData.hint }
                        }
                    }
                }
                    }
                }

                Caption { text: "KOREKTOR"; topPadding: 6 }
                FxSlider { label: "Niskie (bas)"; from: -12; to: 12; centered: true; value: insp.mx.eqLow || 0; shown: insp.db(value); onMoved: (v) => Studio.setTrackFx(insp.ti, "eqLow", v) }
                FxSlider { label: "Średnie (głos)"; from: -12; to: 12; centered: true; value: insp.mx.eqMid || 0; shown: insp.db(value); onMoved: (v) => Studio.setTrackFx(insp.ti, "eqMid", v) }
                FxSlider { label: "Wysokie (blask)"; from: -12; to: 12; centered: true; value: insp.mx.eqHigh || 0; shown: insp.db(value); onMoved: (v) => Studio.setTrackFx(insp.ti, "eqHigh", v) }
                Check {
                    text: "Usuń dudnienie (poniżej 80 Hz)"
                    on: !!insp.mx.lowCut
                    onToggled: { Studio.remember(); Studio.setTrackFx(insp.ti, "lowCut", insp.mx.lowCut ? 0 : 1); }
                }

                Caption { text: "AUTOTUNE"; topPadding: 6 }
                FxSlider {
                    label: "Korekcja wysokości"
                    hint: "Dociąga głos do tonacji " + Studio.keyName
                    from: 0; to: 1
                    value: insp.mx.tune || 0
                    shown: value < 0.01 ? "wył." : value < 0.4 ? "naturalnie" : value < 0.75 ? "wyraźnie" : "efekt trap"
                    onMoved: (v) => Studio.setTrackFx(insp.ti, "tune", v)
                }

                Caption { text: "DYNAMIKA I PRZESTRZEŃ"; topPadding: 6 }
                FxSlider { label: "Kompresja"; hint: "Wyrównuje ciche i głośne fragmenty"; from: 0; to: 1; value: insp.mx.comp || 0; shown: insp.pct(value); onMoved: (v) => Studio.setTrackFx(insp.ti, "comp", v) }
                FxSlider { label: "Pogłos"; hint: "Ile sali słychać wokół ścieżki"; from: 0; to: 1; value: insp.mx.reverb || 0; shown: insp.pct(value); onMoved: (v) => Studio.setTrackFx(insp.ti, "reverb", v) }
                FxSlider { label: "Echo"; hint: "Powtórzenia w rytm piosenki"; from: 0; to: 1; value: insp.mx.echo || 0; shown: insp.pct(value); onMoved: (v) => Studio.setTrackFx(insp.ti, "echo", v) }
                FxSlider { label: "Ciepło / przester"; hint: "Nasycenie — 808 i głos słychać nawet w telefonie"; from: 0; to: 1; value: insp.mx.drive || 0; shown: insp.pct(value); onMoved: (v) => Studio.setTrackFx(insp.ti, "drive", v) }
            }

            Rectangle { width: col.width; height: 1; color: Theme.line; visible: insp.hasClip }

            // ——— Klip ———
            Column {
                width: col.width
                spacing: 10
                visible: insp.hasClip
                Caption { text: "KLIP" }
                Text {
                    width: col.width
                    text: insp.hasClip ? insp.cl.name : ""
                    elide: Text.ElideRight
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                }
                FxSlider {
                    label: "Głośność klipu"; from: -24; to: 12; centered: true; origin: 0
                    value: insp.hasClip ? insp.cl.gain : 0; shown: insp.db(value)
                    onMoved: (v) => Studio.setClipGain(insp.cl.id, v)
                }
                FxSlider {
                    label: "Narastanie"; from: 0; to: insp.hasClip ? Math.min(10, insp.cl.length) : 1
                    value: insp.hasClip ? insp.cl.fadeIn : 0; shown: insp.sec(value)
                    onMoved: (v) => Studio.setClipFades(insp.cl.id, v, Math.min(insp.cl.fadeOut, insp.cl.length - v))
                }
                FxSlider {
                    label: "Wyciszanie"; from: 0; to: insp.hasClip ? Math.min(10, insp.cl.length) : 1
                    value: insp.hasClip ? insp.cl.fadeOut : 0; shown: insp.sec(value)
                    onMoved: (v) => Studio.setClipFades(insp.cl.id, Math.min(insp.cl.fadeIn, insp.cl.length - v), v)
                }
                Check {
                    text: "Zapętlaj (wydłużaj prawym brzegiem)"
                    on: insp.hasClip && insp.cl.loop
                    onToggled: Studio.setClipLoop(insp.cl.id, !insp.cl.loop)
                }
                Pill {
                    text: "Ćwicz ten fragment w pętli"
                    icon: "repeat"
                    height: 30
                    onClicked: Studio.cycleClip(insp.cl.id)
                }
            }

            Rectangle { width: col.width; height: 1; color: Theme.line }

            // ——— Mastering (suma) ———
            Caption { text: "MASTERING" }
            Text {
                width: col.width
                wrapMode: Text.WordWrap
                text: "Ostatni szlif całej piosenki: brzmienie, sklejenie i głośność jak w radiu."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
            }
            Flow {
                width: col.width
                spacing: 6
                Repeater {
                    model: Studio.masteringPresets
                    delegate: HoverButton {
                        id: mchip
                        required property var modelData
                        readonly property bool on: (Studio.mastering.preset || "none") === modelData.id
                        width: mchipText.implicitWidth + 22; height: 28; radius: 14
                        baseColor: on ? Theme.accent : Theme.fill
                        color: on ? baseColor : (hovered ? Theme.hover : baseColor)
                        onClicked: Studio.applyMastering(modelData.id)
                        Text { id: mchipText; anchors.centerIn: parent; text: mchip.modelData.label; color: mchip.on ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                        Tip { shown: mchip.hovered; text: mchip.modelData.hint }
                    }
                }
            }
            FxSlider { label: "Dół"; from: -12; to: 12; centered: true; value: Studio.mastering.eqLow; shown: insp.db(value); onMoved: (v) => Studio.setMastering("eqLow", v) }
            FxSlider { label: "Góra"; from: -12; to: 12; centered: true; value: Studio.mastering.eqHigh; shown: insp.db(value); onMoved: (v) => Studio.setMastering("eqHigh", v) }
            FxSlider { label: "Sklejenie (kompresja)"; from: 0; to: 1; value: Studio.mastering.comp; shown: insp.pct(value); onMoved: (v) => Studio.setMastering("comp", v) }
            FxSlider { label: "Szerokość stereo"; from: 0; to: 2; origin: 1; centered: true; value: Studio.mastering.width; shown: Math.round(value * 100) + "%"; onMoved: (v) => Studio.setMastering("width", v) }
            FxSlider { label: "Głośność (dociśnięcie)"; from: 0; to: 12; value: Studio.mastering.drive; shown: "+" + value.toFixed(1) + " dB"; onMoved: (v) => Studio.setMastering("drive", v) }

            Rectangle { width: col.width; height: 1; color: Theme.line }

            // ——— Projekt ———
            Caption { text: "PROJEKT" }
            Item {
                width: col.width; height: 34
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Tonacja"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Pill { height: 28; icon: "minus"; onClicked: { Studio.remember(); Studio.keyRoot = (Studio.keyRoot + 11) % 12; } }
                    Text { anchors.verticalCenter: parent.verticalCenter; width: 70; horizontalAlignment: Text.AlignHCenter; text: Studio.keyName; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Pill { height: 28; icon: "plus"; onClicked: { Studio.remember(); Studio.keyRoot = (Studio.keyRoot + 1) % 12; } }
                }
            }
            Item {
                width: col.width; height: 34
                Segmented {
                    anchors.verticalCenter: parent.verticalCenter
                    model: [{ label: "moll", value: true }, { label: "dur", value: false }]
                    value: Studio.keyMinor
                    onPicked: (v) => { Studio.remember(); Studio.keyMinor = v; }
                }
                Pill {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    height: 30; text: "Jak w 808"; icon: "music"
                    visible: Studio.tracks.some(t => t.kind === "bass")
                    tip: "Tonacja autotune taka jak basu 808"
                    onClicked: { Studio.remember(); Studio.keyFrom808(); }
                }
            }
            Item {
                width: col.width; height: 34
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Echo co"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                Segmented {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    model: [{ label: "1/4", value: "1/4" }, { label: "1/8", value: "1/8" }, { label: "1/8 z kropką", value: "3/16" }]
                    value: Studio.echoTime
                    onPicked: (v) => Studio.echoTime = v
                }
            }
            FxSlider {
                label: "Wielkość sali (pogłos)"; from: 0; to: 1
                value: Studio.reverbSize
                shown: value < 0.3 ? "pokój" : value < 0.7 ? "sala" : "hala"
                onMoved: (v) => Studio.reverbSize = v
            }
            FxSlider {
                label: "Głośność metronomu"; from: 0; to: 1
                value: Studio.clickVolume; shown: insp.pct(value)
                onMoved: (v) => Studio.clickVolume = v
            }
        }
    }

    component Caption: Text {
        color: Theme.text2
        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.6
    }

    component Check: HoverButton {
        id: ck
        property string text
        property bool on
        signal toggled()
        width: col.width; height: 30; radius: 8
        onClicked: ck.toggled()
        Rectangle {
            x: 4; anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18; radius: 5
            color: ck.on ? Theme.accent : "transparent"
            border.width: ck.on ? 0 : 1.5; border.color: Theme.text2
            Icon { visible: ck.on; anchors.centerIn: parent; d: Icons.check; size: 12; stroke: 2.4; color: "white" }
        }
        Text { x: 30; width: parent.width - 34; anchors.verticalCenter: parent.verticalCenter; text: ck.text; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
    }

    // Suwak z podpisem i wartością. centered — pasek od zera (np. korektor); dwuklik wraca do zera
    component FxSlider: Item {
        id: fs
        property string label
        property string hint
        property string shown
        property real from: 0
        property real to: 1
        property real value: 0
        property real origin: from < 0 ? 0 : from
        property bool centered: false
        signal moved(real v)
        width: col.width; height: hint ? 52 : 38
        readonly property real frac: (Math.max(from, Math.min(to, value)) - from) / Math.max(1e-6, to - from)
        readonly property real originFrac: (origin - from) / Math.max(1e-6, to - from)
        Text { text: fs.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
        Text { anchors.right: parent.right; text: fs.shown; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 } }
        Text { visible: fs.hint !== ""; y: 16; text: fs.hint; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
        Item {
            id: bar
            y: fs.hint ? 36 : 22
            width: parent.width; height: 16
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Theme.fill }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: parent.width * Math.min(fs.frac, fs.centered ? fs.originFrac : 0)
                width: parent.width * Math.abs(fs.frac - (fs.centered ? fs.originFrac : 0))
                height: 4; radius: 2
                color: area.containsMouse || area.pressed ? Theme.accent : Theme.text2
            }
            Rectangle { visible: fs.centered; x: parent.width * fs.originFrac - 0.5; anchors.verticalCenter: parent.verticalCenter; width: 1; height: 10; color: Theme.text2; opacity: 0.6 }
            Rectangle {
                x: parent.width * fs.frac - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 14; height: 14; radius: 7
                color: "white"; border.width: 1; border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(0, 0, 0, 0.2)
            }
            MouseArea {
                id: area
                anchors.fill: parent; anchors.margins: -4
                hoverEnabled: true
                function at(x) { return fs.from + Math.max(0, Math.min(1, (x - 4) / bar.width)) * (fs.to - fs.from); }
                onPressed: (e) => { Studio.remember(); fs.moved(at(e.x)); }
                onPositionChanged: (e) => { if (pressed) fs.moved(at(e.x)); }
                onDoubleClicked: fs.moved(fs.origin)
                onWheel: (w) => fs.moved(Math.max(fs.from, Math.min(fs.to, fs.value + (w.angleDelta.y > 0 ? 1 : -1) * (fs.to - fs.from) / 40)))
            }
        }
    }
}
