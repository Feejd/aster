pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import Aster.Shell
import Aster.Ui

// Dolny pasek: trzy szklane wyspy na warstwie „top”, z rezerwacją miejsca (okna nie wchodzą pod spód).
//  lewa    — logo Aster: otwiera Start (to samo robi klawisz Super)
//  środek  — dok: przypięte aplikacje + działające okna
//  prawa   — zegar i skrót do ustawień
Window {
    id: dock
    color: "transparent"
    title: "Dok"
    visible: false
    width: Screen.width
    // Okno jest wyższe niż wyspy, żeby zmieściły się podpowiedzi nad ikonami.
    // Kliknięcia trafiają tylko w wyspy (Platform.setInputRegion), resztę przepuszcza do okien.
    height: 150

    readonly property int reserved: 96
    property bool startOpen: false
    property bool controlOpen: false
    signal startRequested()
    signal controlRequested()

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
            "applications:org.aster.browser.desktop",
            "applications:org.kde.kate.desktop",
            "applications:org.kde.konsole.desktop",
            "applications:org.aster.store.desktop",
            "applications:systemsettings.desktop"
        ]
    }

    // Podgląd (ASTER_PREVIEW): przypięte programy z bazy KDE, bez okien
    ListModel { id: previewModel }
    Component.onDestruction: {}
    Timer {
        running: Platform.preview
        interval: 10
        onTriggered: {
            const ids = ["org.aster.files", "org.aster.browser", "org.aster.webapps", "org.aster.store", "org.kde.konsole", "systemsettings"];
            ids.forEach((id, i) => {
                const a = Platform.appInfo(id);
                if (!a.valid) return;
                previewModel.append({ decoration: a.icon, display: a.name, IsWindow: i < 2, IsActive: i === 0, IsStartup: false,
                                      LauncherUrlWithoutIcon: "applications:" + id + ".desktop" });
            });
        }
    }

    property date now: new Date()
    Timer { interval: 1000; repeat: true; running: true; onTriggered: dock.now = new Date() }

    // ——— Lewa wyspa: logo Aster (kolorowy kafelek) — otwiera Start ———
    Island {
        id: left
        x: 18
        y: dock.height - height - 14
        width: 76; height: 76
        radius: 26
        AppIcon {
            id: logoBtn
            anchors.centerIn: parent
            size: 52
            desktopId: "aster-start"
            scale: logoArea.pressed ? 0.9 : (logoArea.containsMouse ? 1.04 : 1)
            rotation: dock.startOpen ? 90 : 0
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
            Behavior on rotation { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
            MouseArea { id: logoArea; anchors.fill: parent; hoverEnabled: true; onClicked: dock.startRequested() }
        }
    }

    // ——— Środek: dok ———
    Island {
        id: center
        anchors.horizontalCenter: parent.horizontalCenter
        y: dock.height - height - 14
        width: row.width + 20
        height: 76
        radius: 26
        onWidthChanged: blurTimer.restart()
        onXChanged: blurTimer.restart()

        Row {
            id: row
            x: 10
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            spacing: 2
            Repeater {
                model: Platform.preview ? previewModel : tasks
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

    // ——— Prawa wyspa: stan systemu (centrum sterowania) i zegar ———
    Island {
        id: right
        anchors.right: parent.right
        anchors.rightMargin: 18
        y: dock.height - height - 14
        width: tray.width + 28
        height: 76
        radius: 26

        Row {
            id: tray
            anchors.centerIn: parent
            spacing: 14
            // Stan sieci, dźwięku i baterii — otwiera centrum sterowania
            Rectangle {
                id: status
                anchors.verticalCenter: parent.verticalCenter
                width: statusRow.width + 22; height: 44; radius: 14
                color: dock.controlOpen ? Theme.accentSoft : (statusArea.containsMouse ? Theme.hover : "transparent")
                scale: statusArea.pressed ? 0.94 : 1
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on scale { NumberAnimation { duration: 100 } }
                readonly property color ink: dock.controlOpen ? Theme.accentText : Theme.text
                Row {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 9
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        d: !ControlCenter.wifiAvailable && ControlCenter.wired ? Icons.ethernet : Icons.wifi
                        size: 19; stroke: 2
                        color: status.ink
                        opacity: ControlCenter.networkName !== "" ? 1 : 0.4
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: ControlCenter.audioAvailable
                        d: ControlCenter.muted || ControlCenter.volume === 0 ? Icons.volumeOff : ControlCenter.volume < 0.5 ? Icons.volumeLow : Icons.volume
                        size: 19; stroke: 2
                        color: status.ink
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: ControlCenter.batteryAvailable
                        spacing: 3
                        Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.battery; size: 20; stroke: 1.8; color: status.ink }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ControlCenter.battery + "%"
                            color: status.ink
                            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                        }
                    }
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: ControlCenter.doNotDisturb
                        d: Icons.moon
                        size: 17; stroke: 2
                        color: status.ink
                    }
                }
                MouseArea { id: statusArea; anchors.fill: parent; hoverEnabled: true; onClicked: dock.controlRequested() }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    anchors.right: parent.right
                    text: dock.now.toLocaleTimeString(Qt.locale("pl_PL"), "HH:mm")
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 18; font.letterSpacing: -0.2; font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
                Text {
                    anchors.right: parent.right
                    text: dock.now.toLocaleDateString(Qt.locale("pl_PL"), "ddd, d MMM")
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                }
            }
        }
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
