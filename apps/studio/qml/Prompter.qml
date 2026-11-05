import QtQuick
import Aster.Ui
import Aster.Studio

// Prompter w trakcie nagrywania: bieżący wers duży, z paskiem postępu do następnego, pod nim dwa kolejne.
// Przed pierwszym wersem — odliczanie miar („za 3”).
Rectangle {
    id: pr
    readonly property var lines: Studio.lyricLines
    readonly property var content: lines.filter((l) => l.kind === "line")
    readonly property real spb: 60 / Studio.bpm
    readonly property int cur: lines.length >= 0 ? Studio.lyricAt(Studio.position) : -1
    readonly property int k: {                 // numer bieżącego wersu wśród wersów (−1 przed pierwszym)
        for (let i = 0; i < content.length; ++i)
            if (content[i].line === cur) return i;
        return -1;
    }
    readonly property var now: k >= 0 ? content[k] : null
    readonly property var next1: content[k + 1] || null
    readonly property var next2: content[k + 2] || null
    readonly property real beatNow: Studio.position / spb
    readonly property int countdown: k < 0 && content.length > 0 ? Math.ceil(content[0].beat - beatNow) : 0
    height: 132; radius: 12
    color: Theme.pane
    border.width: 1; border.color: Theme.edge

    Column {
        x: 22; y: 14
        width: parent.width - 44
        spacing: 6
        Item {
            width: parent.width; height: 38
            Text {
                visible: !pr.now
                anchors.verticalCenter: parent.verticalCenter
                text: pr.countdown > 0 && pr.countdown <= 8 ? "Pierwszy wers za " + pr.countdown + "…" : "Pierwszy wers:"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 20; font.weight: Font.DemiBold
            }
            LyricText {
                visible: !!pr.now
                width: parent.width
                anchors.verticalCenter: parent.verticalCenter
                line: pr.now
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                font.pixelSize: 28; font.weight: Font.Bold
            }
        }
        // Ile wersu już minęło — do początku następnego
        Rectangle {
            width: parent.width; height: 3; radius: 1.5
            color: Theme.fill
            Rectangle {
                height: parent.height; radius: 1.5
                width: pr.now && pr.now.end > pr.now.beat ? parent.width * Math.max(0, Math.min(1, (pr.beatNow - pr.now.beat) / (pr.now.end - pr.now.beat))) : 0
                color: "#E5484D"
            }
        }
        LyricText {
            width: parent.width
            line: pr.now ? pr.next1 : pr.content[0] || null
            wrapMode: Text.NoWrap; elide: Text.ElideRight
            color: Theme.text
            opacity: 0.75
            font.pixelSize: 19; font.weight: Font.Medium
        }
        LyricText {
            width: parent.width
            line: pr.now ? pr.next2 : pr.content[1] || null
            rhymes: false
            wrapMode: Text.NoWrap; elide: Text.ElideRight
            color: Theme.text2
            opacity: 0.7
            font.pixelSize: 15
        }
    }
}
