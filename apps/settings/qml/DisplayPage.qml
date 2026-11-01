pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Settings

// Ekran: układ monitorów (przeciąganie), rozdzielczość, odświeżanie, skalowanie, obrót, monitor główny,
// jasność i nocne światło z harmonogramem i barwą
Page {
    id: dp
    property string selected: Displays.outputs.length ? Displays.outputs[0].name : ""
    readonly property var out: Displays.outputs.find(o => o.name === selected) || Displays.outputs[0] || null
    readonly property var nightMode: { Conf.revision; return Conf.read("kwinrc", ["NightColor"], "Mode", "Automatic"); }
    readonly property int nightTemp: { Conf.revision; return Number(Conf.read("kwinrc", ["NightColor"], "NightTemperature", 4500)); }

    // ——— Układ monitorów ———
    Section {
        visible: Displays.outputs.length > 1
        title: "Monitory"
        footer: "Przeciągnij monitor, żeby ustawić, jak stoją względem siebie. Kliknij, żeby zmienić jego ustawienia."
        Item {
            id: arrange
            width: parent.width; height: 200
            // Skala: wszystkie monitory mieszczą się w polu
            readonly property var bounds: {
                let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
                for (const o of Displays.outputs) {
                    if (!o.enabled) continue;
                    const w = o.width / o.scale, h = o.height / o.scale;
                    x0 = Math.min(x0, o.x); y0 = Math.min(y0, o.y); x1 = Math.max(x1, o.x + w); y1 = Math.max(y1, o.y + h);
                }
                return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) };
            }
            readonly property real k: Math.min((width - 60) / bounds.w, (height - 40) / bounds.h)
            Repeater {
                model: Displays.outputs.filter(o => o.enabled)
                delegate: Rectangle {
                    id: mon
                    required property var modelData
                    readonly property bool sel: modelData.name === dp.selected
                    x: (arrange.width - arrange.bounds.w * arrange.k) / 2 + (modelData.x - arrange.bounds.x) * arrange.k
                    y: (arrange.height - arrange.bounds.h * arrange.k) / 2 + (modelData.y - arrange.bounds.y) * arrange.k
                    width: modelData.width / modelData.scale * arrange.k - 4
                    height: modelData.height / modelData.scale * arrange.k - 4
                    radius: 8
                    color: sel ? Theme.accentSoft : Theme.fill
                    border.width: sel ? 2 : 1
                    border.color: sel ? Theme.accent : Theme.line
                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: mon.modelData.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; visible: mon.modelData.primary; text: "główny"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        drag.target: Displays.outputs.length > 1 ? mon : null
                        cursorShape: Qt.OpenHandCursor
                        onPressed: dp.selected = mon.modelData.name
                        onReleased: {
                            // Pozycja w pikselach ekranu, dociągnięta do sąsiada
                            const nx = Math.round((mon.x - (arrange.width - arrange.bounds.w * arrange.k) / 2) / arrange.k + arrange.bounds.x);
                            const ny = Math.round((mon.y - (arrange.height - arrange.bounds.h * arrange.k) / 2) / arrange.k + arrange.bounds.y);
                            if (Math.abs(nx - mon.modelData.x) > 4 || Math.abs(ny - mon.modelData.y) > 4)
                                Displays.setPosition(mon.modelData.name, nx, ny);
                        }
                    }
                }
            }
        }
    }

    // ——— Wybrany monitor ———
    Section {
        visible: !!dp.out
        title: Displays.outputs.length > 1 && dp.out ? dp.out.label : "Ekran"
        SettingRow {
            visible: Displays.outputs.length > 1
            title: "Używaj tego monitora"
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: !!dp.out && dp.out.enabled; onToggled: on => Displays.setEnabled(dp.out.name, on) }
        }
        SettingRow {
            visible: Displays.outputs.length > 1
            title: "Monitor główny"
            subtitle: "Tu pojawiają się dok, górna wyspa i nowe okna"
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: !!dp.out && dp.out.primary; onToggled: on => { if (on) Displays.setPrimary(dp.out.name); } }
        }
        SettingRow {
            title: "Rozdzielczość"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                readonly property var sizes: {
                    if (!dp.out) return [];
                    const seen = {}, list = [];
                    for (const m of dp.out.modes) {
                        const key = m.width + "×" + m.height;
                        if (seen[key]) continue;
                        seen[key] = true;
                        list.push({ label: key + (list.length === 0 ? " (zalecana)" : ""), value: key });
                    }
                    return list;
                }
                model: sizes
                value: dp.out ? dp.out.width + "×" + dp.out.height : ""
                onPicked: v => {
                    // Najszybsze odświeżanie dla tej rozdzielczości
                    const m = dp.out.modes.find(x => x.width + "×" + x.height === v);
                    if (m) Displays.setMode(dp.out.name, m.id);
                }
            }
        }
        SettingRow {
            title: "Odświeżanie"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: dp.out ? dp.out.modes.filter(m => m.width === dp.out.width && m.height === dp.out.height)
                                .map(m => ({ label: Math.round(m.refresh) + " Hz", value: m.id })) : []
                value: dp.out ? dp.out.modeId : ""
                onPicked: v => Displays.setMode(dp.out.name, v)
            }
        }
        SettingRow {
            title: "Rozmiar wszystkiego na ekranie"
            subtitle: "Większy — wygodniej czytać, mniejszy — więcej miejsca"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: [1, 1.25, 1.5, 1.75, 2, 2.5, 3].map(s => ({ label: Math.round(s * 100) + "%", value: s }))
                value: dp.out ? Math.round(dp.out.scale * 100) / 100 : 1
                onPicked: v => Displays.setScale(dp.out.name, v)
            }
        }
        SettingRow {
            title: "Obrót"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: [{ label: "Bez obrotu", value: "normal" }, { label: "90° w lewo", value: "left" },
                        { label: "90° w prawo", value: "right" }, { label: "Do góry nogami", value: "inverted" }]
                value: dp.out ? dp.out.rotation : "normal"
                onPicked: v => Displays.setRotation(dp.out.name, v)
            }
        }
    }

    // ——— Jasność ———
    Section {
        visible: Displays.brightnessAvailable
        title: "Jasność"
        Item {
            width: parent.width; height: 58
            LevelSlider {
                x: 16; width: parent.width - 32
                anchors.verticalCenter: parent.verticalCenter
                icon: "sun"
                value: Displays.brightness
                onMoved: v => Displays.setBrightness(v)
            }
        }
        SettingRow {
            title: "Przyciemniaj ekran na baterii"
            subtitle: "Ekran zużywa najwięcej prądu"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: { Conf.revision; return Conf.read("powerdevilrc", ["Battery", "Display"], "UseProfileSpecificDisplayBrightness", false); }
                onToggled: on => {
                    Conf.write("powerdevilrc", ["Battery", "Display"], "UseProfileSpecificDisplayBrightness", on);
                    Conf.write("powerdevilrc", ["Battery", "Display"], "DisplayBrightness", 60);
                    Conf.reloadPower();
                }
            }
        }
    }

    // ——— Nocne światło ———
    Section {
        title: "Nocne światło"
        footer: "Ciepłe kolory wieczorem mniej męczą oczy i ułatwiają zaśnięcie."
        SettingRow {
            title: "Nocne światło"
            icon: "moon"; colors: ["#FDBA74", "#EA580C"]
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: System.nightLight; onToggled: on => System.setNightLight(on) }
        }
        SettingRow {
            visible: System.nightLight
            title: "Kiedy"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: [{ label: "Od zachodu do wschodu słońca", value: "Automatic" }, { label: "W wybranych godzinach", value: "Times" }, { label: "Cały czas", value: "Constant" }]
                value: dp.nightMode
                maxWidth: 280
                onPicked: v => { Conf.write("kwinrc", ["NightColor"], "Mode", v); Conf.reloadKWin(); }
            }
        }
        SettingRow {
            visible: System.nightLight && dp.nightMode === "Times"
            title: "Od – do"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: ["1800", "1900", "2000", "2100", "2200", "2300"].map(t => ({ label: t.slice(0, 2) + ":00", value: t }))
                value: { Conf.revision; return String(Conf.read("kwinrc", ["NightColor"], "EveningBeginFixed", "2000")); }
                onPicked: v => { Conf.write("kwinrc", ["NightColor"], "EveningBeginFixed", v); Conf.reloadKWin(); }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "–"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: ["0500", "0600", "0700", "0800", "0900"].map(t => ({ label: t.slice(0, 2) + ":00", value: t }))
                value: { Conf.revision; return String(Conf.read("kwinrc", ["NightColor"], "MorningBeginFixed", "0700")); }
                onPicked: v => { Conf.write("kwinrc", ["NightColor"], "MorningBeginFixed", v); Conf.reloadKWin(); }
            }
        }
        Item {
            visible: System.nightLight
            width: parent.width; height: 70
            Text { x: 16; y: 12; text: "Barwa"; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
            Text { anchors.right: parent.right; anchors.rightMargin: 16; y: 12; text: dp.nightTemp + " K"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
            Rectangle {
                id: tempTrack
                x: 16; y: 40; width: parent.width - 32; height: 12; radius: 6
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#FF8A3D" }
                    GradientStop { position: 1; color: "#FFF4E0" }
                }
                // 2500 K (ciepło) … 6000 K (zimno)
                Rectangle {
                    x: (dp.nightTemp - 2500) / 3500 * (parent.width - width)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20; radius: 10
                    color: "white"; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15)
                }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -8
                    function apply(mx) {
                        const t = Math.round((2500 + Math.max(0, Math.min(1, mx / tempTrack.width)) * 3500) / 100) * 100;
                        Conf.write("kwinrc", ["NightColor"], "NightTemperature", t);
                    }
                    onPressed: m => apply(m.x - 8)
                    onPositionChanged: m => { if (pressed) apply(m.x - 8); }
                    onReleased: Conf.reloadKWin()
                }
            }
        }
    }
}
