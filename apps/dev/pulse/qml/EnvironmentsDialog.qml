pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Aster.Ui
import Aster.Pulse

// Środowiska (lokalne, produkcyjne…) i ich zmienne. Tajne (kłódka) trafiają do portfela systemu,
// w pliku pulse.json zostaje tylko ich nazwa — można go bezpiecznie dodać do repozytorium.
Item {
    id: dlg
    property bool shown: false
    property var envs: []
    property int current: 0
    property real radius: 24
    signal saved()

    property var original: []            // nazwy przy otwarciu — po zmianie nazwy wybranego środowiska zostaje wybrane
    function open(select) {
        envs = Pulse.environmentsWithSecrets();
        original = envs.map(e => e.name);
        current = Math.max(0, envs.findIndex(e => e.name === (select || Pulse.activeEnv)));
        editor.load(envs.length ? envs[current].vars : []);
        nameField.setText(envs.length ? envs[current].name : "");
        shown = true;
    }
    function keep() {
        if (current < 0 || current >= envs.length) return;
        const e = envs.slice();
        e[current] = Object.assign({}, e[current], { vars: editor.toArray(), name: nameField.text.trim() || e[current].name });
        envs = e;
    }
    function pick(i) {
        keep();
        current = i;
        editor.load(envs[i].vars);
        nameField.setText(envs[i].name);
    }
    function add() {
        keep();
        let name = "nowe", n = 2;
        while (envs.some(e => e.name === name)) name = "nowe " + n++;
        // Nowe środowisko z tymi samymi nazwami zmiennych (bez wartości tajnych)
        const base = envs.length ? envs[current].vars.map(v => ({ key: v.key, value: v.secret ? "" : v.value, secret: v.secret })) : [{ key: "baseUrl", value: "http://localhost:8000", secret: false }];
        envs = envs.concat([{ name: name, vars: base }]);
        original = original.concat([""]);
        current = envs.length - 1;
        editor.load(base);
        nameField.setText(name);
        nameField.focusEnd();
    }
    function remove() {
        if (envs.length <= 1) return;
        const e = envs.slice();
        e.splice(current, 1);
        envs = e;
        const o = original.slice(); o.splice(current, 1); original = o;
        current = Math.min(current, envs.length - 1);
        editor.load(envs[current].vars);
        nameField.setText(envs[current].name);
    }
    function save() {
        keep();
        const was = original.indexOf(Pulse.activeEnv);
        if (Pulse.saveEnvironments(envs)) {
            if (was >= 0 && envs[was]) Pulse.activeEnv = envs[was].name;
            shown = false;
            saved();
        }
    }

    anchors.fill: parent
    visible: shown
    z: 150

    Rectangle { anchors.fill: parent; radius: dlg.radius; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.25) }
    MouseArea { anchors.fill: parent; onClicked: dlg.shown = false }
    Keys.onEscapePressed: dlg.shown = false
    RectangularShadow { anchors.fill: sheet; radius: sheet.radius; blur: 40; offset.y: 14; color: Theme.shadow }
    Rectangle {
        id: sheet
        anchors.centerIn: parent
        width: Math.min(parent.width - 60, 820); height: Math.min(parent.height - 60, 520)
        radius: 22
        color: Theme.surface
        border.width: 1; border.color: Theme.edge
        MouseArea { anchors.fill: parent }

        Text {
            x: 24; y: 20
            text: "Środowiska"
            color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
        }
        Text {
            x: 24; y: 46
            width: parent.width - 48
            elide: Text.ElideRight
            text: "Zmienne wpisujesz w zapytaniach jako {{nazwa}}. Plik: " + Pulse.workspaceDir + "/pulse.json"
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
        }

        // Lista środowisk
        Column {
            id: envList
            x: 16; y: 80
            width: 190
            spacing: 2
            Repeater {
                model: dlg.envs
                delegate: Rectangle {
                    id: er
                    required property var modelData
                    required property int index
                    readonly property bool active: index === dlg.current
                    width: envList.width; height: 34; radius: 9
                    color: active ? Theme.accent : erArea.containsMouse ? Theme.hover : "transparent"
                    Rectangle {
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        width: 8; height: 8; radius: 4
                        color: /prod/i.test(er.modelData.name) ? "#E5484D" : /stag|test/i.test(er.modelData.name) ? "#F5A623" : "#21B35A"
                        border.width: er.active ? 1.5 : 0; border.color: "white"
                    }
                    Text {
                        x: 28; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 36
                        text: er.modelData.name + (er.modelData.name === Pulse.activeEnv ? "  ·  wybrane" : "")
                        elide: Text.ElideRight
                        color: er.active ? "white" : Theme.text
                        font.family: Theme.font; font.pixelSize: 13
                    }
                    MouseArea { id: erArea; anchors.fill: parent; hoverEnabled: true; onClicked: dlg.pick(er.index) }
                }
            }
            Item { width: 1; height: 6 }
            HoverButton {
                width: envList.width; height: 32; radius: 9
                onClicked: dlg.add()
                Row {
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.plus; size: 14; stroke: 2; color: Theme.text2 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Dodaj środowisko"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                }
            }
        }
        Rectangle { x: envList.x + envList.width + 14; y: 80; width: 1; height: parent.height - 80 - 70; color: Theme.line }

        // Zmienne
        Item {
            id: right
            x: envList.x + envList.width + 30; y: 76
            width: parent.width - x - 20; height: parent.height - y - 70
            Text { y: 8; text: "Nazwa"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
            Field {
                id: nameField
                x: 56; width: 220; height: 32
                vars: false
            }
            Pill {
                anchors.right: parent.right
                small: true
                text: "Usuń środowisko"
                icon: "trash"
                enabled: dlg.envs.length > 1
                onClicked: dlg.remove()
            }
            KeyValueEditor {
                id: editor
                y: 46
                width: parent.width; height: parent.height - y
                secrets: true
                toggles: false
                keyPlaceholder: "Zmienna, np. baseUrl"
                valuePlaceholder: "Wartość"
            }
        }

        // Stopka
        Row {
            x: 24; anchors.bottom: parent.bottom; anchors.bottomMargin: 26
            spacing: 8
            Icon { anchors.verticalCenter: parent.verticalCenter; d: Pulse.walletAvailable ? Icons.lock : Icons.warning; size: 15; color: Pulse.walletAvailable ? Theme.text2 : "#D97706" }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: sheet.width - 300
                wrapMode: Text.Wrap
                text: Pulse.walletAvailable ? "Tajne wartości (kłódka) są w portfelu systemu, nie w pliku projektu."
                                            : "Brak portfela systemu — tajne wartości będą pamiętane tylko do zamknięcia programu."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 20
            anchors.bottom: parent.bottom; anchors.bottomMargin: 18
            spacing: 8
            Pill { text: "Anuluj"; onClicked: dlg.shown = false }
            Pill { text: "Zapisz"; primary: true; onClicked: dlg.save() }
        }
    }
}
