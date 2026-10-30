.pragma library

// Zamiana tego, co wpisano w pasek adresu, na adres strony albo wyszukiwanie
var searchUrl = "https://www.google.com/search?q=";

function fixup(text) {
    var t = text.trim();
    if (!t) return "";
    if (/^[a-z][a-z0-9+.-]*:/i.test(t) && !/^localhost:\d/.test(t)) return t;        // ma schemat (https:, file:, about:)
    var looksLikeHost = /^[^\s]+\.[a-z]{2,}([:/?#].*)?$/i.test(t) || /^localhost(:\d+)?(\/.*)?$/.test(t)
                        || /^\d{1,3}(\.\d{1,3}){3}(:\d+)?(\/.*)?$/.test(t);
    if (looksLikeHost && t.indexOf(" ") < 0) return "https://" + t;
    return searchUrl + encodeURIComponent(t);
}

// „pl.wikipedia.org” z pełnego adresu (bez www.)
function host(url) {
    var m = /^[a-z]+:\/\/([^/:?#]+)/i.exec(url || "");
    return m ? m[1].replace(/^www\./, "") : (url || "");
}

function isSearch(url) {
    return (url || "").indexOf(searchUrl) === 0;
}

function searchQuery(url) {
    if (!isSearch(url)) return "";
    var q = url.slice(searchUrl.length).split("&")[0];
    try { return decodeURIComponent(q.replace(/\+/g, " ")); } catch (e) { return q; }
}

// Ikona strony z publicznej usługi (gdy strona jeszcze się nie wczytała)
function favicon(url) {
    var h = host(url);
    return h ? "https://icons.duckduckgo.com/ip3/" + h + ".ico" : "";
}
