pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Studio

// Beat Maker: siatka szesnastek dla ścieżki bitu (perkusja) albo 808 (mini-pianino w skali molowej).
// Klik włącza krok, przeciągnięcie maluje kilka naraz; prawy klik na hi-hacie — rolka ×2/×3/×4,
// na innym instrumencie — ciche uderzenie. Zmiana od razu przelicza pętlę (słychać przy odtwarzaniu).
Item {
    id: pe
    property int track: -1
    property var colors: []
    signal closeRequested()

    readonly property var tr: Studio.tracks[track] || null
    readonly property bool bass: !!tr && tr.kind === "bass"
    readonly property bool keys: !!tr && tr.kind === "keys"
    signal chordMenuRequested(int index, real x, real y)
    readonly property int playBar: Studio.playing && pat && pat.chords ? Math.floor(Math.max(0, Studio.position) / (stepSec * 16)) % pat.chords.length : -1
    property var pat: null                       // lokalna kopia wzoru (edycja przed zapisaniem)
    readonly property int steps: pat ? (pat.bars || 2) * 16 : 32
    readonly property var rowIds: ["kick", "snare", "clap", "hat", "openhat", "perc"]
    readonly property var rowLabels: ({ kick: "Stopa", snare: "Werbel", clap: "Klaśnięcie", hat: "Hi-hat", openhat: "Otwarty hi-hat", perc: "Perkusjonalia" })
    readonly property int degrees: 15
    readonly property real stepSec: 60 / Studio.bpm / 4
    readonly property int playStep: Studio.playing ? Math.floor(Math.max(0, Studio.position) / stepSec) % steps : -1
    readonly property color tint: tr && colors.length ? colors[tr.color % colors.length] : Theme.accent

    function reload() { pat = tr ? JSON.parse(JSON.stringify(tr.pattern)) : null; }
    onTrChanged: reload()
    Component.onCompleted: reload()
    Connections { target: Studio; function onTracksChanged() { if (!grid.painting) pe.reload(); } }
    function commit() { Studio.setPattern(track, pat); }
    function setKey(key, value) { const p = JSON.parse(JSON.stringify(pat)); p[key] = value; pat = p; commit(); }
    // Zmiana liczby taktów: nowe takty powtarzają pierwszy
    function setBars(bars) {
        const p = JSON.parse(JSON.stringify(pat));
        const n = bars * 16, old = (p.bars || 2) * 16;
        const fit = (a, fill) => { const r = []; for (let i = 0; i < n; ++i) r.push(i < old ? a[i] : (a[i % old] !== undefined ? a[i % old] : fill)); return r; };
        if (bass) p.notes = fit(p.notes, -1);
        else { for (const k of rowIds) p.rows[k] = fit(p.rows[k], 0); p.rolls = fit(p.rolls, 1); }
        p.bars = bars;
        pat = p;
        commit();
    }
    function clear() {
        const p = JSON.parse(JSON.stringify(pat));
        if (bass) p.notes = p.notes.map(() => -1);
        else { for (const k of rowIds) p.rows[k] = p.rows[k].map(() => 0); p.rolls = p.rolls.map(() => 1); }
        pat = p;
        commit();
    }

    // Pełne tło: pasy osi czasu nie prześwitują (ikony wektorowe nie zawsze są przycinane)
    Rectangle { anchors.fill: parent; color: Theme.dark ? "#16171C" : "#F1F2F6" }
    Rectangle { width: parent.width; height: 1; color: Theme.line }

    // ——— Pasek: zestaw, wzór gatunku, takty, swing / tonacja ———
    Item {
        id: bar
        width: parent.width; height: 52
        Row {
            x: 16; anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 34; height: 34; radius: 10
                color: pe.tint
                Text { anchors.centerIn: parent; text: pe.bass ? "808" : pe.keys ? "♪" : "BIT"; color: "white"; font.family: Theme.font; font.pixelSize: pe.keys ? 17 : 11; font.weight: Font.Bold }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text { text: pe.tr ? pe.tr.name : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Bold }
                Text { text: pe.bass ? "Bas 808 — kliknij nutę w kolumnie" : pe.keys ? "Akordy w tonacji " + Studio.keyName : "Beat Maker — kliknij albo maluj kroki"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
            }
            Item { width: 8; height: 1 }
            Segmented {
                visible: !pe.keys
                anchors.verticalCenter: parent.verticalCenter
                model: Studio.kits.map(k => ({ label: k.label, value: k.id }))
                value: pe.pat ? pe.pat.kit : ""
                onPicked: (v) => pe.setKey("kit", v)
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Pill { height: 30; text: "Wzór…"; icon: "sparkle"; tip: "Wstaw gotowy wzór gatunku"; onClicked: { const p = mapToItem(pe, 0, height + 4); pe.genreMenu(p.x, p.y); } }
            Pill { visible: !pe.keys; height: 30; text: "Wyczyść"; icon: "trash"; onClicked: pe.clear() }
            Pill { visible: pe.keys; height: 30; text: "Zamień na nuty"; icon: "pencil"; tip: "Przenieś akordy do piano rolla i zmieniaj pojedyncze nuty"; onClicked: Studio.chordsToNotes(pe.track) }
            HoverButton {
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30; radius: 15
                onClicked: pe.closeRequested()
                Icon { anchors.centerIn: parent; d: Icons.close; size: 13; stroke: 2; color: Theme.text2 }
            }
        }
    }
    signal genreMenuRequested(real x, real y)
    function genreMenu(x, y) { genreMenuRequested(x, y); }

    // ——— Akordy: brzmienie, rytm, oktawa, progresja i akord na każdy takt ———
    Column {
        id: keysPane
        visible: pe.keys
        x: 16; y: bar.height
        width: parent.width - 32
        spacing: 12
        Flow {
            width: parent.width
            spacing: 6
            Repeater {
                model: Studio.instruments
                delegate: Chip {
                    required property var modelData
                    text: modelData.label; tip: modelData.hint
                    on: !!pe.pat && pe.pat.instrument === modelData.id
                    onClicked: pe.setKey("instrument", modelData.id)
                }
            }
        }
        Row {
            spacing: 14
            height: 34
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Rytm"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
            Segmented {
                anchors.verticalCenter: parent.verticalCenter
                model: Studio.rhythms.map(r => ({ label: r.label, value: r.id }))
                value: pe.pat ? pe.pat.rhythm || "" : ""
                onPicked: (v) => pe.setKey("rhythm", v)
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Oktawa"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Pill { height: 28; icon: "minus"; onClicked: pe.setKey("octave", Math.max(2, (pe.pat.octave || 4) - 1)) }
                Text { anchors.verticalCenter: parent.verticalCenter; width: 24; horizontalAlignment: Text.AlignHCenter; text: pe.pat ? pe.pat.octave || 4 : ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                Pill { height: 28; icon: "plus"; onClicked: pe.setKey("octave", Math.min(6, (pe.pat.octave || 4) + 1)) }
            }
            Chip { anchors.verticalCenter: parent.verticalCenter; text: "Septymy (bogatsze akordy)"; on: !!pe.pat && !!pe.pat.seventh; onClicked: pe.setKey("seventh", !pe.pat.seventh) }
        }
        Row {
            spacing: 6
            Text { anchors.verticalCenter: parent.verticalCenter; rightPadding: 8; text: "Progresja"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
            Repeater {
                model: Studio.progressions
                delegate: Chip {
                    required property var modelData
                    text: modelData.label; tip: modelData.hint
                    on: !!pe.pat && !!pe.pat.chords && JSON.stringify(pe.pat.chords) === JSON.stringify(modelData.chords)
                    onClicked: pe.setKey("chords", modelData.chords)
                }
            }
        }
        Row {
            spacing: 10
            Repeater {
                model: pe.pat && pe.pat.chords ? pe.pat.chords.length : 0
                delegate: HoverButton {
                    id: tile
                    required property int index
                    readonly property int degree: pe.pat && pe.pat.chords ? pe.pat.chords[index] || 0 : 0
                    width: 128; height: 76; radius: 14
                    baseColor: index === pe.playBar ? Qt.rgba(pe.tint.r, pe.tint.g, pe.tint.b, 0.55) : Qt.rgba(pe.tint.r, pe.tint.g, pe.tint.b, 0.22)
                    border.width: 1; border.color: Qt.rgba(pe.tint.r, pe.tint.g, pe.tint.b, 0.8)
                    onClicked: { const p = mapToItem(pe, 0, height + 4); pe.chordMenuRequested(index, p.x, p.y); }
                    Text { x: 12; y: 8; text: "Takt " + (tile.index + 1); color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
                    Text { x: 12; y: 26; text: Studio.chordName(tile.degree, !!pe.pat && !!pe.pat.seventh); color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold }
                    Text { x: 12; y: 52; text: ["I", "II", "III", "IV", "V", "VI", "VII"][tile.degree] + " stopień"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
                    Icon { anchors.right: parent.right; anchors.rightMargin: 10; y: 10; d: Icons.chevronDown; size: 13; stroke: 2; color: Theme.text2 }
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Pill { height: 30; icon: "plus"; tip: "Dodaj takt"; enabled: !!pe.pat && !!pe.pat.chords && pe.pat.chords.length < 8; onClicked: pe.setKey("chords", pe.pat.chords.concat([pe.pat.chords[pe.pat.chords.length - 1]])) }
                Pill { height: 30; icon: "minus"; tip: "Usuń ostatni takt"; enabled: !!pe.pat && !!pe.pat.chords && pe.pat.chords.length > 1; onClicked: pe.setKey("chords", pe.pat.chords.slice(0, -1)) }
            }
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Akordy są zawsze w tonacji piosenki (" + Studio.keyName + ") — tej samej co 808 i autotune. Tonację zmienisz w panelu po prawej (Projekt)."
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
        }
    }

    component Chip: HoverButton {
        id: chip
        property string text
        property string tip
        property bool on: false
        width: chipText.implicitWidth + 24; height: 30; radius: 15
        baseColor: on ? Theme.accent : Theme.fill
        color: on ? baseColor : (hovered ? Theme.hover : baseColor)
        Text { id: chipText; anchors.centerIn: parent; text: chip.text; color: chip.on ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
        Tip { shown: chip.hovered && chip.tip !== ""; text: chip.tip }
    }

    Row {
        id: opts
        visible: !pe.keys
        x: 16; y: bar.height
        spacing: 14
        height: 34
        Text { anchors.verticalCenter: parent.verticalCenter; text: "Takty"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        Segmented {
            anchors.verticalCenter: parent.verticalCenter
            model: [{ label: "1", value: 1 }, { label: "2", value: 2 }, { label: "4", value: 4 }]
            value: pe.pat ? pe.pat.bars : 2
            onPicked: (v) => pe.setBars(v)
        }
        // Perkusja: swing
        Text { visible: !pe.bass; anchors.verticalCenter: parent.verticalCenter; text: "Swing"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        Segmented {
            visible: !pe.bass
            anchors.verticalCenter: parent.verticalCenter
            model: [{ label: "prosto", value: 0 }, { label: "lekki", value: 0.12 }, { label: "mocny", value: 0.22 }]
            value: pe.pat ? Math.round((pe.pat.swing || 0) * 100) / 100 : 0
            onPicked: (v) => pe.setKey("swing", v)
        }
        // 808: tonacja i ślizg
        Text { visible: pe.bass; anchors.verticalCenter: parent.verticalCenter; text: "Tonacja"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        Row {
            visible: pe.bass
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Pill { height: 28; icon: "minus"; onClicked: pe.setKey("root", ((pe.pat.root || 0) + 11) % 12) }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 64; horizontalAlignment: Text.AlignHCenter
                text: pe.pat ? Studio.noteName(pe.pat.root || 0, 0).replace(/[0-9]/g, "") + "-moll" : ""
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
            }
            Pill { height: 28; icon: "plus"; onClicked: pe.setKey("root", ((pe.pat.root || 0) + 1) % 12) }
        }
        HoverButton {
            visible: pe.bass
            anchors.verticalCenter: parent.verticalCenter
            width: glideRow.implicitWidth + 16; height: 28; radius: 8
            onClicked: pe.setKey("glide", !pe.pat.glide)
            Row {
                id: glideRow
                x: 8; anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18; radius: 5
                    color: !!pe.pat && !!pe.pat.glide ? Theme.accent : "transparent"
                    border.width: !!pe.pat && !!pe.pat.glide ? 0 : 1.5; border.color: Theme.text2
                    Icon { visible: !!pe.pat && !!pe.pat.glide; anchors.centerIn: parent; d: Icons.check; size: 12; stroke: 2.4; color: "white" }
                }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Ślizg między bliskimi nutami"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
            }
        }
        Text {
            visible: !pe.bass
            anchors.verticalCenter: parent.verticalCenter
            text: "Prawy klik: hi-hat — rolka ×2 ×3 ×4, inne — ciche uderzenie"
            color: Theme.text2; opacity: 0.8; font.family: Theme.font; font.pixelSize: 11
        }
    }

    // ——— Siatka ———
    Item {
        id: grid
        visible: !pe.keys
        x: 16; y: opts.y + opts.height + 8
        width: parent.width - 32; height: parent.height - y - 12
        readonly property int labelW: 112
        readonly property int rows: pe.bass ? pe.degrees : pe.rowIds.length
        readonly property real cellW: (width - labelW) / pe.steps
        readonly property real cellH: Math.min(pe.bass ? 22 : 34, height / rows)
        property bool painting: false
        property real paintValue: 0
        property int lastCell: -1

        function cellValue(r, i) {
            if (!pe.pat) return 0;
            // W chwili przełączania ścieżki wzór może być jeszcze innego rodzaju
            if (pe.bass) return pe.pat.notes && pe.pat.notes[i] === (pe.degrees - 1 - r) ? 1 : 0;
            const row = pe.pat.rows ? pe.pat.rows[pe.rowIds[r]] : null;
            return row ? row[i] || 0 : 0;
        }
        function setCell(r, i, v) {
            const p = JSON.parse(JSON.stringify(pe.pat));
            if (pe.bass) p.notes[i] = v > 0 ? pe.degrees - 1 - r : (p.notes[i] === pe.degrees - 1 - r ? -1 : p.notes[i]);
            else p.rows[pe.rowIds[r]][i] = v;
            pe.pat = p;
        }

        Repeater {
            model: grid.rows
            delegate: Item {
                id: rowItem
                required property int index
                y: index * grid.cellH
                width: grid.width; height: grid.cellH
                readonly property int degree: pe.degrees - 1 - index
                MouseArea {
                    width: grid.labelW - 10; height: parent.height
                    cursorShape: Qt.PointingHandCursor
                    onPressed: Studio.previewNote(pe.track, pe.bass ? rowItem.degree : rowItem.index)
                }
                Text {
                    width: grid.labelW - 10; height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: pe.bass ? (pe.pat ? Studio.noteName(pe.pat.root || 0, rowItem.degree) : "") : pe.rowLabels[pe.rowIds[rowItem.index]]
                    elide: Text.ElideRight
                    color: pe.bass && rowItem.degree % 7 === 0 ? Theme.text : Theme.text2
                    font.family: Theme.font; font.pixelSize: pe.bass ? 11 : 12; font.weight: pe.bass && rowItem.degree % 7 === 0 ? Font.DemiBold : Font.Medium
                }
                Repeater {
                    model: pe.steps
                    delegate: Rectangle {
                        id: cell
                        required property int index
                        readonly property real v: grid.cellValue(rowItem.index, index)
                        readonly property int roll: !pe.bass && pe.pat && pe.pat.rolls && pe.rowIds[rowItem.index] === "hat" ? (pe.pat.rolls[index] || 1) : 1
                        x: grid.labelW + index * grid.cellW + 1
                        y: 1
                        width: grid.cellW - 2; height: grid.cellH - 2
                        radius: Math.min(6, height / 3)
                        // Co miarę (4 kroki) jaśniejsze tło — łatwo liczyć
                        color: v > 0 ? Qt.rgba(pe.tint.r, pe.tint.g, pe.tint.b, 0.35 + 0.65 * v)
                             : (Math.floor(index / 4) % 2 === 0 ? Theme.fill : (Theme.dark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.03)))
                        border.width: index === pe.playStep ? 2 : 0
                        border.color: Theme.text
                        Text {
                            visible: cell.roll > 1 && cell.v > 0
                            anchors.centerIn: parent
                            text: "×" + cell.roll
                            color: "white"
                            font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Bold
                        }
                    }
                }
            }
        }

        MouseArea {
            x: grid.labelW; width: grid.width - grid.labelW; height: grid.rows * grid.cellH
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            function cellAt(mx, my) { return { r: Math.floor(my / grid.cellH), i: Math.floor(mx / grid.cellW) }; }
            function valid(c) { return c.r >= 0 && c.r < grid.rows && c.i >= 0 && c.i < pe.steps; }
            onPressed: (e) => {
                const c = cellAt(e.x, e.y);
                if (!valid(c) || !pe.pat) return;
                if (e.button === Qt.RightButton) {
                    const p = JSON.parse(JSON.stringify(pe.pat));
                    if (pe.bass) return;
                    const id = pe.rowIds[c.r];
                    if (id === "hat") {
                        p.rolls[c.i] = (p.rolls[c.i] || 1) % 4 + 1;
                        if (!p.rows.hat[c.i]) p.rows.hat[c.i] = 1;
                    } else {
                        p.rows[id][c.i] = p.rows[id][c.i] > 0.7 ? 0.55 : p.rows[id][c.i] > 0 ? 0 : 0.55;
                    }
                    pe.pat = p;
                    pe.commit();
                    return;
                }
                grid.painting = true;
                grid.paintValue = grid.cellValue(c.r, c.i) > 0 ? 0 : 1;
                if (grid.paintValue > 0) Studio.previewNote(pe.track, pe.bass ? pe.degrees - 1 - c.r : c.r);
                grid.lastCell = c.r * 1000 + c.i;
                grid.setCell(c.r, c.i, grid.paintValue);
            }
            onPositionChanged: (e) => {
                if (!grid.painting) return;
                const c = cellAt(e.x, e.y);
                if (!valid(c) || c.r * 1000 + c.i === grid.lastCell) return;
                grid.lastCell = c.r * 1000 + c.i;
                // 808: malowanie w poziomie po tym samym wierszu, perkusja: dowolnie
                grid.setCell(c.r, c.i, grid.paintValue);
            }
            onReleased: { if (grid.painting) { grid.painting = false; pe.commit(); } }
        }
    }
}
