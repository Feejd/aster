import QtQuick

// Wirtualny dysk prototypu: drzewo folderów i plików w pamięci.
// Wszystkie operacje (nowy folder, zmiana nazwy, przeniesienie, kopiowanie, kosz)
// zapisują stan przed zmianą, więc każdą da się cofnąć.
QtObject {
    id: store

    property var nodes: ({})
    property int rev: 0
    property var undoStack: []
    property int nextId: 1

    readonly property string rootId: "pc"
    readonly property string winId: "win"
    readonly property string trashId: "trash"
    readonly property var places: [
        { id: "desktop", name: "Pulpit", icon: "desktop" },
        { id: "docs", name: "Dokumenty", icon: "doc" },
        { id: "downloads", name: "Pobrane", icon: "download" },
        { id: "pictures", name: "Obrazy", icon: "image" },
        { id: "music", name: "Muzyka", icon: "music" }
    ]

    // Spłaszczona lista plików (dla wyszukiwania w Start i asystenta)
    readonly property var flat: { rev; return allFiles(); }

    readonly property var types: ({
        docx: { label: "DOCX", kind: "Dokument", tint: "#4338CA" },
        txt: { label: "TXT", kind: "Tekst", tint: "#535A68" },
        xlsx: { label: "XLSX", kind: "Arkusz", tint: "#166A3F" },
        pdf: { label: "PDF", kind: "Dokument PDF", tint: "#A8341C" },
        png: { label: "PNG", kind: "Obraz", tint: "#9B2C5E" },
        jpg: { label: "JPG", kind: "Zdjęcie", tint: "#9B2C5E" },
        mp3: { label: "MP3", kind: "Muzyka", tint: "#A63D2A" },
        zip: { label: "ZIP", kind: "Archiwum", tint: "#535A68" },
        exe: { label: "EXE", kind: "Program Windows", tint: "#8A5300" }
    })

    Component.onCompleted: build()

    function build() {
        const n = {};
        const now = Date.now();
        const day = 86400000;
        let seq = 1;
        function dir(id, name, parent, age) {
            n[id] = { id: id, name: name, dir: true, parent: parent, children: [], size: 0, mtime: now - (age || 0) * day, origin: "" };
            if (parent) n[parent].children.push(id);
            return id;
        }
        function file(name, parent, kb, age) {
            const id = "n" + (seq++);
            n[id] = { id: id, name: name, dir: false, parent: parent, children: [], size: kb * 1024, mtime: now - age * day, origin: "" };
            n[parent].children.push(id);
            return id;
        }
        dir("pc", "Dysk systemowy (C:)", "", 0);
        dir("desktop", "Pulpit", "pc", 1);
        dir("docs", "Dokumenty", "pc", 0);
        dir("downloads", "Pobrane", "pc", 2);
        dir("pictures", "Obrazy", "pc", 3);
        dir("music", "Muzyka", "pc", 20);
        dir("trash", "Kosz", "", 0);
        dir("win", "Windows (D:)", "", 400);

        file("Zrzut ekranu 2026-10-28.png", "desktop", 820, 1);
        file("Lista zakupów.txt", "desktop", 2, 0.2);

        const work = "work";
        dir(work, "Praca", "docs", 0.1);
        dir("invoices", "Faktury 2026", work, 5);
        for (let i = 1; i <= 6; i++) file("Faktura 2026-0" + i + ".pdf", "invoices", 140 + i * 7, 280 - i * 30);
        dir("clients", "Klienci", work, 9);
        dir("c1", "Kowalski i Syn", "clients", 9);
        dir("c2", "Studio Nova", "clients", 30);
        file("Brief.docx", "c1", 48, 9);
        file("Wycena.xlsx", "c1", 36, 12);
        file("Logo — szkice.png", "c2", 2100, 30);
        file("Oferta dla klienta.docx", work, 64, 0.1);
        file("Budżet Q4.xlsx", work, 92, 1);
        file("Umowa — wzór.pdf", work, 310, 17);
        file("Notatki ze spotkania.docx", work, 28, 19);
        file("Zestawienie godzin.xlsx", work, 51, 28);
        file("Budżet domowy 2025.xlsx", "docs", 40, 44);
        file("CV.docx", "docs", 75, 120);

        file("Regulamin.pdf", "downloads", 512, 31);
        file("instalator-drukarki.exe", "downloads", 48200, 3);
        file("zdjecia-od-mamy.zip", "downloads", 182000, 6);

        dir("trip", "Wakacje 2025", "pictures", 70);
        for (let i = 1; i <= 8; i++) file("IMG_04" + (10 + i) + ".jpg", "trip", 3400 + i * 120, 70);
        file("Logo firmy.png", "pictures", 96, 26);

        file("Ulubiona piosenka.mp3", "music", 7200, 200);
        file("Podcast — odcinek 12.mp3", "music", 41000, 15);

        dir("wusers", "Users", "win", 400);
        dir("wuser", "Użytkownik", "wusers", 400);
        dir("wdocs", "Documents", "wuser", 400);
        file("Stary budżet 2023.xlsx", "wdocs", 38, 700);
        file("Program księgowy — dane.zip", "wdocs", 9100, 500);

        nextId = seq;
        nodes = n;
        rev++;
    }

    // ——— Odczyt ———

    function ext(name) {
        const i = name.lastIndexOf(".");
        return i > 0 ? name.slice(i + 1).toLowerCase() : "";
    }

    function decorate(node) {
        const t = types[ext(node.name)];
        return {
            id: node.id,
            name: node.name,
            dir: node.dir,
            parent: node.parent,
            badge: node.dir ? "" : (t ? t.label : (ext(node.name).toUpperCase() || "PLIK")),
            tint: node.dir ? "#3456E8" : (t ? t.tint : "#535A68"),
            kind: node.dir ? "Folder" : (t ? t.kind : "Plik"),
            size: node.dir ? totalSize(node.id) : node.size,
            sizeText: node.dir ? countText(node.children.length) : sizeText(node.size),
            mtime: node.mtime,
            when: node.dir ? countText(node.children.length) : dateText(node.mtime),
            date: dateText(node.mtime),
            where: pathText(node.parent),
            origin: node.origin ? pathText(node.origin) : ""
        };
    }

    function get(id) { rev; return nodes[id] ? decorate(nodes[id]) : null; }
    function isDir(id) { return !!(nodes[id] && nodes[id].dir); }
    function exists(id) { return !!nodes[id]; }

    function children(dirId, sortKey, ascending) {
        rev;
        const d = nodes[dirId];
        if (!d) return [];
        const list = d.children.map(id => decorate(nodes[id]));
        const dirSign = (a, b) => (b.dir ? 1 : 0) - (a.dir ? 1 : 0);
        const cmp = {
            name: (a, b) => a.name.localeCompare(b.name, "pl", { numeric: true }),
            date: (a, b) => a.mtime - b.mtime,
            size: (a, b) => a.size - b.size,
            kind: (a, b) => a.kind.localeCompare(b.kind, "pl") || a.name.localeCompare(b.name, "pl")
        }[sortKey || "name"];
        list.sort((a, b) => dirSign(a, b) || (ascending === false ? -cmp(a, b) : cmp(a, b)));
        return list;
    }

    function path(id) {
        rev;
        const out = [];
        let cur = nodes[id];
        while (cur) {
            out.unshift({ id: cur.id, name: cur.id === rootId ? "Komputer" : cur.name });
            cur = nodes[cur.parent];
        }
        return out;
    }

    function pathText(id) {
        return path(id).map(p => p.name).join(" › ");
    }

    function search(q, dirId) {
        rev;
        q = q.trim().toLowerCase();
        const out = [];
        function walk(id) {
            for (const c of nodes[id].children) {
                const node = nodes[c];
                if (node.name.toLowerCase().indexOf(q) >= 0) out.push(decorate(node));
                if (node.dir) walk(c);
            }
        }
        if (q && nodes[dirId]) walk(dirId);
        return out;
    }

    function allFiles() {
        const out = [];
        for (const id in nodes) {
            const node = nodes[id];
            if (!node.dir && !inTrash(id)) out.push(decorate(node));
        }
        out.sort((a, b) => b.mtime - a.mtime);
        return out;
    }

    function totalSize(id) {
        const node = nodes[id];
        if (!node) return 0;
        if (!node.dir) return node.size;
        let s = 0;
        for (const c of node.children) s += totalSize(c);
        return s;
    }

    function isAncestor(a, b) {
        let cur = nodes[b];
        while (cur) {
            if (cur.id === a) return true;
            cur = nodes[cur.parent];
        }
        return false;
    }

    function inTrash(id) { return isAncestor(trashId, id) && id !== trashId; }

    function sizeText(bytes) {
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return Math.round(bytes / 1024) + " KB";
        if (bytes < 1024 * 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1).replace(".", ",") + " MB";
        return (bytes / 1024 / 1024 / 1024).toFixed(1).replace(".", ",") + " GB";
    }

    function countText(n) {
        if (n === 0) return "pusty";
        if (n === 1) return "1 element";
        const last = n % 10, last2 = n % 100;
        return n + (last >= 2 && last <= 4 && (last2 < 12 || last2 > 14) ? " elementy" : " elementów");
    }

    function dateText(ms) {
        const d = new Date(ms), now = new Date();
        const startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        if (ms >= startToday) return "dziś, " + Qt.formatTime(d, "HH:mm");
        if (ms >= startToday - 86400000) return "wczoraj, " + Qt.formatTime(d, "HH:mm");
        return Qt.locale("pl_PL").toString(d, d.getFullYear() === now.getFullYear() ? "d MMM" : "d MMM yyyy");
    }

    // ——— Zmiany ———

    function snapshot(label) {
        const s = undoStack.slice(-29);
        s.push({ label: label, nodes: JSON.stringify(nodes), nextId: nextId });
        undoStack = s;
    }

    function commit() {
        nodes = nodes;
        rev++;
    }

    function undo() {
        if (!undoStack.length) return "";
        const s = undoStack.slice();
        const last = s.pop();
        undoStack = s;
        nodes = JSON.parse(last.nodes);
        nextId = last.nextId;
        rev++;
        return last.label;
    }

    function hasName(dirId, name, exceptId) {
        return nodes[dirId].children.some(c => c !== exceptId && nodes[c].name.toLowerCase() === name.toLowerCase());
    }

    function uniqueName(dirId, name) {
        if (!hasName(dirId, name)) return name;
        const base = ext(name) ? name.slice(0, name.lastIndexOf(".")) : name;
        const suffix = base === name ? "" : name.slice(base.length);
        for (let i = 2; ; i++) {
            const candidate = base + " (" + i + ")" + suffix;
            if (!hasName(dirId, candidate)) return candidate;
        }
    }

    function newId() { return "n" + (nextId++); }

    function mkdir(dirId, name) {
        snapshot("Utworzenie folderu");
        const id = newId();
        nodes[id] = { id: id, name: uniqueName(dirId, name || "Nowy folder"), dir: true, parent: dirId, children: [], size: 0, mtime: Date.now(), origin: "" };
        nodes[dirId].children.push(id);
        nodes[dirId].mtime = Date.now();
        commit();
        return id;
    }

    function mkfile(dirId, name) {
        snapshot("Utworzenie pliku");
        const id = newId();
        nodes[id] = { id: id, name: uniqueName(dirId, name), dir: false, parent: dirId, children: [], size: 0, mtime: Date.now(), origin: "" };
        nodes[dirId].children.push(id);
        commit();
        return id;
    }

    // Zwraca pusty tekst albo komunikat błędu
    function rename(id, name) {
        name = name.trim();
        const node = nodes[id];
        if (!node || name === node.name) return "";
        if (!name) return "Nazwa nie może być pusta.";
        if (/[\/\\:*?"<>|]/.test(name)) return "Nazwa nie może zawierać znaków / \\ : * ? \" < > |";
        if (hasName(node.parent, name, id)) return "W tym folderze jest już „" + name + "”.";
        snapshot("Zmiana nazwy");
        node.name = name;
        node.mtime = Date.now();
        commit();
        return "";
    }

    function detach(id) {
        const p = nodes[nodes[id].parent];
        p.children = p.children.filter(c => c !== id);
    }

    function attach(id, dest) {
        nodes[id].parent = dest;
        nodes[dest].children.push(id);
    }

    // Przenosi elementy do folderu; pomija niemożliwe (folder do samego siebie itp.)
    function move(ids, dest, label) {
        const ok = ids.filter(id => nodes[id] && nodes[dest] && nodes[id].parent !== dest && !isAncestor(id, dest));
        if (!ok.length) return 0;
        snapshot(label || "Przeniesienie");
        for (const id of ok) {
            detach(id);
            nodes[id].name = uniqueName(dest, nodes[id].name);
            attach(id, dest);
        }
        commit();
        return ok.length;
    }

    function cloneInto(id, dest) {
        const src = nodes[id];
        const cid = newId();
        nodes[cid] = { id: cid, name: uniqueName(dest, src.name), dir: src.dir, parent: dest, children: [], size: src.size, mtime: Date.now(), origin: "" };
        nodes[dest].children.push(cid);
        for (const c of src.children.slice()) cloneInto(c, cid);
        return cid;
    }

    function copy(ids, dest) {
        const ok = ids.filter(id => nodes[id] && nodes[dest] && !isAncestor(id, dest));
        if (!ok.length) return [];
        snapshot("Kopiowanie");
        const out = ok.map(id => cloneInto(id, dest));
        commit();
        return out;
    }

    function trash(ids) {
        const ok = ids.filter(id => nodes[id] && !inTrash(id) && [rootId, winId, trashId].indexOf(id) < 0 && places.every(p => p.id !== id));
        if (!ok.length) return 0;
        snapshot("Przeniesienie do kosza");
        for (const id of ok) {
            nodes[id].origin = nodes[id].parent;
            detach(id);
            nodes[id].name = uniqueName(trashId, nodes[id].name);
            attach(id, trashId);
        }
        commit();
        return ok.length;
    }

    function restore(ids) {
        const ok = ids.filter(id => nodes[id] && nodes[id].parent === trashId);
        if (!ok.length) return 0;
        snapshot("Przywrócenie z kosza");
        for (const id of ok) {
            const dest = nodes[nodes[id].origin] && !inTrash(nodes[id].origin) ? nodes[id].origin : "docs";
            detach(id);
            nodes[id].name = uniqueName(dest, nodes[id].name);
            nodes[id].origin = "";
            attach(id, dest);
        }
        commit();
        return ok.length;
    }

    function purgeNode(id) {
        for (const c of nodes[id].children.slice()) purgeNode(c);
        delete nodes[id];
    }

    // Usuwa na zawsze (tylko z kosza). Też da się cofnąć w tej sesji prototypu.
    function purge(ids) {
        const ok = ids.filter(id => nodes[id] && nodes[id].parent === trashId);
        if (!ok.length) return 0;
        snapshot("Usunięcie na zawsze");
        for (const id of ok) {
            detach(id);
            purgeNode(id);
        }
        commit();
        return ok.length;
    }

    function emptyTrash() { return purge(nodes[trashId].children.slice()); }
}
