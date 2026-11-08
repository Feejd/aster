pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import Aster.Shell
import Aster.Ui

// Pulpit (nad tapetą, pod oknami) — pierwsze, co widać po zalogowaniu:
//  • data i duża, cienka godzina w jednym kolorze,
//  • pod nią widżety w siatce kafelków (bento): kalendarz miesiąca, bateria, teraz gra.
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

    Item {
        id: hero
        x: 44; y: 60
        width: Math.max(timeText.implicitWidth, bento.width)
        height: bento.y + bento.height
        opacity: cw.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            id: dateText
            x: 3
            text: {
                const t = cw.now.toLocaleDateString(cw.loc, "dddd, d MMMM");
                return t.charAt(0).toUpperCase() + t.slice(1);
            }
            color: cw.ink
            font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Medium
        }
        Text {
            id: timeText
            y: dateText.height + 2
            text: cw.now.toLocaleTimeString(cw.loc, "HH:mm")
            color: cw.ink
            font.family: Theme.font
            font.pixelSize: 148
            font.weight: Font.ExtraLight
            font.letterSpacing: -7
            font.features: { "tnum": 1 }
        }

        // ——— Widżety ———
        Row {
            id: bento
            y: timeText.y + timeText.height + 18
            spacing: 12

            // Kalendarz miesiąca
            Card {
                id: calendar
                width: 256; height: 254
                readonly property int year: cw.now.getFullYear()
                readonly property int month: cw.now.getMonth()
                readonly property int today: cw.now.getDate()
                // pierwszy dzień siatki: poniedziałek tygodnia, w którym wypada 1. dzień miesiąca
                readonly property int lead: (new Date(year, month, 1).getDay() + 6) % 7
                readonly property int days: new Date(year, month + 1, 0).getDate()

                Row {
                    x: 20; y: 16
                    spacing: 6
                    Text {
                        text: {
                            const m = cw.loc.standaloneMonthName(calendar.month, Locale.LongFormat);
                            return m.charAt(0).toUpperCase() + m.slice(1);
                        }
                        color: Theme.text
                        font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                    }
                    Text {
                        text: calendar.year
                        color: Theme.text2
                        font.family: Theme.font; font.pixelSize: 16
                    }
                }
                Grid {
                    x: 12; y: 48
                    columns: 7
                    Repeater {
                        model: ["P", "W", "Ś", "C", "P", "S", "N"]
                        delegate: Text {
                            required property string modelData
                            required property int index
                            width: 33; height: 22
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: Theme.text2
                            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium
                        }
                    }
                    Repeater {
                        model: 42
                        delegate: Item {
                            id: cell
                            required property int index
                            readonly property int day: index - calendar.lead + 1
                            readonly property bool inMonth: day >= 1 && day <= calendar.days
                            readonly property bool isToday: day === calendar.today
                            visible: index < Math.ceil((calendar.lead + calendar.days) / 7) * 7
                            width: 33; height: 28
                            Rectangle {
                                anchors.centerIn: parent
                                width: 28; height: 28; radius: 7
                                visible: cell.isToday
                                color: Theme.accent
                            }
                            Text {
                                anchors.centerIn: parent
                                text: cell.inMonth ? cell.day : ""
                                color: cell.isToday ? "white" : cell.index % 7 >= 5 ? Theme.text2 : Theme.text
                                font.family: Theme.font; font.pixelSize: 13
                                font.weight: cell.isToday ? Font.DemiBold : Font.Normal
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }
            }

            // Obok kalendarza tylko to, co teraz coś znaczy: bateria i grająca muzyka
            Column {
                spacing: 12

                // Bateria: pierścień naładowania
                Card {
                    width: 236; height: 121
                    visible: ControlCenter.batteryAvailable
                    Item {
                        id: ring
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        width: 72; height: 72
                        readonly property real level: ControlCenter.battery / 100
                        readonly property color tint: ControlCenter.charging ? "#30D158" : ControlCenter.battery <= 20 ? "#FF453A" : Theme.accent
                        Shape {
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeColor: Theme.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
                                strokeWidth: 7
                                fillColor: "transparent"
                                PathAngleArc { centerX: 36; centerY: 36; radiusX: 31; radiusY: 31; startAngle: 0; sweepAngle: 360 }
                            }
                            ShapePath {
                                strokeColor: ring.tint
                                strokeWidth: 7
                                capStyle: ShapePath.RoundCap
                                fillColor: "transparent"
                                PathAngleArc { centerX: 36; centerY: 36; radiusX: 31; radiusY: 31; startAngle: -90; sweepAngle: 360 * ring.level }
                            }
                        }
                        Icon {
                            anchors.centerIn: parent
                            d: ControlCenter.charging ? Icons.bolt : Icons.battery
                            size: 22; stroke: 2
                            color: Theme.text
                        }
                    }
                    Column {
                        anchors.left: ring.right; anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        Text {
                            text: ControlCenter.battery + "%"
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 28; font.weight: Font.Medium; font.letterSpacing: -0.8
                            font.features: { "tnum": 1 }
                        }
                        Text {
                            text: ControlCenter.charging ? "Ładowanie" : "Bateria"
                            color: Theme.text2
                            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                        }
                    }
                }

                // Teraz gra
                Card {
                    width: 236; height: 121
                    visible: ControlCenter.playerAvailable
                    Rectangle {
                        id: cover
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        width: 72; height: 72; radius: 8
                        color: Theme.accent
                        Image {
                            anchors.fill: parent
                            source: ControlCenter.artUrl
                            fillMode: Image.PreserveAspectCrop
                            visible: status === Image.Ready
                            sourceSize: Qt.size(120, 120)
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
                            text: ControlCenter.playerAvailable ? (ControlCenter.title || ControlCenter.playerName) : "Nic nie gra"
                            color: Theme.text
                            font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: ControlCenter.artist
                            color: Theme.text2
                            font.family: Theme.font; font.pixelSize: 12
                        }
                        Row {
                            topPadding: 6
                            spacing: 4
                            MediaButton { glyph: Icons.prev; onClicked: ControlCenter.previous() }
                            MediaButton { glyph: ControlCenter.playing ? Icons.pause : Icons.play; filled: true; onClicked: ControlCenter.playPause() }
                            MediaButton { glyph: Icons.next; onClicked: ControlCenter.next() }
                        }
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
