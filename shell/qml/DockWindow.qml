pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import org.kde.taskmanager as TaskManager
import Aster.Shell
import Aster.Ui

// Dok: jedna szklana wyspa pośrodku dolnej krawędzi, na warstwie „top”, z rezerwacją miejsca.
//  Start (logo Aster) │ przypięte aplikacje i działające okna │ Kosz
// Ikony mają stały rozmiar, po szkle sunie miękka poświata za kursorem.
// Stan systemu i zegar są na górnym pasku (HorizonWindow).
Window {
    id: dock
    color: "transparent"
    title: "Dok"
    visible: false
    width: Screen.width
    // Okno jest wyższe niż wyspa, żeby zmieściły się powiększone ikony i podpowiedzi.
    // Kliknięcia trafiają tylko w wyspę (Platform.setInputRegion), resztę przepuszcza do okien.
    height: 190
    readonly property int shotY: Screen.height - height      // podgląd pulpitu w testach

    readonly property int reserved: 84
    property bool startOpen: false
    signal startRequested()

    // Rozmiar bazowy i powiększenie pod kursorem (1 = wyłączone) z zasięgiem w px od kursora
    readonly property real base: 50
    readonly property real maxMagnify: 1
    readonly property real reach: 92
    readonly property real slotW: base + 8
    readonly property real dividerW: 17

    Component.onCompleted: {
        Platform.makeLayer(dock, "top", 2 | 4 | 8, dock.reserved, "none", "aster-dock");
        visible = true;
        regionTimer.start();
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
            "applications:org.aster.webapps.desktop",
            "applications:org.aster.terminal.desktop",
            "applications:org.aster.store.desktop",
            "applications:org.aster.settings.desktop"
        ]
    }

    // Podgląd (ASTER_PREVIEW): przypięte programy z bazy KDE, bez okien
    ListModel { id: previewModel }
    Timer {
        running: Platform.preview
        interval: 10
        onTriggered: {
            const ids = ["org.aster.files", "org.aster.browser", "org.aster.webapps", "org.aster.terminal", "org.aster.editor", "org.aster.store", "org.aster.settings"];
            ids.forEach((id, i) => {
                const a = Platform.appInfo(id);
                if (!a.valid) return;
                previewModel.append({ decoration: a.icon, display: a.name, IsWindow: i < 3, IsActive: i === 1, IsStartup: false,
                                      LauncherUrlWithoutIcon: "applications:" + id + ".desktop" });
            });
            // Zrzuty: kursor nad wybraną ikoną, żeby było widać powiększenie
            const hx = Platform.env("ASTER_SHOT_HOVER");
            if (hx !== "") { dock.pointerX = dock.slotCenter(Number(hx)) + 10; dock.pointerY = dock.height - 40; dock.forcedHover = true; }
        }
    }
    readonly property var model: Platform.preview ? previewModel : tasks
    readonly property int count: repeater.count

    // ——— Położenie „spoczynkowe” (bez powiększenia) — z niego liczymy powiększenie, żeby ikony nie drgały ———
    readonly property real restWidth: 2 * slotW + count * slotW + 2 * dividerW
    readonly property real restLeft: (width - restWidth) / 2
    // slot: 0 = Start, 1…count = programy, count + 1 = Kosz
    function slotCenter(i) {
        let x = restLeft + slotW / 2 + i * slotW;
        if (i >= 1) x += dividerW;
        if (i >= count + 1) x += dividerW;
        return x;
    }
    function magnifyAt(i) {
        if (hoverAmt <= 0) return 1;
        const d = (pointerX - slotCenter(i)) / reach;
        return 1 + (maxMagnify - 1) * hoverAmt * Math.exp(-d * d * 1.6);
    }

    property real pointerX: -1000
    property real pointerY: 0
    property bool forcedHover: false
    readonly property bool hovering: hover.hovered || forcedHover
    property real hoverAmt: hovering ? 1 : 0
    Behavior on hoverAmt { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    // Na korzeniu okna, żeby kursor był śledzony także nad ikonami
    HoverHandler {
        id: hover
        onPointChanged: if (hovered && !dock.forcedHover) { dock.pointerX = point.position.x; dock.pointerY = point.position.y; }
    }

    // ——— Wyspa ———
    Island {
        id: island
        x: Math.round((dock.width - width) / 2)
        y: dock.height - height - 10
        width: row.width + 18
        height: 66
        radius: 24
        spot: dock.hoverAmt * 0.9
        spotX: dock.pointerX - x
        spotY: dock.pointerY - y
        onWidthChanged: dock.updateRegion()

        Row {
            id: row
            x: 9
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            spacing: 0

            DockItem {
                id: startItem
                base: dock.base
                magnify: dock.magnifyAt(0)
                desktopId: "aster-start"
                label: "Start"
                pressedLook: dock.startOpen
                onClicked: dock.startRequested()
            }
            Divider {}
            Repeater {
                id: repeater
                model: dock.model
                delegate: DockItem {
                    id: di
                    required property var model
                    required property int index
                    base: dock.base
                    magnify: dock.magnifyAt(index + 1)
                    desktopId: {
                        const u = (di.model.LauncherUrlWithoutIcon || "").toString();
                        return u.replace(/^.*[\/:]/, "").replace(/\.desktop$/, "");
                    }
                    iconSource: di.model.decoration
                    label: di.model.display || ""
                    running: di.model.IsWindow === true
                    active: di.model.IsActive === true
                    starting: di.model.IsStartup === true
                    onClicked: {
                        const idx = tasks.makeModelIndex(di.index);
                        if (di.model.IsWindow && di.model.IsActive) tasks.requestToggleMinimized(idx);
                        else tasks.requestActivate(idx);
                    }
                    onMiddleClicked: tasks.requestNewInstance(tasks.makeModelIndex(di.index))
                    // KWin animuje minimalizację okna do tego miejsca
                    function publish() {
                        if (Platform.preview) return;
                        const p = di.mapToGlobal(0, 0);
                        tasks.requestPublishDelegateGeometry(tasks.makeModelIndex(di.index), Qt.rect(p.x, p.y, di.width, di.height), di);
                    }
                    onXChanged: publishTimer.restart()
                    Timer { id: publishTimer; interval: 300; onTriggered: di.publish() }
                    Component.onCompleted: publish()
                }
            }
            Divider {}
            DockItem {
                base: dock.base
                magnify: dock.magnifyAt(dock.count + 1)
                desktopId: "aster-trash"
                label: "Kosz"
                onClicked: Platform.openUrl("trash:/")
            }
        }
    }

    component Divider: Item {
        anchors.bottom: parent ? parent.bottom : undefined
        width: dock.dividerW
        height: dock.base
        Rectangle {
            anchors.centerIn: parent
            width: 1; height: 30
            color: Theme.dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0, 0, 0, 0.12)
        }
    }

    // Rozmycie pod wyspą; kliknięcia — w wyspę i (gdy kursor jest nad dokiem) w powiększone ikony nad nią
    function updateRegion() { if (!regionTimer.running) regionTimer.start(); }
    onHoveringChanged: updateRegion()
    Timer {
        id: regionTimer
        interval: 16
        onTriggered: {
            const r = { x: island.x, y: island.y, w: island.width, h: island.height, r: island.radius };
            Platform.setBlur(dock, [r]);
            const lift = dock.hovering ? Math.ceil(dock.base * (dock.maxMagnify - 1)) + 6 : 0;
            Platform.setInputRegion(dock, [{ x: r.x, y: r.y - lift, w: r.w, h: r.h + lift, r: r.r }]);
        }
    }
}
