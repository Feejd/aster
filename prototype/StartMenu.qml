import QtQuick
import "Icons.js" as I

// Start = wyszukiwarka: puste pole pokazuje przypięte i ostatnie, wpisanie tekstu — wyniki
Panel {
    id: sm
    property var apps: []
    property var files: []
    property alias query: field.text
    property int selected: 0

    signal launch(string name)
    signal openFile(string id)
    signal lockRequested()
    signal closeRequested()

    width: 680
    height: 640
    originX: 0
    originY: 1

    readonly property var results: {
        const q = field.text.trim().toLowerCase();
        if (!q) return [];
        const out = [];
        for (const a of apps)
            if (a.name.toLowerCase().indexOf(q) >= 0) out.push({ kind: "app", name: a.name, sub: "Aplikacja", color: a.color, icon: a.icon });
        for (const f of files)
            if (f.name.toLowerCase().indexOf(q) >= 0) out.push({ kind: "file", id: f.id, name: f.name, sub: f.where, color: f.tint, icon: f.badge });
        const settings = ["Tryb ciemny", "Wi-Fi", "Bluetooth", "Oszczędzanie baterii", "Tapeta", "Drukarki", "Dźwięk"];
        for (const s of settings)
            if (s.toLowerCase().indexOf(q) >= 0) out.push({ kind: "setting", name: s, sub: "Ustawienia", color: "#535A68", icon: "sliders" });
        out.push({ kind: "ask", name: "Zapytaj asystenta: „" + field.text.trim() + "”", sub: "Tab", color: "", icon: "sparkle" });
        return out;
    }

    onResultsChanged: selected = 0
    onOpenChanged: {
        if (open) {
            field.text = "";
            field.forceActiveFocus();
        }
    }

    function activate(i) {
        const r = results[i];
        if (r && r.kind === "app") sm.launch(r.name);
        else if (r && r.kind === "file") sm.openFile(r.id);
        sm.closeRequested();
    }

    Column {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 14

        Rectangle {
            width: parent.width; height: 48
            radius: 12
            color: sm.t.surface
            border.width: field.activeFocus ? 1.5 : 1
            border.color: field.activeFocus ? sm.t.accent : sm.t.line
            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                radius: 15
                color: "transparent"
                border.width: 4
                border.color: Qt.rgba(52 / 255, 86 / 255, 232 / 255, 0.14)
                visible: field.activeFocus
            }
            Icon { anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; d: I.search; size: 20; color: field.activeFocus ? sm.t.accentText : sm.t.text2 }
            TextInput {
                id: field
                anchors.left: parent.left; anchors.leftMargin: 46
                anchors.right: parent.right; anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                color: sm.t.text
                font.pixelSize: 16
                selectionColor: sm.t.accentSoft
                selectedTextColor: sm.t.text
                clip: true
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !field.text
                    text: "Aplikacje, pliki, ustawienia — albo zapytaj"
                    color: sm.t.text2
                    font.pixelSize: 16
                }
                Keys.onEscapePressed: sm.closeRequested()
                Keys.onReturnPressed: sm.activate(sm.selected)
                Keys.onDownPressed: sm.selected = Math.min(sm.selected + 1, sm.results.length - 1)
                Keys.onUpPressed: sm.selected = Math.max(sm.selected - 1, 0)
            }
        }

        // Widok domowy
        Column {
            width: parent.width
            spacing: 10
            visible: sm.results.length === 0

            Text { text: "Przypięte"; color: sm.t.text; font.pixelSize: 14; font.weight: Font.DemiBold; leftPadding: 10; topPadding: 4 }
            Grid {
                columns: 6
                width: parent.width
                Repeater {
                    model: sm.apps
                    delegate: HoverButton {
                        id: tile
                        required property var modelData
                        t: sm.t
                        width: (sm.width - 44) / 6; height: 92
                        radius: 12
                        required property int index
                        readonly property real k: sm.stagger(index)
                        opacity: k
                        transform: Translate { y: (1 - tile.k) * 18 }
                        onClicked: { sm.launch(modelData.name); sm.closeRequested(); }
                        Column {
                            anchors.centerIn: parent
                            spacing: 8
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 48; height: 48; radius: 13
                                color: tile.modelData.color
                                Icon { anchors.centerIn: parent; d: I[tile.modelData.icon]; size: 22; color: "white" }
                            }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.name; color: sm.t.text; font.pixelSize: 12 }
                        }
                    }
                }
            }

            Text { text: "Ostatnie"; color: sm.t.text; font.pixelSize: 14; font.weight: Font.DemiBold; leftPadding: 10; topPadding: 8 }
            Grid {
                columns: 2
                width: parent.width
                Repeater {
                    model: sm.files.slice(0, 4)
                    delegate: HoverButton {
                        id: rec
                        required property var modelData
                        t: sm.t
                        width: (sm.width - 44) / 2; height: 58
                        required property int index
                        readonly property real k: sm.stagger(12 + index)
                        opacity: k
                        transform: Translate { x: (1 - rec.k) * -16 }
                        onClicked: { sm.openFile(rec.modelData.id); sm.closeRequested(); }
                        FileBadge { id: fb; t: sm.t; x: 10; anchors.verticalCenter: parent.verticalCenter; file: rec.modelData; small: true }
                        Column {
                            anchors.left: fb.right; anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text { text: rec.modelData.name; color: sm.t.text; font.pixelSize: 13; font.weight: Font.Medium }
                            Text { text: rec.modelData.when; color: sm.t.text2; font.pixelSize: 12 }
                        }
                    }
                }
            }
        }

        // Wyniki wyszukiwania
        Column {
            width: parent.width
            spacing: 2
            visible: sm.results.length > 0
            Text { text: "WYNIKI"; color: sm.t.text2; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4; leftPadding: 10; bottomPadding: 4 }
            Repeater {
                model: sm.results
                delegate: HoverButton {
                    id: row
                    required property var modelData
                    required property int index
                    t: sm.t
                    width: parent.width; height: 52
                    active: index === sm.selected
                    onClicked: sm.activate(index)
                    Rectangle {
                        id: ricon
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32; height: 32; radius: 9
                        color: row.modelData.kind === "ask" ? sm.t.accentSoft : (row.modelData.kind === "file" ? row.modelData.color : row.modelData.color)
                        Icon {
                            anchors.centerIn: parent
                            visible: row.modelData.kind !== "file"
                            d: I[row.modelData.icon] || ""
                            size: 17
                            color: row.modelData.kind === "ask" ? sm.t.accentText : "white"
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: row.modelData.kind === "file"
                            text: row.modelData.icon
                            color: "white"
                            font.pixelSize: 8; font.weight: Font.Bold
                        }
                    }
                    Text { anchors.left: ricon.right; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: row.modelData.name; color: sm.t.text; font.pixelSize: 14; font.weight: row.index === sm.selected ? Font.DemiBold : Font.Normal }
                    Text { anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; text: row.index === sm.selected ? "Enter" : row.modelData.sub; color: sm.t.text2; font.pixelSize: 12 }
                }
            }
        }
    }

    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 60
        color: "transparent"
        Rectangle { width: parent.width; height: 1; color: sm.t.line }
        Rectangle {
            id: avatar
            x: 16; anchors.verticalCenter: parent.verticalCenter
            width: 34; height: 34; radius: 17
            color: sm.t.accentSoft
            Text { anchors.centerIn: parent; text: "U"; color: sm.t.accentText; font.weight: Font.DemiBold; font.pixelSize: 14 }
        }
        Text { anchors.left: avatar.right; anchors.leftMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: "Użytkownik"; color: sm.t.text; font.pixelSize: 13; font.weight: Font.Medium }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            HoverButton { t: sm.t; width: 40; height: 40; onClicked: sm.lockRequested(); Icon { anchors.centerIn: parent; d: I.lock; color: sm.t.text } }
            HoverButton { t: sm.t; width: 40; height: 40; Icon { anchors.centerIn: parent; d: I.power; color: sm.t.text } }
        }
    }
}
