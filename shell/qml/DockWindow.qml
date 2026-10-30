pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import Aster.Shell
import Aster.Ui

// Dolny pasek: trzy szklane wyspy na warstwie „top”, z rezerwacją miejsca (okna nie wchodzą pod spód).
//  lewa    — wyszukiwanie: otwiera Start (to samo robi klawisz Super)
//  środek  — dok: przypięte aplikacje + działające okna
//  prawa   — zegar i skrót do ustawień
Window {
    id: dock
    color: "transparent"
    visible: false
    width: Screen.width
    // Okno jest wyższe niż wyspy, żeby zmieściły się podpowiedzi nad ikonami.
    // Kliknięcia trafiają tylko w wyspy (Platform.setInputRegion), resztę przepuszcza do okien.
    height: 150

    readonly property int reserved: 84
    property bool startOpen: false
    signal startRequested()

    Component.onCompleted: {
        Platform.makeLayer(dock, "top", 2 | 4 | 8, dock.reserved, "none", "aster-dock");
        visible = true;
        blurTimer.start();
    }

    TaskManager.TasksModel {
        id: tasks
        groupMode: TaskManager.TasksModel.GroupApplications
        sortMode: TaskManager.TasksModel.SortManual
        launchInPlace: true
        separateLaunchers: false
        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false
        launcherList: [
            "applications:org.aster.files.desktop",
            "applications:org.mozilla.firefox.desktop",
            "applications:org.kde.kate.desktop",
            "applications:org.kde.konsole.desktop",
            "applications:org.kde.discover.desktop",
            "applications:systemsettings.desktop"
        ]
    }

    property date now: new Date()
    Timer { interval: 1000; repeat: true; running: true; onTriggered: dock.now = new Date() }

    // ——— Lewa wyspa: wyszukiwanie ———
    Island {
        id: left
        x: 16
        y: dock.height - height - 12
        width: 64; height: 64
        HoverButton {
            anchors.centerIn: parent
            icon: "search"
            active: dock.startOpen
            onClicked: dock.startRequested()
        }
    }

    // ——— Środek: dok ———
    Island {
        id: center
        anchors.horizontalCenter: parent.horizontalCenter
        y: dock.height - height - 12
        width: row.width + 24
        height: 64
        onWidthChanged: blurTimer.restart()
        onXChanged: blurTimer.restart()

        Row {
            id: row
            x: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            spacing: 4
            Repeater {
                model: tasks
                delegate: DockItem {
                    id: di
                    onActivated: {
                        const idx = tasks.makeModelIndex(di.index);
                        if (di.model.IsWindow && di.model.IsActive) tasks.requestToggleMinimized(idx);
                        else tasks.requestActivate(idx);
                    }
                    onNewInstance: tasks.requestNewInstance(tasks.makeModelIndex(di.index))
                    // KWin animuje minimalizację okna do tego miejsca
                    function publish() {
                        const p = di.mapToGlobal(0, 0);
                        tasks.requestPublishDelegateGeometry(tasks.makeModelIndex(di.index), Qt.rect(p.x, p.y, di.width, di.height), di);
                    }
                    onXChanged: publish()
                    Component.onCompleted: publish()
                }
            }
        }
    }

    // ——— Prawa wyspa: zegar ———
    Island {
        id: right
        anchors.right: parent.right
        anchors.rightMargin: 16
        y: dock.height - height - 12
        width: tray.width + 28
        height: 64

        Row {
            id: tray
            anchors.centerIn: parent
            spacing: 14
            HoverButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "configure"
                onClicked: Platform.run("systemsettings")
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    anchors.right: parent.right
                    text: dock.now.toLocaleTimeString(Qt.locale("pl_PL"), "HH:mm")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                }
                Text {
                    anchors.right: parent.right
                    text: dock.now.toLocaleDateString(Qt.locale("pl_PL"), "ddd, d MMM")
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: 11
                }
            }
        }
    }

    component HoverButton: Rectangle {
        id: hb
        property string icon
        property bool active: false
        signal clicked()
        width: 44; height: 44; radius: 14
        color: active ? Theme.accentSoft : (hbArea.containsMouse ? Theme.hover : "transparent")
        scale: hbArea.pressed ? 0.92 : 1
        Behavior on color { ColorAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 100 } }
        Kirigami.Icon {
            anchors.centerIn: parent
            width: 22; height: 22
            source: hb.icon
            color: hb.active ? Theme.accentText : Theme.text
            isMask: true
        }
        MouseArea { id: hbArea; anchors.fill: parent; hoverEnabled: true; onClicked: hb.clicked() }
    }

    Timer {
        id: blurTimer
        interval: 50
        onTriggered: {
            const r = [];
            for (const it of [left, center, right])
                r.push({ x: it.x, y: it.y, w: it.width, h: it.height, r: it.radius });
            Platform.setBlur(dock, r);
            Platform.setInputRegion(dock, r);
        }
    }
}
