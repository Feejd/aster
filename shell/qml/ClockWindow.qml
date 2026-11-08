pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import Aster.Shell
import Aster.Ui

// Pulpit (nad tapetą, pod oknami) — pierwsze, co widać po zalogowaniu:
//  • na środku u góry data i duża, lekka godzina,
//  • pod nią pasek widżetów: bieżący tydzień, a bateria i muzyka tylko wtedy, gdy mają coś do pokazania.
// Kliknięcia trafiają tylko w widżety; reszta pulpitu przepuszcza je dalej.
// Ustawienia → Pulpit i dok → „Zegar na pulpicie” chowa całość.
Window {
    id: cw
    property bool followsPrimary: true   // po zmianie głównego ekranu main.cpp przenosi okno
    color: "transparent"
    title: "Zegar"
    visible: false
    width: Screen.width
    height: Screen.height

    Component.onCompleted: {
        Platform.makeLayer(cw, "bottom", 1 | 2 | 4 | 8, -1, "none", "aster-clock");
        visible = true;
        regionTimer.start();
    }

    property date now: new Date()
    Timer { interval: 1000; repeat: true; running: true; onTriggered: cw.now = new Date() }
    readonly property var loc: Qt.locale("pl_PL")
    readonly property bool shown: Config.desktopClock
    onShownChanged: regionTimer.restart()
    readonly property color ink: Theme.dark ? "white" : Qt.rgba(0.08, 0.09, 0.13, 1)

    // Data, godzina i pasek widżetów na środku, w górnej części ekranu
    Item {
        id: hero
        x: Math.round((cw.width - width) / 2)
        y: Math.round(cw.height * 0.12)
        width: Math.max(timeText.implicitWidth, bento.width)
        height: bento.y + bento.height
        opacity: cw.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            id: dateText
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
                const t = cw.now.toLocaleDateString(cw.loc, "dddd, d MMMM");
                return t.charAt(0).toUpperCase() + t.slice(1);
            }
            color: cw.ink
            opacity: 0.85
            font.family: Theme.font; font.pixelSize: 18; font.weight: Font.Medium
        }
        Text {
            id: timeText
            anchors.horizontalCenter: parent.horizontalCenter
            y: dateText.height - 6
            text: cw.now.toLocaleTimeString(cw.loc, "HH:mm")
            color: cw.ink
            font.family: Theme.font
            font.pixelSize: 150
            font.weight: Font.Light
            font.letterSpacing: -6
            font.features: { "tnum": 1 }
            font.variableAxes: { "opsz": 32 }   // wersja „Display”: ciaśniej i smuklej przy dużych rozmiarach
        }

        // ——— Widżety ———
        Row {
            id: bento
            anchors.horizontalCenter: parent.horizontalCenter
            y: timeText.y + timeText.height + 6
            spacing: 12

            // Tydzień: dziś wyróżnione, reszta przygaszona
            Card {
                id: week
                width: 7 * 52 + 24; height: 92
                readonly property var days: {
                    const out = [];
                    const d = new Date(cw.now);
                    const shift = (d.getDay() + 6) % 7;
                    for (let i = 0; i < 7; ++i) {
                        const day = new Date(d.getFullYear(), d.getMonth(), d.getDate() - shift + i);
                        out.push({ n: day.getDate(), label: ["Pn", "Wt", "Śr", "Cz", "Pt", "So", "Nd"][i], today: i === shift, weekend: i >= 5 });
                    }
                    return out;
                }
                Row {
                    anchors.centerIn: parent
                    Repeater {
                        model: week.days
                        delegate: Item {
                            id: dayItem
                            required property var modelData
                            width: 52; height: 66
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: dayItem.modelData.label
                                color: dayItem.modelData.today ? Theme.accentText : Theme.text2
                                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 24
                                width: 38; height: 38; radius: 19
                                color: dayItem.modelData.today ? Theme.accent : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: dayItem.modelData.n
                                    color: dayItem.modelData.today ? "white" : dayItem.modelData.weekend ? Theme.text2 : Theme.text
                                    font.family: Theme.font; font.pixelSize: 17
                                    font.weight: dayItem.modelData.today ? Font.DemiBold : Font.Normal
                                    font.features: { "tnum": 1 }
                                }
                            }
                        }
                    }
                }
            }

            // Bateria (tylko na laptopie)
            Card {
                width: 92; height: 92
                visible: ControlCenter.batteryAvailable
                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        d: ControlCenter.charging ? Icons.bolt : Icons.battery
                        size: 20; stroke: 2
                        color: ControlCenter.charging ? "#30D158" : ControlCenter.battery <= 20 ? "#FF453A" : Theme.text
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ControlCenter.battery + "%"
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 18; font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                    }
                }
            }

            // Teraz gra (tylko gdy coś gra)
            Card {
                width: 300; height: 92
                visible: ControlCenter.playerAvailable
                Rectangle {
                    id: cover
                    x: 14; anchors.verticalCenter: parent.verticalCenter
                    width: 64; height: 64; radius: 16
                    color: Theme.accent
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: ControlCenter.artUrl
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                        sourceSize: Qt.size(128, 128)
                    }
                    Icon { anchors.centerIn: parent; visible: ControlCenter.artUrl === ""; d: Icons.music; size: 24; stroke: 2; color: "white" }
                }
                Column {
                    anchors.left: cover.right; anchors.leftMargin: 12
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: ControlCenter.title || ControlCenter.playerName
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: ControlCenter.artist
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 13
                    }
                    Row {
                        topPadding: 4
                        spacing: 4
                        MediaButton { glyph: Icons.prev; onClicked: ControlCenter.previous() }
                        MediaButton { glyph: ControlCenter.playing ? Icons.pause : Icons.play; filled: true; onClicked: ControlCenter.playPause() }
                        MediaButton { glyph: Icons.next; onClicked: ControlCenter.next() }
                    }
                }
            }
        }
    }

    // Kafelek widżetu: ta sama matowa powierzchnia co panele
    component Card: Island {
        id: card
        readonly property bool isCard: true
        onVisibleChanged: regionTimer.restart()
        radius: 26
        shadowStrength: 0.45
    }

    component MediaButton: Rectangle {
        id: mb
        property string glyph
        property bool filled: false
        signal clicked()
        width: 30; height: 30; radius: 15
        color: mbArea.containsMouse ? Theme.hover : "transparent"
        Icon {
            anchors.centerIn: parent
            d: mb.glyph; size: 16; stroke: 2
            color: Theme.text
            fill: mb.filled ? Theme.text : "transparent"
        }
        MouseArea { id: mbArea; anchors.fill: parent; hoverEnabled: true; onClicked: mb.clicked() }
    }

    // Rozmycie pod widżetami; kliknięcia tylko w nie (gdy są widoczne)
    function cardRects() {
        const out = [];
        const walk = (it) => {
            for (const c of it.children) {
                if (c.isCard === true) {
                    if (!c.visible) continue;
                    const p = c.mapToItem(null, 0, 0);
                    out.push({ x: p.x, y: p.y, w: c.width, h: c.height, r: c.radius });
                } else walk(c);
            }
        };
        walk(bento);
        return out;
    }
    Timer {
        id: regionTimer
        interval: 200
        onTriggered: {
            const r = cw.shown ? cw.cardRects() : [];
            Platform.setBlur(cw, r);
            Platform.setInputRegion(cw, r.length ? r : [{ x: 0, y: 0, w: 1, h: 1, r: 0 }]);
        }
    }
}
