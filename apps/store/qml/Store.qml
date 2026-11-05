pragma Singleton
import QtQuick
import Aster.Store
import "Catalog.js" as Catalog
import "Facts.js" as Facts
import "Find.js" as Find

// Serce sklepu: jedno miejsce na dane o programach z każdego źródła. Strony pytają o ref i nie wiedzą,
// skąd program pochodzi. Flathub jest jednym z dostawców danych i paczek, nie tożsamością sklepu.
QtObject {
    id: store
    readonly property string api: "https://flathub.org/api/v2/"
    readonly property string odrs: "https://odrs.gnome.org/1.0/reviews/api/"

    property var items: ({})
    property var summaries: ({})
    property var ratings: ({})
    property int version: 0
    property var compare: []
    property var outside: ({})                  // programy spoza katalogu, poznane z wyszukiwania

    signal toast(string text)
    signal requestOpen(string ref)
    signal requestRemove(string ref)

    // Dane spływają paczkami: jedno przeliczenie zamiast kilkudziesięciu (ważne na słabym procesorze)
    property Timer flush: Timer { interval: 40; onTriggered: store.version++ }
    function touched() { if (!flush.running) flush.start(); }

    function kindOf(ref) {
        if (!ref) return "app";
        return ref.indexOf("web:") === 0 ? "web" : ref.indexOf("aster:") === 0 ? "aster" : ref.indexOf("get:") === 0 ? "get"
             : ref.indexOf("via:") === 0 ? "via" : "app";
    }
    function meta(ref) { return Find.refMeta(ref) || null; }
    // Identyfikator z flatpaka → pozycja katalogu (aplikacje Aster mają własne odnośniki)
    function refOf(id) {
        for (const k in Catalog.aster) if (Catalog.aster[k].id === id) return "aster:" + k;
        return id;
    }

    function item(ref) {
        const kind = kindOf(ref), m = meta(ref);
        if (kind === "web") return { ref: ref, kind: kind, name: m.name, summary: m.pl, color: m.color, dev: "", meta: m, icon: faviconOf(m.url) };
        if (kind === "get" || kind === "via") return { ref: ref, kind: kind, name: m.name, summary: m.pl, color: "", dev: m.site, meta: m, icon: faviconOf("https://" + m.site) };
        if (kind === "aster") return { ref: ref, kind: kind, id: m.id, name: m.name, summary: m.pl, dev: "Aster", meta: m };
        const known = items[ref];
        if (known) return known;
        const seen = outside[ref];
        if (seen) return seen;
        loadApp(ref);
        return { ref: ref, kind: kind, id: ref, name: ref.split(".").pop(), summary: m ? m.pl : "", icon: "", dev: "", meta: m };
    }
    // Znak firmowy prosto ze strony producenta; gdy nie przyjdzie, zostaje kafel z literą
    function faviconOf(url) { return "https://www.google.com/s2/favicons?sz=128&domain_url=" + encodeURIComponent(url); }
    property var asked: ({})
    function loadApp(id) {
        if (asked[id]) return;
        asked[id] = true;
        Net.get(api + "appstream/" + id + "?locale=pl", 3 * 86400, (d) => {
            if (!d) return;
            const m = meta(id);
            items[id] = { ref: id, kind: "app", id: id, name: d.name, summary: m ? m.pl : (d.summary || ""), icon: d.icon || "",
                          dev: d.developer_name || "", meta: m, app: d };
            touched();
        });
    }
    function summary(id, cb) {
        if (summaries[id]) { cb(summaries[id]); return; }
        Net.get(api + "summary/" + id, 86400, (d) => { if (d) { summaries[id] = d; touched(); } cb(d); });
    }
    function rating(id, cb) {
        if (ratings[id] !== undefined) { cb(ratings[id]); return; }
        Net.get(odrs + "ratings/" + id, 7 * 86400, (d) => { ratings[id] = d; touched(); cb(d); });
    }
    function reviews(id, cb) {
        // Skrót anonimowy: serwis wymaga pola user_hash, nie wysyłamy nic o użytkowniku
        Net.post(odrs + "fetch", { app_id: id, user_hash: "0000000000000000000000000000000000000000", locale: Qt.locale().name, distro: "Aster",
                                   version: "1", limit: 8, karma: 0 }, 86400, cb);
    }

    // Program spoza katalogu z wyników wyszukiwania
    function fromHit(h) {
        const id = h.app_id;
        const o = { ref: id, kind: "app", id: id, name: h.name, summary: h.summary || "", icon: h.icon || "", dev: h.developer_name || "", meta: null };
        outside[id] = o;
        return o;
    }

    function state(ref) {
        const kind = kindOf(ref);
        if (kind === "web") return Flatpak.webApps[meta(ref).url] ? "installed" : "none";
        if (kind === "get") return Flatpak.getApps[ref.slice(4)] ? "installed" : "none";
        if (kind === "via") return Flatpak.installed.indexOf(meta(ref).host) >= 0 ? "installed" : "none";
        if (kind === "aster") {
            const m = meta(ref);
            if (Flatpak.hasExecutable(m.exec)) return "builtin";
            return Flatpak.installed.indexOf(m.id) >= 0 ? "installed" : "none";
        }
        return Flatpak.installed.indexOf(ref) >= 0 ? "installed" : "none";
    }
    function isInstalled(ref) { const s = state(ref); return s === "installed" || s === "builtin"; }
    function jobKey(ref) {
        const kind = kindOf(ref);
        if (kind === "via") return meta(ref).host;
        return kind === "aster" ? meta(ref).id : ref;
    }
    function canInstall(ref) {
        const kind = kindOf(ref);
        if (kind === "web") return Flatpak.webAppsAvailable;
        if (kind === "get") { const m = meta(ref); return !!Find.recipe(ref, Flatpak.arch); }
        if (kind === "via") return Flatpak.available && Flatpak.arch === "x86_64";
        if (!Flatpak.available) return false;
        if (kind !== "app") return true;
        if (Flatpak.arch !== "x86_64" && Catalog.x86Only.indexOf(ref) >= 0) return false;
        const s = summaries[ref];
        return !(s && s.arches && s.arches.length && s.arches.indexOf(Flatpak.arch) < 0);
    }
    function install(ref) {
        const kind = kindOf(ref), m = meta(ref);
        if (kind === "web") Flatpak.addWebApp(ref, m.url, m.name, m.category, m.color || "");
        else if (kind === "get") Flatpak.installGet(ref, JSON.stringify(Find.recipe(ref, Flatpak.arch)));
        else if (kind === "via") Flatpak.install(m.host);
        else if (kind === "aster") Flatpak.installBundle(m.id, ref.slice(6));
        else Flatpak.install(ref);
    }
    function launch(ref) {
        const kind = kindOf(ref), m = meta(ref);
        if (kind === "web") Flatpak.launchWebApp(Flatpak.webApps[m.url]);
        else if (kind === "get") { if (m.cli) toast("To program do terminala: wpisz " + (m.commandName || ref.slice(4))); else Flatpak.launchGet(ref); }
        else if (kind === "via") Flatpak.launchWith(m.host, "lutris:" + m.slug);
        else if (kind === "aster" && state(ref) === "builtin") Flatpak.launchExecutable(m.exec);
        else Flatpak.launch(kind === "aster" ? m.id : ref);
    }
    function act(ref) {
        if (isInstalled(ref)) launch(ref);
        else install(ref);
    }
    function installMany(refs) { refs.forEach(r => { if (!isInstalled(r) && canInstall(r)) install(r); }); }
    function openApp(ref) { requestOpen(ref); }
    function nameOf(key) {
        const m = /^(web|get|via):/.test(key) ? meta(key) : null;
        if (m) return m.name;
        for (const k in Catalog.aster) if (Catalog.aster[k].id === key) return Catalog.aster[k].name;
        const known = items[key] || outside[key];
        if (known) return known.name;
        const listed = Flatpak.installedApps.find(a => a.id === key);
        return listed ? listed.name : key;
    }

    function toggleCompare(ref) {
        const list = compare.slice();
        const i = list.indexOf(ref);
        if (i >= 0) list.splice(i, 1);
        else {
            if (list.length >= 4) { toast("Porównasz najwyżej cztery programy naraz"); return; }
            list.push(ref);
        }
        compare = list;
    }

    // ——— Komunikaty z instalatora ———
    property Connections jobs: Connections {
        target: Flatpak
        function onFinished(appId, action, ok, message) {
            const name = store.nameOf(appId);
            if (!ok) {
                store.toast((action === "install" || action === "bundle" || action === "webadd" || action === "get" ? "Nie udało się zainstalować: " : "Nie udało się: ") + name + (message ? ". " + message : ""));
                return;
            }
            if (action === "get" && (store.meta(appId) || {}).cli) store.toast(name + ": gotowe, działa w terminalu");
            else if (action === "install" || action === "bundle" || action === "webadd" || action === "get") store.toast(name + " już czeka w Starcie");
            else if (action === "uninstall" || action === "webremove" || action === "getremove") store.toast("Usunięto: " + name);
            else if (action === "rollback") store.toast(name + ": wróciła poprzednia wersja");
            else if (action === "prune") store.toast("Posprzątane");
            else if (appId === "*") store.toast("Wszystko jest aktualne");
            else store.toast(name + ": zaktualizowano");
        }
    }
    function requestRemoval(ref) { requestRemove(ref); }
}
