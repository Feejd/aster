pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// Sekrety projektu (zmienne .env, klucze API) w portfelu systemu: lista nazw z zakrytymi wartościami
// (pokaż, kopiuj, usuń), dodawanie, przeniesienie pliku .env do portfela. Wartości trafiają do zadań
// i debugera przy uruchomieniu i nigdy do agenta.
Rectangle {
    id: sv
    property bool shown: false
    property var revealed: ({})          // nazwa → wartość pokazana na żądanie
    property var files: []
    signal closed()

    visible: shown
    color: Theme.dark ? "#090A0D" : "#FFFFFF"
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    function open() {
        shown = true;
        revealed = {};
        Secrets.reload();
        files = Secrets.envFiles();
        Qt.callLater(() => newName.forceActiveFocus());
    }
    function close() { shown = false; revealed = {}; closed(); }
    function add() {
        if (!newName.text.trim()) return;
        if (Secrets.set(newName.text.trim(), newValue.text)) { newName.text = ""; newValue.text = ""; newName.forceActiveFocus(); }
    }

    Item {
        id: header
        width: parent.width; height: 58
        Row {
            x: col.x; anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.key; size: 18; color: Theme.accentText }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Sekrety projektu"; color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold }
        }
        HoverButton {
            anchors.right: parent.right; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; radius: 8
            onClicked: sv.close()
            Icon { anchors.centerIn: parent; d: Icons.close; size: 13; stroke: 2; color: Theme.text2 }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
    }

    Flickable {
        y: header.height
        width: parent.width; height: parent.height - y
        contentHeight: col.height + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            x: Math.max(24, (parent.width - width) / 2); y: 18
            width: Math.min(720, sv.width - 48)
            spacing: 14

            Text {
                width: parent.width; wrapMode: Text.Wrap
                text: "Klucze API i hasła trzymane w portfelu systemu, nie w plikach projektu. Trafiają do zadań, serwerów i debugera jako zmienne środowiska przy uruchomieniu — i nigdy do agenta ani modelu."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.2
            }
            Rectangle {
                visible: !!Secrets.error
                width: parent.width; height: errText.implicitHeight + 20; radius: 10
                color: Qt.rgba(0.9, 0.28, 0.3, Theme.dark ? 0.16 : 0.08)
                Text { id: errText; x: 12; y: 10; width: parent.width - 24; wrapMode: Text.Wrap; text: Secrets.error; color: Theme.danger; font.family: Theme.font; font.pixelSize: 12 }
            }

            // Plik .env z wartościami — do portfela
            Repeater {
                model: sv.files
                delegate: Rectangle {
                    id: ef
                    required property var modelData
                    width: col.width; height: 64; radius: 12
                    color: Qt.rgba(0.85, 0.6, 0.1, Theme.dark ? 0.16 : 0.10)
                    Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; d: Icons.alertCircle; size: 18; color: Theme.dark ? "#E3B341" : "#9A6700" }
                    Column {
                        x: 44; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 44 - moveBtn.width - 24
                        spacing: 2
                        Text { text: ef.modelData.name + " — " + ef.modelData.count + " zmiennych w zwykłym pliku"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                        Text { width: parent.width; elide: Text.ElideRight; text: "Przeniesienie do portfela zostawi w pliku same nazwy (jak w .env.example)"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                    }
                    HoverButton {
                        id: moveBtn
                        anchors.right: parent.right; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: mvText.implicitWidth + 24; height: 32; radius: 9
                        baseColor: Theme.accent
                        onClicked: {
                            const n = Secrets.importEnv(ef.modelData.path, true);
                            if (n > 0) { Project.message("Przeniesiono " + n + " zmiennych do portfela"); sv.files = Secrets.envFiles(); }
                        }
                        Text { id: mvText; anchors.centerIn: parent; text: "Przenieś do portfela"; color: "white"; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                    }
                }
            }

            // Lista
            Column {
                width: parent.width
                spacing: 4
                Repeater {
                    model: Secrets.names
                    delegate: Rectangle {
                        id: sr
                        required property string modelData
                        readonly property bool open: sv.revealed[modelData] !== undefined
                        width: col.width; height: 46; radius: 10
                        color: srHover.hovered ? Theme.hover : Theme.fill
                        HoverHandler { id: srHover }
                        Text {
                            id: sname
                            x: 14; anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, parent.width * 0.4)
                            elide: Text.ElideRight
                            text: sr.modelData
                            color: Theme.text; font.family: "JetBrains Mono"; font.pixelSize: 13; font.weight: Font.Medium
                        }
                        Text {
                            anchors.left: sname.right; anchors.leftMargin: 16
                            anchors.right: tools.left; anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideMiddle
                            text: sr.open ? sv.revealed[sr.modelData] : "••••••••••••"
                            color: sr.open ? Theme.text : Theme.text2; font.family: "JetBrains Mono"; font.pixelSize: 12
                        }
                        Row {
                            id: tools
                            anchors.right: parent.right; anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            RowBtn {
                                icon: sr.open ? "eyeOff" : "eye"
                                onClicked: {
                                    const r = Object.assign({}, sv.revealed);
                                    if (sr.open) delete r[sr.modelData]; else r[sr.modelData] = Secrets.reveal(sr.modelData);
                                    sv.revealed = r;
                                }
                            }
                            RowBtn { icon: "copy"; onClicked: { Project.copyText(Secrets.reveal(sr.modelData)); Project.message("Skopiowano " + sr.modelData); } }
                            RowBtn { icon: "trash"; onClicked: Secrets.remove(sr.modelData) }
                        }
                    }
                }
                Text {
                    visible: Secrets.names.length === 0 && !Secrets.error
                    topPadding: 4; bottomPadding: 4
                    text: "Brak sekretów w tym projekcie"
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
            }

            // Nowy
            Row {
                width: parent.width
                spacing: 6
                Field { id: newName; width: parent.width * 0.36; placeholder: "NAZWA, np. OPENAI_API_KEY"; mono: true; onAccepted: newValue.forceActiveFocus() }
                Field { id: newValue; width: parent.width - newName.width - addBtn.width - 12; placeholder: "wartość"; mono: true; secret: true; onAccepted: sv.add() }
                HoverButton {
                    id: addBtn
                    width: addText.implicitWidth + 24; height: 36; radius: 9
                    baseColor: Theme.accent
                    enabled: !!newName.text.trim()
                    opacity: enabled ? 1 : 0.5
                    onClicked: sv.add()
                    Text { id: addText; anchors.centerIn: parent; text: "Dodaj"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                }
            }
        }
    }

    component RowBtn: HoverButton {
        id: rb
        property string icon
        width: 28; height: 28; radius: 7
        Icon { anchors.centerIn: parent; d: Icons[rb.icon] || ""; size: 14; color: Theme.text2 }
    }
    component Field: Rectangle {
        id: fld
        property alias text: input.text
        property string placeholder
        property bool mono: false
        property bool secret: false
        signal accepted()
        function forceActiveFocus() { input.forceActiveFocus(); }
        height: 36; radius: 9
        color: Theme.fill
        border.width: input.activeFocus ? 1.5 : 0; border.color: Theme.accent
        TextInput {
            id: input
            x: 10; width: parent.width - 20
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
            font.family: fld.mono ? "JetBrains Mono" : Theme.font; font.pixelSize: 13
            echoMode: fld.secret ? TextInput.Password : TextInput.Normal
            clip: true
            onAccepted: fld.accepted()
            Text { anchors.verticalCenter: parent.verticalCenter; visible: !input.text; text: fld.placeholder; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
        }
    }
}
