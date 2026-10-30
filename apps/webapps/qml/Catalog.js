.pragma library

// Polecane aplikacje webowe: adres, kolor paska i kategoria w Starcie.
// Ikony i resztę danych instalator i tak pobiera ze strony (manifest), tu tylko to, co warto wymusić.
var apps = [
    { name: "WhatsApp", url: "https://web.whatsapp.com/", color: "#00A884", category: "internet", desc: "Czaty i rozmowy" },
    { name: "Messenger", url: "https://www.messenger.com/", color: "#0866FF", category: "internet", desc: "Wiadomości z Facebooka" },
    { name: "Gmail", url: "https://mail.google.com/", color: "", category: "internet", desc: "Poczta Google" },
    { name: "Outlook", url: "https://outlook.live.com/mail/", color: "#0F6CBD", category: "internet", desc: "Poczta Microsoft" },
    { name: "Teams", url: "https://teams.microsoft.com/", color: "#5B5FC7", category: "internet", desc: "Spotkania i czaty w pracy" },
    { name: "Discord", url: "https://discord.com/app", color: "#313338", category: "internet", desc: "Społeczności i rozmowy głosowe" },
    { name: "Slack", url: "https://app.slack.com/client", color: "#4A154B", category: "internet", desc: "Komunikator do pracy" },
    { name: "Kalendarz Google", url: "https://calendar.google.com/", color: "", category: "biuro", desc: "Terminy i spotkania" },
    { name: "Dokumenty Google", url: "https://docs.google.com/document/", color: "", category: "biuro", desc: "Edytor tekstu w chmurze" },
    { name: "Arkusze Google", url: "https://docs.google.com/spreadsheets/", color: "", category: "biuro", desc: "Arkusze kalkulacyjne" },
    { name: "Microsoft 365", url: "https://www.office.com/", color: "", category: "biuro", desc: "Word, Excel i PowerPoint" },
    { name: "Notion", url: "https://www.notion.so/", color: "", category: "biuro", desc: "Notatki i projekty" },
    { name: "Trello", url: "https://trello.com/", color: "#0C66E4", category: "biuro", desc: "Tablice z zadaniami" },
    { name: "Spotify", url: "https://open.spotify.com/", color: "#121212", category: "multimedia", desc: "Muzyka i podcasty" },
    { name: "YouTube", url: "https://www.youtube.com/", color: "", category: "multimedia", desc: "Filmy" },
    { name: "YouTube Music", url: "https://music.youtube.com/", color: "#030303", category: "multimedia", desc: "Muzyka z YouTube" },
    { name: "ChatGPT", url: "https://chatgpt.com/", color: "", category: "narzedzia", desc: "Asystent AI" },
    { name: "Claude", url: "https://claude.ai/", color: "", category: "narzedzia", desc: "Asystent AI od Anthropic" },
    { name: "Canva", url: "https://www.canva.com/", color: "", category: "grafika", desc: "Grafiki, plakaty, prezentacje" },
    { name: "Figma", url: "https://www.figma.com/", color: "#2C2C2C", category: "grafika", desc: "Projektowanie interfejsów" },
    { name: "Instagram", url: "https://www.instagram.com/", color: "", category: "internet", desc: "Zdjęcia i relacje" },
    { name: "Facebook", url: "https://www.facebook.com/", color: "#0866FF", category: "internet", desc: "Znajomi i grupy" },
    { name: "LinkedIn", url: "https://www.linkedin.com/", color: "", category: "internet", desc: "Sieć zawodowa" },
    { name: "Allegro", url: "https://allegro.pl/", color: "#FF5A00", category: "internet", desc: "Zakupy" }
];

var categories = [
    { id: "internet", name: "Internet" },
    { id: "biuro", name: "Biuro" },
    { id: "multimedia", name: "Multimedia" },
    { id: "grafika", name: "Grafika" },
    { id: "narzedzia", name: "Narzędzia" },
    { id: "edukacja", name: "Edukacja" },
    { id: "gry", name: "Gry" }
];

function host(url) {
    var m = /^[a-z]+:\/\/([^/:?#]+)/i.exec(url || "");
    return m ? m[1] : "";
}

// Ikona do kafelka w katalogu (z domeny głównej: web.whatsapp.com → whatsapp.com)
function preview(url) {
    var h = host(url).replace(/^(web|app|open|music|mail|teams)\./, "");
    if (h.indexOf("docs.google.com") >= 0 || h.indexOf("calendar.google.com") >= 0) h = host(url);
    return "https://www.google.com/s2/favicons?sz=128&domain=" + h;
}
