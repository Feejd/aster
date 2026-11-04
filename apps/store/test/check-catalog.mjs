// Test katalogu: każda pozycja istnieje naprawdę, wszystkie odnośniki się zgadzają, karta i wyszukiwanie działają na prawdziwych danych.
// Uruchomienie: node apps/store/test/check-catalog.mjs (potrzebny internet)
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";

const qml = join(dirname(fileURLToPath(import.meta.url)), "../qml");
const load = (file, extra = {}) => {
    const src = readFileSync(join(qml, file), "utf8").replace(/^\.pragma.*$/m, "").replace(/^\.import.*$/m, "");
    const ctx = vm.createContext({ ...extra, console, Date, JSON, Math });
    vm.runInContext(src, ctx);
    return ctx;
};
const Catalog = load("Catalog.js");
const Facts = load("Facts.js");
const Find = load("Find.js", { Catalog });

let failed = 0;
const fail = (m) => { console.log("BŁĄD:", m); ++failed; };
const check = (ok, m) => { if (!ok) fail(m); };

// Odnośniki
const refs = new Set();
Catalog.tasks.forEach(t => t.picks.forEach(p => refs.add(p.ref)));
Catalog.windows.forEach(w => [w.pick, w.keep, w.alt].filter(Boolean).forEach(r => refs.add(r)));
Object.values(Catalog.apps).forEach(a => a.web && refs.add("web:" + a.web));
for (const r of refs) check(Find.refMeta(r), "nieznany odnośnik " + r);
const cats = new Set(Catalog.categories.map(c => c.id));
for (const table of [Catalog.apps, Catalog.web, Catalog.aster])
    for (const [k, v] of Object.entries(table)) {
        check(cats.has(v.cat), k + ": nieznany dział " + v.cat);
        check(v.pl && v.pl.length < 95, k + ": opis pusty albo za długi na wiersz (" + (v.pl || "").length + ")");
    }
for (const t of Catalog.tasks) check(t.picks.some(p => p.role === "Najlepszy wybór" || p.on), t.id + ": brak wyboru domyślnego");

// Prawdziwe dane
const get = async (u) => { const r = await fetch(u, { headers: { "User-Agent": "AsterStoreTest" } }); return r.ok ? r.json() : null; };
const ids = Object.keys(Catalog.apps);
const lines = {};
let warnings = 0;
for (let i = 0; i < ids.length; i += 8) {
    await Promise.all(ids.slice(i, i + 8).map(async (id) => {
        const [app, summary] = await Promise.all([get(`https://flathub.org/api/v2/appstream/${id}?locale=pl`), get(`https://flathub.org/api/v2/summary/${id}`)]);
        if (!app || !summary) return fail("nie ma takiego programu: " + id);
        if (app.is_eol) fail("porzucony program w katalogu: " + id);
        const card = Facts.cardLines({ kind: "app", app, summary, meta: Catalog.apps[id], arch: "x86_64", memoryGb: 8 });
        lines[id] = card;
        for (const l of card) {
            check(["ok", "warn", "bad", "info", "unknown"].includes(l.tone), id + ": zły ton " + l.tone);
            check(l.text && !/undefined|NaN|null/.test(l.text), id + ": zły tekst: " + l.text);
            if (l.tone === "bad") { console.log("uwaga:", id, "—", l.text); ++warnings; }
        }
        check(Facts.diskBill(summary, false).total > 0, id + ": brak rozmiaru");
    }));
}
console.log(ids.length, "programów sprawdzonych z prawdziwymi danymi,", warnings, "z czerwoną kartą");

// Porównanie
const row = Facts.compareRows([{ kind: "web", meta: Catalog.web.word }, { kind: "aster", meta: Catalog.aster.pdf }]);
check(row.length > 5 && row.every(r => r.values.length === 2), "porównanie");

// Wyszukiwanie po tym, co chcesz zrobić
const cases = [
    ["zmontować film z wakacji", "film"], ["zmontowac film", "film"], ["otworzyć plik .psd", "zdjecia"], ["psd", "zdjecia"], ["czym otworzyć exe", "windows"],
    ["chcę pograć w gry", "gry"], ["napisać cv", "dokumenty"], ["rozpakować rar", "pliki"], ["nagrać ekran", "nagrywanie"], ["podpisać pdf", "pdf"], ["fiszki do angielskiego", "szkola"],
];
for (const [q, want] of cases) {
    const r = Find.local(q);
    check(r.tasks.length && r.tasks[0].id === want, `„${q}” → ${r.tasks.map(t => t.id)} zamiast ${want}`);
}
for (const [q, want] of [["zamiast photoshopa", "Photoshop"], ["word", "Word"], ["premiere", "Premiere Pro"], ["winrar", "WinRAR / 7-Zip"]]) {
    const r = Find.local(q);
    check(r.windows.length && r.windows[0].name === want, `„${q}” → ${r.windows.map(w => w.name)} zamiast ${want}`);
}
check(Find.local("gimp").refs[0] === "org.gimp.GIMP", "gimp");
check(Find.parseAssistant('Oto: {"why":"x","refs":["org.gimp.GIMP","wymyslone.id"],"search":"a"}').refs.length === 1, "asystent nie może wymyślać programów");

console.log(failed ? failed + " błędów" : "Wszystko się zgadza");
process.exit(failed ? 1 : 0);
