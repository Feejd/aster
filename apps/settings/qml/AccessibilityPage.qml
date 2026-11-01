import QtQuick
import Aster.Settings

// Dostępność: lupa, kursor, mniej ruchu, czytnik ekranu, lepkie klawisze, dźwięk w mono
Page {
    id: acc
    function kwinPlugin(name, def) { Conf.revision; return Conf.read("kwinrc", ["Plugins"], name + "Enabled", def); }
    function setKwinPlugin(name, on) { Conf.write("kwinrc", ["Plugins"], name + "Enabled", on); Conf.reloadKWin(); }

    Section {
        title: "Wzrok"
        SettingRow {
            title: "Lupa ekranowa"
            subtitle: "Powiększanie: Super + =, pomniejszanie: Super + −"
            icon: "search"; colors: ["#7DD3FC", "#2563EB"]
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: acc.kwinPlugin("zoom", true); onToggled: on => acc.setKwinPlugin("zoom", on) }
        }
        SettingRow {
            title: "Czytnik ekranu"
            subtitle: "Orca czyta na głos to, co jest na ekranie"
            icon: "volume"; colors: ["#86EFAC", "#16A34A"]
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: { Conf.revision; return Conf.read("kaccessrc", ["ScreenReader"], "Enabled", false); }
                onToggled: on => Conf.write("kaccessrc", ["ScreenReader"], "Enabled", on)
            }
        }
        SettingRow {
            title: "Rozmiar kursora"
            icon: "cursor"; colors: ["#C4B5FD", "#7C3AED"]
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: [{ label: "Zwykły", value: 24 }, { label: "Duży", value: 32 }, { label: "Bardzo duży", value: 48 }, { label: "Ogromny", value: 64 }]
                value: { Conf.revision; return Number(Conf.read("kcminputrc", ["Mouse"], "cursorSize", 24)); }
                onPicked: v => { Conf.write("kcminputrc", ["Mouse"], "cursorSize", v); Conf.reloadKWin(); }
            }
        }
        SettingRow {
            title: "Odwróć kolory"
            subtitle: "Włączanie i wyłączanie: Super + Ctrl + I"
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: acc.kwinPlugin("invert", false); onToggled: on => acc.setKwinPlugin("invert", on) }
        }
    }

    Section {
        title: "Ruch"
        SettingRow {
            title: "Ogranicz animacje"
            subtitle: "Okna i menu pojawiają się od razu, bez przesuwania i powiększania"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: { Conf.revision; return Number(Conf.read("kdeglobals", ["KDE"], "AnimationDurationFactor", 1)) === 0; }
                onToggled: on => { Conf.write("kdeglobals", ["KDE"], "AnimationDurationFactor", on ? 0 : 1); Conf.notifyGlobals(3); }
            }
        }
    }

    Section {
        title: "Klawiatura"
        SettingRow {
            title: "Lepkie klawisze"
            subtitle: "Shift, Ctrl i Alt można naciskać po kolei zamiast razem"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: { Conf.revision; return Conf.read("kaccessrc", ["Keyboard"], "StickyKeys", false); }
                onToggled: on => Conf.write("kaccessrc", ["Keyboard"], "StickyKeys", on)
            }
        }
        SettingRow {
            title: "Ignoruj przypadkowe powtórzenia"
            subtitle: "Klawisz naciśnięty dwa razy szybko liczy się raz"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: { Conf.revision; return Conf.read("kaccessrc", ["Keyboard"], "BounceKeys", false); }
                onToggled: on => Conf.write("kaccessrc", ["Keyboard"], "BounceKeys", on)
            }
        }
    }

    Section {
        title: "Słuch"
        SettingRow {
            title: "Błysk ekranu przy dźwięku systemowym"
            subtitle: "Zamiast albo oprócz sygnału dźwiękowego"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: { Conf.revision; return Conf.read("kaccessrc", ["Bell"], "VisibleBell", false); }
                onToggled: on => Conf.write("kaccessrc", ["Bell"], "VisibleBell", on)
            }
        }
    }
}
