pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Settings

// Data i czas: czas z internetu albo ręcznie, strefa czasowa z wyszukiwarką, format godziny
Page {
    id: dt
    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: dt.now = new Date() }
    readonly property var loc: Qt.locale("pl_PL")

    Item {
        width: parent.width; height: 120
        Column {
            anchors.centerIn: parent
            spacing: 2
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: dt.now.toLocaleTimeString(dt.loc, "HH:mm:ss"); color: Theme.text; font.family: Theme.font; font.pixelSize: 44; font.weight: Font.DemiBold; font.letterSpacing: -1.2; font.features: { "tnum": 1 } }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: dt.now.toLocaleDateString(dt.loc, "dddd, d MMMM yyyy"); color: Theme.text2; font.family: Theme.font; font.pixelSize: 14 }
        }
    }

    Section {
        footer: DateTime.ntp ? "Zegar sam się poprawia, gdy komputer ma internet — także po zmianie czasu na letni." : ""
        SettingRow {
            title: "Ustawiaj czas automatycznie"
            icon: "clock"; colors: ["#FDBA74", "#EA580C"]
            Toggle { anchors.verticalCenter: parent.verticalCenter; checked: DateTime.ntp; enabled: DateTime.canNtp; onToggled: on => DateTime.setNtp(on) }
        }
        SettingRow {
            visible: !DateTime.ntp
            title: "Data i godzina"
            TextButton { anchors.verticalCenter: parent.verticalCenter; text: "Zmień…"; onClicked: { dateField.text = dt.now.toLocaleDateString(dt.loc, "dd.MM.yyyy"); timeField.text = dt.now.toLocaleTimeString(dt.loc, "HH:mm"); timeSheet.open(); } }
        }
        SettingRow {
            title: "Strefa czasowa"
            Dropdown {
                anchors.verticalCenter: parent.verticalCenter
                maxWidth: 300
                model: DateTime.timezones.map(z => ({ label: z.city + " (" + z.region + ")", detail: z.offset, value: z.id }))
                value: DateTime.timezone
                onPicked: v => DateTime.setTimezone(v)
            }
        }
    }

    Sheet {
        id: timeSheet
        title: "Ustaw datę i godzinę"
        subtitle: "Data w formacie dd.mm.rrrr, godzina gg:mm"
        acceptText: "Ustaw"
        Field { id: dateField; placeholder: "01.11.2026" }
        Field { id: timeField; placeholder: "13:30" }
        onAccepted: {
            const d = dateField.text.split("."), t = timeField.text.split(":");
            const when = new Date(Number(d[2]), Number(d[1]) - 1, Number(d[0]), Number(t[0]), Number(t[1] || 0));
            if (!isNaN(when.getTime())) DateTime.setTime(when);
        }
    }
}
