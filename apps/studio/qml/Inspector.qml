pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Studio

// Panel z prawej w czterech zakładkach: Ścieżka (gotowe brzmienie, korektor, autotune, dynamika, przestrzeń),
// Klip (głośność, narastanie, wyciszanie, pętla), Piosenka (mastering, tonacja, pogłos i echo, metronom)
// i Tekst (pisanie, rymy, czas wersów, prompter).
Item {
    id: insp
    property var colors: []
    // Efekty należą do insertu: zaznaczonego w mikserze, racku albo na ścieżce playlisty
    readonly property int iid: Studio.selectedInsert
    readonly property var mx: Studio.inserts.find((i) => i.id === iid) || ({})
    readonly property var track: mx.id ? ({ name: mx.name, color: mx.color, kind: "audio", beat: false }) : null
    readonly property int ti: mx.track !== undefined ? mx.track : -1
    // Zależność od listy ścieżek musi być użyta, inaczej kompilator QML ją pomija i klip się nie odświeża
    readonly property var cl: Studio.tracks.length >= 0 && Studio.selectedClip > 0 ? Studio.clip(Studio.selectedClip) : null
    readonly property bool hasClip: !!cl && cl.id !== undefined

    function db(v) { return (v > 0 ? "+" : v < 0 ? "−" : "") + Math.abs(v).toFixed(1) + " dB"; }
    function pct(v) { return Math.round(v * 100) + "%"; }
    function sec(v) { return v <= 0.001 ? "brak" : v.toFixed(1).replace(".", ",") + " s"; }

    // Zakładka: ścieżka (brzmienie), klip, piosenka (mastering i ustawienia całego projektu)
    property string page: "track"

    Rectangle { width: 1; height: parent.height; color: Theme.line }

    Item {
        id: tabs
        x: 1; width: parent.width - 1; height: 58
        Segmented {
            anchors.centerIn: parent
            model: [{ label: "Ścieżka", value: "track" }, { label: "Klip", value: "clip" }, { label: "Piosenka", value: "song" }, { label: "Tekst", value: "lyrics" }]
            value: insp.page
            onPicked: (v) => insp.page = v
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line; opacity: 0.6 }
    }

    signal addPluginRequested()

    // Tekst piosenki — własny układ (pole do pisania, lista wersów), bez wspólnego przewijania
    property alias lyrics: lyricsPanel
    Lyrics {
        id: lyricsPanel
        visible: insp.page === "lyrics"
        x: 1; y: tabs.height
        width: parent.width - 1; height: parent.height - y
    }

    Flickable {
        id: flick
        visible: insp.page !== "lyrics"
        x: 1; y: tabs.height
        width: parent.width - 1; height: parent.height - y
        contentHeight: col.height + 30
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Connections { target: insp; function onPageChanged() { flick.contentY = 0; } }

        Column {
            id: col
            x: 14; y: 14
            width: parent.width - 28
            spacing: 12

            // ——————— Ścieżka ———————
            Column {
                width: col.width
                spacing: 12
                visible: insp.page === "track"

                Text {
                    visible: !insp.track
                    width: col.width
                    wrapMode: Text.WordWrap
                    text: "Zaznacz ścieżkę, żeby zmienić jej brzmienie."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                }
                Row {
                    x: 4
                    spacing: 8
                    visible: !!insp.track
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5; color: insp.track && insp.colors.length ? insp.colors[insp.track.color % insp.colors.length] : Theme.accent }
                    Text {
                        width: col.width - 26
                        text: insp.track ? insp.track.name : ""
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold
                    }
                }

                // Zaznaczony klip — skrót do jego ustawień
                HoverButton {
                    visible: insp.hasClip && !!insp.track
                    width: col.width; height: 36; radius: 10
                    baseColor: Theme.fill
                    onClicked: insp.page = "clip"
                    Text {
                        x: 12; width: parent.width - 40; anchors.verticalCenter: parent.verticalCenter
                        text: "Klip: " + (insp.hasClip ? insp.cl.name : "")
                        elide: Text.ElideRight
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                    }
                    Icon { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.chevronRight; size: 14; stroke: 2; color: Theme.text2 }
                }

                Card {
                    visible: !!insp.track
                    title: "Gotowe brzmienie"
                    action: "Bez efektów"
                    onActionClicked: Studio.applyInsertPreset(insp.iid, "none")
                    Repeater {
                        // Najpierw grupa pasująca do ścieżki: wokal przy nagraniu, instrumenty przy bicie i syntezatorach
                        model: insp.track && insp.track.kind !== "audio" ? ["Instrumenty", "Efekty", "Wokal"] : ["Wokal", "Instrumenty", "Efekty"]
                        delegate: Column {
                            id: group
                            required property string modelData
                            width: parent ? parent.width : 0
                            spacing: 6
                            Text { text: group.modelData; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
                            Flow {
                                width: group.width
                                spacing: 6
                                Repeater {
                                    model: Studio.presets.filter(p => p.group === group.modelData)
                                    delegate: Chip {
                                        required property var modelData
                                        label: modelData.label
                                        hint: modelData.hint
                                        on: (insp.mx.preset || "") === modelData.id
                                        onClicked: Studio.applyInsertPreset(insp.iid, modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }

                // Czystość głosu: szum tła (odszumianie nagrań w tle) i syczenie (de-esser na żywo)
                Card {
                    visible: !!insp.track
                    title: "Czystość głosu"
                    Column {
                        visible: insp.ti >= 0            // nagrania są na ścieżkach playlisty
                        width: parent.width
                        spacing: 6
                        Text { text: "Odszumianie"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: Studio.busy ? "Odszumiam… (chwila)" : "Szum mikrofonu, komputera i pokoju — Studio uczy się go z pauz między wersami. Działa też na nowych nagraniach."
                            color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                        }
                        Flow {
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: [{ label: "Wył.", value: 0 }, { label: "Lekko", value: 1 }, { label: "Średnio", value: 2 }, { label: "Mocno", value: 3 }]
                                delegate: Chip {
                                    required property var modelData
                                    label: modelData.label
                                    on: (insp.mx.denoise || 0) === modelData.value
                                    enabled: !Studio.busy && !Studio.recording
                                    onClicked: Studio.denoiseTrack(insp.ti, modelData.value)
                                }
                            }
                        }
                    }
                    FxSlider { label: "De-esser"; hint: "Ścisza syczenie „s”, „sz”, „c”"; from: 0; to: 1; value: insp.mx.deess || 0; shown: insp.pct(value); onMoved: (v) => Studio.setInsertFx(insp.iid, "deess", v) }
                }

                Card {
                    visible: !!insp.track
                    title: "Korektor"
                    FxSlider { label: "Niskie (bas)"; from: -12; to: 12; centered: true; value: insp.mx.eqLow || 0; shown: insp.db(value); onMoved: (v) => Studio.setInsertFx(insp.iid, "eqLow", v) }
                    FxSlider { label: "Średnie (głos)"; from: -12; to: 12; centered: true; value: insp.mx.eqMid || 0; shown: insp.db(value); onMoved: (v) => Studio.setInsertFx(insp.iid, "eqMid", v) }
                    FxSlider { label: "Wysokie (blask)"; from: -12; to: 12; centered: true; value: insp.mx.eqHigh || 0; shown: insp.db(value); onMoved: (v) => Studio.setInsertFx(insp.iid, "eqHigh", v) }
                    Check {
                        text: "Usuń dudnienie (poniżej 80 Hz)"
                        on: !!insp.mx.lowCut
                        onToggled: { Studio.remember(); Studio.setInsertFx(insp.iid, "lowCut", insp.mx.lowCut ? 0 : 1); }
                    }
                }

                // Autotune ma sens przy głosie i instrumentach nagranych; przy syntezatorach tylko, gdy już włączony
                Card {
                    visible: !!insp.track && (insp.track.kind === "audio" || (insp.mx.tune || 0) > 0)
                    title: "Autotune"
                    FxSlider {
                        label: "Korekcja wysokości"
                        hint: "Dociąga głos do tonacji " + Studio.keyName
                        from: 0; to: 1
                        value: insp.mx.tune || 0
                        shown: value < 0.01 ? "wył." : value < 0.4 ? "naturalnie" : value < 0.75 ? "wyraźnie" : "efekt trap"
                        onMoved: (v) => Studio.setInsertFx(insp.iid, "tune", v)
                    }
                    Text {
                        width: parent ? parent.width : 0
                        wrapMode: Text.WordWrap
                        text: "Tonację zmienisz w zakładce Piosenka."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                    }
                }

                Card {
                    visible: !!insp.track
                    title: "Dynamika"
                    FxSlider { label: "Kompresja"; hint: "Wyrównuje ciche i głośne fragmenty"; from: 0; to: 1; value: insp.mx.comp || 0; shown: insp.pct(value); onMoved: (v) => Studio.setInsertFx(insp.iid, "comp", v) }
                    FxSlider { label: "Ciepło / przester"; hint: "Nasycenie — słychać nawet w telefonie"; from: 0; to: 1; value: insp.mx.drive || 0; shown: insp.pct(value); onMoved: (v) => Studio.setInsertFx(insp.iid, "drive", v) }
                }

                Card {
                    visible: !!insp.track
                    title: "Przestrzeń"
                    FxSlider { label: "Pogłos"; hint: "Ile sali słychać wokół ścieżki"; from: 0; to: 1; value: insp.mx.reverb || 0; shown: insp.pct(value); onMoved: (v) => Studio.setInsertFx(insp.iid, "reverb", v) }
                    FxSlider { label: "Echo"; hint: "Powtórzenia co " + Studio.echoTime.replace("3/16", "1/8 z kropką"); from: 0; to: 1; value: insp.mx.echo || 0; shown: insp.pct(value); onMoved: (v) => Studio.setInsertFx(insp.iid, "echo", v) }
                    FxSlider { label: "Sztuczny dubel"; hint: "Dwie kopie głosu po bokach, jak nagrane drugi raz — szerzej i grubiej"; from: 0; to: 1; value: insp.mx["double"] || 0; shown: insp.pct(value); onMoved: (v) => Studio.setInsertFx(insp.iid, "double", v) }
                }

                // Wtyczki VST3: po efektach Studia, w kolejności od góry
                Card {
                    visible: !!insp.track
                    title: "Wtyczki"
                    action: "Dodaj"
                    onActionClicked: insp.addPluginRequested()
                    Text {
                        visible: (insp.mx.plugins || []).length === 0
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Efekty VST3 zainstalowane w systemie. Wtyczka otwiera się we własnym oknie."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                    }
                    Repeater {
                        model: insp.mx.plugins || []
                        delegate: Rectangle {
                            id: slotRow
                            required property var modelData
                            width: parent ? parent.width : 0; height: 38; radius: 9
                            color: Theme.fill
                            opacity: modelData.bypass || modelData.missing ? 0.55 : 1
                            HoverButton {
                                x: 2; width: parent.width - 66; height: parent.height; radius: 8
                                enabled: !slotRow.modelData.missing
                                onClicked: Studio.openPlugin(insp.iid, slotRow.modelData.id)
                                Text {
                                    x: 8; width: parent.width - 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: slotRow.modelData.name + (slotRow.modelData.missing ? " — brak wtyczki" : "")
                                    elide: Text.ElideRight
                                    color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                                }
                                Tip { shown: parent.hovered; text: "Otwórz okno wtyczki" }
                            }
                            HoverButton {
                                x: parent.width - 62; anchors.verticalCenter: parent.verticalCenter
                                width: 28; height: 28; radius: 7
                                onClicked: Studio.setPluginBypass(insp.iid, slotRow.modelData.id, !slotRow.modelData.bypass)
                                Icon { anchors.centerIn: parent; d: Icons.power; size: 14; stroke: 2; color: slotRow.modelData.bypass ? Theme.text2 : Theme.accentText }
                                Tip { shown: parent.hovered; text: slotRow.modelData.bypass ? "Włącz wtyczkę" : "Pomiń wtyczkę" }
                            }
                            HoverButton {
                                x: parent.width - 32; anchors.verticalCenter: parent.verticalCenter
                                width: 28; height: 28; radius: 7
                                onClicked: Studio.removePlugin(insp.iid, slotRow.modelData.id)
                                Icon { anchors.centerIn: parent; d: Icons.close; size: 14; stroke: 2; color: Theme.text2 }
                                Tip { shown: parent.hovered; text: "Usuń wtyczkę ze ścieżki" }
                            }
                        }
                    }
                }
            }

            // ——————— Klip ———————
            Column {
                width: col.width
                spacing: 12
                visible: insp.page === "clip"

                Text {
                    visible: !insp.hasClip
                    width: col.width
                    wrapMode: Text.WordWrap
                    text: "Kliknij klip na osi czasu, żeby zmienić jego głośność, narastanie i wyciszanie."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                }
                Text {
                    visible: insp.hasClip
                    x: 4; width: col.width - 4
                    text: insp.hasClip ? insp.cl.name : ""
                    elide: Text.ElideRight
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold
                }
                Card {
                    visible: insp.hasClip && (insp.cl.takes || 0) > 1
                    title: "Podejścia"
                    hint: "Nagrane w pętli, jedno po drugim. Podziel klip (S), żeby z każdego kawałka wziąć inne podejście."
                    Flow {
                        width: parent ? parent.width : 0
                        spacing: 6
                        Repeater {
                            model: insp.hasClip ? (insp.cl.takes || 0) : 0
                            delegate: Chip {
                                required property int index
                                label: String(index + 1)
                                hint: (insp.cl.takeOk || [])[index] ? "Podejście " + (index + 1) : "Podejście " + (index + 1) + " nie obejmuje tego kawałka"
                                on: insp.cl.take === index
                                opacity: (insp.cl.takeOk || [])[index] ? 1 : 0.4
                                onClicked: Studio.setClipTake(insp.cl.id, index)
                            }
                        }
                    }
                }
                Card {
                    visible: insp.hasClip
                    title: "Głośność"
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
                }
                Card {
                    visible: insp.hasClip
                    title: "Powtarzanie"
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
            }

            // ——————— Piosenka ———————
            Column {
                width: col.width
                spacing: 12
                visible: insp.page === "song"

                Card {
                    title: "Mastering"
                    hint: "Ostatni szlif całej piosenki: brzmienie, sklejenie i głośność jak w radiu."
                    Flow {
                        width: parent ? parent.width : 0
                        spacing: 6
                        Repeater {
                            model: Studio.masteringPresets
                            delegate: Chip {
                                required property var modelData
                                label: modelData.label
                                hint: modelData.hint
                                on: (Studio.mastering.preset || "none") === modelData.id
                                onClicked: Studio.applyMastering(modelData.id)
                            }
                        }
                    }
                    FxSlider { label: "Dół"; from: -12; to: 12; centered: true; value: Studio.mastering.eqLow; shown: insp.db(value); onMoved: (v) => Studio.setMastering("eqLow", v) }
                    FxSlider { label: "Góra"; from: -12; to: 12; centered: true; value: Studio.mastering.eqHigh; shown: insp.db(value); onMoved: (v) => Studio.setMastering("eqHigh", v) }
                    FxSlider { label: "Sklejenie (kompresja)"; from: 0; to: 1; value: Studio.mastering.comp; shown: insp.pct(value); onMoved: (v) => Studio.setMastering("comp", v) }
                    FxSlider { label: "Szerokość stereo"; from: 0; to: 2; origin: 1; centered: true; value: Studio.mastering.width; shown: Math.round(value * 100) + "%"; onMoved: (v) => Studio.setMastering("width", v) }
                    FxSlider { label: "Głośność (dociśnięcie)"; from: 0; to: 12; value: Studio.mastering.drive; shown: "+" + value.toFixed(1) + " dB"; onMoved: (v) => Studio.setMastering("drive", v) }
                }

                Card {
                    title: "Tonacja"
                    hint: "Do niej autotune dociąga głos, a piano roll podpowiada nuty."
                    Item {
                        width: parent ? parent.width : 0; height: 34
                        Segmented {
                            anchors.verticalCenter: parent.verticalCenter
                            model: [{ label: "moll", value: true }, { label: "dur", value: false }]
                            value: Studio.keyMinor
                            onPicked: (v) => { Studio.remember(); Studio.keyMinor = v; }
                        }
                        Row {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Pill { height: 28; icon: "minus"; onClicked: { Studio.remember(); Studio.keyRoot = (Studio.keyRoot + 11) % 12; } }
                            Text { anchors.verticalCenter: parent.verticalCenter; width: 64; horizontalAlignment: Text.AlignHCenter; text: Studio.keyName; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Pill { height: 28; icon: "plus"; onClicked: { Studio.remember(); Studio.keyRoot = (Studio.keyRoot + 1) % 12; } }
                        }
                    }
                }

                Card {
                    title: "Pogłos i echo"
                    hint: "Wspólne dla wszystkich ścieżek — ile ich słychać, ustawiasz przy ścieżce."
                    FxSlider {
                        label: "Wielkość sali"; from: 0; to: 1
                        value: Studio.reverbSize
                        shown: value < 0.3 ? "pokój" : value < 0.7 ? "sala" : "hala"
                        onMoved: (v) => Studio.reverbSize = v
                    }
                    Item {
                        width: parent ? parent.width : 0; height: 34
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Echo co"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                        Segmented {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            model: [{ label: "1/4", value: "1/4" }, { label: "1/8", value: "1/8" }, { label: "1/8.", value: "3/16" }]
                            value: Studio.echoTime
                            onPicked: (v) => Studio.echoTime = v
                        }
                    }
                }

                Card {
                    title: "Metronom"
                    FxSlider {
                        label: "Głośność metronomu"; from: 0; to: 1
                        value: Studio.clickVolume; shown: insp.pct(value)
                        onMoved: (v) => Studio.clickVolume = v
                    }
                }
            }
        }
    }

    // Grupa ustawień na lekkim tle z tytułem (i opcjonalnym przyciskiem z prawej)
    component Card: Rectangle {
        id: card
        property string title
        property string hint
        property string action
        signal actionClicked()
        default property alias content: body.data
        width: col.width; height: cardCol.height + 26; radius: 12
        color: Theme.pane
        border.width: 1; border.color: Theme.line
        Column {
            id: cardCol
            x: 12; y: 12
            width: parent.width - 24
            spacing: 10
            Item {
                width: parent.width; height: 20
                Text { anchors.verticalCenter: parent.verticalCenter; text: card.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold }
                HoverButton {
                    visible: card.action !== ""
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: actText.implicitWidth + 16; height: 24; radius: 8
                    onClicked: card.actionClicked()
                    Text { id: actText; anchors.centerIn: parent; text: card.action; color: Theme.accentText; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }
                }
            }
            Text {
                visible: card.hint !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: card.hint
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
            }
            Column { id: body; width: parent.width; spacing: 8 }
        }
    }

    component Chip: HoverButton {
        id: chip
        property string label
        property string hint
        property bool on
        width: chipText.implicitWidth + 22; height: 28; radius: 8
        baseColor: on ? Theme.accent : Theme.fill
        color: on ? baseColor : (hovered ? Theme.hover : baseColor)
        Text { id: chipText; anchors.centerIn: parent; text: chip.label; color: chip.on ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
        Tip { shown: chip.hovered && chip.hint !== ""; text: chip.hint }
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
        width: parent ? parent.width : 0; height: 30; radius: 8
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
        width: parent ? parent.width : 0; height: hint ? 52 : 38
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
