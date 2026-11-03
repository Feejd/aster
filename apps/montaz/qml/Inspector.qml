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

    property string clipTab: "basic"           // klip: basic (dźwięk, prędkość), frame (kadr i ruch), look (kolory), trans (przejście)
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
                      : insp.kind === "text" ? "Tekst" : insp.kind === "music" ? (insp.info.voice ? "Lektor" : "Muzyka")
                      : insp.kind === "overlay" ? (insp.info.kind === "image" ? "Nakładka — zdjęcie" : "Nakładka — film") : "Projekt"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold
            }
            Text {
                visible: insp.kind === "clip" || insp.kind === "music" || insp.kind === "overlay"
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
                Label { text: "Format" }
                Chips {
                    model: ["9:16", "16:9", "1:1"]
                    labelOf: (v) => v === "9:16" ? "9:16 pionowy" : v === "16:9" ? "16:9 poziomy" : "1:1 kwadrat"
                    current: Project.format
                    onPicked: (v) => Project.setOption("format", v)
                }
                InfoRow { label: "Długość"; value: Project.time(Project.duration, false) }
                InfoRow { label: "Klipy"; value: String(Project.clips.length) }
                Label { text: "Początek i koniec filmu" }
                Flow {
                    width: parent.width
                    spacing: 6
                    Toggle { label: "Rozjaśnij z czerni"; on: Project.fadeIn; onToggled: Project.setOption("fadeIn", !Project.fadeIn) }
                    Toggle { label: "Ściemnij na końcu"; on: Project.fadeOut; onToggled: Project.setOption("fadeOut", !Project.fadeOut) }
                }
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
            Segmented {
                visible: insp.kind === "clip"
                model: (insp.info.index ?? 0) > 0
                       ? [{ id: "basic", name: "Klip" }, { id: "frame", name: "Kadr" }, { id: "look", name: "Kolory" }, { id: "trans", name: "Przejście" }]
                       : [{ id: "basic", name: "Klip" }, { id: "frame", name: "Kadr" }, { id: "look", name: "Kolory" }]
                current: insp.clipTab === "trans" && (insp.info.index ?? 0) === 0 ? "basic" : insp.clipTab
                onPicked: (v) => insp.clipTab = v
            }
            // ——— Kadr: dopasowanie, ruch kamery, odbicie ———
            Column {
                visible: insp.kind === "clip" && insp.clipTab === "frame"
                width: parent.width
                spacing: 10
                Label { text: "Dopasowanie" }
                Chips {
                    model: ["fill", "fit", "blur"]
                    labelOf: (v) => v === "fill" ? "Wypełnij" : v === "fit" ? "Zmieść" : "Rozmyte tło"
                    current: insp.info.fit ?? "fill"
                    onPicked: (v) => Project.setValue(insp.selected, "fit", v)
                }
                Label { text: "Ruch kamery" }
                Grid {
                    columns: 3
                    spacing: 8
                    Repeater {
                        model: Project.motions
                        delegate: AnimTile {
                            required property var modelData
                            width: (col.width - 16) / 3
                            kind: "motion"
                            effect: modelData.id
                            name: modelData.name
                            current: (insp.info.motion ?? "") === modelData.id
                            onClicked: Project.setValue(insp.selected, "motion", modelData.id)
                        }
                    }
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    Toggle { label: "Odbicie lustrzane"; on: insp.info.flip ?? false; onToggled: Project.setValue(insp.selected, "flip", !insp.info.flip) }
                }
            }
            // ——— Przejście z poprzedniego klipu ———
            Column {
                visible: insp.kind === "clip" && insp.clipTab === "trans" && (insp.info.index ?? 0) > 0
                width: parent.width
                spacing: 10
                Grid {
                    columns: 3
                    spacing: 8
                    AnimTile {
                        width: (col.width - 16) / 3
                        kind: "trans"
                        effect: ""
                        name: "Cięcie"
                        current: (insp.info.fade ?? 0) === 0
                        onClicked: Project.setValue(insp.selected, "fade", 0)
                    }
                    Repeater {
                        model: Project.transitions
                        delegate: AnimTile {
                            required property var modelData
                            width: (col.width - 16) / 3
                            kind: "trans"
                            effect: modelData.id
                            name: modelData.name
                            current: (insp.info.fade ?? 0) > 0 && insp.info.trans === modelData.id
                            onClicked: Project.setValue(insp.selected, "trans", modelData.id)
                        }
                    }
                }
                Label { text: "Długość"; visible: (insp.info.fade ?? 0) > 0 }
                Chips {
                    visible: (insp.info.fade ?? 0) > 0
                    model: [9, 15, 24, 30]
                    labelOf: (v) => (v / Project.fps).toFixed(1).replace(".", ",") + " s"
                    current: insp.info.fade ?? 0
                    onPicked: (v) => Project.setValue(insp.selected, "fade", v)
                }
                HoverButton {
                    visible: (insp.info.fade ?? 0) > 0 && Project.clips.length > 2
                    width: allText.implicitWidth + 24; height: 30; radius: 15
                    baseColor: Theme.fill
                    onClicked: Project.applyTransitionToAll(insp.selected)
                    Text { id: allText; anchors.centerIn: parent; text: "Zastosuj do wszystkich klipów"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                }
            }
            Column {
                visible: insp.kind === "clip" && insp.clipTab === "look"
                width: parent.width
                spacing: 10
                Label { text: "Filtr" }
                Grid {
                    columns: 3
                    spacing: 8
                    Repeater {
                        model: Project.looks
                        delegate: LookCard {
                            required property var modelData
                            width: (col.width - 16) / 3
                            look: modelData
                            current: (insp.info.look ?? "") === modelData.id
                            onClicked: Project.setValue(insp.selected, "look", modelData.id)
                        }
                    }
                }
                Label { text: "Korekta" }
                ValueSlider {
                    label: "Jasność"; from: -0.5; to: 0.5; neutral: 0
                    value: insp.info.brightness ?? 0
                    onMoved: (v) => Project.setValue(insp.selected, "brightness", v)
                }
                ValueSlider {
                    label: "Kontrast"; from: 0.3; to: 2; neutral: 1
                    value: insp.info.contrast ?? 1
                    onMoved: (v) => Project.setValue(insp.selected, "contrast", v)
                }
                ValueSlider {
                    label: "Nasycenie"; from: 0; to: 2.5; neutral: 1
                    value: insp.info.saturation ?? 1
                    onMoved: (v) => Project.setValue(insp.selected, "saturation", v)
                }
                HoverButton {
                    visible: (insp.info.look ?? "") !== "" || (insp.info.brightness ?? 0) !== 0 || (insp.info.contrast ?? 1) !== 1 || (insp.info.saturation ?? 1) !== 1
                    width: resetText.implicitWidth + 24; height: 30; radius: 15
                    baseColor: Theme.fill
                    onClicked: Project.setValue(insp.selected, "resetLook", true)
                    Text { id: resetText; anchors.centerIn: parent; text: "Przywróć oryginał"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                }
            }
            Column {
                visible: insp.kind === "clip" && insp.clipTab === "basic"
                width: parent.width
                spacing: 10

                Label { text: "Głośność"; visible: insp.info.kind !== "image" }
                VolumeSlider {
                    visible: insp.info.kind !== "image"
                    value: insp.info.volume ?? 1
                    onMoved: (v) => Project.setValue(insp.selected, "volume", v)
                }
                VoiceTools { visible: insp.info.audio ?? false }

                Label { text: "Prędkość"; visible: insp.info.kind !== "image" }
                Chips {
                    visible: insp.info.kind !== "image"
                    model: [0.25, 0.5, 1, 1.5, 2, 3]
                    labelOf: (v) => String(v).replace(".", ",") + "×"
                    current: insp.info.speed ?? 1
                    onPicked: (v) => Project.setValue(insp.selected, "speed", v)
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
                        text: insp.kind === "text" ? (insp.info.text ?? "") : ""
                        wrapMode: TextEdit.Wrap
                        color: Theme.text
                        selectionColor: Theme.accentSoft
                        font.family: Theme.font; font.pixelSize: 14
                        onTextChanged: if (activeFocus && insp.kind === "text" && text !== insp.info.text) Project.setValue(insp.selected, "text", text)
                        Keys.onEscapePressed: focus = false
                    }
                }
                Label { text: "Kolor liter" }
                Flow {
                    width: parent.width
                    spacing: 7
                    Repeater {
                        model: ["", "#FFFFFF", "#FFD84D", "#FF9F1C", "#FF4D6D", "#C77DFF", "#4DA3FF", "#3DDC97", "#111111"]
                        delegate: Rectangle {
                            id: sw
                            required property string modelData
                            readonly property bool on: (insp.info.color ?? "") === modelData
                            width: 24; height: 24; radius: 12
                            color: modelData === "" ? "transparent" : modelData
                            border.width: on ? 3 : 1
                            border.color: on ? Theme.accent : Theme.line
                            Icon { visible: sw.modelData === ""; anchors.centerIn: parent; d: Icons.sparkle; size: 13; color: Theme.text2 }
                            MouseArea { anchors.fill: parent; anchors.margins: -2; cursorShape: Qt.PointingHandCursor; onClicked: Project.setValue(insp.selected, "color", sw.modelData) }
                        }
                    }
                }
                ValueSlider {
                    label: "Wielkość"; from: 0.4; to: 3; neutral: 1
                    value: insp.info.scale ?? 1
                    onMoved: (v) => Project.setValue(insp.selected, "scale", v)
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: (insp.info.x ?? -1) >= 0 ? "Napis stoi tam, gdzie go przeciągnięto na podglądzie." : "Przeciągnij napis na podglądzie, żeby go przesunąć."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                }
                HoverButton {
                    visible: (insp.info.x ?? -1) >= 0 || (insp.info.scale ?? 1) !== 1
                    width: posText.implicitWidth + 24; height: 28; radius: 14
                    baseColor: Theme.fill
                    onClicked: Project.setValue(insp.selected, "resetPos", true)
                    Text { id: posText; anchors.centerIn: parent; text: "Miejsce i wielkość ze stylu"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                }
                Label { text: "Animacja" }
                Chips {
                    model: Project.textAnimations.map(a => a.id)
                    labelOf: (v) => Project.textAnimations.find(a => a.id === v).name
                    current: insp.info.anim ?? "brak"
                    onPicked: (v) => Project.setValue(insp.selected, "anim", v)
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

            // ——— Nakładka ———
            Column {
                visible: insp.kind === "overlay"
                width: parent.width
                spacing: 10
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Przeciągnij nakładkę na podglądzie, a róg ramki — żeby zmienić wielkość."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                }
                ValueSlider {
                    label: "Wielkość"; from: 0.05; to: 1.5; neutral: 0.05; unit: "%"
                    value: insp.info.scale ?? 0.5
                    onMoved: (v) => Project.setValue(insp.selected, "scale", v)
                }
                ValueSlider {
                    label: "Obrót"; from: -180; to: 180; neutral: 0; unit: "°"; step: 1
                    value: insp.info.rotation ?? 0
                    onMoved: (v) => Project.setValue(insp.selected, "rotation", v)
                }
                ValueSlider {
                    label: "Widoczność"; from: 0.05; to: 1; neutral: 1; unit: "%"
                    value: insp.info.opacity ?? 1
                    onMoved: (v) => Project.setValue(insp.selected, "opacity", v)
                }
                Label { text: "Kształt" }
                Chips {
                    model: ["rect", "rounded", "circle"]
                    labelOf: (v) => v === "rect" ? "Prostokąt" : v === "rounded" ? "Zaokrąglony" : "Koło"
                    current: insp.info.shape ?? "rect"
                    onPicked: (v) => Project.setValue(insp.selected, "shape", v)
                }
                Label { text: "Pojawianie się" }
                Chips {
                    model: ["brak", "pojawianie", "wyskok", "wjazd"]
                    labelOf: (v) => v === "brak" ? "Bez animacji" : v === "pojawianie" ? "Pojawianie" : v === "wyskok" ? "Wyskok" : "Wjazd od dołu"
                    current: insp.info.anim ?? "brak"
                    onPicked: (v) => Project.setValue(insp.selected, "anim", v)
                }
                Label { text: "Tło nakładki" }
                Flow {
                    width: parent.width
                    spacing: 6
                    Toggle { label: "Usuń zielone tło"; on: (insp.info.chroma ?? false) && insp.info.key === "#00B140"
                             onToggled: { if (on) Project.setValue(insp.selected, "chroma", false); else { Project.setValue(insp.selected, "key", "#00B140"); Project.setValue(insp.selected, "chroma", true); } } }
                    Toggle { label: "Usuń niebieskie tło"; on: (insp.info.chroma ?? false) && insp.info.key === "#0047BB"
                             onToggled: { if (on) Project.setValue(insp.selected, "chroma", false); else { Project.setValue(insp.selected, "key", "#0047BB"); Project.setValue(insp.selected, "chroma", true); } } }
                }
                ValueSlider {
                    visible: insp.info.chroma ?? false
                    label: "Czułość"; from: 0.02; to: 0.6; neutral: 0.25
                    value: insp.info.variance ?? 0.25
                    onMoved: (v) => Project.setValue(insp.selected, "variance", v)
                }
                Label { text: "Głośność"; visible: insp.info.kind === "video" }
                VolumeSlider {
                    visible: insp.info.kind === "video"
                    value: insp.info.volume ?? 1
                    onMoved: (v) => Project.setValue(insp.selected, "volume", v)
                }
                HoverButton {
                    width: fullText.implicitWidth + 24; height: 30; radius: 15
                    baseColor: Theme.fill
                    onClicked: Project.setValue(insp.selected, "full", true)
                    Text { id: fullText; anchors.centerIn: parent; text: "Na cały kadr"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
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
                VoiceTools {}
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

    // Kafelek z małą animacją: jak działa przejście (A → B) albo ruch kamery. Animuje się po najechaniu i gdy jest wybrany.
    component AnimTile: Item {
        id: at
        property string kind                // "trans" albo "motion"
        property string effect
        property string name
        property bool current: false
        signal clicked()
        height: width * 0.75 + 18
        property real t: 0
        NumberAnimation on t {
            from: 0; to: 1; duration: 1300; loops: Animation.Infinite
            running: at.visible && (atArea.containsMouse || at.current)
            onRunningChanged: if (!running) at.t = 0.35
        }
        Component.onCompleted: t = 0.35
        // postęp przejścia z pauzą na końcach
        readonly property real p: Math.max(0, Math.min(1, (t - 0.2) / 0.6))
        Rectangle {
            id: box
            width: parent.width; height: parent.width * 0.75
            radius: 8
            color: "#1E2230"
            clip: true
            // A — poprzedni klip
            Rectangle {
                id: ra
                readonly property string e: at.effect
                z: e === "zoomin" ? 2 : 0          // przy przybliżeniu poprzedni klip jest na wierzchu
                width: box.width; height: box.height
                color: "#4F7BFF"
                x: at.kind === "trans" ? (e === "pushleft" || e === "whip" ? -at.p * box.width : 0) : 0
                y: at.kind === "trans" && e === "pushup" ? -at.p * box.height : 0
                scale: at.kind === "trans" && e === "zoomin" ? 1 + at.p : 1
                opacity: at.kind === "motion" ? 0 : (e === "zoomin" ? 1 - at.p : 1)
                Text { anchors.centerIn: parent; text: "A"; color: "white"; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold }
            }
            // B — następny klip (dla ruchu kamery: sam kadr)
            Item {
                id: rbBox
                anchors.fill: parent
                Rectangle {
                    id: rb
                    readonly property string e: at.effect
                    readonly property real p: at.p
                    width: box.width; height: box.height
                    radius: e === "circle" && at.kind === "trans" ? width : 0
                    color: "#FF5C8A"
                    // ruch kamery: zoom, przesunięcie, puls, drgania
                    x: at.kind === "motion" ? (e === "panleft" ? -p * width * 0.16 : e === "panright" ? (p - 1) * width * 0.16
                                               : e === "shake" ? Math.sin(at.t * 60) * 2 : 0)
                       : (e === "pushleft" || e === "whip" || e === "slide" ? (1 - p) * box.width : 0)
                    y: at.kind === "motion" ? (e === "shake" ? Math.cos(at.t * 47) * 2 : 0) : (e === "pushup" ? (1 - p) * box.height : 0)
                    scale: at.kind === "motion" ? (e === "zoomin" ? 1 + 0.16 * p : e === "zoomout" ? 1.16 - 0.16 * p : e === "pulse" ? 1 + 0.06 * Math.abs(Math.sin(at.t * Math.PI * 4))
                                                   : e === "panleft" || e === "panright" || e === "shake" ? 1.16 : 1)
                           : e === "zoomout" ? 1.6 - 0.6 * p : e === "spin" ? 0.4 + 0.6 * p : e === "circle" ? 1.5 * p : 1
                    rotation: at.kind === "trans" && e === "spin" ? -180 * (1 - p) : 0
                    opacity: at.kind === "motion" ? 1
                             : e === "" ? (at.t > 0.5 ? 1 : 0)
                             : e === "fade" || e === "blur" || e === "zoomout" || e === "spin" ? p
                             : e === "black" || e === "white" ? (p > 0.5 ? 1 : 0)
                             : 1
                    Text { visible: at.kind === "trans"; anchors.centerIn: parent; text: "B"; color: "white"; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold }
                    Icon {
                        visible: at.kind === "motion"
                        anchors.centerIn: parent
                        readonly property var glyphs: ({ "": "close", zoomin: "plus", zoomout: "minus", panleft: "back", panright: "chevronRight", pulse: "activity", shake: "signal" })
                        d: Icons[glyphs[at.effect] || "close"]
                        size: 18; stroke: 2.2; color: "white"
                    }
                }
            }
            Rectangle {      // maska kurtyny (zakrywa nieodsłoniętą część B)
                visible: at.kind === "trans" && at.effect === "wipe"
                x: at.p * box.width; width: box.width - x; height: box.height
                color: "#4F7BFF"
                Text { visible: at.p < 0.5; anchors.centerIn: parent; text: "A"; color: "white"; font.family: Theme.font; font.pixelSize: 15; font.weight: Font.Bold }
            }
            Rectangle {      // błysk, czerń
                anchors.fill: parent
                visible: at.kind === "trans" && (at.effect === "white" || at.effect === "black")
                color: at.effect === "white" ? "white" : "black"
                opacity: 1 - Math.abs(at.p * 2 - 1)
            }
            Rectangle {      // smuga, rozmycie — przybliżenie ruchu
                anchors.fill: parent
                visible: at.kind === "trans" && (at.effect === "whip" || at.effect === "blur")
                color: "white"
                opacity: 0.35 * (1 - Math.abs(at.p * 2 - 1))
            }
            Rectangle {
                anchors.fill: parent; radius: 8
                color: "transparent"
                border.width: at.current ? 2 : (atArea.containsMouse ? 1 : 0)
                border.color: at.current ? Theme.accent : Theme.line
            }
        }
        Text {
            y: box.height + 3
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: at.name
            elide: Text.ElideRight
            color: at.current ? Theme.accentText : Theme.text2
            font.family: Theme.font; font.pixelSize: 10; font.weight: at.current ? Font.DemiBold : Font.Normal
        }
        MouseArea { id: atArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: at.clicked() }
    }

    // Przełącznik dwóch-trzech widoków (jak karty)
    component Segmented: Rectangle {
        id: seg
        property var model: []
        property string current
        signal picked(string value)
        width: parent ? parent.width : 0; height: 32; radius: 10
        color: Theme.fill
        Row {
            anchors.fill: parent; anchors.margins: 3
            Repeater {
                model: seg.model
                delegate: Rectangle {
                    id: segItem
                    required property var modelData
                    readonly property bool on: seg.current === modelData.id
                    width: (seg.width - 6) / seg.model.length; height: parent.height; radius: 8
                    color: on ? Theme.surface : "transparent"
                    border.width: on ? 1 : 0; border.color: Theme.line
                    Text {
                        anchors.centerIn: parent
                        text: segItem.modelData.name
                        color: segItem.on ? Theme.text : Theme.text2
                        font.family: Theme.font; font.pixelSize: seg.model.length > 3 ? 11 : 12; font.weight: Font.DemiBold
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: seg.picked(segItem.modelData.id) }
                }
            }
        }
    }

    // Głos: odszumianie i „wyraźny głos” (klip z dźwiękiem, muzyka, lektor)
    component VoiceTools: Column {
        width: parent ? parent.width : 0
        spacing: 10
        Label { text: "Odszumianie" }
        Segmented {
            model: [{ id: "0", name: "Wyłączone" }, { id: "1", name: "Lekkie" }, { id: "2", name: "Mocne" }]
            current: String(insp.info.denoise ?? 0)
            onPicked: (v) => Project.setValue(insp.selected, "denoise", Number(v))
        }
        Toggle {
            label: "Wyraźny głos"
            on: insp.info.clearVoice ?? false
            onToggled: Project.setValue(insp.selected, "clearVoice", !on)
        }
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: (insp.info.denoise ?? 0) === 2 ? "Usuwa szum, wiatr, wentylator i gwar w tle. Muzyka w tle też zniknie — zostaje sam głos."
                : (insp.info.denoise ?? 0) === 1 ? "Ścisza szum i hałas w tle, a głos zostaje naturalny."
                : "Szum w nagraniu? Włącz odszumianie — program zostawi sam głos."
            color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; lineHeight: 1.15
        }
    }

    // Włącz/wyłącz jako pigułka
    component Toggle: HoverButton {
        id: tg
        property string label
        property bool on: false
        signal toggled()
        width: tgRow.implicitWidth + 22; height: 28; radius: 14
        baseColor: on ? Theme.accent : Theme.fill
        color: on ? Theme.accent : (hovered ? Theme.hover : baseColor)
        onClicked: tg.toggled()
        Row {
            id: tgRow
            anchors.centerIn: parent
            spacing: 5
            Icon { visible: tg.on; anchors.verticalCenter: parent.verticalCenter; d: Icons.check; size: 12; stroke: 2.4; color: "white" }
            Text { anchors.verticalCenter: parent.verticalCenter; text: tg.label; color: tg.on ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
        }
    }

    // Filtr kolorów: miniatura klipu w tym filtrze
    component LookCard: Item {
        id: lc
        property var look
        property bool current: false
        signal clicked()
        height: width * 0.75 + 18
        Rectangle {
            id: lcBox
            width: parent.width; height: parent.width * 0.75
            radius: 8
            color: Theme.dark ? "#1B1D24" : "#E4E7EE"
            clip: true
            Image {
                anchors.fill: parent; anchors.margins: 2
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.height: 90
                source: insp.kind === "clip" ? Project.thumb(insp.info.path, (insp.info.in ?? 0) + Math.round((insp.info.out - insp.info.in) / 3 / 10) * 10, lc.look.id) : ""
            }
            Rectangle {
                anchors.fill: parent; radius: 8
                color: "transparent"
                border.width: lc.current ? 2 : (lcArea.containsMouse ? 1 : 0)
                border.color: lc.current ? Theme.accent : Theme.line
            }
        }
        Text {
            y: lcBox.height + 3
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: lc.look.name
            elide: Text.ElideRight
            color: lc.current ? Theme.accentText : Theme.text2
            font.family: Theme.font; font.pixelSize: 10; font.weight: lc.current ? Font.DemiBold : Font.Normal
        }
        MouseArea { id: lcArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lc.clicked() }
    }

    // Suwak wartości z punktem neutralnym (przyciąga się do niego)
    component ValueSlider: Item {
        id: vsl
        property string label
        property real from: 0
        property real to: 1
        property real neutral: 0
        property real value: 0
        property string unit: ""             // "" — różnica od punktu neutralnego, "%" — procent, "°" — stopnie
        property real step: 0.01
        signal moved(real value)
        width: parent ? parent.width : 0; height: 26
        readonly property real shown: sArea.pressed ? sArea.dragValue : value
        readonly property real frac: (shown - from) / (to - from)
        Text { width: 70; anchors.verticalCenter: parent.verticalCenter; text: vsl.label; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
        Item {
            id: sTrack
            x: 72; width: parent.width - 72 - 40; height: parent.height
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Theme.fill }
            Rectangle {
                readonly property real n: (vsl.neutral - vsl.from) / (vsl.to - vsl.from)
                x: parent.width * Math.min(n, vsl.frac)
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * Math.abs(vsl.frac - n); height: 4; radius: 2
                color: Theme.accent
            }
            Rectangle {
                x: parent.width * (vsl.neutral - vsl.from) / (vsl.to - vsl.from) - 0.5
                anchors.verticalCenter: parent.verticalCenter
                width: 1; height: 10; color: Theme.text2; opacity: 0.5
            }
            Rectangle {
                x: parent.width * vsl.frac - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 16; height: 16; radius: 8
                color: "white"
                border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15)
            }
            MouseArea {
                id: sArea
                anchors.fill: parent
                anchors.margins: -4
                preventStealing: true
                property real dragValue: 0
                function valueAt(x) {
                    let v = vsl.from + Math.max(0, Math.min(1, (x - 4) / sTrack.width)) * (vsl.to - vsl.from);
                    if (Math.abs(v - vsl.neutral) < (vsl.to - vsl.from) * 0.03) v = vsl.neutral;
                    return Math.round(v / vsl.step) * vsl.step;
                }
                onPressed: (e) => { dragValue = valueAt(e.x); vsl.moved(dragValue); }
                onPositionChanged: (e) => { dragValue = valueAt(e.x); vsl.moved(dragValue); }
                onDoubleClicked: vsl.moved(vsl.neutral)
            }
        }
        Text {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: vsl.unit === "%" ? Math.round(vsl.shown * 100) + "%"
                  : vsl.unit === "°" ? Math.round(vsl.shown) + "°"
                  : (vsl.shown - vsl.neutral > 0.005 ? "+" : "") + Math.round((vsl.shown - vsl.neutral) * 100)
            color: Theme.text
            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium; font.features: { "tnum": 1 }
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
