pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Aster.Ui
import Aster.WebApps

// Aplikacje webowe — menedżer. Trzy części:
//  1. „Dodaj stronę”: wpisz adres → podgląd (ikona-kafelek, nazwa, kolor, kategoria) → Zainstaluj
//  2. „Twoje aplikacje”: kliknięcie otwiera, krzyżyk usuwa
//  3. „Polecane”: popularne serwisy instalowane jednym kliknięciem
Window {
    id: win
    property string installUrl

    width: 980 + 2 * m
    height: 720 + 2 * m
    minimumWidth: 640 + 2 * m
    minimumHeight: 480 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: "Aplikacje webowe"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: maxed ? 0 : 24

    property var preview: null              // wynik WebApps.inspect() do pokazania
    property var pending: null              // instalacja z Polecanych: {name, color, category}
    property string busyUrl: ""

    readonly property var installedHosts: WebApps.installed.map(a => a.host)
    function isInstalled(url) { return installedHosts.indexOf(Catalog.host(url)) >= 0; }
    function installedId(url) { const a = WebApps.installed.find(x => x.host === Catalog.host(url)); return a ? a.id : ""; }

    Connections {
        target: WebApps
        function onInspected(info) {
            if (win.pending) {
                // Polecane: nasze nazwa/kolor/kategoria mają pierwszeństwo, reszta ze strony
                const p = win.pending;
                win.pending = null;
                const merged = Object.assign({}, info, { name: p.name, category: p.category });
                if (p.color) merged.themeColor = p.color;
                WebApps.install(merged);
            } else {
                win.preview = Object.assign({ category: "internet" }, info);
                nameEdit.text = info.name;
            }
        }
        function onInstalledApp(id) {
            const a = WebApps.installed.find(x => x.id === id);
            win.busyUrl = "";
            win.preview = null;
            addField.text = "";
            win.toast((a ? a.name : "Aplikacja") + " jest gotowa — znajdziesz ją w Starcie", id);
        }
        function onFailed(message) {
            win.busyUrl = "";
            win.pending = null;
            win.toast(message, "");
        }
    }

    function check() {
        if (!addField.text.trim()) return;
        preview = null;
        pending = null;
        WebApps.inspect(addField.text);
    }
    function installRecommended(app) {
        busyUrl = app.url;
        pending = { name: app.name, color: app.color, category: app.category };
        WebApps.inspect(app.url);
    }

    property string toastAppId: ""
    function toast(text, appId) {
        toastLabel.text = text;
        toastAppId = appId;
        toastTimer.restart();
    }

    Component.onCompleted: {
        effectsTimer.restart();
        if (installUrl) { addField.text = installUrl; check(); }
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

        Item {
            id: titlebar
            width: parent.width; height: 52
            z: 10
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
            TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }
            Row {
                x: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Rectangle {
                    width: 28; height: 28; radius: 8
                    anchors.verticalCenter: parent.verticalCenter
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.accent }
                        GradientStop { position: 1; color: "#8B5CF6" }
                    }
                    Icon { anchors.centerIn: parent; d: Icons.webapp; size: 16; stroke: 2; color: "white" }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Aplikacje webowe"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium
                }
            }
            WindowButtons {
                window: win
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        GlassPane {
            id: pane
            x: 8; y: titlebar.height
            width: parent.width - 16; height: parent.height - y - 8
            radius: Math.max(10, win.r - 8)
        }

        Flickable {
            id: page
            x: pane.x; y: pane.y
            width: pane.width; height: pane.height
            contentHeight: col.height + 60
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: col
                width: Math.min(860, page.width - 64)
                x: (page.width - width) / 2
                y: 14
                spacing: 22

                // ——— Nagłówek i dodawanie ———
                Column {
                    width: parent.width
                    spacing: 8
                    Text {
                        text: "Każda strona może być aplikacją"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 28; font.weight: Font.DemiBold
                        font.letterSpacing: -0.6
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: "Własne okno i ikona w doku, powiadomienia jak z prawdziwego programu, osobne logowanie i żadnych pasków przeglądarki."
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 14
                    }
                }

                Rectangle {
                    width: parent.width; height: 56
                    radius: 14
                    color: Theme.surface
                    border.width: addField.activeFocus ? 1.5 : 1
                    border.color: addField.activeFocus ? Theme.accent : Theme.line
                    Icon { x: 18; anchors.verticalCenter: parent.verticalCenter; d: Icons.globe; size: 18; color: Theme.text2 }
                    TextInput {
                        id: addField
                        anchors.left: parent.left; anchors.leftMargin: 48
                        anchors.right: checkBtn.left; anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 15
                        selectionColor: Theme.accentSoft
                        selectedTextColor: Theme.text
                        clip: true
                        Keys.onReturnPressed: win.check()
                        Keys.onEnterPressed: win.check()
                        Text { visible: !addField.text; text: "Wpisz adres strony, np. notion.so albo poczta.onet.pl"; color: Theme.text2; font: addField.font }
                    }
                    Rectangle {
                        id: checkBtn
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: checkRow.implicitWidth + 28; height: 40; radius: 10
                        color: checkArea.containsMouse ? Qt.darker(Theme.accent, 1.1) : Theme.accent
                        opacity: addField.text.trim() ? 1 : 0.5
                        Row {
                            id: checkRow
                            anchors.centerIn: parent
                            spacing: 8
                            Spinner { anchors.verticalCenter: parent.verticalCenter; visible: WebApps.busy && !win.pending; color: "white" }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Utwórz aplikację"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                        }
                        MouseArea { id: checkArea; anchors.fill: parent; hoverEnabled: true; onClicked: win.check() }
                    }
                }

                // ——— Podgląd przed instalacją ———
                Rectangle {
                    id: previewCard
                    visible: !!win.preview
                    width: parent.width
                    height: visible ? 196 : 0
                    radius: 18
                    color: Theme.surface
                    border.width: 1; border.color: Theme.line
                    opacity: visible ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }

                    // Jak będzie wyglądać okno: ikona na pasku w kolorze aplikacji
                    Rectangle {
                        id: miniWindow
                        x: 20; y: 20
                        width: 220; height: 156; radius: 12
                        color: Theme.pane
                        border.width: 1; border.color: Theme.line
                        clip: true
                        Rectangle {
                            id: miniBar
                            width: parent.width; height: 30
                            topLeftRadius: 12; topRightRadius: 12
                            color: win.preview && win.preview.themeColor ? win.preview.themeColor : Theme.fill
                            Row {
                                x: 10; anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Image { width: 14; height: 14; source: win.preview ? (win.preview.icon || "") : ""; sourceSize: Qt.size(28, 28); smooth: true }
                                Text {
                                    text: nameEdit.text
                                    color: {
                                        const c = miniBar.color;
                                        return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.62 || c.a < 0.5 ? "#16181D" : "white";
                                    }
                                    font.family: Theme.font; font.pixelSize: 11; font.letterSpacing: 0.1; font.weight: Font.Medium
                                }
                            }
                        }
                        Image {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: 15
                            width: 64; height: 64
                            source: win.preview ? (win.preview.icon || "") : ""
                            sourceSize: Qt.size(128, 128)
                            smooth: true; mipmap: true
                        }
                    }

                    Column {
                        x: miniWindow.x + miniWindow.width + 24
                        y: 22
                        width: previewCard.width - x - 22
                        spacing: 10
                        Rectangle {
                            width: parent.width; height: 40; radius: 10
                            color: Theme.fill
                            TextInput {
                                id: nameEdit
                                x: 12; width: parent.width - 24
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.text
                                font.family: Theme.font; font.pixelSize: 17; font.letterSpacing: -0.2; font.weight: Font.DemiBold
                                selectionColor: Theme.accentSoft
                                clip: true
                            }
                        }
                        Text {
                            text: win.preview ? win.preview.host : ""
                            color: Theme.text2
                            font.family: Theme.font; font.pixelSize: 12
                        }
                        Flow {
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: Catalog.categories
                                delegate: Rectangle {
                                    id: chip
                                    required property var modelData
                                    readonly property bool on: !!win.preview && win.preview.category === modelData.id
                                    width: chipText.implicitWidth + 22; height: 28; radius: 14
                                    color: on ? Theme.accentSoft : Theme.fill
                                    border.width: on ? 1 : 0; border.color: Theme.accent
                                    Text { id: chipText; anchors.centerIn: parent; text: chip.modelData.name; color: chip.on ? Theme.accentText : Theme.text; font.family: Theme.font; font.pixelSize: 12 }
                                    MouseArea { anchors.fill: parent; onClicked: win.preview = Object.assign({}, win.preview, { category: chip.modelData.id }) }
                                }
                            }
                        }
                        Row {
                            spacing: 8
                            Rectangle {
                                width: instText.implicitWidth + 30; height: 38; radius: 10
                                color: instArea.containsMouse ? Qt.darker(Theme.accent, 1.1) : Theme.accent
                                Text { id: instText; anchors.centerIn: parent; text: "Zainstaluj"; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                                MouseArea { id: instArea; anchors.fill: parent; hoverEnabled: true; onClicked: WebApps.install(Object.assign({}, win.preview, { name: nameEdit.text })) }
                            }
                            HoverButton {
                                width: 90; height: 38; radius: 10; baseColor: Theme.fill
                                onClicked: win.preview = null
                                Text { anchors.centerIn: parent; text: "Anuluj"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13 }
                            }
                        }
                    }
                }

                // ——— Zainstalowane ———
                Column {
                    width: parent.width
                    spacing: 12
                    visible: WebApps.installed.length > 0
                    Text { text: "Twoje aplikacje"; color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.letterSpacing: -0.2; font.weight: Font.DemiBold }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: WebApps.installed
                            delegate: Item {
                                id: inst
                                required property var modelData
                                width: 112; height: 120
                                Rectangle {
                                    anchors.fill: parent; radius: 16
                                    color: instHover.containsMouse ? Theme.hover : "transparent"
                                }
                                Image {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 12
                                    width: 64; height: 64
                                    source: inst.modelData.icon
                                    sourceSize: Qt.size(128, 128)
                                    smooth: true; mipmap: true
                                    cache: false
                                    scale: instHover.pressed ? 0.94 : 1
                                    Behavior on scale { NumberAnimation { duration: 100 } }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 86; width: parent.width - 10
                                    horizontalAlignment: Text.AlignHCenter
                                    text: inst.modelData.name
                                    elide: Text.ElideRight
                                    color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                                }
                                MouseArea { id: instHover; anchors.fill: parent; hoverEnabled: true; onClicked: WebApps.launch(inst.modelData.id) }
                                Rectangle {
                                    x: 76; y: 4
                                    width: 22; height: 22; radius: 11
                                    visible: instHover.containsMouse || removeArea.containsMouse
                                    color: removeArea.containsMouse ? "#D93B3B" : Theme.surface
                                    border.width: 1; border.color: Theme.line
                                    Icon { anchors.centerIn: parent; d: Icons.close; size: 10; stroke: 2.2; color: removeArea.containsMouse ? "white" : Theme.text2 }
                                    MouseArea { id: removeArea; anchors.fill: parent; hoverEnabled: true; onClicked: WebApps.uninstall(inst.modelData.id) }
                                }
                            }
                        }
                    }
                }

                // ——— Polecane ———
                Column {
                    width: parent.width
                    spacing: 12
                    Text { text: "Polecane"; color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.letterSpacing: -0.2; font.weight: Font.DemiBold }
                    Grid {
                        id: recGrid
                        columns: Math.max(2, Math.floor(col.width / 280))
                        columnSpacing: 10; rowSpacing: 10
                        Repeater {
                            model: Catalog.apps
                            delegate: Rectangle {
                                id: rec
                                required property var modelData
                                required property int index
                                readonly property bool installed: win.isInstalled(modelData.url)
                                readonly property bool busy: win.busyUrl === modelData.url
                                width: (col.width - (recGrid.columns - 1) * 10) / recGrid.columns
                                height: 76
                                radius: 14
                                color: recArea.containsMouse ? Theme.surface : Qt.alpha(Theme.surface, Theme.dark ? 0.5 : 0.7)
                                border.width: 1; border.color: Theme.line
                                opacity: 0
                                Component.onCompleted: recIn.start()
                                SequentialAnimation {
                                    id: recIn
                                    PauseAnimation { duration: Math.min(rec.index, 20) * 18 }
                                    NumberAnimation { target: rec; property: "opacity"; to: 1; duration: 180 }
                                }
                                MouseArea { id: recArea; anchors.fill: parent; hoverEnabled: true }
                                Rectangle {
                                    x: 14; anchors.verticalCenter: parent.verticalCenter
                                    width: 48; height: 48; radius: 12
                                    color: "white"
                                    border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.08)
                                    Image {
                                        anchors.centerIn: parent
                                        width: 30; height: 30
                                        source: Catalog.preview(rec.modelData.url)
                                        sourceSize: Qt.size(64, 64)
                                        asynchronous: true
                                        smooth: true
                                    }
                                }
                                Column {
                                    x: 76; anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - x - getBtn.width - 22
                                    spacing: 2
                                    Text { width: parent.width; text: rec.modelData.name; elide: Text.ElideRight; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Medium }
                                    Text { width: parent.width; text: rec.modelData.desc; elide: Text.ElideRight; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                                }
                                // „Pobierz” → kółko → „Otwórz” (jak w sklepie)
                                Rectangle {
                                    id: getBtn
                                    anchors.right: parent.right; anchors.rightMargin: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: rec.busy ? 30 : getText.implicitWidth + 26
                                    height: 30; radius: 15
                                    color: rec.installed ? Theme.fill : Theme.accentSoft
                                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
                                    Text {
                                        id: getText
                                        anchors.centerIn: parent
                                        visible: !rec.busy
                                        text: rec.installed ? "OTWÓRZ" : "DODAJ"
                                        color: rec.installed ? Theme.text : Theme.accentText
                                        font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                                    }
                                    Spinner { anchors.centerIn: parent; visible: rec.busy; color: Theme.accent }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: !rec.busy && !WebApps.busy
                                        onClicked: rec.installed ? WebApps.launch(win.installedId(rec.modelData.url)) : win.installRecommended(rec.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ——— Komunikat ———
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: toastTimer.running ? 22 : -height
            Behavior on anchors.bottomMargin { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
            width: Math.min(parent.width - 40, toastRow.implicitWidth + 36); height: 44; radius: 22
            color: Theme.text
            Row {
                id: toastRow
                anchors.centerIn: parent
                spacing: 14
                Text { id: toastLabel; anchors.verticalCenter: parent.verticalCenter; color: Theme.surface; font.family: Theme.font; font.pixelSize: 13 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: win.toastAppId !== ""
                    text: "Otwórz"
                    color: Theme.dark ? Theme.accent : "#8FA6FF"
                    font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Bold
                    MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: { toastTimer.stop(); WebApps.launch(win.toastAppId); } }
                }
            }
        }
        Timer { id: toastTimer; interval: 5000 }
    }

    component Spinner: Item {
        id: sp
        property color color: Theme.accent
        width: 16; height: 16
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Qt.alpha(sp.color, 0.25)
        }
        Rectangle {
            width: 4; height: 4; radius: 2
            color: sp.color
            x: sp.width / 2 - 2 + Math.cos(angle) * (sp.width / 2 - 1)
            y: sp.height / 2 - 2 + Math.sin(angle) * (sp.height / 2 - 1)
            property real angle: 0
            NumberAnimation on angle { from: 0; to: Math.PI * 2; duration: 800; loops: Animation.Infinite; running: sp.visible }
        }
    }
}
