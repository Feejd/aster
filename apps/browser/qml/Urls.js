.pragma library

// Drobne pomocniki do adresów (reszta — wyszukiwarka, rozpoznawanie adresu — jest w Browser)

// „pl.wikipedia.org” z pełnego adresu (bez www.)
function host(url) {
    var m = /^[a-z-]+:\/\/([^/:?#]+)/i.exec(url || "");
    return m ? m[1].replace(/^www\./, "") : (url || "");
}

// Adres bez „https://www.” i końcowego ukośnika — do podpowiedzi i list
function pretty(url) {
    return (url || "").replace(/^https?:\/\/(www\.)?/i, "").replace(/\/$/, "");
}

// Ikona witryny z publicznej usługi (gdy strona nie jest otwarta) — zawsze PNG
function favicon(url) {
    var h = host(url);
    return h && /^https?:/i.test(url) ? "https://www.google.com/s2/favicons?sz=64&domain=" + h : "";
}

// Strony wewnętrzne przeglądarki: aster://history, aster://downloads, aster://settings
var pages = {
    "history": "Historia",
    "downloads": "Pobrane",
    "settings": "Ustawienia"
};
function internal(url) {
    var m = /^aster:(\/\/)?([a-z]+)/i.exec(url || "");
    return m && pages[m[2].toLowerCase()] ? m[2].toLowerCase() : "";
}

// 1536000 → „1,5 MB”
function size(bytes) {
    if (!(bytes > 0)) return "";
    var units = ["B", "KB", "MB", "GB", "TB"], i = 0;
    while (bytes >= 1024 && i < units.length - 1) { bytes /= 1024; ++i; }
    return (i === 0 ? bytes : bytes.toFixed(bytes < 10 ? 1 : 0)).toString().replace(".", ",") + " " + units[i];
}

// Pozostały czas pobierania: „jeszcze 2 min”
function remaining(left, speed) {
    if (!(speed > 0) || !(left > 0)) return "";
    var s = Math.round(left / speed);
    if (s < 60) return "jeszcze " + s + " s";
    if (s < 3600) return "jeszcze " + Math.round(s / 60) + " min";
    return "jeszcze " + Math.floor(s / 3600) + " godz. " + Math.round((s % 3600) / 60) + " min";
}

// Nagłówek dnia w historii: „Dzisiaj”, „Wczoraj”, „wtorek, 28 października”
function dayLabel(time, locale) {
    var d = new Date(time), now = new Date();
    var start = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    if (time >= start) return "Dzisiaj";
    if (time >= start - 86400000) return "Wczoraj";
    return d.toLocaleDateString(locale, d.getFullYear() === now.getFullYear() ? "dddd, d MMMM" : "d MMMM yyyy");
}
function dayKey(time) {
    var d = new Date(time);
    return d.getFullYear() * 10000 + d.getMonth() * 100 + d.getDate();
}
