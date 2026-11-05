pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import Aster.Ui
import Aster.Montaz

// Okno eksportu: jakość, miejsce zapisu, postęp. Gdy w systemie nie ma kodera H.264
// (Fedora bez RPM Fusion i bez OpenH264), film zapisuje się jako WebM — i mówimy o tym wprost.
Item {
    id: sheet
    property bool shown: false
    readonly property bool running: Exporter.running
    property int quality: 1
    property string path
    signal toast(string text)

    visible: opacity > 0
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    function open() {
        Exporter.detect();
        if (!Exporter.running) Exporter.reset();
        path = Exporter.codec ? Exporter.suggestedPath() : "";
        shown = true;
    }
    function sizeText(q, format) {      // format — żeby napis odświeżał się po zmianie projektu
        const s = Exporter.size(q);
        return format ? s.width + "×" + s.height : "";
    }
    // Do testów: eksport, gdy tylko wiadomo, jaki koder jest dostępny
    property string pendingPath
    function startWhenReady(p) {
        if (Exporter.codec) Exporter.start(p, quality);
        else pendingPath = p;
    }
    function close() { if (!Exporter.running) shown = false; }

    Connections {
        target: Exporter
        function onCodecChanged() {
            if (!sheet.path || !Exporter.running) sheet.path = Exporter.suggestedPath();
            if (sheet.pendingPath) { Exporter.start(sheet.pendingPath, sheet.quality); sheet.pendingPath = ""; }
        }
        function onStateChanged() { if (Exporter.finished && !sheet.shown) sheet.toast("Film zapisany"); }
    }

    FileDialog {
        id: saveDialog
        title: "Zapisz film jako"
        fileMode: FileDialog.SaveFile
        currentFolder: "file://" + sheet.path.substring(0, sheet.path.lastIndexOf("/"))
        selectedFile: "file://" + sheet.path
        nameFilters: Exporter.codec === "vp9" ? ["Film WebM (*.webm)"] : ["Film MP4 (*.mp4)"]
        onAccepted: {
            let p = Project.toPath(String(selectedFile));
            if (!p.toLowerCase().endsWith("." + Exporter.extension())) p += "." + Exporter.extension();
            sheet.path = p;
        }
    }

    MouseArea { anchors.fill: parent; onClicked: sheet.close(); onWheel: {} }
    Rectangle { anchors.fill: parent; radius: 12; color: Qt.rgba(0, 0, 0, 0.4) }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 460
        height: content.implicitHeight + 44
        radius: 10
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

            Text {
                text: Exporter.finished ? "Gotowe!" : Exporter.running ? "Zapisuję film…" : "Eksportuj film"
                color: Theme.text
                font.family: Theme.font; font.pixelSize: 19; font.weight: Font.Bold
            }

            // ——— Ustawienia ———
            Column {
                visible: !Exporter.running && !Exporter.finished
                width: parent.width
                spacing: 14

                Text {
                    text: "Jakość"
                    color: Theme.text2
                    font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; font.capitalization: Font.AllUppercase
                }
                Column {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: [
                            { q: 0, title: "Mniejszy plik", detail: "720p — szybciej się wysyła" },
                            { q: 1, title: "Wysoka", detail: "1080p — polecana do TikToka, Reels i YouTube" },
                            { q: 2, title: "Najwyższa", detail: "1080p — większy plik, dłuższy zapis" }
                        ]
                        delegate: HoverButton {
                            id: opt
                            required property var modelData
                            readonly property bool on: sheet.quality === modelData.q
                            width: content.width; height: 50; radius: 12
                            baseColor: on ? Theme.accentSoft : Theme.fill
                            border.width: on ? 1.5 : 0
                            border.color: Theme.accent
                            onClicked: sheet.quality = modelData.q
                            Column {
                                x: 14; anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text {
                                    text: opt.modelData.title + "  ·  " + sheet.sizeText(opt.modelData.q, Project.format)
                                    color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                                }
                                Text { text: opt.modelData.detail; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12 }
                            }
                            Icon { visible: opt.on; anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter; d: Icons.check; size: 18; stroke: 2.2; color: Theme.accentText }
                        }
                    }
                }

                // Format pliku
                Rectangle {
                    width: parent.width
                    height: fmtCol.implicitHeight + 20
                    radius: 12
                    color: Exporter.codec === "vp9" ? (Theme.dark ? Qt.rgba(1, 0.75, 0.2, 0.12) : "#FFF6E0") : Theme.fill
                    Row {
                        x: 12; y: 10
                        spacing: 10
                        Icon {
                            d: Exporter.codec === "vp9" ? Icons.info : Icons.film
                            size: 18; color: Exporter.codec === "vp9" ? (Theme.dark ? "#FFC857" : "#B07800") : Theme.text2
                        }
                        Column {
                            id: fmtCol
                            width: content.width - 52
                            spacing: 3
                            Text {
                                width: parent.width
                                text: Exporter.codec === "" ? "Sprawdzam dostępne kodery…"
                                      : Exporter.codec === "h264" ? "MP4 (H.264 i AAC)" : "WebM (VP9 i Opus)"
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                            }
                            Text {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                lineHeight: 1.25
                                text: Exporter.codec === "h264" ? "Odtworzy się wszędzie — w telefonie, na TikToku, Instagramie i YouTube."
                                      : Exporter.codec === "vp9" ? "W tym systemie nie ma kodera H.264, więc film zapiszę jako WebM. Działa na YouTube, w przeglądarkach i większości odtwarzaczy, ale TikTok i Instagram mogą go nie przyjąć. Żeby zapisywać MP4, zainstaluj kodeki multimediów (np. z RPM Fusion albo OpenH264 od Cisco)."
                                      : ""
                                visible: text !== ""
                                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                            }
                        }
                    }
                }

                // Miejsce zapisu
                Item {
                    width: parent.width; height: 34
                    Text {
                        anchors.left: parent.left; anchors.right: changeBtn.left; anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: sheet.path ? "Zapisz w: " + sheet.path.replace(/^\/home\/[^/]+|^\/root/, "~") : ""
                        elide: Text.ElideMiddle
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                    }
                    HoverButton {
                        id: changeBtn
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: changeText.implicitWidth + 20; height: 30
                        baseColor: Theme.fill
                        enabled: Exporter.codec !== ""
                        onClicked: saveDialog.open()
                        Text { id: changeText; anchors.centerIn: parent; text: "Zmień…"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
                    }
                }
                Text {
                    visible: Exporter.error !== ""
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: Exporter.error
                    color: Theme.danger; font.family: Theme.font; font.pixelSize: 12
                }
            }

            // ——— Postęp ———
            Column {
                visible: Exporter.running
                width: parent.width
                spacing: 8
                Rectangle {
                    width: parent.width; height: 8; radius: 4
                    color: Theme.fill
                    Rectangle { width: parent.width * Exporter.progress; height: parent.height; radius: 4; color: Theme.accent; Behavior on width { NumberAnimation { duration: 180 } } }
                }
                Item {
                    width: parent.width; height: 18
                    Text { text: Math.round(Exporter.progress * 100) + "%"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; font.features: { "tnum": 1 } }
                    Text {
                        anchors.right: parent.right
                        text: Exporter.secondsLeft < 0 ? "Liczę pozostały czas…"
                              : Exporter.secondsLeft < 60 ? "Zostało ok. " + Math.max(1, Exporter.secondsLeft) + " s"
                              : "Zostało ok. " + Math.round(Exporter.secondsLeft / 60) + " min"
                        color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                    }
                }
                Text {
                    width: parent.width
                    text: Exporter.output.split("/").pop()
                    elide: Text.ElideMiddle
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
                }
            }

            // ——— Zakończono ———
            Column {
                visible: Exporter.finished
                width: parent.width
                spacing: 8
                Row {
                    spacing: 10
                    Rectangle {
                        width: 34; height: 34; radius: 17
                        color: "#24A57E"
                        Icon { anchors.centerIn: parent; d: Icons.check; size: 18; stroke: 2.4; color: "white" }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: content.width - 50
                        text: "Film zapisany: " + Exporter.output.split("/").pop()
                        elide: Text.ElideMiddle
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13
                    }
                }
            }

            // ——— Przyciski ———
            Item {
                width: parent.width; height: 38
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    SheetButton {
                        label: Exporter.running ? "Przerwij" : Exporter.finished ? "Zamknij" : "Anuluj"
                        onClicked: { if (Exporter.running) Exporter.cancel(); else sheet.shown = false; }
                    }
                    SheetButton {
                        visible: Exporter.finished
                        label: "Pokaż w folderze"
                        onClicked: Project.showInFolder(Exporter.output)
                    }
                    SheetButton {
                        visible: !Exporter.running && !Exporter.finished
                        primary: true
                        enabled: Exporter.codec !== "" && sheet.path !== "" && Project.duration > 0
                        label: "Eksportuj"
                        onClicked: Exporter.start(sheet.path, sheet.quality)
                    }
                }
            }
        }
    }

    component SheetButton: HoverButton {
        id: sb
        property string label
        property bool primary: false
        width: sbText.implicitWidth + 32; height: 36; radius: 10
        baseColor: primary ? Theme.accent : Theme.fill
        color: primary ? (hovered ? Qt.lighter(Theme.accent, 1.12) : Theme.accent) : (hovered ? Theme.hover : baseColor)
        opacity: enabled ? 1 : 0.45
        Text { id: sbText; anchors.centerIn: parent; text: sb.label; color: sb.primary ? "white" : Theme.text; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
    }
}
