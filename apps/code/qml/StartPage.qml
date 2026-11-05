pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Okno startowe (bez otwartego folderu): po lewej znak programu i główne akcje, po prawej ostatnie
// foldery — jak ekran powitalny Xcode, z podpowiedzią skrótów znanych z VS Code.
Item {
    id: start
    property real radius: 0
    signal openFolder()
    signal newApp()
    signal openRecent(string path)

    // Lewa kolumna — na szkle okna
    Item {
        id: left
        width: Math.min(400, parent.width * 0.45); height: parent.height
        Column {
            x: 40; y: Math.round((parent.height - height) / 2)
            width: parent.width - 80
            spacing: 0
            AppIcon { anchors.horizontalCenter: parent.horizontalCenter; desktopId: "org.aster.code"; size: 104 }
            Item { width: 1; height: 22 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Aster Code"
                color: Theme.text; font.family: Theme.font; font.pixelSize: 30; font.weight: Font.DemiBold; font.letterSpacing: -0.4
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: 4
                text: "Wersja 1.0 · edytor kodu"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
            }
            Item { width: 1; height: 30 }
            Action { width: parent.width; icon: "folder"; label: "Otwórz folder…"; hint: "Ctrl+O"; primary: true; onClicked: start.openFolder() }
            Action { width: parent.width; icon: "sparkle"; label: "Nowa aplikacja…"; hint: "frontend, backend, baza"; onClicked: start.newApp() }
            Item { width: 1; height: 8 }
            Action {
                width: parent.width; icon: "reload"; label: "Otwórz ostatni"; hint: Project.recent.length ? Project.recent[0].name : ""
                enabled: Project.recent.length > 0
                onClicked: start.openRecent(Project.recent[0].path)
            }
            Item { width: 1; height: 34 }
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Repeater {
                    model: [["Ctrl+P", "Szybkie otwieranie pliku"], ["Ctrl+Shift+P", "Wszystkie polecenia"],
                            ["Ctrl+Shift+F", "Szukaj w projekcie"], ["Ctrl+`", "Terminal"]]
                    delegate: Item {
                        id: tip
                        required property var modelData
                        width: 290; height: 22
                        Rectangle {
                            anchors.right: parent.left; anchors.rightMargin: -100
                            width: keyText.implicitWidth + 14; height: 22; radius: 6
                            color: Theme.fill
                            Text { id: keyText; anchors.centerIn: parent; text: tip.modelData[0]; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
                        }
                        Text {
                            x: 112; anchors.verticalCenter: parent.verticalCenter
                            text: tip.modelData[1]; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }

    // Prawa kolumna — ostatnie foldery na panelu treści
    GlassPane {
        x: left.width
        width: parent.width - left.width; height: parent.height
        topRightRadius: start.radius; bottomRightRadius: start.radius
        Column {
            x: 28; y: 64
            width: parent.width - 56
            spacing: 2
            Text { text: "OSTATNIE"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium; font.letterSpacing: 0.4; leftPadding: 12; bottomPadding: 8 }
            Repeater {
                model: Project.recent
                delegate: Rectangle {
                    id: rec
                    required property var modelData
                    width: parent.width; height: 54; radius: 12
                    color: recArea.containsMouse ? Theme.hover : "transparent"
                    Rectangle {
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        width: 34; height: 34; radius: 9
                        color: Theme.accentAlpha(Theme.dark ? 0.2 : 0.1)
                        Icon { anchors.centerIn: parent; d: Icons.folder; size: 18; color: Theme.accentText }
                    }
                    Column {
                        x: 56; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 56 - 40
                        spacing: 2
                        Row {
                            spacing: 8
                            Text { text: rec.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                            Icon { visible: rec.modelData.git; anchors.verticalCenter: parent.verticalCenter; d: Icons.gitBranch; size: 13; color: Theme.text2 }
                        }
                        Text { width: parent.width; elide: Text.ElideMiddle; text: rec.modelData.pretty; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    MouseArea { id: recArea; anchors.fill: parent; hoverEnabled: true; onClicked: start.openRecent(rec.modelData.path) }
                    HoverButton {
                        visible: recArea.containsMouse || hovered
                        anchors.right: parent.right; anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26; height: 26; radius: 7
                        onClicked: Project.forgetRecent(rec.modelData.path)
                        Icon { anchors.centerIn: parent; d: Icons.close; size: 12; stroke: 2; color: Theme.text2 }
                    }
                }
            }
            Column {
                visible: Project.recent.length === 0
                width: parent.width
                topPadding: 60
                spacing: 8
                Icon { anchors.horizontalCenter: parent.horizontalCenter; d: Icons.folder; size: 40; stroke: 1.4; color: Theme.text2; opacity: 0.6 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Tu pojawią się otwierane foldery"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
            }
        }
    }

    component Action: HoverButton {
        id: act
        property string icon
        property string label
        property string hint
        property bool primary: false
        height: 46; radius: 12
        opacity: enabled ? 1 : 0.45
        baseColor: primary ? Theme.accent : Theme.fill
        color: hovered && enabled ? (primary ? Qt.darker(Theme.accent, 1.1) : Theme.hover) : baseColor
        Icon { x: 16; anchors.verticalCenter: parent.verticalCenter; d: Icons[act.icon] || ""; size: 18; color: act.primary ? "white" : Theme.text }
        Text { x: 46; anchors.verticalCenter: parent.verticalCenter; text: act.label; color: act.primary ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
        Text {
            anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, act.width - 200); elide: Text.ElideRight
            text: act.hint; color: act.primary ? Qt.rgba(1, 1, 1, 0.8) : Theme.text2; font.family: Theme.font; font.pixelSize: 12
        }
    }
}
