pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Aster.Ui
import Aster.Vault

// Ekran startowy: po lewej znak programu i główne akcje, po prawej zapisane połączenia i ostatnie pliki
Item {
    id: start
    property real radius: 0
    signal newConnection()
    signal openFile()
    signal newFile()
    signal editConnection(var conn)
    signal connectionMenu(var conn, real x, real y)

    function kindColor(k) { return k === "postgres" ? "#4F6BED" : k === "mysql" ? "#E8833A" : "#2BA3C9"; }
    function kindLabel(k) { return k === "postgres" ? "PG" : k === "mysql" ? "My" : "SQ"; }
    function where(c) {
        if (c.kind === "sqlite") return c.file || "";
        return (c.user ? c.user + "@" : "") + (c.host || "localhost") + (c.port ? ":" + c.port : "") + (c.database ? " / " + c.database : "");
    }

    Item {
        id: left
        width: Math.min(380, parent.width * 0.42); height: parent.height
        DragHandler { target: null; onActiveChanged: if (active) start.Window.window.startSystemMove() }
        Column {
            x: 40; y: Math.round((parent.height - height) / 2)
            width: parent.width - 80
            AppIcon { anchors.horizontalCenter: parent.horizontalCenter; desktopId: "org.aster.vault"; size: 104 }
            Item { width: 1; height: 22 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Aster Vault"
                color: Theme.text; font.family: Theme.font; font.pixelSize: 30; font.weight: Font.DemiBold; font.letterSpacing: -0.4
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 4
                text: "SQLite · PostgreSQL · MySQL / MariaDB"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
            }
            Item { width: 1; height: 30 }
            Action { width: parent.width; icon: "plus"; label: "Nowe połączenie…"; hint: "Ctrl+N"; primary: true; onClicked: start.newConnection() }
            Item { width: 1; height: 8 }
            Action { width: parent.width; icon: "folder"; label: "Otwórz plik SQLite…"; hint: "Ctrl+O"; onClicked: start.openFile() }
            Item { width: 1; height: 8 }
            Action { width: parent.width; icon: "filePlus"; label: "Nowa baza SQLite…"; onClicked: start.newFile() }
            Item { width: 1; height: 26 }
            Text {
                width: parent.width; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                text: "Asystent Aster i terminal czytają bazy przez aster-vault --query (tylko odczyt)."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
            }
        }
    }

    GlassPane {
        id: right
        x: left.width
        width: parent.width - left.width; height: parent.height
        topRightRadius: start.radius; bottomRightRadius: start.radius
        DragHandler { target: null; onActiveChanged: if (active) start.Window.window.startSystemMove() }

        WindowButtons {
            window: start.Window.window
            anchors.right: parent.right; anchors.rightMargin: 16
            y: 18
        }
        Text {
            x: 40; y: 26
            text: "POŁĄCZENIA"
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 0.4
        }

        ListView {
            id: list
            x: 28; y: 54
            width: parent.width - 56; height: parent.height - y - 16
            clip: true
            spacing: 2
            model: Vault.connections
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                width: ListView.view.width; height: 58
                radius: 12
                color: rowArea.containsMouse ? Theme.hover : "transparent"
                Rectangle {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    width: 36; height: 36; radius: 10
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(start.kindColor(row.modelData.kind), 1.35) }
                        GradientStop { position: 1; color: start.kindColor(row.modelData.kind) }
                    }
                    Icon { anchors.centerIn: parent; d: Icons.database; size: 18; stroke: 1.9; color: "white" }
                }
                Column {
                    x: 60; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 60 - 120
                    spacing: 3
                    Row {
                        spacing: 8
                        Text { text: row.modelData.name || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                        Rectangle {
                            visible: !!row.modelData.readOnly
                            anchors.verticalCenter: parent.verticalCenter
                            width: roText.implicitWidth + 12; height: 18; radius: 9
                            color: Theme.fill
                            Text { id: roText; anchors.centerIn: parent; text: "tylko odczyt"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Medium }
                        }
                    }
                    Text {
                        width: parent.width; elide: Text.ElideMiddle
                        text: start.where(row.modelData)
                        color: Theme.text2; font.family: "JetBrains Mono"; font.pixelSize: 11
                    }
                }
                Text {
                    anchors.right: more.left; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.kind === "postgres" ? "PostgreSQL" : row.modelData.kind === "mysql" ? "MySQL" : "SQLite"
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (m) => {
                        if (m.button === Qt.RightButton) {
                            const p = mapToItem(start, m.x, m.y);
                            start.connectionMenu(row.modelData, p.x, p.y);
                        } else {
                            Vault.open(row.modelData.id);
                        }
                    }
                }
                ToolBtn {
                    id: more
                    anchors.right: parent.right; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "more"
                    onClicked: { const p = mapToItem(start, 0, height); start.connectionMenu(row.modelData, p.x - 210, p.y + 4); }
                }
            }
        }

        // Pusto: zachęta
        Column {
            visible: Vault.connections.length === 0
            anchors.centerIn: parent
            spacing: 10
            width: 320
            Icon { anchors.horizontalCenter: parent.horizontalCenter; d: Icons.database; size: 44; stroke: 1.4; color: Theme.text2; opacity: 0.6 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Brak połączeń"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Medium }
            Text {
                width: parent.width; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                text: "Dodaj serwer PostgreSQL albo MySQL, albo otwórz plik SQLite — pojawi się tutaj."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.2
            }
        }
    }

    component Action: HoverButton {
        id: act
        property string icon
        property string label
        property string hint
        property bool primary: false
        height: 44; radius: 12
        opacity: enabled ? 1 : 0.45
        baseColor: primary ? Theme.accent : Theme.fill
        color: hovered && enabled ? (primary ? Qt.darker(Theme.accent, 1.08) : Theme.hover) : baseColor
        Icon { x: 16; anchors.verticalCenter: parent.verticalCenter; d: Icons[act.icon] || ""; size: 17; stroke: 1.9; color: act.primary ? "white" : Theme.text }
        Text { x: 44; anchors.verticalCenter: parent.verticalCenter; text: act.label; color: act.primary ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
        Text {
            anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
            text: act.hint; color: act.primary ? Qt.rgba(1, 1, 1, 0.75) : Theme.text2; font.family: Theme.font; font.pixelSize: 12
        }
    }
}
