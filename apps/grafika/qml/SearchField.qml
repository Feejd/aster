import QtQuick
import Aster.Ui

// Pole wyszukiwania: Enter (albo chwila bez pisania) — `search(text)`, Esc czyści
Rectangle {
    id: sf
    property alias text: input.text
    property string placeholder: "Szukaj"
    property int delay: 600                 // 0 — tylko Enter
    signal search(string text)
    function focusInput() { input.forceActiveFocus(); }
    function set(t) { input.text = t; later.stop(); sf.search(t); }

    width: parent ? parent.width : 200
    height: 38; radius: 10
    color: Theme.fill
    border.width: input.activeFocus ? 1.5 : 0
    border.color: Theme.accent
    Icon { x: 11; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 15; color: Theme.text2 }
    TextInput {
        id: input
        x: 34; width: parent.width - 34 - (clear.visible ? 30 : 10)
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.text
        clip: true
        selectByMouse: true
        selectionColor: Theme.accent
        font.family: Theme.font; font.pixelSize: 13
        onTextEdited: if (sf.delay > 0) later.restart()
        onAccepted: { later.stop(); sf.search(text.trim()); }
        Keys.onEscapePressed: (e) => { if (text !== "") { sf.set(""); } else { e.accepted = false; } }
        Text { visible: !input.text; text: sf.placeholder; color: Theme.text2; font: input.font }
    }
    Timer { id: later; interval: sf.delay; onTriggered: sf.search(input.text.trim()) }
    HoverButton {
        id: clear
        visible: input.text !== ""
        anchors.right: parent.right; anchors.rightMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        width: 26; height: 26; radius: 13
        onClicked: sf.set("")
        Icon { anchors.centerIn: parent; d: Icons.close; size: 12; stroke: 2.2; color: Theme.text2 }
    }
}
