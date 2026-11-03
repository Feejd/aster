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
    readonly property bool active: visible && !colorPop.shown && !fontPop.shown && !exportPop.shown && !shortcutsSheet.open
    readonly property string sel: stage.selected
    readonly property var many: stage.selection           // zaznaczone (jeden albo kilka)

    onVisibleChanged: if (visible) { stage.clearSelection(); stage.fit = true; side.tab = "templates"; stage.forceActiveFocus(); }

    Settings { id: viewSettings; category: "Grafika"; property bool rulers: false }

    // ——— Działania ———
    function addElement(el) {
        stage.stopEditing();
        stage.select(project.add(el));
        stage.forceActiveFocus();
    }
    function addImageKey(key) {
        const s = project.imageSize(key);
        if (s.width <= 0) return;
        if (key.endsWith(".svg")) { addVector(key, "#16181D"); return; }
        // Zaznaczone puste miejsce na zdjęcie (szablon, kolaż) — zdjęcie trafia do niego
        if (stage.current.type === "image" && !stage.current.src && !stage.current.locked) {
            project.change(sel, { src: key, focusX: null, focusY: null, zoom: null, credit: null });
            selectNextEmptyFrame();
            return;
        }
        const k = Math.min(1, project.pageWidth * 0.6 / s.width, project.pageHeight * 0.6 / s.height);
        addElement({ type: "image", src: key, w: Math.round(s.width * k), h: Math.round(s.height * k) });
    }
    // Ikona albo naklejka na środek strony; jednokolorowe dostają kolor (da się go potem zmienić)
    function addVector(key, color) {
        const s = project.imageSize(key);
        const side = Math.round(Math.min(project.pageWidth, project.pageHeight) * 0.28);
        const k = side / Math.max(s.width, s.height);
        const el = { type: "vector", src: key, w: Math.round(s.width * k), h: Math.round(s.height * k) };
        if (project.recolorable(key)) el.color = color;
        addElement(el);
    }

    // ——— Z internetu: pobranie, potem wstawienie ———
    property var downloads: ({})            // adres → co zrobić po pobraniu
    function download(url, job) {
        if (downloads[url]) return;
        const d = Object.assign({}, downloads);
        d[url] = job;
        downloads = d;
        Online.fetch(url, url);
    }
    function finishDownload(url) {
        const d = Object.assign({}, downloads);
        delete d[url];
        downloads = d;
    }
    function addGraphic(file) {
        const key = project.importImage(file);
        if (key !== "") addVector(key, "#16181D");
    }
    function addOnlinePhoto(photo) {
        // Zaznaczone puste miejsce na zdjęcie (np. w szablonie) — zdjęcie trafia do niego
        const frame = stage.current.type === "image" && !stage.current.src && !stage.current.locked ? stage.current.id : "";
        download(photo.url, { kind: "photo", frame: frame, fallback: photo.fallback, credit: photo.credit || "" });
    }
    Connections {
        target: Online
        function onFetched(tag, path) {
            const job = ed.downloads[tag];
            if (!job) return;
            ed.finishDownload(tag);
            const key = ed.project.importImage(path);
            if (key === "") return;
            if (job.kind === "photo") {
                if (job.frame !== "" && ed.project.indexOf(job.frame) >= 0) {
                    ed.project.change(job.frame, { src: key, focusX: null, focusY: null, zoom: null, credit: job.credit || null });
                    stage.select(job.frame);
                    ed.selectNextEmptyFrame();
                } else {
                    ed.addImageKey(key);
                    if (job.credit) ed.project.change(ed.sel, { credit: job.credit });
                }
                if (job.credit) ed.app.toast("To zdjęcie wymaga podpisu autora — dodasz go w panelu zdjęcia", "");
            }
        }
        function onFetchFailed(tag) {
            const job = ed.downloads[tag];
            if (!job) return;
            ed.finishDownload(tag);
            // Oryginał bywa niedostępny — wtedy mniejsza kopia z Openverse
            if (job.kind === "photo" && job.fallback && job.fallback !== tag) {
                ed.download(job.fallback, { kind: "photo", frame: job.frame, credit: job.credit });
                return;
            }
            ed.app.toast("Nie udało się pobrać — sprawdź połączenie z internetem", "");
        }
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
            project.change(target.id, { src: key, focusX: null, focusY: null, zoom: null, credit: null });
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
            project.change(sel, { src: key, credit: null });
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
    // Narzędzia AI na zaznaczonym zdjęciu
    function startMagic() {
        if (sel === "" || stage.current.type !== "image" || !stage.current.src) return;
        stage.stopEditing();
        stage.cropping = "";
        Magic.begin(project, sel);
        stage.forceActiveFocus();
    }
    function undo() {
        if (Magic.element !== "" && Magic.hasMask) { Magic.undoMask(); return; }
        project.undo();
        if (Magic.element !== "" && project.indexOf(Magic.element) >= 0) Magic.begin(project, Magic.element);
    }
    Connections {
        target: Magic
        function onFinished(message, ids) {
            if (Magic.element === "" && ids.length > 0) stage.setSelection(ids);
            if (message !== "") ed.app.toast(message, "");
        }
        function onFailed(message) { ed.app.toast(message, ""); }
    }
    function saveElements() {
        if (many.length === 0) return;
        if (project.saveElements(many)) app.toast("Zapisano w „Moich elementach” — znajdziesz je w zakładce Elementy w każdym projekcie", "");
    }
    function insertSaved(file) {
        stage.stopEditing();
        const ids = project.insertSaved(file);
        if (ids.length > 0) stage.setSelection(ids);
        stage.forceActiveFocus();
    }
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
    // Po wypełnieniu ramki — następna pusta (kolaż wypełnia się kliknięciami w zdjęcia po kolei)
    function selectNextEmptyFrame() {
        for (const o of project.document().elements)
            if (o.type === "image" && !o.src && !o.hidden && !o.locked) { stage.select(o.id); return; }
    }

    // ——— Grupy ———
    property int rev: 0                     // zmiany treści — odświeża wiązania, które pytają projekt o elementy
    Connections {
        target: ed.project
        function onDataChanged() { ed.rev += 1; }
        function onReset() { ed.rev += 1; }
    }
    readonly property bool grouped: rev >= 0 && many.length > 1 && many.every(id => { const g = project.get(id).group; return !!g && g === project.get(many[0]).group; })
    function group() {
        if (many.length < 2) return;
        const g = "g" + Math.floor(Math.random() * 1e8);
        for (const id of many) project.change(id, { group: g }, false);
        project.commit();
        app.toast("Zgrupowano — kliknięcie zaznacza całą grupę, drugie kliknięcie jeden element", "");
    }
    function ungroup() {
        for (const id of many) project.change(id, { group: null }, false);
        project.commit();
    }

    // Kolaż: puste ramki na zdjęcia z odstępami (r — prostokąty w częściach strony)
    function addCollage(rects) {
        stage.clearSelection();
        const W = project.pageWidth, H = project.pageHeight;
        const gap = Math.round(Math.min(W, H) * 0.02);
        const ids = [];
        for (const r of rects) {
            const x = Math.round(r[0] * (W - gap) + gap), y = Math.round(r[1] * (H - gap) + gap);
            const w = Math.round(r[2] * (W - gap) - gap), h = Math.round(r[3] * (H - gap) - gap);
            ids.push(project.add({ type: "image", src: "", x: x, y: y, w: w, h: h, radius: Math.round(gap * 0.6) }));
        }
        stage.select(ids[0]);
        app.toast("Kliknij zdjęcie z dysku albo z internetu — trafi do zaznaczonej ramki", "");
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
    // Podpis autora zdjęcia (licencja CC BY) — mały tekst w rogu strony
    function addCredit(id) {
        const el = project.get(id);
        if (!el.credit) return;
        const size = Math.max(10, Math.round(Math.min(project.pageWidth, project.pageHeight) * 0.016));
        const t = { type: "text", text: el.credit, size: size, color: "#ffffff", font: "Geist", weight: 500, align: "right", shadow: true, opacity: 0.85 };
        t.w = Math.min(project.pageWidth * 0.9, project.naturalWidth(t) + size);
        t.x = Math.round(project.pageWidth - t.w - size * 1.5);
        t.y = Math.round(project.pageHeight - size * 3);
        addElement(t);
    }
    // ——— Kopiowanie stylu (kolory, czcionka, efekty) z jednego elementu na inne tego samego rodzaju ———
    property var styleClip: null
    readonly property var styleSkip: ["id", "type", "x", "y", "w", "h", "text", "src", "data", "ssid", "pass", "group", "locked", "hidden",
                                      "credit", "focusX", "focusY", "zoom", "shape", "kind", "chart", "qrType", "rotation"]
    function copyStyle() {
        if (sel === "") return;
        const el = project.get(sel);
        const st = { type: el.type };
        for (const k in el) if (styleSkip.indexOf(k) < 0) st[k] = el[k];
        styleClip = st;
        app.toast("Skopiowano styl — zaznacz inne elementy i wybierz „Wklej styl” (Ctrl+Alt+V)", "");
    }
    function pasteStyle() {
        if (styleClip && applyStyle(styleClip) === 0) app.toast("Styl pasuje tylko do elementów tego samego rodzaju", "");
    }
    // Styl (pola wyglądu) na zaznaczone elementy tego samego rodzaju; zwraca, ile się zmieniło
    function applyStyle(st) {
        let n = 0;
        for (const id of many) {
            const el = project.get(id);
            if (el.type !== st.type || el.locked) continue;
            const patch = {};
            for (const k in el) if (styleSkip.indexOf(k) < 0 && !(k in st)) patch[k] = null;
            for (const k in st) if (k !== "type") patch[k] = st[k];
            project.change(id, patch, false);
            n += 1;
        }
        project.commit();
        return n;
    }

    function copyImage() {
        exportPop.close();
        if (project.copyImage()) app.toast("Skopiowano grafikę — wklej ją w wiadomości (Ctrl+V)", "");
    }
    function exportNow(format, scale) {
        exportPop.close();
        const all = exportPop.allPages && project.pageCount > 1 && format !== "pdf";
        const path = project.exportFile(format, scale, "", all);
        if (path === "") return;
        if (all) app.toast("Zapisano " + project.pageCount + " pliki: „" + path.split("/").pop() + "” i kolejne", path);
        else app.toast("Zapisano „" + path.split("/").pop() + "”", path);
    }

    // ——— Strony ———
    function goToPage(i) {
        stage.clearSelection();
        project.goToPage(i);
        stage.forceActiveFocus();
    }
    function showPageMenu(i, item) {
        const items = [
            { label: "Duplikuj stronę", icon: "copy", action: "page:dup:" + i },
            { label: "Przesuń w lewo", icon: "back", action: "page:left:" + i, disabled: i === 0 },
            { label: "Przesuń w prawo", icon: "forward", action: "page:right:" + i, disabled: i === project.pageCount - 1 },
            { separator: true },
            { label: "Usuń stronę", icon: "trash", action: "page:del:" + i, danger: true, disabled: project.pageCount < 2 }
        ];
        const pt = item.mapToItem(ed, 0, 0);
        menu.openAt(pt.x, pt.y - items.length * 34 - 16, items.filter(it => !it.disabled));
    }

    function runMenu(a) {
        if (a.startsWith("page:")) {
            const [, what, n] = a.split(":");
            const i = Number(n);
            stage.clearSelection();
            if (what === "dup") project.duplicatePage(i);
            else if (what === "del") project.removePage(i);
            else if (what === "left") project.movePage(i, i - 1);
            else if (what === "right") project.movePage(i, i + 1);
            return;
        }
        if (a.startsWith("size:")) {
            for (const p of app.presets) if (p.id === a.substring(5)) project.setPageSize(p.w, p.h, true);
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
        else if (a === "rulers") stage.rulers = !stage.rulers;
        else if (a.startsWith("guides:")) {
            if (a === "guides:clear") project.setGuides({});
            else stage.addGuides(a.substring(7));
        }
        else if (a === "lock") setLocked(true);
        else if (a === "group") group();
        else if (a === "copyStyle") copyStyle();
        else if (a === "saveElements") saveElements();
        else if (a === "aiBackground") Magic.removeBackground(project, sel);
        else if (a === "templates") side.tab = "templates";
        else if (a === "shapesTab") side.tab = "shapes";
        else if (a === "addText") side.addTextStyle(side.textStyles[0]);
        else if (a === "addPhoto") { side.tab = "photos"; chooseImage("element"); }
        else if (a === "shortcuts") shortcutsSheet.open = true;
        else if (a === "aiMagic") startMagic();
        else if (a === "pasteStyle") pasteStyle();
        else if (a === "ungroup") ungroup();
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
            items.push({ label: "Zapisz jako mój element", icon: "star", action: "saveElements" });
            if (grouped) items.push({ label: "Rozgrupuj", icon: "layers", shortcut: "Ctrl+Shift+G", action: "ungroup" });
            else items.push({ label: "Grupuj", icon: "layers", shortcut: "Ctrl+G", action: "group" });
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
            if (el.type === "image" && el.src && Magic.available) {
                items.push({ label: "Usuń tło (AI)", icon: "sparkles", action: "aiBackground" });
                items.push({ label: "Gumka i wyodrębnianie", icon: "brush", action: "aiMagic" });
            }
            items.push({ label: "Kopiuj", icon: "copy", shortcut: "Ctrl+C", action: "copy" });
            items.push({ label: "Wytnij", icon: "scissors", shortcut: "Ctrl+X", action: "cut" });
            items.push({ label: "Wklej", icon: "paste", shortcut: "Ctrl+V", action: "paste" });
            items.push({ label: "Duplikuj", icon: "copy", shortcut: "Ctrl+D", action: "duplicate" });
            items.push({ label: "Kopiuj styl", icon: "palette", shortcut: "Ctrl+Alt+C", action: "copyStyle" });
            if (styleClip && styleClip.type === el.type) items.push({ label: "Wklej styl", icon: "palette", shortcut: "Ctrl+Alt+V", action: "pasteStyle" });
            items.push({ label: "Zapisz jako mój element", icon: "star", action: "saveElements" });
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
            items.push({ separator: true });
            items.push({ label: stage.rulers ? "Ukryj linijki i prowadnice" : "Pokaż linijki i prowadnice", icon: "ruler", shortcut: "Ctrl+R", action: "rulers" });
            items.push({ label: "Prowadnice na środku", icon: "plus", action: "guides:center" });
            items.push({ label: "Prowadnice marginesów", icon: "crop", action: "guides:margins" });
            items.push({ label: "Podział na trzy części", icon: "gridLines", action: "guides:thirds" });
            if (stage.rulers && ((project.guides.x || []).length + (project.guides.y || []).length) > 0)
                items.push({ label: "Usuń prowadnice", icon: "trash", action: "guides:clear", danger: true });
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
        else if (cmd === "group") group();
        else if (cmd === "addpage") project.addPage();
        else if (cmd === "copystyle") copyStyle();
        else if (cmd === "pastestyle") pasteStyle();
        else if (cmd === "addextra") side.addExtra(side.extras[Number(arg)]);
        else if (cmd === "duppage") project.duplicatePage(project.currentPage);
        else if (cmd === "page") goToPage(Number(arg));
        else if (cmd === "exportpages") { const p = project.exportFile(arg, 0.5, "/tmp/grafika-strony." + arg, true); app.toast(p, p); }
        else if (cmd === "collage") addCollage(side.collages[Number(arg)].rects);
        else if (cmd === "resize") { const [w, h] = arg.split("x"); project.setPageSize(Number(w), Number(h), true); stage.fit = true; }
        else if (cmd === "searchg") { side.tab = "shapes"; side.searchGraphics(arg); }
        else if (cmd === "searchp") { side.tab = "photos"; side.searchPhotos(arg); }
        else if (cmd === "addg") addGraphic(side.icons[Number(arg)].file);
        else if (cmd === "addst") addGraphic(side.stickers[Number(arg)].file);
        else if (cmd === "addp") addOnlinePhoto(side.webPhotos[Number(arg)]);
        else if (cmd === "fontweb") { fontPop.source = "web"; pickFont(inspector, stage.current.font || "Geist", f => project.change(sel, { font: f })); }
        else if (cmd === "fontinstall") fontPop.choose(arg);
        else if (cmd === "fontpop") pickFont(inspector, stage.current.font || "Geist", f => project.change(sel, { font: f }));
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
        else if (cmd === "menuaction") runMenu(arg);
        else if (cmd === "savestyle") side.saveTextStyle();
        else if (cmd === "saveel") saveElements();
        else if (cmd === "magic") startMagic();
        else if (cmd === "magicbg") Magic.removeBackground(project, sel);
        else if (cmd === "magicobj") { const [x, y] = arg.split(",").map(Number); Magic.addObject(x, y, false); }
        else if (cmd === "magicstroke") { const a = JSON.parse(arg); Magic.addStroke(a.points, a.width || 0, !!a.lasso, false); }
        else if (cmd === "magicapply") Magic.apply(arg);
        else if (cmd === "magictool") stage.magicTool = arg;
        else if (cmd === "shortcuts") shortcutsSheet.open = true;
        else if (cmd === "insertsaved") insertSaved(side.saved[Number(arg)].file);
        else if (cmd === "replacecolor") { const [a, b] = arg.split(","); project.commit(); project.replaceColor(a, b); }
        else if (cmd === "usestyle") side.useTextStyle(side.myStyles[Number(arg)]);
        else if (cmd === "guides") project.setGuides(JSON.parse(arg));
        else if (cmd === "snapmove") {
            // Przesunięcie jak myszą (bez puszczania — znaczniki zostają): indeks,x,y
            const [i, x, y] = arg.split(",").map(Number);
            const id = project.idAt(i);
            stage.select(id);
            stage.prepareSnap([id]);
            const r = stage.snapMove(project.get(id), x, y);
            project.change(id, { x: r.x, y: r.y }, false);
        }
    }

    // ——— Skróty ———
    Shortcut { sequences: [StandardKey.Undo]; enabled: ed.active && !ed.typing; onActivated: ed.undo() }
    Shortcut { sequences: [StandardKey.Redo, "Ctrl+Y"]; enabled: ed.active && !ed.typing; onActivated: ed.project.redo() }
    Shortcut { sequences: [StandardKey.Delete, "Backspace"]; enabled: ed.active && !ed.typing; onActivated: ed.remove() }
    Shortcut { sequences: [StandardKey.Copy]; enabled: ed.active && !ed.typing; onActivated: ed.copy() }
    Shortcut { sequences: [StandardKey.Cut]; enabled: ed.active && !ed.typing; onActivated: { ed.copy(); ed.remove(); } }
    Shortcut { sequences: [StandardKey.Paste]; enabled: ed.active && !ed.typing; onActivated: ed.paste() }
    Shortcut { sequence: "Ctrl+D"; enabled: ed.active && !ed.typing && ed.many.length > 0; onActivated: ed.duplicate() }
    Shortcut { sequences: [StandardKey.SelectAll]; enabled: ed.active && !ed.typing; onActivated: stage.selectAll() }
    Shortcut { sequence: "PgDown"; enabled: ed.active && !ed.typing; onActivated: ed.goToPage(Math.min(ed.project.pageCount - 1, ed.project.currentPage + 1)) }
    Shortcut { sequence: "PgUp"; enabled: ed.active && !ed.typing; onActivated: ed.goToPage(Math.max(0, ed.project.currentPage - 1)) }
    Shortcut { sequence: "Ctrl+Return"; enabled: ed.active && !ed.typing; onActivated: { stage.clearSelection(); ed.project.addPage(); } }
    Shortcut { sequence: "Ctrl+Alt+C"; enabled: ed.active && !ed.typing && ed.sel !== ""; onActivated: ed.copyStyle() }
    Shortcut { sequence: "Ctrl+Alt+V"; enabled: ed.active && !ed.typing && ed.many.length > 0; onActivated: ed.pasteStyle() }
    Shortcut { sequence: "Ctrl+G"; enabled: ed.active && !ed.typing && ed.many.length > 1; onActivated: ed.group() }
    Shortcut { sequence: "Ctrl+Shift+G"; enabled: ed.active && !ed.typing && ed.many.length > 1; onActivated: ed.ungroup() }
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
    // Formatowanie zaznaczonych tekstów
    function toggleText(key) {
        const texts = many.map(id => project.get(id)).filter(o => o.type === "text" && !o.locked);
        if (texts.length === 0) return;
        const on = key === "weight" ? (texts[0].weight || 400) >= 600 : !!texts[0][key];
        for (const o of texts) {
            const patch = {};
            patch[key] = key === "weight" ? (on ? 400 : 700) : (on ? null : true);
            project.change(o.id, patch, false);
        }
        project.commit();
    }
    Shortcut { sequence: StandardKey.Bold; enabled: ed.active && !ed.typing; onActivated: ed.toggleText("weight") }
    Shortcut { sequence: StandardKey.Italic; enabled: ed.active && !ed.typing; onActivated: ed.toggleText("italic") }
    Shortcut { sequence: StandardKey.Underline; enabled: ed.active && !ed.typing; onActivated: ed.toggleText("underline") }
    Shortcut { sequence: "Ctrl+R"; enabled: ed.visible; onActivated: stage.rulers = !stage.rulers }
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
            const path = ed.project.exportFile(format, scale, String(selectedFile), exportPop.allPages && format !== "pdf");
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
                ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "undo"; tip: "Cofnij (Ctrl+Z)"; enabled: ed.project.canUndo; onClicked: ed.undo() }
                ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "redo"; tip: "Ponów (Ctrl+Shift+Z)"; enabled: ed.project.canRedo; onClicked: ed.project.redo() }
                Item { width: 8; height: 1 }
                ToolBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "ruler"
                    tip: "Linijki i prowadnice (Ctrl+R)"
                    baseColor: stage.rulers ? Theme.accentSoft : "transparent"
                    onClicked: stage.rulers = !stage.rulers
                }
                ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "keyboard"; tip: "Skróty klawiszowe (Ctrl+/)"; onClicked: shortcutsSheet.open = true }
                ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "minus"; tip: "Pomniejsz (Ctrl −)"; onClicked: stage.zoomBy(0.8) }
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
                ToolBtn { anchors.verticalCenter: parent.verticalCenter; icon: "plus"; tip: "Powiększ (Ctrl +)"; onClicked: stage.zoomBy(1.25) }
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
            height: parent.height - y - pageBar.height
            project: ed.project
            rulers: viewSettings.rulers
            onRulersChanged: viewSettings.rulers = rulers
            onMenuRequested: (x, y) => ed.showContextMenu(x, y)
            onQuickAction: (a) => ed.runMenu(a)
        }

        // Pasek stron: podglądy, kliknięcie przechodzi na stronę, prawy przycisk — menu strony
        Item {
            id: pageBar
            y: stage.y + stage.height
            width: stage.width
            height: 92
            readonly property real thumbH: 56
            readonly property real thumbW: Math.max(32, Math.min(110, thumbH * ed.project.pageWidth / ed.project.pageHeight))
            property int dragFrom: -1           // przeciąganie strony na inne miejsce
            property int dragTo: -1
            Rectangle { width: parent.width; height: 1; color: Theme.line }
            Flickable {
                id: pageFlick
                anchors.fill: parent
                anchors.leftMargin: 16; anchors.rightMargin: 16
                contentWidth: pageRow.width
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                Row {
                    id: pageRow
                    height: pageFlick.height
                    spacing: 10
                    Repeater {
                        model: ed.project.pageCount
                        delegate: Item {
                            id: pg
                            required property int index
                            readonly property bool current: index === ed.project.currentPage
                            width: pageBar.thumbW + 8
                            height: pageRow.height
                            Rectangle {
                                id: pgFrame
                                x: 0; y: 10
                                width: pageBar.thumbW + 8; height: pageBar.thumbH + 8
                                radius: 8
                                color: "transparent"
                                border.width: pg.current ? 2 : 1
                                border.color: pg.current ? Theme.accent : pgMa.containsMouse ? Theme.text2 : Theme.line
                                PageView {
                                    x: 4; y: 4
                                    width: pageBar.thumbW; height: pageBar.thumbH
                                    project: ed.project
                                    page: pg.index
                                }
                                MouseArea {
                                    id: pgMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: pageBar.dragFrom >= 0 ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                    property real startX
                                    property bool dragged: false
                                    onPressed: (e) => { startX = mapToItem(pageRow, e.x, e.y).x; dragged = false; }
                                    onPositionChanged: (e) => {
                                        if (!pressed || !(pressedButtons & Qt.LeftButton)) return;
                                        const x = mapToItem(pageRow, e.x, e.y).x;
                                        if (pageBar.dragFrom < 0 && Math.abs(x - startX) < 8) return;
                                        pageBar.dragFrom = pg.index;
                                        dragged = true;
                                        pageBar.dragTo = Math.max(0, Math.min(ed.project.pageCount - 1, Math.floor(x / (pageBar.thumbW + 18))));
                                    }
                                    onReleased: {
                                        if (pageBar.dragFrom < 0) return;
                                        const from = pageBar.dragFrom, to = pageBar.dragTo;
                                        pageBar.dragFrom = -1;
                                        if (from !== to) { stage.clearSelection(); ed.project.movePage(from, to); }
                                    }
                                    onClicked: (e) => {
                                        if (dragged) return;
                                        if (e.button === Qt.RightButton) { ed.goToPage(pg.index); ed.showPageMenu(pg.index, pgFrame); }
                                        else ed.goToPage(pg.index);
                                    }
                                }
                                // Miejsce, w które trafi przeciągana strona
                                Rectangle {
                                    visible: pageBar.dragFrom >= 0 && pageBar.dragTo === pg.index && pageBar.dragFrom !== pg.index
                                    x: pageBar.dragTo > pageBar.dragFrom ? parent.width + 3 : -7
                                    y: -2; width: 3; height: parent.height + 4; radius: 1.5
                                    color: Theme.accent
                                }
                            }
                            Text {
                                anchors.horizontalCenter: pgFrame.horizontalCenter
                                y: pgFrame.y + pgFrame.height + 3
                                text: pg.index + 1
                                color: pg.current ? Theme.accentText : Theme.text2
                                font.family: Theme.font; font.pixelSize: 11; font.weight: pg.current ? Font.DemiBold : Font.Normal
                            }
                        }
                    }
                    HoverButton {
                        y: 10
                        width: Math.max(pageBar.thumbW + 8, addPageRow.implicitWidth + 20); height: pageBar.thumbH + 8
                        radius: 8
                        baseColor: Theme.fill
                        onClicked: { stage.clearSelection(); ed.project.addPage(); pageFlick.contentX = Math.max(0, pageFlick.contentWidth - pageFlick.width); }
                        Column {
                            id: addPageRow
                            anchors.centerIn: parent
                            spacing: 2
                            Icon { anchors.horizontalCenter: parent.horizontalCenter; d: Icons.plus; size: 16; stroke: 2.2; color: Theme.text }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: ed.project.pageCount > 1 ? "Strona" : "Dodaj stronę"
                                color: Theme.text2; font.family: Theme.font; font.pixelSize: 11
                            }
                        }
                    }
                }
            }
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
        property bool allPages: true    // kilka stron: każda do osobnego pliku
        property bool printMarks: false // PDF: spad i znaczniki cięcia
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
                visible: exportPop.format === "pdf"
                title: "Druk"
                Row {
                    spacing: 6
                    Chip { text: "Zwykły"; on: !exportPop.printMarks; onClicked: exportPop.printMarks = false }
                    Chip { text: "Do drukarni"; on: exportPop.printMarks; onClicked: exportPop.printMarks = true }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: exportPop.printMarks ? "Ze spadem 3 mm i znacznikami cięcia — tego zwykle wymagają drukarnie (wizytówki, ulotki, plakaty)."
                        : "Dokładnie w rozmiarze strony — do wydruku w domu albo wysłania."
                    color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.2
                }
            }
            Section {
                visible: ed.project.pageCount > 1
                title: "Strony"
                Row {
                    visible: exportPop.format !== "pdf"
                    spacing: 6
                    Chip { text: "Wszystkie (" + ed.project.pageCount + ")"; on: exportPop.allPages; onClicked: exportPop.allPages = true }
                    Chip { text: "Tylko ta"; on: !exportPop.allPages; onClicked: exportPop.allPages = false }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: exportPop.format === "pdf" ? "Wszystkie " + ed.project.pageCount + " strony w jednym pliku PDF."
                        : exportPop.allPages ? "Każda strona w osobnym pliku: nazwa-1, nazwa-2… — gotowe do karuzeli." : "Tylko strona " + (ed.project.currentPage + 1) + "."
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
                    onClicked: ed.exportNow(exportPop.format === "pdf" && exportPop.printMarks ? "pdf-print" : exportPop.format, exportPop.format === "pdf" ? 1 : exportPop.size)
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

    // ——— Skróty klawiszowe (Ctrl+/ albo przycisk na pasku) ———
    Item {
        id: shortcutsSheet
        property bool open: false
        anchors.fill: parent
        visible: open
        z: 100
        readonly property var groups: [
            { title: "Podstawy", items: [["Ctrl+Z", "Cofnij"], ["Ctrl+Shift+Z", "Ponów"], ["Ctrl+C / Ctrl+V", "Kopiuj / wklej"], ["Ctrl+D", "Duplikuj"],
                                         ["Delete", "Usuń"], ["Ctrl+A", "Zaznacz wszystko"], ["Esc", "Odznacz, wyjdź z trybu"], ["Ctrl+S", "Zapisz"], ["Ctrl+E", "Eksportuj"]] },
            { title: "Elementy", items: [["T", "Nowy tekst"], ["Enter", "Pisz w tekście"], ["Ctrl+B / I / U", "Pogrubienie, kursywa, podkreślenie"],
                                         ["Strzałki", "Przesuń (z Shiftem o 10)"], ["Ctrl+G", "Grupuj"], ["Ctrl+Shift+G", "Rozgrupuj"],
                                         ["Ctrl+] / Ctrl+[", "Do przodu / do tyłu"], ["Ctrl+Alt+C / V", "Kopiuj / wklej styl"], ["Shift+przeciąganie", "Zachowaj proporcje"]] },
            { title: "Widok i strony", items: [["Ctrl + / Ctrl −", "Powiększ / pomniejsz"], ["Ctrl+0", "Dopasuj do okna"], ["Ctrl+1", "100%"],
                                               ["Spacja+przeciąganie", "Przesuń widok"], ["Ctrl+R", "Linijki i prowadnice"],
                                               ["Ctrl+Enter", "Nowa strona"], ["PgUp / PgDn", "Poprzednia / następna strona"], ["Ctrl+/", "Ta ściąga"]] }
        ]
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35); radius: ed.radius }
        MouseArea { anchors.fill: parent; onClicked: shortcutsSheet.open = false }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, sheetRow.implicitWidth + 56)
            height: sheetCol.implicitHeight + 48
            radius: 20
            color: Theme.surface
            border.width: 1; border.color: Theme.line
            MouseArea { anchors.fill: parent }
            Column {
                id: sheetCol
                anchors.centerIn: parent
                spacing: 18
                Item {
                    width: sheetRow.implicitWidth; height: 28
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Skróty klawiszowe"; color: Theme.text; font.family: Theme.font; font.pixelSize: 19; font.weight: Font.Bold }
                    ToolBtn { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; icon: "close"; tip: "Zamknij (Esc)"; onClicked: shortcutsSheet.open = false }
                }
                Row {
                    id: sheetRow
                    spacing: 32
                    Repeater {
                        model: shortcutsSheet.groups
                        delegate: Column {
                            id: grp
                            required property var modelData
                            spacing: 9
                            Text { text: grp.modelData.title; color: Theme.text2; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                            Repeater {
                                model: grp.modelData.items
                                delegate: Row {
                                    required property var modelData
                                    spacing: 10
                                    Rectangle {
                                        width: 128; height: 24; radius: 6
                                        color: Theme.fill
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter; x: 8
                                            width: parent.width - 12; elide: Text.ElideRight
                                            text: modelData[0]
                                            color: Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                                        }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 170; wrapMode: Text.WordWrap
                                        text: modelData[1]
                                        color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    Shortcut { sequences: ["Ctrl+/", "F1"]; enabled: ed.visible; onActivated: shortcutsSheet.open = !shortcutsSheet.open }
    Shortcut { sequence: "Escape"; enabled: shortcutsSheet.open; onActivated: shortcutsSheet.open = false }
}
