import QtQuick
import QtQuick.Window

// „Horyzont”: szklana wyspa u góry ekranu. Na razie pokazuje datę i godzinę;
// powiadomienia i panel „Dziś” z prototypu dojdą w kolejnych krokach.
Window {
    id: hz
    color: "transparent"
    visible: false
    width: 460
    height: 64

    Component.onCompleted: {
        Platform.makeLayer(hz, "top", 1, 0, "none", "aster-horizon");
        visible = true;
        blurTimer.start();
    }

    property date now: new Date()
    Timer { interval: 1000; repeat: true; running: true; onTriggered: hz.now = new Date() }

    Island {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        y: 12
        width: label.implicitWidth + 40
        height: 40
        radius: 20
        onWidthChanged: blurTimer.restart()

        Text {
            id: label
            anchors.centerIn: parent
            text: hz.now.toLocaleDateString(Qt.locale("pl_PL"), "dddd, d MMMM") + "  ·  " + hz.now.toLocaleTimeString(Qt.locale("pl_PL"), "HH:mm")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }

    Timer {
        id: blurTimer
        interval: 50
        onTriggered: Platform.setBlur(hz, [{ x: pill.x, y: pill.y, w: pill.width, h: pill.height, r: pill.radius }])
    }
}
