pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Store

// Główne działanie na programie, wspólne dla każdego źródła: Zainstaluj / Dodaj → pasek postępu w przycisku → Otwórz
Item {
    id: gb
    property string ref
    property bool big: false
    property bool onTint: false

    readonly property var state_: { Store.version; Flatpak.installed; Flatpak.webApps; return Store.state(ref); }
    readonly property bool installed: state_ === "installed" || state_ === "builtin"
    readonly property string key: Store.jobKey(ref)
    readonly property var prog: Flatpak.progress[key]
    readonly property bool busy: prog !== undefined
    readonly property real fraction: busy && prog >= 0 ? prog : 0
    readonly property bool usable: { Store.version; return Store.canInstall(ref); }

    implicitWidth: Math.max(label.implicitWidth + (big ? 44 : 26), big ? 148 : 84)
    implicitHeight: big ? 44 : 32
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: gb.big ? 10 : 8
        color: gb.busy ? Theme.fill
             : gb.installed ? (area.containsMouse ? Theme.hover : Theme.fill)
             : gb.big ? Theme.accent
             : (area.containsMouse ? Theme.accentAlpha(0.24) : Theme.accentSoft)
        scale: area.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: 80 } }
        opacity: gb.installed || gb.busy || gb.usable ? 1 : 0.5
        clip: true

        // Postęp wypełnia przycisk od lewej
        Rectangle {
            visible: gb.busy
            height: parent.height
            width: parent.width * gb.fraction
            radius: parent.radius
            color: Theme.accentSoft
            Behavior on width { NumberAnimation { duration: 120 } }
        }
        Txt {
            id: label
            anchors.centerIn: parent
            text: gb.busy ? (gb.prog < 0 ? "W kolejce" : Math.round(gb.fraction * 100) + "%")
                : gb.installed ? "Otwórz"
                : !gb.usable ? (Flatpak.arch === "aarch64" ? "Tylko x86" : "Niedostępny")
                : Store.kindOf(gb.ref) === "web" ? "Dodaj" : "Zainstaluj"
            color: gb.busy ? Theme.text
                 : gb.installed ? Theme.text
                 : gb.big ? "white" : Theme.accentText
            font.pixelSize: gb.big ? 15 : 13
            font.weight: Font.DemiBold
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        enabled: !gb.busy && (gb.installed || gb.usable)
        onClicked: Store.act(gb.ref)
    }
}
