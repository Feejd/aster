import QtQuick
import Aster.Ui
import Aster.Browser

// Wiersz pobranego pliku (lista w dymku i na stronie Pobrane):
// ikona rodzaju pliku, nazwa, postęp albo stan, a z prawej czynności
Rectangle {
    id: row
    required property var modelData
    readonly property var d: modelData
    property bool big: false
    readonly property bool active: d.active
    readonly property bool done: d.state === DownloadItem.Completed
    readonly property bool failed: d.state === DownloadItem.Cancelled || d.state === DownloadItem.Interrupted

    height: big ? 68 : 58
    radius: 12
    color: area.containsMouse ? Theme.hover : (big ? (Theme.dark ? Qt.rgba(1, 1, 1, 0.03) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.025)) : "transparent")

    readonly property string ext: d.fileName.indexOf(".") > 0 ? d.fileName.split(".").pop().toLowerCase() : ""
    readonly property var kind: ({
        pdf: ["doc", "#E5484D"], doc: ["doc", "#2B6CEB"], docx: ["doc", "#2B6CEB"], odt: ["doc", "#2B6CEB"], txt: ["doc", "#6B7280"],
        xls: ["sheet", "#1F9D55"], xlsx: ["sheet", "#1F9D55"], ods: ["sheet", "#1F9D55"], csv: ["sheet", "#1F9D55"],
        jpg: ["image", "#C026D3"], jpeg: ["image", "#C026D3"], png: ["image", "#C026D3"], gif: ["image", "#C026D3"], webp: ["image", "#C026D3"], svg: ["image", "#C026D3"],
        mp3: ["music", "#F43F5E"], flac: ["music", "#F43F5E"], wav: ["music", "#F43F5E"], ogg: ["music", "#F43F5E"],
        mp4: ["video", "#7C3AED"], mkv: ["video", "#7C3AED"], webm: ["video", "#7C3AED"], mov: ["video", "#7C3AED"],
        zip: ["drive", "#B7791F"], gz: ["drive", "#B7791F"], xz: ["drive", "#B7791F"], "7z": ["drive", "#B7791F"], rar: ["drive", "#B7791F"],
        rpm: ["bag", "#0E9F6E"], flatpakref: ["bag", "#0E9F6E"], appimage: ["bag", "#0E9F6E"], exe: ["bag", "#6B7280"], iso: ["drive", "#6B7280"]
    })[ext] || ["download", Theme.accent]

    Rectangle {
        id: icon
        x: 10; anchors.verticalCenter: parent.verticalCenter
        width: row.big ? 44 : 38; height: width; radius: width * 0.3
        color: Qt.rgba(Qt.color(row.kind[1]).r, Qt.color(row.kind[1]).g, Qt.color(row.kind[1]).b, Theme.dark ? 0.22 : 0.13)
        opacity: row.failed || (row.done && !row.d.exists) ? 0.5 : 1
        Icon { anchors.centerIn: parent; d: Icons[row.kind[0]] || Icons.download; size: icon.width * 0.45; stroke: 1.9; color: Theme.dark ? Qt.lighter(row.kind[1], 1.4) : row.kind[1] }
    }

    Column {
        anchors.left: icon.right; anchors.leftMargin: 12
        anchors.right: actions.left; anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 5
        Text {
            width: parent.width
            text: row.d.fileName
            elide: Text.ElideMiddle
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
            font.strikeout: row.done && !row.d.exists
        }
        Rectangle {
            visible: row.active
            width: parent.width; height: 4; radius: 2
            color: Theme.line
            Rectangle {
                height: parent.height; radius: 2
                width: parent.width * Math.max(0.03, row.d.progress < 0 ? 0.3 : row.d.progress)
                color: row.d.state === DownloadItem.Paused ? Theme.text2 : Theme.accent
                Behavior on width { NumberAnimation { duration: 150 } }
            }
        }
        Text {
            width: parent.width
            elide: Text.ElideRight
            text: {
                const d = row.d;
                if (d.state === DownloadItem.Paused) return "Wstrzymano · " + Urls.size(d.received) + (d.total > 0 ? " z " + Urls.size(d.total) : "");
                if (row.active) {
                    const parts = [Urls.size(d.received) + (d.total > 0 ? " z " + Urls.size(d.total) : "")];
                    if (d.speed > 0) parts.push(Urls.size(d.speed) + "/s");
                    const left = Urls.remaining(d.total - d.received, d.speed);
                    if (left) parts.push(left);
                    return parts.join(" · ");
                }
                if (d.state === DownloadItem.Cancelled) return "Anulowano";
                if (d.state === DownloadItem.Interrupted) return "Przerwano" + (d.error ? " — " + d.error : "");
                if (!d.exists) return "Plik usunięto albo przeniesiono";
                return [Urls.size(d.total), Urls.host(d.url), new Date(d.time).toLocaleString(Qt.locale("pl_PL"), "d MMM, HH:mm")].filter(s => s).join(" · ");
            }
            color: row.d.state === DownloadItem.Interrupted ? Theme.danger : Theme.text2
            font.family: Theme.font; font.pixelSize: 12
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: row.done && row.d.exists ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (row.done) row.d.open()
    }

    Row {
        id: actions
        anchors.right: parent.right; anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        RowButton {
            visible: row.active
            icon: row.d.state === DownloadItem.Paused ? "play" : "pause"
            onClicked: if (row.d.state === DownloadItem.Paused) row.d.resume(); else row.d.pause()
        }
        RowButton { visible: row.done && row.d.exists; icon: "folder"; onClicked: row.d.showInFolder() }
        RowButton {
            visible: row.active || row.big || area.containsMouse
            icon: "close"
            onClicked: if (row.active) row.d.cancel(); else Browser.removeDownload(row.d)
        }
    }

    component RowButton: HoverButton {
        property string icon
        width: 32; height: 32
        Icon { anchors.centerIn: parent; d: Icons[parent.icon] || ""; size: 15; stroke: 1.9; color: Theme.text2 }
    }
}
