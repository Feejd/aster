pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Launch

// Logi produkcji na żywo: journalctl (usługa) albo podman/docker logs (kontener) przez SSH
Item {
    id: page
    required property var project
    required property var app
    readonly property bool mine: Launch.liveLogProject === project.id
    readonly property bool live: mine && Launch.liveLogRunning
    property string filter: ""
    property bool follow: true

    Component.onCompleted: start()
    readonly property string pid: project.id
    onPidChanged: { filter = ""; follow = true; start(); }
    function start() {
        if (project.current > 0 && project.target === "ssh") { if (!live) Launch.startLiveLog(project.id); }
        else if (Launch.liveLogRunning) Launch.stopLiveLog();
    }
    Component.onDestruction: if (Launch.liveLogProject === project.id) Launch.stopLiveLog()

    readonly property string source: project.target !== "ssh" ? "panel hostingu"
        : project.type === "node" || project.type === "python" ? "journalctl -u aster-" + slug + ".service"
        : project.type === "docker" ? (project.facts && project.facts.podman ? "podman" : "docker") + " logs aster-" + slug
        : project.type === "compose" ? "compose logs (aster-" + slug + ")"
        : "journalctl -u caddy.service"
    readonly property string slug: project.slug || project.name.toLowerCase().replace(/[ąćęłńóśźż]/g, c => "acelnoszz"["ąćęłńóśźż".indexOf(c)]).replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")

    Item {
        id: bar
        x: 28; y: 18
        width: parent.width - 56; height: 36
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: liveRow.implicitWidth + 20; height: 28; radius: 14
                color: page.live ? Qt.rgba(0.18, 0.75, 0.44, 0.16) : Theme.fill
                Row {
                    id: liveRow
                    anchors.centerIn: parent
                    spacing: 7
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8; height: 8; radius: 4
                        color: page.live ? "#2FBF71" : Theme.text2
                        SequentialAnimation on opacity {
                            running: page.live; loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 700 }
                            NumberAnimation { to: 1; duration: 700 }
                        }
                    }
                    Text { text: page.live ? "Na żywo" : "Zatrzymane"; color: page.live ? (Theme.dark ? "#7EE2A8" : "#167A45") : Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: page.source
                color: Theme.text2; font.family: "JetBrains Mono"; font.pixelSize: 12
            }
        }
        Row {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 200; height: 32; radius: 9
                color: Theme.fill
                border.width: filterInput.activeFocus ? 1.5 : 0; border.color: Theme.accent
                Icon { x: 9; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 14; color: Theme.text2 }
                TextInput {
                    id: filterInput
                    x: 30; width: parent.width - 38
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.text; selectionColor: Theme.accentSoft; font.family: Theme.font; font.pixelSize: 13
                    clip: true
                    onTextChanged: page.filter = text.toLowerCase()
                    Text { anchors.verticalCenter: parent.verticalCenter; visible: !filterInput.text; text: "Filtruj"; color: Theme.text2; font: filterInput.font }
                }
            }
            Pill {
                anchors.verticalCenter: parent.verticalCenter
                small: true
                visible: page.project.target === "ssh" && page.project.current > 0
                text: page.live ? "Zatrzymaj" : "Na żywo"
                iconPath: page.live ? Icons.pause : Icons.play
                onClicked: page.live ? Launch.stopLiveLog() : Launch.startLiveLog(page.project.id)
            }
            ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "copy"; tip: "Kopiuj logi"; onClicked: { Launch.copyText(Launch.liveLog.text()); page.app.toast("Skopiowano logi"); } }
            ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "trash"; tip: "Wyczyść widok"; onClicked: Launch.liveLog.clear() }
        }
    }

    Rectangle {
        id: box
        x: 28; y: bar.y + bar.height + 12
        width: parent.width - 56; height: parent.height - y - 24
        radius: 14
        color: Theme.dark ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(16 / 255, 24 / 255, 40 / 255, 0.035)
        border.width: 1; border.color: Theme.line
        clip: true

        Text {
            visible: !page.project.current || page.project.target !== "ssh"
            anchors.centerIn: parent
            width: parent.width - 80; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            text: page.project.target !== "ssh" ? "Logi strony w hostingu są w jego panelu — Aster Launch czyta logi z własnych serwerów."
                                                  : "Logi pojawią się po pierwszym wdrożeniu."
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
        }

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: 12
            visible: page.mine
            model: Launch.liveLog
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            onCountChanged: if (page.follow) positionViewAtEnd()
            onMovementEnded: page.follow = atYEnd
            delegate: Text {
                id: line
                required property var model
                readonly property string level: model.level || ""
                readonly property bool shown: page.filter === "" || model.text.toLowerCase().indexOf(page.filter) >= 0
                width: list.width
                height: shown ? implicitHeight : 0
                visible: shown
                wrapMode: Text.WrapAnywhere
                text: line.model.text
                color: line.level === "error" ? Theme.danger : line.level === "warn" ? (Theme.dark ? "#FFC56B" : "#A86200") : line.level === "step" ? Theme.accentText : Theme.text
                font.family: "JetBrains Mono"; font.pixelSize: 12
                lineHeight: 1.15
            }
        }
        Pill {
            visible: !page.follow && page.mine
            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 12
            small: true; primary: true
            text: "Na dół"
            iconPath: Icons.arrowDown
            onClicked: { page.follow = true; list.positionViewAtEnd(); }
        }
    }
}
