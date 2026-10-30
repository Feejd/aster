import QtQuick

// Tapeta pulpitu. Warianty-krajobrazy („szczyty”, „jezioro”) to obrazy z katalogu
// wallpapers/ (renderowane przez tools/make_wallpapers.py) — osobno na dzień i noc,
// z płynnym przenikaniem przy zmianie motywu. Pozostałe warianty to fale (Waves.qml).
Item {
    id: wp
    property bool dark: false
    property string variant: "szczyty"
    property bool thumb: false              // miniatura w Ustawieniach — lżejszy plik
    readonly property bool photo: variant === "szczyty" || variant === "jezioro"

    function src(mode) {
        return Qt.resolvedUrl("wallpapers/" + wp.variant + "-" + mode + (wp.thumb ? "-thumb" : "") + ".jpg");
    }

    Waves {
        anchors.fill: parent
        visible: !wp.photo
        dark: wp.dark
        variant: wp.photo ? "swit" : wp.variant
    }

    Image {
        anchors.fill: parent
        visible: wp.photo
        source: wp.photo ? wp.src("light") : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: !wp.thumb
        smooth: true; mipmap: true
    }
    Image {
        anchors.fill: parent
        visible: wp.photo && opacity > 0
        source: wp.photo ? wp.src("dark") : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: !wp.thumb
        smooth: true; mipmap: true
        opacity: wp.dark ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    }
}
