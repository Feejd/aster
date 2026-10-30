.pragma library

// Redakcja sklepu: polecane na górze, odpowiedniki programów z Windowsa, kategorie.

// Duże polecenie na stronie „Odkrywaj” (zmienia się codziennie)
var heroes = [
    { id: "com.spotify.Client", tag: "WYBÓR REDAKCJI", title: "Cała muzyka świata", colors: ["#1ED760", "#0A4D25"] },
    { id: "com.valvesoftware.Steam", tag: "GRY", title: "Tysiące gier — także z Windowsa", colors: ["#2A475E", "#0E1A26"] },
    { id: "com.obsproject.Studio", tag: "TWÓRZ", title: "Nagrywaj ekran i nadawaj na żywo", colors: ["#6E6BFF", "#21203A"] },
    { id: "org.kde.krita", tag: "TWÓRZ", title: "Maluj jak na płótnie", colors: ["#F1588F", "#5B1E52"] },
    { id: "org.libreoffice.LibreOffice", tag: "PRACA", title: "Dokumenty bez abonamentu", colors: ["#2FA3E0", "#16416B"] },
    { id: "com.discordapp.Discord", tag: "ROZMOWY", title: "Twoje serwery i znajomi", colors: ["#7984FF", "#2E2F8A"] }
];

// „Przesiadasz się z Windowsa?” — czym zastąpić znane programy
var switchers = [
    { id: "org.onlyoffice.desktopeditors", instead: "Word, Excel i PowerPoint" },
    { id: "org.libreoffice.LibreOffice", instead: "Microsoft Office" },
    { id: "org.gimp.GIMP", instead: "Photoshopa" },
    { id: "org.videolan.VLC", instead: "Windows Media Playera" },
    { id: "com.usebottles.bottles", instead: "programów .exe z Windowsa" },
    { id: "org.kde.kdenlive", instead: "Premiere i Clipchampa" },
    { id: "org.mozilla.Thunderbird", instead: "Outlooka" },
    { id: "org.kde.okular", instead: "Adobe Readera" }
];

var categories = [
    { id: "discover", name: "Odkrywaj", icon: "sparkle" },
    { id: "Office", name: "Praca i biuro", icon: "doc" },
    { id: "Graphics", name: "Grafika i zdjęcia", icon: "image" },
    { id: "AudioVideo", name: "Muzyka i wideo", icon: "music" },
    { id: "Game", name: "Gry", icon: "game" },
    { id: "Network", name: "Internet i rozmowy", icon: "globe" },
    { id: "Education", name: "Nauka", icon: "book" },
    { id: "Development", name: "Programowanie", icon: "code" },
    { id: "Utility", name: "Narzędzia", icon: "tool" },
    { id: "System", name: "System", icon: "sliders" }
];

function heroOfTheDay() {
    var day = Math.floor(Date.now() / 86400000);
    return heroes[day % heroes.length];
}

// „3,9 mln”, „245 tys.”
function count(n) {
    if (!n) return "—";
    if (n >= 1000000) return (n / 1000000).toFixed(1).replace(".", ",") + " mln";
    if (n >= 1000) return Math.round(n / 1000) + " tys.";
    return String(n);
}

function size(bytes) {
    if (!bytes) return "—";
    if (bytes >= 1e9) return (bytes / 1e9).toFixed(1).replace(".", ",") + " GB";
    return Math.round(bytes / 1e6) + " MB";
}

// Krótki opis z listy Flathub
function short(h) {
    return { id: h.app_id || h.id, name: h.name, summary: h.summary || "", icon: h.icon || "",
             dev: h.developer_name || "", installs: h.installs_last_month || 0 };
}
