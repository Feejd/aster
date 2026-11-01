pragma ComponentBehavior: Bound
import QtQuick
import Aster.Settings

// Język i region: język programów (KDE i aplikacji z tłumaczeniami) oraz formaty dat, liczb i walut
Page {
    id: lp
    readonly property var languages: [
        { label: "Polski", value: "pl" }, { label: "English (US)", value: "en_US" }, { label: "English (UK)", value: "en_GB" },
        { label: "Deutsch", value: "de" }, { label: "Українська", value: "uk" }, { label: "Čeština", value: "cs" },
        { label: "Slovenčina", value: "sk" }, { label: "Español", value: "es" }, { label: "Français", value: "fr" },
        { label: "Italiano", value: "it" }, { label: "Lietuvių", value: "lt" }, { label: "Русский", value: "ru" }
    ]
    readonly property var regions: [
        { label: "Polska", value: "pl_PL.UTF-8" }, { label: "Stany Zjednoczone", value: "en_US.UTF-8" }, { label: "Wielka Brytania", value: "en_GB.UTF-8" },
        { label: "Niemcy", value: "de_DE.UTF-8" }, { label: "Ukraina", value: "uk_UA.UTF-8" }, { label: "Czechy", value: "cs_CZ.UTF-8" },
        { label: "Irlandia", value: "en_IE.UTF-8" }, { label: "Holandia", value: "nl_NL.UTF-8" }, { label: "Francja", value: "fr_FR.UTF-8" },
        { label: "Hiszpania", value: "es_ES.UTF-8" }, { label: "Włochy", value: "it_IT.UTF-8" }, { label: "Norwegia", value: "nb_NO.UTF-8" }
    ]
    readonly property string language: { Conf.revision; return String(Conf.read("plasma-localerc", ["Translations"], "LANGUAGE", "pl")).split(":")[0]; }
    readonly property string region: { Conf.revision; return String(Conf.read("plasma-localerc", ["Formats"], "LANG", "pl_PL.UTF-8")); }
    readonly property var sample: Qt.locale(region.split(".")[0])
    property bool changed: false

    Section {
        title: "Język"
        footer: "Programy Aster mówią na razie po polsku; język zmienia pozostałe programy po ponownym zalogowaniu."
        SettingRow {
            title: "Język systemu"
            icon: "translate"; colors: ["#7DD3FC", "#0284C7"]
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: lp.languages
                value: lp.language
                onPicked: v => { Conf.write("plasma-localerc", ["Translations"], "LANGUAGE", v === "pl" ? "pl" : v + ":pl"); lp.changed = true; }
            }
        }
    }

    Section {
        title: "Region"
        footer: "Tak będą wyglądały daty, godziny, liczby i kwoty."
        SettingRow {
            title: "Formaty"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                model: lp.regions
                value: lp.region
                onPicked: v => {
                    for (const key of ["LANG", "LC_NUMERIC", "LC_TIME", "LC_MONETARY", "LC_MEASUREMENT"])
                        Conf.write("plasma-localerc", ["Formats"], key, v);
                    lp.changed = true;
                }
            }
        }
        SettingRow { title: "Data"; value: new Date().toLocaleDateString(lp.sample, Locale.LongFormat) }
        SettingRow { title: "Godzina"; value: new Date().toLocaleTimeString(lp.sample, Locale.ShortFormat) }
        SettingRow { title: "Liczby"; value: Number(1234567.89).toLocaleString(lp.sample, "f", 2) }
        SettingRow { title: "Waluta"; value: Number(1299.5).toLocaleCurrencyString(lp.sample) }
        SettingRow { title: "Pierwszy dzień tygodnia"; value: lp.sample.dayName(lp.sample.firstDayOfWeek, Locale.LongFormat) }
    }

    Section {
        visible: lp.changed
        SettingRow {
            title: "Zmiany zadziałają po ponownym zalogowaniu"
            icon: "info"
            TextButton { anchors.verticalCenter: parent.verticalCenter; primary: true; text: "Wyloguj"; onClicked: System.run("dbus-send", ["--session", "--dest=org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown.logout"]) }
        }
    }
}
