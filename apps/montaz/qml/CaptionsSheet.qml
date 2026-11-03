pragma ComponentBehavior: Bound
import QtQuick
import Aster.Ui
import Aster.Montaz

// Napisy z mowy: wybór modelu (pobieranego raz), języka i stylu, potem postęp słuchania.
// Rozpoznawanie działa na tym komputerze (whisper.cpp) — nagrania nigdzie nie wychodzą.
Item {
    id: sheet
    property bool shown: false
    property string model: "small"
    property string language: "pl"
    property string style: "klasyczny"
    property string anim: "karaoke"
    readonly property bool busy: Captions.state === "downloading" || Captions.state === "listening"
    readonly property bool hasCaptions: Project.texts.some(t => t.caption)
    signal toast(string text)

    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    function open() {
        Captions.reset();
        // Domyślnie model, który już jest na dysku
        const ready = Captions.models.filter(m => m.ready);
        if (ready.length > 0 && !Captions.models.find(m => m.id === model).ready) model = ready[0].id;
        shown = true;
    }
    function close() { if (!busy) shown = false; }

    Connections {
        target: Captions
        function onStateChanged() {
            if (Captions.state === "done" && Captions.added > 0) {
                sheet.toast("Dodano napisy: " + Captions.added);
                sheet.shown = false;
            }
        }
    }

    MouseArea { anchors.fill: parent; onClicked: sheet.close(); onWheel: {} }
    Rectangle { anchors.fill: parent; radius: 24; color: Qt.rgba(0, 0, 0, 0.4) }

    Rectangle {
        anchors.centerIn: parent
        width: 460
        height: content.implicitHeight + 44
        radius: 18
        color: Theme.surface
        border.width: 1; border.color: Theme.edge
        scale: sheet.shown ? 1 : 0.96
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutQuad } }
        MouseArea { anchors.fill: parent }

        Column {
            id: content
            x: 24; y: 22
            width: parent.width - 48
            spacing: 14

            Row {
                spacing: 10
                Rectangle {
                    width: 34; height: 34; radius: 10
                    color: Theme.accentSoft
                    Icon { anchors.centerIn: parent; d: Icons.captions; size: 18; color: Theme.accentText }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Captions.state === "downloading" ? "Pobieram model mowy…"
                          : Captions.state === "listening" ? "Słucham filmów…" : "Napisy z mowy"
                    color: Theme.text
                    font.family: Theme.font; font.pixelSize: 19; font.weight: Font.Bold
                }
            }

            // ——— Ustawienia ———
            Column {
                visible: !sheet.busy
                width: parent.width
                spacing: 12
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    lineHeight: 1.25
                    text: "Montaż wysłucha filmów na osi czasu i sam doda krótkie napisy. Wszystko dzieje się na tym komputerze — nagrania nigdzie nie są wysyłane."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
                Repeater {
                    model: Captions.models
                    delegate: HoverButton {
                        id: opt
                        required property var modelData
                        readonly property bool on: sheet.model === modelData.id
                        width: content.width; height: 50; radius: 12
                        baseColor: on ? Theme.accentSoft : Theme.fill
                        border.width: on ? 1.5 : 0
                        border.color: Theme.accent
                        onClicked: sheet.model = modelData.id
                        Column {
                            x: 14; anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text { text: opt.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text {
                                text: opt.modelData.ready ? "Pobrany — gotowy do pracy" : opt.modelData.detail
                                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                            }
                        }
                        Icon { visible: opt.on; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; d: Icons.check; size: 18; stroke: 2.2; color: Theme.accentText }
                    }
                }
                Text { text: "Język"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase }
                Pills {
                    model: [{ id: "pl", name: "Polski" }, { id: "en", name: "Angielski" }, { id: "auto", name: "Wykryj sam" }]
                    current: sheet.language
                    onPicked: (v) => sheet.language = v
                }
                Text { text: "Wygląd napisów"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase }
                Pills {
                    model: Project.textStyles.filter(s => s.place !== "top")
                    current: sheet.style
                    onPicked: (v) => sheet.style = v
                }
                Text { text: "Ruch napisów"; color: Theme.text2; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase }
                Pills {
                    model: [{ id: "brak", name: "Zwykłe" }, { id: "karaoke", name: "Karaoke" }, { id: "ramka", name: "Ramka słowa" },
                            { id: "slowo", name: "Słowo po słowie" }, { id: "narastanie", name: "Narastanie" }]
                    current: sheet.anim
                    onPicked: (v) => sheet.anim = v
                }
                Text {
                    visible: sheet.anim !== "brak"
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: sheet.anim === "karaoke" ? "Słowo, które właśnie pada, zmienia kolor — jak w karaoke."
                          : sheet.anim === "ramka" ? "Wypowiadane słowo dostaje kolorową ramkę."
                          : sheet.anim === "slowo" ? "Na ekranie zawsze jedno słowo — duże i wyraźne."
                          : "Słowa dopisują się na bieżąco, w rytm mowy."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
                Text {
                    visible: sheet.hasCaptions
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Poprzednie napisy z mowy zostaną zastąpione nowymi. Twoje własne napisy zostają."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
            }

            // ——— Postęp ———
            Column {
                visible: sheet.busy
                width: parent.width
                spacing: 8
                Rectangle {
                    width: parent.width; height: 8; radius: 4
                    color: Theme.fill
                    Rectangle { width: parent.width * Captions.progress; height: parent.height; radius: 4; color: Theme.accent; Behavior on width { NumberAnimation { duration: 180 } } }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Math.round(Captions.progress * 100) + "%  ·  "
                          + (Captions.state === "downloading" ? "model pobiera się tylko raz" : "to może potrwać mniej więcej tyle, ile trwa film")
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
            }

            Text {
                visible: Captions.error !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: Captions.error
                color: Theme.danger; font.family: Theme.font; font.pixelSize: 12
            }

            Item {
                width: parent.width; height: 38
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    SheetButton {
                        label: sheet.busy ? "Przerwij" : "Anuluj"
                        onClicked: { if (sheet.busy) Captions.cancel(); else sheet.shown = false; }
                    }
                    SheetButton {
                        visible: !sheet.busy
                        primary: true
                        enabled: Project.clips.length > 0
                        label: Captions.models.find(m => m.id === sheet.model).ready ? "Utwórz napisy" : "Pobierz i utwórz"
                        onClicked: Captions.start(sheet.model, sheet.language, sheet.style, sheet.anim)
                    }
                }
            }
        }
    }

    component Pills: Flow {
        id: pills
        property var model: []
        property string current
        signal picked(string value)
        width: parent ? parent.width : 0
        spacing: 6
        Repeater {
            model: pills.model
            delegate: HoverButton {
                id: pill
                required property var modelData
                readonly property bool on: pills.current === modelData.id
                width: pillText.implicitWidth + 20; height: 28; radius: 14
                baseColor: on ? Theme.accent : Theme.fill
                color: on ? Theme.accent : (hovered ? Theme.hover : baseColor)
                onClicked: pills.picked(modelData.id)
                Text {
                    id: pillText
                    anchors.centerIn: parent
                    text: pill.modelData.name
                    color: pill.on ? "white" : Theme.text
                    font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                }
            }
        }
    }

    component SheetButton: HoverButton {
        id: sb
        property string label
        property bool primary: false
        width: sbText.implicitWidth + 32; height: 36; radius: 18
        baseColor: primary ? Theme.accent : Theme.fill
        color: primary ? (hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent) : (hovered ? Theme.hover : baseColor)
        opacity: enabled ? 1 : 0.45
        Text { id: sbText; anchors.centerIn: parent; text: sb.label; color: sb.primary ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
    }
}
