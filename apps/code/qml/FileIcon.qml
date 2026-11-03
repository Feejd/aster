import QtQuick
import Aster.Ui

// Ikona pliku w drzewie, na kartach i w wynikach: znak liniowy Aster w kolorze typu pliku
// (jak ikony plików w VS Code, ale w jednym, spokojnym stylu).
Item {
    id: fi
    property string name
    property bool isDir: false
    property bool expanded: false
    property real size: 16
    width: size; height: size

    readonly property var special: ({
        "CMakeLists.txt": ["tool", "#5B8DEF"], "Makefile": ["tool", "#8A909C"], "meson.build": ["tool", "#5B8DEF"],
        "Containerfile": ["drive", "#2496ED"], "Dockerfile": ["drive", "#2496ED"],
        ".gitignore": ["gitBranch", "#F05033"], ".gitattributes": ["gitBranch", "#F05033"], ".gitmodules": ["gitBranch", "#F05033"],
        "LICENSE": ["shield", "#D4A72C"], "COPYING": ["shield", "#D4A72C"],
        "package.json": ["braces", "#7EC46D"], "Cargo.toml": ["tool", "#DEA584"]
    })
    readonly property var byExt: ({
        "c": ["code", "#6E8EF7"], "h": ["code", "#A78BFA"], "cpp": ["code", "#4C8BF5"], "cc": ["code", "#4C8BF5"], "cxx": ["code", "#4C8BF5"],
        "hpp": ["code", "#A78BFA"], "hh": ["code", "#A78BFA"], "m": ["code", "#6E8EF7"],
        "py": ["code", "#3B82C4"], "js": ["code", "#E2B714"], "mjs": ["code", "#E2B714"], "cjs": ["code", "#E2B714"],
        "ts": ["code", "#3178C6"], "tsx": ["code", "#3178C6"], "jsx": ["code", "#38BDF8"], "vue": ["code", "#41B883"], "svelte": ["code", "#FF3E00"],
        "qml": ["code", "#41CD52"], "rs": ["code", "#DEA584"], "go": ["code", "#00ADD8"], "java": ["code", "#E76F00"], "kt": ["code", "#A97BFF"],
        "cs": ["code", "#9B4F96"], "rb": ["code", "#E0115F"], "php": ["code", "#8892BF"], "swift": ["code", "#F05138"], "lua": ["code", "#4C6EF5"],
        "dart": ["code", "#0EA5E9"], "zig": ["code", "#F7A41D"], "pl": ["code", "#39457E"], "r": ["code", "#276DC3"], "sql": ["drive", "#E38C00"],
        "html": ["code", "#E44D26"], "htm": ["code", "#E44D26"], "xml": ["code", "#E37933"], "svg": ["image", "#FFB13B"],
        "css": ["hash", "#2965F1"], "scss": ["hash", "#CD6799"], "sass": ["hash", "#CD6799"], "less": ["hash", "#2965F1"],
        "sh": ["prompt", "#4EAA25"], "bash": ["prompt", "#4EAA25"], "zsh": ["prompt", "#4EAA25"], "fish": ["prompt", "#4EAA25"], "ps1": ["prompt", "#5391FE"],
        "json": ["braces", "#D4A72C"], "jsonc": ["braces", "#D4A72C"], "yaml": ["sliders", "#CB4B5A"], "yml": ["sliders", "#CB4B5A"],
        "toml": ["sliders", "#9C4221"], "ini": ["sliders", "#8A909C"], "conf": ["sliders", "#8A909C"], "cfg": ["sliders", "#8A909C"],
        "desktop": ["apps", "#8A909C"], "service": ["gear", "#8A909C"], "cmake": ["tool", "#5B8DEF"],
        "md": ["doc", "#4C8BF5"], "markdown": ["doc", "#4C8BF5"], "rst": ["doc", "#8A909C"], "txt": ["doc", "#8A909C"], "log": ["doc", "#8A909C"],
        "pdf": ["doc", "#DC2550"], "csv": ["sheet", "#1A8F4C"],
        "png": ["image", "#B23DE0"], "jpg": ["image", "#B23DE0"], "jpeg": ["image", "#B23DE0"], "gif": ["image", "#B23DE0"],
        "webp": ["image", "#B23DE0"], "ico": ["image", "#B23DE0"], "bmp": ["image", "#B23DE0"],
        "ttf": ["textSize", "#8A909C"], "otf": ["textSize", "#8A909C"], "woff": ["textSize", "#8A909C"], "woff2": ["textSize", "#8A909C"],
        "mp3": ["music", "#E2283E"], "wav": ["music", "#E2283E"], "ogg": ["music", "#E2283E"], "flac": ["music", "#E2283E"],
        "mp4": ["film", "#3A36D8"], "mkv": ["film", "#3A36D8"], "webm": ["film", "#3A36D8"],
        "zip": ["archive", "#9A6838"], "tar": ["archive", "#9A6838"], "gz": ["archive", "#9A6838"], "xz": ["archive", "#9A6838"], "zst": ["archive", "#9A6838"],
        "lock": ["lock", "#8A909C"], "plymouth": ["sliders", "#8A909C"], "js.map": ["braces", "#8A909C"]
    })
    readonly property var kind: {
        if (isDir) return ["folder", Theme.dark ? "#7FB2FF" : "#3D7BEA"];
        if (special[name]) return special[name];
        const dot = name.lastIndexOf(".");
        const ext = dot > 0 ? name.slice(dot + 1).toLowerCase() : "";
        return byExt[ext] || ["doc", Theme.text2];
    }

    Icon {
        anchors.centerIn: parent
        d: Icons[fi.kind[0]] || Icons.doc
        size: fi.size
        stroke: 1.7
        color: fi.kind[1]
        fill: fi.isDir && fi.expanded ? Qt.rgba(color.r, color.g, color.b, 0.16) : "transparent"
    }
}
