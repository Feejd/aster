import QtQuick
import QtQuick.Effects
import "Icons.js" as I

// „Horyzont”: szklana wyspa u góry ekranu. Zwinięta pokazuje jedną rzecz naraz
// (najbliższe spotkanie, pogoda, powiadomienia, muzyka) i co kilka sekund płynnie ją zmienia.
// Po kliknięciu rozwija się w panel „Dziś”. Dane w prototypie są przykładowe.
// Na co dzień jest schowana za górną krawędzią ekranu: wysuwa się, gdy kursor dotknie
// środka górnej krawędzi (peek) albo gdy przyjdzie powiadomienie (notify()).
Item {
    id: hz
    property var t
    property Item backdrop
    property bool dark: false
    property bool open: false
    signal toggle()

    readonly property var items: [
        { icon: "calendar", color: "#F2B33D", text: "Spotkanie z zespołem · za 2 godz." },
        { icon: "sun", color: "#FF9F1C", text: "12° · słonecznie, wieczorem deszcz" },
        { icon: "bell", color: "#5B7CFF", text: "2 nowe powiadomienia" },
        { icon: "music", color: "#F0524F", text: "Gra: Ulubiona piosenka" }
    ]
    property int shown: 0
    property var note: null              // bieżące powiadomienie (ma pierwszeństwo przed rotacją)
    property var pending: null
    readonly property var cur: note || items[shown]

    // ——— Chowanie ———
    property bool peek: false            // kursor w strefie u góry ekranu
    readonly property bool want: open || peek || hover.hovered || note !== null
    property bool up: false
    onWantChanged: if (want) { hideDelay.stop(); up = true; } else hideDelay.restart()
    Timer { id: hideDelay; interval: 420; onTriggered: hz.up = false }
    property real hideP: up ? 0 : 1      // 0 = widoczna, 1 = schowana
    Behavior on hideP {
        NumberAnimation {
            duration: hz.up ? 260 : 170
            easing.type: hz.up ? Easing.OutBack : Easing.InCubic
            easing.overshoot: 1.1
        }
    }
    readonly property real lift: hideP * (height + 18)
    opacity: 1 - hideP * hideP
    visible: hideP < 0.999
    transform: [
        Scale { origin.x: hz.width / 2; origin.y: 0; xScale: 1 - 0.3 * hz.hideP; yScale: 1 - 0.3 * hz.hideP },
        Translate { y: -hz.lift }
    ]
    HoverHandler { id: hover }

    function notify(icon, color, text) {
        pending = { icon: icon, color: color, text: text };
        tick.restart();
        noteTimer.restart();
        popAnim.restart();
    }
    Timer {
        id: noteTimer; interval: 4600
        onTriggered: { if (hover.hovered) restart(); else tick.restart(); }
    }
    // Przy powiadomieniu wyspa lekko „podskakuje”
    property real pop: 1
    SequentialAnimation {
        id: popAnim
        PauseAnimation { duration: 140 }
        NumberAnimation { target: hz; property: "pop"; to: 1.08; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: hz; property: "pop"; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 }
    }
    scale: pop
    transformOrigin: Item.Top

    width: open ? 560 : pill.implicitWidth + 30
    height: open ? 532 : 40
    readonly property real r: open ? 28 : 20
    Behavior on width { NumberAnimation { duration: 210; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
    Behavior on height { NumberAnimation { duration: 230; easing.type: Easing.OutBack; easing.overshoot: 0.45 } }

    Timer {
        interval: 4200; repeat: true
        running: !hz.open && hz.note === null
        onTriggered: tick.restart()
    }

    RectangularShadow {
        anchors.fill: parent
        radius: hz.r
        blur: hz.open ? 60 : 24
        offset.y: hz.open ? 22 : 6
        color: hz.open ? hz.t.shadow : Qt.rgba(0, 0, 0, hz.dark ? 0.3 : 0.10)
    }
    Glass {
        anchors.fill: parent
        backdrop: hz.backdrop
        sx: hz.x
        sy: hz.y - hz.lift
        radius: hz.r
        tint: hz.open ? hz.t.glass : hz.t.bar
        edge: hz.t.edge
        rim: hz.t.rim
    }

    // ——— Zwinięta: przewijana informacja ———
    Item {
        anchors.fill: parent
        opacity: hz.open ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 110 } }

        Row {
            id: pill
            anchors.centerIn: parent
            spacing: 10

            Item {
                width: 22; height: 22
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    anchors.centerIn: parent
                    width: 22; height: 22; radius: 11
                    color: hz.cur.color
                    opacity: 0.22
                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.8; to: 1.25; duration: 1100; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1.25; to: 0.8; duration: 1100; easing.type: Easing.InOutSine }
                    }
                }
                Icon { id: tickIcon; anchors.centerIn: parent; d: I[hz.cur.icon]; size: 15; stroke: 2; color: hz.cur.color }
            }

            Item {
                id: ticker
                width: tickText.implicitWidth
                height: 22
                clip: true
                anchors.verticalCenter: parent.verticalCenter
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutQuint } }
                Text {
                    id: tickText
                    y: 2
                    text: hz.cur.text
                    color: hz.t.text
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }
        }

        // Stary tekst odjeżdża w górę, nowy wjeżdża od dołu
        SequentialAnimation {
            id: tick
            ParallelAnimation {
                NumberAnimation { target: tickText; property: "y"; to: -14; duration: 120; easing.type: Easing.InCubic }
                NumberAnimation { targets: [tickText, tickIcon]; property: "opacity"; to: 0; duration: 110 }
            }
            ScriptAction { script: {
                if (hz.pending) { hz.note = hz.pending; hz.pending = null; }
                else if (hz.note) hz.note = null;
                else hz.shown = (hz.shown + 1) % hz.items.length;
                tickText.y = 16;
            } }
            ParallelAnimation {
                NumberAnimation { target: tickText; property: "y"; to: 2; duration: 220; easing.type: Easing.OutQuint }
                NumberAnimation { targets: [tickText, tickIcon]; property: "opacity"; to: 1; duration: 160 }
            }
        }

        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: hz.toggle() }
    }

    // ——— Rozwinięta: panel „Dziś” ———
    Item {
        id: today
        anchors.fill: parent
        clip: true
        opacity: hz.open ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: hz.open ? 160 : 80 } }
        property date now: new Date()
        Timer { interval: 30000; repeat: true; running: hz.open; onTriggered: today.now = new Date() }

        Column {
            x: 24; y: 22
            width: 560 - 48
            spacing: 16

            Item {
                width: parent.width; height: 52
                Column {
                    Text {
                        text: today.now.getHours() < 5 ? "Dobranoc" : (today.now.getHours() < 18 ? "Dzień dobry" : "Dobry wieczór")
                        color: hz.t.text; font.pixelSize: 24; font.weight: Font.Bold
                    }
                    Text { text: Qt.locale("pl_PL").toString(today.now, "dddd, d MMMM"); color: hz.t.text2; font.pixelSize: 13 }
                }
                HoverButton {
                    t: hz.t
                    anchors.right: parent.right; anchors.top: parent.top
                    width: 32; height: 32; radius: 16
                    color: hz.t.fill
                    onClicked: hz.toggle()
                    Icon { anchors.centerIn: parent; d: I.close; size: 14; color: hz.t.text2 }
                }
            }

            Row {
                spacing: 12
                // Pogoda
                Rectangle {
                    width: (512 - 12) / 2; height: 136; radius: 20
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0; color: hz.dark ? "#3654D9" : "#5B86FF" }
                        GradientStop { position: 1; color: hz.dark ? "#5A33B8" : "#8C6BF5" }
                    }
                    Text { x: 18; y: 12; text: "Warszawa"; color: Qt.rgba(1, 1, 1, 0.85); font.pixelSize: 13; font.weight: Font.Medium }
                    Text { x: 16; y: 30; text: "12°"; color: "white"; font.pixelSize: 52; font.weight: Font.Light }
                    Icon { x: parent.width - 52; y: 16; d: I.sun; size: 34; stroke: 1.6; color: "#FFD36B" }
                    Text { x: 18; y: 102; text: "Słonecznie · 8° / 14°"; color: Qt.rgba(1, 1, 1, 0.9); font.pixelSize: 13 }
                }
                // Najbliższe wydarzenie
                Rectangle {
                    width: (512 - 12) / 2; height: 136; radius: 20
                    color: hz.t.surface
                    border.width: 1; border.color: hz.t.line
                    Text { x: 18; y: 14; text: "NASTĘPNE"; color: "#E39B12"; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 0.6 }
                    Text { x: 18; y: 34; width: parent.width - 36; text: "Spotkanie z zespołem"; color: hz.t.text; font.pixelSize: 16; font.weight: Font.DemiBold; elide: Text.ElideRight }
                    Text { x: 18; y: 58; text: "16:00 – 17:00 · za 2 godz."; color: hz.t.text2; font.pixelSize: 13 }
                    Rectangle {
                        x: 18; y: 90; width: joinText.implicitWidth + 28; height: 32; radius: 16
                        color: joinArea.containsMouse ? Qt.darker(hz.t.accent, 1.1) : hz.t.accent
                        Text { id: joinText; anchors.centerIn: parent; text: "Dołącz"; color: "white"; font.pixelSize: 13; font.weight: Font.DemiBold }
                        MouseArea { id: joinArea; anchors.fill: parent; hoverEnabled: true }
                    }
                }
            }

            Item {
                width: parent.width; height: 20
                Text { text: "Powiadomienia"; color: hz.t.text; font.pixelSize: 14; font.weight: Font.DemiBold }
                Text { anchors.right: parent.right; text: "Wyczyść"; color: hz.t.accentText; font.pixelSize: 13; font.weight: Font.Medium }
            }

            Repeater {
                model: [
                    { icon: "undo", tint: "#3456E8", title: "Aktualizacja jest gotowa", body: "Wejdzie przy następnym uruchomieniu. Zawsze możesz wrócić do poprzedniej wersji.", when: "teraz" },
                    { icon: "mail", tint: "#C8551F", title: "Poczta · Anna", body: "Przesyłam poprawioną ofertę do akceptacji.", when: "12 min" }
                ]
                delegate: Rectangle {
                    id: note
                    required property var modelData
                    width: 512; height: 64; radius: 16
                    color: hz.t.fill
                    Rectangle {
                        id: noteIcon
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        width: 38; height: 38; radius: 11
                        color: note.modelData.tint
                        Icon { anchors.centerIn: parent; d: I[note.modelData.icon]; size: 18; color: "white" }
                    }
                    Column {
                        anchors.left: noteIcon.right; anchors.leftMargin: 12
                        anchors.right: parent.right; anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Item {
                            width: parent.width; height: 18
                            Text { text: note.modelData.title; color: hz.t.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { anchors.right: parent.right; text: note.modelData.when; color: hz.t.text2; font.pixelSize: 12 }
                        }
                        Text { width: parent.width; text: note.modelData.body; color: hz.t.text2; font.pixelSize: 12; elide: Text.ElideRight }
                    }
                }
            }

            // Teraz gra
            Rectangle {
                width: 512; height: 58; radius: 16
                color: hz.t.fill
                Rectangle {
                    id: cover
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    width: 38; height: 38; radius: 10
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#FF8A6B" }
                        GradientStop { position: 1; color: "#B45CF0" }
                    }
                    Icon { anchors.centerIn: parent; d: I.music; size: 17; color: "white" }
                }
                Column {
                    anchors.left: cover.right; anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Text { text: "Ulubiona piosenka"; color: hz.t.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Rectangle {
                        width: 300; height: 4; radius: 2; color: hz.t.line
                        Rectangle {
                            id: progress
                            height: 4; radius: 2; color: hz.t.accentText
                            width: 300 * 0.35
                            NumberAnimation on width { running: hz.open && playing.on; from: 300 * 0.35; to: 300; duration: 90000 }
                        }
                    }
                }
                HoverButton {
                    id: playing
                    property bool on: true
                    t: hz.t
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36; height: 36; radius: 18
                    color: hz.t.surface
                    onClicked: on = !on
                    Icon { anchors.centerIn: parent; d: playing.on ? "M9 6v12M15 6v12" : "M8 5l11 7-11 7z"; size: 15; stroke: 2.2; color: hz.t.text }
                }
            }
        }
    }
}
