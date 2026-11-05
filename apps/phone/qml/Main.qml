pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Dialogs
import QtCore
import Aster.Ui
import Aster.Phone

// Telefon Aster (zamiast okien KDE Connect), jak „Łącze z telefonem” w Windows: po lewej urządzenia, po prawej
// wybrany telefon — bateria i zasięg, parowanie z kodem, szybkie akcje (znajdź, wyślij pliki, schowek, pliki telefonu)
// i powiadomienia z telefonu. Pliki upuszczone na okno lecą prosto na telefon.
Window {
    id: win
    width: 1000 + 2 * m
    height: 680 + 2 * m
    minimumWidth: 720 + 2 * m
    minimumHeight: 480 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: "Telefon"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 12

    Settings { id: prefs; property string device }

    // Wybrane urządzenie (zapamiętane) albo pierwsze; „help” — jak dodać telefon
    property string selected: prefs.device
    onSelectedChanged: if (selected !== "help") prefs.device = selected
    readonly property var dev: {
        for (const d of Phone.devices) if (d.id === selected) return d;
        return selected === "help" || Phone.devices.length === 0 ? null : Phone.devices[0];
    }
    function has(plugin) { return dev !== null && dev.plugins.indexOf(plugin) >= 0; }
    readonly property bool usable: dev !== null && dev.paired && dev.reachable

    function status(d) {
        if (d.requestedByPeer) return "Chce się połączyć";
        if (!d.paired) return d.requested ? "Czekam na potwierdzenie…" : "Nie sparowano";
        if (!d.reachable) return "Niedostępny";
        return d.battery >= 0 ? "Połączony · " + d.battery + "%" : "Połączony";
    }
    function typeIcon(t) { return t === "desktop" || t === "laptop" ? "desktop" : "phone"; }

    Connections {
        target: Phone
        function onMessage(text) { win.toast(text); }
    }
    function toast(text) { toastBox.text = text; toastBox.shown = true; toastTimer.restart(); }

    FileDialog {
        id: sendDialog
        title: "Wyślij pliki na telefon"
        fileMode: FileDialog.OpenFiles
        currentFolder: StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
        onAccepted: if (win.dev) Phone.sendFiles(win.dev.id, selectedFiles.map(u => String(u)))
    }

    function runMenu(a) {
        if (!dev) return;
        if (a === "unpair") unpairSheet.shown = true;
        else if (a === "ping") Phone.ping(dev.id);
    }

    // Do testów (ASTER_OPEN): select:id | help | menu | unpair
    function testOpen(what) {
        if (what.startsWith("select:")) selected = what.substring(7);
        else if (what === "help") selected = "help";
        else if (what === "menu") moreBtn.clicked();
        else if (what === "unpair") unpairSheet.shown = true;
    }

    // ——— Okno ———
    function updateEffects() {
        WindowEffects.setBlur(win, Qt.rect(m, m, frame.width, frame.height), r);
        WindowEffects.setInputRegion(win, Qt.rect(Math.max(0, m - 6), Math.max(0, m - 6), frame.width + (maxed ? 0 : 12), frame.height + (maxed ? 0 : 12)));
    }
    Component.onCompleted: effectsTimer.restart()
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

        // ——— Pasek boczny: urządzenia ———
        Item {
            id: side
            width: 270; height: parent.height
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }

            Row {
                x: 22; y: 22
                spacing: 12
                AppIcon { anchors.verticalCenter: parent.verticalCenter; desktopId: "org.aster.phone"; size: 30 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Telefon"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4
                }
            }

            Text {
                x: 24; y: 82
                text: "Urządzenia"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                visible: Phone.devices.length > 0
            }
            ListView {
                id: devList
                x: 12; y: 104
                width: parent.width - 24; height: parent.height - y - footer.height - 12
                spacing: 4
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: Phone.devices
                delegate: HoverButton {
                    id: row
                    required property var modelData
                    readonly property bool current: win.dev !== null && win.dev.id === modelData.id
                    width: devList.width; height: 58; radius: 14
                    baseColor: current ? Theme.accentSoft : "transparent"
                    color: current ? baseColor : hovered ? Theme.hover : baseColor
                    onClicked: win.selected = modelData.id
                    Rectangle {
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        width: 38; height: 38; radius: 11
                        color: row.modelData.paired && row.modelData.reachable ? Theme.accent : Theme.fill
                        Icon {
                            anchors.centerIn: parent
                            d: Icons[win.typeIcon(row.modelData.type)]
                            size: 19; stroke: 1.8
                            color: row.modelData.paired && row.modelData.reachable ? "white" : Theme.text2
                        }
                        Rectangle {
                            visible: row.modelData.requestedByPeer
                            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: -3
                            width: 12; height: 12; radius: 6
                            color: "#F59E0B"; border.width: 2; border.color: Theme.pane
                        }
                    }
                    Column {
                        x: 60; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 70
                        spacing: 2
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: row.modelData.name
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width; elide: Text.ElideRight
                            text: win.status(row.modelData)
                            color: row.modelData.requestedByPeer ? "#D97706" : Theme.text2
                            font.family: Theme.font; font.pixelSize: 12
                        }
                    }
                }
            }

            Column {
                id: footer
                anchors.bottom: parent.bottom; anchors.bottomMargin: 16
                x: 12; width: parent.width - 24
                spacing: 4
                HoverButton {
                    width: parent.width; height: 40; radius: 12
                    baseColor: win.selected === "help" ? Theme.accentSoft : "transparent"
                    color: win.selected === "help" ? baseColor : hovered ? Theme.hover : baseColor
                    onClicked: win.selected = "help"
                    Icon { x: 14; anchors.verticalCenter: parent.verticalCenter; d: Icons.plus; size: 17; stroke: 2; color: Theme.text }
                    Text { x: 42; anchors.verticalCenter: parent.verticalCenter; text: "Dodaj telefon"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                }
                Text {
                    x: 14; width: parent.width - 28
                    elide: Text.ElideRight
                    visible: Phone.selfName !== ""
                    text: "Ten komputer: " + Phone.selfName
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                }
            }
        }

        // ——— Główna część ———
        GlassPane {
            id: content
            x: side.width
            width: parent.width - side.width; height: parent.height
            topRightRadius: win.r; bottomRightRadius: win.r

            Item {
                id: topBar
                width: parent.width; height: 64
                z: 5
                DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
                TapHandler { onDoubleTapped: if (win.maxed) win.showNormal(); else win.showMaximized() }
                WindowButtons {
                    window: win
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Usługa nie działa
            Column {
                anchors.centerIn: parent
                width: Math.min(parent.width - 60, 420)
                spacing: 12
                visible: !Phone.running
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 76; height: 76; radius: 22; color: Theme.fill
                    Icon { anchors.centerIn: parent; d: Icons.phone; size: 36; stroke: 1.6; color: Theme.text2 }
                }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: "Usługa łączenia z telefonem nie działa"
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                    text: "Telefon korzysta z KDE Connect (pakiet kdeconnectd). Spróbuj uruchomić usługę jeszcze raz."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.25
                }
                Btn { anchors.horizontalCenter: parent.horizontalCenter; text: "Uruchom"; icon: "reload"; onClicked: Phone.start() }
            }

            // Jak dodać telefon (też gdy nic nie ma)
            Flickable {
                visible: Phone.running && win.dev === null
                y: topBar.height
                width: parent.width; height: parent.height - y
                contentHeight: helpCol.implicitHeight + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: helpCol
                    x: 40; width: Math.min(parent.width - 80, 560)
                    spacing: 20
                    Text {
                        text: "Połącz telefon z komputerem"
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 24; font.weight: Font.Bold; font.letterSpacing: -0.4
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: "Powiadomienia z telefonu na ekranie komputera, pliki i schowek w obie strony, dzwonek, gdy telefon zginie pod poduszką. Działa z Androidem i iPhone’em w tej samej sieci Wi‑Fi."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 14; lineHeight: 1.3
                    }
                    Repeater {
                        model: [
                            { t: "Zainstaluj na telefonie aplikację KDE Connect", s: "Android: Google Play albo F‑Droid. iPhone: App Store." },
                            { t: "Połącz telefon z tą samą siecią Wi‑Fi co komputer", s: "Albo włącz na telefonie hotspot i podłącz do niego komputer." },
                            { t: "W aplikacji stuknij „" + (Phone.selfName || "ten komputer") + "” i „Sparuj”", s: "Komputer pojawi się na liście sam, po kilku sekundach." },
                            { t: "Potwierdź tutaj", s: "Telefon pojawi się po lewej — sprawdź, czy kody na obu ekranach są takie same, i kliknij „Połącz”." }
                        ]
                        delegate: Row {
                            id: step
                            required property var modelData
                            required property int index
                            spacing: 14
                            width: helpCol.width
                            Rectangle {
                                width: 30; height: 30; radius: 15
                                color: Theme.accentSoft
                                Text { anchors.centerIn: parent; text: step.index + 1; color: Theme.accentText; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Bold }
                            }
                            Column {
                                width: parent.width - 44
                                spacing: 3
                                topPadding: 4
                                Text { width: parent.width; wrapMode: Text.WordWrap; text: step.modelData.t; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
                                Text { width: parent.width; wrapMode: Text.WordWrap; text: step.modelData.s; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.2 }
                            }
                        }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        visible: Phone.devices.length === 0
                        text: "Telefon nie pojawia się? Sprawdź, czy aplikacja jest otwarta i czy oba urządzenia są w tej samej sieci."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
                    }
                }
            }

            // ——— Wybrany telefon ———
            Flickable {
                id: devFlick
                visible: Phone.running && win.dev !== null
                y: 12
                width: parent.width; height: parent.height - y
                contentHeight: devCol.implicitHeight + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: devCol
                    x: 32; width: parent.width - 64
                    spacing: 22

                    // Nagłówek: telefon, nazwa, bateria, zasięg
                    Row {
                        spacing: 22
                        width: parent.width
                        Rectangle {
                            id: phoneArt
                            width: 64; height: 112; radius: 14
                            color: Theme.dark ? "#14161C" : "#1F2330"
                            Rectangle {
                                anchors.fill: parent; anchors.margins: 4
                                radius: 11
                                gradient: Gradient {
                                    GradientStop { position: 0; color: win.usable ? Qt.lighter(Theme.accent, 1.35) : "#4B5262" }
                                    GradientStop { position: 1; color: win.usable ? Theme.accent : "#2E3340" }
                                }
                                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: 5; width: 14; height: 4; radius: 2; color: Qt.rgba(0, 0, 0, 0.45) }
                                Icon { anchors.centerIn: parent; d: Icons.aster; size: 22; stroke: 2; color: Qt.rgba(1, 1, 1, 0.85) }
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - phoneArt.width - 22 - 60
                            spacing: 10
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: win.dev ? win.dev.name : ""
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 26; font.weight: Font.Bold; font.letterSpacing: -0.5
                            }
                            Flow {
                                width: parent.width
                                spacing: 8
                                Pill {
                                    icon: win.dev && win.dev.reachable ? "wifi" : "close"
                                    text: win.dev ? (win.dev.paired ? (win.dev.reachable ? "Połączony" : "Niedostępny — poza siecią albo wyłączony") : win.status(win.dev)) : ""
                                    good: win.usable
                                }
                                Pill {
                                    visible: win.dev !== null && win.dev.battery >= 0 && win.dev.reachable
                                    icon: win.dev && win.dev.charging ? "bolt" : "battery"
                                    text: win.dev ? win.dev.battery + "%" + (win.dev.charging ? " · ładuje się" : "") : ""
                                    warn: win.dev !== null && win.dev.battery >= 0 && win.dev.battery <= 15 && !win.dev.charging
                                }
                                Pill {
                                    visible: win.dev !== null && win.dev.network !== "" && win.dev.reachable
                                    icon: "signal"
                                    text: win.dev ? win.dev.network + (win.dev.strength >= 0 ? " · " + ["brak zasięgu", "słaby zasięg", "średni zasięg", "dobry zasięg", "pełny zasięg"][Math.min(4, win.dev.strength)] : "") : ""
                                }
                            }
                        }
                    }

                    // Prośba o sparowanie z telefonu
                    Card {
                        visible: win.dev !== null && win.dev.requestedByPeer
                        accent: true
                        Column {
                            width: parent.width
                            spacing: 12
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                text: "„" + (win.dev ? win.dev.name : "") + "” chce się połączyć z tym komputerem"
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                            }
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                text: "Połącz tylko, jeśli to Twoje urządzenie i na jego ekranie widać ten sam kod:"
                                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13
                            }
                            Text {
                                visible: text !== ""
                                text: win.dev && win.dev.verification ? win.dev.verification : ""
                                color: Theme.text; font.family: "JetBrains Mono"; font.pixelSize: 24; font.weight: Font.Bold; font.letterSpacing: 2
                            }
                            Row {
                                spacing: 8
                                Btn { primary: true; text: "Połącz"; icon: "check"; onClicked: Phone.accept(win.dev.id) }
                                Btn { text: "Odrzuć"; onClicked: Phone.reject(win.dev.id) }
                            }
                        }
                    }

                    // Niesparowane
                    Card {
                        visible: win.dev !== null && !win.dev.paired && !win.dev.requestedByPeer
                        Column {
                            width: parent.width
                            spacing: 12
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                text: win.dev && win.dev.requested ? "Potwierdź na telefonie" : "Sparuj, żeby zacząć"
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                            }
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                text: win.dev && win.dev.requested
                                      ? "Na telefonie pojawiła się prośba o połączenie. Sprawdź, czy kod jest taki sam: " + (win.dev.verification || "")
                                      : "Po sparowaniu zobaczysz tu powiadomienia z telefonu, a pliki i schowek przejdą w obie strony."
                                color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.2
                            }
                            Btn {
                                primary: !(win.dev && win.dev.requested)
                                enabled: win.dev !== null && win.dev.reachable
                                text: win.dev && win.dev.requested ? "Anuluj" : "Sparuj"
                                onClicked: win.dev.requested ? Phone.reject(win.dev.id) : Phone.pair(win.dev.id)
                            }
                        }
                    }

                    // Szybkie akcje
                    Flow {
                        visible: win.dev !== null && win.dev.paired
                        width: parent.width
                        spacing: 12
                        Tile { icon: "bell"; title: "Znajdź telefon"; sub: "Zadzwoni głośno, nawet wyciszony"; plugin: "findmyphone"; onClicked: Phone.ring(win.dev.id) }
                        Tile { icon: "upload"; title: "Wyślij pliki"; sub: "Albo upuść je na to okno"; plugin: "share"; onClicked: sendDialog.open() }
                        Tile { icon: "paste"; title: "Wyślij schowek"; sub: "Skopiuj tutaj, wklej na telefonie"; plugin: "clipboard"; onClicked: Phone.sendClipboard(win.dev.id) }
                        Tile { icon: "folder"; title: "Pliki telefonu"; sub: "Zdjęcia i pobrane w Plikach"; plugin: "sftp"; onClicked: Phone.browse(win.dev.id) }
                    }

                    // Powiadomienia z telefonu
                    Column {
                        visible: win.dev !== null && win.dev.paired
                        width: parent.width
                        spacing: 10
                        Text {
                            text: "Powiadomienia"
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                        }
                        Text {
                            visible: win.dev !== null && win.dev.notifications.length === 0
                            width: parent.width; wrapMode: Text.WordWrap
                            text: !win.has("notifications") && win.usable
                                  ? "Telefon nie udostępnia powiadomień. W aplikacji KDE Connect na telefonie włącz „Synchronizacja powiadomień” i zezwól na dostęp."
                                  : win.dev && win.dev.reachable ? "Brak nowych powiadomień." : "Pojawią się, gdy telefon będzie w zasięgu."
                            color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.2
                        }
                        Repeater {
                            model: win.dev ? win.dev.notifications : []
                            delegate: Rectangle {
                                id: note
                                required property var modelData
                                width: parent.width
                                height: noteCol.implicitHeight + 26
                                radius: 14
                                color: Theme.surface
                                border.width: 1; border.color: Theme.line
                                Rectangle {
                                    x: 14; y: 14
                                    width: 32; height: 32; radius: 9
                                    color: Theme.fill
                                    Image {
                                        id: noteIcon
                                        anchors.fill: parent; anchors.margins: 4
                                        source: note.modelData.icon
                                        sourceSize.width: 48
                                        fillMode: Image.PreserveAspectFit
                                        visible: status === Image.Ready
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !noteIcon.visible
                                        text: (note.modelData.app || "?").charAt(0).toUpperCase()
                                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold
                                    }
                                }
                                Column {
                                    id: noteCol
                                    x: 58; y: 13
                                    width: parent.width - 58 - 48
                                    spacing: 3
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        text: note.modelData.app
                                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium
                                    }
                                    Text {
                                        width: parent.width; elide: Text.ElideRight
                                        visible: text !== ""
                                        text: note.modelData.title
                                        color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                                    }
                                    Text {
                                        width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                                        visible: text !== ""
                                        text: note.modelData.text
                                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.2
                                    }
                                }
                                HoverButton {
                                    visible: note.modelData.dismissable
                                    anchors.right: parent.right; anchors.rightMargin: 10; y: 10
                                    width: 30; height: 30; radius: 15
                                    baseColor: "transparent"
                                    color: hovered ? Theme.hover : baseColor
                                    onClicked: Phone.dismiss(win.dev.id, note.modelData.id)
                                    Icon { anchors.centerIn: parent; d: Icons.close; size: 14; stroke: 2; color: Theme.text2 }
                                }
                            }
                        }
                    }
                }
            }

            // Więcej (tylko sparowane)
            HoverButton {
                id: moreBtn
                visible: Phone.running && win.dev !== null && win.dev.paired
                anchors.right: parent.right; anchors.rightMargin: 120
                y: 16
                z: 6
                width: 32; height: 32; radius: 16
                baseColor: "transparent"
                color: hovered ? Theme.hover : baseColor
                onClicked: {
                    const p = moreBtn.mapToItem(frame, 0, moreBtn.height + 6);
                    menu.openAt(p.x - 180, p.y, [
                        { label: "Wyślij powiadomienie testowe", icon: "bell", action: "ping" },
                        { separator: true },
                        { label: "Usuń parowanie", icon: "close", action: "unpair", danger: true }
                    ]);
                }
                Icon { anchors.centerIn: parent; d: Icons.more; size: 18; stroke: 2.4; color: Theme.text2 }
            }

            // Upuszczone pliki → telefon
            DropArea {
                anchors.fill: parent
                enabled: win.usable && win.has("share")
                onEntered: (drag) => dropHint.visible = drag.hasUrls
                onExited: dropHint.visible = false
                onDropped: (drop) => {
                    dropHint.visible = false;
                    Phone.sendFiles(win.dev.id, drop.urls.map(u => String(u)));
                }
            }
            Rectangle {
                id: dropHint
                visible: false
                anchors.fill: parent; anchors.margins: 16
                radius: 20
                color: Theme.accentSoft
                border.width: 2; border.color: Theme.accent
                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; d: Icons.upload; size: 40; stroke: 1.8; color: Theme.accentText }
                    Text {
                        text: "Upuść, żeby wysłać na: " + (win.dev ? win.dev.name : "")
                        color: Theme.accentText; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                    }
                }
            }
        }

        // Potwierdzenie usunięcia parowania
        Rectangle {
            id: unpairSheet
            property bool shown: false
            anchors.fill: parent
            radius: win.r
            color: Qt.rgba(0, 0, 0, shown ? 0.3 : 0)
            visible: shown
            z: 200
            MouseArea { anchors.fill: parent; onClicked: unpairSheet.shown = false }
            Rectangle {
                anchors.centerIn: parent
                width: 380; height: sheetCol.implicitHeight + 44
                radius: 20
                color: Theme.pane
                border.width: 1; border.color: Theme.line
                MouseArea { anchors.fill: parent }
                Column {
                    id: sheetCol
                    x: 22; y: 22; width: parent.width - 44
                    spacing: 10
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: "Usunąć parowanie z „" + (win.dev ? win.dev.name : "") + "”?"
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: "Telefon przestanie wysyłać powiadomienia i pliki. Możesz go później sparować jeszcze raz."
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.2
                    }
                    Item { width: 1; height: 6 }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Btn { text: "Anuluj"; onClicked: unpairSheet.shown = false }
                        Btn { primary: true; danger: true; text: "Usuń parowanie"; onClicked: { Phone.unpair(win.dev.id); unpairSheet.shown = false; } }
                    }
                }
            }
        }

        // Komunikat
        Rectangle {
            id: toastBox
            property bool shown: false
            property alias text: toastText.text
            x: side.width + (parent.width - side.width - width) / 2
            y: shown ? 20 : -height - 10
            opacity: shown ? 1 : 0
            z: 300
            width: Math.min(parent.width - side.width - 60, toastText.implicitWidth + 36); height: 40; radius: 20
            color: Theme.dark ? "#ECEEF3" : "#1E2027"
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Text {
                id: toastText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 36)
                elide: Text.ElideRight
                color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
            }
            Timer { id: toastTimer; interval: 5000; onTriggered: toastBox.shown = false }
        }

        ContextMenu {
            id: menu
            onTriggered: (a) => win.runMenu(a)
        }
    }

    // ——— Elementy ———
    component Pill: Rectangle {
        id: pill
        property string icon
        property string text
        property bool good: false
        property bool warn: false
        width: pillRow.implicitWidth + 22; height: 28; radius: 14
        color: warn ? Qt.rgba(0.9, 0.3, 0.3, 0.15) : good ? Theme.accentSoft : Theme.fill
        Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6
            Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons[pill.icon] || ""; size: 14; stroke: 2; color: pill.warn ? Theme.danger : pill.good ? Theme.accentText : Theme.text2 }
            Text { anchors.verticalCenter: parent.verticalCenter; text: pill.text; color: pill.warn ? Theme.danger : pill.good ? Theme.accentText : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
        }
    }

    component Card: Rectangle {
        id: card
        property bool accent: false
        default property alias content: inner.data
        width: parent ? parent.width : 0
        height: inner.childrenRect.height + 36
        radius: 16
        color: accent ? Theme.accentSoft : Theme.surface
        border.width: 1; border.color: accent ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.line
        Item { id: inner; x: 18; y: 18; width: card.width - 36; height: childrenRect.height }
    }

    // Kafelek szybkiej akcji (wyszarzony, gdy telefon niedostępny albo nie ma tej funkcji)
    component Tile: HoverButton {
        id: tile
        property string icon
        property string title
        property string sub
        property string plugin
        enabled: win.usable && win.has(plugin)
        readonly property int cols: devCol.width >= 4 * 170 + 36 ? 4 : 2
        width: Math.floor((devCol.width - (cols - 1) * 12) / cols); height: 104; radius: 16
        baseColor: Theme.surface
        color: hovered && enabled ? Theme.hover : baseColor
        opacity: enabled ? 1 : 0.45
        border.width: 1; border.color: Theme.line
        Rectangle {
            x: 14; y: 14
            width: 34; height: 34; radius: 10
            color: Theme.accentSoft
            Icon { anchors.centerIn: parent; d: Icons[tile.icon] || ""; size: 18; stroke: 1.9; color: Theme.accentText }
        }
        Text {
            x: 14; y: 56; width: parent.width - 28
            elide: Text.ElideRight
            text: tile.title
            color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
        }
        Text {
            x: 14; y: 76; width: parent.width - 28
            elide: Text.ElideRight
            text: tile.sub
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
        }
    }

    component Btn: HoverButton {
        id: btn
        property string text
        property string icon
        property bool primary: false
        property bool danger: false
        width: btnRow.implicitWidth + 30; height: 36; radius: height / 2
        readonly property color tone: danger ? "#DC2626" : Theme.accent
        baseColor: primary ? tone : Theme.fill
        color: !enabled ? baseColor : primary ? (hovered ? Qt.lighter(tone, 1.12) : baseColor) : (hovered ? Theme.hover : baseColor)
        opacity: enabled ? 1 : 0.45
        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 7
            Icon { visible: btn.icon !== ""; anchors.verticalCenter: parent.verticalCenter; d: Icons[btn.icon] || ""; size: 16; stroke: 2; color: btn.primary ? "white" : Theme.text }
            Text { anchors.verticalCenter: parent.verticalCenter; text: btn.text; color: btn.primary ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
        }
    }
}
