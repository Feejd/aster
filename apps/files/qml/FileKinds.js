.pragma library

// Kolor karty pliku według rozszerzenia — dokumenty niebieskie, arkusze zielone, PDF czerwone…
var groups = [
    { color: "#3B6FE0", ext: ["DOC", "DOCX", "ODT", "RTF", "PAGES"] },
    { color: "#1E9E5A", ext: ["XLS", "XLSX", "ODS", "CSV", "NUMBERS"] },
    { color: "#E8743B", ext: ["PPT", "PPTX", "ODP", "KEY"] },
    { color: "#D93B3B", ext: ["PDF"] },
    { color: "#C98A12", ext: ["ZIP", "RAR", "7Z", "TAR", "GZ", "XZ", "ZST"] },
    { color: "#D6457A", ext: ["MP3", "FLAC", "WAV", "OGG", "M4A", "OPUS"] },
    { color: "#8B5CF6", ext: ["MP4", "MKV", "MOV", "WEBM", "AVI"] },
    { color: "#0EA5A4", ext: ["SVG", "PSD", "XCF", "KRA", "HEIC", "RAW"] },
    { color: "#5B6270", ext: ["TXT", "MD", "LOG", "JSON", "XML", "INI", "SH", "PY", "JS", "CPP", "H"] }
];

function tint(ext) {
    for (var i = 0; i < groups.length; ++i)
        if (groups[i].ext.indexOf(ext) >= 0) return groups[i].color;
    return "#6B7280";
}
