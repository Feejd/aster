.pragma library
.import "Catalog.js" as Catalog

// Wyszukiwanie po tym, co chcesz zrobić. Najpierw lokalnie i natychmiast, po polsku i z odmianą:
// zadania, programy z Windowsa, rozszerzenia plików, nasz katalog. Flathub i asystent tylko uzupełniają.

function fold(text) {
    var map = { "ą": "a", "ć": "c", "ę": "e", "ł": "l", "ń": "n", "ó": "o", "ś": "s", "ź": "z", "ż": "z" };
    return String(text).toLowerCase().replace(/[ąćęłńóśźż]/g, function (c) { return map[c]; });
}

// Polski rdzeń: wystarczy dopasować początek („zmontuję”, „montaż”, „montowania” → „mont”)
function stem(word) {
    word = fold(word);
    if (word.length <= 4) return word;
    return word.slice(0, Math.max(4, Math.ceil(word.length * 0.7)));
}

var STOP = ["zamiast", "chce", "chcialbym", "chcialabym", "potrzebuje", "jak", "czym", "program", "programu", "programy", "aplikacja", "aplikacje", "aplikacji",
            "do", "na", "w", "z", "i", "a", "o", "to", "sie", "moj", "moje", "moich", "moja", "mi", "dla", "ze", "co", "czy", "bo",
            "najlepszy", "najlepsza", "dobry", "dobra", "darmowy", "darmowa", "za", "darmo", "cos", "jakis", "jakas"];

function words(query) {
    return fold(query).split(/[^a-z0-9+.#]+/).filter(function (w) { return w.length > 1 && STOP.indexOf(w) < 0; });
}

// Punkty za dopasowanie zapytania do tekstu (cała nazwa liczy się najbardziej)
function score(query, name, text) {
    // Formy dokonane: „zmontować” ma szukać też „montaż”
    function bare(w) {
        var m = w.match(/^(prze|za|na|po|wy|do|z|s|u)(.{5,})$/);
        return m ? m[2] : "";
    }
    var list = words(query);
    if (!list.length) return 0;
    var hay = " " + fold(text) + " ";
    var title = " " + fold(name);
    var points = 0, hits = 0;
    list.forEach(function (w) {
        var part = stem(w);
        if (title === " " + w) { points += 12; ++hits; return; }
        if (title.indexOf(" " + w) >= 0) { points += 7; ++hits; return; }
        if (hay.indexOf(" " + w + " ") >= 0) { points += 4; ++hits; return; }
        if (title.indexOf(" " + part) >= 0) { points += 6; ++hits; return; }
        if (hay.indexOf(" " + part) >= 0) { points += 2.5; ++hits; return; }
        var core = bare(w);
        if (core && hay.indexOf(" " + stem(core)) >= 0) { points += 2.5; ++hits; }
    });
    // Wszystkie słowa zapytania pasują: to prawie na pewno to
    if (hits && hits === list.length) points *= 1.5;
    return hits ? points : 0;
}

// Rozszerzenia plików: „czym otworzyć plik .psd”
var FILES = { psd: "zdjecia", ai: "rysowanie", cdr: "rysowanie", svg: "rysowanie", docx: "dokumenty", doc: "dokumenty", xlsx: "dokumenty", xls: "dokumenty",
              pptx: "dokumenty", ppt: "dokumenty", odt: "dokumenty", pdf: "pdf", exe: "windows", msi: "windows", mp4: "ogladanie", mkv: "ogladanie", avi: "ogladanie",
              mp3: "ogladanie", flac: "ogladanie", raw: "zdjecia", cr2: "zdjecia", nef: "zdjecia", dng: "zdjecia", zip: "pliki", rar: "pliki", "7z": "pliki", epub: "szkola" };

function fileTask(query) {
    var m = fold(query).match(/(?:^|[\s.])([a-z0-9]{2,5})$/) || [];
    var dotted = fold(query).match(/\.([a-z0-9]{2,5})\b/);
    var ext = dotted ? dotted[1] : (FILES[fold(query).trim()] ? fold(query).trim() : m[1]);
    return FILES[ext] && (dotted || fold(query).trim() === ext || /plik|otworzyc|otworze/.test(fold(query))) ? FILES[ext] : "";
}

// Polskie słowa → słowa, po których Flathub coś znajdzie (tam opisy są zwykle po angielsku)
var ENGLISH = { montaz: "video editor", film: "video", filmy: "video", wideo: "video", zdjecia: "photo", zdjecie: "photo", obraz: "image", rysowanie: "drawing",
                rysowac: "drawing", muzyka: "music", dzwiek: "audio", notatki: "notes", kalendarz: "calendar", poczta: "email", gry: "game", gra: "game",
                przegladarka: "browser", haslo: "password", hasla: "password", kopia: "backup", czat: "chat", komunikator: "messenger", tekst: "text editor",
                arkusz: "spreadsheet", prezentacja: "presentation", nauka: "education", fiszki: "flashcards", jezyk: "language learning", dzieci: "kids",
                pogoda: "weather", mapa: "map", mapy: "maps", tlumacz: "translator", skaner: "scanner", drukarka: "printer", ksiazki: "ebook", gotowanie: "recipes",
                przepisy: "recipes", pieniadze: "finance", budzet: "budget", faktury: "invoice", zadania: "tasks", nagrywanie: "recorder", dysk: "disk", szachy: "chess" };

function englishTerms(query) {
    var out = [];
    words(query).forEach(function (w) {
        if (ENGLISH[w]) { out.push(ENGLISH[w]); return; }
        var s = stem(w);
        for (var k in ENGLISH)
            if (k.indexOf(s) === 0) { out.push(ENGLISH[k]); return; }
        out.push(w);
    });
    return out.join(" ");
}

function refMeta(ref) {
    if (ref.indexOf("web:") === 0) return Catalog.web[ref.slice(4)];
    if (ref.indexOf("aster:") === 0) return Catalog.aster[ref.slice(6)];
    if (ref.indexOf("get:") === 0) return Catalog.get[ref.slice(4)];
    if (ref.indexOf("via:") === 0) return Catalog.via[ref.slice(4)];
    return Catalog.apps[ref];
}

// Wynik lokalny: { tasks: [zadanie], windows: [wpis], refs: [ref], flathub: "zapytanie" }
function local(query) {
    var tasks = [], switches = [], refs = [];

    Catalog.tasks.forEach(function (t) {
        var s = score(query, t.title, t.title + " " + t.tags);
        if (s > 0) tasks.push({ item: t, s: s });
    });
    var byFile = fileTask(query);
    if (byFile) Catalog.tasks.forEach(function (t) {
        if (t.id === byFile) { tasks = tasks.filter(function (x) { return x.item !== t; }); tasks.unshift({ item: t, s: 100 }); }
    });
    tasks.sort(function (a, b) { return b.s - a.s; });

    Catalog.windows.forEach(function (w) {
        var s = score(query, w.name, w.name);
        if (s >= 9) switches.push({ item: w, s: s });
    });
    switches.sort(function (a, b) { return b.s - a.s; });

    function addRefs(table, prefix) {
        Object.keys(table).forEach(function (k) {
            var m = table[k];
            var name = m.name || k.split(".").pop();
            var s = score(query, name, name + " " + m.pl + " " + (m.tags || ""));
            if (s > 0) refs.push({ item: prefix + k, s: s + (prefix === "aster:" ? 1 : 0) });
        });
    }
    addRefs(Catalog.apps, "");
    addRefs(Catalog.aster, "aster:");
    addRefs(Catalog.web, "web:");
    addRefs(Catalog.get, "get:");
    addRefs(Catalog.via, "via:");
    refs.sort(function (a, b) { return b.s - a.s; });
    // Słabe dopasowania odpadają, a wybór redakcji z najlepszego przewodnika idzie na początek
    var top = refs.length ? refs[0].s : 0;
    refs = refs.filter(function (r) { return r.s >= top * 0.4; });
    if (tasks.length && tasks[0].s >= 5) {
        var first = tasks[0].item.picks.map(function (p) { return p.ref; });
        refs = first.map(function (r) { return { item: r, s: 999 }; }).concat(refs.filter(function (r) { return first.indexOf(r.item) < 0; }));
    }

    // Dokładna nazwa zawsze na początku: kto pisze „claude”, chce Claude'a
    var wanted = fold(query).trim();
    function exact(r) { var m = refMeta(r.item), n = m && m.name; return n && fold(n).indexOf(wanted) === 0 ? 1 : 0; }
    refs = refs.map(function (r, i) { return { item: r.item, s: r.s, i: i }; }).sort(function (a, b) { return exact(b) - exact(a) || a.i - b.i; });

    return {
        tasks: tasks.slice(0, 3).map(function (x) { return x.item; }),
        windows: switches.slice(0, 3).map(function (x) { return x.item; }),
        refs: refs.slice(0, 18).map(function (x) { return x.item; }),
        flathub: englishTerms(query)
    };
}

// Przepis dla aster-get na ten procesor (null, gdy producent nie wydaje takiej wersji)
function recipe(ref, arch) {
    var key = ref.slice(4), m = Catalog.get[key];
    if (!m) return null;
    if (m.url && !m.url[arch]) return null;
    if (m.jsonUrl && !m.jsonUrl[arch]) return null;
    if (m.gh && !m.gh.asset[arch]) return null;
    var r = { id: key, name: m.name, type: m.type, exec: (m.execByArch && m.execByArch[arch]) || m.exec || "", cli: !!m.cli, args: m.args || [], command: m.commandName || "" };
    if (m.removeBin) r.removeBin = m.removeBin;
    if (m.url) r.url = m.url;
    if (m.apt) r.apt = m.apt;
    if (m.gh) r.gh = m.gh;
    if (m.jsonUrl) r.jsonUrl = m.jsonUrl;
    return r;
}

// ——— Aster Intelligence ———
function catalogForAssistant() {
    var lines = [];
    Catalog.tasks.forEach(function (t) { lines.push("zadanie " + t.id + ": " + t.title); });
    Object.keys(Catalog.apps).forEach(function (k) { lines.push(k + ": " + Catalog.apps[k].pl); });
    Object.keys(Catalog.web).forEach(function (k) { lines.push("web:" + k + ": " + Catalog.web[k].pl); });
    Object.keys(Catalog.aster).forEach(function (k) { lines.push("aster:" + k + ": " + Catalog.aster[k].pl); });
    Object.keys(Catalog.get).forEach(function (k) { lines.push("get:" + k + ": " + Catalog.get[k].pl); });
    Object.keys(Catalog.via).forEach(function (k) { lines.push("via:" + k + ": " + Catalog.via[k].pl); });
    return lines.join("\n");
}

function assistantPrompt(query) {
    return "Pomagasz w Sklepie Aster. Ktoś napisał, czego szuka: „" + query + "”. W kontekście jest katalog programów. "
         + "Wybierz najwyżej 4 pozycje z katalogu, które najlepiej pasują. Nie wymyślaj identyfikatorów spoza katalogu. "
         + "Gdy nic nie pasuje, zostaw pustą listę i podaj angielskie słowa do wyszukania. "
         + "Odpowiedz wyłącznie jednym obiektem JSON bez komentarza: "
         + '{"why":"jedno krótkie zdanie po polsku","refs":["identyfikator"],"search":"angielskie słowa kluczowe"}';
}

// Odpowiedź modelu → {why, refs, search}; nieznane identyfikatory wypadają, więc model niczego nie zmyśli
function parseAssistant(text) {
    var m = String(text).match(/\{[\s\S]*\}/);
    if (!m) return null;
    var data;
    try { data = JSON.parse(m[0]); } catch (e) { return null; }
    return {
        why: String(data.why || ""),
        refs: (Array.isArray(data.refs) ? data.refs : []).filter(function (r) { return !!refMeta(String(r)); }).slice(0, 4),
        search: String(data.search || "")
    };
}
