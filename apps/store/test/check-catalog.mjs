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
const shelved = new Set();
for (const c of Object.keys(Catalog.shelves)) {
    check(cats.has(c), "półka bez działu: " + c);
    for (const shelf of Catalog.shelves[c]) for (const r of shelf.refs) { refs.add(r); shelved.add(r); }
}
for (const r of [...Catalog.top, ...Catalog.homeAi, ...Catalog.homeGames]) refs.add(r);
for (const k of Object.keys(Catalog.apps)) check(shelved.has(k), "bez półki: " + k);
for (const k of Object.keys(Catalog.web)) check(shelved.has("web:" + k), "bez półki: web:" + k);
for (const k of Object.keys(Catalog.get)) check(shelved.has("get:" + k), "bez półki: get:" + k);
for (const table of [Catalog.apps, Catalog.web, Catalog.aster, Catalog.get, Catalog.via])
    for (const [k, v] of Object.entries(table)) {
        check(cats.has(v.cat), k + ": nieznany dział " + v.cat);
        check(v.pl && v.pl.length < 95, k + ": opis pusty albo za długi na wiersz (" + (v.pl || "").length + ")");
    }
for (const t of Catalog.tasks) check(t.picks.some(p => p.role === "Najlepszy wybór" || p.on), t.id + ": brak wyboru domyślnego");

// Prawdziwe dane
const get = async (u) => { try { const r = await fetch(u, { signal: AbortSignal.timeout(25000), headers: { "User-Agent": "AsterStoreTest" } }); return r.ok ? r.json() : null; } catch { return null; } };
const ids = Object.keys(Catalog.apps);
const lines = {};
let warnings = 0;
const x86 = [];
for (let i = 0; i < ids.length; i += 8) {
    await Promise.all(ids.slice(i, i + 8).map(async (id) => {
        const [app, summary] = await Promise.all([get(`https://flathub.org/api/v2/appstream/${id}?locale=pl`), get(`https://flathub.org/api/v2/summary/${id}`)]);
        if (!app || !summary) return fail("nie ma takiego programu: " + id);
        if (app.is_eol) fail("porzucony program w katalogu: " + id);
        const card = Facts.cardLines({ kind: "app", app, summary, meta: Catalog.apps[id], arch: "x86_64", memoryGb: 8 });
        lines[id] = card;
        if (summary.arches && !summary.arches.includes("aarch64")) x86.push(id);
        for (const l of card) {
            check(["ok", "warn", "bad", "info", "unknown"].includes(l.tone), id + ": zły ton " + l.tone);
            check(l.text && !/undefined|NaN|null/.test(l.text), id + ": zły tekst: " + l.text);
            if (l.tone === "bad") { console.log("uwaga:", id, "—", l.text); ++warnings; }
        }
        check(Facts.diskBill(summary, false).total > 0, id + ": brak rozmiaru");
    }));
}
const known = new Set(Catalog.x86Only);
if (x86.length !== known.size || x86.some(i => !known.has(i))) fail("nieaktualna lista x86Only: " + JSON.stringify(x86.sort()));
console.log(ids.length, "programów sprawdzonych z prawdziwymi danymi,", warnings, "z czerwoną kartą");

// Programy od producentów: czy adresy naprawdę działają, dla każdego procesora
const head = async (u) => {
    // Tylko nagłówki: odpowiedź przerywamy, zanim zacznie się pobieranie gigabajtów
    const stop = new AbortController();
    const timer = setTimeout(() => stop.abort(), 20000);
    try {
        const r = await fetch(u, { redirect: "follow", signal: stop.signal, headers: { "User-Agent": "Mozilla/5.0 AsterStoreTest" } });
        stop.abort();
        return r.status < 400;
    } catch { return false; } finally { clearTimeout(timer); }
};
for (const k of Object.keys(Catalog.get)) {
    for (const arch of ["x86_64", "aarch64"]) {
        const r = Find.recipe("get:" + k, arch);
        if (!r) { console.log("uwaga:", k, "nie ma wersji na", arch); continue; }
        if (r.url && !(await head(r.url[arch]))) fail(k + ": nie działa adres " + r.url[arch]);
        if (r.jsonUrl) check(await get(r.jsonUrl[arch]), k + ": adres JSON");
        if (r.apt) { const d = { x86_64: "amd64", aarch64: "arm64" }[arch]; check(await head(`${r.apt.base}/dists/stable/main/binary-${d}/Packages`), k + ": indeks apt"); }
    }
}
for (const [k, m] of Object.entries(Catalog.via)) check(await get("https://lutris.net/api/games/" + m.slug), "via " + k);
const webBad = [];
for (const [k, m] of Object.entries(Catalog.web)) if (!(await head(m.url))) webBad.push(k);
if (webBad.length) console.log("uwaga: strony nie odpowiadają automatom:", webBad.join(" "));

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
for (const [q, want] of [["claude", "get:claude-desktop"], ["chatgpt", "web:chatgpt"], ["cursor", "get:cursor"], ["netflix", "web:netflix"], ["roblox", "org.vinegarhq.Sober"], ["battle.net", "via:battlenet"], ["steam", "com.valvesoftware.Steam"]])
    check(Find.local(q).refs.includes(want), `„${q}” nie znajduje ${want}: ${Find.local(q).refs.slice(0, 5)}`);
check(Find.parseAssistant('Oto: {"why":"x","refs":["org.gimp.GIMP","wymyslone.id"],"search":"a"}').refs.length === 1, "asystent nie może wymyślać programów");

console.log(failed ? failed + " błędów" : "Wszystko się zgadza");
process.exit(failed ? 1 : 0);
