pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Dialogs
import QtCore
import Aster.Ui
import Aster.Grafika

// Edytor: panel po lewej (Szablony, Tekst, Kształty, Zdjęcia, Tło), płótno, właściwości po prawej,
// pasek z nazwą projektu, cofaniem, powiększeniem i eksportem. Skróty jak w programach biurowych.
Item {
    id: ed
    required property Project project
    property var app                 // Main: toast, goHome, presets
    property real radius: 24
    readonly property real sideWidth: 72 + 272

    // Pisanie w polu tekstowym — wtedy Delete, strzałki i Ctrl+Z należą do pola
    readonly property bool typing: {
        const f = Window.activeFocusItem;
        return f !== null && (f instanceof TextInput || f instanceof TextEdit);
    }
    readonly property bool active: visible && !colorPop.shown && !fontPop.shown && !exportPop.shown
    readonly property string sel: stage.selected
    readonly property var many: stage.selection           // zaznaczone (jeden albo kilka)

    onVisibleChanged: if (visible) { stage.clearSelection(); stage.fit = true; side.tab = "templates"; stage.forceActiveFocus(); }

    // ——— Działania ———
    function addElement(el) {
        stage.stopEditing();
        stage.select(project.add(el));
        stage.forceActiveFocus();
    }
    function addImageKey(key) {
        const s = project.imageSize(key);
        if (s.width <= 0) return;
        const k = Math.min(1, project.pageWidth * 0.6 / s.width, project.pageHeight * 0.6 / s.height);
        addElement({ type: "image", src: key, w: Math.round(s.width * k), h: Math.round(s.height * k) });
    }
    function addImageFile(url) {
        const key = project.importImage(String(url));
        if (key !== "") addImageKey(key);
    }
    function chooseImage(mode) {
        imageDialog.mode = mode;
        imageDialog.open();
    }
    // Zdjęcia upuszczone z Plików: jedno na ramkę ze zdjęciem (albo miejsce na zdjęcie) trafia do jej środka
    function dropImages(urls, x, y) {
        const p = mapToItem(stage, x, y);
        const target = urls.length === 1 ? stage.elementAt(p.x, p.y) : null;
        if (target && target.type === "image" && !target.locked) {
            const key = project.importImage(String(urls[0]));
            if (key === "") return;
            project.change(target.id, { src: key, focusX: null, focusY: null, zoom: null });
            stage.select(target.id);
            app.toast("Zdjęcie wstawione w ramkę — dwuklik, żeby wybrać kadr", "");
            return;
        }
        for (const u of urls) addImageFile(u);
    }
    function imageChosen(url, mode) {
        const key = project.importImage(String(url));
        if (key === "") return;
        if (mode === "background") {
            project.setBackground({ type: "image", src: key, color: project.background.color || "#ffffff" });
        } else if (mode === "replace" && sel !== "") {
            project.change(sel, { src: key });
        } else {
            addImageKey(key);
        }
    }
    function imageToBackground(id) {
        const el = project.get(id);
        project.setBackground({ type: "image", src: el.src, color: project.background.color || "#ffffff" }, false);
        project.remove(id);
    }
    function applyTemplate(file) {
        stage.clearSelection();
        if (project.applyTemplate(file)) app.toast("Wstawiono szablon — Ctrl+Z przywraca poprzednią stronę", "");
    }
    function pickColor(item, value, allowNone, fn) { colorPop.open(item, value, allowNone, fn, "left"); }
    function pickFont(item, family, fn) { fontPop.open(item, family, fn); }
    function showSizeMenu(item) {
        const items = [];
        for (const p of app.presets) items.push({ label: p.name, shortcut: p.w + "×" + p.h, action: "size:" + p.id });
        const pt = item.mapToItem(ed, 0, item.height + 6);
        menu.openAt(pt.x - 140, pt.y, items);
    }
    function nudge(dx, dy) {
        if (many.length === 0) return;
        for (const id of many) {
            const el = project.get(id);
            if (!el.locked) project.change(id, { x: el.x + dx, y: el.y + dy }, false);
        }
        project.commit();
    }
    function remove() {
        if (many.length === 0) return;
        const ids = many.filter(id => !project.get(id).locked);
        if (ids.length === 0) return;
        stage.clearSelection();
        project.removeAll(ids);
    }
    function copy() { if (many.length > 0) project.copy(many); }
    function paste() { const ids = project.paste(); if (ids.length > 0) stage.setSelection(ids); }
    function duplicate() { if (many.length > 0) stage.setSelection(project.duplicateAll(many)); }
    function arrange(how) { if (sel !== "") project.arrange(sel, how); }
    function setLocked(on) {
        for (const id of many) project.change(id, { locked: on ? true : null }, false);
        project.commit();
        stage.refresh();
    }
    // Kilka elementów: wyrównanie do wspólnego prostokąta i równe odstępy
    function alignMany(how) {
        const g = stage.group;
        if (g.w === undefined) return;
        const items = many.map(id => project.get(id)).filter(o => !o.locked);
        if (how === "spreadH" || how === "spreadV") {
            const hz = how === "spreadH";
            const boxes = items.map(o => ({ o: o, b: stage.box(o, o.x, o.y) }));
            boxes.sort((a, b) => hz ? a.b.xs[0] - b.b.xs[0] : a.b.ys[0] - b.b.ys[0]);
            if (boxes.length < 3) return;
            let total = 0;
            for (const it of boxes) total += hz ? it.b.xs[2] - it.b.xs[0] : it.b.ys[2] - it.b.ys[0];
            const gap = ((hz ? g.w : g.h) - total) / (boxes.length - 1);
            let at = hz ? g.x : g.y;
            for (const it of boxes) {
                const size = hz ? it.b.xs[2] - it.b.xs[0] : it.b.ys[2] - it.b.ys[0];
                const shift = at - (hz ? it.b.xs[0] : it.b.ys[0]);
                const patch = hz ? { x: Math.round((it.o.x + shift) * 10) / 10 } : { y: Math.round((it.o.y + shift) * 10) / 10 };
                project.change(it.o.id, patch, false);
                at += size + gap;
            }
        } else {
            for (const o of items) {
                const b = stage.box(o, o.x, o.y);
                let d = 0, hz = true;
                if (how === "left") d = g.x - b.xs[0];
                else if (how === "hcenter") d = g.x + g.w / 2 - b.xs[1];
                else if (how === "right") d = g.x + g.w - b.xs[2];
                else { hz = false; d = how === "top" ? g.y - b.ys[0] : how === "vcenter" ? g.y + g.h / 2 - b.ys[1] : g.y + g.h - b.ys[2]; }
                project.change(o.id, hz ? { x: Math.round((o.x + d) * 10) / 10 } : { y: Math.round((o.y + d) * 10) / 10 }, false);
            }
        }
        project.commit();
    }
    function selectLayer(id, additive) {
        if (project.get(id).hidden) return;
        if (additive) stage.toggle(id); else stage.select(id);
        stage.forceActiveFocus();
    }
    function setHidden(id, on) {
        if (on && stage.isSelected(id)) stage.setSelection(many.filter(i => i !== id));
        project.change(id, { hidden: on ? true : null });
    }
    function copyImage() {
        exportPop.close();
        if (project.copyImage()) app.toast("Skopiowano grafikę — wklej ją w wiadomości (Ctrl+V)", "");
    }
    function exportNow(format, scale) {
        exportPop.close();
        const path = project.exportFile(format, scale, "");
        if (path !== "") app.toast("Zapisano „" + path.split("/").pop() + "”", path);
    }

    function runMenu(a) {
        if (a.startsWith("size:")) {
            for (const p of app.presets) if (p.id === a.substring(5)) project.setPageSize(p.w, p.h);
            stage.fit = true;
        } else if (a === "copy") copy();
        else if (a === "cut") { copy(); remove(); }
        else if (a === "paste") paste();
        else if (a === "duplicate") duplicate();
        else if (a === "edit") stage.startEditing(sel);
        else if (a === "crop") stage.cropping = sel;
        else if (a === "flip") project.change(sel, { flipX: stage.current.flipX ? null : true });
        else if (a === "background") imageToBackground(sel);
        else if (a === "bgtab") side.tab = "background";
        else if (a === "layers") side.tab = "layers";
        else if (a === "selectAll") stage.selectAll();
        else if (a === "lock") setLocked(true);
        else if (a === "unlock") setLocked(false);
        else if (a === "remove") remove();
        else arrange(a);
    }
    function showContextMenu(x, y) {
        const items = [];
        if (many.length > 1) {
            items.push({ label: "Kopiuj", icon: "copy", shortcut: "Ctrl+C", action: "copy" });
            items.push({ label: "Wytnij", icon: "scissors", shortcut: "Ctrl+X", action: "cut" });
            items.push({ label: "Duplikuj", icon: "copy", shortcut: "Ctrl+D", action: "duplicate" });
            items.push({ label: "Zablokuj", icon: "lock", action: "lock" });
            items.push({ separator: true });
            items.push({ label: "Usuń zaznaczone (" + many.length + ")", icon: "trash", shortcut: "Delete", action: "remove", danger: true });
        } else if (sel !== "" && stage.current.locked) {
            items.push({ label: "Odblokuj", icon: "unlock", action: "unlock" });
            items.push({ label: "Kopiuj", icon: "copy", shortcut: "Ctrl+C", action: "copy" });
            items.push({ label: "Duplikuj", icon: "copy", shortcut: "Ctrl+D", action: "duplicate" });
            items.push({ label: "Warstwy", icon: "layers", action: "layers" });
        } else if (sel !== "") {
            const el = stage.current;
            if (el.type === "text") items.push({ label: "Edytuj tekst", icon: "pencil", shortcut: "Enter", action: "edit" });
            if (el.type === "image" && el.src) items.push({ label: "Kadruj", icon: "crop", shortcut: "dwuklik", action: "crop" });
            if (el.type === "image") items.push({ label: "Odbij w poziomie", icon: "mirror", action: "flip" });
            items.push({ label: "Kopiuj", icon: "copy", shortcut: "Ctrl+C", action: "copy" });
            items.push({ label: "Wytnij", icon: "scissors", shortcut: "Ctrl+X", action: "cut" });
            items.push({ label: "Wklej", icon: "paste", shortcut: "Ctrl+V", action: "paste" });
            items.push({ label: "Duplikuj", icon: "copy", shortcut: "Ctrl+D", action: "duplicate" });
            items.push({ separator: true });
            items.push({ label: "Na wierzch", icon: "bringFront", shortcut: "Ctrl+Shift+]", action: "front" });
            items.push({ label: "Do przodu", icon: "layerUp", shortcut: "Ctrl+]", action: "up" });
            items.push({ label: "Do tyłu", icon: "layerDown", shortcut: "Ctrl+[", action: "down" });
            items.push({ label: "Na spód", icon: "sendBack", shortcut: "Ctrl+Shift+[", action: "back" });
            if (el.type === "image") items.push({ label: "Ustaw jako tło", icon: "image", action: "background" });
            items.push({ label: "Zablokuj", icon: "lock", action: "lock" });
            items.push({ separator: true });
            items.push({ label: "Usuń", icon: "trash", shortcut: "Delete", action: "remove", danger: true });
        } else {
            items.push({ label: "Wklej", icon: "paste", shortcut: "Ctrl+V", action: "paste" });
            items.push({ label: "Zaznacz wszystko", icon: "check", shortcut: "Ctrl+A", action: "selectAll" });
            items.push({ label: "Zmień tło", icon: "palette", action: "bgtab" });
        }
        const p = stage.mapToItem(ed, x, y);
        menu.openAt(p.x, Math.min(p.y, ed.height - items.length * 34 - 20), items);
    }

    // Do testów (wołane z Main.testOpen)
    function testOpen(cmd, arg) {
        if (cmd === "select") stage.select(project.idAt(Number(arg)));
        else if (cmd === "selectmany") stage.setSelection(String(arg).split(",").map(i => project.idAt(Number(i))));
        else if (cmd === "selectall") stage.selectAll();
        else if (cmd === "crop") stage.cropping = sel;
        else if (cmd === "set") project.change(sel, JSON.parse(arg));
        else if (cmd === "align") alignMany(arg);
        else if (cmd === "dup") duplicate();
        else if (cmd === "edit") stage.startEditing(sel);
        else if (cmd === "tab") side.tab = arg;
        else if (cmd === "export") exportPop.openAt(exportBtn);
        else if (cmd === "exportfile") { const p = project.exportFile(arg, 1, "/tmp/grafika-test." + arg); app.toast("Zapisano „" + p.split("/").pop() + "”", p); }
        else if (cmd === "color") pickColor(inspector, stage.current.color || stage.current.fill || "#5B7CFA", false, () => {});
        else if (cmd === "font") pickFont(inspector, stage.current.font || "Geist", () => {});
        else if (cmd === "menu") showContextMenu(stage.width / 2, stage.height / 2);
        else if (cmd === "addtext") side.addTextStyle(side.textStyles[Number(arg) || 0]);
        else if (cmd === "addshape") { for (const s of side.shapes) if (s.label === arg || s.shape === arg) { side.addShape(s); break; } }
        else if (cmd === "rotate") project.change(sel, { rotation: Number(arg) });
        else if (cmd === "image") addImageFile(arg);
        else if (cmd === "undo") project.undo();
        else if (cmd === "zoom") stage.zoomTo(Number(arg));
    }

    // ——— Skróty ———
    Shortcut { sequences: [StandardKey.Undo]; enabled: ed.active && !ed.typing; onActivated: ed.project.undo() }
    Shortcut { sequences: [StandardKey.Redo, "Ctrl+Y"]; enabled: ed.active && !ed.typing; onActivated: ed.project.redo() }
    Shortcut { sequences: [StandardKey.Delete, "Backspace"]; enabled: ed.active && !ed.typing; onActivated: ed.remove() }
    Shortcut { sequences: [StandardKey.Copy]; enabled: ed.active && !ed.typing; onActivated: ed.copy() }
    Shortcut { sequences: [StandardKey.Cut]; enabled: ed.active && !ed.typing; onActivated: { ed.copy(); ed.remove(); } }
    Shortcut { sequences: [StandardKey.Paste]; enabled: ed.active && !ed.typing; onActivated: ed.paste() }
    Shortcut { sequence: "Ctrl+D"; enabled: ed.active && !ed.typing && ed.many.length > 0; onActivated: ed.duplicate() }
    Shortcut { sequences: [StandardKey.SelectAll]; enabled: ed.active && !ed.typing; onActivated: stage.selectAll() }
    Shortcut { sequence: "Ctrl+]"; enabled: ed.active && !ed.typing; onActivated: ed.arrange("up") }
    Shortcut { sequence: "Ctrl+["; enabled: ed.active && !ed.typing; onActivated: ed.arrange("down") }
    Shortcut { sequence: "Ctrl+Shift+]"; enabled: ed.active && !ed.typing; onActivated: ed.arrange("front") }
    Shortcut { sequence: "Ctrl+Shift+["; enabled: ed.active && !ed.typing; onActivated: ed.arrange("back") }
    Shortcut { sequence: "Left"; enabled: ed.active && !ed.typing; onActivated: ed.nudge(-1, 0) }
    Shortcut { sequence: "Right"; enabled: ed.active && !ed.typing; onActivated: ed.nudge(1, 0) }
    Shortcut { sequence: "Up"; enabled: ed.active && !ed.typing; onActivated: ed.nudge(0, -1) }
    Shortcut { sequence: "Down"; enabled: ed.active && !ed.typing; onActivated: ed.nudge(0, 1) }
    Shortcut { sequence: "Shift+Left"; enabled: ed.active && !ed.typing; onActivated: ed.nudge(-10, 0) }
    Shortcut { sequence: "Shift+Right"; enabled: ed.active && !ed.typing; onActivated: ed.nudge(10, 0) }
    Shortcut { sequence: "Shift+Up"; enabled: ed.active && !ed.typing; onActivated: ed.nudge(0, -10) }
    Shortcut { sequence: "Shift+Down"; enabled: ed.active && !ed.typing; onActivated: ed.nudge(0, 10) }
    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: ed.active && !ed.typing && ed.sel !== ""
        onActivated: {
            if (stage.cropping !== "") stage.cropping = "";
            else if (stage.current.type === "image" && stage.current.src && !stage.current.locked) stage.cropping = ed.sel;
            else stage.startEditing(ed.sel);
        }
    }
    Shortcut { sequence: "Escape"; enabled: ed.active && !ed.typing; onActivated: stage.cancel() }
    Shortcut { sequences: [StandardKey.Save]; enabled: ed.visible; onActivated: { ed.app.saveNow(); ed.app.toast("Zapisano w folderze Dokumenty/Grafiki", ed.project.path); } }
    Shortcut { sequence: "Ctrl+E"; enabled: ed.visible; onActivated: exportPop.openAt(exportBtn) }
    Shortcut { sequences: ["Ctrl+=", "Ctrl++", StandardKey.ZoomIn]; enabled: ed.visible; onActivated: stage.zoomBy(1.25) }
    Shortcut { sequences: ["Ctrl+-", StandardKey.ZoomOut]; enabled: ed.visible; onActivated: stage.zoomBy(0.8) }
    Shortcut { sequence: "Ctrl+0"; enabled: ed.visible; onActivated: stage.fit = true }
    Shortcut { sequence: "Ctrl+1"; enabled: ed.visible; onActivated: stage.zoomTo(1) }
    Shortcut { sequence: "T"; enabled: ed.active && !ed.typing; onActivated: side.addTextStyle(side.textStyles[2]) }

    FileDialog {
        id: imageDialog
        property string mode: "element"
        title: mode === "background" ? "Zdjęcie na tło" : "Dodaj zdjęcie"
        nameFilters: ["Zdjęcia (*.jpg *.jpeg *.png *.webp *.gif *.bmp *.tif *.tiff *.heic *.avif)", "Wszystkie pliki (*)"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        onAccepted: ed.imageChosen(selectedFile, mode)
    }
    FileDialog {
        id: exportDialog
        property string format: "png"
        property real scale: 1
        title: "Eksportuj jako"
        fileMode: FileDialog.SaveFile
        defaultSuffix: format
        selectedFile: "file:///" + ed.project.name + "." + format
        nameFilters: format === "pdf" ? ["Dokument PDF (*.pdf)"] : format === "jpg" ? ["Obraz JPG (*.jpg)"] : ["Obraz PNG (*.png)"]
        onAccepted: {
            const path = ed.project.exportFile(format, scale, String(selectedFile));
            if (path !== "") ed.app.toast("Zapisano „" + path.split("/").pop() + "”", path);
        }
    }

    // Zdjęcia przeciągnięte z Plików
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: (drop) => {
            ed.dropImages(drop.urls, drop.x, drop.y);
            drop.accept();
        }
    }

    // ——— Lewa strona: powrót i panel ———
    Item {
        id: sideTop
        width: ed.sideWidth; height: 60
        DragHandler { target: null; onActiveChanged: if (active) ed.Window.window.startSystemMove() }
        HoverButton {
            x: 14; anchors.verticalCenter: parent.verticalCenter
            width: homeRow.implicitWidth + 22; height: 36; radius: 18
            onClicked: ed.app.goHome()
            Row {
                id: homeRow
                anchors.centerIn: parent
                spacing: 8
                Icon { anchors.verticalCenter: parent.verticalCenter; d: Icons.back; size: 16; stroke: 2.2; color: Theme.text }
                AppIcon { anchors.verticalCenter: parent.verticalCenter; desktopId: "org.aster.grafika"; size: 24 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Projekty"; color: Theme.text; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
            }
        }
    }
    SidePanel {
        id: side
        y: sideTop.height
        width: ed.sideWidth
        height: parent.height - y
        project: ed.project
        editor: ed
    }

    // ——— Prawa strona: pasek, płótno, właściwości ———
    GlassPane {
        id: pane
        x: ed.sideWidth
        width: parent.width - x
        height: parent.height
        topRightRadius: ed.radius
        bottomRightRadius: ed.radius

        Item {
            id: bar
            width: parent.width; height: 60
            DragHandler { target: null; onActiveChanged: if (active) ed.Window.window.startSystemMove() }
            TapHandler { onDoubleTapped: { const w = ed.Window.window; if (w.visibility === Window.Maximized) w.showNormal(); else w.showMaximized(); } }

            // Nazwa projektu (do zmiany w miejscu)
            Rectangle {
                id: nameBox
                x: 18; anchors.verticalCenter: parent.verticalCenter
                width: Math.min(Math.max(140, nameInput.contentWidth + 24), parent.width - right.width - 220)
                height: 36; radius: 10
                color: nameInput.activeFocus ? Theme.fill : nameHover.hovered ? Theme.hover : "transparent"
                HoverHandler { id: nameHover; cursorShape: Qt.IBeamCursor }
                TextInput {
                    id: nameInput
                    x: 12; width: parent.width - 24
                    anchors.verticalCenter: parent.verticalCenter
                    text: ed.project.name
                    color: Theme.text
                    clip: true
                    selectByMouse: true
                    selectionColor: Theme.accent
                    font.family: Theme.font; font.pixelSize: 16; font.weight: Font.DemiBold
                    onAccepted: focus = false
                    onEditingFinished: ed.project.name = text
                    Keys.onEscapePressed: { text = ed.project.name; focus = false; }
                }
            }
            Text {
                anchors.left: nameBox.right; anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: ed.project.modified ? "Zmiany zapiszą się same" : ed.project.path !== "" ? "Zapisano" : ""
                color: Theme.text2; font.family: Theme.font; font.pixelSize: 12
            }

            Row {
                id: right
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "undo"; enabled: ed.project.canUndo; onClicked: ed.project.undo() }
                ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "redo"; enabled: ed.project.canRedo; onClicked: ed.project.redo() }
                Item { width: 8; height: 1 }
                ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "minus"; onClicked: stage.zoomBy(0.8) }
                HoverButton {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 58; height: 32
                    onClicked: { if (stage.fit) stage.zoomTo(1); else stage.fit = true; }
                    Text {
                        anchors.centerIn: parent
                        text: Math.round(stage.zoom * 100) + "%"
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 13; font.features: { "tnum": 1 }
                    }
                }
                ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "plus"; onClicked: stage.zoomBy(1.25) }
                Item { width: 8; height: 1 }
                Btn {
                    id: exportBtn
                    anchors.verticalCenter: parent.verticalCenter
                    primary: true
                    icon: "download"
                    text: "Eksportuj"
                    onClicked: exportPop.openAt(exportBtn)
                }
                Item { width: 6; height: 1 }
                WindowButtons { anchors.verticalCenter: parent.verticalCenter; window: ed.app }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        }

        Stage {
            id: stage
            y: bar.height
            width: parent.width - inspector.width
            height: parent.height - y
            project: ed.project
            onMenuRequested: (x, y) => ed.showContextMenu(x, y)
        }

        Rectangle {
            x: inspector.x; y: bar.height
            width: 1; height: inspector.height
            color: Theme.line
        }
        Inspector {
            id: inspector
            x: parent.width - width
            y: bar.height
            width: 290
            height: parent.height - y
            project: ed.project
            stage: stage
            editor: ed
        }
    }

    ContextMenu {
        id: menu
        onTriggered: (a) => ed.runMenu(a)
    }
    ColorPopup { id: colorPop; project: ed.project }
    FontPopup { id: fontPop }

    // ——— Eksport ———
    Popover {
        id: exportPop
        property string format: "png"
        property real size: 1           // mnożnik rozmiaru PNG/JPG
        cardWidth: 320
        Column {
            width: parent.width
            spacing: 14
            Text { text: "Eksportuj"; color: Theme.text; font.family: Theme.font; font.pixelSize: 16; font.weight: Font.Bold }
            Section {
                title: "Format"
                Row {
                    spacing: 6
                    Chip { text: "PNG"; on: exportPop.format === "png"; onClicked: exportPop.format = "png" }
                    Chip { text: "JPG"; on: exportPop.format === "jpg"; onClicked: exportPop.format = "jpg" }
                    Chip { text: "PDF"; on: exportPop.format === "pdf"; onClicked: exportPop.format = "pdf" }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: exportPop.format === "png" ? "Najlepsza jakość — do mediów społecznościowych i na ekran."
                        : exportPop.format === "jpg" ? "Mniejszy plik — do wysłania mailem albo komunikatorem."
                        : "Do druku: ostre litery w każdym powiększeniu. Zapisuje się w Dokumenty/Grafiki."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
                }
            }
            Section {
                visible: exportPop.format !== "pdf"
                title: "Rozmiar"
                Row {
                    spacing: 6
                    Repeater {
                        model: [1, 2]
                        delegate: Chip {
                            required property real modelData
                            text: modelData + "× · " + Math.round(ed.project.pageWidth * modelData) + "×" + Math.round(ed.project.pageHeight * modelData)
                            on: exportPop.size === modelData
                            onClicked: exportPop.size = modelData
                        }
                    }
                }
            }
            Column {
                width: parent.width
                spacing: 8
                Btn {
                    width: parent.width; height: 40
                    primary: true
                    icon: "download"
                    text: exportPop.format === "pdf" ? "Zapisz PDF" : "Zapisz w Obrazy/Grafiki"
                    onClicked: ed.exportNow(exportPop.format, exportPop.format === "pdf" ? 1 : exportPop.size)
                }
                Btn {
                    width: parent.width
                    icon: "copy"
                    text: "Kopiuj do schowka"
                    onClicked: ed.copyImage()
                }
                Btn {
                    width: parent.width
                    text: "Wybierz miejsce…"
                    onClicked: {
                        exportDialog.format = exportPop.format;
                        exportDialog.scale = exportPop.size;
                        exportPop.close();
                        exportDialog.open();
                    }
                }
            }
        }
    }
}
