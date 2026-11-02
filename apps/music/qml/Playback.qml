import QtQuick
import QtMultimedia
import QtCore
import Aster.Music

// Odtwarzanie i kolejka: co gra, co dalej, losowo (reszta kolejki tasowana, „wyłącz” wraca do
// kolejności), powtarzanie (wszystko / jeden utwór). Kolejka, utwór i miejsce przetrwają
// zamknięcie programu. Na zewnątrz — MPRIS (Centrum sterowania, klawisze multimedialne).
Item {
    id: pb
    property var queue: []                  // utwory (mapy z Library)
    property int index: -1
    property var original: []               // kolejność sprzed „losowo”
    property bool shuffle: false
    property string repeat: "none"          // none | all | one
    property real volume: 0.8
    property bool muted: false
    signal raiseRequested()
    signal quitRequested()

    readonly property var current: index >= 0 && index < queue.length ? queue[index] : null
    readonly property bool playing: mp.playbackState === MediaPlayer.PlayingState
    readonly property real position: mp.position
    readonly property real duration: mp.duration > 0 ? mp.duration : (current ? current.duration : 0)
    readonly property bool hasNext: queue.length > 0 && (index < queue.length - 1 || repeat === "all")
    readonly property bool hasPrev: index > 0 || mp.position > 3000
    readonly property string coverUrl: current && current.cover ? "file://" + current.cover : ""

    // ——— Sterowanie ———
    // start niepodany przy „losowo” — losowy pierwszy utwór
    function play(list, start, shuffled) {
        if (!list || list.length === 0) return;
        if (shuffled) shuffle = true;
        original = list.slice();
        let i = start === undefined ? (shuffle ? Math.floor(Math.random() * list.length) : 0) : Math.max(0, Math.min(list.length - 1, start));
        let q = list.slice();
        if (shuffle) {
            const first = q.splice(i, 1)[0];
            q = [first].concat(mix(q));
            i = 0;
        }
        queue = q;
        load(i, true);
    }
    function load(i, autoplay) {
        index = i;
        const t = current;
        if (!t) { mp.stop(); mp.source = ""; return; }
        mp.source = Library.url(t.path);
        if (autoplay) mp.play();
        saveState();
    }
    function toggle() {
        if (!current) { if (Library.tracks.length) play(Library.tracks, undefined, true); return; }
        if (playing) mp.pause(); else mp.play();
    }
    function next(auto) {
        if (queue.length === 0) return;
        if (auto && repeat === "one") { mp.position = 0; mp.play(); return; }
        if (index < queue.length - 1) load(index + 1, true);
        else if (repeat === "all") load(0, true);
        else if (auto) { mp.stop(); index = 0; mp.source = Library.url(queue[0].path); }
    }
    function prev() {
        if (mp.position > 3000 || index <= 0) { seek(0); return; }
        load(index - 1, true);
    }
    function seek(ms) { mp.position = Math.max(0, Math.min(duration, ms)); session.seeked(mp.position); }
    function jump(i) { load(i, true); }
    function playNext(tracks) {
        if (!current) { play(tracks, 0); return; }
        const q = queue.slice();
        q.splice(index + 1, 0, ...tracks);
        queue = q;
        saveState();
    }
    function enqueue(tracks) {
        if (!current) { play(tracks, 0); return; }
        queue = queue.concat(tracks);
        if (!shuffle) original = original.concat(tracks);
        saveState();
    }
    function remove(i) {
        if (i === index) return;
        const q = queue.slice();
        q.splice(i, 1);
        if (i < index) index--;
        queue = q;
        saveState();
    }
    function clear() {
        mp.stop();
        queue = []; original = []; index = -1;
        mp.source = "";
        saveState();
    }
    function setShuffle(on) {
        if (on === shuffle) return;
        shuffle = on;
        if (!current) return;
        const cur = current;
        if (on) {
            original = queue.slice();
            const rest = queue.filter((t, i) => i !== index);
            queue = [cur].concat(mix(rest));
            index = 0;
        } else {
            // Wróć do kolejności, grając dalej to samo
            const q = original.length ? original.slice() : queue.slice();
            queue = q;
            index = Math.max(0, q.findIndex(t => t.path === cur.path));
        }
        saveState();
    }
    function cycleRepeat() { repeat = repeat === "none" ? "all" : (repeat === "all" ? "one" : "none"); }
    function setVolume(v) { volume = Math.max(0, Math.min(1, v)); if (volume > 0) muted = false; }
    function mix(list) {
        const a = list.slice();
        for (let i = a.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            const t = a[i]; a[i] = a[j]; a[j] = t;
        }
        return a;
    }

    // ——— Pamięć między uruchomieniami ———
    Settings {
        id: state
        category: "playback"
        property var queuePaths: []
        property var originalPaths: []
        property int index: -1
        property real position: 0
        property alias shuffle: pb.shuffle
        property alias repeat: pb.repeat
        property alias volume: pb.volume
        property alias muted: pb.muted
    }
    function saveState() {
        state.queuePaths = queue.map(t => t.path);
        state.originalPaths = shuffle ? original.map(t => t.path) : [];
        state.index = index;
        state.position = mp.position;
    }
    function restore() {
        if (!state.queuePaths || state.queuePaths.length === 0) return;
        const q = Library.tracksFor(state.queuePaths);
        if (q.length === 0) return;
        queue = q;
        original = state.originalPaths && state.originalPaths.length ? Library.tracksFor(state.originalPaths) : q.slice();
        index = Math.max(0, Math.min(q.length - 1, state.index));
        mp.source = Library.url(current.path);
        resumeAt = state.position;
    }
    property real resumeAt: 0
    Timer { interval: 4000; repeat: true; running: pb.playing; onTriggered: state.position = mp.position }

    MediaPlayer {
        id: mp
        audioOutput: AudioOutput { volume: pb.muted ? 0 : pb.volume * pb.volume }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia) pb.next(true);
            else if ((mediaStatus === MediaPlayer.LoadedMedia || mediaStatus === MediaPlayer.BufferedMedia) && pb.resumeAt > 0) {
                position = pb.resumeAt;
                pb.resumeAt = 0;
            } else if (mediaStatus === MediaPlayer.InvalidMedia && pb.playing) pb.next(true);
        }
    }

    MediaSession {
        id: session
        name: "Muzyka"
        desktopEntry: "org.aster.music"
        status: pb.playing ? "Playing" : (pb.current ? "Paused" : "Stopped")
        title: pb.current ? pb.current.title : ""
        artist: pb.current ? pb.current.artist : ""
        album: pb.current ? (pb.current.albumTitle || pb.current.album || "") : ""
        artUrl: pb.coverUrl
        length: pb.duration
        position: mp.position
        canNext: pb.hasNext
        canPrevious: pb.current !== null
        volume: pb.volume
        shuffle: pb.shuffle
        loop: pb.repeat === "one" ? "Track" : (pb.repeat === "all" ? "Playlist" : "None")
        onPlayRequested: if (pb.current) mp.play()
        onPauseRequested: mp.pause()
        onPlayPauseRequested: pb.toggle()
        onStopRequested: { mp.pause(); pb.seek(0); }
        onNextRequested: pb.next(false)
        onPreviousRequested: pb.prev()
        onPositionRequested: (ms) => pb.seek(ms)
        onVolumeRequested: (v) => pb.setVolume(v)
        onShuffleRequested: (on) => pb.setShuffle(on)
        onLoopRequested: (l) => pb.repeat = l === "Track" ? "one" : (l === "Playlist" ? "all" : "none")
        onRaiseRequested: pb.raiseRequested()
        onQuitRequested: pb.quitRequested()
    }
}
