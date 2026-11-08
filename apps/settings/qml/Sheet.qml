import QtQuick
import Aster.Ui

// Okienko na środku okna (zmiana hasła, nowe konto, hotspot…): przyciemnione tło, karta z tytułem,
// treścią i przyciskami. Samo przenosi się nad całe okno, więc można je zadeklarować w dowolnej stronie.
Item {
    id: sh
    property string title
    property string subtitle
    property bool shown: false
    property string acceptText: "Zapisz"
    property bool acceptEnabled: true
    property bool danger: false
    default property alias content: body.data
    signal accepted()

    function open() { shown = true; }
    function close() { shown = false; }

    parent: Window.window ? Window.window.contentItem : null
    anchors.fill: parent
    z: 900
    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 90 } }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.32)
        MouseArea { anchors.fill: parent; onClicked: sh.close() }
    }
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 420
        height: col.implicitHeight + 48
        radius: 22
        color: Theme.surface
        border.width: 1; border.color: Theme.edge
        scale: sh.shown ? 1 : 0.95
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
        MouseArea { anchors.fill: parent }
        Keys.onEscapePressed: sh.close()
        Column {
            id: col
            x: 24; y: 24
            width: parent.width - 48
            spacing: 14
            Column {
                width: parent.width
                spacing: 4
                Text { width: parent.width; text: sh.title; wrapMode: Text.Wrap; color: Theme.text; font.family: Theme.font; font.pixelSize: 17; font.weight: Font.DemiBold }
                Text { visible: sh.subtitle !== ""; width: parent.width; text: sh.subtitle; wrapMode: Text.Wrap; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.15 }
            }
            Column { id: body; width: parent.width; spacing: 10 }
            Row {
                anchors.right: parent.right
                spacing: 8
                TextButton { height: 34; text: "Anuluj"; onClicked: sh.close() }
                Rectangle {
                    height: 34; width: okText.implicitWidth + 30; radius: 17
                    opacity: sh.acceptEnabled ? 1 : 0.45
                    color: sh.danger ? (okArea.containsMouse ? "#C42B2B" : "#DC3B3B") : (okArea.containsMouse ? Qt.darker(Theme.accent, 1.1) : Theme.accent)
                    Text { id: okText; anchors.centerIn: parent; text: sh.acceptText; color: "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                    MouseArea { id: okArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (sh.acceptEnabled) { sh.accepted(); sh.close(); } }
                }
            }
        }
    }
}
