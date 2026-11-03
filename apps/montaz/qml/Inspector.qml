pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Montaz

// Ustawienia zaznaczonego elementu: klip (głośność, prędkość, kadr, przejście),
// tekst (treść i styl napisu) albo muzyka (głośność, wyciszenie na końcu).
Item {
    id: insp
    property string selected
    property string kind
    property var editor            // Editor (typ rekurencyjny — qmllint go nie przyjmuje)
    readonly property var info: Project.revision >= 0 && selected ? Project.item(selected) : ({})

    function focusText() { Qt.callLater(() => { textEdit.forceActiveFocus(); textEdit.selectAll(); }) }

    Rectangle { width: 1; height: parent.height; color: Theme.line }

    Flickable {
        x: 1
        width: parent.width - 1; height: parent.height
        contentHeight: col.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            x: 18; y: 6
            width: parent.width - 36
            spacing: 10

            Text {
                width: parent.width
                text: insp.kind === "clip" ? (insp.info.kind === "image" ? "Zdjęcie" : "Klip wideo")
                      : insp.kind === "text" ? "Tekst" : insp.kind === "music" ? "Muzyka" : "Projekt"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            }
            Text {
                visible: insp.kind === "clip" || insp.kind === "music"
                width: parent.width
                text: insp.info.name || ""
                elide: Text.ElideMiddle
                color: Theme.text2
                font.family: Theme.font; font.pixelSize: 12
            }

            // ——— Nic nie zaznaczono: o projekcie i wskazówki ———
            Column {
                visible: insp.kind === ""
                width: parent.width
                spacing: 8
                InfoRow { label: "Format"; value: Project.format + "  ·  " + Project.width + "×" + Project.height }
                InfoRow { label: "Długość"; value: Project.time(Project.duration, false) }
                InfoRow { label: "Klipy"; value: String(Project.clips.length) }
                Item { width: 1; height: 8 }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    lineHeight: 1.35
                    text: "• Kliknij klip na osi czasu, żeby zmienić głośność, prędkość albo przejście.\n"
                          + "• Przeciągnij krawędź klipu, żeby go przyciąć.\n"
                          + "• S dzieli klip w miejscu głowicy, Delete usuwa.\n"
                          + "• Spacja — odtwarzanie, strzałki — klatka po klatce."
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: 12
                }
            }

            // ——— Klip ———
            Column {
                visible: insp.kind === "clip"
                width: parent.width
                spacing: 10

                Label { text: "Głośność"; visible: insp.info.kind !== "image" }
                VolumeSlider {
                    visible: insp.info.kind !== "image"
                    value: insp.info.volume ?? 1
                    onMoved: (v) => Project.setValue(insp.selected, "volume", v)
                }

                Label { text: "Prędkość"; visible: insp.info.kind !== "image" }
                Chips {
                    visible: insp.info.kind !== "image"
                    model: [0.25, 0.5, 1, 1.5, 2, 3]
                    labelOf: (v) => String(v).replace(".", ",") + "×"
                    current: insp.info.speed ?? 1
                    onPicked: (v) => Project.setValue(insp.selected, "speed", v)
                }

                Label { text: "Kadr" }
                Chips {
                    model: [true, false]
                    labelOf: (v) => v ? "Wypełnij" : "Zmieść całość"
                    current: insp.info.fill ?? true
                    onPicked: (v) => Project.setValue(insp.selected, "fill", v)
                }

                Label { text: "Przejście z poprzedniego klipu"; visible: (insp.info.index ?? 0) > 0 }
                Chips {
                    visible: (insp.info.index ?? 0) > 0
                    model: [0, 15, 30]
                    labelOf: (v) => v === 0 ? "Cięcie" : "Przenikanie " + (v === 15 ? "0,5 s" : "1 s")
                    current: insp.info.fade ?? 0
                    onPicked: (v) => Project.setValue(insp.selected, "fade", v)
                }
                InfoRow { label: "Długość"; value: Project.time(insp.info.length ?? 0) }
            }

            // ——— Tekst ———
            Column {
                visible: insp.kind === "text"
                width: parent.width
                spacing: 10
                Rectangle {
                    width: parent.width; height: Math.max(70, textEdit.contentHeight + 20)
                    radius: 10
                    color: Theme.fill
                    border.width: textEdit.activeFocus ? 1 : 0
                    border.color: Theme.accentAlpha(0.6)
                    TextEdit {
                        id: textEdit
                        x: 10; y: 10; width: parent.width - 20
                        text: insp.kind === "text" ? insp.info.text : ""
                        wrapMode: TextEdit.Wrap
                        color: Theme.text
                        selectionColor: Theme.accentSoft
                        font.family: Theme.font; font.pixelSize: 14
                        onTextChanged: if (activeFocus && insp.kind === "text" && text !== insp.info.text) Project.setValue(insp.selected, "text", text)
                        Keys.onEscapePressed: focus = false
                    }
                }
                Label { text: "Styl" }
                Grid {
                    columns: 2
                    spacing: 8
                    Repeater {
                        model: Project.textStyles
                        delegate: StyleCard {
                            required property var modelData
                            style: modelData
                            width: (col.width - 8) / 2
                            current: insp.info.style === modelData.id
                            onClicked: Project.setValue(insp.selected, "style", modelData.id)
                        }
                    }
                }
                InfoRow { label: "Długość"; value: Project.time(insp.info.length ?? 0) }
            }

            // ——— Muzyka ———
            Column {
                visible: insp.kind === "music"
                width: parent.width
                spacing: 10
                Label { text: "Głośność" }
                VolumeSlider {
                    value: insp.info.volume ?? 1
                    onMoved: (v) => Project.setValue(insp.selected, "volume", v)
                }
                Chips {
                    model: [true, false]
                    labelOf: (v) => v ? "Wycisz na końcu" : "Bez wyciszania"
                    current: insp.info.fadeOut ?? true
                    onPicked: (v) => Project.setValue(insp.selected, "fadeOut", v)
                }
                InfoRow { label: "Długość"; value: Project.time(insp.info.length ?? 0) }
            }

            Item { width: 1; height: 4; visible: insp.kind !== "" }
            HoverButton {
                visible: insp.kind !== ""
                width: parent.width; height: 34
                baseColor: Theme.fill
                onClicked: insp.editor.removeSelected()
                Row {
                    anchors.centerIn: parent
                    spacing: 7
                    Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.trash; size: 15; color: Theme.danger }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Usuń z osi czasu"; color: Theme.danger; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium }
                }
            }
        }
    }

    component Label: Text {
        topPadding: 4
        color: Theme.text2
        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase; font.letterSpacing: 0.4
    }

    component InfoRow: Item {
        property string label
        property string value
        width: parent ? parent.width : 0; height: 20
        Text { text: parent.label; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        Text { anchors.right: parent.right; text: parent.value; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium; font.features: { "tnum": 1 } }
    }

    // Wybór jednej z kilku wartości
    component Chips: Flow {
        id: chips
        property var model: []
        property var current
        property var labelOf: (v) => String(v)
        signal picked(var value)
        width: parent ? parent.width : 0
        spacing: 6
        Repeater {
            model: chips.model
            delegate: HoverButton {
                id: chip
                required property var modelData
                readonly property bool on: chips.current === modelData
                width: chipText.implicitWidth + 20; height: 28; radius: 14
                baseColor: on ? Theme.accent : Theme.fill
                color: on ? Theme.accent : (hovered ? Theme.hover : baseColor)
                onClicked: chips.picked(modelData)
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: chips.labelOf(chip.modelData)
                    color: chip.on ? "white" : Theme.text
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                }
            }
        }
    }

    // Suwak głośności 0–200% (100% pośrodku)
    component VolumeSlider: Item {
        id: vs
        property real value: 1
        signal moved(real value)
        width: parent ? parent.width : 0; height: 26
        readonly property real shown: area.pressed ? area.dragValue : value
        Icon { anchors.verticalCenter: parent.verticalCenter; d: vs.shown === 0 ? Icons.volumeOff : vs.shown < 0.6 ? Icons.volumeLow : Icons.volume; size: 16; color: Theme.text2 }
        Item {
            id: track
            x: 26; width: parent.width - 26 - 46; height: parent.height
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Theme.fill }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * vs.shown / 2; height: 4; radius: 2; color: Theme.accent }
            Rectangle { x: parent.width / 2 - 0.5; anchors.verticalCenter: parent.verticalCenter; width: 1; height: 10; color: Theme.text2; opacity: 0.5 }
            Rectangle {
                x: parent.width * vs.shown / 2 - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 16; height: 16; radius: 8
                color: "white"
                border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15)
            }
            MouseArea {
                id: area
                anchors.fill: parent
                anchors.margins: -4
                preventStealing: true
                property real dragValue: 1
                function valueAt(x) {
                    let v = Math.max(0, Math.min(2, (x - 4) / track.width * 2));
                    if (Math.abs(v - 1) < 0.05) v = 1;      // przyciąganie do 100%
                    return Math.round(v * 100) / 100;
                }
                onPressed: (e) => { dragValue = valueAt(e.x); vs.moved(dragValue); }
                onPositionChanged: (e) => { dragValue = valueAt(e.x); vs.moved(dragValue); }
            }
        }
        Text {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: Math.round(vs.shown * 100) + "%"
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium; font.features: { "tnum": 1 }
        }
    }

    // Podgląd stylu napisu
    component StyleCard: HoverButton {
        id: sc
        property var style
        property bool current: false
        height: 54; radius: 10
        baseColor: "#3B4252"
        color: "#3B4252"
        border.width: current ? 2 : 0
        border.color: Theme.accent
        clip: true
        Rectangle {
            anchors.fill: parent; radius: 10
            gradient: Gradient {
                GradientStop { position: 0; color: "#5E6B85" }
                GradientStop { position: 1; color: "#2B3140" }
            }
            opacity: sc.hovered ? 0.85 : 1
        }
        Rectangle {
            anchors.centerIn: sampleText
            width: sampleText.implicitWidth + 10; height: sampleText.implicitHeight + 2; radius: 3
            color: sc.style.bg.length === 9 && !sc.style.bg.startsWith("#00") ? "#" + sc.style.bg.substring(3) : "transparent"
            opacity: sc.style.bg.length === 9 ? parseInt(sc.style.bg.substring(1, 3), 16) / 255 : 1
        }
        Text {
            id: sampleText
            anchors.horizontalCenter: parent.horizontalCenter
            y: sc.style.place === "top" ? 6 : sc.style.place === "middle" ? (parent.height - height) / 2 - 4 : parent.height - height - 14
            text: sc.style.upper ? "AA" : "Aa"
            color: sc.style.fg
            style: sc.style.outline > 0 ? Text.Outline : Text.Normal
            styleColor: sc.style.ol.length === 9 ? "#" + sc.style.ol.substring(3) : sc.style.ol
            font.family: Theme.font; font.pixelSize: 16; font.weight: sc.style.weight
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom; anchors.bottomMargin: 2
            text: sc.style.name
            color: Qt.rgba(1, 1, 1, 0.7)
            font.family: Theme.font; font.pixelSize: 9; font.weight: Font.Medium
        }
    }
}
