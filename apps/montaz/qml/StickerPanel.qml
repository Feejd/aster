pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Montaz

// Naklejki: wzory Aster i emoji (z wyszukiwaniem po polsku). Klik dodaje naklejkę jako nakładkę w miejscu głowicy.
Item {
    id: sp
    property var editor
    property string group: "smileys"
    property string query: ""
    property string sub: "shapes"            // "shapes" (wzory Aster) albo "emoji"
    onQueryChanged: if (query) sub = "emoji"
    readonly property var emojiList: query.trim().length > 0 ? Stickers.search(query) : Stickers.emoji(group)

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            x: 12
            width: parent.width - 24
            spacing: 10

            Row {
                spacing: 6
                Repeater {
                    model: [{ id: "shapes", name: "Wzory" }, { id: "emoji", name: "Emoji" }]
                    delegate: HoverButton {
                        id: sb
                        required property var modelData
                        readonly property bool on: sp.sub === modelData.id
                        width: sbText.implicitWidth + 22; height: 26; radius: 13
                        baseColor: on ? Theme.accent : Theme.fill
                        color: on ? Theme.accent : (hovered ? Theme.hover : baseColor)
                        onClicked: sp.sub = modelData.id
                        Text { id: sbText; anchors.centerIn: parent; text: sb.modelData.name; color: sb.on ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                    }
                }
            }

            Grid {
                visible: sp.sub === "shapes"
                columns: 2
                spacing: 8
                Repeater {
                    model: Stickers.builtins
                    delegate: Item {
                        id: bt
                        required property var modelData
                        width: (col.width - 8) / 2; height: 70
                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: btArea.containsMouse ? Theme.hover : Theme.fill
                            border.width: btArea.containsMouse ? 1 : 0
                            border.color: Theme.accentAlpha(0.6)
                        }
                        Image {
                            anchors.centerIn: parent
                            width: parent.width - 16; height: parent.height - 16
                            fillMode: Image.PreserveAspectFit
                            source: bt.modelData.url
                            sourceSize.width: 200
                            asynchronous: true
                        }
                        MouseArea {
                            id: btArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: sp.editor.addSticker(Stickers.builtinFile(bt.modelData.id), bt.modelData.name, 0.5)
                        }
                    }
                }
            }

            Rectangle {
                visible: sp.sub === "emoji"
                width: parent.width; height: 32; radius: 9
                color: Theme.fill
                border.width: search.activeFocus ? 1 : 0
                border.color: Theme.accentAlpha(0.6)
                Icon { x: 9; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 14; color: Theme.text2 }
                TextInput {
                    id: search
                    x: 30; width: parent.width - 40
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 13
                    clip: true
                    text: sp.query
                    onTextChanged: sp.query = text
                    Keys.onEscapePressed: { text = ""; focus = false; }
                    Text {
                        visible: !search.text
                        text: "Szukaj: serce, ogień, śmiech…"
                        color: Theme.text2
                        font: search.font
                    }
                }
            }
            Flow {
                visible: sp.sub === "emoji" && sp.query.trim().length === 0
                width: parent.width
                spacing: 3
                Repeater {
                    model: Stickers.groups
                    delegate: Rectangle {
                        id: gb
                        required property var modelData
                        width: 30; height: 30; radius: 8
                        color: sp.group === modelData.id ? Theme.accentSoft : (gbArea.containsMouse ? Theme.hover : "transparent")
                        Text { anchors.centerIn: parent; text: gb.modelData.icon; font.family: "Noto Color Emoji"; font.pixelSize: 17 }
                        MouseArea { id: gbArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sp.group = gb.modelData.id }
                    }
                }
            }
            Grid {
                visible: sp.sub === "emoji"
                columns: Math.floor(parent.width / 38)
                Repeater {
                    model: sp.emojiList
                    delegate: Rectangle {
                        id: em
                        required property var modelData
                        width: 38; height: 38; radius: 8
                        color: emArea.containsMouse ? Theme.hover : "transparent"
                        Text { anchors.centerIn: parent; text: em.modelData.c; font.family: "Noto Color Emoji"; font.pixelSize: 24 }
                        MouseArea {
                            id: emArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: sp.editor.addSticker(Stickers.emojiFile(em.modelData.c), em.modelData.n, 0.3)
                        }
                    }
                }
            }
            Text {
                visible: sp.query.trim().length > 0 && sp.emojiList.length === 0
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Nic nie znaleziono"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
        }
    }
}
