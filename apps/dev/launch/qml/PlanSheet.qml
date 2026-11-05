pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Aster.Ui
import Aster.Launch
import "LaunchIcons.js" as LI

// Plan zmian przed wdrożeniem / przywróceniem: każdy krok z miejscem wykonania i dokładnym poleceniem.
// Nic się nie dzieje bez „Wykonaj”. Potem ten sam arkusz pokazuje przebieg (stan kroków, wyjście) i wynik.
Item {
    id: sheet
    required property var app
    property real radius: 0
    readonly property var steps: Launch.plan
    readonly property bool open: steps.length > 0
    readonly property bool started: Launch.running || Launch.runResult !== ""
    readonly property int changes: steps.filter(s => s.change).length
    readonly property bool liveButBroken: steps.some(s => s.id === "switch" && s.state === "done") && steps.some(s => s.id === "health" && s.state === "failed")
    readonly property var project: sheet.app.projects.find(p => p.id === Launch.planProject) || null
    property bool showCommands: true

    visible: open
    onOpenChanged: if (open) { showCommands = true; flick.contentY = 0; }

    Rectangle { anchors.fill: parent; radius: sheet.radius; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.5 : 0.28) }
    MouseArea { anchors.fill: parent; onWheel: (w) => w.accepted = true }

    RectangularShadow { anchors.fill: card; radius: card.radius; blur: 44; offset.y: 16; color: Theme.shadow }
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 820)
        height: Math.min(parent.height - 56, head.height + flick.contentHeight + foot.height + 8)
        radius: 12
        color: Theme.surface
        border.width: 1; border.color: Theme.edge
        clip: true

        // ——— Nagłówek ———
        Column {
            id: head
            x: 26; y: 22
            width: parent.width - 52
            spacing: 6
            Row {
                spacing: 12
                Rectangle {
                    width: 36; height: 36; radius: 11
                    color: Launch.runResult === "ok" ? Qt.rgba(0.18, 0.75, 0.44, 0.18) : Launch.runResult === "failed" ? Qt.rgba(0.9, 0.28, 0.3, 0.16) : Theme.accentSoft
                    Icon {
                        anchors.centerIn: parent
                        d: Launch.runResult === "ok" ? Icons.check : Launch.runResult === "failed" ? Icons.warning : LI.rocket
                        size: 19; stroke: 2
                        color: Launch.runResult === "ok" ? "#2FBF71" : Launch.runResult === "failed" ? Theme.danger : Theme.accentText
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { text: Launch.planTitle; color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold }
                    Text {
                        text: Launch.running ? "Trwa — możesz przerwać w każdej chwili"
                            : Launch.runResult === "ok" ? "Gotowe"
                            : Launch.runResult === "failed" ? "Nie udało się"
                            : sheet.changes > 0 ? "Sprawdź, co się stanie: " + sheet.changes + (sheet.changes === 1 ? " zmiana" : sheet.changes < 5 ? " zmiany" : " zmian") + " — nic nie ruszy bez Twojej zgody"
                            : "Sprawdź kroki i potwierdź"
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                    }
                }
            }
            // Prośba z zewnątrz (asystent, terminal) — wyraźnie
            Rectangle {
                visible: Launch.planOrigin !== "" && Launch.planOrigin !== "Terminal" && !sheet.started
                width: parent.width; height: originText.implicitHeight + 18; radius: 10
                color: Theme.dark ? Qt.rgba(1, 0.75, 0.3, 0.12) : Qt.rgba(1, 0.65, 0.1, 0.12)
                Row {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.sparkle; size: 15; stroke: 2; color: Theme.dark ? "#FFC56B" : "#A86200" }
                    Text { id: originText; width: head.width - 50; wrapMode: Text.Wrap; text: Launch.planOrigin + " — zanim się zgodzisz, przejrzyj plan."; color: Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                }
            }
            Item { width: 1; height: 6 }
            Rectangle { width: parent.width; height: 1; color: Theme.line }
        }

        // ——— Kroki ———
        Flickable {
            id: flick
            y: head.y + head.height + 4
            width: parent.width
            height: card.height - y - foot.height
            contentHeight: stepsCol.height + (outBox.visible ? outBox.height + 16 : 0) + 16
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: stepsCol
                x: 26; y: 8
                width: parent.width - 52
                spacing: 4
                Repeater {
                    model: sheet.steps
                    delegate: Item {
                        id: st
                        required property var modelData
                        required property int index
                        readonly property bool codeShown: sheet.showCommands && !sheet.started && modelData.shown !== ""
                        width: stepsCol.width
                        height: stepHead.height + (codeShown ? code.height + 10 : 0) + 10

                        // Numer / stan
                        Item {
                            width: 26; height: 26
                            y: 2
                            Rectangle {
                                anchors.fill: parent; radius: 13
                                color: st.modelData.state === "done" ? "#2FBF71" : st.modelData.state === "failed" ? Theme.danger : st.modelData.state === "running" ? Theme.accentSoft : Theme.fill
                            }
                            Text {
                                visible: st.modelData.state === "pending"
                                anchors.centerIn: parent
                                text: st.index + 1
                                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            Icon {
                                visible: st.modelData.state === "done" || st.modelData.state === "failed"
                                anchors.centerIn: parent
                                d: st.modelData.state === "done" ? Icons.check : Icons.close
                                size: 13; stroke: 2.6; color: "white"
                            }
                            Icon {
                                visible: st.modelData.state === "running"
                                anchors.centerIn: parent
                                d: Icons.reload; size: 14; stroke: 2.2; color: Theme.accentText
                                RotationAnimation on rotation { running: st.modelData.state === "running"; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                            }
                        }
                        Column {
                            id: stepHead
                            x: 38
                            width: parent.width - 38
                            spacing: 2
                            Row {
                                spacing: 8
                                Text { text: st.modelData.title; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: whereText.implicitWidth + 14; height: 20; radius: 10
                                    color: st.modelData.where.startsWith("Na serwerze") || st.modelData.where.startsWith("Z tego") ? Theme.accentSoft : Theme.fill
                                    Text { id: whereText; anchors.centerIn: parent; text: st.modelData.where; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
                                }
                            }
                            Text {
                                width: parent.width; wrapMode: Text.Wrap
                                text: st.modelData.detail
                                color: st.modelData.state === "failed" ? Theme.danger : Theme.text2
                                font.family: Theme.font; font.pixelSize: 12
                            }
                        }
                        Rectangle {
                            id: code
                            visible: st.codeShown
                            x: 38; y: stepHead.height + 8
                            width: parent.width - 38; height: codeText.implicitHeight + 18
                            radius: 10
                            color: Theme.dark ? Qt.rgba(0, 0, 0, 0.35) : "#F4F5F8"
                            border.width: 1; border.color: Theme.line
                            TextEdit {
                                id: codeText
                                x: 12; y: 9; width: parent.width - 24
                                readOnly: true; selectByMouse: true
                                wrapMode: TextEdit.WrapAnywhere
                                text: st.modelData.shown
                                color: Theme.text; selectionColor: Theme.accentSoft; selectedTextColor: Theme.text
                                font.family: "JetBrains Mono"; font.pixelSize: 11
                            }
                        }
                    }
                }
            }

            // Wyjście poleceń podczas i po wykonaniu
            Rectangle {
                id: outBox
                visible: sheet.started
                x: 26; y: stepsCol.y + stepsCol.height + 12
                width: parent.width - 52; height: 220
                radius: 12
                color: Theme.dark ? Qt.rgba(0, 0, 0, 0.4) : "#F4F5F8"
                border.width: 1; border.color: Theme.line
                ListView {
                    id: outList
                    anchors.fill: parent; anchors.margins: 10
                    clip: true
                    model: Launch.output
                    onCountChanged: positionViewAtEnd()
                    delegate: Text {
                        id: outLine
                        required property var model
                        width: outList.width
                        wrapMode: Text.WrapAnywhere
                        text: outLine.model.text
                        color: outLine.model.level === "step" ? Theme.accentText : outLine.model.level === "error" ? Theme.danger : Theme.text
                        font.family: "JetBrains Mono"; font.pixelSize: 11
                        font.weight: outLine.model.level === "step" ? Font.DemiBold : Font.Normal
                    }
                }
            }
        }

        // ——— Przyciski ———
        Item {
            id: foot
            anchors.bottom: parent.bottom
            width: parent.width; height: 70
            Rectangle { width: parent.width; height: 1; color: Theme.line }
            HoverButton {
                visible: !sheet.started
                x: 18; anchors.verticalCenter: parent.verticalCenter
                width: cmdRow.implicitWidth + 20; height: 32; radius: 8
                onClicked: sheet.showCommands = !sheet.showCommands
                Row {
                    id: cmdRow
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: sheet.showCommands ? Icons.eyeOff : Icons.eye; size: 15; stroke: 1.9; color: Theme.text2 }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: sheet.showCommands ? "Ukryj polecenia" : "Pokaż polecenia"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                }
            }
            Row {
                id: buttons
                anchors.right: parent.right; anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Pill { visible: !sheet.started; text: "Anuluj"; onClicked: Launch.cancelPlan() }
                Pill {
                    visible: !sheet.started
                    primary: true
                    iconPath: LI.rocket
                    text: sheet.changes > 0 ? "Wykonaj (" + sheet.changes + ")" : "Wykonaj"
                    onClicked: Launch.confirmPlan()
                }
                Pill { visible: Launch.running; danger: true; text: "Przerwij"; onClicked: Launch.stopRun() }
                Pill {
                    visible: !Launch.running && sheet.started
                    text: "Kopiuj przebieg"
                    iconPath: Icons.copy
                    onClicked: { Launch.copyText(Launch.output.text()); sheet.app.toast("Skopiowano"); }
                }
                Pill {
                    readonly property int prev: sheet.project ? Launch.previousVersion(sheet.project.id) : 0
                    visible: !Launch.running && sheet.liveButBroken && prev > 0
                    text: "Wróć do v" + prev
                    iconPath: Icons.undo
                    onClicked: { const id = Launch.planProject; const v = prev; Launch.closeRun(); Launch.prepareRollback(id, v); }
                }
                Pill {
                    visible: !Launch.running && sheet.started
                    primary: true
                    text: "Zamknij"
                    onClicked: Launch.closeRun()
                }
            }
        }
    }

    Shortcut { sequence: "Esc"; enabled: sheet.open && !Launch.running; onActivated: sheet.started ? Launch.closeRun() : Launch.cancelPlan() }
}
