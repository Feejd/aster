import QtQuick
import "Icons.js" as I

// Ikona pliku: kolorowa kartka z typem albo folder
Item {
    id: fb
    property var t
    property var file
    property bool small: false

    readonly property bool isDir: file && file.badge === ""

    width: small ? 28 : 60
    height: small ? 34 : 64

    Rectangle {
        visible: !fb.isDir
        anchors.centerIn: parent
        width: fb.small ? 28 : 50; height: fb.small ? 34 : 62
        radius: fb.small ? 5 : 8
        color: fb.file ? Qt.alpha(fb.file.tint, fb.t.dark ? 0.28 : 0.16) : "transparent"
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: fb.small ? 4 : 8
            text: fb.file ? fb.file.badge : ""
            color: fb.file ? (fb.t.dark ? Qt.lighter(fb.file.tint, 1.9) : fb.file.tint) : "black"
            font.pixelSize: fb.small ? 8 : 11
            font.weight: Font.Bold
        }
    }

    Rectangle {
        visible: fb.isDir
        anchors.centerIn: parent
        width: fb.small ? 28 : 60; height: fb.small ? 22 : 46
        radius: 8
        color: Qt.alpha(fb.t.accent, fb.t.dark ? 0.3 : 0.16)
        Icon { anchors.centerIn: parent; d: I.folder; size: fb.small ? 14 : 22; color: fb.t.accentText }
    }
}
