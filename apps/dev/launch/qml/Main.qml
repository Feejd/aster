pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Dialogs
import Aster.Ui
import Aster.Launch
import "LaunchIcons.js" as LI

// Aster Launch — wdrażanie aplikacji:
//  • pasek boczny: projekty (kropka = czy strona odpowiada), „Dodaj projekt”,
//  • strona projektu: Przegląd (co działa na produkcji), Historia (wersje, przywracanie), Logi (na żywo), Cel (serwer/hosting),
//  • każde wdrożenie i przywrócenie: najpierw plan z dokładnymi poleceniami, potem potwierdzenie (PlanSheet).
Window {
    id: win
    property string selected: ""
    property string tab: "overview"

    width: 1060 + 2 * m
    height: 700 + 2 * m
    minimumWidth: 820 + 2 * m
    minimumHeight: 520 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: "Aster Launch"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 24

    readonly property var projects: Launch.projects
    readonly property var project: projects.find(p => p.id === selected) || null
    readonly property var tabs: [
        { id: "overview", name: "Przegląd" },
        { id: "history", name: "Historia" },
        { id: "logs", name: "Logi" },
        { id: "target", name: "Cel wdrożenia" }
    ]

    onProjectsChanged: if (!project && projects.length > 0) selected = projects[0].id
    Component.onCompleted: { if (!project && projects.length > 0) selected = projects[0].id; effectsTimer.restart(); }

    function go(t) { if (t === tab) return; tab = t; pageAnim.restart(); }
    function select(id) { if (id === selected) return; selected = id; tab = "overview"; pageAnim.restart(); }
    function toast(text) { toastBox.text = text; toastBox.shown = true; toastTimer.restart(); }
    function addFolder(url) {
        const id = Launch.addProject(String(url));
        if (id) { select(id); toast("Dodano projekt"); }
        else toast("To nie jest folder");
    }
    function deploy() {
        if (!project) return;
        if (project.target === "ssh" && !project.host) { go("target"); toast("Najpierw podaj adres serwera"); return; }
        Launch.prepareDeploy(selected);
    }
    function rollback(v) { Launch.prepareRollback(selected, v); }
    function statusColor(p) {
        if (!p || !p.current) return Theme.text2;
        if (!p.lastCheck) return "#F5A623";
        return p.lastCheck.ok ? "#2FBF71" : "#E5484D";
    }
    function when(iso) {
        if (!iso) return "";
        const d = new Date(iso);
        const now = new Date();
        const mins = Math.round((now - d) / 60000);
        if (mins < 1) return "przed chwilą";
        if (mins < 60) return mins + " min temu";
        const sameDay = d.toDateString() === now.toDateString();
        const hm = d.toLocaleTimeString(Qt.locale("pl_PL"), "HH:mm");
        if (sameDay) return "dziś, " + hm;
        const y = new Date(now); y.setDate(now.getDate() - 1);
        if (d.toDateString() === y.toDateString()) return "wczoraj, " + hm;
        return d.toLocaleDateString(Qt.locale("pl_PL"), "d MMM yyyy") + ", " + hm;
    }

    Connections {
        target: Launch
        function onPlanFailed(id, message) { win.toast(message); }
        function onMessage(text) { win.toast(text); }
        function onProbed(id, ok, message) { if (!Launch.preparing) win.toast(ok ? "Połączenie działa" : message); }
    }

    // Do testów (ASTER_OPEN): add | project:N | history | logs | target | plan | rollback:N | ask | menu
    function testOpen(what) {
        for (const w of what.split(",")) {
            if (w.startsWith("project:")) select(projects[Number(w.slice(8))].id);
            else if (w === "history" || w === "logs" || w === "target" || w === "overview") go(w);
            else if (w === "live") { go("logs"); Launch.startLiveLog(selected); }
            else if (w === "plan") deploy();
            else if (w === "run") { deploy(); runAfterPlan.enabled = true; }
            else if (w.startsWith("rollback:")) rollback(Number(w.slice(9)));
            else if (w === "health") Launch.checkHealth(selected);
            else if (w === "dns") Launch.checkDns(selected);
            else if (w === "probe") Launch.probe(selected);
            else if (w === "ask") Launch.requestPermission("Udostępnić logi „" + (project ? project.name : "") + "”?", "Asystent Aster prosi o ostatnie 200 wierszy logów produkcji. Logi mogą zawierać adresy e-mail, adresy IP albo inne dane użytkowników strony.", "Udostępnij");
            else if (w === "start") startOverride = true;
            else if (w.startsWith("scroll:")) { scrollTimer.to = Number(w.slice(7)); scrollTimer.start(); }
            else if (w.startsWith("confirm-after:")) { testConfirm.interval = Number(w.slice(14)); testConfirm.start(); }
            else if (w.startsWith("deny-after:")) { testConfirm.deny = true; testConfirm.interval = Number(w.slice(11)); testConfirm.start(); }
        }
    }
    // Tylko do testów (ASTER_OPEN=confirm-after:MS, działa wyłącznie przy ASTER_SHOT): po chwili „klika” Wykonaj / Udostępnij
    Timer {
        id: testConfirm
        property bool deny: false
        repeat: true
        onTriggered: {
            if (Launch.ask.token) Launch.answer(Launch.ask.token, !deny);
            else if (Launch.plan.length > 0 && !Launch.running && Launch.runResult === "") { if (deny) Launch.cancelPlan(); else Launch.confirmPlan(); }
        }
    }
    property bool startOverride: false
    Timer {
        id: scrollTimer
        property int to: 0
        interval: 600
        onTriggered: { const f = pageLoader.item; if (f && f.contentHeight !== undefined) f.contentY = Math.min(to, Math.max(0, f.contentHeight - f.height)); }
    }
    // Tylko do testów: plan potwierdzony automatycznie (ASTER_OPEN=run) — w normalnej pracy zawsze klika użytkownik
    Connections {
        id: runAfterPlan
        enabled: false
        target: Launch
        function onPlanReady(id) { runAfterPlan.enabled = false; Launch.confirmPlan(); }
    }

    Shortcut { sequence: "Ctrl+O"; onActivated: folderDialog.open() }
    Shortcut { sequence: "Ctrl+Return"; enabled: !!win.project && Launch.plan.length === 0; onActivated: win.deploy() }
    Shortcut { sequence: "Ctrl+1"; onActivated: win.go("overview") }
    Shortcut { sequence: "Ctrl+2"; onActivated: win.go("history") }
    Shortcut { sequence: "Ctrl+3"; onActivated: win.go("logs") }
    Shortcut { sequence: "Ctrl+4"; onActivated: win.go("target") }
    Shortcut { sequence: "Ctrl+W"; onActivated: win.close() }

    FolderDialog {
        id: folderDialog
        title: "Folder projektu do wdrożenia"
        onAccepted: win.addFolder(selectedFolder)
    }

    // ——— Okno ———
    function updateEffects() {
        WindowEffects.setBlur(win, Qt.rect(m, m, frame.width, frame.height), r);
        WindowEffects.setInputRegion(win, Qt.rect(Math.max(0, m - 6), Math.max(0, m - 6), frame.width + (maxed ? 0 : 12), frame.height + (maxed ? 0 : 12)));
    }
    onWidthChanged: effectsTimer.restart()
    onHeightChanged: effectsTimer.restart()
    onMaxedChanged: effectsTimer.restart()
    Timer { id: effectsTimer; interval: 16; onTriggered: win.updateEffects() }

    WindowShadow { window: win; frame: frame; radius: win.r; visible: !win.maxed }
    ResizeHandles { window: win; frame: frame; margin: win.m }

    Rectangle {
        id: frame
        x: win.m; y: win.m
        width: win.width - 2 * win.m
        height: win.height - 2 * win.m
        radius: win.r
        color: Theme.windowGlass
        border.width: win.maxed ? 0 : 1
        border.color: Theme.edge
        WindowSheen { window: win; radius: win.r }
        clip: true

        DropArea {
            anchors.fill: parent
            onDropped: (drop) => { if (drop.hasUrls) win.addFolder(drop.urls[0]); }
        }

        // ——— Pasek boczny ———
        Item {
            id: side
            width: 236; height: parent.height
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }

            Row {
                x: 20; y: 22
                spacing: 10
                Rectangle {
                    width: 30; height: 30; radius: 9
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#FFB27A" }
                        GradientStop { position: 1; color: "#E5366F" }
                    }
                    Icon { anchors.centerIn: parent; d: LI.rocket; size: 17; stroke: 1.9; color: "white" }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Launch"
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.Bold; font.letterSpacing: -0.3
                }
            }

            Text {
                x: 22; y: 74
                visible: win.projects.length > 0
                text: "PROJEKTY"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.6
            }
            ListView {
                id: projectList
                x: 10; y: 96
                width: parent.width - 20
                height: parent.height - y - addButton.height - 30
                clip: true
                spacing: 2
                model: win.projects
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    id: nav
                    required property var modelData
                    readonly property bool active: win.selected === modelData.id
                    width: projectList.width; height: 48
                    radius: 10
                    color: active ? Theme.accent : (navArea.containsMouse ? Theme.hover : "transparent")
                    Rectangle {
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        width: 28; height: 28; radius: 8
                        color: nav.active ? Qt.rgba(1, 1, 1, 0.2) : Theme.fill
                        Icon {
                            anchors.centerIn: parent
                            d: nav.modelData.target === "ssh" ? LI.server : LI.cloud
                            size: 15; stroke: 1.8; color: nav.active ? "white" : Theme.text2
                        }
                        Rectangle {
                            anchors.right: parent.right; anchors.bottom: parent.bottom
                            anchors.rightMargin: -2; anchors.bottomMargin: -2
                            width: 10; height: 10; radius: 5
                            color: win.statusColor(nav.modelData)
                            border.width: 2; border.color: nav.active ? Theme.accent : (Theme.dark ? "#1E2027" : "#EEF0F5")
                        }
                    }
                    Column {
                        x: 48; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 56
                        spacing: 1
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: nav.modelData.name
                            color: nav.active ? "white" : Theme.text
                            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: (nav.modelData.current ? "v" + nav.modelData.current + " · " : "") + (nav.modelData.domain || nav.modelData.host || nav.modelData.typeName)
                            color: nav.active ? Qt.rgba(1, 1, 1, 0.8) : Theme.text2
                            font.family: Theme.font; font.pixelSize: 11
                        }
                    }
                    MouseArea {
                        id: navArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: win.select(nav.modelData.id)
                    }
                }
            }
            HoverButton {
                id: addButton
                x: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 16
                width: parent.width - 20; height: 38; radius: 10
                onClicked: folderDialog.open()
                Row {
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.plus; size: 16; stroke: 2; color: Theme.accentText }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Dodaj projekt"; color: Theme.accentText; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                }
            }
        }

        // ——— Strona ———
        GlassPane {
            id: main
            x: side.width
            width: parent.width - side.width
            height: parent.height
            topRightRadius: win.r; bottomRightRadius: win.r

            Item {
                id: topBar
                width: parent.width; height: win.project && !win.startOverride ? 112 : 64
                z: 5
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }

                Column {
                    visible: !!win.project && !win.startOverride
                    x: 28; y: 16
                    width: parent.width - x - actions.width - 40
                    spacing: 4
                    Row {
                        spacing: 10
                        Text {
                            text: win.project ? win.project.name : ""
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: typeText.implicitWidth + 16; height: 22; radius: 11
                            color: Theme.fill
                            Text { id: typeText; anchors.centerIn: parent; text: win.project ? win.project.typeName : ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium }
                        }
                    }
                    Text {
                        width: parent.width; elide: Text.ElideMiddle
                        text: win.project ? win.project.path : ""
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                    }
                }

                Row {
                    id: actions
                    anchors.right: winButtons.left; anchors.rightMargin: 14
                    y: 16
                    spacing: 8
                    visible: !!win.project && !win.startOverride
                    Pill {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!win.project && !!win.project.url && win.project.current > 0
                        text: "Otwórz stronę"
                        iconPath: LI.link
                        onClicked: Launch.openUrl(win.project.url)
                    }
                    Pill {
                        id: deployButton
                        anchors.verticalCenter: parent.verticalCenter
                        primary: true
                        enabled: !Launch.preparing && !Launch.running && Launch.plan.length === 0
                        text: Launch.preparing ? "Sprawdzam serwer…" : "Wdróż"
                        iconPath: LI.rocket
                        tip: "Pokaże plan zmian do potwierdzenia (Ctrl+Enter)"
                        onClicked: win.deploy()
                    }
                }
                WindowButtons {
                    id: winButtons
                    window: win
                    anchors.right: parent.right; anchors.rightMargin: 16
                    y: 19
                }

                // Zakładki
                Row {
                    visible: !!win.project && !win.startOverride
                    x: 22; anchors.bottom: parent.bottom
                    spacing: 4
                    Repeater {
                        model: win.tabs
                        delegate: HoverButton {
                            id: tabBtn
                            required property var modelData
                            readonly property bool active: win.tab === modelData.id
                            width: tabText.implicitWidth + 24; height: 36; radius: 8
                            onClicked: win.go(modelData.id)
                            Text {
                                id: tabText
                                anchors.centerIn: parent
                                text: tabBtn.modelData.name
                                color: tabBtn.active ? Theme.text : Theme.text2
                                font.family: Theme.font; font.pixelSize: 13; font.weight: tabBtn.active ? Font.DemiBold : Font.Normal
                            }
                            Rectangle {
                                visible: tabBtn.active
                                anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - 18; height: 2.5; radius: 1.25
                                color: Theme.accent
                            }
                        }
                    }
                }
                Rectangle { visible: !!win.project && !win.startOverride; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
            }

            Item {
                id: pageHolder
                y: topBar.height
                width: parent.width; height: parent.height - y
                property real shift: 0
                transform: Translate { x: pageHolder.shift }
                clip: true

                StartPage {
                    anchors.fill: parent
                    visible: !win.project || win.startOverride
                    onAddRequested: folderDialog.open()
                }
                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    active: !!win.project && !win.startOverride
                    sourceComponent: win.tab === "history" ? historyPage : win.tab === "logs" ? logsPage : win.tab === "target" ? targetPage : overviewPage
                }
                Component { id: overviewPage; ProjectPage { project: win.project; app: win } }
                Component { id: historyPage; HistoryPage { project: win.project; app: win } }
                Component { id: logsPage; LogsPage { project: win.project; app: win } }
                Component { id: targetPage; TargetPage { project: win.project; app: win } }
            }
            ParallelAnimation {
                id: pageAnim
                NumberAnimation { target: pageHolder; property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutQuad }
                NumberAnimation { target: pageHolder; property: "shift"; from: 14; to: 0; duration: 240; easing.type: Easing.OutQuint }
            }

            // Komunikat na dole
            Rectangle {
                id: toastBox
                property bool shown: false
                property alias text: toastText.text
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - (shown ? height + 22 : 0)
                opacity: shown ? 1 : 0
                z: 20
                width: Math.min(parent.width - 60, toastText.implicitWidth + 36); height: toastText.height + 22; radius: 20
                color: Theme.dark ? "#ECEEF3" : "#1E2027"
                Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
                Behavior on opacity { NumberAnimation { duration: 160 } }
                Text {
                    id: toastText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.parent.width - 96)
                    wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
                    color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                }
                Timer { id: toastTimer; interval: 4500; onTriggered: toastBox.shown = false }
            }
        }

        // ——— Plan zmian i przebieg wdrożenia ———
        PlanSheet {
            anchors.fill: parent
            radius: win.r
            app: win
            z: 150
        }

        // ——— Pytanie od programu z zewnątrz (np. asystent chce logów) ———
        Item {
            anchors.fill: parent
            visible: !!Launch.ask.token
            z: 200
            Rectangle { anchors.fill: parent; radius: win.r; color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.25) }
            MouseArea { anchors.fill: parent }
            RectangularShadow { anchors.fill: dlg; radius: dlg.radius; blur: 40; offset.y: 14; color: Theme.shadow }
            Rectangle {
                id: dlg
                anchors.centerIn: parent
                width: 430; height: dlgCol.implicitHeight + 44
                radius: 22
                color: Theme.surface
                border.width: 1; border.color: Theme.edge
                Column {
                    id: dlgCol
                    x: 24; y: 22; width: parent.width - 48
                    spacing: 8
                    Row {
                        spacing: 10
                        Rectangle {
                            width: 32; height: 32; radius: 10
                            color: Theme.accentSoft
                            Icon { anchors.centerIn: parent; d: Icons.sparkle; size: 17; stroke: 1.9; color: Theme.accentText }
                        }
                        Text { anchors.verticalCenter: parent.verticalCenter; width: dlgCol.width - 42; wrapMode: Text.Wrap; text: Launch.ask.title || ""; color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold }
                    }
                    Text { width: parent.width; wrapMode: Text.Wrap; text: Launch.ask.text || ""; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.15 }
                    Item { width: 1; height: 10 }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Pill { text: "Nie"; onClicked: Launch.answer(Launch.ask.token, false) }
                        Pill { text: Launch.ask.button || "Tak"; primary: true; onClicked: Launch.answer(Launch.ask.token, true) }
                    }
                }
            }
        }
    }
}
