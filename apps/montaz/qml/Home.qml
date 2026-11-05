pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Aster.Ui
import Aster.Montaz

// Ekran startowy: nowy projekt w jednym z trzech formatów i lista zapisanych projektów
GlassPane {
    id: home
    required property Window window
    property real radius: 0
    signal menuRequested(var items, real x, real y)

    leftLine: false
    topLeftRadius: radius; topRightRadius: radius; bottomLeftRadius: radius; bottomRightRadius: radius

    readonly property bool shaders: GraphicsInfo.api !== GraphicsInfo.Software && GraphicsInfo.api !== GraphicsInfo.Unknown
    property string menuId

    function projectMenu(id, item, x, y) {
        menuId = id;
        const p = item.mapToItem(null, x, y);
        menuRequested([{ label: "Otwórz", icon: "folder", action: "open" },
                       { separator: true },
                       { label: "Usuń projekt", icon: "trash", action: "delete", danger: true }], p.x, p.y);
    }
    function runMenu(a) {
        if (a === "open") Project.openProject(menuId);
        else if (a === "delete") Project.deleteProject(menuId);
    }

    Item {
        id: topBar
        width: parent.width; height: 68
        z: 5
        DragHandler { target: null; onActiveChanged: if (active) home.window.startSystemMove() }
        TapHandler { onDoubleTapped: if (home.window.visibility === Window.Maximized) home.window.showNormal(); else home.window.showMaximized() }
        Row {
            x: 26; anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            AppIcon { anchors.verticalCenter: parent.verticalCenter; desktopId: "org.aster.montaz"; size: 30 }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Montaż"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: -0.4
            }
        }
        WindowButtons {
            window: home.window
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Flickable {
        id: flick
        y: topBar.height
        width: parent.width; height: parent.height - y
        contentHeight: col.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        readonly property int cardW: {
            const avail = width - 52;
            const cols = Math.max(2, Math.floor((avail + 16) / 220));
            return Math.floor((avail - (cols - 1) * 16) / cols);
        }

        Column {
            id: col
            x: 26
            width: parent.width - 52
            spacing: 14

            Text {
                text: "Nowy projekt"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: "Wybierz, gdzie pokażesz film. Format możesz dobrać do platformy — klipy same dopasują się do kadru."
                wrapMode: Text.WordWrap
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 13
            }
            Row {
                spacing: 16
                FormatCard { format: "9:16"; title: "Pionowy"; detail: "TikTok, Reels, Shorts"; ratio: 9 / 16; tint: "#FF5C8A" }
                FormatCard { format: "16:9"; title: "Poziomy"; detail: "YouTube, telewizor"; ratio: 16 / 9; tint: "#5C8BFF" }
                FormatCard { format: "1:1"; title: "Kwadrat"; detail: "Instagram, Facebook"; ratio: 1; tint: "#34C08A" }
            }
            Item { width: 1; height: 10 }

            Text {
                visible: Project.projects.length > 0
                text: "Twoje projekty"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
            }
            Flow {
                width: parent.width
                spacing: 16
                Repeater {
                    model: Project.projects
                    delegate: ProjectCard {
                        required property var modelData
                        width: flick.cardW
                        info: modelData
                    }
                }
            }
            Column {
                visible: Project.projects.length === 0
                width: parent.width
                topPadding: 26
                spacing: 8
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Nie masz jeszcze projektów"
                    color: Theme.text; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, 420)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Wybierz format powyżej albo upuść filmy i zdjęcia na to okno — projekt powstanie od razu. Projekty zapisują się same."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; lineHeight: 1.25
                }
            }
        }
    }

    // Karta formatu: prostokąt w proporcjach kadru
    component FormatCard: Rectangle {
        id: fc
        property string format
        property string title
        property string detail
        property real ratio: 1
        property color tint
        width: 200; height: 190
        radius: 10
        color: fcArea.containsMouse ? Theme.hover : Theme.fill
        border.width: 1
        border.color: fcArea.containsMouse ? Theme.accentAlpha(0.5) : Theme.line
        scale: fcArea.pressed ? 0.97 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
        Behavior on color { ColorAnimation { duration: 120 } }

        Item {
            width: parent.width; height: 112
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(124, 84 * fc.ratio)
                height: width / fc.ratio
                radius: 8
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(fc.tint, 1.25) }
                    GradientStop { position: 1; color: fc.tint }
                }
                Icon { anchors.centerIn: parent; d: Icons.play; size: 20; color: "white"; fill: "white" }
            }
        }
        Column {
            x: 16; y: 118
            spacing: 3
            Text {
                text: fc.title + "  ·  " + fc.format
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            }
            Text {
                text: fc.detail
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 12
            }
        }
        MouseArea {
            id: fcArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Project.newProject(fc.format)
        }
    }

    // Karta projektu: miniatura pierwszego klipu, nazwa, długość i data
    component ProjectCard: Item {
        id: pc
        property var info
        height: width * 9 / 16 + 50

        Rectangle {
            id: shot
            width: parent.width; height: width * 9 / 16
            radius: 12
            color: Theme.dark ? "#1B1D24" : "#E4E7EE"
            layer.enabled: home.shaders
            layer.effect: MultiEffect { maskEnabled: true; maskSource: shotMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
            scale: pcArea.pressed ? 0.98 : 1
            Behavior on scale { NumberAnimation { duration: 100 } }
            Icon { anchors.centerIn: parent; d: Icons.clapper; size: 30; stroke: 1.5; color: Theme.text2; visible: img.status !== Image.Ready }
            Image {
                id: img
                anchors.fill: parent
                source: pc.info.thumb
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.height: 200
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
            Rectangle {
                anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 8
                width: fmt.implicitWidth + 12; height: 20; radius: 6
                color: Qt.rgba(0, 0, 0, 0.55)
                Text { id: fmt; anchors.centerIn: parent; text: pc.info.format; color: "white"; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }
            }
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, pcArea.containsMouse ? 0.18 : 0)
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }
        Rectangle { id: shotMask; width: shot.width; height: shot.height; radius: 12; visible: false; layer.enabled: true }
        Text {
            y: shot.height + 9
            width: parent.width
            text: pc.info.name
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
        }
        Text {
            y: shot.height + 28
            width: parent.width
            text: Project.time(pc.info.duration, false) + "  ·  " + Project.when(pc.info.modified)
            elide: Text.ElideRight
            color: Theme.text2
            font.family: Theme.font; font.pixelSize: 12
        }
        MouseArea {
            id: pcArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (e) => {
                if (e.button === Qt.RightButton) home.projectMenu(pc.info.id, pc, e.x, e.y);
                else Project.openProject(pc.info.id);
            }
        }
    }
}
