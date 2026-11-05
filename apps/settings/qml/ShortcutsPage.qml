pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Settings

// Skróty klawiszowe całego systemu: wyszukiwanie, zmiana (naciśnij nowy skrót), usunięcie, przywrócenie domyślnego
Page {
    id: sp
    property string query: ""
    property var editing: null          // { group, action, name, keys }
    property int newKey: 0
    property int newMods: 0

    Rectangle {
        width: parent.width; height: 38; radius: 10
        color: Theme.fill
        border.width: q.activeFocus ? 1.5 : 0; border.color: Theme.accent
        Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 15; color: Theme.text2 }
        TextInput {
            id: q
            x: 38; width: parent.width - 52
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text; font.family: Theme.font; font.pixelSize: 13
            clip: true
            onTextChanged: sp.query = text.toLowerCase()
            Text { visible: !q.text; text: "Szukaj skrótu albo czynności"; color: Theme.text2; font: q.font }
        }
    }

    Section {
        visible: !Shortcuts.available
        SettingRow { title: "Usługa skrótów nie odpowiada"; subtitle: "Skróty działają, ale nie da się ich teraz zmienić" }
    }

    Repeater {
        model: Shortcuts.groups
        delegate: Section {
            id: grp
            required property var modelData
            readonly property var actions: modelData.actions.filter(a => !sp.query || a.name.toLowerCase().indexOf(sp.query) >= 0 || a.keys.toLowerCase().indexOf(sp.query) >= 0)
            visible: actions.length > 0
            title: modelData.name
            Repeater {
                model: grp.actions
                delegate: SettingRow {
                    id: act
                    required property var modelData
                    title: modelData.name
                    clickable: true
                    onClicked: { sp.newKey = 0; sp.newMods = 0; sp.editing = { group: grp.modelData.id, action: modelData.id, name: modelData.name, keys: modelData.keys, defaults: modelData.defaultKeys }; recorder.open(); }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: keyText.implicitWidth + 18; height: 26; radius: 7
                        color: act.modelData.keys ? Theme.fill : "transparent"
                        border.width: act.modelData.keys ? 1 : 0; border.color: Theme.line
                        Text {
                            id: keyText
                            anchors.centerIn: parent
                            text: act.modelData.keys || "Brak"
                            color: act.modelData.keys ? Theme.text : Theme.text2
                            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                        }
                    }
                }
            }
        }
    }

    // ——— Nagrywanie skrótu ———
    Sheet {
        id: recorder
        title: sp.editing ? sp.editing.name : ""
        subtitle: "Naciśnij nowe połączenie klawiszy (np. Super + E)."
        acceptText: "Zapisz"
        acceptEnabled: sp.newKey !== 0
        onShownChanged: if (shown) catcher.forceActiveFocus()
        onAccepted: Shortcuts.setKeys(sp.editing.group, sp.editing.action, [sp.newKey | sp.newMods])
        Rectangle {
            width: parent.width; height: 64; radius: 10
            color: Theme.fill
            border.width: 1.5; border.color: catcher.activeFocus ? Theme.accent : Theme.line
            Text {
                anchors.centerIn: parent
                text: sp.newKey ? Shortcuts.keyText(sp.newKey, sp.newMods) : (sp.editing && sp.editing.keys ? "Teraz: " + sp.editing.keys : "Czekam na klawisze…")
                color: sp.newKey ? Theme.text : Theme.text2
                font.family: Theme.font; font.pixelSize: sp.newKey ? 20 : 14; font.weight: sp.newKey ? Font.DemiBold : Font.Normal
            }
            Item {
                id: catcher
                anchors.fill: parent
                focus: true
                Keys.onPressed: e => {
                    e.accepted = true;
                    if (e.key === Qt.Key_Escape && !e.modifiers) { recorder.close(); return; }
                    // Same modyfikatory jeszcze nie są skrótem
                    if ([Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_AltGr].indexOf(e.key) >= 0) return;
                    sp.newKey = e.key;
                    sp.newMods = e.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
                }
                MouseArea { anchors.fill: parent; onClicked: catcher.forceActiveFocus() }
            }
        }
        Text {
            readonly property string who: sp.newKey ? Shortcuts.conflict(sp.newKey | sp.newMods) : ""
            visible: who !== "" && sp.editing && who !== sp.editing.name
            width: parent.width; wrapMode: Text.Wrap
            text: "Ten skrót ma już: „" + who + "”. Po zapisaniu zadziała tutaj."
            color: Theme.danger; font.family: Theme.font; font.pixelSize: 12
        }
        Row {
            spacing: 8
            TextButton { text: "Bez skrótu"; onClicked: { Shortcuts.setKeys(sp.editing.group, sp.editing.action, []); recorder.close(); } }
            TextButton {
                visible: !!sp.editing && !!sp.editing.defaults && sp.editing.defaults !== sp.editing.keys
                text: "Przywróć: " + (sp.editing ? sp.editing.defaults : "")
                onClicked: { Shortcuts.resetKeys(sp.editing.group, sp.editing.action); recorder.close(); }
            }
        }
    }
}
