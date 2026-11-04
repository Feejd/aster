pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Launch

// Historia: wszystkie wersje (najnowsze na górze) i zdarzenia — kto i kiedy wdrożył albo przywrócił
Flickable {
    id: page
    required property var project
    required property var app
    readonly property var history: (project.history || []).slice().reverse()
    readonly property var events: (project.events || []).slice().reverse().slice(0, 30)

    contentHeight: col.height + 48
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
        id: col
        x: 28; y: 24
        width: page.width - 56
        spacing: 16

        Card {
            title: "Wersje"
            subtitle: page.project.target === "ssh"
                      ? "Na serwerze zostaje " + (page.project.keep || 5) + " ostatnich wersji — do każdej z nich wrócisz w kilka sekund, bez ponownego wysyłania plików."
                      : "Kopie " + (page.project.keep || 5) + " ostatnich wersji są na tym komputerze — przywrócenie wdraża wybraną kopię jeszcze raz."
            spacing: 0
            Text {
                visible: page.history.length === 0
                text: "Jeszcze nic nie wdrożono."
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
            }
            Repeater {
                model: page.history
                delegate: VersionRow {
                    required property var modelData
                    entry: modelData
                    project: page.project
                    app: page.app
                }
            }
        }

        Card {
            visible: page.events.length > 0
            title: "Zdarzenia"
            spacing: 8
            Repeater {
                model: page.events
                delegate: Row {
                    id: ev
                    required property var modelData
                    width: parent.width
                    spacing: 10
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8; height: 8; radius: 4
                        color: ev.modelData.ok ? (ev.modelData.kind === "rollback" ? "#F5A623" : "#2FBF71") : Theme.danger
                    }
                    Text {
                        width: 130
                        text: page.app.when(ev.modelData.time)
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                    }
                    Text {
                        width: parent.width - 160; elide: Text.ElideRight
                        text: (ev.modelData.kind === "rollback" ? "Przywrócenie v" + ev.modelData.v + (ev.modelData.from ? " (z v" + ev.modelData.from + ")" : "")
                                                                : "Wdrożenie v" + ev.modelData.v)
                              + (ev.modelData.ok ? "" : " — nieudane")
                              + (ev.modelData.origin ? " · " + (ev.modelData.origin.startsWith("Prośba") ? "na prośbę asystenta / innego programu" : ev.modelData.origin.toLowerCase()) : "")
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                    }
                }
            }
        }
    }
}
