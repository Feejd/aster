pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Code

// „Nowa aplikacja”: nazwa, frontend, backend i baza do wyboru — Aster Code tworzy działający szkielet
// z testami i .env.example, zakłada kontener projektu z potrzebnymi pakietami, instaluje zależności
// i robi pierwsze zatwierdzenie. Agent zaczyna od działającej aplikacji, nie od pustego folderu.
Rectangle {
    id: na
    property bool shown: false
    property string frontend: "vite-react"
    property string backend: "fastapi"
    property string db: "sqlite"
    property bool container: ProjectEnv.toolAvailable()
    property string error
    signal created(var result, bool container)
    signal closed()

    visible: shown
    color: Theme.dark ? "#090A0D" : "#FFFFFF"
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    function open() {
        shown = true;
        error = "";
        if (!parentField.text) parentField.text = Templates.defaultParent();
        Qt.callLater(() => nameField.forceActiveFocus());
    }
    function close() { shown = false; closed(); }
    readonly property string target: parentField.text.replace(/\/$/, "") + "/" + Templates.slug(nameField.text || "aplikacja")
    function create() {
        const r = Templates.create({ name: nameField.text, parent: parentField.text, frontend: frontend, backend: backend, db: db, git: true });
        if (!r.ok) { error = r.error; return; }
        shown = false;
        created(r, container && ProjectEnv.toolAvailable());
    }

    Item {
        id: header
        width: parent.width; height: 58
        Text { x: col.x; anchors.verticalCenter: parent.verticalCenter; text: "Nowa aplikacja"; color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold }
        HoverButton {
            anchors.right: parent.right; anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; radius: 8
            onClicked: na.close()
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
            x: Math.max(24, (parent.width - width) / 2); y: 20
            width: Math.min(760, na.width - 48)
            spacing: 18

            Row {
                width: parent.width
                spacing: 10
                Field { id: nameField; width: parent.width * 0.4; label: "Nazwa"; placeholder: "np. Lista zakupów"; onAccepted: na.create() }
                Field { id: parentField; width: parent.width * 0.6 - 10; label: "Gdzie (folder nadrzędny)"; placeholder: "~/Projekty"; mono: true }
            }
            Text { text: "Powstanie: " + na.target; color: Theme.text2; font.family: "JetBrains Mono"; font.pixelSize: 11; topPadding: -10 }

            Group {
                title: "Frontend"
                current: na.frontend
                options: [
                    { id: "vite-react", name: "Vite + React", desc: "Strona w przeglądarce, testy Vitest", icon: "globe" },
                    { id: "", name: "Bez frontendu", desc: "Samo API", icon: "close" }
                ]
                onPicked: (id) => na.frontend = id
            }
            Group {
                title: "Backend"
                current: na.backend
                options: [
                    { id: "fastapi", name: "FastAPI (Python)", desc: "API z dokumentacją /docs, testy pytest", icon: "code" },
                    { id: "node", name: "Node (Express)", desc: "API w JavaScripcie, testy node:test", icon: "code" },
                    { id: "", name: "Bez backendu", desc: "Sama strona", icon: "close" }
                ]
                onPicked: (id) => na.backend = id
            }
            Group {
                visible: !!na.backend
                title: "Baza danych"
                current: na.db
                options: [
                    { id: "sqlite", name: "SQLite", desc: "Jeden plik, bez serwera", icon: "doc" },
                    { id: "postgres", name: "PostgreSQL", desc: "Serwer w kontenerze projektu", icon: "box" },
                    { id: "", name: "Bez bazy", desc: "Dane w pamięci", icon: "close" }
                ]
                onPicked: (id) => na.db = id
            }

            // Kontener
            Rectangle {
                width: parent.width; height: 64; radius: 12
                color: Theme.fill
                opacity: ProjectEnv.toolAvailable() ? 1 : 0.5
                Icon { x: 16; anchors.verticalCenter: parent.verticalCenter; d: Icons.box; size: 20; color: Theme.accentText }
                Column {
                    x: 48; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 48 - 70
                    spacing: 2
                    Text { text: "Kontener projektu"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                    Text {
                        width: parent.width; wrapMode: Text.Wrap
                        text: ProjectEnv.toolAvailable() ? "Node, Python i baza trafią do kontenera aster-" + Templates.slug(nameField.text || "aplikacja") + " — w systemie nic nie przybędzie"
                                                         : "W systemie nie ma toolbox — zależności zainstalują się w systemie"
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                    }
                }
                Rectangle {
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 24; radius: 12
                    color: na.container ? Theme.accent : Theme.surface
                    border.width: na.container ? 0 : 1; border.color: Theme.edge
                    Rectangle { x: na.container ? 19 : 3; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; radius: 9; color: "white" }
                    MouseArea { anchors.fill: parent; enabled: ProjectEnv.toolAvailable(); onClicked: na.container = !na.container }
                }
            }

            Text { visible: !!na.error; width: parent.width; wrapMode: Text.Wrap; text: na.error; color: Theme.danger; font.family: Theme.font; font.pixelSize: 13 }

            Item {
                width: parent.width; height: 40
                HoverButton {
                    anchors.right: parent.right
                    width: createText.implicitWidth + 36; height: 40; radius: 11
                    baseColor: Theme.accent
                    enabled: !!nameField.text.trim() && (!!na.frontend || !!na.backend)
                    opacity: enabled ? 1 : 0.5
                    onClicked: na.create()
                    Text { id: createText; anchors.centerIn: parent; text: "Utwórz aplikację"; color: "white"; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 220; wrapMode: Text.Wrap
                    text: "Szkielet z testami, .env.example i README; potem instalacja zależności i pierwsze zatwierdzenie w gicie."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
            }
        }
    }

    component Group: Column {
        id: grp
        property string title
        property string current
        property var options: []
        signal picked(string id)
        width: col.width
        spacing: 8
        Text { text: grp.title.toUpperCase(); color: Theme.accentText; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.6 }
        Row {
            width: parent.width
            spacing: 8
            Repeater {
                model: grp.options
                delegate: HoverButton {
                    id: card
                    required property var modelData
                    readonly property bool on: grp.current === modelData.id
                    width: (grp.width - (grp.options.length - 1) * 8) / grp.options.length; height: 72; radius: 12
                    baseColor: on ? Theme.accentSoft : Theme.fill
                    onClicked: grp.picked(modelData.id)
                    Rectangle { anchors.fill: parent; radius: 12; color: "transparent"; border.width: card.on ? 1.5 : 0; border.color: Theme.accent }
                    Icon { x: 14; y: 14; d: Icons[card.modelData.icon] || ""; size: 16; color: card.on ? Theme.accentText : Theme.text2 }
                    Column {
                        x: 40; y: 12; width: parent.width - 52
                        spacing: 3
                        Text { width: parent.width; elide: Text.ElideRight; text: card.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                        Text { width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight; text: card.modelData.desc; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
                    }
                }
            }
        }
    }
    component Field: Column {
        id: fld
        property alias text: input.text
        property string label
        property string placeholder
        property bool mono: false
        signal accepted()
        function forceActiveFocus() { input.forceActiveFocus(); }
        spacing: 6
        Text { text: fld.label; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        Rectangle {
            width: fld.width; height: 38; radius: 10
            color: Theme.fill
            border.width: input.activeFocus ? 1.5 : 0; border.color: Theme.accent
            TextInput {
                id: input
                x: 12; width: parent.width - 24
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                font.family: fld.mono ? "JetBrains Mono" : Theme.font; font.pixelSize: 13
                clip: true
                onAccepted: fld.accepted()
                Text { anchors.verticalCenter: parent.verticalCenter; visible: !input.text; text: fld.placeholder; color: Theme.text2; font: input.font }
            }
        }
    }
}
