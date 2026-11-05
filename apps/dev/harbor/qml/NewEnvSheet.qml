pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Aster.Ui
import Aster.Harbor

// „Nowe środowisko”: rodzaj (Node, Python, Go…), nazwa i folder projektu → toolbox z gotowymi narzędziami.
// Ten sam arkusz pokazuje postęp każdego dłuższego zadania (tworzenie, compose up) z wyjściem poleceń.
Sheet {
    id: sheet
    cardWidth: progress ? 600 : 640
    dismissable: Harbor.taskState !== "running"
    onDismissed: done()
    signal done()

    readonly property bool progress: Harbor.taskState !== ""
    property string kind: "node"
    property bool folderEdited: false
    readonly property var kindInfo: Harbor.kinds.find(k => k.id === kind) || Harbor.kinds[0]
    readonly property string name: nameInput.text.trim()
    readonly property string problem: !name ? "Podaj nazwę"
        : !Harbor.validName(name) ? "Nazwa: litery, cyfry, - _ . (bez spacji i polskich znaków)"
        : Harbor.nameTaken(name) ? "Kontener o tej nazwie już istnieje"
        : ""

    function freeName(base) {
        let n = base, i = 2;
        while (Harbor.nameTaken(n)) n = base + "-" + i++;
        return n;
    }
    function pick(id) {
        kind = id;
        nameInput.text = freeName(id === "fedora" ? "dev" : id);
        if (!folderEdited) folderInput.text = Harbor.homePath(Harbor.defaultFolder(nameInput.text));
    }
    function reset() { folderEdited = false; pick("node"); }
    function create() {
        if (problem) return;
        Harbor.createEnvironment(kind, name, folderInput.text.trim());
    }

    FolderDialog {
        id: folderDialog
        title: "Folder projektu"
        onAccepted: {
            sheet.folderEdited = true;
            folderInput.text = Harbor.homePath(decodeURIComponent(selectedFolder.toString().replace(/^file:\/\//, "")));
        }
    }

    // ——— Formularz ———
    Column {
        visible: !sheet.progress
        width: parent.width
        spacing: 0
        Text {
            text: "Nowe środowisko"
            color: Theme.text; font.family: Theme.font; font.pixelSize: 19; font.weight: Font.DemiBold
        }
        Item { width: 1; height: 6 }
        Text {
            width: parent.width; wrapMode: Text.Wrap
            text: "Osobna Fedora w toolboxie z narzędziami do wybranego języka. System zostaje czysty, a folder domowy jest w środku dostępny — pracujesz na zwykłych plikach."
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.25
        }
        Item { width: 1; height: 18 }

        Grid {
            id: grid
            width: parent.width
            columns: 3
            columnSpacing: 8; rowSpacing: 8
            Repeater {
                model: Harbor.kinds
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    readonly property bool chosen: sheet.kind === modelData.id
                    width: (grid.width - 16) / 3; height: 62
                    radius: 10
                    color: chosen ? Theme.accentSoft : tileArea.containsMouse ? Theme.hover : Theme.fill
                    border.width: chosen ? 1.5 : 0
                    border.color: Theme.accent
                    Rectangle {
                        x: 11; anchors.verticalCenter: parent.verticalCenter
                        width: 36; height: 36; radius: 11
                        gradient: Gradient {
                            GradientStop { position: 0; color: tile.modelData.colors[0] }
                            GradientStop { position: 1; color: tile.modelData.colors[1] }
                        }
                        Icon { anchors.centerIn: parent; d: Icons[tile.modelData.icon] || ""; size: 18; stroke: 2; color: "white" }
                    }
                    Column {
                        x: 56; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 64
                        spacing: 2
                        Text { text: tile.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: tile.modelData.desc
                            color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                        }
                    }
                    MouseArea { id: tileArea; anchors.fill: parent; hoverEnabled: true; onClicked: sheet.pick(tile.modelData.id) }
                }
            }
        }
        Item { width: 1; height: 18 }

        // Nazwa i folder
        Row {
            width: parent.width
            spacing: 12
            Column {
                width: 190
                spacing: 6
                Text { text: "Nazwa"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                Field {
                    width: parent.width
                    TextInput {
                        id: nameInput
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                        selectionColor: Theme.accentSoft
                        clip: true
                        onTextEdited: if (!sheet.folderEdited) folderInput.text = Harbor.homePath(Harbor.defaultFolder(text.trim()))
                        Keys.onReturnPressed: sheet.create()
                    }
                }
            }
            Column {
                width: parent.width - 202
                spacing: 6
                Text { text: "Folder projektu"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                Row {
                    width: parent.width
                    spacing: 6
                    Field {
                        width: parent.width - chooseBtn.width - 6
                        TextInput {
                            id: folderInput
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                            selectionColor: Theme.accentSoft
                            clip: true
                            onTextEdited: sheet.folderEdited = true
                            Keys.onReturnPressed: sheet.create()
                        }
                    }
                    ActionButton { id: chooseBtn; text: "Wybierz…"; onClicked: folderDialog.open() }
                }
            }
        }
        Item { width: 1; height: 12 }
        Text {
            width: parent.width; wrapMode: Text.Wrap
            text: sheet.problem && sheet.name ? sheet.problem
                : sheet.kindInfo.packages ? "Zainstaluje: " + sheet.kindInfo.packages.split(" ").join(", ") + " (i git, który jest zawsze)."
                : "Tylko Fedora z gitem — resztę doinstalujesz poleceniem sudo dnf install."
            color: sheet.problem && sheet.name ? Theme.danger : Theme.text2
            font.family: Theme.font; font.pixelSize: 12
        }
        Item { width: 1; height: 20 }
        Row {
            anchors.right: parent.right
            spacing: 8
            ActionButton { text: "Anuluj"; onClicked: sheet.done() }
            ActionButton {
                text: "Utwórz środowisko"; icon: "plus"; primary: true
                enabled: !sheet.problem
                onClicked: sheet.create()
            }
        }
    }

    // ——— Postęp ———
    Column {
        visible: sheet.progress
        width: parent.width
        spacing: 0
        Row {
            spacing: 10
            Item {
                width: 22; height: 22
                anchors.verticalCenter: parent.verticalCenter
                Icon {
                    anchors.centerIn: parent
                    visible: Harbor.taskState === "running"
                    d: Icons.reload; size: 20; stroke: 2; color: Theme.accent
                    RotationAnimation on rotation { running: Harbor.taskState === "running" && sheet.visible; from: 0; to: 360; duration: 1100; loops: Animation.Infinite }
                }
                Rectangle {
                    anchors.fill: parent; radius: 11
                    visible: Harbor.taskState !== "running"
                    color: Harbor.taskState === "done" ? "#16A34A" : "#E5484D"
                    Icon { anchors.centerIn: parent; d: Harbor.taskState === "done" ? Icons.check : Icons.close; size: 13; stroke: 2.6; color: "white" }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Harbor.taskState === "done" ? (Harbor.taskResult.kind === "env" ? "Środowisko „" + Harbor.taskResult.name + "” gotowe" : "Gotowe")
                    : Harbor.taskState === "failed" ? "Coś poszło nie tak" : Harbor.taskTitle
                color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
            }
        }
        Item { width: 1; height: 16 }
        Repeater {
            model: Harbor.taskSteps
            delegate: Item {
                id: stepRow
                required property string modelData
                required property int index
                readonly property bool isDone: index < Harbor.taskStep || Harbor.taskState === "done"
                readonly property bool isCurrent: index === Harbor.taskStep && Harbor.taskState !== "done"
                readonly property bool isFailed: isCurrent && Harbor.taskState === "failed"
                width: parent.width; height: 28
                Rectangle {
                    x: 2; anchors.verticalCenter: parent.verticalCenter
                    width: 18; height: 18; radius: 9
                    color: stepRow.isDone ? "#16A34A" : stepRow.isFailed ? "#E5484D" : "transparent"
                    border.width: stepRow.isDone || stepRow.isFailed ? 0 : 1.5
                    border.color: stepRow.isCurrent ? Theme.accent : Theme.line
                    Icon { visible: stepRow.isDone || stepRow.isFailed; anchors.centerIn: parent; d: stepRow.isDone ? Icons.check : Icons.close; size: 11; stroke: 2.6; color: "white" }
                    Rectangle { visible: stepRow.isCurrent && !stepRow.isFailed; anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: Theme.accent }
                }
                Text {
                    x: 32; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 32; elide: Text.ElideRight
                    text: stepRow.modelData
                    color: stepRow.isCurrent || stepRow.isDone ? Theme.text : Theme.text2
                    font.family: Theme.font; font.pixelSize: 13; font.weight: stepRow.isCurrent ? Font.Medium : Font.Normal
                }
            }
        }
        Item { width: 1; height: 12 }
        Rectangle {
            width: parent.width; height: 210
            radius: 12
            color: Theme.dark ? "#0B0C10" : "#F4F5F8"
            border.width: 1; border.color: Theme.line
            ListView {
                id: out
                anchors.fill: parent; anchors.margins: 10
                clip: true
                model: Harbor.taskLines
                boundsBehavior: Flickable.StopAtBounds
                onCountChanged: Qt.callLater(positionViewAtEnd)
                delegate: Text {
                    required property string line
                    width: out.width
                    elide: Text.ElideRight
                    text: line
                    textFormat: Text.PlainText
                    color: /error|błąd|failed/i.test(line) ? Theme.danger : Theme.text2
                    font.family: "JetBrains Mono"; font.pixelSize: 11
                }
                Text {
                    visible: out.count === 0
                    anchors.centerIn: parent
                    text: "Uruchamiam…"
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
            }
        }
        Item { width: 1; height: 18 }
        Row {
            anchors.right: parent.right
            spacing: 8
            ActionButton {
                visible: Harbor.taskState === "running"
                text: "Przerwij"
                onClicked: sheet.done()
            }
            ActionButton {
                visible: Harbor.taskState === "done" && Harbor.taskResult.kind === "env" && !!Harbor.taskResult.folder
                text: "Otwórz w Aster Code"; icon: "code"
                onClicked: { Harbor.openInCode(Harbor.taskResult.folder); sheet.done(); }
            }
            ActionButton {
                visible: Harbor.taskState === "done" && Harbor.taskResult.kind === "env"
                text: "Otwórz terminal"; icon: "prompt"; primary: true
                onClicked: { Harbor.openTerminal(Harbor.taskResult.name); sheet.done(); }
            }
            ActionButton {
                visible: Harbor.taskState === "failed" || (Harbor.taskState === "done" && Harbor.taskResult.kind !== "env")
                text: Harbor.taskState === "failed" ? "Zamknij" : "Gotowe"
                primary: Harbor.taskState === "done"
                onClicked: sheet.done()
            }
        }
    }

    component Field: Rectangle {
        height: 36; radius: 10
        color: Theme.fill
        border.width: children[0] && children[0].activeFocus ? 1.5 : 0
        border.color: Theme.accent
    }
}
