pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Settings

// Pulpit i okna: zegar na pulpicie, przyciąganie okien do krawędzi, animacje,
// narożniki ekranu (przegląd okien, pulpit, blokada, Start) i liczba pulpitów
Page {
    id: dp
    function kw(groups, key, def) { Conf.revision; return Conf.read("kwinrc", groups, key, def); }
    function setKw(groups, key, value) { Conf.write("kwinrc", groups, key, value); Conf.reloadKWin(); }

    // Narożniki: kody KWin (ElectricBorder) i nazwy kluczy w [ElectricBorders]
    readonly property var corners: [
        { name: "Lewy górny", key: "TopLeft", code: 7 }, { name: "Prawy górny", key: "TopRight", code: 1 },
        { name: "Lewy dolny", key: "BottomLeft", code: 5 }, { name: "Prawy dolny", key: "BottomRight", code: 3 }
    ]
    readonly property var cornerActions: [
        { label: "Nic", value: "None" }, { label: "Przegląd okien", value: "overview" }, { label: "Pokaż pulpit", value: "ShowDesktop" },
        { label: "Otwórz Start", value: "ApplicationLauncher" }, { label: "Zablokuj ekran", value: "LockScreen" }
    ]
    function overviewCodes() { return String(kw(["Effect-overview"], "BorderActivate", "7")).split(",").filter(s => s !== "" && s !== "9").map(Number); }
    function cornerAction(c) {
        if (overviewCodes().indexOf(c.code) >= 0) return "overview";
        return String(kw(["ElectricBorders"], c.key, "None"));
    }
    function setCorner(c, action) {
        const codes = overviewCodes().filter(x => x !== c.code);
        if (action === "overview") codes.push(c.code);
        Conf.write("kwinrc", ["Effect-overview"], "BorderActivate", codes.length ? codes.join(",") : "9");
        Conf.write("kwinrc", ["ElectricBorders"], c.key, action === "overview" ? "None" : action);
        Conf.reloadKWin();
    }
    readonly property string minimizeEffect: kw(["Plugins"], "magiclampEnabled", false) === true || kw(["Plugins"], "magiclampEnabled", false) === "true" ? "magiclamp"
                                           : kw(["Plugins"], "squashEnabled", true) === false || kw(["Plugins"], "squashEnabled", true) === "false" ? "none" : "squash"

    Section {
        title: "Pulpit"
        SettingRow {
            title: "Zegar i widżety na pulpicie"
            subtitle: "Duża godzina, kalendarz, bateria i muzyka"
            icon: "clock"; colors: ["#FDBA74", "#EA580C"]
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: Config.desktopClock; onToggled: on => Config.desktopClock = on }
        }
        SettingRow {
            title: "Liczba pulpitów"
            subtitle: "Osobne pulpity na różne zajęcia — przełączasz Ctrl + Super + strzałka"
            Segmented {
                anchors.verticalCenter: parent.verticalCenter
                model: [1, 2, 3, 4].map(n => ({ label: String(n), value: n }))
                value: Number(dp.kw(["Desktops"], "Number", 1))
                onPicked: v => { Conf.write("kwinrc", ["Desktops"], "Rows", 1); dp.setKw(["Desktops"], "Number", v); }
            }
        }
    }

    Section {
        title: "Dok"
        SettingRow {
            title: "Chowaj dok, gdy okno go zasłania"
            subtitle: "Wraca po dojechaniu kursorem do dolnej krawędzi ekranu"
            icon: "apps"; colors: ["#A5B4FC", "#4F46E5"]
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: Config.dockAutoHide; onToggled: on => Config.dockAutoHide = on }
        }
    }

    Section {
        title: "Okna"
        footer: "Przeciągnij okno do lewej albo prawej krawędzi, a zajmie pół ekranu; do górnej — cały ekran. Skrótami: Super + strzałki."
        SettingRow {
            title: "Przyciągaj okna do krawędzi"
            icon: "windows"; colors: ["#7DD3FC", "#2563EB"]
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: dp.kw(["Windows"], "ElectricBorderTiling", true) !== false && dp.kw(["Windows"], "ElectricBorderTiling", true) !== "false"
                onToggled: on => { Conf.write("kwinrc", ["Windows"], "ElectricBorderMaximize", on); dp.setKw(["Windows"], "ElectricBorderTiling", on); }
            }
        }
        SettingRow {
            title: "Animacja minimalizowania"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: [{ label: "Wsysanie do doku", value: "magiclamp" }, { label: "Zmniejszanie", value: "squash" }, { label: "Bez animacji", value: "none" }]
                value: dp.minimizeEffect
                onPicked: v => {
                    Conf.write("kwinrc", ["Plugins"], "magiclampEnabled", v === "magiclamp");
                    dp.setKw(["Plugins"], "squashEnabled", v === "squash");
                }
            }
        }
        SettingRow {
            title: "Szybkość animacji"
            Segmented {
                anchors.verticalCenter: parent.verticalCenter
                model: [{ label: "Wolno", value: 1.5 }, { label: "Normalnie", value: 1 }, { label: "Szybko", value: 0.5 }]
                value: { Conf.revision; const f = Number(Conf.read("kdeglobals", ["KDE"], "AnimationDurationFactor", 1)); return f >= 1.25 ? 1.5 : f <= 0.75 && f > 0 ? 0.5 : 1; }
                onPicked: v => { Conf.write("kdeglobals", ["KDE"], "AnimationDurationFactor", v); Conf.notifyGlobals(3); }
            }
        }
    }

    Section {
        title: "Narożniki ekranu"
        footer: "Co się dzieje, gdy kursor dotknie rogu ekranu."
        Repeater {
            model: dp.corners
            delegate: SettingRow {
                id: corner
                required property var modelData
                title: modelData.name
                Dropdown {
                    anchors.verticalCenter: parent.verticalCenter
                    model: dp.cornerActions
                    value: { Conf.revision; return dp.cornerAction(corner.modelData); }
                    onPicked: v => dp.setCorner(corner.modelData, v)
                }
            }
        }
    }
}
