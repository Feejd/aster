pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Grafika

// Wybór koloru: gotowe barwy, kolory już użyte w projekcie, pole jasności i nasycenia, odcień, zapis szesnastkowy.
// open(item, kolor, brakDozwolony, funkcja(kolor, koniec)) — funkcja dostaje "" dla „brak”.
Popover {
    id: cp
    required property Project project
    property var callback: null
    property bool allowNone: false
    property real hue: 0
    property real sat: 0
    property real val: 1
    property string value: "#000000"
    cardWidth: 268

    readonly property var swatches: [
        "#000000", "#3D4048", "#8A8F99", "#D5D8DE", "#FFFFFF", "#FFF4E0",
        "#E53935", "#FF7043", "#FFB300", "#FDD835", "#7CB342", "#2E7D32",
        "#00ACC1", "#1E88E5", "#3949AB", "#7E57C2", "#D81B60", "#F48FB1",
        "#5D4037", "#A1887F", "#004D40", "#0D47A1", "#1A237E", "#311B92"
    ]

    function open(item, color, none, fn, side) {
        callback = fn;
        allowNone = !!none;
        setFrom(color || "#000000", false);
        openAt(item, side);
    }
    function setFrom(c, notify) {
        value = c === "" ? "" : String(c);
        if (c !== "") {
            const q = Qt.color(c);
            if (q.hsvSaturation > 0.001) hue = Math.max(0, q.hsvHue);
            sat = q.hsvSaturation;
            val = q.hsvValue;
        }
        if (notify && callback) callback(value, true);
    }
    function fromHsv(done) {
        value = Qt.hsva(hue, sat, val, 1).toString();
        if (callback) callback(value, done);
    }

    Column {
        width: parent.width
        spacing: 12

        Grid {
            columns: 6
            spacing: 8
            Repeater {
                model: cp.swatches
                delegate: Rectangle {
                    id: sw
                    required property string modelData
                    width: 32; height: 32; radius: 16
                    color: modelData
                    border.width: cp.value.toLowerCase() === modelData.toLowerCase() ? 2.5 : 1
                    border.color: cp.value.toLowerCase() === modelData.toLowerCase() ? Theme.accent : Qt.rgba(0, 0, 0, 0.14)
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: cp.setFrom(sw.modelData, true) }
                }
            }
        }

        Text {
            visible: cp.project.colors.length > 0
            text: "W tym projekcie"
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
        }
        Flow {
            visible: cp.project.colors.length > 0 || cp.allowNone
            width: parent.width
            spacing: 8
            Rectangle {
                visible: cp.allowNone
                width: 32; height: 32; radius: 16
                color: "white"
                border.width: cp.value === "" ? 2.5 : 1
                border.color: cp.value === "" ? Theme.accent : Qt.rgba(0, 0, 0, 0.14)
                Rectangle { anchors.centerIn: parent; width: 2; height: 26; rotation: 45; color: "#E53935" }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: cp.setFrom("", true) }
            }
            Repeater {
                model: cp.project.colors
                delegate: Rectangle {
                    id: used
                    required property string modelData
                    width: 32; height: 32; radius: 16
                    color: modelData
                    border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.14)
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: cp.setFrom(used.modelData, true) }
                }
            }
        }

        // Nasycenie (w poziomie) i jasność (w pionie)
        Rectangle {
            id: sv
            width: parent.width; height: 140; radius: 10
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "white" }
                GradientStop { position: 1; color: Qt.hsva(cp.hue, 1, 1, 1) }
            }
            Rectangle {
                anchors.fill: parent; radius: 10
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: "black" }
                }
            }
            Rectangle {
                x: cp.sat * sv.width - 8; y: (1 - cp.val) * sv.height - 8
                width: 16; height: 16; radius: 8
                color: "transparent"
                border.width: 2; border.color: "white"
                Rectangle { anchors.fill: parent; anchors.margins: -1; radius: 9; color: "transparent"; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.3) }
            }
            MouseArea {
                anchors.fill: parent
                function pick(e, done) {
                    cp.sat = Math.max(0, Math.min(1, e.x / sv.width));
                    cp.val = Math.max(0, Math.min(1, 1 - e.y / sv.height));
                    cp.fromHsv(done);
                }
                onPressed: (e) => pick(e, false)
                onPositionChanged: (e) => { if (pressed) pick(e, false); }
                onReleased: (e) => pick(e, true)
            }
        }
        // Odcień
        Rectangle {
            id: hueBar
            width: parent.width; height: 14; radius: 7
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#FF0000" }
                GradientStop { position: 0.17; color: "#FFFF00" }
                GradientStop { position: 0.33; color: "#00FF00" }
                GradientStop { position: 0.5; color: "#00FFFF" }
                GradientStop { position: 0.67; color: "#0000FF" }
                GradientStop { position: 0.83; color: "#FF00FF" }
                GradientStop { position: 1.0; color: "#FF0000" }
            }
            Rectangle {
                x: cp.hue * (hueBar.width - width); anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18; radius: 9
                color: Qt.hsva(cp.hue, 1, 1, 1)
                border.width: 2; border.color: "white"
            }
            MouseArea {
                anchors.fill: parent; anchors.margins: -6
                function pick(e, done) {
                    cp.hue = Math.max(0, Math.min(0.999, (e.x - 6) / hueBar.width));
                    if (cp.sat < 0.05) cp.sat = 1;
                    if (cp.val < 0.05) cp.val = 1;
                    cp.fromHsv(done);
                }
                onPressed: (e) => pick(e, false)
                onPositionChanged: (e) => { if (pressed) pick(e, false); }
                onReleased: (e) => pick(e, true)
            }
        }
        Row {
            spacing: 10
            Rectangle {
                width: 34; height: 34; radius: 10
                color: cp.value !== "" ? cp.value : "white"
                border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.14)
            }
            Rectangle {
                width: 150; height: 34; radius: 10
                color: Theme.fill
                Text { x: 12; anchors.verticalCenter: parent.verticalCenter; text: "#"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13 }
                TextInput {
                    id: hex
                    x: 26; width: parent.width - 36
                    anchors.verticalCenter: parent.verticalCenter
                    text: cp.value.replace("#", "").toUpperCase()
                    color: Theme.text
                    selectByMouse: true
                    font.family: Theme.font; font.pixelSize: 13; font.capitalization: Font.AllUppercase
                    validator: RegularExpressionValidator { regularExpression: /[0-9a-fA-F]{0,8}/ }
                    onAccepted: if (text.length === 6 || text.length === 8) cp.setFrom("#" + text, true)
                }
            }
        }
    }
}
