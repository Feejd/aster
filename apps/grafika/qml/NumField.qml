import QtQuick
import Aster.Ui

// Pole liczby z przyciskami − i + (rozmiar czcionki, wymiary strony)
Rectangle {
    id: nf
    property real value: 0
    property real step: 1
    property real from: 1
    property real to: 100000
    property string suffix
    signal edited(real v)

    width: 120
    height: 34
    radius: 10
    color: Theme.fill

    function set(v) { nf.edited(Math.max(nf.from, Math.min(nf.to, v))); }

    HoverButton {
        id: minus
        width: 28; height: parent.height - 6
        x: 3; anchors.verticalCenter: parent.verticalCenter
        radius: 7
        onClicked: nf.set(nf.value - nf.step)
        Icon { anchors.centerIn: parent; d: Icons.minus; size: 14; stroke: 2; color: Theme.text }
    }
    TextInput {
        id: input
        anchors.left: minus.right; anchors.right: plus.left
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: TextInput.AlignHCenter
        text: Math.round(nf.value * 10) / 10 + nf.suffix
        color: Theme.text
        selectByMouse: true
        selectionColor: Theme.accent
        font.family: Theme.font; font.pixelSize: 13; font.features: { "tnum": 1 }
        validator: RegularExpressionValidator { regularExpression: /[0-9]{0,6}([.,][0-9])?\s*[a-z%]*/ }
        onActiveFocusChanged: if (activeFocus) selectAll()
        onAccepted: { nf.set(parseFloat(text.replace(",", "."))); focus = false; }
        onEditingFinished: { const v = parseFloat(text.replace(",", ".")); if (!isNaN(v) && v !== nf.value) nf.set(v); }
        Keys.onUpPressed: nf.set(nf.value + nf.step)
        Keys.onDownPressed: nf.set(nf.value - nf.step)
    }
    HoverButton {
        id: plus
        width: 28; height: parent.height - 6
        anchors.right: parent.right; anchors.rightMargin: 3; anchors.verticalCenter: parent.verticalCenter
        radius: 7
        onClicked: nf.set(nf.value + nf.step)
        Icon { anchors.centerIn: parent; d: Icons.plus; size: 14; stroke: 2; color: Theme.text }
    }
}
