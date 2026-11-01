pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Browser

// Historia (aster://history): odwiedzone strony pogrupowane po dniach, z wyszukiwaniem.
// Kliknięcie otwiera stronę, środkowy przycisk — w nowej karcie; krzyżyk usuwa wpis.
Item {
    id: hp
    signal open(string url, bool background)

    property int limit: 300
    readonly property var loc: Qt.locale("pl_PL")

    ListModel { id: rows }
    function refresh() {
        const list = Browser.history(search.text, limit);
        rows.clear();
        for (const h of list)
            rows.append({ url: h.url, title: h.title || Urls.pretty(h.url), time: h.time, day: Urls.dayLabel(h.time, loc) });
    }
    Component.onCompleted: refresh()
    Connections { target: Browser; function onHistoryChanged() { refreshTimer.restart(); } }
    Timer { id: refreshTimer; interval: 250; onTriggered: hp.refresh() }

    PageHeader {
        id: header
        title: "Historia"
        PageSearch { id: search; placeholder: "Szukaj w historii"; onTextChanged: { hp.limit = 300; refreshTimer.restart(); } }
        PillButton { text: "Wyczyść dane przeglądania…"; onClicked: hp.open("aster://settings#privacy", false) }
    }

    ListView {
        id: list
        anchors.top: header.bottom; anchors.bottom: parent.bottom
        width: Math.min(860, parent.width - 64)
        x: (parent.width - width) / 2
        clip: true
        model: rows
        boundsBehavior: Flickable.StopAtBounds
        bottomMargin: 40
        section.property: "day"
        section.delegate: Text {
            required property string section
            width: list.width
            topPadding: 18; bottomPadding: 8; leftPadding: 12
            text: section
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
        }
        delegate: Rectangle {
            id: row
            required property string url
            required property string title
            required property real time
            width: list.width; height: 48
            radius: 12
            color: area.containsMouse ? Theme.hover : "transparent"
            Text {
                x: 12; width: 48
                anchors.verticalCenter: parent.verticalCenter
                text: new Date(row.time).toLocaleTimeString(hp.loc, "HH:mm")
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                font.features: { "tnum": 1 }
            }
            Image {
                id: ico
                x: 64; anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18
                source: Urls.favicon(row.url)
                sourceSize: Qt.size(36, 36)
                asynchronous: true
            }
            Row {
                x: 94; width: parent.width - 140
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text {
                    id: titleText
                    width: Math.min(implicitWidth, parent.width * 0.65)
                    text: row.title
                    elide: Text.ElideRight
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                }
                Text {
                    width: parent.width - titleText.width - 10
                    text: Urls.host(row.url)
                    elide: Text.ElideRight
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
            }
            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onClicked: (m) => hp.open(row.url, m.button === Qt.MiddleButton || (m.modifiers & Qt.ControlModifier))
            }
            HoverButton {
                anchors.right: parent.right; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30
                visible: area.containsMouse || hovered
                onClicked: Browser.removeHistory(row.url)
                Icon { anchors.centerIn: parent; d: Icons.close; size: 12; stroke: 2; color: Theme.text2 }
            }
        }
        footer: Item {
            width: list.width
            height: rows.count >= hp.limit ? 64 : (rows.count === 0 ? 220 : 0)
            PillButton {
                anchors.centerIn: parent
                visible: rows.count >= hp.limit
                text: "Pokaż starsze"
                onClicked: { hp.limit += 300; hp.refresh(); }
            }
            Text {
                anchors.centerIn: parent
                visible: rows.count === 0
                text: search.text ? "Nic nie znaleziono" : "Historia jest pusta"
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 15
            }
        }
    }
}
