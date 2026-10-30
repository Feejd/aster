.pragma library

// Natywne nakładki dla popularnych aplikacji. Zamiast zgadywać z wyglądu strony,
// opisujemy aplikację tak, jakby jej twórca zrobił wersję na Astera:
//   nav      — pasek boczny Aster: sekcje i pozycje (adresy w serwisie; aktywna = pasujący adres)
//   search   — wyszukiwarka w pasku tytułu: adres wyników i podpowiedzi
//   css      — co schować na stronie (jej własne menu i nagłówek) i jak ją dopasować (tło = szkło okna)
//   dark     — skrypt włączający ciemny motyw strony, gdy system jest ciemny
//   avatar   — gdzie na stronie jest zdjęcie konta (pokazujemy je w rogu okna), accountClick — co kliknąć
//   title    — jak z adresu i tytułu strony zrobić tytuł okna

var youtube = {
    id: "youtube",
    hosts: ["www.youtube.com", "youtube.com", "m.youtube.com"],
    accent: "#FF0033",
    glass: true,
    home: "https://www.youtube.com/",
    nav: [
        { items: [
            { label: "Główna", icon: "home", url: "/", match: "^/$" },
            { label: "Shorts", icon: "shorts", url: "/shorts", match: "^/shorts" },
            { label: "Subskrypcje", icon: "subs", url: "/feed/subscriptions", match: "^/feed/subscriptions" }
        ] },
        { section: "Ty", items: [
            { label: "Historia", icon: "clock", url: "/feed/history", match: "^/feed/history" },
            { label: "Playlisty", icon: "playlist", url: "/feed/playlists", match: "^/feed/playlists" },
            { label: "Do obejrzenia", icon: "clock", url: "/playlist?list=WL", match: "list=WL" },
            { label: "Polubione", icon: "thumb", url: "/playlist?list=LL", match: "list=LL" }
        ] },
        { section: "Odkrywaj", items: [
            { label: "Muzyka", icon: "music", url: "/channel/UC-9-kyTW8ZkZNDHQJ6FgpwQ", match: "UC-9-kyTW8ZkZNDHQJ6FgpwQ" },
            { label: "Gry", icon: "game", url: "/gaming", match: "^/gaming" },
            { label: "Wiadomości", icon: "news", url: "/channel/UCYfdidRxbB8Qhf0Nx7ioOYw", match: "UCYfdidRxbB8Qhf0Nx7ioOYw" },
            { label: "Sport", icon: "trophy", url: "/channel/UCEgdi0XIXXZ-qJOFPf4JSKw", match: "UCEgdi0XIXXZ-qJOFPf4JSKw" }
        ] }
    ],
    search: {
        placeholder: "Szukaj w YouTube",
        url: "https://www.youtube.com/results?search_query=%s",
        suggest: "https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&hl=pl&q=%s"
    },
    avatar: "#avatar-btn img, ytd-topbar-menu-button-renderer img#img",
    accountClick: "#avatar-btn, ytd-topbar-menu-button-renderer button",
    signIn: "/signin",
    css:
        // Własny nagłówek i menu YouTube znikają — zastępuje je okno Aster
        "#masthead-container,ytd-mini-guide-renderer,tp-yt-app-drawer#guide,#guide{display:none!important}" +
        "ytd-app{--ytd-masthead-height:0px!important;--ytd-toolbar-height:0px!important}" +
        "ytd-app[guide-persistent-and-visible] ytd-page-manager,ytd-app[mini-guide-visible] ytd-page-manager{margin-left:0!important}" +
        "ytd-page-manager{margin-top:0!important}" +
        "#frosted-glass,#background.ytd-masthead{display:none!important}" +
        "#chips-wrapper.ytd-feed-filter-chip-bar-renderer,ytd-feed-filter-chip-bar-renderer{top:0!important;background:transparent!important}" +
        // Tło strony = szkło okna; karty i odtwarzacz z miękkimi zaokrągleniami
        "html,body,ytd-app,#content.ytd-app,ytd-page-manager,ytd-browse,ytd-two-column-browse-results-renderer,ytd-rich-grid-renderer," +
        "ytd-watch-flexy,ytd-search,#columns,#primary,#secondary,ytd-section-list-renderer,ytd-shorts{background:transparent!important}" +
        "#movie_player,.html5-video-player{border-radius:16px!important;overflow:hidden!important}" +
        "ytd-thumbnail,yt-thumbnail-view-model,yt-image img{border-radius:14px!important}" +
        "ytd-rich-grid-renderer{--ytd-rich-grid-item-margin:20px!important}" +
        "#primary.ytd-two-column-browse-results-renderer{padding-top:8px!important}",
    dark: "document.documentElement.toggleAttribute('dark', %d);",
    title: function (url, pageTitle) {
        var path = url.replace(/^https?:\/\/[^/]+/, "");
        if (/^\/watch/.test(path)) return pageTitle.replace(/\s*-\s*YouTube$/, "").replace(/^\(\d+\)\s*/, "");
        if (/^\/results/.test(path)) {
            var q = /search_query=([^&]*)/.exec(path);
            return q ? "Wyniki: " + decodeURIComponent(q[1].replace(/\+/g, " ")) : "Wyniki";
        }
        if (/^\/(@|channel\/|c\/)/.test(path)) return pageTitle.replace(/\s*-\s*YouTube$/, "").replace(/^\(\d+\)\s*/, "");
        return "";
    }
};

var all = [youtube];

function find(host) {
    host = (host || "").toLowerCase();
    for (var i = 0; i < all.length; ++i)
        if (all[i].hosts.indexOf(host) >= 0) return all[i];
    return null;
}

// Aktywna pozycja paska bocznego dla bieżącego adresu
function activeUrl(adapter, url) {
    var path = url.replace(/^https?:\/\/[^/]+/, "");
    var hit = "";
    adapter.nav.forEach(function (s) {
        s.items.forEach(function (it) { if (!hit && new RegExp(it.match).test(path)) hit = it.url; });
    });
    return hit;
}

function titleFor(adapter, url) {
    var path = url.replace(/^https?:\/\/[^/]+/, "");
    var label = "";
    adapter.nav.forEach(function (s) {
        s.items.forEach(function (it) { if (!label && new RegExp(it.match).test(path)) label = it.label; });
    });
    return label;
}
