pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Browser

// Pobrane (aster://downloads): wszystkie pobrane pliki z postępem, prędkością i czynnościami
Item {
    id: dp
    signal open(string url, bool background)

    PageHeader {
        id: header
        title: "Pobrane"
        PillButton { text: "Otwórz folder"; onClicked: Qt.openUrlExternally("file://" + Browser.downloadDir) }
        PillButton { text: "Wyczyść listę"; enabled: Browser.downloads.length > Browser.activeDownloads; onClicked: Browser.clearDownloads() }
    }

    ListView {
        id: list
        anchors.top: header.bottom; anchors.bottom: parent.bottom
        width: Math.min(860, parent.width - 64)
        x: (parent.width - width) / 2
        clip: true
        spacing: 6
        bottomMargin: 40
        boundsBehavior: Flickable.StopAtBounds
        model: Browser.downloads
        delegate: DownloadRow { width: list.width; big: true }
        footer: Item {
            width: list.width; height: Browser.downloads.length ? 0 : 220
            Column {
                anchors.centerIn: parent
                spacing: 8
                visible: Browser.downloads.length === 0
                Icon { anchors.horizontalCenter: parent.horizontalCenter; d: Icons.download; size: 34; stroke: 1.6; color: Theme.text2 }
                Text { text: "Nic jeszcze nie pobrano"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 15 }
            }
        }
    }
}
