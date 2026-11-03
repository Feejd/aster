pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Dialogs
import Aster.Ui
import Aster.Studio

// Studio Aster: proste studio nagrań dla amatorów. Na górze transport (początek, odtwórz, nagraj), licznik
// taktów, tempo i metrum, metronom i odliczanie; pod spodem ścieżki z klipami na siatce taktów; na dole mikser.
Window {
    id: win
    width: 1280 + 2 * m
    height: 800 + 2 * m
    minimumWidth: 1040 + 2 * m
    minimumHeight: 560 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: Studio.open ? Studio.name + (Studio.dirty ? " •" : "") + " — Studio" : "Studio"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: maxed ? 0 : 24
    // Kolory ścieżek (indeks zapisany w projekcie)
    readonly property var trackColors: ["#FF6B6B", "#FFA94D", "#F5C542", "#51CF66", "#22B8CF", "#4D8BF7", "#9775FA", "#F06595"]
    property bool showMixer: false
    property bool showInspector: true
    property int editTrack: -1                  // ścieżka otwarta w Beat Makerze (-1 — zamknięty)
    readonly property bool textTyping: activeFocusItem instanceof TextInput
    // Litery są zajęte przez wpisywanie tekstu albo granie na klawiaturze w piano rollu
    readonly property bool typing: textTyping || (pianoRoll.visible && pianoRoll.keysActive)

    onClosing: Studio.closeProject()
    Component.onCompleted: effectsTimer.restart()

    // Klawiatura MIDI: do otwartego piano rolla, a bez niego — odsłuch na zaznaczonej (albo pierwszej) ścieżce z nutami
    property bool midiHintShown: false
    function midiTrack() {
        const t = Studio.tracks;
        if (t[Studio.selectedTrack] && (t[Studio.selectedTrack].kind === "melody" || t[Studio.selectedTrack].kind === "keys")) return Studio.selectedTrack;
        for (let i = 0; i < t.length; ++i) if (t[i].kind === "melody" || t[i].kind === "keys") return i;
        return -1;
    }
    Connections {
        target: Studio
        function onMidiNote(pitch, velocity, on) {
            if (!Studio.open) return;
            if (pianoRoll.visible) { if (on) pianoRoll.midiDown(pitch, velocity); else pianoRoll.midiUp(pitch); return; }
            if (!on) { Studio.liveNoteOff(pitch); return; }
            const i = win.midiTrack();
            if (i >= 0) Studio.liveNoteOn(i, pitch, velocity / 127);
            else if (!win.midiHintShown) { win.midiHintShown = true; win.toast("Dodaj ścieżkę Melodia, żeby grać i nagrywać z klawiatury MIDI"); }
        }
        function onMidiDevicesChanged() { if (Studio.midiDevices.length) win.toast("Podłączono klawiaturę MIDI: " + Studio.midiDevices.join(", ")); }
    }
    Connections {
        target: Studio
        function onMessage(text) { win.toast(text); console.warn(text); }
        function onExportFinished(ok, path, error) {
            exportSheet.close();
            if (ok) win.toast("Zapisano „" + path.split("/").pop() + "”", "Pokaż w folderze", () => Studio.showInFolder(path));
            else if (error) win.toast(error);
        }
    }

    // ——— Okna wyboru plików ———
    FolderDialog {
        id: openDialog
        title: "Otwórz projekt Studia"
        currentFolder: "file://" + Studio.projectsFolder
        onAccepted: Studio.openProject(String(selectedFolder))
    }
    FileDialog {
        id: bundleDialog
        title: "Otwórz paczkę projektu"
        nameFilters: ["Paczka projektu Studia (*.zip)"]
        onAccepted: Studio.openProject(String(selectedFile))
    }
    FileDialog {
        id: importDialog
        title: "Dodaj dźwięk do projektu"
        fileMode: FileDialog.OpenFiles
        nameFilters: ["Pliki dźwiękowe (*.wav *.flac *.mp3 *.ogg *.oga *.opus *.aiff *.aif)", "Wszystkie pliki (*)"]
        onAccepted: Studio.importFiles(selectedFiles, Studio.selectedTrack, Studio.position)
    }

    // ——— Skróty ———
    Shortcut { sequences: ["Space"]; enabled: Studio.open && !win.textTyping; onActivated: Studio.toggle() }
    Shortcut { sequences: ["R"]; enabled: Studio.open && !win.typing; onActivated: Studio.record() }
    Shortcut { sequences: ["Return", "Home"]; enabled: Studio.open && !win.typing; onActivated: Studio.seek(0) }
    Shortcut { sequences: ["K"]; enabled: Studio.open && !win.typing; onActivated: Studio.metronome = !Studio.metronome }
    Shortcut { sequences: ["X"]; enabled: Studio.open && !win.typing; onActivated: win.showMixer = !win.showMixer }
    Shortcut { sequences: ["E"]; enabled: Studio.open && !win.typing; onActivated: win.showInspector = !win.showInspector }
    Shortcut { sequences: ["C"]; enabled: Studio.open && !win.typing; onActivated: Studio.cycle = !Studio.cycle }
    Shortcut { sequences: ["M"]; enabled: Studio.open && !win.typing && Studio.tracks.length > 0; onActivated: Studio.setTrackMute(Studio.selectedTrack, !Studio.mix[Studio.selectedTrack].mute) }
    Shortcut { sequences: ["S"]; enabled: Studio.open && !win.typing && Studio.selectedClip > 0; onActivated: { if (!Studio.splitClip(Studio.selectedClip, Studio.position)) win.toast("Ustaw głowicę na zaznaczonym klipie, żeby go podzielić"); } }
    Shortcut { sequences: ["L"]; enabled: Studio.open && !win.typing && Studio.selectedClip > 0; onActivated: Studio.setClipLoop(Studio.selectedClip, !Studio.clip(Studio.selectedClip).loop) }
    Shortcut { sequences: ["Ctrl+D"]; enabled: Studio.open && Studio.selectedClip > 0; onActivated: Studio.duplicateClip(Studio.selectedClip) }
    Shortcut { sequences: ["Delete", "Backspace"]; enabled: Studio.open && !win.typing && Studio.selectedClip > 0; onActivated: Studio.removeClip(Studio.selectedClip) }
    Shortcut { sequences: [StandardKey.Undo]; enabled: Studio.open && !win.typing; onActivated: Studio.undo() }
    Shortcut { sequences: [StandardKey.Redo, "Ctrl+Shift+Z"]; enabled: Studio.open && !win.typing; onActivated: Studio.redo() }
    Shortcut { sequences: [StandardKey.Save]; enabled: Studio.open; onActivated: { if (Studio.save()) win.toast("Projekt zapisany"); } }
    Shortcut { sequences: ["Ctrl+E"]; enabled: Studio.open; onActivated: exportSheet.open() }
    Shortcut { sequences: ["Ctrl+T"]; enabled: Studio.open; onActivated: Studio.addTrack() }
    Shortcut { sequences: ["Ctrl+I"]; enabled: Studio.open; onActivated: importDialog.open() }
    Shortcut { sequences: ["Ctrl+N"]; onActivated: win.newProject() }
    Shortcut { sequences: [StandardKey.Open]; onActivated: openDialog.open() }
    Shortcut { sequences: [StandardKey.ZoomIn, "Ctrl+="]; enabled: Studio.open; onActivated: timeline.zoom(1.25, timeline.viewW / 2) }
    Shortcut { sequences: [StandardKey.ZoomOut]; enabled: Studio.open; onActivated: timeline.zoom(0.8, timeline.viewW / 2) }

    function newProject(genre) {
        newName.text = Studio.suggestName();
        newSheet.template = genre || "";
        const g = Studio.genres.find(x => x.id === newSheet.template);
        newSheet.bpm = g ? g.bpm : 100;
        newSheet.beats = 4;
        newSheet.open();
        newName.input.forceActiveFocus();
        newName.input.selectAll();
    }

    // Do testów (ASTER_OPEN, kroki po „;”): new | demo | loop | split | mixer | seek:s | export:format | exportSheet
    // | audio | tempo | newSheet | menu | vol:ścieżka:dB | pan:ścieżka:p | mute:ścieżka | open:folder
    // | play | stop | rec | arm:ścieżka | input:węzeł | output:węzeł | save
    function testOpen(what) {
        const clips = (i) => Studio.tracks[i] ? Studio.tracks[i].clips : [];
        if (what === "new") Studio.newProject("Pierwsza piosenka", 96, 4);
        else if (what.startsWith("newp:")) Studio.newProject(what.substring(5), 96, 4);
        else if (what.startsWith("fx:")) { const a = what.split(":"); Studio.setTrackFx(Number(a[1]), a[2], Number(a[3])); }
        else if (what.startsWith("import:")) { const a = what.split(":"); Studio.importFiles([a[2]], Number(a[1]), 0); }
        else if (what.startsWith("add:")) Studio.addPatternTrack(what.substring(4), "trap");
        else if (what.startsWith("pv:")) { const a = what.split(":"); Studio.previewNote(Number(a[1]), Number(a[2])); }
        else if (what.startsWith("kd:")) pianoRoll.keyDown(what.substring(3));
        else if (what.startsWith("ku:")) pianoRoll.keyUp(what.substring(3));
        else if (what === "recNotes") pianoRoll.recNotes = true;
        else if (what === "shareSheet") shareSheet.start();
        else if (what === "shareSong") Studio.shareSong("Nocna jazda", "Dominik");
        else if (what === "shareProject") { shareSheet.kind = "project"; Studio.shareProject(); }
        else if (what.startsWith("midi:")) { const a = what.split(":"); Studio.simulateMidi(Number(a[1]), Number(a[2])); }
        else if (what.startsWith("toNotes:")) Studio.chordsToNotes(Number(what.substring(8)));
        else if (what.startsWith("edit:")) editTrack = Number(what.substring(5));
        else if (what.startsWith("tpl:")) Studio.newProject("Szablon " + what.substring(4), 100, 4, what.substring(4));
        else if (what === "demo") {
            const dir = "/root/Muzyka/";
            Studio.importFiles([dir + "Neon Bałtyk/Miejskie Światła/01 Tramwaj nr 4.flac"], 0, 0);
            Studio.importFiles([dir + "Anna Kowalczyk/Cisza/02 Kawa.opus"], 1, timeline.barSec * 2);
            Studio.importFiles([dir + "nagranie_dyktafon_0412.mp3"], -1, timeline.barSec * 4);
        }
        else if (what === "demo2") {
            // Własne próbki testowe (generowane w kontenerze): melodia, bas (MP3), perkusja (OGG)
            const dir = "/tmp/studio-demo/";
            Studio.importFiles([dir + "Melodia.wav"], 0, timeline.barSec * 2);
            Studio.importFiles([dir + "Bas.mp3"], 1, 0);
            Studio.importFiles([dir + "Perkusja.ogg"], -1, 0);
        }
        else if (what === "loops") {
            for (let i of [1, 2]) {
                const c = clips(i)[0];
                Studio.setClipLoop(c.id, true);
                Studio.trimClipEnd(c.id, c.start + timeline.barSec * 10);
            }
            Studio.setTrackVolume(1, -3);
            Studio.setTrackPan(2, -0.25);
            Studio.setTrackPan(0, 0.2);
            Studio.selectedClip = clips(0)[0].id;
        }
        else if (what === "loop") {
            const c = clips(2)[0];
            Studio.trimClipEnd(c.id, c.start + timeline.barSec * 2);
            Studio.setClipLoop(c.id, true);
            Studio.trimClipEnd(c.id, c.start + timeline.barSec * 8);
            Studio.selectedClip = c.id;
        }
        else if (what === "split") { const c = clips(0)[0]; Studio.splitClip(c.id, c.start + timeline.barSec * 6); }
        else if (what === "mixer") showMixer = true;
        else if (what.startsWith("seek:")) Studio.seek(Number(what.substring(5)));
        else if (what.startsWith("export:")) Studio.exportMix(what.substring(7));
        else if (what === "exportSheet") exportSheet.open();
        else if (what === "audio") audioSheet.open();
        else if (what === "tempo") tempoSheet.open();
        else if (what === "newSheet") newProject();
        else if (what === "menu") { const c = clips(1)[0]; clipMenu(c, 1, timeline, timeline.headerW + c.start * timeline.pps - timeline.scrollX + 40, 160, c.start + 1); }
        else if (what.startsWith("vol:")) { const a = what.split(":"); Studio.setTrackVolume(Number(a[1]), Number(a[2])); }
        else if (what.startsWith("pan:")) { const a = what.split(":"); Studio.setTrackPan(Number(a[1]), Number(a[2])); }
        else if (what.startsWith("mute:")) Studio.setTrackMute(Number(what.substring(5)), true);
        else if (what.startsWith("open:")) Studio.openProject(what.substring(5));
        else if (what === "zoomOut") timeline.zoom(0.6, 0);
        else if (what === "play") Studio.play();
        else if (what === "stop") Studio.stop();
        else if (what === "rec") Studio.record();
        else if (what.startsWith("arm:")) Studio.setTrackArmed(Number(what.substring(4)), true);
        else if (what.startsWith("input:")) Studio.input = what.substring(6);
        else if (what.startsWith("output:")) Studio.output = what.substring(7);
        else if (what === "save") Studio.save();
        else if (what === "close") Studio.closeProject();
        else if (what.startsWith("preset:")) { const a = what.split(":"); Studio.applyPreset(Number(a[1]), a[2]); }
        else if (what.startsWith("fade:")) { const a = what.split(":"); const c = clips(Number(a[1]))[0]; Studio.setClipFades(c.id, Number(a[2]), Number(a[3])); Studio.selectedClip = c.id; }
        else if (what.startsWith("cycle:")) { const a = what.split(":"); Studio.setCycle(Number(a[1]), Number(a[2])); }
        else if (what.startsWith("select:")) Studio.selectedTrack = Number(what.substring(7));
        else if (what === "inspectorOff") showInspector = false;
        else if (what === "dbgpos") console.warn("POS", Studio.position.toFixed(2), Studio.playing);
        else if (what === "dbg") console.warn("STUDIO", inspector.hasClip, JSON.stringify(inspector.cl), Studio.selectedClip, JSON.stringify(Studio.clip(Studio.selectedClip)));
    }

    // ——— Menu ———
    function clipMenu(c, track, item, x, y, at) {
        Studio.selectedClip = c.id;
        menu.clipId = c.id;
        menu.at = at;
        const p = item.mapToItem(frame, x, y);
        menu.openAt(p.x, p.y, [
            { label: "Podziel w tym miejscu", icon: "scissors", action: "split" },
            { label: "Podziel na głowicy", icon: "scissors", shortcut: "S", action: "splitHead" },
            { label: c.loop ? "Wyłącz pętlę" : "Zapętlaj", icon: "repeat", shortcut: "L", action: "loop" },
            { label: "Duplikuj", icon: "copy", shortcut: "Ctrl+D", action: "dup" },
            { label: "Ćwicz w pętli", icon: "repeat", action: "cycle" },
            { label: "Zmień nazwę…", icon: "pencil", action: "renameClip" },
            { separator: true },
            { label: "Usuń klip", icon: "trash", shortcut: "Del", action: "remove", danger: true }
        ]);
    }
    function trackMenu(track, item, x, y) {
        Studio.selectedTrack = track;
        menu.track = track;
        const t = Studio.tracks[track];
        const p = item.mapToItem(frame, x, y);
        menu.openAt(p.x, p.y, [
            { label: "Zmień nazwę…", icon: "pencil", action: "rename" },
            { label: t.armed ? "Nie nagrywaj na tę ścieżkę" : "Nagrywaj na tę ścieżkę", icon: "mic", action: "arm" },
            { label: "Dodaj dźwięk z pliku…", icon: "plus", shortcut: "Ctrl+I", action: "import" },
            { separator: true },
            { label: "Wejście: oba kanały", icon: t.input === 0 ? "check" : "", action: "in:0" },
            { label: "Wejście: lewy kanał (1)", icon: t.input === 1 ? "check" : "", action: "in:1" },
            { label: "Wejście: prawy kanał (2)", icon: t.input === 2 ? "check" : "", action: "in:2" },
            { separator: true },
            { label: "Przesuń w górę", icon: "up", action: "up", enabled: track > 0 },
            { label: "Przesuń w dół", icon: "arrowDown", action: "down", enabled: track < Studio.tracks.length - 1 },
            { separator: true },
            { label: "Usuń ścieżkę", icon: "trash", action: "removeTrack", danger: true }
        ]);
    }
    function addTrackMenu(item, x, y) {
        const p = item.mapToItem(frame, x, y);
        menu.openAt(p.x, p.y, [
            { label: "Nagranie — głos, gitara", icon: "mic", shortcut: "Ctrl+T", action: "addAudio" },
            { label: "Bit — Beat Maker", icon: "grid", action: "addDrums" },
            { label: "Bas 808", icon: "music", action: "addBass" },
            { label: "Akordy", icon: "music", action: "addKeys" },
            { label: "Melodia — piano roll", icon: "music", action: "addMelody" }
        ]);
    }
    function projectMenu(project, item, x, y) {
        menu.folder = project.folder;
        const p = item.mapToItem(frame, x, y);
        menu.openAt(p.x, p.y, [
            { label: "Otwórz", icon: "folder", action: "openProject" },
            { label: "Pokaż w folderze", icon: "folder", action: "showProject" },
            { separator: true },
            { label: "Usuń z listy", icon: "close", action: "forget" }
        ]);
    }
    function runMenu(a) {
        if (a === "split") Studio.splitClip(menu.clipId, menu.at);
        else if (a === "splitHead") { if (!Studio.splitClip(menu.clipId, Studio.position)) toast("Głowica nie stoi na tym klipie"); }
        else if (a === "loop") Studio.setClipLoop(menu.clipId, !Studio.clip(menu.clipId).loop);
        else if (a === "dup") Studio.duplicateClip(menu.clipId);
        else if (a === "cycle") Studio.cycleClip(menu.clipId);
        else if (a === "renameClip") { renameSheet.clipId = menu.clipId; renameField.text = Studio.clip(menu.clipId).name; renameSheet.open(); renameField.input.forceActiveFocus(); renameField.input.selectAll(); }
        else if (a === "remove") Studio.removeClip(menu.clipId);
        else if (a === "rename") { renameSheet.clipId = 0; renameField.text = Studio.tracks[menu.track].name; renameSheet.open(); renameField.input.forceActiveFocus(); renameField.input.selectAll(); }
        else if (a === "arm") Studio.setTrackArmed(menu.track, !Studio.tracks[menu.track].armed);
        else if (a === "import") importDialog.open();
        else if (a.startsWith("in:")) Studio.setTrackInput(menu.track, Number(a.substring(3)));
        else if (a === "up") Studio.moveTrack(menu.track, menu.track - 1);
        else if (a === "down") Studio.moveTrack(menu.track, menu.track + 1);
        else if (a === "removeTrack") Studio.removeTrack(menu.track);
        else if (a === "openProject") Studio.openProject(menu.folder);
        else if (a === "showProject") Studio.showInFolder(menu.folder);
        else if (a === "forget") Studio.forgetRecent(menu.folder);
        else if (a === "addAudio") Studio.addTrack();
        else if (a === "addDrums") { const i = Studio.addPatternTrack("drums", "trap"); if (i >= 0) editTrack = i; }
        else if (a === "addMelody") { const i = Studio.addPatternTrack("melody", ""); if (i >= 0) editTrack = i; }
        else if (a === "addKeys") { const i = Studio.addPatternTrack("keys", "trap"); if (i >= 0) editTrack = i; }
        else if (a === "addBass") { const i = Studio.addPatternTrack("bass", "trap"); if (i >= 0) editTrack = i; }
        else if (a.startsWith("chord:") && editTrack >= 0) {
            const p = JSON.parse(JSON.stringify(Studio.tracks[editTrack].pattern));
            p.chords[menu.chordIndex] = Number(a.substring(6));
            Studio.setPattern(editTrack, p);
        }
        else if (a.startsWith("genre:") && editTrack >= 0) Studio.setPattern(editTrack, Studio.genrePattern(Studio.tracks[editTrack].kind, a.substring(6)));
    }

    function toast(text, action, callback) {
        toastBox.text = text;
        toastBox.action = action || "";
        toastBox.callback = callback || null;
        toastBox.shown = true;
        toastTimer.restart();
    }

    // ——— Okno ———
    function updateEffects() {
        WindowEffects.setBlur(win, Qt.rect(m, m, frame.width, frame.height), r);
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
        color: Theme.windowGlass
        border.width: win.maxed ? 0 : 1
        border.color: Theme.edge
        WindowSheen { window: win; radius: win.r }

        StartPage {
            anchors.fill: parent
            visible: !Studio.open
            window: win
            radius: win.r
            onNewRequested: (genre) => win.newProject(genre)
            onOpenRequested: openDialog.open()
            onBundleRequested: bundleDialog.open()
            onMenuRequested: (project, item, x, y) => win.projectMenu(project, item, x, y)
        }

        // ——— Projekt ———
        Item {
            id: project
            anchors.fill: parent
            visible: Studio.open

            // Pasek transportu
            Item {
                id: toolbar
                width: parent.width; height: 66
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }

                Row {
                    id: titleRow
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    HoverButton {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34; height: 34; radius: 17
                        onClicked: Studio.closeProject()
                        Icon { anchors.centerIn: parent; d: Icons.back; size: 17; stroke: 2; color: Theme.text }
                        Tip { shown: parent.hovered; text: "Wszystkie projekty"; below: true }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            width: Math.min(implicitWidth, 220)
                            text: Studio.name
                            elide: Text.ElideRight
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold
                        }
                        Text {
                            text: Studio.busy ? "Wczytywanie dźwięku…" : Studio.recording ? "Nagrywanie…" : Studio.dirty ? "Niezapisane zmiany" : "Zapisano"
                            color: Studio.recording ? "#E5484D" : Theme.text2
                            font.family: Theme.font; font.pixelSize: 12
                        }
                    }
                }

                // Transport i licznik
                // Na środku okna, a gdy brak miejsca — między nazwą a przyciskami z prawej
                Row {
                    id: transport
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(titleRow.x + titleRow.width + 20, Math.min((parent.width - width) / 2, rightTools.x - width - 20))
                    spacing: 8
                    RoundBtn { icon: "prev"; tip: "Na początek (Enter)"; onClicked: Studio.seek(0) }
                    HoverButton {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42; height: 42; radius: 21
                        baseColor: Theme.text
                        color: hovered ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.82) : baseColor
                        onClicked: Studio.toggle()
                        Icon {
                            anchors.centerIn: parent; anchors.horizontalCenterOffset: Studio.playing ? 0 : 1
                            d: Studio.playing ? Icons.pause : Icons.play
                            size: 19; stroke: 2.4
                            color: Theme.dark ? "#16181D" : "white"
                            fill: Studio.playing ? "transparent" : (Theme.dark ? "#16181D" : "white")
                        }
                        Tip { shown: parent.hovered; text: Studio.playing ? "Zatrzymaj (Spacja)" : "Odtwórz (Spacja)"; below: true }
                    }
                    HoverButton {
                        id: recBtn
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42; height: 42; radius: 21
                        baseColor: Studio.recording ? "#E5484D" : Theme.fill
                        color: Studio.recording ? (hovered ? "#EE6266" : baseColor) : (hovered ? Theme.hover : baseColor)
                        onClicked: Studio.record()
                        Rectangle {
                            anchors.centerIn: parent
                            width: Studio.recording ? 14 : 16; height: width
                            radius: Studio.recording ? 3 : width / 2
                            color: Studio.recording ? "white" : "#E5484D"
                        }
                        SequentialAnimation on opacity {
                            running: Studio.countingIn
                            loops: Animation.Infinite
                            alwaysRunToEnd: true
                            NumberAnimation { to: 0.45; duration: 300 }
                            NumberAnimation { to: 1; duration: 300 }
                        }
                        Tip { shown: parent.hovered; text: Studio.recording ? "Zakończ nagrywanie (R)" : "Nagrywaj na zaznaczoną ścieżkę (R)"; below: true }
                    }
                    Item { width: 6; height: 1 }
                    // Licznik: takt.miara, czas, tempo, metrum
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: lcd.width + 8; height: 46; radius: 12
                        color: Theme.fill
                        Row {
                            id: lcd
                            x: 4; anchors.verticalCenter: parent.verticalCenter
                            Column {
                                width: 96
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Studio.position < 0 ? "−" : Studio.barBeat(Studio.position)
                                    color: Studio.recording ? "#E5484D" : Theme.text
                                    font.family: Theme.font; font.pixelSize: 19; font.weight: Font.DemiBold; font.features: { "tnum": 1 }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Studio.clock(Studio.position)
                                    color: Theme.text2
                                    font.family: Theme.font; font.pixelSize: 11; font.features: { "tnum": 1 }
                                }
                            }
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: 28; color: Theme.line }
                            LcdButton { value: Math.round(Studio.bpm * 10) / 10; caption: "BPM"; tip: "Tempo i metrum"; onClicked: tempoSheet.open() }
                            LcdButton { value: Studio.beatsPerBar + "/4"; caption: "metrum"; tip: "Tempo i metrum"; onClicked: tempoSheet.open() }
                        }
                    }
                    Item { width: 6; height: 1 }
                    RoundBtn {
                        path: win.metronomePath
                        active: Studio.metronome
                        tip: Studio.metronome ? "Metronom włączony (K)" : "Metronom wyłączony (K)"
                        onClicked: Studio.metronome = !Studio.metronome
                    }
                    RoundBtn {
                        icon: "repeat"
                        active: Studio.cycle
                        tip: Studio.cycle ? "Pętla odtwarzania: wł. (C)" : "Pętla odtwarzania — ćwicz fragment (C)"
                        onClicked: Studio.cycle = !Studio.cycle
                    }
                    RoundBtn {
                        icon: "timer"
                        active: Studio.countIn
                        tip: Studio.countIn ? "Odliczanie taktu przed nagraniem: wł." : "Odliczanie przed nagraniem: wył."
                        onClicked: Studio.countIn = !Studio.countIn
                    }
                }

                Row {
                    id: rightTools
                    anchors.right: winButtons.left; anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    RoundBtn { icon: "undo"; enabled: Studio.canUndo; tip: "Cofnij (Ctrl+Z)"; onClicked: Studio.undo() }
                    RoundBtn { icon: "undo"; mirror: true; enabled: Studio.canRedo; tip: "Ponów (Ctrl+Shift+Z)"; onClicked: Studio.redo() }
                    Item { width: 4; height: 1 }
                    RoundBtn { icon: "sliders"; active: win.showMixer; tip: "Mikser (X)"; onClicked: win.showMixer = !win.showMixer }
                    RoundBtn { icon: "sparkle"; active: win.showInspector; tip: "Efekty i klip (E)"; onClicked: win.showInspector = !win.showInspector }
                    RoundBtn { icon: "speaker"; tip: "Ustawienia dźwięku"; onClicked: audioSheet.open(); warn: !Studio.audioOk || Studio.audioError !== "" }
                    RoundBtn { icon: "download"; tip: "Eksportuj do MP3, WAV, OGG, FLAC (Ctrl+E)"; onClicked: exportSheet.open() }
                    Pill { anchors.verticalCenter: parent.verticalCenter; text: "Udostępnij"; icon: "upload"; primary: true; tip: "Piosenka z okładką albo projekt do remiksu — na telefon, e-mailem, w komunikatorze"; onClicked: shareSheet.start() }
                }
                WindowButtons {
                    id: winButtons
                    window: win
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Treść: nagłówki ścieżek na szkle okna, pasy na panelu
            GlassPane {
                x: timeline.headerW
                y: toolbar.height
                width: timeline.width - x
                height: timeline.height + statusBar.height
                topLeftRadius: 14
                topRightRadius: inspector.width > 0 ? 14 : 0
                leftLine: false
                bottomRightRadius: win.showMixer || inspector.width > 0 ? 0 : win.r
            }
            Rectangle { y: toolbar.height; width: parent.width; height: 1; color: Theme.line; opacity: 0.6 }
            Timeline {
                id: timeline
                y: toolbar.height
                width: parent.width - inspector.width
                height: parent.height - y - statusBar.height - mixer.height - beatMaker.height - pianoRoll.height
                colors: win.trackColors
                onClipMenu: (c, track, item, x, y, at) => win.clipMenu(c, track, item, x, y, at)
                onTrackMenu: (track, item, x, y) => win.trackMenu(track, item, x, y)
                onAddTrackRequested: (item, x, y) => win.addTrackMenu(item, x, y)
                onEditPattern: (track) => { win.editTrack = track; Studio.selectedTrack = track; }
            }

            // Pasek pod osią: dodawanie dźwięku, siatka, powiększenie
            Item {
                id: statusBar
                y: timeline.y + timeline.height
                width: timeline.width; height: 44
                Row {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Pill { anchors.verticalCenter: parent.verticalCenter; height: 30; text: "Dodaj dźwięk…"; icon: "plus"; tip: "Plik WAV, FLAC, MP3 lub OGG na zaznaczoną ścieżkę (Ctrl+I)"; onClicked: importDialog.open() }
                }
                Row {
                    x: timeline.headerW + 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Przyciągaj do"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                    Segmented {
                        anchors.verticalCenter: parent.verticalCenter
                        model: [{ label: "taktu", value: 0 }, { label: "miary", value: 1 }, { label: "1/8", value: 2 }, { label: "1/16", value: 4 }, { label: "wył.", value: -1 }]
                        value: timeline.snapDiv
                        onPicked: (v) => timeline.snapDiv = v
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: 6
                        text: "Shift — bez przyciągania"
                        color: Theme.text2
                        opacity: 0.8
                        font.family: Theme.font; font.pixelSize: 11
                    }
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    RoundBtn { icon: "minus"; size: 28; tip: "Pomniejsz (Ctrl+−)"; onClicked: timeline.zoom(0.8, timeline.viewW / 2) }
                    RoundBtn { icon: "plus"; size: 28; tip: "Powiększ (Ctrl++)"; onClicked: timeline.zoom(1.25, timeline.viewW / 2) }
                }
            }

            Inspector {
                id: inspector
                x: parent.width - width
                y: toolbar.height
                width: win.showInspector ? 300 : 0
                height: timeline.height + statusBar.height
                visible: width > 0
                clip: true
                colors: win.trackColors
                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
            }

            Mixer {
                id: mixer
                z: 20
                anchors.bottom: parent.bottom
                width: parent.width
                height: win.showMixer && win.editTrack < 0 ? Math.min(300, parent.height * 0.42) : 0
                visible: height > 0
                clip: true
                colors: win.trackColors
                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
            }
        }

        // Beat Maker (zamiast miksera, gdy otwarty)
        PatternEditor {
            id: beatMaker
            parent: project
            z: 20
            anchors.bottom: parent ? parent.bottom : undefined
            width: project.width
            track: win.editTrack
            colors: win.trackColors
            readonly property bool bassMode: !!Studio.tracks[win.editTrack] && Studio.tracks[win.editTrack].kind === "bass"
            readonly property bool melody: !!Studio.tracks[win.editTrack] && Studio.tracks[win.editTrack].kind === "melody"
            height: win.editTrack >= 0 && !!Studio.tracks[win.editTrack] && !melody ? Math.min(bassMode ? 450 : 330, project.height * 0.55) : 0
            // Akordy: niższy panel
            visible: height > 0
            clip: true
            onCloseRequested: win.editTrack = -1
            onChordMenuRequested: (index, x, y) => {
                const p = beatMaker.mapToItem(frame, x, y);
                const seventh = !!Studio.tracks[win.editTrack].pattern.seventh;
                menu.chordIndex = index;
                menu.openAt(p.x, Math.min(p.y, frame.height - 300), [0, 1, 2, 3, 4, 5, 6].map(d => ({ label: Studio.chordName(d, seventh), shortcut: ["I", "II", "III", "IV", "V", "VI", "VII"][d], action: "chord:" + d })));
            }
            onGenreMenuRequested: (x, y) => {
                const p = beatMaker.mapToItem(frame, x, y);
                menu.openAt(p.x, Math.min(p.y, frame.height - 320), Studio.genres.map(g => ({ label: g.label + " · " + g.bpm + " BPM", icon: "sparkle", action: "genre:" + g.id })));
            }
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
        }

        // Piano roll (ścieżka Melodia)
        PianoRoll {
            id: pianoRoll
            parent: project
            z: 20
            anchors.bottom: parent ? parent.bottom : undefined
            width: project.width
            track: beatMaker.melody ? win.editTrack : -1
            colors: win.trackColors
            height: beatMaker.melody ? Math.min(460, project.height * 0.6) : 0
            visible: height > 0
            clip: true
            onCloseRequested: win.editTrack = -1
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutQuad } }
        }

        // ——— Arkusze ———
        Sheet {
            id: newSheet
            radius: win.r
            title: "Nowy projekt"
            cardWidth: 480
            property real bpm: 100
            property int beats: 4
            property string template: ""
            Column {
                width: parent.width
                spacing: 14
                Label { text: "Na czym zaczynasz?" }
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: [{ id: "", label: "Pusty projekt", hint: "Ścieżki na wokal i gitarę" }].concat(Studio.genres)
                        delegate: HoverButton {
                            id: tplChip
                            required property var modelData
                            readonly property bool on: newSheet.template === modelData.id
                            width: tplText.implicitWidth + 24; height: 30; radius: 15
                            baseColor: on ? Theme.accent : Theme.fill
                            color: on ? baseColor : (hovered ? Theme.hover : baseColor)
                            onClicked: { newSheet.template = modelData.id; if (modelData.bpm) newSheet.bpm = modelData.bpm; }
                            Text { id: tplText; anchors.centerIn: parent; text: tplChip.modelData.label; color: tplChip.on ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                            Tip { shown: tplChip.hovered; text: tplChip.modelData.hint }
                        }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    visible: newSheet.template !== ""
                    text: "Gotowy bit i 808 (do zmiany w Beat Makerze), dwie ścieżki na wokal z efektami i mastering gatunku. Wystarczy nagrać głos."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
                Label { text: "Nazwa piosenki" }
                Field { id: newName; width: parent.width; onAccepted: createBtn.clicked() }
                Row {
                    spacing: 24
                    Column {
                        spacing: 8
                        Label { text: "Tempo (uderzenia na minutę)" }
                        Stepper { value: newSheet.bpm; onChanged: (v) => newSheet.bpm = v }
                    }
                    Column {
                        spacing: 8
                        Label { text: "Metrum" }
                        Segmented {
                            model: [{ label: "2/4", value: 2 }, { label: "3/4", value: 3 }, { label: "4/4", value: 4 }, { label: "6/4", value: 6 }]
                            value: newSheet.beats
                            onPicked: (v) => newSheet.beats = v
                        }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Projekt trafi do folderu Muzyka/Studio — nagrania i dodane pliki zapisują się razem z nim."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Pill { text: "Anuluj"; onClicked: newSheet.close() }
                    Pill {
                        id: createBtn
                        text: "Utwórz"; primary: true
                        onClicked: { newSheet.close(); Studio.newProject(newName.text, newSheet.bpm, newSheet.beats, newSheet.template); if (newSheet.template && Studio.bpm !== newSheet.bpm) Studio.bpm = newSheet.bpm; }
                    }
                }
            }
        }

        Sheet {
            id: tempoSheet
            radius: win.r
            title: "Tempo i metrum"
            cardWidth: 460
            property var taps: []
            onShownChanged: taps = []
            Column {
                width: parent.width
                spacing: 14
                Label { text: "Tempo (uderzenia na minutę)" }
                Row {
                    spacing: 10
                    Stepper { value: Studio.bpm; onChanged: (v) => Studio.bpm = v }
                    Pill {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Wystukaj"
                        icon: "thumb"
                        tip: "Klikaj w rytm piosenki — tempo ustawi się samo"
                        onClicked: {
                            const now = Date.now();
                            let t = tempoSheet.taps.filter(x => now - x < 3000);
                            t.push(now);
                            tempoSheet.taps = t;
                            if (t.length >= 3) Studio.bpm = Math.round(60000 * (t.length - 1) / (t[t.length - 1] - t[0]));
                        }
                    }
                }
                Label { text: "Metrum" }
                Segmented {
                    model: [{ label: "2/4", value: 2 }, { label: "3/4", value: 3 }, { label: "4/4", value: 4 }, { label: "5/4", value: 5 }, { label: "6/4", value: 6 }]
                    value: Studio.beatsPerBar
                    onPicked: (v) => Studio.beatsPerBar = v
                }
                Check { text: "Metronom podczas odtwarzania i nagrywania"; on: Studio.metronome; onToggled: Studio.metronome = !Studio.metronome }
                Check { text: "Odliczaj jeden takt przed nagraniem"; on: Studio.countIn; onToggled: Studio.countIn = !Studio.countIn }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Zmiana tempa przesuwa siatkę taktów — nagrane dźwięki zostają tam, gdzie są."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
                Pill { anchors.right: parent.right; text: "Gotowe"; primary: true; onClicked: tempoSheet.close() }
            }
        }

        // ——— Udostępnianie ———
        Sheet {
            id: shareSheet
            radius: win.r
            title: "Udostępnij"
            cardWidth: 720
            closable: !Studio.sharing && !Studio.exporting
            property string kind: "song"
            property string result: ""                 // przygotowany plik
            property string cover: ""
            property var phones: []
            function start() {
                result = "";
                shareTitle.text = Studio.name;
                shareArtist.text = Studio.artist;
                phones = Studio.phones();
                refreshCover();
                open();
            }
            function refreshCover() { cover = Studio.coverPreview(shareTitle.text || Studio.name, shareArtist.text); }
            Timer { id: coverTimer; interval: 350; onTriggered: shareSheet.refreshCover() }
            Connections {
                target: Studio
                function onShareReady(path, kind) { shareSheet.result = path; shareSheet.phones = Studio.phones(); }
                function onShareFailed(error) { win.toast(error); }
            }
            Row {
                width: parent.width
                spacing: 22
                Rectangle {
                    width: 260; height: 260; radius: 14
                    color: Theme.fill
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: shareSheet.cover
                        visible: shareSheet.kind === "song"
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                    }
                    Column {
                        visible: shareSheet.kind === "project"
                        anchors.centerIn: parent
                        spacing: 10
                        Icon { anchors.horizontalCenter: parent.horizontalCenter; d: Icons.archive; size: 64; stroke: 1.4; color: Theme.text2 }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Studio.tracksLabel(Studio.tracks.length); color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                    }
                }
                Column {
                    width: parent.width - 282
                    spacing: 12
                    Segmented {
                        model: [{ label: "Piosenka (MP3)", value: "song" }, { label: "Projekt do remiksu", value: "project" }]
                        value: shareSheet.kind
                        onPicked: (v) => { shareSheet.kind = v; shareSheet.result = ""; }
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: shareSheet.kind === "song"
                              ? "Gotowa piosenka z okładką, tytułem i wykonawcą — tak widać ją na telefonie i w odtwarzaczach."
                              : "Cały projekt w jednej paczce: ścieżki, nagrania, bity, efekty. Znajomy otworzy ją w swoim Studiu i zrobi własną wersję."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
                    }
                    Column {
                        visible: shareSheet.kind === "song"
                        width: parent.width
                        spacing: 8
                        Label { text: "Tytuł" }
                        Field { id: shareTitle; width: parent.width; input.onTextChanged: coverTimer.restart() }
                        Label { text: "Wykonawca" }
                        Field { id: shareArtist; width: parent.width; placeholder: "Twój pseudonim"; input.onTextChanged: coverTimer.restart() }
                    }
                    Rectangle {
                        visible: Studio.exporting || Studio.sharing
                        width: parent.width; height: 6; radius: 3
                        color: Theme.fill
                        Rectangle { width: parent.width * (Studio.exporting ? Studio.exportProgress : 0.6); height: parent.height; radius: 3; color: Theme.accent }
                    }
                    // Po przygotowaniu: gdzie wysłać
                    Column {
                        visible: shareSheet.result !== ""
                        width: parent.width
                        spacing: 8
                        Row {
                            spacing: 8
                            Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.check; size: 16; stroke: 2.4; color: "#30C26B" }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: shareSheet.cardWidth - 340
                                text: "Gotowe: " + shareSheet.result.split("/").pop()
                                elide: Text.ElideMiddle
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                            }
                        }
                        Flow {
                            width: parent.width
                            spacing: 8
                            Repeater {
                                model: shareSheet.phones
                                delegate: Pill {
                                    required property var modelData
                                    text: "Na telefon: " + modelData.name
                                    icon: "phone"
                                    onClicked: Studio.sendToPhone(modelData.id, shareSheet.result)
                                }
                            }
                            Pill { text: "E-mail"; icon: "mail"; onClicked: Studio.sendEmail(shareSheet.result, shareTitle.text || Studio.name) }
                            Pill { text: "Kopiuj plik"; icon: "copy"; tip: "Wklej w komunikatorze, przeglądarce albo w Plikach"; onClicked: Studio.copyFile(shareSheet.result) }
                            Pill { text: "Pokaż w folderze"; icon: "folder"; onClicked: Studio.showInFolder(shareSheet.result) }
                        }
                        Text {
                            visible: shareSheet.phones.length === 0
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "Telefon połączysz w programie Telefon — potem pliki wyślesz jednym kliknięciem."
                            color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Pill { text: shareSheet.result ? "Gotowe" : "Anuluj"; enabled: !Studio.sharing && !Studio.exporting; onClicked: shareSheet.close() }
                        Pill {
                            visible: shareSheet.result === ""
                            text: Studio.exporting || Studio.sharing ? "Przygotowuję…" : (shareSheet.kind === "song" ? "Przygotuj piosenkę" : "Spakuj projekt")
                            primary: true
                            enabled: !Studio.exporting && !Studio.sharing
                            onClicked: shareSheet.kind === "song" ? Studio.shareSong(shareTitle.text, shareArtist.text) : Studio.shareProject()
                        }
                    }
                }
            }
        }

        Sheet {
            id: exportSheet
            radius: win.r
            title: "Eksportuj piosenkę"
            closable: !Studio.exporting
            property string format: "mp3"
            Column {
                width: parent.width
                spacing: 12
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Wszystkie ścieżki zmiksowane tak, jak je słychać — z głośnością, panoramą, wyciszeniem i solo — do jednego pliku w folderze projektu (Eksport)."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.2
                }
                Repeater {
                    model: [{ value: "mp3", label: "MP3", hint: "Do wysłania znajomym i na telefon" },
                            { value: "wav", label: "WAV", hint: "Najwyższa jakość, do dalszej obróbki (CD: 16 bitów)" },
                            { value: "ogg", label: "OGG Vorbis", hint: "Otwarty format, mały plik" },
                            { value: "flac", label: "FLAC", hint: "Bez utraty jakości, mniejszy od WAV" }]
                    delegate: HoverButton {
                        id: fmt
                        required property var modelData
                        readonly property bool on: exportSheet.format === modelData.value
                        width: parent.width; height: 50; radius: 12
                        baseColor: on ? Theme.accentSoft : Theme.fill
                        border.width: on ? 2 : 0; border.color: Theme.accent
                        enabled: !Studio.exporting
                        onClicked: exportSheet.format = modelData.value
                        Rectangle {
                            x: 14; anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 18; radius: 9
                            color: "transparent"
                            border.width: fmt.on ? 5 : 1.5; border.color: fmt.on ? Theme.accent : Theme.text2
                        }
                        Column {
                            x: 44; anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text { text: fmt.modelData.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                            Text { text: fmt.modelData.hint; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                        }
                    }
                }
                Rectangle {
                    visible: Studio.exporting
                    width: parent.width; height: 6; radius: 3
                    color: Theme.fill
                    Rectangle { width: parent.width * Studio.exportProgress; height: parent.height; radius: 3; color: Theme.accent }
                }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Pill { text: "Anuluj"; onClicked: { if (Studio.exporting) Studio.cancelExport(); else exportSheet.close(); } }
                    Pill {
                        text: Studio.exporting ? "Eksportowanie… " + Math.round(Studio.exportProgress * 100) + "%" : "Eksportuj"
                        primary: true
                        enabled: !Studio.exporting
                        onClicked: Studio.exportMix(exportSheet.format)
                    }
                }
            }
        }

        Sheet {
            id: audioSheet
            radius: win.r
            title: "Ustawienia dźwięku"
            cardWidth: 500
            Column {
                width: parent.width
                spacing: 12
                Row {
                    spacing: 8
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: Studio.audioOk && !Studio.audioError ? "#30C26B" : "#E5484D" }
                    Text {
                        width: audioSheet.cardWidth - 70
                        wrapMode: Text.WordWrap
                        text: Studio.audioOk && !Studio.audioError ? "Dźwięk działa (PipeWire, 48 kHz)" : (Studio.audioError || "Brak dźwięku")
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                    }
                }
                Label { text: "Wyjście — głośniki lub słuchawki" }
                DeviceList { model: Studio.outputs; current: Studio.output; onPicked: (n) => Studio.output = n }
                Label { text: "Wejście — mikrofon lub interfejs audio" }
                DeviceList { model: Studio.inputs; current: Studio.input; onPicked: (n) => Studio.input = n }
                Item {
                    width: parent.width; height: 26
                    visible: Studio.tracks.length > 0
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Poziom wejścia"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                    Rectangle {
                        x: 110; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 110; height: 6; radius: 3
                        color: Theme.fill
                        Rectangle {
                            width: parent.width * (Studio.inputLevel <= 0 ? 0 : Math.max(0, Math.min(1, (20 * Math.log(Studio.inputLevel) / Math.LN10 + 60) / 60)))
                            height: parent.height; radius: 3
                            color: Studio.inputLevel >= 0.99 ? "#E5484D" : "#30C26B"
                        }
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    visible: Studio.tracks.length > 0
                    text: "Poziom widać, gdy ścieżka jest gotowa do nagrania (czerwona kropka przy ścieżce). Śpiewaj głośno — wskaźnik nie powinien dochodzić do czerwieni."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
                Label { text: "Klawiatury MIDI" }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Studio.midiDevices.length ? Studio.midiDevices.join(", ") + " — graj w piano rollu (ścieżka Melodia)"
                                                    : "Brak — podłącz klawiaturę USB, Studio połączy się z nią samo"
                    color: Studio.midiDevices.length ? Theme.text : Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
                Label { text: "Korekta opóźnienia nagrań" }
                Row {
                    spacing: 10
                    Stepper { value: Studio.latency; step: 5; min: -500; max: 500; suffix: " ms"; onChanged: (v) => Studio.latency = v }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 260
                        wrapMode: Text.WordWrap
                        text: "Gdy nagranie jest spóźnione względem metronomu — zwiększ."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                    }
                }
                Pill { anchors.right: parent.right; text: "Gotowe"; primary: true; onClicked: audioSheet.close() }
            }
        }

        Sheet {
            id: renameSheet
            radius: win.r
            property int clipId: 0              // 0 — zmiana nazwy ścieżki
            title: clipId ? "Nazwa klipu" : "Nazwa ścieżki"
            cardWidth: 380
            Column {
                width: parent.width
                spacing: 14
                Field { id: renameField; width: parent.width; onAccepted: renameOk.clicked() }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Pill { text: "Anuluj"; onClicked: renameSheet.close() }
                    Pill { id: renameOk; text: "Zmień"; primary: true; onClicked: { if (renameSheet.clipId) Studio.renameClip(renameSheet.clipId, renameField.text); else Studio.renameTrack(menu.track, renameField.text); renameSheet.close(); } }
                }
            }
        }

        // Komunikat (z opcjonalnym przyciskiem)
        Rectangle {
            id: toastBox
            property bool shown: false
            property alias text: toastText.text
            property string action
            property var callback: null
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - (shown ? height + 24 : 0)
            opacity: shown ? 1 : 0
            z: 450
            width: toastRow.implicitWidth + 36; height: 40; radius: 20
            color: Theme.dark ? "#ECEEF3" : "#1E2027"
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Row {
                id: toastRow
                anchors.centerIn: parent
                spacing: 14
                Text { id: toastText; anchors.verticalCenter: parent.verticalCenter; color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                Text {
                    visible: toastBox.action !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: toastBox.action
                    color: Theme.dark ? Theme.accent : Qt.lighter(Theme.accent, 1.5)
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                    MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: { if (toastBox.callback) toastBox.callback(); toastBox.shown = false; } }
                }
            }
            Timer { id: toastTimer; interval: 4500; onTriggered: toastBox.shown = false }
        }

        ContextMenu {
            id: menu
            property int clipId
            property real at
            property int track
            property string folder
            property int chordIndex
            onTriggered: (a) => win.runMenu(a)
        }
    }

    // Metronom (ikona w siatce 24×24)
    readonly property string metronomePath: "M9.5 3h5l4 18h-13zM7.6 15h8.8M12 15l5.5-9"

    // ——— Elementy ———
    component RoundBtn: HoverButton {
        id: rb
        property string icon
        property string path
        property bool active: false
        property bool mirror: false
        property bool warn: false
        property string tip
        property real size: 34
        width: size; height: size; radius: size / 2
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        baseColor: active ? Theme.accentSoft : "transparent"
        color: hovered ? (active ? Theme.accentAlpha(Theme.dark ? 0.42 : 0.22) : Theme.hover) : baseColor
        opacity: enabled ? 1 : 0.35
        Icon {
            anchors.centerIn: parent
            d: rb.path || Icons[rb.icon] || ""
            size: rb.size * 0.52; stroke: 1.9
            color: rb.active ? Theme.accentText : Theme.text
            transform: Scale { origin.x: rb.size * 0.26; xScale: rb.mirror ? -1 : 1 }
        }
        Rectangle { visible: rb.warn; x: rb.width - 10; y: 3; width: 8; height: 8; radius: 4; color: "#E5484D" }
        Tip { shown: rb.hovered && rb.tip !== ""; text: rb.tip; below: true }
    }

    component LcdButton: HoverButton {
        id: lb
        property var value
        property string caption
        property string tip
        width: 64; height: 40; radius: 9
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Column {
            anchors.centerIn: parent
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: lb.value; color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: lb.caption; color: Theme.text2; font.family: Theme.font; font.pixelSize: 10 }
        }
        Tip { shown: lb.hovered; text: lb.tip; below: true }
    }

    component Label: Text {
        color: Theme.text
        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
    }

    // Liczba z przyciskami − / +
    component Stepper: Row {
        id: sp
        property real value
        property real step: 1
        property real min: 30
        property real max: 300
        property string suffix
        signal changed(real v)
        spacing: 6
        function set(v) { sp.changed(Math.max(sp.min, Math.min(sp.max, v))); }
        Pill { icon: "minus"; onClicked: sp.set(sp.value - sp.step) }
        Rectangle {
            width: 90; height: 34; radius: 10
            color: Theme.fill
            border.width: num.activeFocus ? 2 : 0; border.color: Theme.accent
            TextInput {
                id: num
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: (Math.round(sp.value * 10) / 10) + sp.suffix
                color: Theme.text
                selectByMouse: true
                font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold; font.features: { "tnum": 1 }
                onEditingFinished: { const v = parseFloat(text.replace(",", ".")); if (!isNaN(v)) sp.set(v); text = Qt.binding(() => (Math.round(sp.value * 10) / 10) + sp.suffix); }
            }
        }
        Pill { icon: "plus"; onClicked: sp.set(sp.value + sp.step) }
    }

    component Check: HoverButton {
        id: ck
        property string text
        property bool on
        signal toggled()
        width: parent ? parent.width : 300; height: 34; radius: 9
        onClicked: ck.toggled()
        Rectangle {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            width: 20; height: 20; radius: 6
            color: ck.on ? Theme.accent : "transparent"
            border.width: ck.on ? 0 : 1.5; border.color: Theme.text2
            Icon { visible: ck.on; anchors.centerIn: parent; d: Icons.check; size: 13; stroke: 2.4; color: "white" }
        }
        Text { x: 38; anchors.verticalCenter: parent.verticalCenter; text: ck.text; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
    }

    component DeviceList: Column {
        id: dl
        property var model: []
        property string current
        signal picked(string name)
        width: parent ? parent.width : 400
        spacing: 2
        Repeater {
            model: dl.model
            delegate: HoverButton {
                id: dev
                required property var modelData
                readonly property bool on: dl.current === modelData.name
                width: dl.width; height: 34; radius: 9
                baseColor: on ? Theme.accentSoft : "transparent"
                onClicked: dl.picked(modelData.name)
                Icon { visible: dev.on; x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.check; size: 14; stroke: 2.2; color: Theme.accentText }
                Text {
                    x: 34; width: parent.width - 44
                    anchors.verticalCenter: parent.verticalCenter
                    text: dev.modelData.label
                    elide: Text.ElideRight
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                }
            }
        }
    }
}
