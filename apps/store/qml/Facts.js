.pragma library

// Karta programu: uczciwe informacje liczone z prawdziwych danych (uprawnienia piaskownicy, rozmiary, daty)
// plus to, co sprawdziła redakcja. Czego nie wiemy, tego nie zgadujemy: wiersz mówi „nie sprawdziliśmy”.
// Ton wiersza: ok | warn | bad | info | unknown. Bez zależności od QML; test: apps/store/test/check-catalog.mjs.

var DAY = 86400;

function size(bytes) {
    if (!bytes || bytes < 0) return "—";
    if (bytes >= 1e9) return (bytes / 1e9).toFixed(1).replace(".", ",") + " GB";
    if (bytes >= 1e6) return Math.round(bytes / 1e6) + " MB";
    return Math.max(1, Math.round(bytes / 1e3)) + " kB";
}

function count(n) {
    if (!n) return "—";
    if (n >= 1000000) return (n / 1000000).toFixed(1).replace(".", ",") + " mln";
    if (n >= 1000) return Math.round(n / 1000) + " tys.";
    return String(n);
}

function plural(n, one, few, many) {
    if (n === 1) return one;
    var d = n % 10, t = n % 100;
    return (d >= 2 && d <= 4 && !(t >= 12 && t <= 14)) ? few : many;
}

// „3 dni temu”, „5 miesięcy temu”
function ago(seconds, now) {
    var days = Math.floor(((now || Date.now() / 1000) - seconds) / DAY);
    if (days < 1) return "dzisiaj";
    if (days === 1) return "wczoraj";
    if (days < 30) return days + " " + plural(days, "dzień", "dni", "dni") + " temu";
    var months = Math.floor(days / 30.4);
    if (months < 12) return months + " " + plural(months, "miesiąc", "miesiące", "miesięcy") + " temu";
    var years = Math.floor(days / 365);
    return years + " " + plural(years, "rok", "lata", "lat") + " temu";
}

// ——— Piaskownica ———
// Uprawnienia Flatpaka → to, co program faktycznie może
function sandbox(perm) {
    perm = perm || {};
    var fs = perm.filesystems || [], shared = perm.shared || [], sockets = perm.sockets || [], devices = perm.devices || [];
    var talk = (perm["session-bus"] && perm["session-bus"].talk) || [];
    var own = fs.map(function (f) { return String(f).replace(/:(ro|rw|create)$/, ""); });
    var readOnly = function (name) { return fs.some(function (f) { return String(f).indexOf(name) === 0 && /:ro$/.test(f); }); };

    var files = "wskazane";
    if (own.indexOf("host") >= 0) files = readOnly("host") ? "wszystko-odczyt" : "wszystko";
    else if (own.indexOf("host-os") >= 0) files = "wszystko-odczyt";
    else if (own.indexOf("home") >= 0) files = readOnly("home") ? "domowy-odczyt" : "domowy";

    // Foldery użytkownika nazwane po ludzku (konfiguracje i gniazda nie są „plikami”)
    var names = { "xdg-download": "Pobrane", "xdg-documents": "Dokumenty", "xdg-pictures": "Obrazy", "xdg-music": "Muzyka", "xdg-videos": "Wideo", "xdg-desktop": "Pulpit" };
    var folders = [];
    own.forEach(function (f) {
        var base = f.split("/")[0];
        if (names[base] && folders.indexOf(names[base]) < 0) folders.push(names[base]);
    });
    if (files === "wskazane" && folders.length) files = "foldery";

    return {
        files: files,
        folders: folders,
        network: shared.indexOf("network") >= 0,
        devicesAll: devices.indexOf("all") >= 0,
        audio: sockets.indexOf("pulseaudio") >= 0 || own.some(function (f) { return f.indexOf("xdg-run/pipewire") === 0; }),
        bluetooth: sockets.indexOf("bluetooth") >= 0,
        // Prawdziwe X11 (nie „fallback-x11”, używane tylko bez Waylanda) pozwala podglądać inne okna
        x11: sockets.indexOf("x11") >= 0,
        // Rozmowa z org.freedesktop.Flatpak to wyjście poza piaskownicę
        escape: talk.indexOf("org.freedesktop.Flatpak") >= 0
    };
}

// ——— Karta ———
// d: { summary (Flathub /summary), app (appstream), meta (nasz wpis), hasRuntime, arch, memoryGb, kind }
function cardLines(d) {
    var lines = [];
    var meta = d.meta || {};

    function line(key, tone, title, text) { lines.push({ key: key, tone: tone, title: title, text: text || "" }); }

    if (d.kind === "web") {
        line("files", "ok", "Pliki", "Działa w osobnym oknie jak strona. Widzi tylko pliki, które do niej wyślesz.");
        line("net", "info", "Internet", "Bez internetu nie działa.");
        line("disk", "ok", "Miejsce", "Prawie nic nie zajmuje na dysku.");
        accountLines(line, meta);
        return lines;
    }
    if (d.kind === "aster") {
        line("files", "ok", "Pochodzenie", "Część systemu Aster, rozwijana przez nas.");
        line("code", "ok", "Kod", "Otwarty: każdy może sprawdzić, co program robi.");
        accountLines(line, meta);
        return lines;
    }

    var p = d.summary && d.summary.metadata ? sandbox(d.summary.metadata.permissions) : null;
    if (p) {
        // Pliki
        if (p.files === "wskazane") line("files", "ok", "Twoje pliki", "Widzi tylko pliki, które otworzysz.");
        else if (p.files === "foldery") line("files", "ok", "Twoje pliki", "Widzi tylko foldery: " + p.folders.join(", ") + ".");
        else if (p.files === "domowy-odczyt") line("files", "warn", "Twoje pliki", "Może czytać wszystko w Twoim folderze domowym.");
        else if (p.files === "domowy") line("files", "warn", "Twoje pliki", "Może czytać i zmieniać wszystko w Twoim folderze domowym.");
        else if (p.files === "wszystko-odczyt") line("files", "warn", "Twoje pliki", "Może czytać wszystkie pliki na komputerze.");
        else line("files", "warn", "Twoje pliki", "Może czytać i zmieniać wszystkie Twoje pliki, także na pendrive'ach.");

        // Internet i dane
        if (!p.network) line("net", "ok", "Internet i dane", "Nie ma dostępu do sieci, więc nie może nic wysłać.");
        else if (meta.offline === "tak") line("net", "info", "Internet i dane", "Działa bez internetu. Ma dostęp do sieci, a co wysyła, tego nie sprawdziliśmy.");
        else if (meta.offline === "czesc") line("net", "info", "Internet i dane", "Część funkcji działa bez internetu.");
        else if (meta.offline === "nie") line("net", "info", "Internet i dane", "Wymaga internetu.");
        else line("net", "unknown", "Internet i dane", "Ma dostęp do sieci. Nie sprawdziliśmy, co wysyła.");

        // Urządzenia
        var dev = [];
        if (p.devicesAll) dev.push("kamera, pendrive'y i inne urządzenia");
        if (p.audio) dev.push("mikrofon");
        if (p.bluetooth) dev.push("Bluetooth");
        if (dev.length) line("dev", p.devicesAll ? "warn" : "info", "Urządzenia", "Dostęp: " + dev.join(", ") + ".");
        else line("dev", "ok", "Urządzenia", "Bez kamery i mikrofonu.");

        // Izolacja
        if (p.escape) line("sandbox", "warn", "Izolacja", "Może uruchamiać polecenia poza piaskownicą, więc izolacja go nie chroni.");
        else if (p.x11) line("sandbox", "warn", "Izolacja", "Stary tryb okien: w teorii może podglądać inne programy.");
        else line("sandbox", "ok", "Izolacja", "Działa w piaskownicy, oddzielony od reszty systemu.");
    } else {
        line("files", "unknown", "Uprawnienia", "Nie udało się ich sprawdzić.");
    }

    accountLines(line, meta);

    // Aktualizacje: data ostatniej paczki, nie deklaracja autora
    var app = d.app || {}, stamp = (d.summary && d.summary.timestamp) || 0;
    var rel = app.releases && app.releases.length ? Number(app.releases[0].timestamp) || 0 : 0;
    stamp = Math.max(stamp, rel);
    if (app.is_eol) line("update", "bad", "Aktualizacje", "Autorzy porzucili tę paczkę. Nie instaluj.");
    else if (d.summary && d.summary.metadata && d.summary.metadata.runtimeIsEol) line("update", "bad", "Aktualizacje", "Opiera się na bibliotekach bez poprawek bezpieczeństwa.");
    else if (stamp) {
        var days = (Date.now() / 1000 - stamp) / DAY;
        line("update", days > 900 ? "bad" : days > 400 ? "warn" : "ok", "Aktualizacje", "Ostatnia aktualizacja: " + ago(stamp) + (days > 900 ? ". Wygląda na porzucony." : "."));
    } else line("update", "unknown", "Aktualizacje", "Brak daty ostatniej wersji.");

    // Wydawca i kod
    var m = app.metadata || {};
    if (m["flathub::verification::verified"]) {
        var who = m["flathub::verification::website"] || "";
        line("who", "ok", "Wydawca", "Potwierdzony" + (who ? ": " + who : "") + ".");
    } else line("who", "warn", "Wydawca", "Paczkę przygotowała społeczność, a nie autorzy programu.");
    if (app.id) line("code", app.is_free_license ? "ok" : "info", "Kod", app.is_free_license ? "Otwarty: każdy może sprawdzić, co program robi." : "Zamknięty: wierzysz autorowi na słowo.");

    // Ten komputer
    var fit = fitness(d);
    if (fit) line("fit", fit.tone, "Na tym komputerze", fit.text);
    return lines;
}

function accountLines(line, meta) {
    if (meta.account === "tak") line("account", "info", "Konto", "Bez konta nie skorzystasz.");
    else if (meta.account === "opcja") line("account", "ok", "Konto", "Możesz, ale nie musisz go zakładać.");
    else if (meta.account === "nie") line("account", "ok", "Konto", "Bez konta.");
    else line("account", "unknown", "Konto", "Nie sprawdziliśmy.");

    var ads = meta.ads ? " Z reklamami." : "";
    if (meta.cost === "free") line("cost", meta.ads ? "info" : "ok", "Cena", "Bezpłatny." + ads);
    else if (meta.cost === "freemium") line("cost", "info", "Cena", "Podstawa bezpłatna, reszta płatna." + ads);
    else if (meta.cost === "paid") line("cost", "warn", "Cena", "Płatny." + ads);
    else line("cost", "unknown", "Cena", "Nie sprawdziliśmy.");
}

function isElectron(summary) {
    var base = summary && summary.metadata ? (summary.metadata.base || "") : "";
    return /electron/i.test(base);
}

// Czy pójdzie na tym komputerze
function fitness(d) {
    var s = d.summary;
    if (d.arch && s && s.arches && s.arches.length && s.arches.indexOf(d.arch) < 0)
        return { tone: "bad", block: true, text: "Nie ma wersji na ten procesor." };
    var heavy = d.meta && d.meta.heavy !== undefined ? d.meta.heavy : (isElectron(s) ? 2 : -1);
    var gb = d.memoryGb || 0;
    if (heavy < 0) return null;
    if (heavy === 2 && gb > 0 && gb < 12)
        return { tone: "warn", text: (isElectron(s) ? "Zbudowany na przeglądarce, więc zużywa sporo pamięci." : "Wymagający.") + " Przy " + Math.round(gb) + " GB RAM zamykaj inne programy." };
    if (heavy === 2) return { tone: "info", text: "Wymagający, ale tu pamięci wystarczy." };
    if (heavy === 1) return { tone: "ok", text: "Pójdzie płynnie." };
    return { tone: "ok", text: "Lekki, pójdzie nawet na starym sprzęcie." };
}

// Prawdziwy rachunek za dysk: program + biblioteki, jeśli jeszcze ich nie ma
function diskBill(summary, hasRuntime) {
    if (!summary) return null;
    var runtime = summary.metadata ? (summary.metadata.runtimeInstalledSize || 0) : 0;
    var extra = hasRuntime ? 0 : runtime;
    return { download: summary.download_size || 0, app: summary.installed_size || 0, runtime: runtime, extra: extra,
             total: (summary.installed_size || 0) + extra, shared: hasRuntime };
}

function billText(bill) {
    if (!bill) return "";
    if (bill.extra > 0) return size(bill.app) + " program + " + size(bill.extra) + " bibliotek";
    return size(bill.app) + " (biblioteki już masz)";
}

// „org.gnome.Platform/x86_64/51” → czy taki zestaw jest w installed (bez względu na procesor)
function runtimeInstalled(runtimeRef, installed) {
    if (!runtimeRef) return false;
    var parts = runtimeRef.split("/");
    var keys = Object.keys(installed || {});
    for (var i = 0; i < keys.length; ++i) {
        var k = keys[i].split("/");
        if (k[0] === parts[0] && k[2] === parts[2]) return true;
    }
    return false;
}

// Podsumowanie karty jednym zdaniem
function verdict(lines) {
    var bad = 0, warn = 0, unknown = 0;
    lines.forEach(function (l) {
        if (l.tone === "bad") ++bad;
        else if (l.tone === "warn") ++warn;
        else if (l.tone === "unknown") ++unknown;
    });
    if (bad) return { tone: "bad", text: "Uważaj" };
    if (warn >= 3) return { tone: "warn", text: "Zajrzyj w szczegóły" };
    if (warn) return { tone: "warn", text: warn === 1 ? "Jedna rzecz do wiedzy" : "Dwie rzeczy do wiedzy" };
    return { tone: "ok", text: "Bez zastrzeżeń" };
}

// Oceny: procent polecających (4 i 5 gwiazdek) zamiast średniej, która zawsze wychodzi koło 4
function rating(r) {
    if (!r || !r.total) return null;
    var total = (r.star1 || 0) + (r.star2 || 0) + (r.star3 || 0) + (r.star4 || 0) + (r.star5 || 0);
    if (total < 5) return null;
    return { percent: Math.round(100 * ((r.star4 || 0) + (r.star5 || 0)) / total), total: total };
}

// Wiersze porównania: [{label, values:[…], best: indeks najlepszego lub -1}]
function compareRows(list) {
    function row(label, get, better) {
        var raw = list.map(get);
        var best = -1;
        if (better) {
            var nums = raw.map(function (v) { return v.n; });
            var valid = nums.filter(function (n) { return n !== undefined && n !== null; });
            if (valid.length >= 2) {
                var top = better === "min" ? Math.min.apply(null, valid) : Math.max.apply(null, valid);
                var same = nums.filter(function (n) { return n === top; }).length;
                if (same === 1 && Math.min.apply(null, valid) !== Math.max.apply(null, valid)) best = nums.indexOf(top);
            }
        }
        return { label: label, values: raw.map(function (v) { return v.t; }), best: best };
    }
    var sbox = function (x) { return x.summary && x.summary.metadata ? sandbox(x.summary.metadata.permissions) : null; };
    return [
        row("Zajmie na dysku", function (x) {
            if (x.kind === "web") return { t: "Prawie nic", n: 0 };
            if (x.kind === "aster") return { t: "W systemie", n: 0 };
            var bill = diskBill(x.summary, x.hasRuntime);
            return bill ? { t: size(bill.total), n: bill.total } : { t: "—" };
        }, "min"),
        row("Bez internetu", function (x) {
            var m = x.meta || {}, v = m.offline;
            if (v === "tak") return { t: "Działa", n: 2 };
            if (v === "czesc") return { t: "Częściowo", n: 1 };
            if (v === "nie") return { t: "Nie działa", n: 0 };
            return { t: "Nie sprawdziliśmy" };
        }, "max"),
        row("Twoje pliki", function (x) {
            if (x.kind !== "app") return { t: "Tylko wskazane", n: 2 };
            var p = sbox(x);
            if (!p) return { t: "—" };
            if (p.files === "wskazane" || p.files === "foldery") return { t: "Tylko wskazane", n: 2 };
            if (/domowy/.test(p.files)) return { t: "Folder domowy", n: 1 };
            return { t: "Wszystkie", n: 0 };
        }, "max"),
        row("Obciążenie", function (x) {
            var m = x.meta || {};
            var h = m.heavy !== undefined ? m.heavy : (isElectron(x.summary) ? 2 : undefined);
            if (x.kind === "web") return { t: "Jak karta przeglądarki", n: 1 };
            if (h === undefined) return { t: "Nie sprawdziliśmy" };
            return { t: ["Lekki", "Średni", "Ciężki"][h], n: h };
        }, "min"),
        row("Konto", function (x) {
            var a = (x.meta || {}).account;
            return a === "nie" ? { t: "Niepotrzebne", n: 2 } : a === "opcja" ? { t: "Opcjonalne", n: 1 } : a === "tak" ? { t: "Wymagane", n: 0 } : { t: "Nie sprawdziliśmy" };
        }, "max"),
        row("Cena", function (x) {
            var c = (x.meta || {}).cost;
            var ads = (x.meta || {}).ads ? " z reklamami" : "";
            return c === "free" ? { t: "Bezpłatny" + ads, n: ads ? 1 : 2 } : c === "freemium" ? { t: "Darmowy z płatną częścią" + ads, n: 1 } : c === "paid" ? { t: "Płatny", n: 0 } : { t: "Nie sprawdziliśmy" };
        }, "max"),
        row("Kod", function (x) {
            if (x.kind === "web") return { t: "Zamknięty" };
            if (x.kind === "aster") return { t: "Otwarty" };
            return x.app ? { t: x.app.is_free_license ? "Otwarty" : "Zamknięty" } : { t: "—" };
        }),
        row("Ostatnia aktualizacja", function (x) {
            if (x.kind !== "app") return { t: "Na bieżąco" };
            var s = x.summary ? x.summary.timestamp : 0;
            return s ? { t: ago(s), n: s } : { t: "—" };
        }, "max"),
        row("Poleca", function (x) {
            var r = rating(x.rating);
            return r ? { t: r.percent + "% z " + r.total, n: r.percent } : { t: "Za mało ocen" };
        }, "max")
    ];
}

// Czy program spoza katalogu w ogóle pokazać: odsiewamy porzucone i te bez wersji na ten procesor.
// hit: wynik wyszukiwania Flathub
function worthShowing(hit, arch, strict) {
    if (strict && (!hit.verification_verified || (hit.installs_last_month || 0) < 300)) return false;
    if (!hit || hit.type && hit.type !== "desktop-application" && hit.type !== "console-application") return false;
    if (arch && hit.arches && hit.arches.indexOf(arch) < 0) return false;
    if (hit.updated_at && (Date.now() / 1000 - hit.updated_at) / DAY > 1000) return false;
    return true;
}
