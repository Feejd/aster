pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Zmiany w repozytorium gita: gałąź, pliki zmienione, nowe i usunięte — klik otwiera plik.
// Zatwierdzanie (commit) i wysyłanie — w terminalu; własny widok w dalszych krokach.
Item {
    id: cv
    signal openFile(string path)

    function statusColor(s) {
        if (s === "A" || s === "U") return Theme.dark ? "#3FB950" : "#1A7F37";
        if (s === "D" || s === "C") return Theme.dark ? "#F85149" : "#CF222E";
        if (s === "R") return Theme.dark ? "#58A6FF" : "#0969DA";
        return Theme.dark ? "#D29922" : "#9A6700";
    }
    function statusName(s) {
        return { M: "zmieniony", A: "dodany", U: "nowy", D: "usunięty", R: "przemianowany", C: "konflikt" }[s] || "";
    }

    Column {
        id: head
        x: 10; width: parent.width - 20
        spacing: 6
        visible: Project.isGit
        Rectangle {
            width: parent.width; height: 40; radius: 10
            color: Theme.fill
            Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; d: Icons.gitBranch; size: 16; color: Theme.accentText }
            Text {
                x: 36; width: parent.width - 36 - 90
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: Project.branch || "—"
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Project.ahead > 0 || Project.behind > 0
                    text: (Project.behind ? "↓" + Project.behind + " " : "") + (Project.ahead ? "↑" + Project.ahead : "")
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.features: { "tnum": 1 }
                }
                HoverButton {
                    width: 28; height: 28; radius: 7
                    onClicked: Project.refreshGit()
                    Icon { anchors.centerIn: parent; d: Icons.reload; size: 14; color: Theme.text2 }
                }
            }
        }
        Text {
            leftPadding: 4; topPadding: 4
            text: Project.changes.length === 0 ? "Brak zmian — wszystko zatwierdzone"
                : "ZMIANY · " + Project.changes.length
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 0.4
        }
    }

    ListView {
        visible: Project.isGit
        y: head.height + 6
        width: parent.width; height: parent.height - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: Project.changes
        delegate: Item {
            id: row
            required property var modelData
            width: ListView.view.width; height: 30
            Rectangle {
                anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                radius: 7
                color: rowArea.containsMouse ? Theme.hover : "transparent"
            }
            FileIcon { x: 16; anchors.verticalCenter: parent.verticalCenter; name: row.modelData.name; isDir: row.modelData.isDir; size: 15 }
            Text {
                id: nm
                x: 40; anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - 40 - 40)
                elide: Text.ElideRight
                text: row.modelData.name
                color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                font.strikeout: row.modelData.status === "D"
            }
            Text {
                anchors.left: nm.right; anchors.leftMargin: 6
                anchors.right: letter.left; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideLeft
                text: row.modelData.dir; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
            }
            Text {
                id: letter
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.status
                color: cv.statusColor(row.modelData.status)
                font.family: "JetBrains Mono"; font.pixelSize: 12; font.weight: Font.Bold
            }
            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: if (row.modelData.status !== "D" && !row.modelData.isDir) cv.openFile(row.modelData.path)
            }
        }
    }

    Column {
        visible: !Project.isGit
        anchors.centerIn: parent
        width: parent.width - 40
        spacing: 8
        Icon { anchors.horizontalCenter: parent.horizontalCenter; d: Icons.gitBranch; size: 34; stroke: 1.4; color: Theme.text2; opacity: 0.6 }
        Text {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: "Ten folder nie jest repozytorium gita.\nW terminalu: git init"
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
        }
    }
}
