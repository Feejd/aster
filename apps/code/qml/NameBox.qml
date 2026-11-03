import QtQuick
import Aster.Ui

// Pole nazwy u góry edytora (nowy plik, nowy folder, zmiana nazwy) — jak pole wprowadzania w VS Code.
// Enter zatwierdza, Esc albo kliknięcie obok zamyka.
Item {
    id: box
    property bool shown: false
    property string title
    property string hint
    property var onDone: null
    signal closed()

    anchors.fill: parent
    visible: shown
    z: 400

    function ask(t, value, h, done, selectBase) {
        title = t;
        hint = h || "";
        onDone = done;
        field.text = value || "";
        shown = true;
        field.forceActiveFocus();
        // Przy zmianie nazwy zaznaczona jest nazwa bez rozszerzenia
        const dot = selectBase ? field.text.lastIndexOf(".") : -1;
        if (dot > 0) field.select(0, dot); else field.selectAll();
    }
    function close() { shown = false; closed(); }

    MouseArea { anchors.fill: parent; onPressed: box.close() }

    Rectangle {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        y: 10
        width: Math.min(520, parent.width - 40); height: col.implicitHeight + 20
        radius: 14
        color: Theme.surface
        border.width: 1; border.color: Theme.edge
        MouseArea { anchors.fill: parent }
        Column {
            id: col
            x: 10; y: 10; width: parent.width - 20
            spacing: 6
            Text { leftPadding: 4; text: box.title; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
            Rectangle {
                width: parent.width; height: 34; radius: 9
                color: Theme.fill
                border.width: 1.5; border.color: Theme.accent
                TextInput {
                    id: field
                    x: 10; width: parent.width - 20
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                    font.family: Theme.font; font.pixelSize: 13
                    clip: true
                    Keys.onEscapePressed: box.close()
                    onAccepted: {
                        const t = text.trim();
                        const done = box.onDone;
                        box.close();
                        if (t && done) done(t);
                    }
                }
            }
            Text {
                visible: !!box.hint
                leftPadding: 4
                width: parent.width; elide: Text.ElideMiddle
                text: box.hint; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
            }
        }
    }
}
