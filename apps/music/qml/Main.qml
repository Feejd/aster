pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Dialogs
import Aster.Ui
import Aster.Music

// Muzyka Aster (zamiast Elisy): albumy z okładkami, wykonawcy, wszystkie utwory i kolejka,
// a na dole — pasek odtwarzania (losowo, powtarzanie, głośność). Gra dalej, gdy przeglądasz.
Window {
    id: win
    width: 1180 + 2 * m
    height: 760 + 2 * m
    minimumWidth: 760 + 2 * m
    minimumHeight: 480 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: pb.current && pb.playing ? pb.current.title + " — Muzyka" : "Muzyka"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 24

    Playback {
        id: pb
        onRaiseRequested: { if (win.visibility === Window.Minimized) win.showNormal(); win.raise(); win.requestActivate(); }
        onQuitRequested: win.close()
    }

    // ——— Nawigacja ———
    property string section: "albums"           // albums | artists | songs | queue
    property var stack: []                       // szczegóły: { kind: "album", key } | { kind: "artist", name }
    readonly property var detail: stack.length ? stack[stack.length - 1] : null
    property string search: ""
    function go(s) { section = s; stack = []; search = ""; searchInput.text = ""; }
    function openAlbum(key) { stack = stack.concat([{ kind: "album", key: key }]); }
    function openArtist(name) { stack = stack.concat([{ kind: "artist", name: name }]); }
    function back() { stack = stack.slice(0, -1); }

    // Zależność od Library.albums/tracks: po ponownym skanie szczegóły się odświeżą
    readonly property var albumData: { Library.albums; return detail && detail.kind === "album" ? Library.album(detail.key) : null; }
    readonly property var artistData: { Library.tracks; return detail && detail.kind === "artist" ? Library.artist(detail.name) : null; }

    function matches(t, q) {
        return t.title.toLowerCase().indexOf(q) >= 0 || t.artist.toLowerCase().indexOf(q) >= 0
            || String(t.albumTitle || "").toLowerCase().indexOf(q) >= 0;
    }
    readonly property var shownAlbums: {
        const q = search.trim().toLowerCase();
        if (!q) return Library.albums;
        return Library.albums.filter(a => a.title.toLowerCase().indexOf(q) >= 0 || a.artist.toLowerCase().indexOf(q) >= 0);
    }
    readonly property var shownArtists: {
        const q = search.trim().toLowerCase();
        return q ? Library.artists.filter(a => a.name.toLowerCase().indexOf(q) >= 0) : Library.artists;
    }
    readonly property var shownTracks: {
        const q = search.trim().toLowerCase();
        return q ? Library.tracks.filter(t => win.matches(t, q)) : Library.tracks;
    }

    // Pliki z wiersza poleceń / drugiego uruchomienia — grają od razu
    function playFiles(files) {
        const list = Library.tracksFor(files);
        if (list.length > 0) { pb.play(list, 0); go("queue"); }
    }
    Connections {
        target: Library
        function onOpenRequested(files) {
            if (files.length > 0) win.playFiles(files);
            if (win.visibility === Window.Minimized) win.showNormal();
            win.raise(); win.requestActivate();
        }
    }
    Component.onCompleted: {
        effectsTimer.restart();
        if (Library.pendingFiles.length > 0) playFiles(Library.pendingFiles);
        else pb.restore();
    }

    // ——— Menu ———
    function trackMenu(tracks, i, item, x, y, queueIndex) {
        menu.tracks = [tracks[i]];
        menu.queueIndex = queueIndex === undefined ? -1 : queueIndex;
        const t = tracks[i];
        const items = [{ label: "Odtwórz", icon: "play", action: "play" },
                       { label: "Odtwórz jako następny", icon: "next", action: "next" },
                       { label: "Dodaj do kolejki", icon: "playlist", action: "enqueue" },
                       { separator: true }];
        if (menu.queueIndex >= 0) items.push({ label: "Usuń z kolejki", icon: "close", action: "dequeue", enabled: menu.queueIndex !== pb.index }, { separator: true });
        if (t.albumKey) items.push({ label: "Przejdź do albumu", icon: "disc", action: "album:" + t.albumKey });
        items.push({ label: "Przejdź do wykonawcy", icon: "user", action: "artist:" + t.artist });
        items.push({ label: "Pokaż w folderze", icon: "folder", action: "folder:" + t.path });
        const p = item.mapToItem(frame, x, y);
        menu.openAt(p.x, p.y, items);
    }
    function albumMenu(key, item, x, y) {
        const a = Library.album(key);
        menu.tracks = a.tracks || [];
        menu.queueIndex = -1;
        const p = item.mapToItem(frame, x, y);
        menu.openAt(p.x, p.y, [{ label: "Odtwórz", icon: "play", action: "play" },
                              { label: "Odtwórz losowo", icon: "shuffle", action: "shuffle" },
                              { label: "Odtwórz jako następny", icon: "next", action: "next" },
                              { label: "Dodaj do kolejki", icon: "playlist", action: "enqueue" },
                              { separator: true },
                              { label: "Przejdź do wykonawcy", icon: "user", action: "artist:" + a.artist },
                              { label: "Pokaż w folderze", icon: "folder", action: "showdir:" + a.folder }]);
    }
    function runMenu(a) {
        const n = menu.tracks.length;
        if (a === "play") pb.play(menu.tracks, 0);
        else if (a === "shuffle") pb.play(menu.tracks, undefined, true);
        else if (a === "next") { pb.playNext(menu.tracks); toast(n === 1 ? "Zagra jako następny" : "Zagrają jako następne"); }
        else if (a === "enqueue") { pb.enqueue(menu.tracks); toast("Dodano do kolejki: " + (n === 1 ? "„" + menu.tracks[0].title + "”" : Library.songs(n))); }
        else if (a === "dequeue") pb.remove(menu.queueIndex);
        else if (a.startsWith("album:")) { if (section === "queue") section = "albums"; openAlbum(a.substring(6)); }
        else if (a.startsWith("artist:")) { if (section === "queue") section = "artists"; openArtist(a.substring(7)); }
        else if (a.startsWith("folder:")) Library.showInFolder(a.substring(7));
        else if (a.startsWith("showdir:")) Qt.openUrlExternally("file://" + a.substring(8));
    }

    function toast(text) { toastBox.text = text; toastBox.shown = true; toastTimer.restart(); }

    FolderDialog {
        id: folderDialog
        title: "Dodaj folder z muzyką"
        onAccepted: Library.addFolder(String(selectedFolder))
    }

    // Skróty jak w Windows Media Player
    Shortcut { sequences: ["Ctrl+P"]; onActivated: pb.toggle() }
    Shortcut { sequences: ["Ctrl+F", "Ctrl+Right"]; onActivated: pb.next(false) }
    Shortcut { sequences: ["Ctrl+B", "Ctrl+Left"]; onActivated: pb.prev() }
    Shortcut { sequences: ["Ctrl+H"]; onActivated: pb.setShuffle(!pb.shuffle) }
    Shortcut { sequences: ["Ctrl+T"]; onActivated: pb.cycleRepeat() }
    Shortcut { sequences: ["Ctrl+E", "Ctrl+K"]; onActivated: searchInput.forceActiveFocus() }
    Shortcut { sequences: ["Ctrl+Up"]; onActivated: pb.setVolume(pb.volume + 0.05) }
    Shortcut { sequences: ["Ctrl+Down"]; onActivated: pb.setVolume(pb.volume - 0.05) }
    Shortcut { sequences: ["Alt+Left", "Backspace"]; enabled: win.stack.length > 0 && !searchInput.activeFocus; onActivated: win.back() }

    // Do testów (ASTER_OPEN, kroki po „;”): play | album | artist | songs | queue | menu | search:tekst | dark
    function testOpen(what) {
        if (what === "play") pb.play(Library.album(Library.albums[1].key).tracks, 1);
        else if (what === "album") openAlbum(Library.albums[1].key);
        else if (what === "artist") { section = "artists"; openArtist("Jezioro"); }
        else if (what === "songs") go("songs");
        else if (what === "queue") go("queue");
        else if (what === "artists") go("artists");
        else if (what === "menu") trackMenu(albumData.tracks, 2, albumPage, 400, 420);
        else if (what.startsWith("search:")) { searchInput.text = what.substring(7); }
        else if (what === "pause") pb.toggle();
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

        // ——— Pasek boczny ———
        Item {
            id: side
            width: 220; height: parent.height - bar.height
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }

            Column {
                x: 10; y: 58
                width: parent.width - 20
                spacing: 2
                NavItem { key: "albums"; label: "Albumy"; icon: "disc"; colors: ["#FFA394", "#E2283E"] }
                NavItem { key: "artists"; label: "Wykonawcy"; icon: "user"; colors: ["#FFC48A", "#EA6A12"] }
                NavItem { key: "songs"; label: "Utwory"; icon: "music"; colors: ["#E6A4FF", "#7330E0"] }
                NavItem { key: "queue"; label: "Kolejka"; icon: "playlist"; colors: ["#74CCFF", "#2457E6"]; badge: pb.queue.length > 0 ? String(pb.queue.length) : "" }

                Text {
                    topPadding: 22; bottomPadding: 6; leftPadding: 10
                    text: "FOLDERY"
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.6
                }
                Repeater {
                    model: Library.folders
                    delegate: HoverButton {
                        id: folderItem
                        required property var modelData
                        width: parent.width; height: 32; radius: 9
                        onClicked: Qt.openUrlExternally("file://" + modelData.path)
                        Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; d: Icons.folder; size: 15; color: Theme.text2 }
                        Text {
                            x: 38; width: parent.width - 46 - (removeBtn.visible ? 26 : 0)
                            anchors.verticalCenter: parent.verticalCenter
                            text: folderItem.modelData.name
                            elide: Text.ElideRight
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 13
                        }
                        HoverButton {
                            id: removeBtn
                            visible: folderItem.modelData.removable && folderItem.hovered || hovered
                            anchors.right: parent.right; anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24; radius: 6
                            onClicked: Library.removeFolder(folderItem.modelData.path)
                            Icon { anchors.centerIn: parent; d: Icons.close; size: 12; stroke: 2; color: Theme.text2 }
                        }
                    }
                }
                HoverButton {
                    width: parent.width; height: 32; radius: 9
                    onClicked: folderDialog.open()
                    Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; d: Icons.plus; size: 15; stroke: 2; color: Theme.text2 }
                    Text { x: 38; anchors.verticalCenter: parent.verticalCenter; text: "Dodaj folder…"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                }
            }
        }

        // ——— Treść ———
        GlassPane {
            id: main
            x: side.width
            width: parent.width - side.width
            height: parent.height - bar.height
            topRightRadius: win.r

            Item {
                id: topBar
                width: parent.width; height: 68
                z: 5
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }
                HoverButton {
                    id: backBtn
                    visible: win.stack.length > 0
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 34; radius: 17
                    onClicked: win.back()
                    Icon { anchors.centerIn: parent; d: Icons.back; size: 17; stroke: 2; color: Theme.text }
                }
                Column {
                    x: backBtn.visible ? 60 : 28
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    visible: !win.detail
                    Text {
                        text: ({ albums: "Albumy", artists: "Wykonawcy", songs: "Utwory", queue: "Kolejka" })[win.section]
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4
                    }
                    Text {
                        text: Library.loading && Library.tracks.length === 0 ? "Szukam muzyki…"
                            : win.section === "albums" ? Library.albumsCount(win.shownAlbums.length)
                            : win.section === "artists" ? win.shownArtists.length + " wykonawców".replace(/^1 wykonawców$/, "1 wykonawca")
                            : win.section === "songs" ? Library.songs(win.shownTracks.length)
                            : (pb.queue.length ? Library.songs(pb.queue.length) : "Pusta")
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 12
                    }
                }
                Row {
                    anchors.right: winButtons.left; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    // Szukaj (Ctrl+E)
                    Rectangle {
                        visible: !win.detail && win.section !== "queue"
                        width: 220; height: 34; radius: 17
                        color: Theme.fill
                        border.width: searchInput.activeFocus ? 2 : 0
                        border.color: Theme.accent
                        Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 15; color: Theme.text2 }
                        TextInput {
                            id: searchInput
                            x: 36; width: parent.width - 48
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.text
                            selectionColor: Theme.accentSoft
                            selectedTextColor: Theme.text
                            font.family: Theme.font; font.pixelSize: 13
                            clip: true
                            onTextChanged: win.search = text
                            Keys.onEscapePressed: { text = ""; focus = false; }
                            Text {
                                visible: !parent.text
                                text: "Szukaj"
                                color: Theme.text2
                                font: parent.font
                            }
                        }
                    }
                    PillButton {
                        visible: win.section === "queue" && pb.queue.length > 0 && !win.detail
                        text: "Wyczyść"; icon: "trash"
                        onClicked: pb.clear()
                    }
                    PillButton {
                        visible: !win.detail && win.section !== "queue" && Library.tracks.length > 0
                        text: "Losowo"; icon: "shuffle"; primary: true
                        onClicked: pb.play(win.section === "songs" ? win.shownTracks : Library.tracks, undefined, true)
                    }
                }
                WindowButtons {
                    id: winButtons
                    window: win
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Item {
                id: content
                y: topBar.height
                width: parent.width; height: parent.height - y

                // Albumy
                GridView {
                    id: albumGrid
                    visible: win.section === "albums" && !win.detail
                    x: 18; width: parent.width - 36; height: parent.height
                    readonly property int cols: Math.max(2, Math.floor(width / 196))
                    cellWidth: Math.floor(width / cols); cellHeight: cellWidth + 52
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: win.shownAlbums
                    delegate: AlbumTile {
                        required property var modelData
                        album: modelData
                        width: albumGrid.cellWidth; height: albumGrid.cellHeight
                    }
                }

                // Wykonawcy
                GridView {
                    id: artistGrid
                    visible: win.section === "artists" && !win.detail
                    x: 18; width: parent.width - 36; height: parent.height
                    readonly property int cols: Math.max(2, Math.floor(width / 176))
                    cellWidth: Math.floor(width / cols); cellHeight: cellWidth + 46
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: win.shownArtists
                    delegate: Item {
                        id: artistTile
                        required property var modelData
                        width: artistGrid.cellWidth; height: artistGrid.cellHeight
                        Cover {
                            x: 12; y: 4
                            width: parent.width - 24; height: width; radius: width / 2
                            source: artistTile.modelData.cover
                            icon: "user"
                            hovered: artistArea.containsMouse
                        }
                        Text {
                            y: artistTile.width - 24 + 14; width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: artistTile.modelData.name
                            elide: Text.ElideRight
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                        Text {
                            y: artistTile.width - 24 + 33; width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: Library.songs(artistTile.modelData.songs)
                            color: Theme.text2
                            font.family: Theme.font; font.pixelSize: 12
                        }
                        MouseArea {
                            id: artistArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.openArtist(artistTile.modelData.name)
                        }
                    }
                }

                // Utwory
                Item {
                    visible: win.section === "songs" && !win.detail
                    anchors.fill: parent
                    ColumnHeader { id: songsHeader; x: 18; width: parent.width - 36; list: songList }
                    TrackList {
                        id: songList
                        x: 18; y: songsHeader.height
                        width: parent.width - 36; height: parent.height - y
                        tracks: win.shownTracks
                        numbers: false
                        playingPath: pb.current ? pb.current.path : ""
                        playing: pb.playing
                        onActivated: (i) => pb.play(win.shownTracks, i)
                        onMenuRequested: (i, x, y) => win.trackMenu(win.shownTracks, i, songList, x, y)
                    }
                }

                // Kolejka
                Item {
                    id: queuePage
                    visible: win.section === "queue" && !win.detail
                    anchors.fill: parent
                    Column {
                        id: nowPlaying
                        visible: pb.current !== null
                        x: 28; y: 6
                        width: Math.min(300, parent.width * 0.32)
                        spacing: 6
                        Cover {
                            width: parent.width; height: width; radius: 14
                            source: pb.current ? pb.current.cover : ""
                            big: true
                        }
                        Item { width: 1; height: 8 }
                        Text {
                            width: parent.width
                            text: pb.current ? pb.current.title : ""
                            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 19; font.weight: Font.Bold
                        }
                        Text {
                            width: parent.width
                            text: pb.current ? pb.current.artist + (pb.current.albumTitle ? " · " + pb.current.albumTitle : "") : ""
                            elide: Text.ElideRight
                            color: Theme.text2
                            font.family: Theme.font; font.pixelSize: 13
                        }
                    }
                    TrackList {
                        id: queueList
                        visible: pb.queue.length > 0
                        x: nowPlaying.x + nowPlaying.width + 28
                        width: parent.width - x - 18; height: parent.height
                        tracks: pb.queue
                        numbers: false
                        showAlbum: width > 640
                        playingIndex: pb.index
                        playing: pb.playing
                        onActivated: (i) => pb.jump(i)
                        onMenuRequested: (i, x, y) => win.trackMenu(pb.queue, i, queueList, x, y, i)
                    }
                    EmptyState {
                        visible: pb.queue.length === 0
                        icon: "playlist"
                        title: "Kolejka jest pusta"
                        hint: "Odtwórz album lub utwór — albo dodaj go do kolejki z menu (prawy przycisk)."
                    }
                }

                // Pusta biblioteka
                EmptyState {
                    visible: !win.detail && win.section !== "queue" && Library.tracks.length === 0 && !Library.loading
                    icon: "music"
                    title: "Brak muzyki"
                    hint: "Utwory z folderu Muzyka pojawią się tutaj. Inne foldery dodasz przyciskiem „Dodaj folder…” po lewej."
                }

                // ——— Album ———
                Flickable {
                    id: albumPage
                    visible: !!win.albumData
                    anchors.fill: parent
                    contentHeight: albumTracks.y + albumTracks.height + 30
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Cover {
                        id: albumCover
                        x: 28; y: 4
                        width: 190; height: 190; radius: 14
                        source: win.albumData ? win.albumData.cover : ""
                        big: true
                    }
                    Column {
                        x: albumCover.x + albumCover.width + 26
                        width: parent.width - x - 28
                        anchors.bottom: albumCover.bottom
                        spacing: 6
                        Text { text: "ALBUM"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.8 }
                        Text {
                            width: parent.width
                            text: win.albumData ? win.albumData.title : ""
                            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 30; font.weight: Font.Bold; font.letterSpacing: -0.6
                        }
                        Text {
                            text: win.albumData ? win.albumData.artist : ""
                            color: Theme.accentText
                            font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Medium
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.openArtist(win.albumData.artist) }
                        }
                        Text {
                            text: win.albumData ? [win.albumData.year > 0 ? win.albumData.year : "", Library.songs(win.albumData.count), Library.total(win.albumData.duration)].filter(s => s !== "").join(" · ") : ""
                            color: Theme.text2
                            font.family: Theme.font; font.pixelSize: 13
                        }
                        Item { width: 1; height: 6 }
                        Row {
                            spacing: 8
                            PillButton { text: "Odtwórz"; icon: "play"; primary: true; onClicked: pb.play(win.albumData.tracks, 0) }
                            PillButton { text: "Losowo"; icon: "shuffle"; onClicked: pb.play(win.albumData.tracks, undefined, true) }
                            PillButton { text: ""; icon: "more"; onClicked: { const p = mapToItem(albumPage, 0, height + 4); win.albumMenu(win.albumData.key, albumPage, p.x, p.y); } }
                        }
                    }
                    TrackList {
                        id: albumTracks
                        x: 18; y: albumCover.y + albumCover.height + 24
                        width: parent.width - 36
                        height: contentHeight
                        interactive: false
                        tracks: win.albumData ? win.albumData.tracks : []
                        showAlbum: false
                        showArtist: win.albumData && win.albumData.artist === "Różni wykonawcy"
                        playingPath: pb.current ? pb.current.path : ""
                        playing: pb.playing
                        onActivated: (i) => pb.play(win.albumData.tracks, i)
                        onMenuRequested: (i, x, y) => win.trackMenu(win.albumData.tracks, i, albumTracks, x, y)
                    }
                }

                // ——— Wykonawca ———
                Flickable {
                    id: artistPage
                    visible: !!win.artistData
                    anchors.fill: parent
                    contentHeight: artistCol.implicitHeight + 30
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: artistCol
                        x: 28; width: parent.width - 56
                        spacing: 14
                        Row {
                            spacing: 22
                            Cover {
                                width: 132; height: 132; radius: 66
                                source: win.artistData && win.artistData.albums.length ? win.artistData.albums[0].cover : ""
                                icon: "user"
                                big: true
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Text { text: "WYKONAWCA"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.8 }
                                Text {
                                    text: win.artistData ? win.artistData.name : ""
                                    color: Theme.text
                                    font.family: Theme.font; font.pixelSize: 30; font.weight: Font.Bold; font.letterSpacing: -0.6
                                }
                                Text {
                                    text: win.artistData ? Library.albumsCount(win.artistData.albums.length) + " · " + Library.songs(win.artistData.tracks.length) : ""
                                    color: Theme.text2
                                    font.family: Theme.font; font.pixelSize: 13
                                }
                                Item { width: 1; height: 4 }
                                Row {
                                    spacing: 8
                                    PillButton { text: "Odtwórz"; icon: "play"; primary: true; onClicked: pb.play(win.artistData.tracks, 0) }
                                    PillButton { text: "Losowo"; icon: "shuffle"; onClicked: pb.play(win.artistData.tracks, undefined, true) }
                                }
                            }
                        }
                        Text {
                            topPadding: 10
                            text: "Albumy"
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                        }
                        Flow {
                            x: -10
                            width: parent.width + 20
                            Repeater {
                                model: win.artistData ? win.artistData.albums : []
                                delegate: AlbumTile {
                                    required property var modelData
                                    album: modelData
                                    width: 180; height: 232
                                }
                            }
                        }
                        Text {
                            text: "Utwory"
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                        }
                        TrackList {
                            id: artistTracks
                            x: -10
                            width: parent.width + 20
                            height: contentHeight
                            interactive: false
                            tracks: win.artistData ? win.artistData.tracks : []
                            numbers: false
                            showArtist: false
                            playingPath: pb.current ? pb.current.path : ""
                            playing: pb.playing
                            onActivated: (i) => pb.play(win.artistData.tracks, i)
                            onMenuRequested: (i, x, y) => win.trackMenu(win.artistData.tracks, i, artistTracks, x, y)
                        }
                    }
                }
            }
        }

        // ——— Pasek odtwarzania ———
        Item {
            id: bar
            anchors.bottom: parent.bottom
            width: parent.width; height: 88
            Rectangle { width: parent.width; height: 1; color: Theme.line }

            // Co gra
            Item {
                x: 16; width: Math.min(320, parent.width * 0.28); height: parent.height
                Cover {
                    id: barCover
                    anchors.verticalCenter: parent.verticalCenter
                    width: 56; height: 56; radius: 9
                    source: pb.current ? pb.current.cover : ""
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.go("queue") }
                }
                Column {
                    x: barCover.width + 14; width: parent.width - x
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Text {
                        width: Math.min(implicitWidth, parent.width)
                        text: pb.current ? pb.current.title : "Nic nie gra"
                        elide: Text.ElideRight
                        color: pb.current ? Theme.text : Theme.text2
                        font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        MouseArea {
                            anchors.fill: parent
                            enabled: !!pb.current && !!pb.current.albumKey
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: { if (win.section === "queue") win.section = "albums"; win.stack = [{ kind: "album", key: pb.current.albumKey }]; }
                        }
                    }
                    Text {
                        width: Math.min(implicitWidth, parent.width)
                        text: pb.current ? pb.current.artist : ""
                        elide: Text.ElideRight
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 12
                        MouseArea {
                            anchors.fill: parent
                            enabled: !!pb.current
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { if (win.section === "queue") win.section = "artists"; win.stack = [{ kind: "artist", name: pb.current.artist }]; }
                        }
                    }
                }
            }

            // Sterowanie i postęp
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(560, parent.width * 0.42)
                spacing: 4
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 10
                    BarBtn { icon: "shuffle"; active: pb.shuffle; tip: pb.shuffle ? "Losowo: wł. (Ctrl+H)" : "Losowo: wył. (Ctrl+H)"; onClicked: pb.setShuffle(!pb.shuffle) }
                    BarBtn { icon: "prev"; enabled: !!pb.current; tip: "Poprzedni (Ctrl+B)"; onClicked: pb.prev() }
                    HoverButton {
                        width: 42; height: 42; radius: 21
                        anchors.verticalCenter: parent.verticalCenter
                        baseColor: Theme.text
                        color: hovered ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.82) : baseColor
                        onClicked: pb.toggle()
                        Icon {
                            anchors.centerIn: parent; anchors.horizontalCenterOffset: pb.playing ? 0 : 1
                            d: pb.playing ? Icons.pause : Icons.play
                            size: 19; stroke: 2.4
                            color: Theme.dark ? "#16181D" : "white"
                            fill: pb.playing ? "transparent" : (Theme.dark ? "#16181D" : "white")
                        }
                    }
                    BarBtn { icon: "next"; enabled: pb.hasNext; tip: "Następny (Ctrl+F)"; onClicked: pb.next(false) }
                    BarBtn {
                        icon: pb.repeat === "one" ? "repeatOne" : "repeat"
                        active: pb.repeat !== "none"
                        tip: pb.repeat === "none" ? "Powtarzaj: wył. (Ctrl+T)" : pb.repeat === "all" ? "Powtarzaj wszystko" : "Powtarzaj jeden"
                        onClicked: pb.cycleRepeat()
                    }
                }
                Item {
                    width: parent.width; height: 18
                    Text {
                        id: posText
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42; horizontalAlignment: Text.AlignRight
                        text: Library.time(seek.dragging ? seek.dragPos : pb.position)
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 11; font.features: { "tnum": 1 }
                    }
                    Slider {
                        id: seek
                        x: 52; width: parent.width - 104
                        anchors.verticalCenter: parent.verticalCenter
                        value: pb.duration > 0 ? pb.position / pb.duration : 0
                        enabled: !!pb.current
                        readonly property real dragPos: dragValue * pb.duration
                        onMoved: (v) => pb.seek(v * pb.duration)
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42
                        text: Library.time(pb.duration)
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 11; font.features: { "tnum": 1 }
                    }
                }
            }

            // Kolejka i głośność
            Row {
                anchors.right: parent.right; anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                BarBtn { icon: "playlist"; active: win.section === "queue" && !win.detail; tip: "Kolejka"; onClicked: win.go("queue") }
                BarBtn {
                    icon: pb.muted || pb.volume === 0 ? "volumeOff" : (pb.volume < 0.5 ? "volumeLow" : "volume")
                    tip: pb.muted ? "Włącz dźwięk" : "Wycisz"
                    onClicked: pb.muted = !pb.muted
                }
                Slider {
                    width: 100
                    anchors.verticalCenter: parent.verticalCenter
                    value: pb.muted ? 0 : pb.volume
                    onMoved: (v) => pb.setVolume(v)
                    WheelHandler { onWheel: (e) => pb.setVolume(pb.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05)) }
                }
            }
        }

        // Komunikat
        Rectangle {
            id: toastBox
            property bool shown: false
            property alias text: toastText.text
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - bar.height - (shown ? height + 18 : 0)
            opacity: shown ? 1 : 0
            z: 300
            width: toastText.implicitWidth + 36; height: 40; radius: 20
            color: Theme.dark ? "#ECEEF3" : "#1E2027"
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Text { id: toastText; anchors.centerIn: parent; color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
            Timer { id: toastTimer; interval: 3500; onTriggered: toastBox.shown = false }
        }

        DropArea {
            anchors.fill: parent
            onDropped: (drop) => win.playFiles(drop.urls.map(u => decodeURIComponent(String(u).replace(/^file:\/\//, ""))))
        }

        ContextMenu {
            id: menu
            property var tracks: []
            property int queueIndex: -1
            onTriggered: (a) => win.runMenu(a)
        }
    }

    // ——— Elementy ———
    component NavItem: Rectangle {
        id: nav
        property string key
        property string label
        property string icon
        property var colors
        property string badge
        readonly property bool active: win.section === key
        width: parent ? parent.width : 0; height: 34
        radius: 9
        color: active ? Theme.accent : (navArea.containsMouse ? Theme.hover : "transparent")
        Rectangle {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; radius: 7
            gradient: Gradient {
                GradientStop { position: 0; color: nav.colors[0] }
                GradientStop { position: 1; color: nav.colors[1] }
            }
            Icon { anchors.centerIn: parent; d: Icons[nav.icon] || ""; size: 14; stroke: 2; color: "white" }
        }
        Text {
            x: 42; anchors.verticalCenter: parent.verticalCenter
            text: nav.label
            color: nav.active ? "white" : Theme.text
            font.family: Theme.font; font.pixelSize: 13; font.weight: nav.active ? Font.Medium : Font.Normal
        }
        Text {
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: nav.badge
            color: nav.active ? Qt.rgba(1, 1, 1, 0.8) : Theme.text2
            font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 }
        }
        MouseArea { id: navArea; anchors.fill: parent; hoverEnabled: true; onClicked: win.go(nav.key) }
    }

    // Okładka albo plakietka z ikoną, gdy jej brak
    component Cover: Rectangle {
        id: cov
        property string source
        property string icon: "music"
        property bool hovered: false
        property bool big: false
        color: Theme.dark ? "#22252E" : "#E4E7EE"
        RoundImage {
            id: covImg
            anchors.fill: parent
            source: cov.source
            radius: cov.radius
        }
        Icon {
            visible: !covImg.ready
            anchors.centerIn: parent
            d: Icons[cov.icon] || ""
            size: Math.max(18, cov.width * 0.3); stroke: 1.4
            color: Theme.text2
        }
        Rectangle {
            anchors.fill: parent; radius: cov.radius
            color: "transparent"
            border.width: 1; border.color: Theme.edge
        }
    }

    // Kafelek albumu: okładka (z „odtwórz” pod kursorem), tytuł, wykonawca
    component AlbumTile: Item {
        id: tile
        property var album
        Cover {
            id: tileCover
            x: 10; y: 4
            width: parent.width - 20; height: width; radius: 12
            source: tile.album.cover
            icon: "disc"
            scale: tileArea.pressed ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: 100 } }
        }
        HoverButton {
            x: tileCover.x + tileCover.width - width - 10
            y: tileCover.y + tileCover.height - height - 10
            width: 40; height: 40; radius: 20
            visible: tileArea.containsMouse || hovered
            baseColor: Theme.accent
            color: hovered ? Qt.lighter(Theme.accent, 1.12) : baseColor
            z: 2
            onClicked: pb.play(Library.album(tile.album.key).tracks, 0)
            Icon { anchors.centerIn: parent; anchors.horizontalCenterOffset: 1; d: Icons.play; size: 17; color: "white"; fill: "white" }
        }
        Text {
            x: 10; y: tileCover.y + tileCover.height + 9
            width: tileCover.width
            text: tile.album.title
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
        }
        Text {
            x: 10; y: tileCover.y + tileCover.height + 28
            width: tileCover.width
            text: tile.album.artist + (tile.album.year > 0 ? " · " + tile.album.year : "")
            elide: Text.ElideRight
            color: Theme.text2
            font.family: Theme.font; font.pixelSize: 12
        }
        MouseArea {
            id: tileArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (e) => {
                if (e.button === Qt.RightButton) win.albumMenu(tile.album.key, tile, e.x, e.y);
                else win.openAlbum(tile.album.key);
            }
        }
    }

    component PillButton: HoverButton {
        id: pill
        property string text
        property string icon
        property bool primary: false
        width: pillRow.implicitWidth + (text ? 30 : 20); height: 34; radius: 17
        baseColor: primary ? Theme.accent : Theme.fill
        color: primary ? (hovered ? Qt.lighter(Theme.accent, 1.12) : baseColor) : (hovered ? Theme.hover : baseColor)
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 7
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                d: Icons[pill.icon] || ""
                size: 15; stroke: 2
                color: pill.primary ? "white" : Theme.text
                fill: pill.icon === "play" ? (pill.primary ? "white" : Theme.text) : "transparent"
            }
            Text {
                visible: pill.text !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: pill.text
                color: pill.primary ? "white" : Theme.text
                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
            }
        }
    }

    component BarBtn: HoverButton {
        id: bb
        property string icon
        property bool active: false
        property string tip
        width: 34; height: 34; radius: 17
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        opacity: enabled ? 1 : 0.35
        Icon { anchors.centerIn: parent; d: Icons[bb.icon] || ""; size: 18; stroke: 1.9; color: bb.active ? Theme.accentText : Theme.text }
        Rectangle {
            visible: bb.active
            anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 4
            width: 4; height: 4; radius: 2; color: Theme.accentText
        }
        Rectangle {
            visible: bb.hovered && bb.tip !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            y: -height - 8
            width: tipText.implicitWidth + 18; height: 26; radius: 7
            color: Theme.dark ? "#ECEEF3" : "#1E2027"
            Text { id: tipText; anchors.centerIn: parent; text: bb.tip; color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 12 }
        }
    }

    // Poziomy suwak (postęp, głośność): grubieje pod kursorem
    component Slider: Item {
        id: sl
        property real value: 0
        readonly property bool dragging: sa.pressed
        property real dragValue: 0
        signal moved(real v)
        height: 16
        readonly property real shown: dragging ? dragValue : Math.max(0, Math.min(1, value))
        readonly property bool hot: sa.containsMouse || dragging
        opacity: enabled ? 1 : 0.4
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: sl.hot ? 5 : 4; radius: height / 2
            color: Theme.fill
            Rectangle { width: parent.width * sl.shown; height: parent.height; radius: parent.radius; color: sl.hot ? Theme.accent : Theme.text2 }
        }
        Rectangle {
            visible: sl.hot
            x: sl.width * sl.shown - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 13; height: 13; radius: 6.5
            color: "white"
            border.width: 1; border.color: Theme.edge
        }
        MouseArea {
            id: sa
            anchors.fill: parent; anchors.margins: -4
            hoverEnabled: true
            enabled: sl.enabled
            function at(x) { return Math.max(0, Math.min(1, (x - 4) / sl.width)); }
            onPressed: (e) => { sl.dragValue = at(e.x); }
            onPositionChanged: (e) => { if (pressed) sl.dragValue = at(e.x); }
            onReleased: sl.moved(sl.dragValue)
        }
    }

    component ColumnHeader: Item {
        id: hdr
        property TrackList list
        height: 34
        Text { x: 56; anchors.verticalCenter: parent.verticalCenter; text: "Tytuł"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
        Text { x: hdr.list.colTitle; anchors.verticalCenter: parent.verticalCenter; text: "Wykonawca"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
        Text { x: hdr.list.colTitle + hdr.list.colArtist; anchors.verticalCenter: parent.verticalCenter; text: "Album"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
        Text { anchors.right: parent.right; anchors.rightMargin: 46; anchors.verticalCenter: parent.verticalCenter; text: "Czas"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
    }

    component EmptyState: Column {
        id: es
        property string icon
        property string title
        property string hint
        anchors.centerIn: parent
        width: Math.min(parent ? parent.width - 60 : 400, 380)
        spacing: 12
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 76; height: 76; radius: 22
            color: Theme.fill
            Icon { anchors.centerIn: parent; d: Icons[es.icon] || ""; size: 34; stroke: 1.6; color: Theme.text2 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: es.title
            color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: es.hint
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.25
        }
    }
}
