pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQml.Models
import org.kde.taskmanager as TaskManager
import Aster.Shell
import Aster.Ui

// Dok: jedna szklana wyspa pośrodku dolnej krawędzi, na warstwie „top”. Gdy okno na niego zachodzi, chowa się
// i oddaje miejsce, a wraca po dojechaniu kursorem do krawędzi (można to wyłączyć w Ustawieniach → Pulpit i okna).
//  Start (logo Aster) │ przypięte aplikacje i działające okna │ Kosz
// Ikony mają stały rozmiar, po szkle sunie miękka poświata za kursorem.
// Stan systemu i zegar są na górnym pasku (HorizonWindow).
Window {
    id: dock
    property bool followsPrimary: true   // po zmianie głównego ekranu main.cpp przenosi okno
    color: "transparent"
    title: "Dok"
    visible: false
    width: Screen.width
    // Okno jest wyższe niż wyspa, żeby zmieściły się podpowiedzi i karta okien.
    // Kliknięcia trafiają tylko w wyspę i kartę (Platform.setInputRegion), resztę przepuszcza do okien.
    height: 380
    readonly property int shotY: Screen.height - height      // podgląd pulpitu w testach

    readonly property int reserved: Config.dockAutoHide ? 0 : 84
    onReservedChanged: Platform.makeLayer(dock, "top", 2 | 4 | 8, dock.reserved, "none", "aster-dock")
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

    // ——— Chowanie: czy jakieś okno zachodzi na miejsce doku ———
    TaskManager.VirtualDesktopInfo { id: desktops }
    TaskManager.TasksModel {
        id: visibleWindows
        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByVirtualDesktop: true
        virtualDesktop: desktops.currentDesktop
        filterByActivity: false
        filterMinimized: true
    }
    Instantiator {
        id: windowWatch
        model: Platform.preview ? null : visibleWindows
        onObjectAdded: dock.checkOverlap()
        onObjectRemoved: dock.checkOverlap()
        delegate: QtObject {
            required property var model
            readonly property rect geometry: model.Geometry || Qt.rect(0, 0, 0, 0)
            onGeometryChanged: dock.checkOverlap()
        }
    }
    property bool covered: false
    function checkOverlap() { overlapTimer.restart(); }
    Timer {
        id: overlapTimer
        interval: 60
        onTriggered: {
            const s = dock.screen;
            if (!s) return;
            const top = s.virtualY + s.height - dock.reserveArea, left = s.virtualX + (s.width - island.width) / 2, right = left + island.width;
            let hit = false;
            for (let i = 0; i < windowWatch.count && !hit; ++i) {
                const o = windowWatch.objectAt(i);
                if (!o) continue;
                const g = o.geometry;
                hit = g.width > 0 && g.y + g.height > top && g.y < s.virtualY + s.height && g.x + g.width > left && g.x < right;
            }
            dock.covered = hit;
        }
    }
    readonly property int reserveArea: 84
    onCoveredChanged: updateRegion()

    // Po zjechaniu kursorem dok zostaje jeszcze chwilę: przejechanie obok nie ma nim szarpać
    property bool pointerNear: false
    onHoveringChanged: {
        if (hovering) { leaveTimer.stop(); pointerNear = true; }
        else leaveTimer.restart();
    }
    Timer { id: leaveTimer; interval: 450; onTriggered: dock.pointerNear = false }
    readonly property bool revealed: !Config.dockAutoHide || !covered || pointerNear || startOpen || popup.open
    onRevealedChanged: updateRegion()

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
    readonly property bool hovering: hover.hovered || forcedHover || popupHover.hovered
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
        y: dock.height - height - 10 + (dock.revealed ? 0 : 96)
        Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        onYChanged: dock.updateRegion()
        width: row.width + 18
        height: 66
        radius: 16
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
                    readonly property int windowCount: di.model.IsGroupParent ? (di.model.ChildCount || 0) : (di.model.IsWindow ? 1 : 0)
                    popupOpen: popup.open && popup.index === di.index
                    running: di.model.IsWindow === true
                    active: di.model.IsActive === true
                    starting: di.model.IsStartup === true
                    onClicked: {
                        popup.hide();
                        const idx = tasks.makeModelIndex(di.index);
                        // Kilka okien: kolejne kliknięcia przechodzą między nimi, zamiast chować wszystkie naraz
                        if (di.model.IsWindow && di.model.IsActive && !di.model.IsGroupParent) tasks.requestToggleMinimized(idx);
                        else tasks.requestActivate(idx);
                    }
                    onRightClicked: popup.showFor(di, di.index, true)
                    onHoveredChanged: {
                        if (hovered && windowCount > 1) popup.schedule(di, di.index);
                        else popup.cancel();
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

    // ——— Karta nad ikoną: okna programu (po najechaniu, gdy jest ich kilka) i działania (prawy przycisk) ———
    DelegateModel {
        id: childWindows
        model: Platform.preview ? null : tasks
        rootIndex: popup.groupIndex
        delegate: PopupRow {
            id: cw
            required property var model
            required property int index
            text: model.display || ""
            emphasized: model.IsActive === true
            closable: true
            onClicked: { tasks.requestActivate(tasks.makeModelIndex(popup.index, cw.index)); popup.hide(); }
            onCloseClicked: tasks.requestClose(tasks.makeModelIndex(popup.index, cw.index))
        }
    }
    Island {
        id: popup
        property bool open: false
        property bool withActions: false
        property int index: -1
        property var item: null
        property var pending: null
        property int pendingIndex: -1
        property var groupIndex: undefined
        readonly property bool grouped: item ? item.windowCount > 1 : false
        function showFor(it, i, actions) {
            delayTimer.stop();
            item = it;
            index = i;
            withActions = actions;
            groupIndex = grouped ? tasks.makeModelIndex(i) : tasks.index(-1, -1);
            open = true;
            dock.updateRegion();
        }
        function schedule(it, i) { pending = it; pendingIndex = i; closeTimer.stop(); delayTimer.restart(); }
        function cancel() { delayTimer.stop(); if (open) closeTimer.restart(); }
        function hide() { delayTimer.stop(); closeTimer.stop(); open = false; dock.updateRegion(); }
        Timer { id: delayTimer; interval: 320; onTriggered: popup.showFor(popup.pending, popup.pendingIndex, false) }
        Timer { id: closeTimer; interval: 380; onTriggered: if (!popupHover.hovered) popup.hide() }
        HoverHandler {
            id: popupHover
            onHoveredChanged: { if (hovered) closeTimer.stop(); else closeTimer.restart(); }
        }

        visible: open
        radius: 12
        width: 280
        height: popupList.height + 16
        x: {
            if (!item) return 0;
            const c = item.mapToItem(island, item.width / 2, 0).x + island.x;
            return Math.max(10, Math.min(dock.width - width - 10, Math.round(c - width / 2)));
        }
        y: island.y - height - 10
        onHeightChanged: dock.updateRegion()
        onXChanged: dock.updateRegion()

        Column {
            id: popupList
            x: 8; y: 8
            width: parent.width - 16
            spacing: 2
            Repeater { model: popup.grouped ? childWindows : null }
            Rectangle {
                visible: popup.grouped && popup.withActions
                width: parent.width; height: 1
                color: Theme.line
            }
            PopupRow {
                visible: popup.withActions
                text: "Nowe okno"
                onClicked: { tasks.requestNewInstance(tasks.makeModelIndex(popup.index)); popup.hide(); }
            }
            PopupRow {
                visible: popup.withActions && popup.item !== null && popup.item.running
                text: popup.grouped ? "Zamknij wszystkie okna" : "Zamknij"
                onClicked: { tasks.requestClose(tasks.makeModelIndex(popup.index)); popup.hide(); }
            }
        }
    }

    component PopupRow: Rectangle {
        id: pr
        property string text
        property bool emphasized: false
        property bool closable: false
        signal clicked()
        signal closeClicked()
        width: popupList.width
        height: 36
        radius: 10
        color: prHover.hovered ? Theme.hover : "transparent"
        HoverHandler { id: prHover }
        MouseArea { anchors.fill: parent; onClicked: pr.clicked() }
        Text {
            x: 10
            width: parent.width - x - (pr.closable ? 34 : 10)
            anchors.verticalCenter: parent.verticalCenter
            text: pr.text
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 13; font.weight: pr.emphasized ? Font.DemiBold : Font.Normal
        }
        HoverButton {
            visible: pr.closable && prHover.hovered
            anchors.right: parent.right; anchors.rightMargin: 5
            anchors.verticalCenter: parent.verticalCenter
            width: 26; height: 26; radius: 13
            baseColor: "transparent"
            color: hovered ? Theme.hover : baseColor
            onClicked: pr.closeClicked()
            Icon { anchors.centerIn: parent; d: Icons.close; size: 12; stroke: 2.2; color: Theme.text2 }
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

    // Rozmycie pod wyspą i kartą. Schowany dok łapie kursor tylko pasem przy krawędzi; odkryty sięga krawędzi, żeby nie migał
    function updateRegion() { if (!regionTimer.running) regionTimer.start(); }
    Timer {
        id: regionTimer
        interval: 16
        onTriggered: {
            const r = { x: island.x, y: island.y, w: island.width, h: island.height, r: island.radius };
            const blur = [];
            if (island.y < dock.height) blur.push(r);
            const input = dock.revealed ? [{ x: r.x, y: r.y, w: r.w, h: dock.height - r.y, r: r.r }]
                                        : [{ x: r.x, y: dock.height - 2, w: r.w, h: 2, r: 0 }];
            if (popup.open) {
                const p = { x: popup.x, y: popup.y, w: popup.width, h: popup.height, r: popup.radius };
                blur.push(p);
                // Kursor ma przejść z ikony na kartę bez wyjścia poza obszar doku
                input.push({ x: p.x, y: p.y, w: p.w, h: island.y - p.y, r: p.r });
            }
            Platform.setBlur(dock, blur);
            Platform.setInputRegion(dock, input);
        }
    }
}
