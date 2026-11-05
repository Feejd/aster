pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Aster.Ui
import Aster.Grafika

// Grafika Aster: szybkie grafiki bez internetu — posty, relacje, plakaty, zaproszenia, CV, miniaturki, slajdy.
// Ekran startowy (rozmiary, szablony, własne projekty) i edytor (płótno z warstwami, panel po lewej, właściwości po prawej).
// Projekty zapisują się same w Dokumenty/Grafiki; eksport do PNG, JPG i PDF.
Window {
    id: win
    width: 1320 + 2 * m
    height: 840 + 2 * m
    minimumWidth: 980 + 2 * m
    minimumHeight: 620 + 2 * m
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: editing ? project.name + " — Grafika" : "Grafika"

    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    readonly property int m: maxed ? 0 : 26
    readonly property real r: visibility === Window.FullScreen ? 0 : 24
    property bool editing: false

    // Gotowe rozmiary; print — wymiary do druku w mm (PDF ma wtedy dokładnie ten format)
    // group: social | print | screen — kolor i kategoria na ekranie startowym
    readonly property var presets: [
        { id: "post", name: "Post kwadratowy", hint: "Instagram, Facebook", w: 1080, h: 1080, group: "social", icon: "image" },
        { id: "portrait", name: "Post pionowy", hint: "Instagram 4:5", w: 1080, h: 1350, group: "social", icon: "image" },
        { id: "story", name: "Relacja", hint: "Story, Reels, TikTok", w: 1080, h: 1920, group: "social", icon: "phone" },
        { id: "fbcover", name: "Okładka Facebook", hint: "Profil, strona", w: 1640, h: 624, group: "social", icon: "user" },
        { id: "youtube", name: "Miniaturka YouTube", hint: "Okładka filmu", w: 1280, h: 720, group: "screen", icon: "play" },
        { id: "slide", name: "Slajd 16:9", hint: "Prezentacja", w: 1920, h: 1080, group: "screen", icon: "layout" },
        { id: "a4", name: "A4 pionowo", hint: "Ulotka, CV, zaproszenie", w: 2480, h: 3508, print: { width: 210, height: 297 }, group: "print", icon: "doc" },
        { id: "a4l", name: "A4 poziomo", hint: "Dyplom, ogłoszenie", w: 3508, h: 2480, print: { width: 297, height: 210 }, group: "print", icon: "doc" },
        { id: "a5", name: "Ulotka A5", hint: "Ulotka, zaproszenie", w: 1748, h: 2480, print: { width: 148, height: 210 }, group: "print", icon: "news" },
        { id: "poster", name: "Plakat A3", hint: "Do druku", w: 3508, h: 4961, print: { width: 297, height: 420 }, group: "print", icon: "news" },
        { id: "card", name: "Kartka A6", hint: "Życzenia, podziękowanie", w: 1748, h: 1240, print: { width: 148, height: 105 }, group: "print", icon: "mail" },
        { id: "bcard", name: "Wizytówka", hint: "Firma, kontakt", w: 1063, h: 591, print: { width: 90, height: 50 }, group: "print", icon: "user" }
    ]

    Project {
        id: project
        onError: (message) => win.toast(message, "")
        onChanged: if (win.editing) saveTimer.restart()
    }

    // ——— Projekty ———
    function newProject(p) {
        project.create(p.w, p.h, p.name, p.print || {});
        editing = true;
    }
    function newCustom(w, h) {
        project.create(Math.round(w), Math.round(h), "Własny rozmiar", {});
        editing = true;
    }
    function fromTemplate(file) {
        if (project.openTemplate(file)) editing = true;
    }
    function openProject(path) {
        if (!project.open(String(path))) return;
        Library.reloadFonts();              // czcionki dołączone do projektu
        Library.addRecent(project.path);
        editing = true;
    }
    function saveNow() {
        saveTimer.stop();
        if (!project.modified) return;
        if (project.save()) Library.addRecent(project.path);
    }
    function goHome() {
        saveNow();
        Library.refresh();
        editing = false;
    }
    onClosing: saveNow()

    Timer { id: saveTimer; interval: 1500; onTriggered: win.saveNow() }

    function toast(text, path) { toastBox.text = text; toastBox.path = path; toastBox.shown = true; toastTimer.restart(); }

    // Do testów (ASTER_OPEN): new:<rozmiar> | template:<nr> | select:<nr> | edit | tab:<karta> | export | exportfile:<format> |
    // color | font | menu | home | custom | addtext | addshape:<kształt> | rotate:<stopnie> | image:<plik> | undo | dark |
    // selectmany:<nr,nr> | selectall | crop | set:<JSON zmian> | align:<jak> | dup
    function testOpen(what) {
        const [cmd, arg] = what.split(":");
        if (cmd === "new") { for (const p of presets) if (p.id === arg) newProject(p); }
        else if (cmd === "template") fromTemplate(Library.templates[Number(arg)].file);
        else if (cmd === "home") goHome();
        else if (cmd === "custom") start.openCustom();
        else if (cmd === "open") openProject(what.substring(5));
        else if (cmd === "exportall") {
            // Każdy szablon do /tmp/szablon-NN.png (dłuższy bok 900 px) — do obejrzenia wszystkich naraz
            const list = Library.templates;
            for (let i = 0; i < list.length; ++i) {
                project.openTemplate(list[i].file);
                project.exportFile("png", 900 / Math.max(project.pageWidth, project.pageHeight), "/tmp/szablon-" + (i < 9 ? "0" : "") + (i + 1) + ".png");
            }
        }
        else editor.testOpen(cmd, arg === undefined ? "" : what.substring(cmd.length + 1));
    }

    // ——— Okno ———
    function updateEffects() {
        WindowEffects.setBlur(win, Qt.rect(m, m, frame.width, frame.height), r);
        WindowEffects.setInputRegion(win, Qt.rect(Math.max(0, m - 6), Math.max(0, m - 6), frame.width + (maxed ? 0 : 12), frame.height + (maxed ? 0 : 12)));
    }
    Component.onCompleted: effectsTimer.restart()
    onWidthChanged: effectsTimer.restart()
    onHeightChanged: effectsTimer.restart()
    onMaxedChanged: effectsTimer.restart()
    Timer { id: effectsTimer; interval: 16; onTriggered: win.updateEffects() }

    WindowShadow { window: win; frame: frame; radius: win.r; visible: !win.maxed }
    ResizeHandles { window: win; frame: frame; margin: win.m }

    Rectangle {
        id: frame
        x: win.m; y: win.m
        width: win.width - 2 * win.m
        height: win.height - 2 * win.m
        radius: win.r
        color: Theme.windowGlass
        border.width: win.maxed ? 0 : 1
        border.color: Theme.edge
        WindowSheen { window: win; radius: win.r }

        StartPage {
            id: start
            anchors.fill: parent
            visible: !win.editing
            app: win
            radius: win.r
        }
        EditorPage {
            id: editor
            anchors.fill: parent
            visible: win.editing
            project: project
            app: win
            radius: win.r
        }

        // Komunikat (z „Otwórz” i „Pokaż w folderze” po eksporcie)
        Rectangle {
            id: toastBox
            property bool shown: false
            property string path
            property alias text: toastText.text
            anchors.horizontalCenter: parent.horizontalCenter
            y: shown ? 70 : -height - 10
            opacity: shown ? 1 : 0
            z: 600
            width: Math.min(parent.width - 60, toastRow.implicitWidth + 36); height: 40; radius: 20
            color: Theme.dark ? "#ECEEF3" : "#1E2027"
            Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Row {
                id: toastRow
                anchors.centerIn: parent
                spacing: 14
                Text {
                    id: toastText
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, toastBox.parent.width - 300)
                    elide: Text.ElideMiddle
                    color: Theme.dark ? "#16181D" : "white"; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
                }
                Repeater {
                    model: toastBox.path ? [{ t: "Otwórz", a: "open" }, { t: "Pokaż w folderze", a: "show" }] : []
                    delegate: Text {
                        id: toastLink
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.t
                        color: Theme.dark ? Qt.darker(Theme.accent, 1.2) : Qt.lighter(Theme.accent, 1.5)
                        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -8
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                toastBox.shown = false;
                                if (toastLink.modelData.a === "open") Library.open(toastBox.path); else Library.showInFolder(toastBox.path);
                            }
                        }
                    }
                }
            }
            Timer { id: toastTimer; interval: 6000; onTriggered: toastBox.shown = false }
        }
    }
}
