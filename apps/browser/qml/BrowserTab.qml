import QtQuick
import QtWebEngine
import Aster.Ui
import Aster.Browser

// Jedna karta: strona (WebEngineView) albo — gdy karta jest pusta — strona startowa.
// Wszystko, co interesuje okno (tytuł, ikona, postęp, prośby strony), wychodzi sygnałami i właściwościami.
Item {
    id: tab
    required property WebEngineProfile profile
    property string initialUrl
    property var favorites: []
    property var recents: []

    readonly property alias view: web
    readonly property string pageUrl: web.url.toString()
    readonly property bool blank: pageUrl === "" || pageUrl === "about:blank"
    readonly property string pageTitle: blank ? "Nowa karta" : (web.title || Urls.host(pageUrl))
    readonly property string pageIcon: blank ? "" : web.icon.toString()
    readonly property bool secure: pageUrl.indexOf("https://") === 0
    property color themeColor: "transparent"           // kolor strony (meta theme-color) — barwi pasek okna

    signal visited(string url, string title)
    signal permissionAsked(var permission)
    signal newWindow(var request)
    signal fullScreen(var request)
    signal contextMenu(var request)
    signal findResult(int active, int total)
    signal removeFavorite(string url)

    function load(url) { web.url = url; }

    // Kolor motywu strony (np. czerwony YouTube) — tylko prawidłowe zapisy kolorów
    function readThemeColor() {
        web.runJavaScript("(function(){var m=document.querySelector('meta[name=\"theme-color\"]');return m?m.content:'';})()",
                          function (c) {
                              c = (c || "").trim();
                              tab.themeColor = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(c) || /^rgba?\(/i.test(c) ? c : "transparent";
                          });
    }

    WebEngineView {
        id: web
        anchors.fill: parent
        profile: tab.profile
        visible: !tab.blank
        backgroundColor: Theme.dark ? "#1E1E22" : "white"
        url: tab.initialUrl
        settings.fullScreenSupportEnabled: true
        settings.scrollAnimatorEnabled: true
        settings.focusOnNavigationEnabled: true

        onLoadingChanged: (info) => {
            if (info.status === WebEngineView.LoadStartedStatus)
                tab.themeColor = "transparent";
            else if (info.status === WebEngineView.LoadSucceededStatus) {
                tab.readThemeColor();
                tab.visited(info.url.toString(), web.title);
            }
        }
        onPermissionRequested: (permission) => tab.permissionAsked(permission)
        onNewWindowRequested: (request) => tab.newWindow(request)
        onFullScreenRequested: (request) => tab.fullScreen(request)
        onContextMenuRequested: (request) => { request.accepted = true; tab.contextMenu(request); }
        onFindTextFinished: (result) => tab.findResult(result.activeMatch, result.numberOfMatches)
    }

    StartPage {
        anchors.fill: parent
        visible: tab.blank
        favorites: tab.favorites
        recents: tab.recents
        onOpen: (url) => tab.load(url)
        onRemove: (url) => tab.removeFavorite(url)
    }
}
