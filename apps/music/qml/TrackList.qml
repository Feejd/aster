pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Music

// Lista utworów: numer (albo okładka), tytuł, wykonawca, album, czas. Grający utwór — w kolorze
// akcentu z ikoną głośnika. Dwuklik lub Enter odtwarza; pod numerem po najechaniu — „odtwórz”.
ListView {
    id: list
    property var tracks: []
    property bool numbers: true             // numer utworu z albumu (inaczej mała okładka)
    property bool showArtist: true
    property bool showAlbum: true
    property string playingPath: ""
    property bool playing: false
    property int playingIndex: -1           // w kolejce: grający po pozycji, nie po ścieżce
    signal activated(int index)
    signal menuRequested(int index, real x, real y)

    model: tracks
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    currentIndex: -1
    keyNavigationEnabled: true
    Keys.onReturnPressed: if (currentIndex >= 0) activated(currentIndex)

    readonly property real colTitle: width * (showAlbum ? 0.40 : 0.58)
    readonly property real colArtist: showArtist ? width * (showAlbum ? 0.24 : 0.28) : 0

    delegate: Rectangle {
        id: row
        required property var modelData
        required property int index
        readonly property bool isPlaying: list.playingIndex >= 0 ? index === list.playingIndex : modelData.path === list.playingPath
        width: ListView.view.width
        height: 46
        radius: 9
        color: ListView.isCurrentItem && list.activeFocus ? Theme.accentSoft
             : rowArea.containsMouse ? Theme.hover
             : (index % 2 ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.02) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.02)) : "transparent")
        readonly property color fg: isPlaying ? Theme.accentText : Theme.text

        // Numer / okładka / „gra”
        Item {
            id: lead
            x: 10; width: 36; height: parent.height
            Text {
                visible: list.numbers && !row.isPlaying && !rowArea.containsMouse
                anchors.centerIn: parent
                text: row.modelData.track > 0 ? row.modelData.track : "·"
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 13; font.features: { "tnum": 1 }
            }
            Rectangle {
                visible: !list.numbers
                anchors.centerIn: parent
                width: 34; height: 34; radius: 6
                color: Theme.fill
                RoundImage {
                    anchors.fill: parent
                    source: row.modelData.cover || ""
                    radius: 6
                }
                Icon { anchors.centerIn: parent; visible: !row.modelData.cover; d: Icons.music; size: 15; color: Theme.text2 }
                Rectangle {
                    anchors.fill: parent; radius: 6
                    visible: rowArea.containsMouse || row.isPlaying
                    color: Qt.rgba(0, 0, 0, 0.45)
                }
            }
            Icon {
                visible: rowArea.containsMouse && !(row.isPlaying && list.playing)
                anchors.centerIn: parent
                d: Icons.play; size: 15
                color: list.numbers ? Theme.text : "white"
                fill: list.numbers ? Theme.text : "white"
            }
            // Grający utwór: głośnik (przygaszony, gdy wstrzymany)
            Icon {
                visible: row.isPlaying && (list.playing || !rowArea.containsMouse)
                anchors.centerIn: parent
                d: Icons.volume; size: 16
                color: list.numbers ? Theme.accentText : "white"
                opacity: list.playing ? 1 : 0.55
            }
        }
        Text {
            x: 56; width: list.colTitle - 66
            anchors.verticalCenter: parent.verticalCenter
            text: row.modelData.title
            elide: Text.ElideRight
            color: row.fg
            font.family: Theme.font; font.pixelSize: 13; font.weight: row.isPlaying ? Font.DemiBold : Font.Medium
        }
        Text {
            visible: list.showArtist
            x: list.colTitle; width: list.colArtist - 14
            anchors.verticalCenter: parent.verticalCenter
            text: row.modelData.artist
            elide: Text.ElideRight
            color: row.isPlaying ? row.fg : Theme.text2
            font.family: Theme.font; font.pixelSize: 13
        }
        Text {
            visible: list.showAlbum
            x: list.colTitle + list.colArtist; width: parent.width - x - 80
            anchors.verticalCenter: parent.verticalCenter
            text: row.modelData.albumTitle || row.modelData.album || ""
            elide: Text.ElideRight
            color: row.isPlaying ? row.fg : Theme.text2
            font.family: Theme.font; font.pixelSize: 13
        }
        Text {
            anchors.right: parent.right; anchors.rightMargin: 46
            anchors.verticalCenter: parent.verticalCenter
            text: Library.time(row.modelData.duration)
            color: row.isPlaying ? row.fg : Theme.text2
            font.family: Theme.font; font.pixelSize: 13; font.features: { "tnum": 1 }
        }
        HoverButton {
            anchors.right: parent.right; anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 32; height: 30
            opacity: rowArea.containsMouse || hovered ? 1 : 0
            onClicked: { const p = mapToItem(list, width / 2, height); list.menuRequested(row.index, p.x - 200, p.y); }
            Icon { anchors.centerIn: parent; d: Icons.more; size: 16; color: Theme.text2 }
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            anchors.rightMargin: 40
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: mouseX < lead.x + lead.width ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: (e) => {
                // Klik w numer / okładkę odtwarza od razu
                if (e.button === Qt.LeftButton && e.x < lead.x + lead.width) { list.activated(row.index); return; }
                list.currentIndex = row.index;
                list.forceActiveFocus();
                if (e.button === Qt.RightButton) {
                    const p = mapToItem(list, e.x, e.y);
                    list.menuRequested(row.index, p.x, p.y);
                }
            }
            onDoubleClicked: (e) => { if (e.button === Qt.LeftButton) list.activated(row.index); }
        }
    }
}
