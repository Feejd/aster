pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Grafika

// Wybór czcionki z zainstalowanych w systemie — każda nazwa napisana swoją czcionką, z wyszukiwaniem
Popover {
    id: fp
    property var callback: null
    property string value
    cardWidth: 280
    cardHeight: 420

    function open(item, family, fn) {
        callback = fn;
        value = family;
        search.text = "";
        openAt(item, "left");
        search.forceActiveFocus();
        const i = Library.fonts.indexOf(family);
        if (i >= 0) list.positionViewAtIndex(i, ListView.Center);
    }

    Rectangle {
        width: parent.width; height: 36; radius: 10
        color: Theme.fill
        Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; d: Icons.search; size: 15; color: Theme.text2 }
        TextInput {
            id: search
            x: 34; width: parent.width - 44
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 13
            Keys.onEscapePressed: fp.close()
            Text { visible: !search.text; text: "Szukaj czcionki"; color: Theme.text2; font: search.font }
        }
    }
    ListView {
        id: list
        y: 46
        width: parent.width; height: parent.height - 46
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: search.text === "" ? Library.fonts : Library.fonts.filter(f => f.toLowerCase().indexOf(search.text.toLowerCase()) >= 0)
        delegate: HoverButton {
            id: row
            required property string modelData
            width: list.width; height: 38; radius: 8
            baseColor: modelData === fp.value ? Theme.accentSoft : "transparent"
            color: modelData === fp.value ? baseColor : hovered ? Theme.hover : baseColor
            onClicked: { if (fp.callback) fp.callback(row.modelData); fp.close(); }
            Text {
                x: 10; width: parent.width - 20
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: row.modelData
                color: Theme.text
                font.family: row.modelData; font.pixelSize: 17
            }
        }
    }
}
