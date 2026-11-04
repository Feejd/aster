pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Tasks

// Porty: kto nasłuchuje na którym porcie — serwery projektów, bazy, usługi systemu.
// Własny serwer można otworzyć w przeglądarce albo zakończyć (np. gdy „port 3000 jest zajęty”).
Item {
    id: page
    Component.onCompleted: Ports.active = true
    Component.onDestruction: Ports.active = false

    readonly property var mine: Ports.ports.filter(p => p.mine)
    readonly property var system: Ports.ports.filter(p => !p.mine)

    Flickable {
        anchors.fill: parent
        anchors.margins: 14
        contentHeight: col.height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: col
            width: parent.width
            spacing: 6

            Text {
                text: "Twoje programy"
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                topPadding: 2; bottomPadding: 2
            }
            Text {
                visible: page.mine.length === 0
                width: parent.width
                wrapMode: Text.Wrap
                text: "Żaden twój program nie nasłuchuje teraz na porcie. Tu pojawią się serwery projektów (np. npm run dev) i bazy danych."
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 13
                bottomPadding: 8
            }
            Repeater {
                model: page.mine
                delegate: PortRow {}
            }

            Text {
                visible: page.system.length > 0
                text: "System i inni użytkownicy"
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                topPadding: 12; bottomPadding: 2
            }
            Repeater {
                model: page.system
                delegate: PortRow {}
            }
        }
    }

    component PortRow: Rectangle {
        id: row
        required property var modelData
        readonly property bool web: modelData.proto === "TCP" && modelData.mine
        width: col.width
        height: 56
        radius: 12
        color: rowArea.containsMouse ? Theme.hover : Theme.fill
        MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true }

        Rectangle {
            id: badge
            x: 10; anchors.verticalCenter: parent.verticalCenter
            width: 74; height: 34; radius: 9
            color: row.modelData.mine ? Theme.accentSoft : Qt.rgba(0.5, 0.5, 0.55, 0.15)
            Column {
                anchors.centerIn: parent
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: row.modelData.port
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: row.modelData.proto
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: 9
                }
            }
        }
        Column {
            anchors.left: badge.right; anchors.leftMargin: 12
            anchors.right: buttons.left; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: row.modelData.mine ? row.modelData.program + "  ·  PID " + row.modelData.pid : "Usługa systemu"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
            }
            Text {
                width: parent.width
                elide: Text.ElideMiddle
                text: (row.modelData.local ? "Tylko ten komputer" : "Widoczny w sieci")
                      + (row.modelData.folder ? "  ·  " + row.modelData.folder : "")
                color: row.modelData.local ? Theme.text2 : "#D97706"
                font.family: Theme.font; font.pixelSize: 11
            }
        }
        Row {
            id: buttons
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            PillButton {
                visible: row.web
                text: "Otwórz"
                onClicked: Ports.openInBrowser(row.modelData.port)
            }
            PillButton {
                visible: row.modelData.mine
                text: "Zakończ"
                onClicked: Ports.end(row.modelData.pid, false)
            }
        }
    }

    component PillButton: Rectangle {
        id: pb
        property string text
        signal clicked()
        width: pbText.implicitWidth + 22; height: 28; radius: 14
        color: pbArea.containsMouse ? Theme.accent : Theme.accentSoft
        Text {
            id: pbText
            anchors.centerIn: parent
            text: pb.text
            color: pbArea.containsMouse ? "white" : Theme.text
            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
        }
        MouseArea { id: pbArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pb.clicked() }
    }
}
