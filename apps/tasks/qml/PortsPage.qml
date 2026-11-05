pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Tasks

// Porty: kto nasłuchuje na którym porcie. „Port 3000 zajęty” → widać program i jednym kliknięciem go zamykasz.
Item {
    id: page
    property alias filter: ports.filter
    signal endRequested(string key, bool force)

    readonly property real portW: 92
    readonly property real protoW: 70
    readonly property real scopeW: 168
    readonly property real pidW: 76
    readonly property real actionsW: 188

    PortModel { id: ports; active: page.visible }
    function focusList() { list.forceActiveFocus(); }

    // ——— Nagłówki ———
    Item {
        id: head
        width: parent.width; height: 44
        Row {
            x: 22; anchors.bottom: parent.bottom; anchors.bottomMargin: 10
            HeadText { width: page.portW; text: "Port" }
            HeadText { width: page.protoW; text: "Protokół" }
            HeadText { width: list.width - 22 - page.portW - page.protoW - page.scopeW - page.pidW - page.actionsW; text: "Program" }
            HeadText { width: page.scopeW; text: "Dostępny z" }
            HeadText { width: page.pidW; text: "PID" }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
    }

    ListView {
        id: list
        y: head.height
        width: parent.width; height: parent.height - y - foot.height
        clip: true
        model: ports
        boundsBehavior: Flickable.StopAtBounds
        delegate: PortRow {}
    }

    // Pusto: nic nie nasłuchuje albo filtr niczego nie znalazł
    Column {
        visible: list.count === 0
        anchors.centerIn: list
        spacing: 8
        Icon { anchors.horizontalCenter: parent.horizontalCenter; d: Icons.globe; size: 34; color: Theme.text2 }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: ports.filter ? "Żaden program nie używa portu „" + ports.filter + "”" : "Żaden program nie nasłuchuje na porcie"
            color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Medium
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: ports.filter !== ""
            text: "Ten port jest wolny — możesz uruchomić na nim swój serwer."
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
        }
    }

    Text {
        id: foot
        anchors.bottom: parent.bottom
        x: 22; width: parent.width - 44; height: ports.hidden > 0 ? 34 : 0
        visible: ports.hidden > 0
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: "Części portów używa system albo inny użytkownik — ich program widać dopiero z uprawnieniami administratora."
        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
    }

    component HeadText: Text {
        color: Theme.text2
        font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
        elide: Text.ElideRight
    }

    component PortRow: Item {
        id: row
        required property int port
        required property string proto
        required property string scope
        required property int pid
        required property string name
        required property string command
        required property string key
        required property bool own
        width: list.width; height: 46

        Rectangle {
            anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
            radius: 8
            color: rowArea.containsMouse ? Theme.hover : "transparent"
        }
        MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

        Row {
            x: 22; anchors.verticalCenter: parent.verticalCenter
            Text {
                width: page.portW; anchors.verticalCenter: parent.verticalCenter
                text: row.port
                color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
            Item {
                width: page.protoW; height: 22; anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    width: protoText.implicitWidth + 14; height: 20; radius: 6
                    anchors.verticalCenter: parent.verticalCenter
                    color: row.proto === "TCP" ? Theme.accentSoft : Theme.fill
                    Text {
                        id: protoText
                        anchors.centerIn: parent
                        text: row.proto
                        color: row.proto === "TCP" ? Theme.accentText : Theme.text2
                        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                    }
                }
            }
            Column {
                width: list.width - 22 - page.portW - page.protoW - page.scopeW - page.pidW - page.actionsW
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    width: parent.width - 12
                    text: row.name
                    elide: Text.ElideRight
                    color: row.pid ? Theme.text : Theme.text2
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                }
                Text {
                    width: parent.width - 12
                    visible: row.command !== "" && row.command !== row.name
                    text: row.command
                    elide: Text.ElideMiddle
                    color: Theme.text2; font.family: "JetBrains Mono"; font.pixelSize: 11
                }
            }
            Text {
                width: page.scopeW; anchors.verticalCenter: parent.verticalCenter
                text: row.scope
                elide: Text.ElideRight
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
            }
            Text {
                width: page.pidW; anchors.verticalCenter: parent.verticalCenter
                text: row.pid ? row.pid : "—"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                font.features: { "tnum": 1 }
            }
        }

        // Akcje — widoczne zawsze, żeby nie trzeba było szukać
        Row {
            anchors.right: parent.right; anchors.rightMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            HoverButton {
                // Serwery stron: 80/443 i porty programistów (3000, 5173, 8080…), nie SSH, poczta czy DNS
                visible: row.proto === "TCP" && (row.port === 80 || row.port === 443 || row.port >= 1024)
                width: openText.implicitWidth + 22; height: 30; radius: 10
                baseColor: Theme.fill
                color: hovered ? Theme.hover : baseColor
                onClicked: ports.openInBrowser(row.port)
                Text { id: openText; anchors.centerIn: parent; text: "Otwórz"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
            }
            HoverButton {
                enabled: row.pid > 0
                opacity: enabled ? 1 : 0.4
                width: endText.implicitWidth + 22; height: 30; radius: 10
                baseColor: row.own ? "#E5484D" : Theme.fill
                color: hovered && enabled ? (row.own ? "#D93B40" : Theme.hover) : baseColor
                onClicked: page.endRequested(row.key, false)
                Text {
                    id: endText
                    anchors.centerIn: parent
                    text: "Zakończ"
                    color: row.own ? "white" : Theme.text
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                }
            }
        }
    }
}
