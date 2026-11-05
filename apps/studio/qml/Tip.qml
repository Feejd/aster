import QtQuick
import Aster.Ui

// Dymek z podpowiedzią nad elementem (pojawia się po chwili)
Rectangle {
    id: tip
    property bool shown: false
    property string text
    property bool below: false
    anchors.horizontalCenter: parent.horizontalCenter
    y: below ? parent.height + 8 : -height - 8
    z: 100
    width: tipText.implicitWidth + 18; height: 26; radius: 7
    color: Theme.text
    visible: opacity > 0
    opacity: shown && delay.done ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 100 } }
    onShownChanged: { delay.done = false; if (shown) delay.restart(); }
    Timer { id: delay; property bool done: false; interval: 450; onTriggered: done = true }
    Text { id: tipText; anchors.centerIn: parent; text: tip.text; color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 12 }
}
