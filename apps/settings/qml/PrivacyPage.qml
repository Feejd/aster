import QtQuick
import Aster.Settings

// Prywatność i bezpieczeństwo: blokada ekranu, zapora sieciowa, historia ostatnich plików
Page {
    id: pv
    function lock(key, def) { Conf.revision; return Conf.read("kscreenlockerrc", ["Daemon"], key, def); }
    Component.onCompleted: System.refreshSecurity()

    Section {
        title: "Blokada ekranu"
        footer: "Zablokować ekran od razu możesz skrótem Super + L."
        SettingRow {
            title: "Blokuj automatycznie"
            icon: "lock"; colors: ["#A5B4FC", "#4F46E5"]
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: [{ label: "Po 1 minucie", value: 1 }, { label: "Po 5 minutach", value: 5 }, { label: "Po 10 minutach", value: 10 },
                        { label: "Po 15 minutach", value: 15 }, { label: "Po 30 minutach", value: 30 }, { label: "Nigdy", value: 0 }]
                value: pv.lock("Autolock", true) === false ? 0 : Number(pv.lock("Timeout", 5))
                onPicked: v => {
                    Conf.write("kscreenlockerrc", ["Daemon"], "Autolock", v > 0);
                    if (v > 0) Conf.write("kscreenlockerrc", ["Daemon"], "Timeout", v);
                }
            }
        }
        SettingRow {
            title: "Wymagaj hasła po wybudzeniu"
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: pv.lock("LockOnResume", true); onToggled: on => Conf.write("kscreenlockerrc", ["Daemon"], "LockOnResume", on) }
        }
        SettingRow {
            title: "Czas na powrót bez hasła"
            subtitle: "Ruch myszą tuż po zablokowaniu odblokowuje bez hasła"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: [{ label: "Brak", value: 0 }, { label: "5 sekund", value: 5 }, { label: "30 sekund", value: 30 }, { label: "1 minuta", value: 60 }]
                value: Number(pv.lock("LockGrace", 5))
                onPicked: v => Conf.write("kscreenlockerrc", ["Daemon"], "LockGrace", v)
            }
        }
    }

    Section {
        visible: System.firewall >= 0
        title: "Zapora sieciowa"
        footer: "Zapora blokuje połączenia przychodzące z sieci, o które nie prosiłeś. Najlepiej, żeby zawsze była włączona."
        SettingRow {
            title: "Zapora"
            subtitle: System.firewall === 1 ? "Chroni komputer" : "Wyłączona — komputer jest mniej chroniony"
            icon: "shield"; colors: System.firewall === 1 ? ["#86EFAC", "#16A34A"] : ["#FCA5A5", "#DC2626"]
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: System.firewall === 1; onToggled: on => System.setFirewall(on) }
        }
    }

    Section {
        title: "Historia"
        SettingRow {
            title: "Zapamiętuj ostatnio otwierane pliki"
            subtitle: "Do szybkiego powrotu w Plikach i w Starcie"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: { Conf.revision; return Conf.read("kdeglobals", ["RecentDocuments"], "UseRecent", true); }
                onToggled: on => { Conf.write("kdeglobals", ["RecentDocuments"], "UseRecent", on); if (!on) System.clearRecentFiles(); }
            }
        }
        SettingRow {
            title: "Wyczyść historię plików"
            TextButton { anchors.verticalCenter: parent.verticalCenter; text: "Wyczyść"; onClicked: System.clearRecentFiles() }
        }
    }
}
