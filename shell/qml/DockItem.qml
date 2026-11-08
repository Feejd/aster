import QtQuick
import Aster.Shell
import Aster.Ui

// Jedna ikona w doku: Start, przypięta aplikacja, działające okno albo Kosz.
// Rozmiar: base × magnify (liczy DockWindow; domyślnie bez powiększania).
// Uruchamiany program podskakuje, działający ma kropkę, aktywny — dłuższą kreskę.
Item {
    id: item
    property string desktopId: ""
    property var iconSource
    property string label: ""
    property bool running: false
    property bool active: false
    property bool starting: false
    property bool pressedLook: false      // np. otwarty Start
    property bool popupOpen: false        // nad ikoną jest już karta okien albo menu
    property real base: 50
    property real magnify: 1
    signal clicked()
    signal middleClicked()
    signal rightClicked()

    readonly property real size: base * magnify
    width: size + 8
    height: size
    anchors.bottom: parent ? parent.bottom : undefined     // w rzędzie doku rośnie w górę

    readonly property int badge: Platform.badges[desktopId] || 0
    readonly property bool hovered: area.containsMouse

    // Ikona w kształcie squircle; po wciśnięciu przyciemnia się i zmniejsza
    AppIcon {
        id: tile
        size: item.size
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: item.jump
        desktopId: item.desktopId
        source: item.iconSource
        scale: area.pressed || item.pressedLook ? 0.88 : 1
        transformOrigin: Item.Bottom
        Behavior on scale { SpringAnimation { spring: 5; damping: 0.32; epsilon: 0.002 } }
        Rectangle {
            anchors.fill: parent
            radius: width * 0.26
            color: "black"
            opacity: area.pressed ? 0.2 : 0
            Behavior on opacity { NumberAnimation { duration: 90 } }
        }
    }

    // Podskakiwanie przy uruchamianiu
    property real jump: 0
    SequentialAnimation on jump {
        running: item.starting
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 18; duration: 160; easing.type: Easing.OutQuad }
        NumberAnimation { to: 0; duration: 180; easing.type: Easing.OutBounce }
        PauseAnimation { duration: 120 }
    }

    // Liczba nieprzeczytanych (komunikatory, poczta, aplikacje webowe)
    Rectangle {
        x: tile.x + tile.width - width + 5
        y: tile.y - 4
        z: 2
        height: 20
        width: Math.max(20, badgeText.implicitWidth + 12)
        radius: 10
        color: "#FF453A"
        border.width: 2
        border.color: Theme.dark ? "#2A2C33" : "white"
        scale: item.badge > 0 ? 1 : 0
        visible: scale > 0.01
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
        Text {
            id: badgeText
            anchors.centerIn: parent
            text: item.badge > 99 ? "99+" : String(item.badge)
            color: "white"
            font.family: Theme.font; font.pixelSize: 11; font.letterSpacing: 0.1; font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }
    }

    // Kropka pod działającą aplikacją — przy aktywnym oknie rozciąga się w kreskę
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: 3
        width: item.active ? 14 : 4
        height: 4; radius: 2
        visible: item.running || item.starting
        color: item.active ? Theme.text : Theme.text2
        opacity: item.active ? 0.95 : 0.7
        Behavior on width { SpringAnimation { spring: 4; damping: 0.35 } }
    }

    // Podpowiedź z nazwą: szklana pigułka nad ikoną, wjeżdża od dołu
    Rectangle {
        id: tip
        anchors.horizontalCenter: parent.horizontalCenter
        y: tile.y - height - 12 - item.jump + (shown ? 0 : 6)
        readonly property bool shown: area.containsMouse && !area.pressed && item.label !== "" && !item.popupOpen
        width: tipText.implicitWidth + 22; height: 28; radius: 14
        color: Theme.dark ? Qt.rgba(0.16, 0.16, 0.19, 0.94) : Qt.rgba(1, 1, 1, 0.94)
        border.width: 1
        border.color: Theme.dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.08)
        opacity: shown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 90 } }
        Behavior on y { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        Text {
            id: tipText
            anchors.centerIn: parent
            text: item.label
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: (m) => {
            if (m.button === Qt.MiddleButton) item.middleClicked();
            else if (m.button === Qt.RightButton) item.rightClicked();
            else item.clicked();
        }
    }
}
